import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/app_session.dart';
import '../services/network_diagnostics.dart';

/// 清单 4.5：常见错误与权限说明。
class TroubleshootingPage extends StatelessWidget {
  const TroubleshootingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('网络与权限')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('客观判定（推荐）', style: t.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '没有单一命令能自动给出 100% 根因；最可靠的是：两台各复制一份下方「诊断报告」，'
                    '再用 Wireshark 在双方 Wi‑Fi 网卡上过滤 udp.port == 45678，对照 OUT/IN 是否出现。',
                    style: t.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () {
                      final session = context.read<AppSession>();
                      final text = collectNetworkDiagnostics(session);
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制诊断报告到剪贴板')),
                      );
                    },
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('复制网络诊断报告'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('接收目录', style: t.titleMedium),
          const SizedBox(height: 8),
          Text(
            '在设置中选择「已存在」的文件夹；保存时会由 Rust 校验路径。'
            '若提示目录不存在或无权限，请更换路径或以管理员身份运行（视系统而定）。',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 24),
          Text('局域网发现（Bonsoir / mDNS）', style: t.titleMedium),
          const SizedBox(height: 8),
          Text(
            '• 确保各电脑在同一局域网，且未开启 AP「客户端隔离」或访客 Wi‑Fi。\n'
            '• 本应用同时使用 Bonsoir（mDNS）与 UDP 广播（端口 45678，含各网卡的子网广播地址）。\n'
            '• Windows：若 Wi‑Fi 被设为「公用网络」，此前仅「专用/域」的防火墙规则不会生效；'
            '请在启动时的防火墙向导中再次「授权并添加规则」（脚本会将规则设为任意配置文件），'
            '或在「设置 → 网络和 Internet」中将当前网络改为「专用网络」。\n'
            '• 首次监听时若弹出「是否允许访问网络」，请选择允许。\n'
            '• 若仍被拦，在防火墙中为实际运行的 **exe** 放行入站 TCP/UDP（含动态文件端口与 UDP 45678）。\n'
            '• 若列表始终为空，可先在设置中开启「单机调试（环回对端）」验证发送流程。\n'
            '• Python 探针能互相收到，但本程序不行时：请看首页「设备 ID」。'
            '若两台电脑的设备 ID 完全一致，说明共用了同一份 Rust 缓存（如复制虚拟机、同步了 AppData），'
            '程序会把对方误判为自己并丢弃；请在两台机器上分别删除应用数据目录中的 xtransfer_device_id 文件后重启（路径因安装而异，一般在「应用支持 / Roaming」下与包名相关的文件夹内）。',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 24),
          Text('文件发送失败', style: t.titleMedium),
          const SizedBox(height: 8),
          Text(
            '发送前对端须已启动本应用并完成文件服务监听；'
            '对端「文件端口」须与 Bonsoir 广播一致。'
            '若提示 TCP 连接失败，请确认防火墙未拦截该端口。',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 24),
          Text('远程桌面', style: t.titleMedium),
          const SizedBox(height: 8),
          Text(
            '被控端需先在本机启动 Rust 侧 remote_host（后续可在界面中提供入口）；'
            '控制端填写的端口与令牌须与被控端一致。'
            '画面与键鼠需系统辅助功能 / 屏幕录制权限时，请按操作系统提示授权。',
            style: t.bodyMedium,
          ),
        ],
      ),
    );
  }
}
