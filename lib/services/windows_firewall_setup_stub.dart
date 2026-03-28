import 'package:flutter/material.dart';

import '../app/app_session.dart';

/// 非 IO 平台无操作。
Future<void> maybeShowWindowsFirewallSetup(
  BuildContext context,
  AppSession session, {
  ScaffoldMessengerState? messenger,
}) async {}
