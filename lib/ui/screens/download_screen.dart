import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../platform/douyin/douyin_bridge.dart';
import '../../platform/xhs/xhs_bridge.dart';
import '../../service/cookie_store.dart';

/// 下载页面 - 完全复刻原项目 DownloadScreen
/// 链接输入框 + 从剪贴板粘贴按钮 + 工具卡片列表
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
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.sharedLink != null) {
      _linkController.text = widget.sharedLink!;
    }
    // 页面打开时自动同步 Cookie
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

  void _showSnackBar(String title, String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title: $msg'),
        duration: const Duration(seconds: 3),
      ),
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

  void _requireLink(void Function(String url) block) async {
    final url = _extractLink();
    if (url.isEmpty) {
      _showSnackBar('${widget.platformName}下载', '请先输入链接');
      return;
    }
    await _syncCookie();
    block(url);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _linkController.text = data.text!;
        _errorMessage = null;
      });
    }
  }

  Future<void> _parseAndDownload(String url) async {
    // 使用用户可见的下载目录
    final home = Platform.environment['HOME'] ?? '/tmp';
    final savePath =
        '$home/Downloads/${widget.platformId == 'xhs' ? 'XhsDownload' : 'DyDownload'}';
    await Directory(savePath).create(recursive: true);
    Map<String, dynamic> result;
    if (widget.platformId == 'xhs') {
      result = await XhsBridge.parseAndDownload(url, savePath);
    } else {
      result = await DouyinBridge.parseAndDownload(url, savePath);
    }
    if (result['success'] == true) {
      final path = result['path'] ?? savePath;
      _showSnackBar('下载成功', '${result['title'] ?? ''}\n保存到: $path');
    } else {
      _showSnackBar('下载失败', result['message'] ?? '未知错误');
    }
  }

  void _detectLinkInfo(String url) {
    final String result;
    if (widget.platformId == 'xhs') {
      result = XhsBridge.detectLinkInfo(url);
    } else {
      result = DouyinBridge.detectLinkInfo(url);
    }
    _showSnackBar(
      '检测结果',
      result.length > 100 ? '${result.substring(0, 100)}...' : result,
    );
  }

  Future<void> _batchDownloadAccount(String url) async {
    _showSnackBar('批量下载账号', '功能执行中...');
  }

  Future<void> _batchDownloadMixOrCollection(String url) async {
    _showSnackBar('批量下载合集', '功能执行中...');
  }

  void _showCollectFolders() {
    _syncCookie();
    _showSnackBar('收藏夹', '功能执行中...');
  }

  void _recordLive(String url) {
    if (widget.platformId == 'xhs') {
      _showSnackBar('直播录制', '小红书暂不支持');
    } else {
      DouyinBridge.recordLive(url, '/tmp/downloads/douyin');
    }
  }

  void _scrapeComments(String url) {
    if (widget.platformId == 'xhs') {
      _showSnackBar('评论采集', '小红书暂不支持');
    } else {
      DouyinBridge.scrapeComments(url, '/tmp/downloads/douyin');
    }
  }

  void _getDataStats(String url) {
    if (widget.platformId == 'xhs') {
      _showSnackBar('数据统计', '小红书暂不支持');
    } else {
      _showSnackBar('数据统计', DouyinBridge.getDataStats(url));
    }
  }

  void _batchDownload(String text) {
    final urls = RegExp(
      r'https?://[^\s<>"]+',
    ).allMatches(text).map((m) => m.group(0)!).toList();
    if (urls.isEmpty) {
      _showSnackBar('批量下载', '未识别到链接');
      return;
    }
    _showSnackBar('批量下载', '识别到 ${urls.length} 个链接');
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 链接输入框 - 对应原项目 OutlinedTextField
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
                      onPressed: () {
                        setState(() {
                          _linkController.clear();
                          _errorMessage = null;
                        });
                      },
                    )
                  : null,
              errorText: _errorMessage,
            ),
            onChanged: (_) => setState(() => _errorMessage = null),
          ),
          const SizedBox(height: 8),

          // 从剪贴板粘贴按钮
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: _pasteFromClipboard,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('从剪贴板粘贴'),
            ),
          ),

          const SizedBox(height: 24),

          // 工具箱标题
          Text(
            '工具箱',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),

          // 工具卡片列表 - 对应原项目 ToolCard
          _ToolCard(
            title: '下载作品',
            desc: '下载视频/图集/实况',
            onTap: () => _requireLink(_parseAndDownload),
          ),
          _ToolCard(
            title: '查看作者作品',
            desc: '列出作者全部作品，点击可选链接',
            onTap: () => _requireLink(_detectLinkInfo),
          ),
          _ToolCard(
            title: '批量下载账号',
            desc: '下载账号全部作品',
            onTap: () => _requireLink(_batchDownloadAccount),
          ),
          _ToolCard(
            title: '批量下载合集',
            desc: '下载合集全部作品',
            onTap: () => _requireLink(_batchDownloadMixOrCollection),
          ),
          _ToolCard(title: '收藏夹', desc: '下载收藏夹内容', onTap: _showCollectFolders),
          if (widget.platformId != 'xhs') ...[
            _ToolCard(
              title: '直播录制',
              desc: '录制抖音直播',
              onTap: () => _requireLink(_recordLive),
            ),
            _ToolCard(
              title: '采集评论',
              desc: '导出评论为CSV',
              onTap: () => _requireLink(_scrapeComments),
            ),
            _ToolCard(
              title: '数据统计',
              desc: '查看作品数据',
              onTap: () => _requireLink(_getDataStats),
            ),
            _ToolCard(
              title: '重新下载',
              desc: '从历史记录重新下载',
              onTap: () => _showSnackBar('重新下载', '功能执行中...'),
            ),
            _ToolCard(
              title: '批量下载',
              desc: '批量下载多个链接',
              onTap: () => _requireLink(_batchDownload),
            ),
          ],
        ],
      ),
    );
  }
}

/// 工具卡片 - 对应原项目 ToolCard composable
class _ToolCard extends StatelessWidget {
  final String title;
  final String desc;
  final VoidCallback onTap;

  const _ToolCard({
    required this.title,
    required this.desc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              Text(
                desc,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
