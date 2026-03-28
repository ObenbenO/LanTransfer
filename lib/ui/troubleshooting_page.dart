import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/app_session.dart';
import '../services/network_diagnostics.dart';

/// 面向普通用户的连接与权限说明。
class TroubleshootingPage extends StatelessWidget {
  const TroubleshootingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('连接问题说明')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('需要技术支持时', style: t.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '请在本页底部复制「简要诊断信息」，发给技术支持或同事对照。',
                    style: t.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () {
                      final session = context.read<AppSession>();
                      final text = collectNetworkDiagnostics(session);
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制到剪贴板')),
                      );
                    },
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('复制简要诊断信息'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('收不到别人发的文件', style: t.titleMedium),
          const SizedBox(height: 8),
          Text(
            '• 请确认双方连的是同一个 Wi‑Fi（或同一有线局域网）。\n'
            '• 在「设置」里选好「接收文件保存位置」，并点「保存并应用」。\n'
            '• Windows 若弹出防火墙询问，请选择「允许」。\n'
            '• 若仍不行，可把网络设为「专用网络」后再试。',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 24),
          Text('列表里看不到其他电脑', style: t.titleMedium),
          const SizedBox(height: 8),
          Text(
            '• 对方也需要打开本应用。\n'
            '• 部分路由器会开启「访客网络」或「设备隔离」，会导致互相看不到，请换到普通局域网或关闭该功能。\n'
            '• 若两台电脑曾复制过同一台机器的系统镜像，可能出现设备识别冲突，需分别清理本应用数据目录中的设备标识文件后重启（可向技术支持索要路径）。',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 24),
          Text('远程协助连不上', style: t.titleMedium),
          const SizedBox(height: 8),
          Text(
            '• 被协助的一方需要在「设置」中打开「允许其他人远程控制本电脑」。\n'
            '• 协助方在列表里点显示器图标；若该按钮为灰色，说明对方未开启远程协助。\n'
            '• 操作系统若询问屏幕录制、辅助功能等权限，请按提示允许。',
            style: t.bodyMedium,
          ),
        ],
      ),
    );
  }
}
