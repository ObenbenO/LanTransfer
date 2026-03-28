import 'package:flutter/foundation.dart';

import '../app/app_session.dart';

/// 可复制的结构化快照，用于与对端报告对照或抓包结果比对。
String collectNetworkDiagnostics(AppSession session) {
  final buf = StringBuffer();
  buf.writeln('=== X传输 网络诊断 ${DateTime.now().toIso8601String()} ===');
  buf.writeln('kIsWeb: $kIsWeb');
  buf.writeln('defaultTargetPlatform: $defaultTargetPlatform');
  buf.writeln('discoverySupported: ${session.discoverySupported}');
  buf.writeln('lanBroadcastActive: ${session.lanBroadcastActive}');
  buf.writeln('instanceTag: "${AppSession.instanceTag}"');
  buf.writeln('localDeviceId: ${session.localDeviceId}');
  buf.writeln('nickname: ${session.nickname}');
  buf.writeln('tags: ${session.tags}');
  buf.writeln('fileListenPort: ${session.fileListenPort}');
  buf.writeln('remoteDesktopAdvertisedPort: ${session.remoteDesktopAdvertisedPort}');
  buf.writeln('debugLoopback: ${session.debugLoopback}');
  buf.writeln('lastError: ${session.lastError}');
  buf.writeln('peers count: ${session.peersById.length}');
  for (final e in session.peersById.entries) {
    final p = e.value;
    buf.writeln(
      '  peerId=${e.key} host=${p.host} fport=${p.fileServicePort} '
      'via=${p.serviceName} nick=${p.nickname}',
    );
  }
  buf.writeln('');
  buf.writeln('--- 如何客观判定（最接近「一锤定音」）---');
  buf.writeln('1) 两台同时复制本报告，核对 localDeviceId 必须不同。');
  buf.writeln('2) 双方 lanBroadcastActive 须为 true；否则本机未监听 UDP 45678（勿同时跑 python listen）。');
  buf.writeln('3) 在收发各装 Wireshark，选当前 Wi‑Fi 网卡，显示过滤器：udp.port == 45678');
  buf.writeln('   · A 启动本应用后，A 上应周期性出现发往 192.168.x.255:45678 的 OUT 包（或 255.255.255.255）。');
  buf.writeln('   · B 上应出现来自 A 的 IP、目的端口 45678 的 IN 包。');
  buf.writeln('   · B 有 IN 但界面无列表 → 应用层/解析/deviceId 问题；把双方报告对照。');
  buf.writeln('   · B 无 IN 但 A 有 OUT → 路径上丢弃（AP 隔离/防火墙/网段）。');
  buf.writeln('   · A 无 OUT → 本机未发广播（见 lanBroadcastActive / 端口占用）。');
  buf.writeln('4) 与 Python 探针对照：仅当本应用关闭时可在对端 listen 45678，避免端口冲突。');
  buf.writeln(
    '5) 若 Python 收不到 Flutter 但收得到 python send：请看 lastError 是否含 Bonsoir；'
    '旧版在 Bonsoir 抛错时会跳过 UDP 广播启动，现已改为先启动 UDP。',
  );
  return buf.toString();
}
