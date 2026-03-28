import 'package:bonsoir/bonsoir.dart';

/// 从 Bonsoir 解析后的对端节点（与 Rust `PeerInfoDto` 字段对齐）。
class DiscoveredPeer {
  DiscoveredPeer({
    required this.peerId,
    required this.instanceId,
    required this.nickname,
    required this.tags,
    required this.host,
    required this.fileServicePort,
    required this.remoteDesktopPort,
    required this.lastSeen,
    this.serviceName,
  });

  final String peerId;
  final String instanceId;
  final String nickname;
  final List<String> tags;
  final String host;
  final int fileServicePort;
  final int remoteDesktopPort;
  final DateTime lastSeen;
  final String? serviceName;

  static DiscoveredPeer? tryParse(BonsoirService s) {
    final host = s.host?.trim();
    if (host == null || host.isEmpty) return null;
    final a = s.attributes;
    final did = a['did'] ?? a['deviceId'];
    if (did == null || did.isEmpty) return null;
    final nick = a['nick'] ?? s.name;
    final tagsRaw = a['tags'] ?? '';
    final tags = tagsRaw.isEmpty
        ? <String>[]
        : tagsRaw
              .split('|||')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
    final fs = int.tryParse(a['fport'] ?? '') ?? s.port;
    final rd = int.tryParse(a['rport'] ?? '') ?? 0;
    return DiscoveredPeer(
      peerId: did,
      instanceId: a['inst'] ?? '',
      nickname: nick,
      tags: tags,
      host: host,
      fileServicePort: fs,
      remoteDesktopPort: rd,
      lastSeen: DateTime.now(),
      serviceName: s.name,
    );
  }

  /// JSON 数字/字符串端口（避免 `fport` 类型不一致时静默丢包）。
  static int? coercePort(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  /// 局域网 UDP 广播 JSON（与 Bonsoir TXT 字段一致，不含 magic 前缀）。
  static DiscoveredPeer? tryParseLan(Map<String, dynamic> m, String sourceIp) {
    final did = m['did']?.toString();
    if (did == null || did.isEmpty) return null;
    final tagsRaw = m['tags'] as String? ?? '';
    final tagList = tagsRaw.isEmpty
        ? <String>[]
        : tagsRaw
              .split('|||')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
    final fp = coercePort(m['fport']);
    if (fp == null || fp <= 0 || fp > 65535) return null;
    final rd = coercePort(m['rport']) ?? 0;
    return DiscoveredPeer(
      peerId: did,
      instanceId: m['inst']?.toString() ?? '',
      nickname: m['nick']?.toString() ?? '',
      tags: tagList,
      host: sourceIp,
      fileServicePort: fp,
      remoteDesktopPort: rd,
      lastSeen: DateTime.now(),
      serviceName: 'lan-broadcast',
    );
  }

  DiscoveredPeer copyWith({DateTime? lastSeen}) => DiscoveredPeer(
    peerId: peerId,
    instanceId: instanceId,
    nickname: nickname,
    tags: tags,
    host: host,
    fileServicePort: fileServicePort,
    remoteDesktopPort: remoteDesktopPort,
    lastSeen: lastSeen ?? this.lastSeen,
    serviceName: serviceName,
  );
}
