import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../models/discovered_peer.dart';

/// 可拖放目标的标签行：悬停时高亮，支持拖拽到标签上传输给所有用户
class TagDropTile extends StatefulWidget {
  const TagDropTile({
    super.key,
    required this.enableDrop,
    required this.onDrop,
    required this.label,
    required this.users,
    this.subtitle,
  });

  final bool enableDrop;
  final void Function(List<DiscoveredPeer> users, DropDoneDetails details) onDrop;
  final String label;
  final List<DiscoveredPeer> users;
  final Widget? subtitle;

  @override
  State<TagDropTile> createState() => _TagDropTileState();
}

class _TagDropTileState extends State<TagDropTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _hover ? scheme.primary : scheme.outlineVariant,
          width: _hover ? 2 : 1,
        ),
        color: _hover ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      ),
      child: ListTile(
        leading: const Icon(Icons.label_outline),
        title: Text(widget.label),
        subtitle: widget.subtitle ?? Text('${widget.users.length} 个用户'),
        trailing: const Icon(Icons.people_outline),
      ),
    );

    if (!widget.enableDrop) return child;

    return DropTarget(
      enable: widget.enableDrop,
      onDragEntered: (_) => setState(() => _hover = true),
      onDragExited: (_) => setState(() => _hover = false),
      onDragDone: (d) {
        setState(() => _hover = false);
        widget.onDrop(widget.users, d);
      },
      child: child,
    );
  }
}