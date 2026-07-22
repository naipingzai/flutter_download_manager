import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../platform/douyin/douyin_bridge.dart';
import '../../platform/xhs/xhs_bridge.dart';
import '../../service/cookie_store.dart';
import '../../service/gallery_service.dart';

/// 下载页面
class DownloadScreen extends StatefulWidget {
  final String platformId;
  final String platformName;
  final String? sharedLink;

  const DownloadScreen({
    super.key,
    required this.platformId,
    required this.platformName,
    this.sharedLink,
  });

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  final TextEditingController _linkController = TextEditingController();
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    if (widget.sharedLink != null) {
      _linkController.text = widget.sharedLink!;
    }
    _syncCookie();
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  String _extractLink() {
    final raw = _linkController.text.trim();
    final match = RegExp(r'https?://[^\s<>"]+').firstMatch(raw);
    return match?.group(0) ?? raw;
  }

  List<String> _extractAllLinks() {
    return RegExp(r'https?://[^\s<>"]+')
        .allMatches(_linkController.text)
        .map((m) => m.group(0)!)
        .toList();
  }

  void _showDialog(String title, String content) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _syncCookie() async {
    final store = CookieStore(platform: widget.platformId);
    await store.load();
    final cookie = store.getActiveCookie();
    if (cookie == null || cookie.isEmpty) return;
    if (widget.platformId == 'xhs') {
      XhsBridge.setCookie(cookie);
    } else {
      DouyinBridge.setCookie(cookie);
    }
  }

  Future<String> _getSavePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final savePath =
        '${appDir.path}/${widget.platformId == 'xhs' ? 'XhsDownload' : 'DyDownload'}';
    await Directory(savePath).create(recursive: true);
    return savePath;
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() => _linkController.text = data.text!);
    }
  }

  Future<void> _executeWithLoading(
      String loadingMsg, Future<Map<String, dynamic>> Function() task) async {
    setState(() => _isDownloading = true);
    _showSnackBar(loadingMsg);
    try {
      final result = await task();
      if (result['success'] == true) {
        await GalleryService.instance.requestPermission();
        final path = result['path']?.toString() ?? '';
        final albumName = widget.platformId == 'xhs' ? '小红书下载' : '抖音下载';
        if (path.isNotEmpty) {
          await GalleryService.instance.saveToGallery(path, album: albumName);
          _showDialog('下载成功', '${result['title'] ?? ''}\n已保存到相册');
        } else {
          final savePath = await _getSavePath();
          final dir = Directory(savePath);
          final files = <String>[];
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) files.add(entity.path);
          }
          final count = await GalleryService.instance
              .saveAllToGallery(files, album: albumName);
          _showDialog('下载成功', '${result['message'] ?? '完成'}\n$count 个文件已保存到相册');
        }
      } else {
        _showDialog('操作失败', result['message']?.toString() ?? '未知错误');
      }
    } catch (e) {
      _showDialog('操作失败', '$e');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _download() async {
    final url = _extractLink();
    if (url.isEmpty) return _showSnackBar('请先输入链接');
    await _syncCookie();
    final savePath = await _getSavePath();
    await _executeWithLoading('正在下载...', () async {
      if (widget.platformId == 'xhs') {
        return await XhsBridge.parseAndDownload(url, savePath);
      } else {
        return await DouyinBridge.parseAndDownload(url, savePath);
      }
    });
  }

  Future<void> _detectLinkInfo() async {
    final url = _extractLink();
    if (url.isEmpty) return _showSnackBar('请先输入链接');
    await _syncCookie();
    // 使用独立加载状态，不影响下载按钮
    setState(() => _isDownloading = true);
    try {
      String result;
      if (widget.platformId == 'xhs') {
        result = XhsBridge.detectLinkInfo(url);
      } else {
        result = await DouyinBridge.detectLinkInfo(url);
      }
      final data = jsonDecode(result) as Map<String, dynamic>;
      if (data['success'] != true) {
        _showDialog('解析失败', data['message']?.toString() ?? '无法解析该链接');
        return;
      }

      final author = data['author'] as Map<String, dynamic>?;
      final mix = data['mix'] as Map<String, dynamic>?;

      // 列出作者作品
      if (author != null && author['sec_uid'] != null) {
        final secUid = author['sec_uid'] as String;
        final nickname = author['nickname'] ?? '未知';
        final worksResult = await DouyinBridge.listAccountWorks(secUid);
        final worksData = jsonDecode(worksResult) as Map<String, dynamic>;
        final works = worksData['works'] as List? ?? [];

        final buf = StringBuffer();
        buf.writeln('作者: $nickname');
        buf.writeln('作品数: ${works.length}\n');
        if (mix != null) {
          buf.writeln('合集: ${mix['mix_name']} (${mix['count']}集)\n');
        }
        buf.writeln('── 作品列表 ──');
        for (var i = 0; i < works.length && i < 50; i++) {
          final w = works[i] as Map<String, dynamic>;
          buf.writeln('${i + 1}. [${w['type']}] ${w['title']}');
          buf.writeln('   ❤${w['likes']}  💬${w['comments']}');
        }
        if (works.length > 50) {
          buf.writeln('\n... 共 ${works.length} 个，显示前50个');
        }
        _showDialog('作者作品 - $nickname', buf.toString());
      } else {
        _showDialog('作者信息', '标题: ${data['title'] ?? '未知'}');
      }
    } catch (e) {
      _showDialog('解析失败', '$e');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _batchDownloadAccount() async {
    final url = _extractLink();
    if (url.isEmpty) return _showSnackBar('请先输入链接');
    await _syncCookie();
    final savePath = await _getSavePath();
    await _executeWithLoading('正在批量下载账号作品...', () async {
      if (widget.platformId == 'xhs') {
        return {'success': false, 'message': '小红书暂不支持'};
      }
      return await DouyinBridge.batchDownloadAccount(url, savePath);
    });
  }

  Future<void> _batchDownloadMix() async {
    final url = _extractLink();
    if (url.isEmpty) return _showSnackBar('请先输入链接');
    await _syncCookie();
    final savePath = await _getSavePath();
    await _executeWithLoading('正在下载合集...', () async {
      if (widget.platformId == 'xhs') {
        return {'success': false, 'message': '小红书暂不支持'};
      }
      return await DouyinBridge.batchDownloadMix(url, savePath);
    });
  }

  Future<void> _scrapeComments() async {
    final url = _extractLink();
    if (url.isEmpty) return _showSnackBar('请先输入链接');
    await _syncCookie();
    final savePath = await _getSavePath();
    await _executeWithLoading('正在采集评论...', () async {
      if (widget.platformId == 'xhs') {
        return {'success': false, 'message': '小红书暂不支持'};
      }
      return await DouyinBridge.scrapeComments(url, savePath);
    });
  }

  Future<void> _getDataStats() async {
    final url = _extractLink();
    if (url.isEmpty) return _showSnackBar('请先输入链接');
    await _syncCookie();
    setState(() => _isDownloading = true);
    try {
      String result;
      if (widget.platformId == 'xhs') {
        result = '{"success":false,"message":"小红书暂不支持"}';
      } else {
        result = await DouyinBridge.getDataStats(url);
      }
      final data = jsonDecode(result) as Map<String, dynamic>;
      if (data['success'] == true) {
        _showDialog('数据统计', '''作者: ${data['author'] ?? '未知'}
标题: ${data['title'] ?? '未知'}

点赞: ${data['likes']}
评论: ${data['comments']}
分享: ${data['shares']}
收藏: ${data['collects']}''');
      } else {
        _showDialog('数据统计', data['message']?.toString() ?? '获取失败');
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _batchDownload() async {
    final links = _extractAllLinks();
    if (links.isEmpty) return _showSnackBar('未识别到链接');
    await _syncCookie();
    final savePath = await _getSavePath();
    await _executeWithLoading('正在批量下载 ${links.length} 个链接...', () async {
      if (widget.platformId == 'xhs') {
        int success = 0;
        for (final link in links) {
          final r = await XhsBridge.parseAndDownload(link, savePath);
          if (r['success'] == true) success++;
        }
        return {
          'success': success > 0,
          'message': '成功 $success/${links.length}'
        };
      } else {
        return await DouyinBridge.batchDownloadLinks(links, savePath);
      }
    });
  }

  Future<void> _redownload() async {
    await _syncCookie();
    final savePath = await _getSavePath();
    await _executeWithLoading('正在重新下载历史记录...', () async {
      if (widget.platformId == 'xhs') {
        return {'success': false, 'message': '小红书暂不支持'};
      }
      return await DouyinBridge.redownloadFromHistory(savePath);
    });
  }

  Future<void> _showCollectFolders() async {
    await _syncCookie();
    setState(() => _isDownloading = true);
    try {
      if (widget.platformId == 'xhs') {
        _showDialog('收藏夹', '小红书暂不支持收藏夹功能');
        return;
      }
      final result = await DouyinBridge.listCollectFolders();
      final data = jsonDecode(result) as Map<String, dynamic>;
      if (data['success'] == true) {
        final folders = data['folders'] as List?;
        if (folders == null || folders.isEmpty) {
          _showDialog('收藏夹', '暂无收藏夹');
        } else {
          final buf = StringBuffer();
          buf.writeln('共 ${folders.length} 个收藏夹:\n');
          for (final f in folders) {
            buf.writeln('• ${f['title']} (${f['count']}个)');
          }
          _showDialog('收藏夹', buf.toString());
        }
      } else {
        _showDialog('收藏夹', data['message']?.toString() ?? '获取失败');
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            HardwareKeyboard.instance.isControlPressed &&
            event.logicalKey == LogicalKeyboardKey.keyV) {
          _pasteFromClipboard();
        }
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _linkController,
              maxLines: 3,
              minLines: 2,
              decoration: InputDecoration(
                hintText: '粘贴${widget.platformName}链接',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                suffixIcon: _linkController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () =>
                            setState(() => _linkController.clear()),
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _pasteFromClipboard,
                      icon: const Icon(Icons.content_paste),
                      label: const Text('粘贴链接'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _isDownloading ? null : _download,
                      icon: _isDownloading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download),
                      label: Text(_isDownloading ? '下载中' : '下载'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('工具箱',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
            const SizedBox(height: 8),
            _ToolCard(
                title: '下载作品',
                desc: '下载视频/图集/实况',
                icon: Icons.download,
                onTap: _isDownloading ? null : _download,
                loading: _isDownloading),
            _ToolCard(
                title: '查看作者作品',
                desc: '解析作者信息和合集',
                icon: Icons.info_outline,
                onTap: _isDownloading ? null : _detectLinkInfo),
            _ToolCard(
                title: '批量下载账号',
                desc: '下载该账号全部作品',
                icon: Icons.person,
                onTap: _isDownloading ? null : _batchDownloadAccount),
            _ToolCard(
                title: '批量下载合集',
                desc: '下载合集全部作品',
                icon: Icons.folder,
                onTap: _isDownloading ? null : _batchDownloadMix),
            _ToolCard(
                title: '收藏夹',
                desc: '查看并下载收藏夹内容',
                icon: Icons.bookmark,
                onTap: _isDownloading ? null : _showCollectFolders),
            _ToolCard(
                title: '批量下载',
                desc: '输入框中多个链接批量下载',
                icon: Icons.download_for_offline,
                onTap: _isDownloading ? null : _batchDownload),
            if (widget.platformId != 'xhs') ...[
              _ToolCard(
                  title: '采集评论',
                  desc: '导出评论为CSV文件',
                  icon: Icons.comment,
                  onTap: _isDownloading ? null : _scrapeComments),
              _ToolCard(
                  title: '数据统计',
                  desc: '查看作品点赞/评论/分享数据',
                  icon: Icons.bar_chart,
                  onTap: _isDownloading ? null : _getDataStats),
              _ToolCard(
                  title: '重新下载',
                  desc: '从历史记录重新下载',
                  icon: Icons.history,
                  onTap: _isDownloading ? null : _redownload),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final String title;
  final String desc;
  final IconData icon;
  final VoidCallback? onTap;
  final bool loading;

  const _ToolCard({
    required this.title,
    required this.desc,
    required this.icon,
    this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon,
                      size: 20,
                      color: enabled
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.5)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: enabled
                                  ? null
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.5),
                            )),
                    Text(desc,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            )),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
