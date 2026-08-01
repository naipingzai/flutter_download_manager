import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 存储服务 — 封装应用目录访问
///
/// 业务代码禁止直接使用 dart:io + path_provider，
/// 必须通过本服务获取应用目录。
class StorageService {
  StorageService._();

  static final StorageService _instance = StorageService._();
  static StorageService get instance => _instance;

  /// 应用文档根目录
  Future<Directory> get appDocumentsDirectory async {
    return getApplicationDocumentsDirectory();
  }

  /// 应用临时目录
  Future<Directory> get tempDirectory async {
    return getTemporaryDirectory();
  }

  /// 下载根目录（包含 DyDownload/XhsDownload）
  Future<Directory> downloadsDirectory() async {
    final root = await appDocumentsDirectory;
    final dir = Directory('${root.path}/downloads');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 平台下载子目录
  Future<Directory> platformDownloadsDirectory(String platformId) async {
    final root = await downloadsDirectory();
    final name = switch (platformId) {
      'xhs' => 'XhsDownload',
      'kuaishou' => 'KsDownload',
      _ => 'DyDownload',
    };
    final dir = Directory('${root.path}/$name');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 应用数据目录（数据库、Cookie 等持久化文件）
  Future<Directory> dataDirectory() async {
    final root = await appDocumentsDirectory;
    final dir = Directory('${root.path}/app_data');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 清理指定目录的所有文件
  Future<int> cleanDirectory(Directory dir) async {
    if (!await dir.exists()) return 0;
    int count = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        await entity.delete();
        count++;
      }
    }
    await dir.delete(recursive: true);
    return count;
  }

  /// 清理所有下载文件（按平台目录）
  Future<int> cleanAllDownloads() async {
    int total = 0;
    for (final id in ['douyin', 'xhs', 'kuaishou']) {
      final dir = await platformDownloadsDirectory(id);
      total += await cleanDirectory(dir);
    }
    return total;
  }
}
