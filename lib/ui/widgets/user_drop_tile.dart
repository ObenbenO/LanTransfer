import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

/// 可拖放目标的用户行：悬停时高亮（清单 4.2 传输入口视觉反馈）。
class UserDropTile extends StatefulWidget {
  const UserDropTile({
    super.key,
    required this.enableDrop,
    required this.onDrop,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final bool enableDrop;
  final void Function(DropDoneDetails details) onDrop;
  final Widget title;
  final Widget subtitle;
  final Widget? trailing;

  @override
  State<UserDropTile> createState() => _UserDropTileState();
}

class _UserDropTileState extends State<UserDropTile> {
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
        leading: const Icon(Icons.person_outline),
        title: widget.title,
        subtitle: widget.subtitle,
        trailing: widget.trailing,
      ),
    );

    if (!widget.enableDrop) return child;

    return DropTarget(
      enable: widget.enableDrop,
      onDragEntered: (_) => setState(() => _hover = true),
      onDragExited: (_) => setState(() => _hover = false),
      onDragDone: (d) {
        setState(() => _hover = false);
        widget.onDrop(d);
      },
      child: child,
    );
  }
}
