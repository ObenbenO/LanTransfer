import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/app_session.dart';
import '../files/export_text.dart';
import '../models/discovered_peer.dart';
import '../models/user_tree.dart';
import '../utils/cartoon_file_icon.dart';
import '../src/rust/api/types.dart';
import 'about_page.dart';
import 'remote_desktop_page.dart';
import 'settings_page.dart';
import 'troubleshooting_page.dart';
import 'widgets/tag_drop_tile.dart';
import 'widgets/user_drop_tile.dart';

/// 首页分区标题样式：整段同一 [fontWeight]，避免部分系统上中文出现「前几个字粗、后几个字细」的错觉。
TextStyle _homeSectionTitleStyle(BuildContext context) {
  final base = Theme.of(context).textTheme.titleMedium;
  return (base ?? const TextStyle(fontSize: 16)).copyWith(
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    height: 1.25,
  );
}

/// 分区标题行：左图标 + 文案（图标颜色为主色）。
Widget _sectionTitleRow(
  BuildContext context, {
  required IconData icon,
  required String label,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 2),
    child: Row(
      children: [
        Icon(icon, size: 22, color: scheme.primary),
        const SizedBox(width: 8),
        Text(label, style: _homeSectionTitleStyle(context)),
      ],
    ),
  );
}

/// 右上角弹出菜单项：图标 + 文案。
Widget _popupMenuRow(
  BuildContext context, {
  required IconData icon,
  required String label,
}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 12),
      Text(label, style: Theme.of(context).textTheme.bodyLarge),
    ],
  );
}

/// 接收记录中展示发送方：优先用发现列表得到「昵称 · 标签/标签/…」；否则提示未在列表。
String _senderDisplayLine(AppSession session, FileReceiveEventDto e) {
  final peer = session.peersById[e.senderPeerId];
  if (peer != null) {
    final nick = peer.nickname.trim().isEmpty ? '（对方未设置昵称）' : peer.nickname;
    if (peer.tags.isEmpty) {
      return nick;
    }
    return '$nick · ${peer.tags.join(' / ')}';
  }
  final id = e.senderPeerId;
  final short = id.length <= 14 ? id : '${id.substring(0, 10)}…';
  return '未在列表中的用户 · $short';
}

String _formatReceiveTimeMs(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  return '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}

/// 单条接收记录：文件名 + 用户信息行 + 留言气泡（仿聊天浅色底）+ 时间。
Widget _receiveEventCard(
  BuildContext context,
  AppSession session,
  FileReceiveEventDto e,
) {
  final scheme = Theme.of(context).colorScheme;
  final t = Theme.of(context).textTheme;
  final senderLine = _senderDisplayLine(session, e);
  final msg = e.message.trim();
  final err = e.error?.trim();

  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CartoonFileIcon(fileName: e.fileName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          e.fileName,
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatReceiveTimeMs(e.timestampMs.toInt()),
                        style: t.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (err != null && err.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      err,
                      style: t.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.account_circle_outlined,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          senderLine,
                          style: t.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (msg.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.65),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 16,
                              color: scheme.primary.withValues(alpha: 0.85),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                msg,
                                style: t.bodyMedium?.copyWith(
                                  height: 1.4,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 标签展开状态
class _ExpansionState {
  _ExpansionState(this.expanded, this.hover);
  
  final bool expanded;
  final bool hover;
}

/// 可展开的标签组件（StatefulWidget实现）
class _TagExpansionTileStateful extends StatefulWidget {
  const _TagExpansionTileStateful({
    required this.label,
    required this.users,
    required this.children,
    required this.dropEnabled,
    required this.onDropTag,
    required this.buildChild,
  });

  final String label;
  final List<DiscoveredPeer> users;
  final List<UserTreeNode> children;
  final bool dropEnabled;
  final void Function(List<DiscoveredPeer> users, DropDoneDetails details) onDropTag;
  final Widget Function(UserTreeNode node) buildChild;

  @override
  State<_TagExpansionTileStateful> createState() => _TagExpansionTileStatefulState();
}

class _TagExpansionTileStatefulState extends State<_TagExpansionTileStateful> {
  bool _expanded = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    // 标签头部内容
    final headerContent = AnimatedContainer(
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
        leading: Icon(_expanded ? Icons.expand_more : Icons.chevron_right),
        title: Text(widget.label),
        subtitle: widget.users.isNotEmpty
            ? Text('${widget.users.length} 个用户 · 点击展开')
            : const Text('暂无用户'),
        trailing: const Icon(Icons.people_outline),
      ),
    );
    
    // 如果没有用户或拖拽未启用，直接返回头部内容
    if (!widget.dropEnabled || widget.users.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: MouseRegion(
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: headerContent,
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children.map(widget.buildChild).toList(),
              ),
            ),
        ],
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标签头部（可点击展开 + 可拖拽）
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: DropTarget(
              enable: widget.dropEnabled && widget.users.isNotEmpty,
              onDragEntered: (_) => setState(() => _hover = true),
              onDragExited: (_) => setState(() => _hover = false),
              onDragDone: (d) {
                setState(() => _hover = false);
                widget.onDropTag(widget.users, d);
              },
              child: headerContent,
            ),
          ),
        ),
        
        // 展开的子节点
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children.map(widget.buildChild).toList(),
            ),
          ),
      ],
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  bool get _dropEnabled {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    };
  }

  String _profileLine(AppSession s) {
    if (s.nickname.isEmpty && s.tags.isEmpty) return '未设置（请打开设置）';
    if (s.tags.isEmpty) return s.nickname;
    return '${s.nickname}（${s.tags.join('/')}）';
  }

  Future<String?> _askMessage(BuildContext context) async {
    // 拖放结束时与 onDragDone 同帧内立刻 showDialog，pointer up 常会落到 barrier 上，
    // 默认 barrierDismissible 会把对话框立刻关掉，表现为「没弹窗就发送了」。
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return null;
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return null;

    final c = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('发送留言'),
          content: TextField(
            controller: c,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(hintText: '可选，接收者将看到此留言'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('发送'),
            ),
          ],
        ),
      );
    } finally {
      c.dispose();
    }
  }

  Future<void> _onDropUser(
    BuildContext context,
    AppSession session,
    DiscoveredPeer peer,
    DropDoneDetails d,
  ) async {
    final paths = AppSession.pathsFromDropDetails(d);
    if (paths.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未识别到本地文件路径')));
      return;
    }
    final msg = await _askMessage(context) ?? '';
    if (!context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(
                child: Text('正在发送 ${paths.length} 个文件至「${peer.nickname}」…'),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await session.sendToPeer(
        filePaths: paths,
        peerId: peer.peerId,
        message: msg,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已提交发送 ${paths.length} 个文件 → ${peer.nickname}')),
      );
    } catch (_) {
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _exportReceiveLogToFile(BuildContext context) async {
    final s = context.read<AppSession>();
    final buf = StringBuffer()..writeln('文件名\t用户信息\t留言\ttimestamp_ms');
    for (final e in s.receiveLog) {
      buf.writeln(
        '${e.fileName}\t${_senderDisplayLine(s, e).replaceAll('\t', ' ')}\t'
        '${e.message.replaceAll('\t', ' ')}\t${e.timestampMs}',
      );
    }
    final text = buf.toString();
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Web 端已复制记录到剪贴板')));
      return;
    }
    final ok = await exportTextFile('xtransfer_receive_log.txt', text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ok ? '已保存到所选文件' : '未保存（已取消或失败）')));
  }

  Future<void> _copyReceiveLog(BuildContext context) async {
    final s = context.read<AppSession>();
    final buf = StringBuffer();
    for (final e in s.receiveLog) {
      buf.writeln('${e.fileName} | ${_senderDisplayLine(s, e)} | ${e.message}');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制 ${s.receiveLog.length} 条')));
  }

  Widget _progressTile(BuildContext context, TransferProgressDto t) {
    final total = t.totalBytes.toInt();
    final sent = t.bytesSent.toInt();
    final ratio = total > 0 ? (sent / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '传输 · ${_shortTransferId(t.transferId)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (total > 0) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: ratio),
            Text(
              '已发送 $sent / $total',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else
            Text(
              '状态: ${t.phase}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (t.error != null)
            Text(
              t.error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTree(
    BuildContext context,
    AppSession session,
    List<UserTreeNode> nodes,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: nodes.map((n) => _buildNode(context, session, n)).toList(),
    );
  }

  Widget _buildNode(BuildContext context, AppSession session, UserTreeNode n) {
    switch (n) {
      case UserTreeLeaf(:final peer):
        final remoteOk = peer.remoteDesktopPort > 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: UserDropTile(
            enableDrop: _dropEnabled,
            onDrop: (d) => _onDropUser(context, session, peer, d),
            title: Text(peer.nickname),
            subtitle: Text(
              remoteOk
                  ? '${peer.host} · 拖放文件到此处发送'
                  : '${peer.host} · 拖放发文件 · 对方未开启远程协助',
            ),
            trailing: IconButton(
              icon: Icon(
                Icons.monitor,
                color: remoteOk
                    ? null
                    : Theme.of(context).colorScheme.onSurface.withValues(
                          alpha: 0.38,
                        ),
              ),
              tooltip: remoteOk ? '远程协助' : '对方未开启远程协助',
              onPressed: remoteOk
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RemoteDesktopPage(prefill: peer),
                        ),
                      );
                    }
                  : null,
            ),
          ),
        );
      case TagTreeNode(:final label, :final children):
        final users = _collectUsersFromNode(TagTreeNode(label: label, children: children));
        return _TagExpansionTile(
          label: label,
          users: users,
          children: children,
          session: session,
          dropEnabled: _dropEnabled,
          onDropTag: (users, d) => _onDropTag(context, session, users, d),
          buildChild: (node) => _buildNode(context, session, node),
        );
    }
  }

  /// 收集标签节点下的所有用户
  List<DiscoveredPeer> _collectUsersFromNode(UserTreeNode node) {
    final users = <DiscoveredPeer>[];
    
    void traverse(UserTreeNode n) {
      switch (n) {
        case UserTreeLeaf(:final peer):
          users.add(peer);
        case TagTreeNode(:final children):
          for (final child in children) {
            traverse(child);
          }
      }
    }
    
    traverse(node);
    return users;
  }

  /// 树形展开的标签组件，避免DropTarget嵌套
  Widget _TagExpansionTile({
    required String label,
    required List<DiscoveredPeer> users,
    required List<UserTreeNode> children,
    required AppSession session,
    required bool dropEnabled,
    required void Function(List<DiscoveredPeer> users, DropDoneDetails details) onDropTag,
    required Widget Function(UserTreeNode node) buildChild,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: _TagExpansionTileStateful(
        label: label,
        users: users,
        children: children,
        dropEnabled: dropEnabled,
        onDropTag: onDropTag,
        buildChild: buildChild,
      ),
    );
  }

  /// 处理标签拖拽事件：向标签下所有用户发送文件
  Future<void> _onDropTag(
    BuildContext context,
    AppSession session,
    List<DiscoveredPeer> users,
    DropDoneDetails d,
  ) async {
    final paths = AppSession.pathsFromDropDetails(d);
    if (paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未识别到本地文件路径')),
      );
      return;
    }
    
    final msg = await _askMessage(context) ?? '';
    if (!context.mounted) return;

    // 显示批量传输对话框
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('批量发送到 ${users.length} 个用户'),
        content: Text(
          '确认向「${users.first.tags.first}」标签下的 ${users.length} 个用户发送 ${paths.length} 个文件？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认发送'),
          ),
        ],
      ),
    );

    if (result != true || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                '正在向 ${users.length} 个用户发送文件…',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    try {
      // 使用顺序发送避免并发问题
      int successCount = 0;
      int failCount = 0;
      
      for (final peer in users) {
        try {
          await session.sendToPeer(
            filePaths: paths,
            peerId: peer.peerId,
            message: msg,
          );
          successCount++;
        } catch (e) {
          failCount++;
          debugPrint('向用户 ${peer.nickname} 发送失败: $e');
        }
        
        // 添加小延迟避免过快发送
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (!context.mounted) return;
      
      Navigator.of(context, rootNavigator: true).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '批量发送完成: $successCount 成功, $failCount 失败',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    final forest = buildUserForest(session.peersById.values.toList());
    final recentTransfers = session.transferLog.reversed.take(5).toList();

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.person_pin_rounded,
                      size: 22,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '我的信息',
                      style: _homeSectionTitleStyle(context),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(_profileLine(session)),
              ],
            ),
          ),
        ),
        if (session.lastError != null) ...[
          const SizedBox(height: 8),
          MaterialBanner(
            content: Text(session.lastError!),
            actions: [
              TextButton(
                onPressed: session.clearLastError,
                child: const Text('关闭'),
              ),
              TextButton(
                onPressed: () {
                  session.clearLastError();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TroubleshootingPage(),
                    ),
                  );
                },
                child: const Text('查看帮助'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _sectionTitleRow(
          context,
          icon: Icons.auto_awesome_motion_rounded,
          label: '传输进度',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: recentTransfers.isEmpty
                ? Text(
                    '暂无传输任务',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...recentTransfers.map((t) => _progressTile(context, t)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: session.clearTransferLog,
                          child: const Text('清空进度记录'),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          initiallyExpanded: true,
          title: Row(
            children: [
              Icon(
                Icons.groups_rounded,
                size: 22,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '其它用户',
                  style: _homeSectionTitleStyle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          subtitle: Text(
            '按标签分组；拖文件到某一用户即可发送',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          children: [
            if (session.discoverySupported)
              ListTile(
                dense: true,
                title: const Text('局域网发现'),
                subtitle: Text(
                  session.lanBroadcastActive
                      ? '正在尝试发现同一网络中的其他电脑。'
                      : '当前未能使用辅助发现（例如端口被占用），若列表为空请检查是否在同一 Wi‑Fi。',
                ),
              )
            else
              const ListTile(
                title: Text('当前设备'),
                subtitle: Text('此平台不展示自动发现列表。'),
              ),
            if (forest.isEmpty)
              const ListTile(
                title: Text('暂无其他用户'),
                subtitle: Text(
                  '请确认对方已打开本应用，且双方在同一网络；必要时在系统防火墙中允许本应用联网。',
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: _buildTree(context, session, forest),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(
              Icons.inbox_rounded,
              size: 22,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '接收记录',
                style: _homeSectionTitleStyle(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: session.receiveLog.isEmpty
                  ? null
                  : () => _copyReceiveLog(context),
              child: const Text('复制'),
            ),
            TextButton(
              onPressed: session.receiveLog.isEmpty || kIsWeb
                  ? null
                  : () => _exportReceiveLogToFile(context),
              child: const Text('另存为…'),
            ),
            TextButton(
              onPressed: session.clearReceiveLog,
              child: const Text('清空'),
            ),
          ],
        ),
        if (session.receiveLog.isEmpty)
          const Text('暂无', style: TextStyle(color: Colors.black54))
        else
          ...session.receiveLog.reversed.map(
            (e) => _receiveEventCard(context, session, e),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('X传输工具'),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'settings':
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  );
                case 'help':
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TroubleshootingPage(),
                    ),
                  );
                case 'about':
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const AboutPage()),
                  );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'settings',
                child: _popupMenuRow(
                  context,
                  icon: Icons.settings_outlined,
                  label: '设置',
                ),
              ),
              PopupMenuItem<String>(
                value: 'help',
                child: _popupMenuRow(
                  context,
                  icon: Icons.help_outline_rounded,
                  label: '连接问题说明',
                ),
              ),
              PopupMenuItem<String>(
                value: 'about',
                child: _popupMenuRow(
                  context,
                  icon: Icons.info_outline_rounded,
                  label: '关于',
                ),
              ),
            ],
          ),
        ],
      ),
      body: DropTarget(
        enable: _dropEnabled,
        onDragDone: (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请把文件拖到某位用户那一行上发送')),
          );
        },
        child: body,
      ),
    );
  }

  String _shortTransferId(String id) =>
      id.length <= 8 ? id : '${id.substring(0, 8)}…';
}
