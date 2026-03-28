import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本地偏好（身份、接收目录、调试开关）。
class SettingsStore {
  static const _kNickname = 'xtransfer_nickname';
  static const _kTags = 'xtransfer_tags_json';
  static const _kReceivePath = 'xtransfer_receive_path';
  static const _kDebugLoopback = 'xtransfer_debug_loopback';
  static const _kFirewallSetupV1Ok = 'xtransfer_firewall_setup_v1_ok';

  Future<String> get nickname async =>
      (await SharedPreferences.getInstance()).getString(_kNickname) ?? '';

  Future<List<String>> get tags async {
    final raw =
        (await SharedPreferences.getInstance()).getString(_kTags) ?? '[]';
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> get receivePath async =>
      (await SharedPreferences.getInstance()).getString(_kReceivePath);

  Future<bool> get debugLoopback async =>
      (await SharedPreferences.getInstance()).getBool(_kDebugLoopback) ?? false;

  Future<void> saveProfile({
    required String nickname,
    required List<String> tags,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kNickname, nickname);
    await p.setString(_kTags, jsonEncode(tags));
  }

  Future<void> saveReceivePath(String? path) async {
    final p = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await p.remove(_kReceivePath);
    } else {
      await p.setString(_kReceivePath, path);
    }
  }

  Future<void> setDebugLoopback(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDebugLoopback, v);
  }

  /// 已完成或永久跳过 Windows 防火墙一键配置，启动时不再弹窗。
  Future<bool> get firewallSetupV1Ok async =>
      (await SharedPreferences.getInstance()).getBool(_kFirewallSetupV1Ok) ??
      false;

  Future<void> setFirewallSetupV1Ok(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kFirewallSetupV1Ok, v);
  }
}
