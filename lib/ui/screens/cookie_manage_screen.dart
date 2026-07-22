import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../service/cookie_store.dart';
import '../../platform/douyin/douyin_bridge.dart';
import '../../platform/xhs/xhs_bridge.dart';

/// Cookie 管理页面
class CookieManageScreen extends StatefulWidget {
  final String platform;
  final String platformName;

  const CookieManageScreen({
    super.key,
    required this.platform,
    required this.platformName,
  });

  @override
  State<CookieManageScreen> createState() => _CookieManageScreenState();
}

class _CookieManageScreenState extends State<CookieManageScreen> {
  late CookieStore _store;
  List<CookieEntry> _cookies = [];
  String _activeName = '';

  @override
  void initState() {
    super.initState();
    _store = CookieStore(platform: widget.platform);
    _loadCookies();
  }

  Future<void> _loadCookies() async {
    await _store.load();
    setState(() {
      _cookies = _store.getAll();
      _activeName = _store.getActiveName();
    });
  }

  void _applyToBridge(String cookie) {
    if (widget.platform == 'xhs') {
      XhsBridge.setCookie(cookie);
    } else {
      DouyinBridge.setCookie(cookie);
    }
  }

  /// 登录获取 Cookie — 桌面端跳转浏览器，移动端用 InAppWebView
  void _showLoginGetDialog() {
    final loginUrl = widget.platform == 'xhs'
        ? 'https://www.xiaohongshu.com/'
        : 'https://www.douyin.com/';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('登录${widget.platformName}获取 Cookie'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('步骤：'),
              const SizedBox(height: 8),
              Text('1. 点击下方按钮打开${widget.platformName}官网'),
              const Text('2. 在浏览器中登录你的账号'),
              const Text('3. 登录成功后，复制浏览器中的 Cookie'),
              const Text('4. 返回应用，点击"手动输入"粘贴'),
              const SizedBox(height: 16),
              Text('网址: $loginUrl',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await launchUrl(Uri.parse(loginUrl),
                  mode: LaunchMode.externalApplication);
            },
            child: const Text('打开浏览器'),
          ),
        ],
      ),
    );
  }

  void _showManualInputDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final dialogWidth = size.width * 0.85;
        final dialogHeight = size.height * 0.5;
        return AlertDialog(
          title: const Text('输入 Cookie'),
          content: SizedBox(
            width: dialogWidth.clamp(280, 600),
            height: dialogHeight.clamp(200, 400),
            child: TextField(
              controller: controller,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: '粘贴 Cookie 内容...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final cookie = controller.text.trim();
                if (cookie.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cookie 不能为空')),
                    );
                  }
                  return;
                }
                final name = 'Cookie ${_cookies.length + 1}';
                await _store.add(name, cookie);
                await _store.setActiveName(name);
                _applyToBridge(cookie);
                await _loadCookies();
                if (context.mounted) Navigator.pop(context);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已保存')),
                  );
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteDialog(int index, CookieEntry entry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 Cookie'),
        content: Text('确定删除「${entry.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await _store.removeAt(index);
              if (_store.getActiveCookie() == null) _applyToBridge('');
              await _loadCookies();
              if (context.mounted) Navigator.pop(context);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasActive = _store.getActiveCookie() != null &&
        _store.getActiveCookie()!.isNotEmpty;
    final activeCookie = _store.getActiveCookie() ?? '';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _showLoginGetDialog,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('登录获取'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _showManualInputDialog,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('手动输入'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (hasActive)
            Text(
              '当前: $_activeName (${_store.getKeyCount(activeCookie)} 个字段)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            )
          else
            Text(
              '未设置 Cookie，部分功能不可用',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: _cookies.isEmpty
                ? Center(
                    child: Text(
                      '暂无保存的 Cookie',
                      style: TextStyle(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _cookies.length,
                    itemBuilder: (context, index) {
                      final entry = _cookies[index];
                      final isActive = entry.name == _activeName;
                      final keyCount = entry.cookie
                          .split(';')
                          .where((s) => s.contains('='))
                          .length;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: isActive
                            ? Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.5)
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () async {
                            await _store.setActiveName(entry.name);
                            _applyToBridge(entry.cookie);
                            await _loadCookies();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('已切换: ${entry.name}')),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              entry.name,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyLarge,
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isActive) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        4),
                                              ),
                                              child: Text(
                                                '当前',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: Theme.of(
                                                              context)
                                                          .colorScheme
                                                          .onPrimary,
                                                      fontSize: 10,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      Text(
                                        '$keyCount 个字段',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error,
                                  ),
                                  onPressed: () =>
                                      _showDeleteDialog(index, entry),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
