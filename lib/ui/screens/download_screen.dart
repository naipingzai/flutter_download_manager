import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/download/douyin_bridge.dart';
import '../../services/download/xhs_bridge.dart';
import '../../services/download/kuaishou_bridge.dart';
import '../../services/storage/cookie_store.dart';
import '../../services/platform/gallery_service.dart';

/// 下载页面 — 粘贴链接 + 所有平台功能入口
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
  bool _isProcessing = false;

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
    final raw = _linkController.text.trim();
    final matches = RegExp(r'https?://[^\s<>"]+').allMatches(raw);
    return matches.map((m) => m.group(0)!).toList();
  }

  Future<void> _syncCookie() async {
    final store = CookieStore(platform: widget.platformId);
    await store.load();
    final cookie = store.getActiveCookie();
    if (cookie == null || cookie.isEmpty) return;
    switch (widget.platformId) {
      case 'xhs':
        await XhsBridge.setCookie(cookie);
        break;
      case 'kuaishou':
        await KuaishouBridge.setCookie(cookie);
        break;
      default:
        await DouyinBridge.setCookie(cookie);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() => _linkController.text = data.text!);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _setProcessing(bool value) {
    if (mounted) setState(() => _isProcessing = value);
  }

  String _getDownloadDir() {
    switch (widget.platformId) {
      case 'xhs':
        return 'XhsDownload';
      case 'kuaishou':
        return 'KsDownload';
      default:
        return 'DyDownload';
    }
  }

  Future<String> _getSavePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final savePath = '${appDir.path}/${_getDownloadDir()}';
    await Directory(savePath).create(recursive: true);
    return savePath;
  }

  // ═══ 核心下载功能 ═══

  /// 下载单个链接
  Future<void> _download() async {
    final url = _extractLink();
    if (url.isEmpty) {
      _showSnackBar('请先输入链接', isError: true);
      return;
    }
    await _syncCookie();
    _setProcessing(true);
    _showSnackBar('正在解析链接...');

    try {
      final savePath = await _getSavePath();
      Map<String, dynamic> result;
      switch (widget.platformId) {
        case 'xhs':
          result = await XhsBridge.parseAndDownload(url, savePath);
          break;
        case 'kuaishou':
          result = await KuaishouBridge.parseAndDownload(url, savePath);
          break;
        default:
          result = await DouyinBridge.parseAndDownload(url, savePath);
      }

      if (!mounted) return;
      if (result['success'] == true) {
        _saveToGallery(result, savePath);
        _showSnackBar('下载成功: ${result['title'] ?? ''}');
      } else {
        final msg = result['message']?.toString() ?? '未知错误';
        if (msg != '已下载过' && msg != '该链接正在下载中') {
          _showSnackBar('下载失败: $msg', isError: true);
        }
      }
    } catch (e) {
      _showSnackBar('下载失败: $e', isError: true);
    } finally {
      _setProcessing(false);
    }
  }

  /// 批量下载多个链接
  Future<void> _batchDownload() async {
    final links = _extractAllLinks();
    if (links.isEmpty) {
      _showSnackBar('请先输入链接', isError: true);
      return;
    }
    if (links.length == 1) {
      await _download();
      return;
    }

    await _syncCookie();
    _setProcessing(true);
    _showSnackBar('检测到 ${links.length} 个链接，开始批量下载...');

    int success = 0, fail = 0;
    for (var i = 0; i < links.length; i++) {
      if (!mounted) return;
      _showSnackBar('正在下载第 ${i + 1}/${links.length} 个...');
      try {
        final savePath = await _getSavePath();
        Map<String, dynamic> result;
        switch (widget.platformId) {
          case 'xhs':
            result = await XhsBridge.parseAndDownload(links[i], savePath);
            break;
          case 'kuaishou':
            result = await KuaishouBridge.parseAndDownload(links[i], savePath);
            break;
          default:
            result = await DouyinBridge.parseAndDownload(links[i], savePath);
        }
        if (result['success'] == true) {
          success++;
          _saveToGallery(result, savePath);
        } else {
          fail++;
        }
      } catch (e) {
        fail++;
      }
    }
    _showSnackBar('批量下载完成: 成功 $success, 失败 $fail');
    _setProcessing(false);
  }

  /// 保存到相册
  Future<void> _saveToGallery(
      Map<String, dynamic> result, String savePath) async {
    try {
      final path = result['path']?.toString() ?? '';
      final albumName = '${widget.platformName}下载';
      await GalleryService.instance.requestPermission();
      if (path.isNotEmpty) {
        await GalleryService.instance.saveToGallery(path, album: albumName);
      } else {
        final dir = Directory(savePath);
        if (await dir.exists()) {
          final files = <String>[];
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) files.add(entity.path);
          }
          await GalleryService.instance
              .saveAllToGallery(files, album: albumName);
        }
      }
    } catch (e) {
      debugPrint('Gallery save failed: $e');
    }
  }

  // ═══ 抖音专属功能 ═══

  /// 检测链接信息（作者/合集）
  Future<void> _detectLinkInfo() async {
    final url = _extractLink();
    if (url.isEmpty) {
      _showSnackBar('请先输入链接', isError: true);
      return;
    }
    await _syncCookie();
    _setProcessing(true);

    try {
      final result = await DouyinBridge.detectLinkInfo(url);
      if (!mounted) return;
      if (result['success'] == true) {
        _showDetectResultDialog(result);
      } else {
        _showSnackBar('检测失败: ${result['message']}', isError: true);
      }
    } catch (e) {
      _showSnackBar('检测失败: $e', isError: true);
    } finally {
      _setProcessing(false);
    }
  }

  void _showDetectResultDialog(Map<String, dynamic> result) {
    final author = result['author'] as Map<String, dynamic>?;
    final mix = result['mix'] as Map<String, dynamic>?;
    final title = result['title']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('链接信息'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title.isNotEmpty) Text('标题: $title'),
              const SizedBox(height: 12),
              if (author != null) ...[
                const Text('👤 作者信息',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('昵称: ${author['nickname'] ?? ''}'),
                Text('UID: ${author['uid'] ?? ''}'),
                Text('抖音号: ${author['unique_id'] ?? ''}'),
                const SizedBox(height: 8),
                if (author['sec_uid'] != null &&
                    (author['sec_uid'] as String).isNotEmpty)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _batchDownloadAuthor(
                          author['sec_uid'], author['nickname'] ?? '未知');
                    },
                    icon: const Icon(Icons.person, size: 16),
                    label: const Text('下载该作者全部作品'),
                  ),
              ],
              if (mix != null) ...[
                const SizedBox(height: 12),
                const Text('📁 合集信息',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('名称: ${mix['mix_name'] ?? ''}'),
                Text('作品数: ${mix['count'] ?? 0}'),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _batchDownloadMix(
                        mix['mix_id'], mix['mix_name'] ?? '未知合集');
                  },
                  icon: const Icon(Icons.folder, size: 16),
                  label: const Text('下载该合集全部作品'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 批量下载作者作品
  Future<void> _batchDownloadAuthor(String secUid, String nickname) async {
    await _syncCookie();
    _setProcessing(true);
    _showSnackBar('开始下载作者作品: $nickname');

    try {
      final savePath = await _getSavePath();
      final result = await DouyinBridge.batchDownloadAccount(
          secUid, nickname, savePath);
      if (!mounted) return;
      if (result['success'] == true) {
        _showSnackBar('✅ ${result['message']}');
      } else {
        _showSnackBar('下载失败: ${result['message']}', isError: true);
      }
    } catch (e) {
      _showSnackBar('下载失败: $e', isError: true);
    } finally {
      _setProcessing(false);
    }
  }

  /// 批量下载合集
  Future<void> _batchDownloadMix(String mixId, String mixName) async {
    await _syncCookie();
    _setProcessing(true);
    _showSnackBar('开始下载合集: $mixName');

    try {
      final savePath = await _getSavePath();
      final result =
          await DouyinBridge.batchDownloadMix(mixId, mixName, savePath);
      if (!mounted) return;
      if (result['success'] == true) {
        _showSnackBar('✅ ${result['message']}');
      } else {
        _showSnackBar('下载失败: ${result['message']}', isError: true);
      }
    } catch (e) {
      _showSnackBar('下载失败: $e', isError: true);
    } finally {
      _setProcessing(false);
    }
  }

  /// 获取收藏夹列表
  Future<void> _listCollectFolders() async {
    await _syncCookie();
    _setProcessing(true);

    try {
      final result = await DouyinBridge.listCollectFolders();
      if (!mounted) return;
      if (result['success'] == true) {
        final folders = result['folders'] as List<dynamic>? ?? [];
        _showCollectFoldersDialog(folders);
      } else {
        _showSnackBar('获取收藏夹失败: ${result['message']}', isError: true);
      }
    } catch (e) {
      _showSnackBar('获取收藏夹失败: $e', isError: true);
    } finally {
      _setProcessing(false);
    }
  }

  void _showCollectFoldersDialog(List<dynamic> folders) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('收藏夹列表'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: folders.isEmpty
              ? const Center(child: Text('没有找到收藏夹'))
              : ListView.builder(
                  itemCount: folders.length,
                  itemBuilder: (context, index) {
                    final folder = folders[index] as Map<String, dynamic>;
                    return ListTile(
                      leading: const Icon(Icons.bookmark),
                      title: Text(folder['name'] ?? '未命名'),
                      subtitle: Text('${folder['count'] ?? 0} 个作品'),
                      trailing: const Icon(Icons.download),
                      onTap: () {
                        Navigator.pop(ctx);
                        _batchDownloadCollect(
                          folder['id']?.toString() ?? '',
                          folder['name'] ?? '未命名',
                        );
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 下载收藏夹
  Future<void> _batchDownloadCollect(String collectId, String collectName) async {
    await _syncCookie();
    _setProcessing(true);
    _showSnackBar('开始下载收藏夹: $collectName');

    try {
      final savePath = await _getSavePath();
      final result = await DouyinBridge.batchDownloadCollect(
          collectId, collectName, savePath);
      if (!mounted) return;
      if (result['success'] == true) {
        _showSnackBar('✅ ${result['message']}');
      } else {
        _showSnackBar('下载失败: ${result['message']}', isError: true);
      }
    } catch (e) {
      _showSnackBar('下载失败: $e', isError: true);
    } finally {
      _setProcessing(false);
    }
  }

  /// 从历史记录重新下载
  Future<void> _redownloadFromHistory() async {
    await _syncCookie();
    _setProcessing(true);
    _showSnackBar('从历史记录重新下载...');

    try {
      final savePath = await _getSavePath();
      final result = await DouyinBridge.redownloadFromHistory(savePath);
      if (!mounted) return;
      if (result['success'] == true) {
        _showSnackBar('✅ ${result['message']}');
      } else {
        _showSnackBar('重新下载失败: ${result['message']}', isError: true);
      }
    } catch (e) {
      _showSnackBar('重新下载失败: $e', isError: true);
    } finally {
      _setProcessing(false);
    }
  }

  /// 录制直播
  Future<void> _recordLive() async {
    final url = _extractLink();
    if (url.isEmpty) {
      _showSnackBar('请先输入直播间链接', isError: true);
      return;
    }
    await _syncCookie();
    _setProcessing(true);
    _showSnackBar('开始录制直播...');

    try {
      final savePath = await _getSavePath();
      Map<String, dynamic> result;
      switch (widget.platformId) {
        case 'kuaishou':
          // 快手直播录制（待实现完整功能）
          _showSnackBar('快手直播录制功能开发中');
          _setProcessing(false);
          return;
        default:
          result = await DouyinBridge.recordLive(url, savePath);
      }
      if (!mounted) return;
      if (result['success'] == true) {
        _showSnackBar('✅ ${result['message']}');
      } else {
        _showSnackBar('录制失败: ${result['message']}', isError: true);
      }
    } catch (e) {
      _showSnackBar('录制失败: $e', isError: true);
    } finally {
      _setProcessing(false);
    }
  }

  // ═══ UI 构建 ═══

  /// 获取平台专属的快捷操作按钮
  List<_QuickAction> _getQuickActions() {
    final actions = <_QuickAction>[
      _QuickAction(
        icon: Icons.download_rounded,
        label: '下载作品',
        description: '粘贴链接直接下载',
        onTap: _download,
      ),
      _QuickAction(
        icon: Icons.content_paste_rounded,
        label: '粘贴链接',
        description: '从剪贴板粘贴',
        onTap: _pasteFromClipboard,
      ),
      _QuickAction(
        icon: Icons.playlist_add_rounded,
        label: '批量下载',
        description: '多个链接批量下载',
        onTap: _batchDownload,
      ),
      _QuickAction(
        icon: Icons.person_search_rounded,
        label: '检测信息',
        description: '解析作者/合集信息',
        onTap: _detectLinkInfo,
      ),
    ];

    // 抖音专属功能
    if (widget.platformId == 'douyin') {
      actions.addAll([
        _QuickAction(
          icon: Icons.person_rounded,
          label: '作者作品',
          description: '下载作者全部作品',
          onTap: _detectLinkInfo, // 先检测再下载
        ),
        _QuickAction(
          icon: Icons.bookmark_rounded,
          label: '收藏夹',
          description: '浏览并下载收藏夹',
          onTap: _listCollectFolders,
        ),
        _QuickAction(
          icon: Icons.live_tv_rounded,
          label: '直播录制',
          description: '录制抖音直播',
          onTap: _recordLive,
        ),
        _QuickAction(
          icon: Icons.history_rounded,
          label: '重新下载',
          description: '从历史记录重新下载',
          onTap: _redownloadFromHistory,
        ),
      ]);
    }

    // 小红书专属功能
    if (widget.platformId == 'xhs') {
      actions.addAll([
        _QuickAction(
          icon: Icons.person_rounded,
          label: '作者作品',
          description: '下载作者全部笔记',
          onTap: () => _showSnackBar('请粘贴作者主页链接后使用批量下载'),
        ),
      ]);
    }

    // 快手专属功能
    if (widget.platformId == 'kuaishou') {
      actions.addAll([
        _QuickAction(
          icon: Icons.live_tv_rounded,
          label: '直播录制',
          description: '录制快手直播',
          onTap: _recordLive,
        ),
      ]);
    }

    return actions;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actions = _getQuickActions();

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 链接输入区域
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _linkController,
                        maxLines: 3,
                        minLines: 2,
                        decoration: InputDecoration(
                          hintText:
                              '粘贴${widget.platformName}链接\n支持多个链接（每行一个）',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
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
                              height: 44,
                              child: OutlinedButton.icon(
                                onPressed: _pasteFromClipboard,
                                icon:
                                    const Icon(Icons.content_paste, size: 18),
                                label: const Text('粘贴链接'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: FilledButton.icon(
                                onPressed: _download,
                                icon: const Icon(Icons.download, size: 18),
                                label: const Text('下载'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 快捷操作区域
              Text(
                '快捷操作',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 2.5,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: actions.length,
                itemBuilder: (context, index) {
                  final action = actions[index];
                  return _QuickActionButton(action: action);
                },
              ),
              const SizedBox(height: 16),

              // 提示信息
              Center(
                child: Text(
                  '下载后请在"任务"页查看进度',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ),

        // 加载遮罩
        if (_isProcessing)
          Container(
            color: Colors.black.withValues(alpha: 0.3),
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('处理中，请稍候...'),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 快捷操作数据
class _QuickAction {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });
}

/// 快捷操作按钮
class _QuickActionButton extends StatelessWidget {
  final _QuickAction action;

  const _QuickActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(action.icon, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      action.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
