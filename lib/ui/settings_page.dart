import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_session.dart';
import '../services/settings_store.dart';
import 'troubleshooting_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _nick = TextEditingController();
  final _tags = <TextEditingController>[];
  final _remoteTok = TextEditingController(text: 'dev-token');
  final _store = SettingsStore();
  bool _loopback = false;
  String? _receivePath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _nick.text = await _store.nickname;
    final t = await _store.tags;
    _tags.clear();
    for (final s in t) {
      _tags.add(TextEditingController(text: s));
    }
    if (_tags.isEmpty) {
      _tags.add(TextEditingController());
    }
    _loopback = await _store.debugLoopback;
    _receivePath = await _store.receivePath;
    setState(() {});
  }

  @override
  void dispose() {
    _nick.dispose();
    _remoteTok.dispose();
    for (final c in _tags) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDir() async {
    final d = await getDirectoryPath(confirmButtonText: '选择');
    if (d != null) setState(() => _receivePath = d);
  }

  Future<void> _save() async {
    final tags = _tags
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    await _store.saveProfile(nickname: _nick.text.trim(), tags: tags);
    await _store.saveReceivePath(_receivePath);
    await _store.setDebugLoopback(_loopback);
    if (!mounted) return;
    await context.read<AppSession>().reloadAfterSettingsSave();
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已保存')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _nick,
            decoration: const InputDecoration(
              labelText: '昵称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '标签（会场 / 片区 / …）',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...List.generate(_tags.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tags[i],
                      decoration: InputDecoration(
                        labelText: '标签 ${i + 1}',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _tags[i].dispose();
                        _tags.removeAt(i);
                        if (_tags.isEmpty) {
                          _tags.add(TextEditingController());
                        }
                      });
                    },
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
            );
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  setState(() => _tags.add(TextEditingController())),
              icon: const Icon(Icons.add),
              label: const Text('添加标签'),
            ),
          ),
          const Divider(height: 32),
          ListTile(
            title: const Text('默认接收目录'),
            subtitle: Text(_receivePath ?? '未选择'),
            trailing: FilledButton(
              onPressed: _pickDir,
              child: const Text('选择文件夹'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
            child: Text(
              '须选择已存在的文件夹；保存并应用时由 Rust 校验可写性。',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('网络与权限说明'),
            subtitle: const Text('防火墙、mDNS、接收目录常见问题'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TroubleshootingPage(),
                ),
              );
            },
          ),
          SwitchListTile(
            title: const Text('单机调试（环回对端）'),
            subtitle: const Text('注册 127.0.0.1 对端，便于自发自收联调'),
            value: _loopback,
            onChanged: (v) => setState(() => _loopback = v),
          ),
          const Divider(height: 32),
          Text(
            '远程桌面 · 本机被控（占位）',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _remoteTok,
            decoration: const InputDecoration(
              labelText: '会话令牌（与控制端一致）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () async {
                  final session = context.read<AppSession>();
                  try {
                    await session.startRemoteHost(
                      token: _remoteTok.text.trim(),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '已启动远控宿主，广播 rport=${session.remoteDesktopAdvertisedPort}',
                        ),
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('启动失败: $e')));
                  }
                },
                child: const Text('启动本机远控端口'),
              ),
              OutlinedButton(
                onPressed: () async {
                  final session = context.read<AppSession>();
                  try {
                    await session.stopRemoteHost();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('已停止远控宿主')));
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('停止失败: $e')));
                  }
                },
                child: const Text('停止'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: context.read<AppSession>(),
            builder: (context, _) {
              final p = context.read<AppSession>().remoteDesktopAdvertisedPort;
              return Text(
                '当前 Bonsoir 中的 rport: $p',
                style: Theme.of(context).textTheme.bodySmall,
              );
            },
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('保存并应用')),
        ],
      ),
    );
  }
}
