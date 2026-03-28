import 'dart:io';

import 'package:file_selector/file_selector.dart';

Future<bool> exportTextFile(String suggestedName, String contents) async {
  final loc = await getSaveLocation(
    suggestedName: suggestedName,
    confirmButtonText: '保存',
  );
  if (loc == null) return false;
  await File(loc.path).writeAsString(contents);
  return true;
}
