import 'dart:io';
import 'package:gal/gal.dart';

/// 相册保存服务 — 跨平台保存媒体文件到系统相册
/// iOS: PhotoKit (gal 插件)
/// Android: MediaStore (gal 插件)
/// Linux/桌面: 文件已在下载目录，跳过
class GalleryService {
  static final GalleryService instance = GalleryService._();
  GalleryService._();

  bool _permissionGranted = false;

  /// 请求相册写入权限
  /// iOS: 必须在 Info.plist 中配置 NSPhotoLibraryAddUsageDescription
  /// Android: gal 自动处理 MediaStore 权限
  Future<bool> requestPermission() async {
    if (_permissionGranted) return true;
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return true;
    }
    try {
      // gal 的 requestAccess 会弹出系统权限对话框
      await Gal.requestAccess();
      _permissionGranted = true;
      return true;
    } catch (e) {
      // 权限被拒绝或出错
      print('[Gallery] Permission request failed: $e');
      return false;
    }
  }

  /// 保存文件到系统相册
  /// [filePath]: 完整文件路径
  /// [album]: 相册名称（可选，iOS/Android 均支持）
  /// 返回 true 表示保存成功
  Future<bool> saveToGallery(String filePath, {String? album}) async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return true; // 桌面平台无需相册操作
    }

    final file = File(filePath);
    if (!await file.exists()) {
      print('[Gallery] File not found: $filePath');
      return false;
    }

    try {
      final ext = filePath.toLowerCase().split('.').last;
      final isVideo =
          ext == 'mp4' || ext == 'mov' || ext == 'avi' || ext == 'mkv';

      if (isVideo) {
        await Gal.putVideo(filePath, album: album);
      } else {
        await Gal.putImage(filePath, album: album);
      }
      print('[Gallery] Saved to gallery: $filePath');
      return true;
    } catch (e) {
      print('[Gallery] Save failed for $filePath: $e');
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
