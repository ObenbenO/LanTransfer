import 'package:flutter/material.dart';

/// 与 `pubspec.yaml` 中 version 保持同步。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const appVersion = '1.0.0+1';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.hub_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('内网传输工具', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          SelectableText(
            '版本 $appVersion',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Text('这是做什么的？', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          const Text(
            '在会议室或同一 Wi‑Fi 下，方便地把文件发给同事，也可以在对方允许时远程查看或操作对方电脑（远程协助）。'
            '更详细的步骤见应用附带的《使用说明》。',
          ),
        ],
      ),
    );
  }
}
