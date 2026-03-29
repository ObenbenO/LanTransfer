import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// 根据文件名后缀选择「卡通感」配色与图标（圆角色块 + Material 图标）。
///
/// 不引入整张主题换肤，仅用于列表行左侧点缀。
@immutable
class CartoonFileIcon extends StatelessWidget {
  const CartoonFileIcon({
    super.key,
    required this.fileName,
    this.size = 44,
  });

  final String fileName;
  final double size;

  static String extensionOf(String fileName) {
    final base = p.basename(fileName);
    final lower = base.toLowerCase();
    if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
      return 'tgz';
    }
    if (lower.endsWith('.tar.bz2')) {
      return 'tbz2';
    }
    final dot = base.lastIndexOf('.');
    if (dot <= 0 || dot >= base.length - 1) {
      return '';
    }
    return base.substring(dot + 1).toLowerCase();
  }

  static (IconData icon, Color bg, Color fg) styleForExtension(String ext) {
    switch (ext) {
      case 'pdf':
        return (
          Icons.picture_as_pdf_rounded,
          const Color(0xFFFFCDD2),
          const Color(0xFFC62828),
        );
      case 'doc':
      case 'docx':
      case 'rtf':
        return (
          Icons.description_rounded,
          const Color(0xFFBBDEFB),
          const Color(0xFF1565C0),
        );
      case 'xls':
      case 'xlsx':
      case 'csv':
        return (
          Icons.table_chart_rounded,
          const Color(0xFFC8E6C9),
          const Color(0xFF2E7D32),
        );
      case 'ppt':
      case 'pptx':
        return (
          Icons.slideshow_rounded,
          const Color(0xFFFFE0B2),
          const Color(0xFFEF6C00),
        );
      case 'zip':
      case 'rar':
      case '7z':
      case 'tgz':
      case 'tbz2':
      case 'gz':
        return (
          Icons.folder_zip_rounded,
          const Color(0xFFFFF9C4),
          const Color(0xFFF9A825),
        );
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'ico':
      case 'svg':
        return (
          Icons.image_rounded,
          const Color(0xFFE1BEE7),
          const Color(0xFF7B1FA2),
        );
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case 'wmv':
        return (
          Icons.movie_rounded,
          const Color(0xFFD1C4E9),
          const Color(0xFF4527A0),
        );
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'ogg':
        return (
          Icons.audio_file_rounded,
          const Color(0xFFF8BBD0),
          const Color(0xFFC2185B),
        );
      case 'txt':
      case 'md':
      case 'log':
        return (
          Icons.article_rounded,
          const Color(0xFFECEFF1),
          const Color(0xFF546E7A),
        );
      case 'exe':
      case 'msi':
      case 'bat':
      case 'cmd':
        return (
          Icons.window_rounded,
          const Color(0xFFCFD8DC),
          const Color(0xFF37474F),
        );
      case 'apk':
        return (
          Icons.android_rounded,
          const Color(0xFFC8E6C9),
          const Color(0xFF1B5E20),
        );
      case 'js':
      case 'ts':
      case 'jsx':
      case 'tsx':
      case 'dart':
      case 'rs':
      case 'go':
      case 'py':
      case 'java':
      case 'c':
      case 'cpp':
      case 'h':
      case 'cs':
      case 'swift':
      case 'kt':
        return (
          Icons.code_rounded,
          const Color(0xFFB3E5FC),
          const Color(0xFF0277BD),
        );
      case 'html':
      case 'htm':
      case 'css':
        return (
          Icons.html_rounded,
          const Color(0xFFFFE0B2),
          const Color(0xFFE65100),
        );
      case 'json':
      case 'xml':
      case 'yaml':
      case 'yml':
      case 'toml':
        return (
          Icons.data_object_rounded,
          const Color(0xFFB2EBF2),
          const Color(0xFF00838F),
        );
      case 'proto':
        return (
          Icons.hub_rounded,
          const Color(0xFFD7CCC8),
          const Color(0xFF4E342E),
        );
      case 'lua':
        return (
          Icons.settings_suggest_rounded,
          const Color(0xFFB2DFDB),
          const Color(0xFF00695C),
        );
      default:
        return (
          Icons.insert_drive_file_rounded,
          const Color(0xFFE0E0E0),
          const Color(0xFF616161),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ext = extensionOf(fileName);
    final (icon, bg, fg) = styleForExtension(ext);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: fg.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: fg, size: size * 0.48),
    );
  }
}
