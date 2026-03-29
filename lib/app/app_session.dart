import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/discovered_peer.dart';
import '../services/lan_broadcast.dart';
import '../services/settings_store.dart';
import '../src/rust/api/config.dart';
import '../src/rust/api/peer.dart';
import '../src/rust/api/remote_host.dart';
import '../src/rust/api/transfer.dart';
import '../src/rust/api/types.dart';

/// 应用会话：持久化、Bonsoir、Rust 文件服务、接收轮询。
class AppSession extends ChangeNotifier {
  AppSession({
    this.dryRunForTest = false,
    this.skipWindowsFirewallPrompt = false,
    SettingsStore? settings,
  }) : _settings = settings ?? SettingsStore();

  /// 编译期指定，用于同机多开时使用不同的 Rust 设备 ID 缓存，避免 Bonsoir 互判为同一台设备。
  /// 运行示例：`flutter run -d windows --dart-define=XTRANSFER_INSTANCE=2`
  static const String instanceTag = String.fromEnvironment(
    'XTRANSFER_INSTANCE',
    defaultValue: '',
  );

  /// 为单元测试跳过网络与文件监听。
  final bool dryRunForTest;

  /// 集成测试等场景跳过 Windows 防火墙引导（仍会尝试后台检测规则）。
  final bool skipWindowsFirewallPrompt;
  final SettingsStore _settings;

  String nickname = '';
  List<String> tags = [];
  String? receivePath;

  /// 与 [SettingsStore.remoteDesktopHostEnabled] 同步：是否在启动本应用时开启远程协助（被控）。
  bool remoteDesktopHostEnabled = false;

  /// 局域网远程协助会话令牌（控制端与被控端一致即可，无需用户输入）。
  static const String kLanRemoteSessionToken = 'xtransfer-lan';

  int? fileListenPort;
  int remoteDesktopAdvertisedPort = 0;

  String? localDeviceId;
  String? lastError;

  /// 局域网 UDP 广播发现（端口 45678）是否已成功绑定；`false` 多为同机多开端口占用。
  bool lanBroadcastActive = false;

  final Map<String, DiscoveredPeer> peersById = {};
  final List<FileReceiveEventDto> receiveLog = [];
  final List<TransferProgressDto> transferLog = [];

  /// 最近一次由局域网 UDP 收到该 peer 的时间；用于忽略 Windows mDNS 误报的 ServiceLost。
  final Map<String, DateTime> _lastLanRefreshByPeerId = {};

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discSub;
  Timer? _pollTimer;
  LanBroadcastController? _lanBc;

  static const _serviceType = '_localdesk._udp';

  /// 超过此时长未收到任何发现刷新（UDP 或 mDNS）则从列表移除，避免对端已关仍占位。
  static const Duration _peerStaleTtl = Duration(seconds: 10);

  bool get discoverySupported {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    };
  }

  Future<void> bootstrap() async {
    if (dryRunForTest) {
      nickname = '测试用户';
      tags = ['会场1', 'A片区'];
      notifyListeners();
      return;
    }

    lastError = null;
    nickname = await _settings.nickname;
    tags = await _settings.tags;
    receivePath = await _settings.receivePath;
    remoteDesktopHostEnabled = await _settings.remoteDesktopHostEnabled;
    notifyListeners();

    try {
      final support = await getApplicationSupportDirectory();
      final cacheRoot = instanceTag.isEmpty
          ? support.path
          : p.join(support.path, 'instance_$instanceTag');
      setRustCacheDir(path: cacheRoot);
    } catch (e) {
      _setErr('缓存目录: $e');
    }

    try {
      localDeviceId = deviceId();
    } catch (e) {
      _setErr('deviceId: ${_fmtErr(e)}');
    }

    await _syncRustProfileAndReceiveDir();
    await _startFileServiceAndDiscovery();
    _scheduleDeferredLanRefresh();
    if (remoteDesktopHostEnabled) {
      try {
        await startRemoteHost(token: kLanRemoteSessionToken);
      } catch (e) {
        _setErr('远程协助启动失败: ${_fmtErr(e)}');
      }
    }

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 600),
      (_) => _pollRustInbound(),
    );

    notifyListeners();
  }

  Future<void> reloadAfterSettingsSave() async {
    if (dryRunForTest) return;
    nickname = await _settings.nickname;
    tags = await _settings.tags;
    receivePath = await _settings.receivePath;
    remoteDesktopHostEnabled = await _settings.remoteDesktopHostEnabled;
    await _syncRustProfileAndReceiveDir();
    // 先 UDP 广播：避免 Bonsoir 抛错时从未执行 _restartLanBroadcast（表现为完全不发 45678）。
    await _restartLanBroadcast();
    try {
      await _restartBonsoirBroadcast();
      await _restartBonsoirDiscovery();
    } catch (e) {
      _setErr('Bonsoir 刷新失败（UDP 发现仍可用）: ${_fmtErr(e)}');
    }
    if (remoteDesktopHostEnabled) {
      try {
        await _ensureRemoteHostRunning();
      } catch (e) {
        _setErr('远程协助启动失败: ${_fmtErr(e)}');
      }
    } else {
      try {
        await stopRemoteHost();
      } catch (_) {}
    }
    notifyListeners();
  }

  /// 先开应用的一方常在 Wi‑Fi 尚未拿到私网 IP 时就绑定，易落到 0.0.0.0 且长期 send=0；数秒后重绑一次。
  void _scheduleDeferredLanRefresh() {
    if (dryRunForTest || !discoverySupported) return;
    unawaited(
      Future<void>.delayed(const Duration(seconds: 5), () async {
        if (dryRunForTest) return;
        if (fileListenPort == null || localDeviceId == null) return;
        await _restartLanBroadcast();
        notifyListeners();
      }),
    );
  }

  Future<void> _syncRustProfileAndReceiveDir() async {
    try {
      setLocalProfile(
        profile: LocalProfileDto(nickname: nickname, tags: tags),
      );
    } catch (e) {
      _setErr('Rust 身份: ${_fmtErr(e)}');
    }
    if (receivePath != null && receivePath!.isNotEmpty) {
      try {
        setDefaultReceivePath(path: receivePath!);
      } catch (e) {
        _setErr('接收目录无效: ${_fmtErr(e)}');
      }
    }
  }

  Future<void> _startFileServiceAndDiscovery() async {
    try {
      await fileServiceStop();
    } catch (_) {}
    try {
      fileListenPort = await fileServiceStart(preferredPort: null);
    } catch (e) {
      _setErr('启动文件监听: ${_fmtErr(e)}');
      return;
    }

    if (discoverySupported) {
      await _restartLanBroadcast();
      try {
        await _startBonsoir();
      } catch (e) {
        _setErr('Bonsoir 启动失败（UDP 广播发现仍可用）: ${_fmtErr(e)}');
      }
    }
  }

  Future<void> _restartBonsoirBroadcast() async {
    if (!discoverySupported || fileListenPort == null) return;
    await _broadcast?.stop();
    _broadcast = null;
    await _startBroadcastOnly();
  }

  Future<void> _restartBonsoirDiscovery() async {
    if (!discoverySupported || dryRunForTest) return;
    await _discovery?.stop();
    await _discSub?.cancel();
    _discSub = null;
    _discovery = null;
    final discovery = BonsoirDiscovery(type: _serviceType);
    await discovery.initialize();
    _discSub = discovery.eventStream?.listen(_onDiscoveryEvent);
    await discovery.start();
    _discovery = discovery;
  }

  Future<void> _startBonsoir() async {
    await _broadcast?.stop();
    _broadcast = null;
    await _discovery?.stop();
    await _discSub?.cancel();
    _discSub = null;
    _discovery = null;

    await _startBroadcastOnly();

    final discovery = BonsoirDiscovery(type: _serviceType);
    await discovery.initialize();
    _discSub = discovery.eventStream?.listen(_onDiscoveryEvent);
    await discovery.start();
    _discovery = discovery;
  }

  Future<void> _startBroadcastOnly() async {
    if (fileListenPort == null || localDeviceId == null) return;
    String inst;
    try {
      inst = sessionId();
    } catch (_) {
      inst = 'na';
    }
    final service = BonsoirService(
      name: nickname.isEmpty ? '内网传输用户' : nickname,
      type: _serviceType,
      port: fileListenPort!,
      attributes: {
        ...BonsoirService.defaultAttributes,
        'did': localDeviceId!,
        'inst': inst,
        'nick': nickname,
        'tags': tags.join('|||'),
        'fport': '${fileListenPort!}',
        'rport': '$remoteDesktopAdvertisedPort',
      },
    );
    final b = BonsoirBroadcast(service: service);
    await b.initialize();
    await b.start();
    _broadcast = b;
  }

  Future<void> _restartLanBroadcast() async {
    if (!discoverySupported || dryRunForTest) {
      lanBroadcastActive = false;
      return;
    }
    _lanBc?.dispose();
    _lanBc = null;
    lanBroadcastActive = false;
    if (fileListenPort == null || localDeviceId == null) {
      notifyListeners();
      return;
    }

    Future<bool> bindOnce(LanBroadcastController c) => c.start(
      onPeer: (p) {
        _lastLanRefreshByPeerId[p.peerId] = DateTime.now();
        peersById[p.peerId] = p.copyWith(lastSeen: DateTime.now());
        _registerInRust(peersById[p.peerId]!);
        notifyListeners();
      },
      payloadBuilder: () {
        var inst = 'na';
        try {
          inst = sessionId();
        } catch (_) {}
        return {
          'did': localDeviceId!,
          'inst': inst,
          'nick': nickname,
          'tags': tags.join('|||'),
          'fport': fileListenPort!,
          'rport': remoteDesktopAdvertisedPort,
        };
      },
      isSelf: (did) => did == localDeviceId,
    );

    var c = LanBroadcastController();
    var ok = await bindOnce(c);
    if (!ok) {
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      c = LanBroadcastController();
      ok = await bindOnce(c);
    }
    if (ok) {
      _lanBc = c;
      lanBroadcastActive = true;
    } else {
      c.dispose();
      lanBroadcastActive = false;
      _setErr(
        '无法在端口 ${LanBroadcastController.kPort} 绑定 UDP（可能被本机其它程序占用，或权限不足）。'
        '请关闭 python listen / 第二实例后再试。',
      );
    }
    notifyListeners();
  }

  void _onDiscoveryEvent(BonsoirDiscoveryEvent event) {
    if (event is BonsoirDiscoveryServiceResolvedEvent) {
      _upsertFromBonsoir(event.service);
    } else if (event is BonsoirDiscoveryServiceUpdatedEvent) {
      _upsertFromBonsoir(event.service);
    } else if (event is BonsoirDiscoveryServiceLostEvent) {
      _removeFromBonsoir(event.service);
    }
  }

  void _upsertFromBonsoir(BonsoirService s) {
    final p = DiscoveredPeer.tryParse(s);
    if (p == null) return;
    if (p.peerId == localDeviceId) return;
    peersById[p.peerId] = p.copyWith(lastSeen: DateTime.now());
    _registerInRust(peersById[p.peerId]!);
    notifyListeners();
  }

  void _removeFromBonsoir(BonsoirService s) {
    final id = s.attributes['did'];
    if (id == null || id.isEmpty) return;
    // Windows 上 mDNS 常误报 ServiceLost；若该 peer 仍被局域网 UDP 周期性刷新，勿从列表移除。
    final lanAt = _lastLanRefreshByPeerId[id];
    // 过宽会挡住「对端已关」时的首次 ServiceLost（之后往往不再触发），列表永远不缩。
    if (lanAt != null &&
        DateTime.now().difference(lanAt) < const Duration(seconds: 8)) {
      return;
    }
    peersById.remove(id);
    _lastLanRefreshByPeerId.remove(id);
    try {
      unregisterPeer(peerId: id);
    } catch (_) {}
    notifyListeners();
  }

  void _registerInRust(DiscoveredPeer p) {
    try {
      registerDiscoveredPeer(
        peer: PeerInfoDto(
          peerId: p.peerId,
          instanceId: p.instanceId,
          nickname: p.nickname,
          tags: p.tags,
          host: p.host,
          fileServicePort: p.fileServicePort,
          remoteDesktopPort: p.remoteDesktopPort,
        ),
      );
    } catch (e) {
      _setErr('register_peer: ${_fmtErr(e)}');
    }
  }

  Future<void> _ensureRemoteHostRunning() async {
    try {
      await startRemoteHost(token: kLanRemoteSessionToken);
    } catch (e) {
      final msg = _fmtErr(e);
      if (msg.contains('HOST_RUNNING') || msg.contains('已在运行')) {
        return;
      }
      rethrow;
    }
  }

  void _pollRustInbound() {
    if (dryRunForTest) return;
    try {
      final batch = pullFileReceiveEvents();
      if (batch.isNotEmpty) {
        receiveLog.addAll(batch);
        notifyListeners();
      }
    } catch (e) {
      _setErr('pull 接收: ${_fmtErr(e)}');
    }
    try {
      final tp = pullTransferProgress();
      if (tp.isNotEmpty) {
        for (final t in tp) {
          final i = transferLog.indexWhere((e) => e.transferId == t.transferId);
          if (i >= 0) {
            transferLog[i] = t;
          } else {
            transferLog.add(t);
          }
        }
        const maxEntries = 40;
        while (transferLog.length > maxEntries) {
          transferLog.removeAt(0);
        }
        notifyListeners();
      }
    } catch (e) {
      _setErr('pull 传输进度: ${_fmtErr(e)}');
    }
    _evictStalePeers();
  }

  void _evictStalePeers() {
    if (dryRunForTest || peersById.isEmpty) return;
    final now = DateTime.now();
    final toRemove = <String>[];
    for (final e in peersById.entries) {
      if (now.difference(e.value.lastSeen) > _peerStaleTtl) {
        toRemove.add(e.key);
      }
    }
    if (toRemove.isEmpty) return;
    for (final id in toRemove) {
      peersById.remove(id);
      _lastLanRefreshByPeerId.remove(id);
      try {
        unregisterPeer(peerId: id);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> sendToPeer({
    required List<String> filePaths,
    required String peerId,
    required String message,
  }) async {
    lastError = null;
    try {
      await sendFiles(
        req: SendFilesRequestDto(
          targetPeerId: peerId,
          filePaths: filePaths,
          message: message,
        ),
      );
    } catch (e) {
      _setErr('发送失败: ${_fmtErr(e)}');
      rethrow;
    }
    notifyListeners();
  }

  void clearReceiveLog() {
    receiveLog.clear();
    notifyListeners();
  }

  void clearTransferLog() {
    transferLog.clear();
    notifyListeners();
  }

  void clearLastError() {
    lastError = null;
    notifyListeners();
  }

  /// 启动远控宿主（占位端口）；成功后可更新 `remoteDesktopAdvertisedPort` 并刷新广播。
  Future<void> startRemoteHost({required String token}) async {
    final port = await remoteHostStart(
      sessionToken: token,
      preferredPort: null,
    );
    remoteDesktopAdvertisedPort = port;
    await _restartBonsoirBroadcast();
    await _restartLanBroadcast();
    notifyListeners();
  }

  Future<void> stopRemoteHost() async {
    await remoteHostStop();
    remoteDesktopAdvertisedPort = 0;
    await _restartBonsoirBroadcast();
    await _restartLanBroadcast();
    notifyListeners();
  }

  void _setErr(String m) {
    lastError = m;
    debugPrint('[AppSession] $m');
  }

  String _fmtErr(Object e) {
    if (e is FrbException) return e.toString();
    return e.toString();
  }

  static List<String> pathsFromDropDetails(DropDoneDetails d) {
    final out = <String>[];
    for (final f in d.files) {
      final p = f.path;
      if (p.isNotEmpty) out.add(p);
    }
    return out;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _discSub?.cancel();
    _lanBc?.dispose();
    _lanBc = null;
    unawaited(_broadcast?.stop() ?? Future.value());
    unawaited(_discovery?.stop() ?? Future.value());
    if (!dryRunForTest) {
      unawaited(fileServiceStop());
      unawaited(remoteHostStop());
    }
    super.dispose();
  }
}
