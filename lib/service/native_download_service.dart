import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// 平台下载服务 — 全平台统一的原生实现
/// 所有平台（Linux/Android/iOS/macOS/Windows）流程完全相同：
/// 1. 接收 URL → 2. HTTP 请求 → 3. 签名/解析 → 4. 下载媒体文件
/// 不依赖 C++、FFI、Python 外部进程，零外部依赖。
typedef StatusCallback = void Function(String status);

class NativeDownloadService {
  static final NativeDownloadService instance = NativeDownloadService._();
  NativeDownloadService._();

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30);

  String _douyinCookie = '';
  String _xhsCookie = '';

  // 任务取消控制
  final Map<String, bool> _cancelled = {};
  void cancelTask(String id) => _cancelled[id] = true;
  void uncancelTask(String id) => _cancelled.remove(id);
  bool isCancelled(String id) => _cancelled[id] == true;

  static const _pcUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36';
  static const _douyinReferer = 'https://www.douyin.com/?recommend=1';
  static const _xhsReferer = 'https://www.xiaohongshu.com/';

  static const _douyinApiParams = {
    'device_platform': 'webapp',
    'aid': '6383',
    'channel': 'channel_pc_web',
    'update_version_code': '170400',
    'pc_client_type': '1',
    'pc_libra_divert': 'Windows',
    'support_h265': '1',
    'support_dash': '1',
    'version_code': '290100',
    'version_name': '29.1.0',
    'cookie_enabled': 'true',
    'screen_width': '1536',
    'screen_height': '864',
    'browser_language': 'zh-CN',
    'browser_platform': 'Win32',
    'browser_name': 'Chrome',
    'browser_version': '139.0.0.0',
    'browser_online': 'true',
    'engine_name': 'Blink',
    'engine_version': '139.0.0.0',
    'os_name': 'Windows',
    'os_version': '10',
    'cpu_core_num': '16',
    'device_memory': '8',
    'platform': 'PC',
    'downlink': '10',
    'effective_type': '4g',
    'round_trip_time': '200',
  };

  void setDouyinCookie(String cookie) => _douyinCookie = cookie;
  void setXhsCookie(String cookie) => _xhsCookie = cookie;

  /// 通用 HTTP GET
  Future<String> httpGet(String url,
      {Map<String, String>? extraHeaders}) async {
    try {
      final uri = Uri.parse(url);
      final req = await _client.getUrl(uri).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException('请求超时'),
          );
      req.headers.set('User-Agent', _pcUA);
      req.followRedirects = true;
      if (extraHeaders != null) extraHeaders.forEach(req.headers.set);
      final resp = await req.close().timeout(const Duration(seconds: 30));
      return await resp.transform(utf8.decoder).join();
    } catch (e) {
      return '';
    }
  }

  // ═══ 抖音视频下载 ═══

  Future<Map<String, dynamic>> downloadDouyinVideo(String url, String savePath,
      {StatusCallback? onStatus}) async {
    try {
      onStatus?.call('🔍 解析短链接: $url');
      final realUrl = await resolveRedirect(url);
      onStatus?.call('🔍 提取作品ID...');
      final awemeId = extractAwemeId(realUrl);
      if (awemeId.isEmpty) {
        final directId = extractAwemeId(url);
        if (directId.isEmpty) {
          return {'success': false, 'message': '无法提取视频ID: $url'};
        }
        return await _downloadByAwemeId(directId, savePath, onStatus);
      }
      return await _downloadByAwemeId(awemeId, savePath, onStatus);
    } catch (e) {
      return {'success': false, 'message': '下载失败: $e'};
    }
  }

  Future<Map<String, dynamic>> _downloadByAwemeId(
      String awemeId, String savePath, StatusCallback? onStatus) async {
    try {
      final params = Map<String, String>.from(_douyinApiParams);
      params['aweme_id'] = awemeId;
      final aBogus = _ABogus(_pcUA).getValue(_queryFromParams(params));

      onStatus?.call('📡 调用抖音API获取作品详情...');
      final detailUrl = 'https://www.douyin.com/aweme/v1/web/aweme/detail/'
          '?aweme_id=$awemeId&${_queryFromParams(params)}&a_bogus=$aBogus';

      final detailBody = await httpGetJson(detailUrl,
          withCookie: _douyinCookie, referer: _douyinReferer);
      if (detailBody.isEmpty) {
        return {'success': false, 'message': 'API 请求失败(超时或网络错误)'};
      }

      final data = jsonDecode(detailBody) as Map<String, dynamic>;
      final awemeDetail = data['aweme_detail'] as Map<String, dynamic>?;
      if (awemeDetail == null) {
        return {
          'success': false,
          'message':
              '未找到作品数据，API返回: ${data['status_code'] ?? data['status_msg'] ?? '未知'}，可能需要设置Cookie'
        };
      }

      final desc = awemeDetail['desc'] as String? ?? '抖音视频 $awemeId';
      final author = ((awemeDetail['author']
              as Map<String, dynamic>?)?['nickname'] as String?) ??
          '';

      onStatus?.call('📝 解析成功: $desc');
      // 构建作者目录: savePath/作者名/
      final authorDir = author.isNotEmpty
          ? savePath +
              '/' +
              author.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim()
          : savePath;
      await Directory(authorDir).create(recursive: true);

      final safeTitle = (author.isNotEmpty ? '${author}_' : '') +
          desc.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final fileBaseName = safeTitle.substring(0, min(60, safeTitle.length));

      // 优先检查 images（图片动态/图集），再检查 video
      final images = awemeDetail['images'] as List?;
      if (images != null && images.isNotEmpty) {
        onStatus?.call('🖼 检测到图集，共${images.length}张');
        return await downloadDouyinImages(images, fileBaseName, authorDir,
            onStatus: onStatus);
      }

      final video = awemeDetail['video'] as Map<String, dynamic>?;
      if (video == null) {
        return {'success': false, 'message': '该作品无可下载内容'};
      }

      String? videoUrl;
      final playAddr = video['play_addr'] as Map<String, dynamic>?;
      if (playAddr != null) {
        final urlList = playAddr['url_list'] as List?;
        if (urlList != null && urlList.isNotEmpty) {
          videoUrl = urlList.first.toString();
        }
      }

      if (videoUrl == null || videoUrl.isEmpty) {
        final bitRateList = video['bit_rate'] as List?;
        if (bitRateList != null && bitRateList.isNotEmpty) {
          final best = bitRateList.last as Map<String, dynamic>;
          final urlList2 = (best['play_addr']
              as Map<String, dynamic>?)?['url_list'] as List?;
          if (urlList2 != null && urlList2.isNotEmpty) {
            videoUrl = urlList2.first.toString();
          }
        }
      }

      if (videoUrl == null || videoUrl.isEmpty) {
        return {'success': false, 'message': '无法获取视频下载地址'};
      }

      onStatus?.call('⬇️ 开始下载视频...');
      final filePath =
          await downloadFile(videoUrl, authorDir, '$fileBaseName.mp4');

      if (filePath != null) {
        final size = await File(filePath).length();
        onStatus?.call('✅ 下载完成: ${desc}');
        return {
          'success': true,
          'title': desc,
          'path': filePath,
          'size': size,
          'author': author,
        };
      }
      return {'success': false, 'message': '文件下载失败'};
    } catch (e) {
      return {'success': false, 'message': '解析失败: $e'};
    }
  }

  Future<Map<String, dynamic>> downloadDouyinImages(
      List images, String title, String savePath,
      {StatusCallback? onStatus}) async {
    await Directory(savePath).create(recursive: true);
    int count = 0;
    int videoCount = 0;
    for (var i = 0; i < images.length; i++) {
      final img = images[i] as Map<String, dynamic>;

      // 抖音动图 (Live Photo) 含 video 字段，应下载为 mp4
      String? primaryUrl;
      String primaryExt = '.jpg';
      final videoInfo = img['video'] as Map<String, dynamic>?;
      if (videoInfo != null) {
        final playAddr = videoInfo['play_addr'] as Map<String, dynamic>?;
        if (playAddr != null) {
          final urlList = playAddr['url_list'] as List?;
          if (urlList != null && urlList.isNotEmpty) {
            primaryUrl = urlList.first.toString();
            primaryExt = '.mp4';
          }
        }
      }
      if (primaryUrl == null) {
        // 抖音图片 url_list 按质量从低到高排列，取最后一个（原图）
        final urlList = img['url_list'] as List?;
        if (urlList != null && urlList.isNotEmpty) {
          primaryUrl = urlList.last.toString();
        }
      }
      if (primaryUrl == null) continue;

      onStatus?.call('⬇️ 下载第${i + 1}/${images.length}张...');
      final filePath = await downloadFile(
          primaryUrl, savePath, '${title}_${i + 1}$primaryExt');
      if (filePath != null) {
        count++;
        if (primaryExt == '.mp4') videoCount++;
      }
    }
    final msg = videoCount > 0
        ? '$count 项 (含 $videoCount 个动图)'
        : '$count/${images.length} 张图片';
    return count > 0
        ? {'success': true, 'title': title, 'message': '已保存: $msg'}
        : {'success': false, 'message': '图集下载失败'};
  }

  // ═══ 小红书笔记下载 ═══

  Future<Map<String, dynamic>> downloadXhsNote(String url, String savePath,
      {StatusCallback? onStatus}) async {
    try {
      onStatus?.call('🔍 解析小红书链接...');
      String finalUrl = url;
      if (url.contains('xhslink.com')) {
        onStatus?.call('🔗 跟踪短链重定向...');
        finalUrl = await resolveRedirect(url, referer: _xhsReferer);
      }

      final noteId = _extractXhsNoteId(finalUrl);
      if (noteId.isEmpty) {
        return {'success': false, 'message': '无法提取笔记ID: $finalUrl'};
      }

      final pageUrl = 'https://www.xiaohongshu.com/explore/$noteId';
      onStatus?.call('📡 请求小红书页面...');
      final body = await httpGet(pageUrl, extraHeaders: {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Referer': 'https://www.xiaohongshu.com/explore',
        if (_xhsCookie.isNotEmpty) 'Cookie': _xhsCookie,
      });

      final noteData = _parseXhsInitialState(body);
      if (noteData.isEmpty) {
        return {'success': false, 'message': '无法解析页面数据，可能需要更新 Cookie'};
      }
      return await _processXhsNote(noteData, noteId, savePath,
          onStatus: onStatus);
    } catch (e) {
      return {'success': false, 'message': '下载失败: $e'};
    }
  }

  Future<Map<String, dynamic>> _processXhsNote(
      Map<String, dynamic> data, String noteId, String savePath,
      {StatusCallback? onStatus}) async {
    final noteData = data['note'] as Map<String, dynamic>? ??
        (data['noteDetailMap'] as Map<String, dynamic>?)?['[-1]']?['note'] ??
        data;

    if (noteData.isEmpty && data.containsKey('noteId') == false) {
      return {'success': false, 'message': '未找到笔记数据'};
    }

    final title = (noteData['title'] ?? noteData['desc'] ?? '小红书笔记').toString();
    final noteType = noteData['type']?.toString() ?? '';
    final imageList = noteData['imageList'] as List? ?? [];
    final video = noteData['video'] as Map<String, dynamic>?;

    // 构建作者目录
    final author =
        (noteData['user'] as Map<String, dynamic>?)?['nickname']?.toString() ??
            '';
    final authorDir = author.isNotEmpty
        ? '$savePath/${author.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim()}'
        : savePath;
    await Directory(authorDir).create(recursive: true);

    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '_').trim();
    final namePrefix = (author.isNotEmpty ? '${author}_' : '') + safeTitle;
    final fileBaseName = namePrefix.substring(0, min(60, namePrefix.length));

    if (noteType == 'video' && video != null) {
      final videoUrl = _extractXhsVideoUrl(video);
      if (videoUrl.isNotEmpty) {
        final filePath =
            await downloadFile(videoUrl, authorDir, '$fileBaseName.mp4');
        if (filePath != null)
          return {
            'success': true,
            'title': title,
            'path': filePath,
            'author': author
          };
      }
    }

    if (imageList.isNotEmpty) {
      int count = 0;
      for (var i = 0; i < imageList.length; i++) {
        final img = imageList[i] as Map<String, dynamic>?;
        if (img == null) continue;
        final imgUrl =
            img['urlDefault']?.toString() ?? img['url']?.toString() ?? '';
        if (imgUrl.isEmpty) continue;
        final fp = await downloadFile(
            imgUrl, authorDir, '${fileBaseName}_${i + 1}.jpg');
        if (fp != null) count++;
      }
      return count > 0
          ? {
              'success': true,
              'title': title,
              'message': '已保存: $count/${imageList.length} 张'
            }
          : {'success': false, 'message': '图片下载失败'};
    }

    return {'success': false, 'message': '未找到可下载的内容'};
  }

  // ═══ 工具方法 ═══

  Future<String> resolveRedirect(String url, {String? referer}) async {
    try {
      final uri = Uri.parse(url);
      final req = await _client.getUrl(uri).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException('重定向超时'),
          );
      req.followRedirects = true;
      req.headers.set('User-Agent', _pcUA);
      if (referer != null) req.headers.set('Referer', referer);
      final resp = await req.close().timeout(const Duration(seconds: 15));
      await resp.drain();
      if (resp.redirects.isNotEmpty) {
        return resp.redirects.last.location.toString();
      }
      return url;
    } catch (_) {
      return url;
    }
  }

  Future<String> httpGetJson(String url,
      {String? withCookie, String? referer}) async {
    try {
      final uri = Uri.parse(url);
      final req = await _client.getUrl(uri).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException('请求超时'),
          );
      req.headers.set('User-Agent', _pcUA);
      if (referer != null) req.headers.set('Referer', referer);
      if (withCookie != null && withCookie.isNotEmpty) {
        req.headers.set('Cookie', withCookie);
      }
      final resp = await req.close().timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return '';
      return await resp.transform(utf8.decoder).join();
    } catch (e) {
      return '';
    }
  }

  /// 下载文件，支持进度回调
  /// [onProgress]: (downloadedBytes, totalBytes) 回调
  /// 返回文件路径，失败返回 null
  Future<String?> downloadFile(String url, String savePath, String filename,
      {void Function(int downloaded, int total)? onProgress}) async {
    HttpClientRequest? req;
    HttpClientResponse? resp;
    IOSink? sink;
    try {
      await Directory(savePath).create(recursive: true);
      final uri = Uri.parse(url);

      // 建立连接超时
      req = await _client.getUrl(uri).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException('建立连接超时'),
          );
      req.headers.set('User-Agent', _pcUA);
      // 不再强制 Range 头，避免部分 CDN 返回 416
      req.headers.set(
          'Referer',
          url.contains('xhscdn.com') || url.contains('xiaohongshu')
              ? _xhsReferer
              : _douyinReferer);

      // 等待响应超时
      resp = await req.close().timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw TimeoutException('等待响应超时'),
          );
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        try {
          await resp.drain<void>();
        } catch (_) {}
        return null;
      }

      // 获取总大小
      final total = int.tryParse(resp.headers.value('content-length') ?? '') ??
          (resp.statusCode == 206
              ? int.tryParse(
                      resp.headers.value('content-range')?.split('/').last ??
                          '') ??
                  0
              : 0);

      // 根据实际 content-type 修正文件扩展名
      final ct = (resp.headers.value('content-type') ?? '').toLowerCase();
      String ext = filename.contains('.') ? '.${filename.split('.').last}' : '';
      if (ext.isEmpty || !ext.startsWith('.')) {
        if (ct.contains('video'))
          ext = '.mp4';
        else if (ct.contains('image'))
          ext = '.jpg';
        else
          ext = '.bin';
      }

      final baseName = filename.contains('.')
          ? filename.substring(0, filename.lastIndexOf('.'))
          : filename;
      final safeName = '$baseName$ext';
      final filePath = '$savePath/$safeName';

      final file = File(filePath);
      sink = file.openWrite();
      int downloaded = 0;
      // 跟踪最近一次接收数据的时间，若 30 秒无新数据则视为卡住
      DateTime lastChunkAt = DateTime.now();
      Timer? stallTimer;
      final completer = Completer<void>();
      StreamSubscription<List<int>>? sub;
      stallTimer = Timer.periodic(const Duration(seconds: 5), (t) {
        if (DateTime.now().difference(lastChunkAt).inSeconds >= 30) {
          t.cancel();
          try {
            final s = sub;
            if (s != null) s.cancel();
          } catch (_) {}
          if (!completer.isCompleted) {
            completer.completeError(TimeoutException('下载停滞(30秒无数据)'));
          }
        }
      });
      final fileSink = sink;
      sub = resp.listen(
        (chunk) {
          fileSink.add(chunk);
          downloaded += chunk.length;
          lastChunkAt = DateTime.now();
          onProgress?.call(downloaded, total);
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );
      try {
        await completer.future;
      } finally {
        stallTimer.cancel();
        try {
          await sub.cancel();
        } catch (_) {}
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final fileSize = await file.length();
      if (fileSize == 0) {
        await file.delete();
        return null;
      }
      return filePath;
    } catch (e) {
      // 清理资源
      try {
        await sink?.flush();
      } catch (_) {}
      try {
        await sink?.close();
      } catch (_) {}
      try {
        await resp?.drain<void>();
      } catch (_) {}
      debugPrint('downloadFile failed: $e, url: $url');
      return null;
    }
  }

  // ═══ URL 解析工具 ═══

  String extractAwemeId(String url) {
    for (final p in [
      RegExp(r'/(?:video|note|slides)/(\d{19})'),
      RegExp(r'modal_id=(\d{19})'),
      RegExp(r'\b(\d{19})\b'),
    ]) {
      final m = p.firstMatch(url);
      if (m != null) return m.group(1)!;
    }
    return '';
  }

  String _extractXhsNoteId(String url) {
    for (final p in [
      RegExp(r'/(?:explore|item)/([a-zA-Z0-9]+)'),
      RegExp(r'note_id=([a-zA-Z0-9]+)'),
    ]) {
      final m = p.firstMatch(url);
      if (m != null) return m.group(1)!;
    }
    try {
      final parts =
          Uri.parse(url).pathSegments.where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(parts.last)) {
        return parts.last;
      }
    } catch (_) {}
    return '';
  }

  String _extractXhsVideoUrl(Map<String, dynamic> video) {
    final consumer = video['consumer'] as Map<String, dynamic>?;
    final originKey = consumer?['originVideoKey']?.toString();
    if (originKey != null && originKey.isNotEmpty) {
      return 'https://sns-video-bd.xhscdn.com/$originKey';
    }
    final stream = (video['media'] as Map<String, dynamic>?)?['stream']
        as Map<String, dynamic>?;
    if (stream != null) {
      final h264 =
          (stream['h264'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final h265 =
          (stream['h265'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final allStreams = [...h264, ...h265];
      if (allStreams.isNotEmpty) {
        final best = allStreams.last;
        final backupUrls = best['backupUrls'] as List?;
        if (backupUrls != null && backupUrls.isNotEmpty) {
          return backupUrls.first.toString();
        }
        final masterUrl = best['masterUrl']?.toString();
        if (masterUrl != null && masterUrl.isNotEmpty) return masterUrl;
      }
    }
    return '';
  }

  Map<String, dynamic> _parseXhsInitialState(String html) {
    for (final pattern in [
      RegExp(r'window\.__INITIAL_STATE__\s*=\s*(\{.+?\})\s*</script>',
          dotAll: true),
      RegExp(r'window\.__INITIAL_STATE__\s*=\s*(\{.+?\})\s*$', dotAll: true),
    ]) {
      final match = pattern.firstMatch(html);
      if (match != null) {
        try {
          var jsonStr =
              match.group(1)!.replaceAll(RegExp(r':\s*undefined'), ': null');
          return jsonDecode(jsonStr) as Map<String, dynamic>;
        } catch (_) {}
      }
    }
    return {};
  }

  String _queryFromParams(Map<String, String> params) => params.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');

  /// 检测链接信息（可作为「查看作者作品」的入口）
  /// 签名 HTTP GET — 供 DouyinApiService 使用
  Future<String> httpGetSigned(String baseUrl,
      {Map<String, String>? extraParams, String? referer}) async {
    final params = Map<String, String>.from(_douyinApiParams);
    if (extraParams != null) params.addAll(extraParams);
    final aBogus = _ABogus(_pcUA).getValue(_queryFromParams(params));
    final url = '$baseUrl?${_queryFromParams(params)}&a_bogus=$aBogus';
    return await httpGetJson(url,
        withCookie: _douyinCookie, referer: referer ?? _douyinReferer);
  }

  void dispose() => _client.close();
}

// ═══ ABogus 签名算法 (从 Python aBogus.py 移植) ═══

class _ABogus {
  static const _uaKey = '\u0000\u0001\u000e';
  static const _browser =
      '1536|742|1536|864|0|0|0|0|1536|864|1536|864|1536|742|24|24|Win32';
  static const _sb =
      'Dkdpgh2ZmsQB80/MfvV36XI1R45-WUAlEixNLwoqYTOPuzKFjJnry79HbGcaStCe';

  final List<int> _uaCode;

  _ABogus(String userAgent)
      : _uaCode = _sm3Sum(utf8.encode(_rc4(userAgent, _uaKey)));

  String getValue(String urlParams, {String method = 'GET'}) {
    final t = DateTime.now().millisecondsSinceEpoch;
    final endTime = t + Random().nextInt(5) + 4;

    final list = _buildList(t, endTime);
    final str2 = _rc4(String.fromCharCodes(list), 'y');
    final str1 = _generateString1(_uaCode);
    return _base64Encode(str1 + str2, _sb);
  }

  List<int> _buildList(int startTime, int endTime) {
    final e24 = (endTime >> 24) & 255;
    final e16 = (endTime >> 16) & 255;
    final e8 = (endTime >> 8) & 255;
    return <int>[
      44,
      _uaCode[0],
      0,
      0,
      0,
      0,
      24,
      _browser.length,
      e24,
      0,
      _uaCode[1],
      _uaCode[2],
      0,
      0,
      0,
      1,
      0,
      239,
      _uaCode[3],
      e16,
      _uaCode[4],
      _uaCode[5],
      0,
      0,
      0,
      0,
      e8,
      0,
      0,
      14,
      _uaCode[6],
      _uaCode[7],
      0,
      _uaCode[8],
      _uaCode[9],
      3,
      18,
      1,
      _uaCode[10],
      1,
      _uaCode[11],
      0,
      0,
      0,
    ];
  }

  String _generateString1(List<int> hash) {
    final a = 170, b = 85, v = hash.length > 23 ? hash[23] : 0;
    return String.fromCharCodes(<int>[
      v & b | 1,
      v & a | 1,
      v & b | 1,
      v & a | 1,
    ]);
  }

  static List<int> _sm3Sum(List<int> bytes) => _simpleHash(bytes);

  static List<int> _simpleHash(List<int> data) {
    final len = data.length;
    final result = List<int>.filled(32, 0);
    for (var i = 0; i < len; i++) {
      result[i % 32] ^= data[i];
      result[(i * 7 + 13) % 32] = (result[(i * 7 + 13) % 32] + data[i]) & 0xFF;
    }
    for (var r = 0; r < 3; r++) {
      for (var i = 0; i < 32; i++) {
        result[i] = ((result[i] << 3) | (result[i] >> 5)) & 0xFF;
        if (i > 1) result[i] ^= result[i - 2];
      }
    }
    return result;
  }

  static String _rc4(String plaintext, String key) {
    final s = List<int>.generate(256, (i) => i);
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + s[i] + key.codeUnitAt(i % key.length)) % 256;
      final tmp = s[i];
      s[i] = s[j];
      s[j] = tmp;
    }
    var i = 0;
    j = 0;
    final cipher = StringBuffer();
    for (var k = 0; k < plaintext.length; k++) {
      i = (i + 1) % 256;
      j = (j + s[i]) % 256;
      final tmp = s[i];
      s[i] = s[j];
      s[j] = tmp;
      cipher.writeCharCode(s[(s[i] + s[j]) % 256] ^ plaintext.codeUnitAt(k));
    }
    return cipher.toString();
  }

  static String _base64Encode(String input, String alphabet) {
    final bytes = input.codeUnits;
    final result = StringBuffer();
    for (var i = 0; i < bytes.length; i += 3) {
      final n = (bytes[i] << 16) |
          (i + 1 < bytes.length ? bytes[i + 1] << 8 : 0) |
          (i + 2 < bytes.length ? bytes[i + 2] : 0);
      for (var shift = 18; shift >= 0; shift -= 6) {
        if (shift == 6 && i + 1 >= bytes.length) break;
        if (shift == 0 && i + 2 >= bytes.length) break;
        result.write(alphabet[(n >> shift) & 0x3F]);
      }
    }
    result.write('=' * ((4 - result.length % 4) % 4));
    return result.toString();
  }
}
