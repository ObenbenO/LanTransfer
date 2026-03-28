import 'package:flutter/material.dart';

/// 与 `pubspec.yaml` 中 version 保持同步，便于会议排障。
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
          Text('X传输工具', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          SelectableText(
            '版本 $appVersion\n'
            'Flutter + Rust（flutter_rust_bridge）\n'
            '局域网发现：Bonsoir（_localdesk._udp）',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Text('说明', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          const Text(
            '本应用用于会议场景下的文件互传与后续远程桌面扩展。'
            '若无法发现其他电脑，请检查是否在同一网段、防火墙是否放行 mDNS，'
            '并可在设置中开启「单机调试」做环回联调。',
          ),
        ],
      ),
    );
  }
}
