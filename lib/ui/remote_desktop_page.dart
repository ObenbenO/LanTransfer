import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../app/app_session.dart';
import '../models/discovered_peer.dart';
import '../src/rust/api/remote_client.dart';
import '../src/rust/api/types.dart';

bool _looksLikeJpeg(Uint8List b) =>
    b.length >= 2 && b[0] == 0xFF && b[1] == 0xD8;

/// 轮询 Rust 侧画面帧（JPEG 或 RGBA）并解码显示。
///
/// 单飞解码 + `_pending` 只保留最新一帧，避免此前 `_decodeGen` 在 50ms 轮询下
/// 快于 [decodeImageFromPixels] 回调而导致**每帧回调都被判为过期**、界面永远停在首帧。
///
/// **Rust 侧**也是单槽：新帧覆盖旧帧；[remoteClientTryTakeRgbaFrame] 会取走并清空槽位。
/// 解码慢于推流时，中间帧会被丢弃，只显示**当时槽里最新的一帧**（有意为之）。
class RdpViewController extends ChangeNotifier {
  Timer? _timer;
  ui.Image? _image;
  int frameW = 0;
  int frameH = 0;
  bool _disposed = false;
  bool _decoding = false;
  VideoFrameDto? _pending;
  int _debugDecodeOk = 0;

  ui.Image? get image => _image;

  void startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _tick() {
    if (_disposed) return;
    try {
      if (_decoding) {
        final f = remoteClientTryTakeRgbaFrame();
        if (f != null) {
          _pending = f;
        }
        return;
      }
      final f = _pending ?? remoteClientTryTakeRgbaFrame();
      _pending = null;
      if (f == null) return;
      _decoding = true;
      unawaited(_decodeFrame(f));
    } catch (_) {
      _decoding = false;
    }
  }

  Future<void> _decodeFrame(VideoFrameDto f) async {
    ui.Codec? jpegCodec;
    try {
      final bytes = Uint8List.fromList(f.rgba);
      final w = f.width;
      final h = f.height;
      if (_looksLikeJpeg(bytes)) {
        const t = Duration(seconds: 5);
        jpegCodec = await ui.instantiateImageCodec(bytes).timeout(
          t,
          onTimeout: () => throw TimeoutException('instantiateImageCodec', t),
        );
        final fi = await jpegCodec.getNextFrame().timeout(
          t,
          onTimeout: () => throw TimeoutException('getNextFrame', t),
        );
        if (_disposed) {
          fi.image.dispose();
          return;
        }
        _image?.dispose();
        _image = fi.image;
        frameW = w;
        frameH = h;
        notifyListeners();
        if (kDebugMode) {
          _debugDecodeOk++;
          if (_debugDecodeOk == 1 || _debugDecodeOk % 30 == 0) {
            debugPrint(
              'RdpViewController: JPEG decode ok count=$_debugDecodeOk '
              '(若持续增长说明 Flutter 侧在更新，不是只收到一帧)',
            );
          }
        }
      } else {
        final done = Completer<void>();
        ui.decodeImageFromPixels(
          bytes,
          w,
          h,
          ui.PixelFormat.rgba8888,
          (ui.Image img) {
            if (_disposed) {
              img.dispose();
            } else {
              _image?.dispose();
              _image = img;
              frameW = w;
              frameH = h;
              notifyListeners();
              if (kDebugMode) {
                _debugDecodeOk++;
                if (_debugDecodeOk == 1 || _debugDecodeOk % 30 == 0) {
                  debugPrint(
                    'RdpViewController: RGBA decode ok count=$_debugDecodeOk',
                  );
                }
              }
            }
            if (!done.isCompleted) {
              done.complete();
            }
          },
        );
        await done.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
      }
    } catch (e, st) {
      debugPrint('RdpViewController decode: $e\n$st');
    } finally {
      jpegCodec?.dispose();
      if (!_disposed) {
        _decoding = false;
        scheduleMicrotask(_tick);
      }
    }
  }

  void disposeController() {
    _disposed = true;
    _pending = null;
    _timer?.cancel();
    _timer = null;
    _image?.dispose();
    _image = null;
    frameW = 0;
    frameH = 0;
    _decoding = false;
  }

  @override
  void dispose() {
    disposeController();
    super.dispose();
  }
}

/// 与 Rust `MOD_*` 一致：Shift=1, Ctrl=2, Alt=4, Meta=8。
int _rdModifierMask() {
  final m = HardwareKeyboard.instance;
  var mask = 0;
  if (m.isShiftPressed) mask |= 1;
  if (m.isControlPressed) mask |= 2;
  if (m.isAltPressed) mask |= 4;
  if (m.isMetaPressed) mask |= 8;
  return mask;
}

(int code, bool down)? _encodeRustKey(KeyEvent e) {
  if (e is! KeyDownEvent && e is! KeyUpEvent && e is! KeyRepeatEvent) {
    return null;
  }
  final down = e is KeyDownEvent || e is KeyRepeatEvent;
  final k = e.logicalKey;

  int? special;
  if (k == LogicalKeyboardKey.arrowLeft) {
    special = -100;
  } else if (k == LogicalKeyboardKey.arrowRight) {
    special = -101;
  } else if (k == LogicalKeyboardKey.arrowUp) {
    special = -102;
  } else if (k == LogicalKeyboardKey.arrowDown) {
    special = -103;
  } else if (k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter) {
    special = -104;
  } else if (k == LogicalKeyboardKey.backspace) {
    special = -105;
  } else if (k == LogicalKeyboardKey.escape) {
    special = -106;
  } else if (k == LogicalKeyboardKey.delete) {
    special = -107;
  } else if (k == LogicalKeyboardKey.tab) {
    special = -108;
  } else if (k == LogicalKeyboardKey.home) {
    special = -109;
  } else if (k == LogicalKeyboardKey.end) {
    special = -110;
  } else if (k == LogicalKeyboardKey.pageUp) {
    special = -111;
  } else if (k == LogicalKeyboardKey.pageDown) {
    special = -112;
  } else if (k == LogicalKeyboardKey.controlLeft ||
      k == LogicalKeyboardKey.controlRight) {
    special = -113;
  } else if (k == LogicalKeyboardKey.shiftLeft ||
      k == LogicalKeyboardKey.shiftRight) {
    special = -114;
  } else if (k == LogicalKeyboardKey.altLeft ||
      k == LogicalKeyboardKey.altRight) {
    special = -115;
  } else if (k == LogicalKeyboardKey.metaLeft ||
      k == LogicalKeyboardKey.metaRight) {
    special = -116;
  }

  if (special != null) {
    return (special, down);
  }

  if (e is KeyRepeatEvent) {
    return null;
  }

  if (e is KeyDownEvent || e is KeyUpEvent) {
    var text = e.character;
    if (text == null || text.isEmpty) {
      final lab = e.logicalKey.keyLabel;
      if (lab.length == 1) {
        text = lab;
      }
    }
    if (text != null && text.isNotEmpty) {
      final cp = text.runes.first;
      if (cp > 0 && cp < 0x110000) {
        return (cp, down);
      }
    }
  }

  return null;
}

/// 远控会话：连接表单 + 实时画面 + 键鼠转发。
class RemoteDesktopPage extends StatefulWidget {
  const RemoteDesktopPage({super.key, this.prefill});

  final DiscoveredPeer? prefill;

  @override
  State<RemoteDesktopPage> createState() => _RemoteDesktopPageState();
}

class _RemoteDesktopPageState extends State<RemoteDesktopPage> {
  late final TextEditingController _host;
  late final TextEditingController _port;
  bool _busy = false;
  bool _connected = false;
  String? _err;
  RdpViewController? _rdp;

  /// 从用户列表点「远程协助」进入时自动发起连接，跳过手动点「连接」。
  bool get _shouldAutoConnect {
    final p = widget.prefill;
    return p != null && p.remoteDesktopPort > 0;
  }

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    _host = TextEditingController(text: p?.host ?? '127.0.0.1');
    _port = TextEditingController(
      text: p != null && p.remoteDesktopPort > 0
          ? '${p.remoteDesktopPort}'
          : '0',
    );
    if (_shouldAutoConnect) {
      _busy = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_connect());
        }
      });
    }
  }

  @override
  void dispose() {
    _rdp?.disposeController();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final port = int.tryParse(_port.text.trim()) ?? 0;
      await remoteClientConnect(
        host: _host.text.trim(),
        port: port,
        sessionToken: AppSession.kLanRemoteSessionToken,
      );
      _rdp?.disposeController();
      _rdp = RdpViewController()..startPolling();
      setState(() => _connected = true);
    } catch (e) {
      setState(() => _err = e is FrbException ? e.toString() : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      _rdp?.disposeController();
      _rdp = null;
      await remoteClientDisconnect();
      setState(() => _connected = false);
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openFullscreen() {
    final c = _rdp;
    if (c == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => _RemoteDesktopFullscreenPage(
          controller: c,
          host: _host.text.trim(),
          port: int.tryParse(_port.text.trim()) ?? 0,
          onDisconnect: () async {
            await _disconnect();
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_connected ? '远程协助 · 已连接' : '远程协助'),
        actions: [
          if (_connected)
            IconButton(
              tooltip: '断开',
              onPressed: _busy ? null : _disconnect,
              icon: const Icon(Icons.link_off),
            ),
        ],
      ),
      body: _connected ? _buildConnectedBody(context) : _buildFormBody(context),
    );
  }

  Widget _buildFormBody(BuildContext context) {
    if (_shouldAutoConnect && _busy && _err == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在连接…'),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _host,
          decoration: const InputDecoration(
            labelText: '对方电脑地址',
            hintText: '一般从列表进入会自动填好',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _port,
          decoration: const InputDecoration(
            labelText: '远程协助端口',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _connect,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('连接'),
        ),
        if (_err != null) ...[
          const SizedBox(height: 12),
          Text(
            _err!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          '对方需在「设置」中开启「允许其他人远程控制本电脑」。'
          '连接后，您的鼠标和键盘会作用在对方电脑上，请仅在取得对方同意时使用。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildConnectedBody(BuildContext context) {
    final c = _rdp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: c == null
              ? const Center(child: Text('内部错误：无会话'))
              : _RdpLiveView(controller: c),
        ),
        Material(
          elevation: 8,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _disconnect,
                    icon: const Icon(Icons.link_off),
                    label: const Text('断开'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _openFullscreen,
                    icon: const Icon(Icons.fullscreen),
                    label: const Text('全屏'),
                  ),
                  const Spacer(),
                  Chip(
                    avatar: Icon(
                      Icons.monitor,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    label: const Text('远程协助'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RdpLiveView extends StatefulWidget {
  const _RdpLiveView({required this.controller});

  final RdpViewController controller;

  @override
  State<_RdpLiveView> createState() => _RdpLiveViewState();
}

class _RdpLiveViewState extends State<_RdpLiveView> {
  /// 与隐藏 [TextField] 共用：承接系统 IME（中文等），可打印字符由此上屏再转发远端。
  final FocusNode _kbdFocus = FocusNode();
  late final TextEditingController _imeSink;
  /// 上次已同步到远端的文本（仅在不处于 composing 时更新）。
  String _lastSyncedText = '';
  int _rdTxPointerOk = 0;
  int _rdTxKeyOk = 0;

  @override
  void initState() {
    super.initState();
    _imeSink = TextEditingController();
    _imeSink.addListener(_onImeSinkChanged);
  }

  @override
  void dispose() {
    _imeSink.removeListener(_onImeSinkChanged);
    _imeSink.dispose();
    _kbdFocus.dispose();
    super.dispose();
  }

  void _onImeSinkChanged() {
    final v = _imeSink.value;
    if (v.composing.isValid && v.composing.start < v.composing.end) {
      return;
    }
    final t = v.text;
    if (t == _lastSyncedText) {
      return;
    }
    _syncTextDeltaToRemote(_lastSyncedText, t);
    _lastSyncedText = t;
    if (t.length > 4000) {
      _imeSink.clear();
      _lastSyncedText = '';
    }
  }

  void _syncTextDeltaToRemote(String oldText, String newText) {
    if (newText.startsWith(oldText)) {
      final added = newText.substring(oldText.length);
      for (final cp in added.runes) {
        _sendUnicodeToRemote(cp);
      }
      return;
    }
    if (oldText.startsWith(newText)) {
      final n = oldText.length - newText.length;
      for (var i = 0; i < n; i++) {
        _sendBackspaceToRemote();
      }
      return;
    }
    for (var i = 0; i < oldText.length; i++) {
      _sendBackspaceToRemote();
    }
    for (final cp in newText.runes) {
      _sendUnicodeToRemote(cp);
    }
  }

  void _sendUnicodeToRemote(int codePoint) {
    if (codePoint <= 0 || codePoint >= 0x110000) {
      return;
    }
    try {
      remoteClientSendKey(
        event: RemoteKeyEventDto(
          keyCode: codePoint,
          down: true,
          modifiers: 0,
        ),
      );
    } catch (e, st) {
      debugPrint('remoteClientSendKey (unicode) failed: $e\n$st');
    }
  }

  /// 与 Rust 特殊键 -105 一致。
  void _sendBackspaceToRemote() {
    const code = -105;
    try {
      remoteClientSendKey(
        event: RemoteKeyEventDto(keyCode: code, down: true, modifiers: 0),
      );
      remoteClientSendKey(
        event: RemoteKeyEventDto(keyCode: code, down: false, modifiers: 0),
      );
    } catch (e, st) {
      debugPrint('remoteClientSendKey (backspace) failed: $e\n$st');
    }
  }

  int _pointerButton(int buttons) {
    if (buttons & kSecondaryMouseButton != 0) {
      return 2;
    }
    return 1;
  }

  void _sendPointer(
    String kind,
    Offset local,
    Size viewSize,
    int button,
    double delta,
  ) {
    final c = widget.controller;
    if (c.frameW <= 0 ||
        c.frameH <= 0 ||
        viewSize.width <= 0 ||
        viewSize.height <= 0) {
      return;
    }
    final x = local.dx / viewSize.width * c.frameW;
    final y = local.dy / viewSize.height * c.frameH;
    if (!x.isFinite || !y.isFinite) {
      return;
    }
    try {
      remoteClientSendPointer(
        event: RemotePointerEventDto(
          kind: kind,
          x: x,
          y: y,
          button: button,
          delta: delta,
          modifiers: _rdModifierMask(),
        ),
      );
      if (kDebugMode) {
        _rdTxPointerOk++;
        if (_rdTxPointerOk <= 10 || _rdTxPointerOk % 80 == 0) {
          debugPrint(
            '[rd-tx] remoteClientSendPointer ok kind=$kind count=$_rdTxPointerOk '
            'x=${x.toStringAsFixed(0)} y=${y.toStringAsFixed(0)} '
            '(若点击画面始终没有本行，多为 frame 未就绪或未收到指针事件)',
          );
        }
      }
    } catch (e, st) {
      debugPrint('remoteClientSendPointer failed: $e\n$st');
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final enc = _encodeRustKey(event);
    if (enc == null) {
      return KeyEventResult.ignored;
    }
    final mods = _rdModifierMask();
    // 无修饰键的可打印字符由隐藏 TextField + IME 走 _onImeSinkChanged（中文上屏）。
    if (enc.$1 >= 0 && mods == 0) {
      return KeyEventResult.ignored;
    }
    try {
      remoteClientSendKey(
        event: RemoteKeyEventDto(
          keyCode: enc.$1,
          down: enc.$2,
          modifiers: mods,
        ),
      );
      if (kDebugMode) {
        _rdTxKeyOk++;
        if (_rdTxKeyOk <= 10 || _rdTxKeyOk % 40 == 0) {
          debugPrint(
            '[rd-tx] remoteClientSendKey ok keyCode=${enc.$1} down=${enc.$2} count=$_rdTxKeyOk',
          );
        }
      }
    } catch (e, st) {
      debugPrint('remoteClientSendKey failed: $e\n$st');
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final c = widget.controller;
              final img = c.image;
              if (img == null) {
                return GestureDetector(
                  onTap: () => _kbdFocus.requestFocus(),
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '已连接，等待首帧画面…\n（点击此处聚焦以使用键盘；中文输入法需由此获得焦点）',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, height: 1.4),
                    ),
                  ),
                );
              }
              final iw = c.frameW.toDouble();
              final ih = c.frameH.toDouble();
              final viewSize = Size(iw, ih);
              final picture = RawImage(
                image: img,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
              );
              return FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.center,
                child: SizedBox(
                  width: iw,
                  height: ih,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) {
                      _kbdFocus.requestFocus();
                      _sendPointer(
                        'down',
                        e.localPosition,
                        viewSize,
                        _pointerButton(e.buttons),
                        0,
                      );
                    },
                    onPointerMove: (e) {
                      if (e.down) {
                        _sendPointer(
                          'move',
                          e.localPosition,
                          viewSize,
                          _pointerButton(e.buttons),
                          0,
                        );
                      }
                    },
                    onPointerHover: (e) {
                      _sendPointer('move', e.localPosition, viewSize, 1, 0);
                    },
                    onPointerUp: (e) {
                      _sendPointer(
                        'up',
                        e.localPosition,
                        viewSize,
                        _pointerButton(e.buttons),
                        0,
                      );
                    },
                    onPointerSignal: (signal) {
                      if (signal is PointerScrollEvent) {
                        _sendPointer(
                          'scroll',
                          signal.localPosition,
                          viewSize,
                          0,
                          signal.scrollDelta.dy,
                        );
                      }
                    },
                    child: picture,
                  ),
                ),
              );
            },
          ),
          // 穿透点击，仅用于持有 IME；中文组字完成后由 controller 差量转发。
          Positioned(
            left: 0,
            top: 0,
            width: 1,
            height: 1,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0,
                child: Focus(
                  focusNode: _kbdFocus,
                  autofocus: true,
                  onKeyEvent: _onKey,
                  child: TextField(
                    focusNode: _kbdFocus,
                    controller: _imeSink,
                    maxLines: 8,
                    minLines: 1,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(
                      color: Colors.transparent,
                      fontSize: 1,
                      height: 1,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    cursorColor: Colors.transparent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteDesktopFullscreenPage extends StatelessWidget {
  const _RemoteDesktopFullscreenPage({
    required this.controller,
    required this.host,
    required this.port,
    required this.onDisconnect,
  });

  final RdpViewController controller;
  final String host;
  final int port;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _RdpLiveView(controller: controller),
            ),
            Positioned(
              top: 4,
              left: 4,
              right: 4,
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.fullscreen_exit),
                    tooltip: '退出全屏',
                  ),
                  const Spacer(),
                  Text(
                    '$host:$port',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () async {
                      await onDisconnect();
                    },
                    icon: const Icon(Icons.power_settings_new),
                    tooltip: '断开并关闭',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
