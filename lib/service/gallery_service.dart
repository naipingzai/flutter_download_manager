import 'dart:io';
import 'package:gal/gal.dart';

/// 相册保存服务 — 跨平台保存媒体文件到系统相册
/// 支持 iOS (PhotoKit)、Android (MediaStore)、Linux (无操作)
class GalleryService {
  static final GalleryService instance = GalleryService._();
  GalleryService._();

  /// 请求相册访问权限
  Future<bool> requestPermission() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      // 桌面平台不需要相册权限，文件保存在 Downloads 目录
      return true;
    }
    try {
      await Gal.requestAccess();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 保存文件到相册
  /// 自动判断图片/视频，支持 JPG/PNG/WEBP/MP4 格式
  Future<bool> saveToGallery(String filePath, {String? album}) async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      // 桌面平台: 文件已经在 Downloads 目录，无需额外操作
      return true;
    }

    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final ext = filePath.toLowerCase().split('.').last;
      final isVideo =
          ext == 'mp4' || ext == 'mov' || ext == 'avi' || ext == 'mkv';

      if (isVideo) {
        await Gal.putVideo(filePath, album: album);
      } else {
        await Gal.putImage(filePath, album: album);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 批量保存多个文件到相册
  Future<int> saveAllToGallery(List<String> filePaths, {String? album}) async {
    int count = 0;
    for (final path in filePaths) {
      if (await saveToGallery(path, album: album)) count++;
    }
    return count;
  }
}
