import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/app_session.dart';
import '../files/export_text.dart';
import '../models/discovered_peer.dart';
import '../models/user_tree.dart';
import '../src/rust/api/types.dart';
import 'about_page.dart';
import 'remote_desktop_page.dart';
import 'settings_page.dart';
import 'troubleshooting_page.dart';
import 'widgets/user_drop_tile.dart';

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
    final buf = StringBuffer()..writeln('文件名\t发送方\t留言\ttimestamp_ms');
    for (final e in s.receiveLog) {
      buf.writeln(
        '${e.fileName}\t${e.senderPeerId}\t${e.message.replaceAll('\t', ' ')}\t${e.timestampMs}',
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
      buf.writeln('${e.fileName} | ${e.senderPeerId} | ${e.message}');
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
        return Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 4),
          child: DropTarget(
            enable: _dropEnabled,
            onDragDone: (_) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请拖到「具体用户」行上发送；标签节点不接收文件')),
              );
            },
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(label),
              subtitle: const Text('请展开后，把文件拖到具体用户上'),
              children: children
                  .map((c) => _buildNode(context, session, c))
                  .toList(),
            ),
          ),
        );
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
                Text('我的信息', style: Theme.of(context).textTheme.titleSmall),
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
        Text('传输进度', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
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
          title: Text('其它用户', style: Theme.of(context).textTheme.titleMedium),
          subtitle: const Text('按标签分组；拖文件到某一用户即可发送'),
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
            Text('接收记录', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
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
            (e) => ListTile(
              dense: true,
              title: Text(e.fileName),
              subtitle: Text('${e.senderPeerId} · ${e.message}'),
              trailing: Text(
                _shortTime(e.timestampMs.toInt()),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
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
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'settings', child: Text('设置')),
              PopupMenuItem(value: 'help', child: Text('连接问题说明')),
              PopupMenuItem(value: 'about', child: Text('关于')),
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

  String _shortTime(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
  }

  String _shortTransferId(String id) =>
      id.length <= 8 ? id : '${id.substring(0, 8)}…';
}
