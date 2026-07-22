import 'dart:convert';
import 'dart:io';
import 'native_download_service.dart';

/// 抖音扩展 API 服务 — 实现查看作者/批量下载/采集评论/数据统计/收藏夹等功能
class DouyinApiService {
  static final DouyinApiService instance = DouyinApiService._();
  DouyinApiService._();

  final _native = NativeDownloadService.instance;

  /// 检测链接信息 — 解析作者和合集信息
  Future<String> detectLinkInfo(String link) async {
    try {
      final realUrl = await _native.resolveRedirect(link);
      final awemeId = _native.extractAwemeId(realUrl);
      if (awemeId.isEmpty) {
        return '{"success":false,"message":"无法提取作品ID"}';
      }

      final detail = await _fetchDetail(awemeId);
      if (detail == null) {
        return '{"success":false,"message":"获取详情失败，请检查Cookie"}';
      }

      final desc = detail['desc'] ?? '';
      final author = detail['author'] as Map<String, dynamic>?;
      final result = <String, dynamic>{
        'success': true,
        'title': desc,
        'author': null,
        'mix': null,
      };

      if (author != null) {
        result['author'] = {
          'uid': author['uid']?.toString() ?? '',
          'sec_uid': author['sec_uid']?.toString() ?? '',
          'nickname': author['nickname']?.toString() ?? '未知用户',
          'unique_id': author['unique_id']?.toString() ?? '',
        };
      }

      final mixInfo = detail['mix_info'] as Map<String, dynamic>?;
      if (mixInfo != null && mixInfo['mix_id'] != null) {
        final statis = mixInfo['statis'] as Map<String, dynamic>?;
        result['mix'] = {
          'mix_id': mixInfo['mix_id']?.toString() ?? '',
          'mix_name': mixInfo['mix_name']?.toString() ?? '未知合集',
          'count': statis?['current_episode'] ?? 0,
        };
      }

      return jsonEncode(result);
    } catch (e) {
      return '{"success":false,"message":"检测失败: $e"}';
    }
  }

  /// 获取作品详情
  Future<Map<String, dynamic>?> _fetchDetail(String awemeId) async {
    final body = await _native.httpGetSigned(
      'https://www.douyin.com/aweme/v1/web/aweme/detail/',
      extraParams: {
        'aweme_id': awemeId,
        'version_code': '190500',
        'version_name': '19.5.0',
      },
    );
    if (body.isEmpty) return null;
    final data = jsonDecode(body) as Map<String, dynamic>;
    return data['aweme_detail'] as Map<String, dynamic>?;
  }

  /// 批量下载账号所有作品

  /// 列出账号所有作品（不下载）
  Future<String> listAccountWorks(String secUid) async {
    try {
      final works = <Map<String, dynamic>>[];
      int cursor = 0;
      for (var page = 0; page < 50; page++) {
        final body = await _native.httpGetSigned(
          'https://www.douyin.com/aweme/v1/web/aweme/post/',
          extraParams: {
            'sec_user_id': secUid,
            'count': '18',
            'max_cursor': cursor.toString(),
            'version_code': '170400',
            'version_name': '17.4.0',
          },
        );
        if (body.isEmpty) break;
        final data = jsonDecode(body) as Map<String, dynamic>;
        final items = data['aweme_list'] as List?;
        if (items == null || items.isEmpty) break;
        for (final item in items) {
          final detail = item as Map<String, dynamic>;
          final desc = detail['desc'] ?? '无标题';
          final awemeId = detail['aweme_id']?.toString() ?? '';
          final awemeType = detail['aweme_type'] ?? 0;
          final typeName = (awemeType == 2 || awemeType == 68) ? '图集' : '视频';
          final stats = detail['statistics'] as Map<String, dynamic>?;
          works.add({
            'id': awemeId,
            'title': desc.toString().length > 60
                ? '${desc.toString().substring(0, 60)}...'
                : desc.toString(),
            'type': typeName,
            'likes': stats?['digg_count'] ?? 0,
            'comments': stats?['comment_count'] ?? 0,
          });
        }
        cursor = (data['max_cursor'] as num?)?.toInt() ?? 0;
        if (data['has_more'] != 1) break;
      }
      return jsonEncode({'success': true, 'works': works, 'count': works.length});
    } catch (e) {
      return jsonEncode({'success': false, 'message': '$e', 'works': []});
    }
  }
  Future<Map<String, dynamic>> batchDownloadAccount(
      String secUid, String nickname, String savePath) async {
    try {
      final authorDir = '$savePath/${_safeName(nickname)}';
      await Directory(authorDir).create(recursive: true);

      int cursor = 0, total = 0, success = 0, fail = 0;

      for (var page = 0; page < 200; page++) {
        final body = await _native.httpGetSigned(
          'https://www.douyin.com/aweme/v1/web/aweme/post/',
          extraParams: {
            'sec_user_id': secUid,
            'count': '18',
            'max_cursor': cursor.toString(),
            'version_code': '170400',
            'version_name': '17.4.0',
          },
        );
        if (body.isEmpty) break;

        final data = jsonDecode(body) as Map<String, dynamic>;
        final items = data['aweme_list'] as List?;
        if (items == null || items.isEmpty) break;

        for (final item in items) {
          total++;
          final detail = item as Map<String, dynamic>;
          final desc = detail['desc'] ?? '未知作品';
          final safeTitle = _safeName('${nickname}_$desc');

          if (await _downloadItem(detail, safeTitle, authorDir)) {
            success++;
          } else {
            fail++;
          }
        }

        cursor = (data['max_cursor'] as num?)?.toInt() ?? 0;
        if (data['has_more'] != 1) break;
      }

      return {
        'success': total > 0,
        'title': nickname,
        'message':
            total == 0 ? '该账号没有作品或获取失败' : '共 $total 个作品，成功 $success，失败 $fail',
      };
    } catch (e) {
      return {'success': false, 'message': '批量下载失败: $e'};
    }
  }

  /// 批量下载合集
  Future<Map<String, dynamic>> batchDownloadMix(
      String mixId, String mixName, String savePath) async {
    try {
      final mixDir = '$savePath/${_safeName(mixName)}';
      await Directory(mixDir).create(recursive: true);

      int cursor = 0, total = 0, success = 0, fail = 0;

      for (var page = 0; page < 200; page++) {
        final body = await _native.httpGetSigned(
          'https://www.douyin.com/aweme/v1/web/mix/aweme/',
          extraParams: {
            'mix_id': mixId,
            'cursor': cursor.toString(),
            'count': '20',
          },
        );
        if (body.isEmpty) break;

        final data = jsonDecode(body) as Map<String, dynamic>;
        final items = data['aweme_list'] as List?;
        if (items == null || items.isEmpty) break;

        for (final item in items) {
          total++;
          final detail = item as Map<String, dynamic>;
          final desc = detail['desc'] ?? '未知作品';
          final safeTitle = _safeName(desc);

          if (await _downloadItem(detail, safeTitle, mixDir)) {
            success++;
          } else {
            fail++;
          }
        }

        cursor = (data['cursor'] as num?)?.toInt() ?? 0;
        if (data['has_more'] != 1) break;
      }

      return {
        'success': total > 0,
        'title': mixName,
        'message':
            total == 0 ? '该合集没有作品或获取失败' : '共 $total 个作品，成功 $success，失败 $fail',
      };
    } catch (e) {
      return {'success': false, 'message': '合集下载失败: $e'};
    }
  }

  /// 列出收藏夹
  Future<String> listCollectFolders() async {
    try {
      final body = await _native.httpGetSigned(
        'https://www.douyin.com/aweme/v1/web/aweme/listcollection/',
        extraParams: {'cursor': '0', 'count': '20'},
      );
      if (body.isEmpty) {
        return '{"success":false,"message":"获取收藏夹失败","folders":[]}';
      }

      final data = jsonDecode(body) as Map<String, dynamic>;
      final folders = <Map<String, dynamic>>[];
      final collects = data['collects'] as List?;
      if (collects != null) {
        for (final folder in collects) {
          final f = folder as Map<String, dynamic>;
          folders.add({
            'collect_id': f['collect_id']?.toString() ?? '',
            'title': f['collect_name']?.toString() ?? '未命名',
            'count': f['note_count'] ?? 0,
          });
        }
      }

      return jsonEncode({'success': true, 'folders': folders});
    } catch (e) {
      return '{"success":false,"message":"获取收藏夹失败: $e","folders":[]}';
    }
  }

  /// 采集评论保存为 CSV
  Future<Map<String, dynamic>> scrapeComments(
      String link, String savePath) async {
    try {
      final realUrl = await _native.resolveRedirect(link);
      final awemeId = _native.extractAwemeId(realUrl);
      if (awemeId.isEmpty) {
        return {'success': false, 'message': '无法解析作品ID'};
      }

      final detail = await _fetchDetail(awemeId);
      String safeName = awemeId;
      if (detail != null) {
        final desc = detail['desc']?.toString() ?? '';
        final author = detail['author'] as Map<String, dynamic>?;
        final nickname = author?['nickname']?.toString() ?? '';
        safeName = _safeName(nickname.isNotEmpty ? '${nickname}_$desc' : desc);
        if (safeName.isEmpty) safeName = awemeId;
      }

      final comments = <Map<String, dynamic>>[];
      int cursor = 0;

      for (var page = 0; page < 100; page++) {
        final body = await _native.httpGetSigned(
          'https://www.douyin.com/aweme/v1/web/comment/list/',
          extraParams: {
            'aweme_id': awemeId,
            'cursor': cursor.toString(),
            'count': '20',
            'item_type': '0',
            'version_code': '170400',
            'version_name': '17.4.0',
          },
          referer: 'https://www.douyin.com/video/$awemeId',
        );
        if (body.isEmpty) break;

        final data = jsonDecode(body) as Map<String, dynamic>;
        final items = data['comments'] as List?;
        if (items == null || items.isEmpty) break;

        for (final c in items) {
          final comment = c as Map<String, dynamic>;
          comments.add({
            'user':
                (comment['user'] as Map<String, dynamic>?)?['nickname'] ?? '',
            'text': comment['text'] ?? '',
            'likes': comment['digg_count'] ?? 0,
            'time': comment['create_time'] ?? 0,
            'ip': comment['ip_label'] ?? '',
          });
        }

        cursor = (data['cursor'] as num?)?.toInt() ?? 0;
        if (data['has_more'] != true) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (comments.isEmpty) {
        return {'success': true, 'title': safeName, 'message': '未找到评论'};
      }

      final dataDir = Directory('$savePath/data');
      await dataDir.create(recursive: true);
      final csvPath = '$savePath/data/${safeName}_comments.csv';

      final buffer = StringBuffer();
      buffer.writeln('user,text,likes,time,ip');
      for (final c in comments) {
        final user = (c['user'] as String).replaceAll(',', '\u{FF0C}');
        final text = (c['text'] as String)
            .replaceAll(',', '\u{FF0C}')
            .replaceAll('\n', ' ');
        buffer.writeln('$user,$text,${c['likes']},${c['time']},${c['ip']}');
      }
      await File(csvPath).writeAsString('\u{FEFF}${buffer.toString()}');

      return {
        'success': true,
        'title': safeName,
        'message': '采集完成: ${comments.length} 条评论',
      };
    } catch (e) {
      return {'success': false, 'message': '评论采集失败: $e'};
    }
  }

  /// 获取数据统计
  Future<String> getDataStats(String link) async {
    try {
      final realUrl = await _native.resolveRedirect(link);
      final awemeId = _native.extractAwemeId(realUrl);
      if (awemeId.isEmpty) {
        return '{"success":false,"message":"无法提取作品ID"}';
      }

      final detail = await _fetchDetail(awemeId);
      if (detail == null) {
        return '{"success":false,"message":"获取详情失败"}';
      }

      final stats = detail['statistics'] as Map<String, dynamic>?;
      return jsonEncode({
        'success': true,
        'title': detail['desc'] ?? '未知',
        'author':
            (detail['author'] as Map<String, dynamic>?)?['nickname'] ?? '未知',
        'likes': stats?['digg_count'] ?? 0,
        'comments': stats?['comment_count'] ?? 0,
        'shares': stats?['share_count'] ?? 0,
        'plays': stats?['play_count'] ?? 0,
        'collects': stats?['collect_count'] ?? 0,
      });
    } catch (e) {
      return '{"success":false,"message":"数据统计失败: $e"}';
    }
  }

  /// 批量下载多个链接
  Future<Map<String, dynamic>> batchDownloadLinks(
      List<String> links, String savePath) async {
    int success = 0, fail = 0;
    for (final link in links) {
      final result = await _native.downloadDouyinVideo(link, savePath);
      if (result['success'] == true) {
        success++;
      } else {
        fail++;
      }
    }
    return {
      'success': success > 0,
      'message': '共 ${links.length} 个链接，成功 $success，失败 $fail',
    };
  }

  /// 重新下载（从历史记录）
  Future<Map<String, dynamic>> redownloadFromHistory(String savePath) async {
    try {
      // 尝试读取历史文件
      final files = ['download_history.csv', 'download_history.txt'];
      List<String> urls = [];

      for (final fileName in files) {
        final file = File('$savePath/data/$fileName');
        if (await file.exists()) {
          final lines = (await file.readAsString()).split('\n');
          for (var i = (fileName.endsWith('.csv') ? 1 : 0);
              i < lines.length;
              i++) {
            final line = lines[i].trim();
            if (line.isEmpty) continue;
            final url =
                fileName.endsWith('.csv') ? line.split(',').first.trim() : line;
            if (url.isNotEmpty && url.startsWith('http')) urls.add(url);
          }
          break;
        }
      }

      if (urls.isEmpty) {
        return {'success': false, 'message': '未找到下载记录'};
      }

      return await batchDownloadLinks(urls, savePath);
    } catch (e) {
      return {'success': false, 'message': '重新下载失败: $e'};
    }
  }

  // ═══ 内部方法 ═══

  /// 下载单个作品
  Future<bool> _downloadItem(
      Map<String, dynamic> detail, String safeTitle, String savePath) async {
    final images = detail['images'] as List?;
    if (images != null && images.isNotEmpty) {
      final result =
          await _native.downloadDouyinImages(images, safeTitle, savePath);
      return result['success'] == true;
    }

    final video = detail['video'] as Map<String, dynamic>?;
    if (video != null) {
      final playAddr = video['play_addr'] as Map<String, dynamic>?;
      final urlList = playAddr?['url_list'] as List?;
      if (urlList != null && urlList.isNotEmpty) {
        final fp = await _native.downloadFile(
            urlList.first.toString(), savePath, '$safeTitle.mp4');
        return fp != null;
      }
    }
    return false;
  }

  String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '_').trim();
    return cleaned.substring(0, cleaned.length > 80 ? 80 : cleaned.length);
  }
}
