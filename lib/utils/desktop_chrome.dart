import 'package:flutter/foundation.dart';

/// 是否为本机桌面端（Windows / Linux / macOS），不含 Web 与移动平台。
bool get isDesktopNative {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
      return true;
    default:
      return false;
  }
}
