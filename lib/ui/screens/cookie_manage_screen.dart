import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design_system/design_system.dart';
import '../../services/storage/cookie_store.dart';
import '../../services/download/douyin_bridge.dart';
import '../../services/download/xhs_bridge.dart';

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
    if (!mounted) return;
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

  Future<void> _openBrowser(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _showLoginDialog() {
    final loginUrl = widget.platform == 'xhs'
        ? 'https://www.xiaohongshu.com/'
        : 'https://www.douyin.com/';

    if (!mounted) return;
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
            onPressed: () {
              Navigator.pop(ctx);
              _openBrowser(loginUrl);
            },
            child: const Text('打开浏览器'),
          ),
        ],
      ),
    );
  }

  Future<void> _showManualInputDialog() async {
    final controller = TextEditingController();
    final size = MediaQuery.of(context).size;
    final dialogWidth = size.width * 0.85;
    final dialogHeight = size.height * 0.5;

    final cookie = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入 Cookie'),
        content: SizedBox(
          width: dialogWidth.clamp(280, 600),
          height: dialogHeight.clamp(200, 400),
          child: AppTextField(
            controller: controller,
            hintText: '粘贴 Cookie 内容...',
            expands: true,
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (cookie == null || cookie.isEmpty) {
      if (cookie != null && mounted) {
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
    }
  }

  Future<void> _selectCookie(CookieEntry entry) async {
    await _store.setActiveName(entry.name);
    _applyToBridge(entry.cookie);
    await _loadCookies();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已切换: ${entry.name}')),
    );
  }

  Future<void> _deleteCookie(int index, CookieEntry entry) async {
    final confirmed = await AppDialog.confirm(
      context,
      title: '删除 Cookie',
      message: '确定删除「${entry.name}」？',
      confirmLabel: '删除',
      cancelLabel: '取消',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    await _store.removeAt(index);
    if (_store.getActiveCookie() == null) _applyToBridge('');
    await _loadCookies();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeCookie = _store.getActiveCookie();
    final hasActive = activeCookie != null && activeCookie.isNotEmpty;
    final keyCount = hasActive ? _store.getKeyCount(activeCookie) : 0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: '登录获取',
                  icon: Icons.login,
                  variant: AppButtonVariant.primary,
                  expand: true,
                  onPressed: _showLoginDialog,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: '手动输入',
                  icon: Icons.edit,
                  variant: AppButtonVariant.secondary,
                  expand: true,
                  onPressed: _showManualInputDialog,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            hasActive
                ? '当前: $_activeName ($keyCount 个字段)'
                : '未设置 Cookie，部分功能不可用',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: hasActive ? scheme.primary : scheme.error,
                ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _cookies.isEmpty
                ? Center(
                    child: Text(
                      '暂无保存的 Cookie',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    itemCount: _cookies.length,
                    itemBuilder: (context, index) {
                      final entry = _cookies[index];
                      final isActive = entry.name == _activeName;
                      final entryKeyCount = entry.cookie
                          .split(';')
                          .where((s) => s.contains('='))
                          .length;
                      return _CookieCard(
                        entry: entry,
                        isActive: isActive,
                        keyCount: entryKeyCount,
                        onTap: () => _selectCookie(entry),
                        onDelete: () => _deleteCookie(index, entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Cookie 卡片 — 复用样式
class _CookieCard extends StatelessWidget {
  final CookieEntry entry;
  final bool isActive;
  final int keyCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _CookieCard({
    required this.entry,
    required this.isActive,
    required this.keyCount,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isActive
          ? scheme.primaryContainer.withValues(alpha: 0.5)
          : scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.name,
                            style: Theme.of(context).textTheme.bodyLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '当前',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: scheme.onPrimary,
                                    fontSize: 10,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '$keyCount 个字段',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete, color: scheme.error),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
