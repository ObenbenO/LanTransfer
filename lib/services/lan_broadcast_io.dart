import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/discovered_peer.dart';

/// 局域网 UDP 广播发现（与 Bonsoir 并行，不依赖 mDNS）。
///
/// 固定端口 [kPort]；Windows 首次监听时常会弹出防火墙提示，用户点「允许」即可。
///
/// 在同时存在 **Hyper-V / WSL 虚网（172.17.x）与真实局域网（192.168.x）** 时，
/// 绑定 `0.0.0.0` 后向广播地址 `send` 可能出现 **写出 0 字节**（不报异常），
/// 对端完全收不到。故优先绑定到 **192.168.x.x / 10.x** 等私网地址，再回退 `anyIPv4`。
class LanBroadcastController {
  static const int kPort = 45678;
  static const String kMagic = 'XTR1';
  static const int kMaxPacket = 4096;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _sub;
  Timer? _timer;
  int _announceTicks = 0;
  DateTime? _lastSelfIgnoreLogAt;

  /// 含全局广播与各 IPv4 子网的 x.y.z.255（假定 /24，覆盖常见家用路由）。
  List<InternetAddress> _broadcastTargets = [
    InternetAddress('255.255.255.255'),
  ];

  Map<String, dynamic> Function()? _payloadBuilder;
  bool Function(String did)? _isSelf;
  void Function(DiscoveredPeer peer)? _onPeer;
  void Function(String message)? _onTransportWarning;
  int _allSendFailStreak = 0;
  int _zeroSendRounds = 0;
  bool _recoverInProgress = false;

  Future<bool> start({
    required void Function(DiscoveredPeer peer) onPeer,
    required Map<String, dynamic> Function() payloadBuilder,
    required bool Function(String did) isSelf,
    void Function(String message)? onTransportWarning,
  }) async {
    _onPeer = onPeer;
    _payloadBuilder = payloadBuilder;
    _isSelf = isSelf;
    _onTransportWarning = onTransportWarning;
    _allSendFailStreak = 0;
    _zeroSendRounds = 0;
    _recoverInProgress = false;
    final opened = await _tryOpenSocket();
    if (opened == null) {
      return false;
    }
    _socket = opened;
    _socket!.broadcastEnabled = true;
    await _refreshBroadcastTargets();
    _sub = _socket!.listen(_onSocketEvent);
    // 略快于 2s + 每目标连发 2 次，减轻 Wi‑Fi 偶发丢包、双机启动错开半拍时的「只见单边」。
    _timer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      _announceTicks++;
      if (_announceTicks % 12 == 0) {
        unawaited(_refreshBroadcastTargets());
      }
      _announce();
    });
    _announce();
    return true;
  }

  static bool _isPrivateIpv4(InternetAddress a) {
    final r = a.rawAddress;
    if (r.length != 4) return false;
    if (r[0] == 10) return true;
    if (r[0] == 172 && r[1] >= 16 && r[1] <= 31) return true;
    if (r[0] == 192 && r[1] == 168) return true;
    return false;
  }

  /// 越小越优先；172.17（Docker/WSL 常见）最后尝试，减轻「send 写出 0 字节」问题。
  static int _bindPreference(InternetAddress a) {
    final r = a.rawAddress;
    if (r.length != 4) return 999;
    if (r[0] == 192 && r[1] == 168) return 0;
    if (r[0] == 10) return 1;
    if (r[0] == 172 && r[1] == 17) return 90;
    if (r[0] == 172 && r[1] >= 16 && r[1] <= 31) return 50;
    return 200;
  }

  static Future<List<InternetAddress>> _orderedBindAddresses() async {
    final specific = <InternetAddress>[];
    try {
      final ifs = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final ni in ifs) {
        for (final addr in ni.addresses) {
          if (addr.type != InternetAddressType.IPv4) continue;
          if (addr.isLoopback) continue;
          if (_isPrivateIpv4(addr)) specific.add(addr);
        }
      }
      specific.sort((a, b) {
        final c = _bindPreference(a).compareTo(_bindPreference(b));
        return c != 0 ? c : a.address.compareTo(b.address);
      });
    } catch (e) {
      debugPrint('[LanBroadcast] orderedBindAddresses: $e');
    }
    return [...specific, InternetAddress.anyIPv4];
  }

  Future<RawDatagramSocket?> _tryOpenSocket() async {
    Object? lastErr;
    for (final addr in await _orderedBindAddresses()) {
      try {
        final s = await RawDatagramSocket.bind(
          addr,
          kPort,
          reuseAddress: true,
        );
        if (kDebugMode) {
          debugPrint('[LanBroadcast] bound ${addr.address}:$kPort');
        }
        return s;
      } catch (e) {
        lastErr = e;
      }
    }
    debugPrint('[LanBroadcast] bind $kPort failed: $lastErr');
    return null;
  }

  Future<void> _refreshBroadcastTargets() async {
    final next = await _enumerateBroadcastTargets();
    if (next.isNotEmpty) {
      _broadcastTargets = next;
    }
  }

  static Future<List<InternetAddress>> _enumerateBroadcastTargets() async {
    final byKey = <String, InternetAddress>{
      '255.255.255.255': InternetAddress('255.255.255.255'),
    };
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final ni in interfaces) {
        for (final addr in ni.addresses) {
          if (addr.type != InternetAddressType.IPv4) continue;
          final raw = addr.rawAddress;
          if (raw.length != 4) continue;
          if (raw[0] == 127) continue;
          final bcast = InternetAddress.fromRawAddress(
            Uint8List.fromList([raw[0], raw[1], raw[2], 255]),
          );
          byKey[bcast.address] = bcast;
        }
      }
    } catch (e) {
      debugPrint('[LanBroadcast] enumerateBroadcastTargets: $e');
    }
    return byKey.values.toList();
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final d = _socket?.receive();
    if (d == null || d.data.length < 4 || d.data.length > kMaxPacket) return;
    final head = String.fromCharCodes(d.data.sublist(0, 4));
    if (head != kMagic) return;
    Map<String, dynamic> map;
    try {
      map = jsonDecode(utf8.decode(d.data.sublist(4))) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final did = map['did']?.toString();
    if (did == null || did.isEmpty) return;
    if (_isSelf?.call(did) ?? false) {
      // Windows 常把本机子网广播递回给自己，约每 2s 一条，不必每次打日志。
      if (kDebugMode) {
        final now = DateTime.now();
        if (_lastSelfIgnoreLogAt == null ||
            now.difference(_lastSelfIgnoreLogAt!) > const Duration(seconds: 30)) {
          _lastSelfIgnoreLogAt = now;
          debugPrint(
            '[LanBroadcast] 忽略与本机 deviceId 相同的包（多为本机 UDP 回环，正常）。'
            '若两台真实电脑设备 ID 也相同，则无法互发现，请删应用支持目录下 xtransfer_device_id 后重启。',
          );
        }
      }
      return;
    }
    final peer = DiscoveredPeer.tryParseLan(map, d.address.address);
    if (peer == null) {
      if (kDebugMode) {
        debugPrint(
          '[LanBroadcast] 解析失败 did=$did fport=${map['fport']} (${map['fport'].runtimeType})',
        );
      }
      return;
    }
    _onPeer?.call(peer);
  }

  void _announce() {
    final socket = _socket;
    final build = _payloadBuilder;
    if (socket == null || build == null) return;
    Map<String, dynamic> map;
    try {
      map = {...build(), 'v': 1};
    } catch (e) {
      debugPrint('[LanBroadcast] payload: $e');
      return;
    }
    final body = utf8.encode(kMagic + jsonEncode(map));
    if (body.length > kMaxPacket) return;
    var okTargets = 0;
    for (final target in _broadcastTargets) {
      var wroteOk = false;
      for (var rep = 0; rep < 2; rep++) {
        try {
          final n = socket.send(body, target, kPort);
          if (n == body.length) {
            wroteOk = true;
          } else if (kDebugMode) {
            debugPrint(
              '[LanBroadcast] send → ${target.address} 仅写出 $n/${body.length} 字节',
            );
          }
        } catch (e) {
          debugPrint('[LanBroadcast] send → ${target.address}: $e');
        }
      }
      if (wroteOk) okTargets++;
    }
    if (_broadcastTargets.isNotEmpty && okTargets == 0) {
      _allSendFailStreak++;
      _zeroSendRounds++;
      if (_allSendFailStreak >= 3) {
        _onTransportWarning?.call(
          '局域网发现 UDP 已连续多轮未能发出。若日志里曾出现「仅写出 0 字节」，多为 **本机多网卡（含 WSL/Hyper-V 172.17.x）** 下绑定 0.0.0.0 导致；'
          '请更新到已「优先绑定 192.168.x.x」的版本。若仍失败，再查防火墙：dart.exe / flutterdemo2.exe 与 python.exe 规则独立。',
        );
        _allSendFailStreak = 0;
      }
      if (_zeroSendRounds >= 6 && !_recoverInProgress) {
        _zeroSendRounds = 0;
        _recoverInProgress = true;
        unawaited(_recoverSocketThenClear());
      }
    } else {
      _allSendFailStreak = 0;
      _zeroSendRounds = 0;
    }
  }

  Future<void> _recoverSocketThenClear() async {
    try {
      await _recoverSocket();
    } finally {
      _recoverInProgress = false;
    }
  }

  /// 网卡枚举或 DHCP 滞后时，旧 socket 可能长期「写出 0 字节」；关闭后按当前网卡列表重绑。
  Future<void> _recoverSocket() async {
    if (_payloadBuilder == null) return;
    final newSock = await _tryOpenSocket();
    if (newSock == null) {
      if (kDebugMode) {
        debugPrint('[LanBroadcast] recover: rebind failed');
      }
      return;
    }
    try {
      _sub?.cancel();
    } catch (_) {}
    try {
      _socket?.close();
    } catch (_) {}
    _socket = newSock;
    _socket!.broadcastEnabled = true;
    _sub = _socket!.listen(_onSocketEvent);
    await _refreshBroadcastTargets();
    if (kDebugMode) {
      debugPrint('[LanBroadcast] socket recovered (rebound after zero-send streak)');
    }
  }

  void dispose() {
    _announceTicks = 0;
    _lastSelfIgnoreLogAt = null;
    _timer?.cancel();
    _timer = null;
    _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
    _payloadBuilder = null;
    _isSelf = null;
    _onPeer = null;
    _onTransportWarning = null;
    _allSendFailStreak = 0;
    _zeroSendRounds = 0;
    _recoverInProgress = false;
  }
}
