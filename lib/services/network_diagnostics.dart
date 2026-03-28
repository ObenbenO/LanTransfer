import 'package:flutter/foundation.dart';

import '../app/app_session.dart';

/// 可复制快照，供技术支持或双方对照。
String collectNetworkDiagnostics(AppSession session) {
  final buf = StringBuffer();
  buf.writeln('=== X传输 简要诊断 ${DateTime.now().toIso8601String()} ===');
  buf.writeln('kIsWeb: $kIsWeb');
  buf.writeln('defaultTargetPlatform: $defaultTargetPlatform');
  buf.writeln('discoverySupported: ${session.discoverySupported}');
  buf.writeln('lanBroadcastActive: ${session.lanBroadcastActive}');
  buf.writeln('instanceTag: "${AppSession.instanceTag}"');
  buf.writeln('localDeviceId: ${session.localDeviceId}');
  buf.writeln('nickname: ${session.nickname}');
  buf.writeln('tags: ${session.tags}');
  buf.writeln('fileListenPort: ${session.fileListenPort}');
  buf.writeln('remoteDesktopHostEnabled: ${session.remoteDesktopHostEnabled}');
  buf.writeln('remoteDesktopAdvertisedPort: ${session.remoteDesktopAdvertisedPort}');
  buf.writeln('lastError: ${session.lastError}');
  buf.writeln('peers count: ${session.peersById.length}');
  for (final e in session.peersById.entries) {
    final p = e.value;
    buf.writeln(
      '  peerId=${e.key} host=${p.host} fport=${p.fileServicePort} '
      'rport=${p.remoteDesktopPort} nick=${p.nickname}',
    );
  }
  buf.writeln('');
  buf.writeln('提示：两台电脑的 localDeviceId 不应相同；若相同需分别清理设备标识缓存。');
  return buf.toString();
}
