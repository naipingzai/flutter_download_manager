
import 'package:dio/dio.dart';

/// HTTP 降级方案 - 当 Python 不可用时（iOS/Web），使用 Dart dio 直接下载
class HttpFallback {
  static final HttpFallback _instance = HttpFallback._();
  static HttpFallback get instance => _instance;

  late Dio _dio;
  String _dyCookie = '';
  String _xhsCookie = '';

  HttpFallback._() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 10),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36',
      },
      followRedirects: true,
      maxRedirects: 10,
    ));
  }

  void setDouyinCookie(String cookie) => _dyCookie = cookie;
  void setXhsCookie(String cookie) => _xhsCookie = cookie;

  /// 从分享链接解析真实URL并下载文件
  Future<Map<String, dynamic>> downloadFromShareLink({
    required String shareUrl,
    required String savePath,
    required String platform,
    Function(int received, int total)? onProgress,
  }) async {
    try {
      // 1. 解析分享链接获取真实页面URL
      final resolvedUrl = await _resolveShareUrl(shareUrl, platform);
      if (resolvedUrl == null) {
        return {'success': false, 'message': '无法解析分享链接'};
      }

      // 2. 提取文件名
      final fileName = _extractFileName(resolvedUrl, platform);
      final filePath = '$savePath/$fileName';

      // 3. 下载文件
      final cookie = platform == 'xhs' ? _xhsCookie : _dyCookie;
      final referer = platform == 'xhs'
          ? 'https://www.xiaohongshu.com/'
          : 'https://www.douyin.com/';

      await _dio.download(
        resolvedUrl,
        filePath,
        onReceiveProgress: onProgress,
        options: Options(
          headers: {
            'Cookie': cookie,
            'Referer': referer,
          },
        ),
      );

      return {
        'success': true,
        'title': fileName,
        'path': filePath,
      };
    } on DioException catch (e) {
      return {'success': false, 'message': '下载失败: ${e.message}'};
    } catch (e) {
      return {'success': false, 'message': '错误: $e'};
    }
  }

  /// 解析分享链接获取真实URL
  Future<String?> _resolveShareUrl(String shareUrl, String platform) async {
    try {
      // 尝试跟随重定向获取真实URL
      final response = await _dio.get(
        shareUrl,
        options: Options(
          followRedirects: false,
          headers: {
            'Cookie': platform == 'xhs' ? _xhsCookie : _dyCookie,
          },
        ),
      );

      // 检查重定向
      final location = response.headers.value('location');
      if (location != null) return location;

      // 如果没有重定向，返回原URL（可能是直接链接）
      if (shareUrl.contains('.mp4') || shareUrl.contains('.mp3')) {
        return shareUrl;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// 从URL提取文件名
  String _extractFileName(String url, String platform) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      if (path.isNotEmpty && path.contains('.')) {
        final name = path.split('/').last;
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}

    final ext = platform == 'xhs' ? '.mp4' : '.mp4';
    return '${platform}_${DateTime.now().millisecondsSinceEpoch}$ext';
  }
}
