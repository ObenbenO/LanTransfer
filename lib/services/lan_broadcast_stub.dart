import '../models/discovered_peer.dart';

/// 非 IO 平台占位（如 Web）。
class LanBroadcastController {
  static const int kPort = 45678;

  Future<bool> start({
    required void Function(DiscoveredPeer peer) onPeer,
    required Map<String, dynamic> Function() payloadBuilder,
    required bool Function(String did) isSelf,
  }) async => false;

  void dispose() {}
}
