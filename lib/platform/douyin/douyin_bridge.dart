import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../bridge_base.dart';
import '../../service/native_download_service.dart';
import '../../service/douyin_api_service.dart';

/// 抖音下载桥接层 — 全平台统一调用 NativeDownloadService
class DouyinBridge {
  static final NativeDownloadService _native = NativeDownloadService.instance;
  static final DouyinApiService _api = DouyinApiService.instance;

  /// 解析抖音链接并下载
  static Future<Map<String, dynamic>> parseAndDownload(
      String link, String savePath) async {
    return BridgeBase.executeTask(
      link: link,
      savePath: savePath,
      source: 'douyin',
      type: 'video',
      execute: () async {
        final result = await _native.downloadDouyinVideo(link, savePath);
        if (result['success'] == true) {
          final path = result['path']?.toString() ?? '';
          final filePath = await _findDownloadedFile(path, savePath);
          if (filePath != null) {
            final file = File(filePath);
            if (await file.exists()) result['path'] = filePath;
          }
        }
        return result;
      },
    );
  }

  static Future<String?> _findDownloadedFile(
      String filePath, String savePath) async {
    if (filePath.isNotEmpty) {
      final file = File(filePath);
      if (await file.exists()) return filePath;
    }
    try {
      final dir = Directory(savePath);
      if (await dir.exists()) {
        final files = await dir.list().where((e) => e is File).toList();
        if (files.isNotEmpty) {
          files.sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );
          return files.first.path;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 检测链接信息 — 解析作者和合集
  static Future<String> detectLinkInfo(String link) async {
    return await _api.detectLinkInfo(link);
  }

  /// 列出账号作品（不下载）
  static Future<String> listAccountWorks(String secUid) async {
    return await _api.listAccountWorks(secUid);
  }

  /// 批量下载账号
  static Future<Map<String, dynamic>> batchDownloadAccount(
      String link, String savePath) async {
    // 先检测链接获取 sec_uid
    final infoStr = await _api.detectLinkInfo(link);
    final info = jsonDecode(infoStr) as Map<String, dynamic>;
    if (info['success'] != true) {
      return {'success': false, 'message': info['message']};
    }
    final author = info['author'] as Map<String, dynamic>?;
    if (author == null || author['sec_uid'] == null) {
      return {'success': false, 'message': '无法获取作者信息'};
    }
    final secUid = author['sec_uid'] as String;
    final nickname = author['nickname'] as String;
    return BridgeBase.executeTask(
      link: link,
      savePath: savePath,
      source: 'douyin',
      type: 'batch_account',
      execute: () async =>
          await _api.batchDownloadAccount(secUid, nickname, savePath),
    );
  }

  /// 批量下载合集
  static Future<Map<String, dynamic>> batchDownloadMix(
      String link, String savePath) async {
    final infoStr = await _api.detectLinkInfo(link);
    final info = jsonDecode(infoStr) as Map<String, dynamic>;
    if (info['success'] != true) {
      return {'success': false, 'message': info['message']};
    }
    final mix = info['mix'] as Map<String, dynamic>?;
    if (mix == null) {
      return {'success': false, 'message': '该作品不属于任何合集'};
    }
    return BridgeBase.executeTask(
      link: link,
      savePath: savePath,
      source: 'douyin',
      type: 'batch_mix',
      execute: () async => await _api.batchDownloadMix(
          mix['mix_id'] as String, mix['mix_name'] as String, savePath),
    );
  }

  /// 列出收藏夹
  static Future<String> listCollectFolders() async {
    return await _api.listCollectFolders();
  }

  /// 采集评论
  static Future<Map<String, dynamic>> scrapeComments(
      String link, String savePath) async {
    return BridgeBase.executeTask(
      link: link,
      savePath: savePath,
      source: 'douyin',
      type: 'comments',
      execute: () async => await _api.scrapeComments(link, savePath),
    );
  }

  /// 获取数据统计
  static Future<String> getDataStats(String link) async {
    return await _api.getDataStats(link);
  }

  /// 批量下载多个链接
  static Future<Map<String, dynamic>> batchDownloadLinks(
      List<String> links, String savePath) async {
    return BridgeBase.executeTask(
      link: links.first,
      savePath: savePath,
      source: 'douyin',
      type: 'batch',
      execute: () async => await _api.batchDownloadLinks(links, savePath),
    );
  }

  /// 重新下载
  static Future<Map<String, dynamic>> redownloadFromHistory(
      String savePath) async {
    return BridgeBase.executeTask(
      link: 'redownload',
      savePath: savePath,
      source: 'douyin',
      type: 'redownload',
      execute: () async => await _api.redownloadFromHistory(savePath),
    );
  }

  /// 设置 Cookie
  static void setCookie(String cookie) => _native.setDouyinCookie(cookie);

  /// 暂停任务
  static void pauseTask(String taskId) {}

  /// 恢复任务
  static void resumeTask(String taskId) {}
}
