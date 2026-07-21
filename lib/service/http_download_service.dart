import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// 纯 Dart HTTP 下载服务 - 当 Python 不可用时作为回退方案
/// 支持抖音和小红书的视频/图片下载
class HttpDownloadService {
  static final HttpDownloadService instance = HttpDownloadService._();
  HttpDownloadService._();

  final http.Client _client = http.Client();

  String _douyinCookie = '';
  String _xhsCookie = '';

  static const String _pcUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36';
  static const String _douyinReferer = 'https://www.douyin.com/?recommend=1';
  static const String _xhsReferer = 'https://www.xiaohongshu.com/';

  void setDouyinCookie(String cookie) => _douyinCookie = cookie;
  void setXhsCookie(String cookie) => _xhsCookie = cookie;

  /// 下载抖音短链对应的视频
  Future<Map<String, dynamic>> downloadDouyinVideo(
      String url, String savePath) async {
    try {
      // 1. 跟踪重定向获取真实 URL
      final redirectResp = await _client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': _pcUA,
          'Cookie': _douyinCookie,
          'Referer': _douyinReferer,
        },
      ).timeout(const Duration(seconds: 30));

      final realUrl = redirectResp.request?.url.toString() ?? url;

      // 2. 提取 aweme_id
      final awemeId = _extractAwemeId(realUrl);
      if (awemeId.isEmpty) {
        return {'success': false, 'message': '无法提取视频ID: $realUrl'};
      }

      // 3. 获取页面内容提取视频 URL
      final pageResp = await _client.get(
        Uri.parse(realUrl),
        headers: {
          'User-Agent': _pcUA,
          'Cookie': _douyinCookie,
          'Referer': _douyinReferer,
        },
      ).timeout(const Duration(seconds: 30));

      final body = pageResp.body;

      // 4. 从页面 JSON 提取视频下载地址
      final videoUrl = _extractVideoUrlFromPage(body);
      if (videoUrl.isEmpty) {
        return {'success': false, 'message': '无法提取视频下载地址'};
      }

      // 5. 下载视频文件
      final result =
          await _downloadFile(videoUrl, savePath, 'douyin_$awemeId.mp4', {
        'User-Agent': _pcUA,
        'Cookie': _douyinCookie,
        'Referer': _douyinReferer,
      });

      if (result['success'] == true) {
        return {
          'success': true,
          'title': '抖音视频 $awemeId',
          'path': result['path'],
        };
      }
      return result;
    } catch (e) {
      return {'success': false, 'message': '下载失败: $e'};
    }
  }

  /// 下载小红书笔记图片
  Future<Map<String, dynamic>> downloadXhsNote(
      String url, String savePath) async {
    try {
      // 1. 解析短链
      final redirectResp = await _client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': _pcUA,
          'Cookie': _xhsCookie,
          'Referer': _xhsReferer,
        },
      ).timeout(const Duration(seconds: 30));

      final realUrl = redirectResp.request?.url.toString() ?? url;

      // 2. 获取页面内容
      final pageResp = await _client.get(
        Uri.parse(realUrl),
        headers: {
          'User-Agent': _pcUA,
          'Cookie': _xhsCookie,
          'Referer': _xhsReferer,
        },
      ).timeout(const Duration(seconds: 30));

      final body = pageResp.body;

      // 3. 提取初始状态 JSON
      final stateData = _extractXhsInitialState(body);
      if (stateData.isEmpty) {
        return {'success': false, 'message': '无法提取笔记数据'};
      }

      final noteData = stateData;
      final title = noteData['title']?.toString() ?? '小红书笔记';
      final images = noteData['imageList'] as List?;

      if (images != null && images.isNotEmpty) {
        // 下载图片
        final dir = Directory(savePath);
        await dir.create(recursive: true);

        int downloaded = 0;
        for (int i = 0; i < images.length; i++) {
          final img = images[i] as Map<String, dynamic>?;
          if (img == null) continue;

          String imgUrl = '';
          if (img['urlDefault'] != null) {
            imgUrl = img['urlDefault'].toString();
          } else if (img['url'] != null) {
            imgUrl = img['url'].toString();
          }

          if (imgUrl.isEmpty) continue;

          final result = await _downloadFile(
            imgUrl,
            savePath,
            'xhs_${i + 1}.jpg',
            {
              'User-Agent': _pcUA,
              'Cookie': _xhsCookie,
              'Referer': _xhsReferer,
            },
          );

          if (result['success'] == true) downloaded++;
        }

        if (downloaded > 0) {
          return {
            'success': true,
            'title': title,
            'message': '下载完成: $downloaded/${images.length} 张图片',
          };
        }
        return {'success': false, 'message': '图片下载失败'};
      }

      // 尝试提取视频
      final videoUrl = _extractXhsVideoUrl(stateData);
      if (videoUrl.isNotEmpty) {
        final result = await _downloadFile(
          videoUrl,
          savePath,
          'xhs_video.mp4',
          {
            'User-Agent': _pcUA,
            'Cookie': _xhsCookie,
            'Referer': _xhsReferer,
          },
        );

        if (result['success'] == true) {
          return {
            'success': true,
            'title': title,
            'path': result['path'],
          };
        }
        return result;
      }

      return {'success': false, 'message': '未找到可下载的内容'};
    } catch (e) {
      return {'success': false, 'message': '下载失败: $e'};
    }
  }

  /// 通用文件下载
  Future<Map<String, dynamic>> _downloadFile(
    String url,
    String savePath,
    String filename,
    Map<String, String> headers,
  ) async {
    try {
      final dir = Directory(savePath);
      await dir.create(recursive: true);
      final filePath = '$savePath/$filename';

      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(headers);

      final response = await _client.send(request).timeout(
            const Duration(seconds: 120),
          );

      if (response.statusCode != 200 && response.statusCode != 206) {
        return {
          'success': false,
          'message': '下载失败: HTTP ${response.statusCode}',
        };
      }

      final file = File(filePath);
      final sink = file.openWrite();

      await response.stream.forEach((chunk) {
        sink.add(chunk);
      });

      await sink.flush();
      await sink.close();

      final fileSize = await file.length();
      return {
        'success': true,
        'path': filePath,
        'size': fileSize,
      };
    } catch (e) {
      return {'success': false, 'message': '文件下载失败: $e'};
    }
  }

  /// 从抖音 URL 提取 aweme_id
  String _extractAwemeId(String url) {
    // 标准格式: /video/1234567890123456789
    final match = RegExp(r'/(?:video|note|slides)/(\d{19})').firstMatch(url);
    if (match != null) return match.group(1)!;

    // modal_id 参数
    final modalMatch = RegExp(r'modal_id=(\d{19})').firstMatch(url);
    if (modalMatch != null) return modalMatch.group(1)!;

    // 19位数字
    final numMatch = RegExp(r'\b(\d{19})\b').firstMatch(url);
    if (numMatch != null) return numMatch.group(1)!;

    return '';
  }

  /// 从抖音页面提取视频 URL
  String _extractVideoUrlFromPage(String html) {
    // 尝试多种模式提取视频 URL
    final patterns = [
      RegExp(r'"playAddr"\s*:\s*"([^"]+)"'),
      RegExp(r'"play_addr"\s*:\s*\{[^}]*"url_list"\s*:\s*\["([^"]+)"'),
      RegExp(r'https?://[^"]*\.mp4[^"]*'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) {
        String url = match.group(1) ?? match.group(0) ?? '';
        url = url.replaceAll(r'\u002F', '/').replaceAll(r'\/', '/');
        if (url.contains('.mp4') || url.contains('play')) {
          return url;
        }
      }
    }
    return '';
  }

  /// 从小红书页面提取初始状态
  Map<String, dynamic> _extractXhsInitialState(String html) {
    // 查找 window.__INITIAL_STATE__
    final patterns = [
      RegExp(r'window\.__INITIAL_STATE__\s*=\s*(\{.+?\})\s*</script>',
          dotAll: true),
      RegExp(r'window\.__INITIAL_STATE__\s*=\s*(\{.+?\})\s*$', dotAll: true),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) {
        try {
          String jsonStr = match.group(1)!;
          // 替换 undefined 为 null
          jsonStr = jsonStr.replaceAll(RegExp(r':\s*undefined'), ': null');
          return jsonDecode(jsonStr) as Map<String, dynamic>;
        } catch (e) {
          // JSON 解析失败，继续尝试其他模式
        }
      }
    }

    // 尝试从 script 标签中提取
    final scriptPattern = RegExp(r'<script[^>]*>(.*?)</script>', dotAll: true);
    final scripts = scriptPattern.allMatches(html).toList();
    for (final script in scripts.reversed) {
      final content = script.group(1) ?? '';
      if (content.contains('__INITIAL_STATE__')) {
        try {
          final stateMatch =
              RegExp(r'__INITIAL_STATE__\s*=\s*(\{.+?\})\s*;?$', dotAll: true)
                  .firstMatch(content);
          if (stateMatch != null) {
            String jsonStr = stateMatch.group(1)!;
            jsonStr = jsonStr.replaceAll(RegExp(r':\s*undefined'), ': null');
            return jsonDecode(jsonStr) as Map<String, dynamic>;
          }
        } catch (e) {
          // 继续尝试
        }
      }
    }

    return {};
  }

  /// 从小红书数据中提取视频 URL
  String _extractXhsVideoUrl(Map<String, dynamic> data) {
    // 尝试从不同路径提取视频
    final paths = [
      ['noteData', 'video', 'media', 'stream', 'h264'],
      ['noteData', 'video', 'media', 'stream', 'h265'],
      ['noteData', 'video', 'url'],
    ];

    for (final path in paths) {
      dynamic current = data;
      for (final key in path) {
        if (current is Map) {
          current = current[key];
        } else {
          current = null;
          break;
        }
      }

      if (current is List && current.isNotEmpty) {
        final videoInfo = current[0] as Map<String, dynamic>?;
        if (videoInfo != null && videoInfo['masterUrl'] != null) {
          return videoInfo['masterUrl'].toString();
        }
      } else if (current is String && current.isNotEmpty) {
        return current;
      }
    }

    return '';
  }

  void dispose() {
    _client.close();
  }
}
