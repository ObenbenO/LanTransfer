import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app/app_session.dart';
import 'settings_store.dart';

bool _deferredThisProcess = false;

const _ruleProgramIn = 'X传输-主程序-入';

Future<bool> _programFirewallRuleExists() async {
  if (!Platform.isWindows) return false;
  final r = await Process.run('netsh', [
    'advfirewall',
    'firewall',
    'show',
    'rule',
    'name=$_ruleProgramIn',
  ]);
  return r.exitCode == 0;
}

Future<void> _markOkIfRulesPresent(SettingsStore store) async {
  if (await _programFirewallRuleExists()) {
    await store.setFirewallSetupV1Ok(true);
  }
}

String _buildSetupScript(String exePath) {
  final escaped = exePath.replaceAll("'", "''");
  return '''
\$ErrorActionPreference = 'SilentlyContinue'
\$exe = '$escaped'

# 旧版规则多为 private,domain，在 Wi‑Fi 被标成「公用网络」时不生效；升级为任意配置文件。
foreach (\$n in @("$_ruleProgramIn","X传输-主程序-出","X传输-mDNS-入","X传输-发现45678-入")) {
  netsh advfirewall firewall set rule name="\$n" new profile=any 2>\$null | Out-Null
}

\$null = netsh advfirewall firewall show rule name="$_ruleProgramIn" 2>\$null
if (\$LASTEXITCODE -ne 0) {
  netsh advfirewall firewall add rule name="$_ruleProgramIn" dir=in action=allow program="\$exe" enable=yes profile=any
}

\$null = netsh advfirewall firewall show rule name="X传输-主程序-出" 2>\$null
if (\$LASTEXITCODE -ne 0) {
  netsh advfirewall firewall add rule name="X传输-主程序-出" dir=out action=allow program="\$exe" enable=yes profile=any
}

\$null = netsh advfirewall firewall show rule name="X传输-mDNS-入" 2>\$null
if (\$LASTEXITCODE -ne 0) {
  netsh advfirewall firewall add rule name="X传输-mDNS-入" dir=in action=allow protocol=UDP localport=5353 profile=any
}

\$null = netsh advfirewall firewall show rule name="X传输-发现45678-入" 2>\$null
if (\$LASTEXITCODE -ne 0) {
  netsh advfirewall firewall add rule name="X传输-发现45678-入" dir=in action=allow protocol=UDP localport=45678 profile=any
}
''';
}

Future<void> _runElevatedSetupScript(String exePath) async {
  final dir = await getTemporaryDirectory();
  final scriptFile = File(p.join(dir.path, 'xtransfer_fw_setup_v1.ps1'));
  await scriptFile.writeAsString(_buildSetupScript(exePath), encoding: utf8);

  final scriptArg = scriptFile.path.replaceAll("'", "''");
  await Process.run('powershell', [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    "Start-Process powershell -Verb RunAs -Wait "
        "-ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','$scriptArg')",
  ]);
}

/// Windows：若尚未配置，在启动后尝试静默识别已有规则；必要时弹出**单一**对话框，引导一次 UAC 添加规则。
Future<void> maybeShowWindowsFirewallSetup(
  BuildContext context,
  AppSession session, {
  ScaffoldMessengerState? messenger,
}) async {
  if (!Platform.isWindows) return;
  if (session.dryRunForTest || session.skipWindowsFirewallPrompt) return;

  final store = SettingsStore();
  if (await store.firewallSetupV1Ok) return;

  await _markOkIfRulesPresent(store);
  if (await store.firewallSetupV1Ok) return;

  if (_deferredThisProcess) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('局域网发现准备'),
        content: const Text(
          '为在局域网内自动发现其他设备，建议在首次使用时通过 Windows 防火墙授权本程序（仅需一次，随后会弹出系统 UAC）。\n\n'
          '若使用安装包部署，也可由安装程序预先写入规则，则不会再出现此提示。',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await store.setFirewallSetupV1Ok(true);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('不再提示'),
          ),
          TextButton(
            onPressed: () {
              _deferredThisProcess = true;
              Navigator.of(ctx).pop();
            },
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              final exe = Platform.resolvedExecutable.replaceAll('/', r'\');
              await _runElevatedSetupScript(exe);
              final exists = await _programFirewallRuleExists();
              if (exists) {
                await store.setFirewallSetupV1Ok(true);
              }
              if (ctx.mounted) nav.pop();
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(
                    exists
                        ? '防火墙规则已就绪'
                        : '未能确认规则已添加（可能已取消 UAC）；可稍后重试',
                  ),
                ),
              );
            },
            child: const Text('授权并添加规则'),
          ),
        ],
      );
    },
  );
}
