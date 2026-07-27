import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';

/// 相册保存服务 — iOS/Android 系统相册集成
/// iOS: PhotoKit (gal 插件)
/// Android: MediaStore (gal 插件)
class GalleryService {
  static final GalleryService instance = GalleryService._();
  GalleryService._();

  bool _permissionGranted = false;

  /// 请求相册写入权限
  /// iOS: 必须在 Info.plist 中配置 NSPhotoLibraryAddUsageDescription
  /// Android: gal 自动处理 MediaStore 权限
  Future<bool> requestPermission() async {
    if (_permissionGranted) return true;
    try {
      await Gal.requestAccess();
      _permissionGranted = true;
      return true;
    } catch (e) {
      debugPrint('[Gallery] Permission request failed: $e');
      return false;
    }
  }

  /// 保存文件到系统相册
  /// [filePath]: 完整文件路径
  /// [album]: 相册名称（可选，iOS/Android 均支持）
  Future<bool> saveToGallery(String filePath, {String? album}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[Gallery] File not found: $filePath');
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
      debugPrint('[Gallery] Saved to gallery: $filePath');
      return true;
    } catch (e) {
      debugPrint('[Gallery] Save failed for $filePath: $e');
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
