import 'package:flutter/foundation.dart';

import 'discovered_peer.dart';

/// 树节点：标签分组或用户叶子。
sealed class UserTreeNode {
  const UserTreeNode();
}

@immutable
class TagTreeNode extends UserTreeNode {
  const TagTreeNode({required this.label, required this.children});

  final String label;
  final List<UserTreeNode> children;
}

@immutable
class UserTreeLeaf extends UserTreeNode {
  const UserTreeLeaf({required this.peer});

  final DiscoveredPeer peer;
}

class _BuilderNode {
  final List<DiscoveredPeer> users = [];
  final Map<String, _BuilderNode> children = {};
}

/// 将扁平对端列表按标签路径插入树（会场 → 片区 → … → 用户）。
List<UserTreeNode> buildUserForest(List<DiscoveredPeer> peers) {
  final root = _BuilderNode();
  final noTag = <DiscoveredPeer>[];

  for (final p in peers) {
    if (p.tags.isEmpty) {
      noTag.add(p);
      continue;
    }
    var cur = root;
    for (final tag in p.tags) {
      cur = cur.children.putIfAbsent(tag, _BuilderNode.new);
    }
    cur.users.add(p);
  }

  List<UserTreeNode> convert(_BuilderNode n) {
    final out = <UserTreeNode>[];
    for (final u in n.users) {
      out.add(UserTreeLeaf(peer: u));
    }
    for (final e in n.children.entries) {
      out.add(TagTreeNode(label: e.key, children: convert(e.value)));
    }
    return out;
  }

  return [...noTag.map((e) => UserTreeLeaf(peer: e)), ...convert(root)];
}
