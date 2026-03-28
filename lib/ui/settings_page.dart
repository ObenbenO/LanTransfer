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
  final _store = SettingsStore();
  bool _remoteHostEnabled = false;
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
    _remoteHostEnabled = await _store.remoteDesktopHostEnabled;
    _receivePath = await _store.receivePath;
    setState(() {});
  }

  @override
  void dispose() {
    _nick.dispose();
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
    await _store.setRemoteDesktopHostEnabled(_remoteHostEnabled);
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
            '分组标签（如会场、区域）',
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
            title: const Text('接收文件保存位置'),
            subtitle: Text(_receivePath ?? '未选择'),
            trailing: FilledButton(
              onPressed: _pickDir,
              child: const Text('选择文件夹'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
            child: Text(
              '请选择一个已存在的文件夹；保存时会检查是否可写入。',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(height: 24),
          SwitchListTile(
            title: const Text('允许其他人远程控制本电脑'),
            subtitle: const Text(
              '开启后，本应用启动时会自动准备好远程协助；同一局域网内的其他用户可直接连接，无需再输入密码。'
              '关闭后，他人无法远程连接本机。',
            ),
            value: _remoteHostEnabled,
            onChanged: (v) => setState(() => _remoteHostEnabled = v),
          ),
          ListenableBuilder(
            listenable: context.read<AppSession>(),
            builder: (context, _) {
              final p = context.read<AppSession>().remoteDesktopAdvertisedPort;
              if (p <= 0) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: Text(
                  '当前远程协助端口：$p',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            },
          ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('连接问题说明'),
            subtitle: const Text('收不到文件、防火墙等常见情况'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TroubleshootingPage(),
                ),
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
