import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../platform/douyin/douyin_bridge.dart';
import '../../platform/xhs/xhs_bridge.dart';
import '../../service/cookie_store.dart';
import '../../service/gallery_service.dart';

/// 下载页面 — 粘贴链接 + 下载
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

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() => _linkController.text = data.text!);
    }
  }

  void _showDialog(String title, String content) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _download() async {
    final url = _extractLink();
    if (url.isEmpty) {
      _showDialog('提示', '请先输入链接');
      return;
    }
    await _syncCookie();
    setState(() => _isDownloading = true);

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final savePath =
          '${appDir.path}/${widget.platformId == 'xhs' ? 'XhsDownload' : 'DyDownload'}';
      await Directory(savePath).create(recursive: true);

      Map<String, dynamic> result;
      if (widget.platformId == 'xhs') {
        result = await XhsBridge.parseAndDownload(url, savePath);
      } else {
        result = await DouyinBridge.parseAndDownload(url, savePath);
      }

      if (!mounted) return;
      if (result['success'] == true) {
        final path = result['path']?.toString() ?? '';
        final albumName =
            widget.platformId == 'xhs' ? '小红书下载' : '抖音下载';

        await GalleryService.instance.requestPermission();
        if (path.isNotEmpty) {
          await GalleryService.instance
              .saveToGallery(path, album: albumName);
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
        _showDialog('下载成功', '${result['title'] ?? ''}\n已保存到相册');
      } else {
        _showDialog('下载失败', result['message']?.toString() ?? '未知错误');
      }
    } catch (e) {
      _showDialog('下载失败', '$e');
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
                      label: Text(_isDownloading ? '下载中...' : '下载'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_isDownloading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text('正在解析链接并下载...'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
