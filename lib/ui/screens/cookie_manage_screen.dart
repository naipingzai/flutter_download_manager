import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  String get _loginUrl => widget.platform == 'xhs'
      ? 'https://www.xiaohongshu.com/'
      : 'https://www.douyin.com/';

  /// 解析登录 URL 中的 Cookie 提取教程链接
  /// 不同平台的 Cookie 提取路径（DevTools → Network → 任意请求 → Cookie）
  String get _cookieExtractionHint => widget.platform == 'xhs'
      ? '小红书：F12 → Network → 任意请求 → 复制 Cookie'
      : '抖音：F12 → Application → Cookies → 复制 sessionid 等';

  /// 关键 Cookie 字段（不同平台不同）
  List<String> get _keyCookieFields => widget.platform == 'xhs'
      ? ['web_session', 'a1', 'webId']
      : ['sessionid', 'ttwid', 'uid_tt', 'sid_tt'];

  Future<void> _openBrowser(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// 解析登录流程：显示步骤说明 + 打开浏览器 + 提供 Cookie 提取提示
  void _showLoginDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.login, size: 20),
            const SizedBox(width: 8),
            Text('登录${widget.platformName}获取 Cookie'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stepItem(1, '点击下方"打开浏览器"按钮'),
              _stepItem(2, '在浏览器中登录您的${widget.platformName}账号'),
              _stepItem(3, '登录成功后，按 F12 打开开发者工具'),
              _stepItem(4, '切换到 Network / Application 选项卡'),
              _stepItem(5, '刷新页面或点击任意链接'),
              _stepItem(6, '找到任意请求 → 复制 Cookie 字符串'),
              _stepItem(7, '返回应用 → "手动输入" → 粘贴'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 16, color: Colors.amber),
                        const SizedBox(width: 6),
                        const Text('提示',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(_cookieExtractionHint,
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('关键字段: ${_keyCookieFields.join(', ')}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('官网地址: $_loginUrl',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openBrowser(_loginUrl);
            },
            icon: const Icon(Icons.open_in_browser, size: 18),
            label: const Text('打开浏览器'),
          ),
        ],
      ),
    );
  }

  Widget _stepItem(int num, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text('$num',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                )),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(text, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  /// 校验 Cookie 字符串
  /// 返回 null 表示合法；返回错误信息表示不合法
  String? _validateCookie(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'Cookie 不能为空';
    if (trimmed.length < 10) return 'Cookie 长度太短（至少 10 字符）';
    if (!trimmed.contains('=')) return 'Cookie 格式错误（缺少 = 符号）';
    if (trimmed.contains('\n') || trimmed.contains('\r')) {
      return 'Cookie 不能包含换行符';
    }
    return null;
  }

  /// 显示手动输入对话框（支持从剪贴板自动获取）
  Future<void> _showManualInputDialog() async {
    // 1) 先尝试从剪贴板读取
    String initialText = '';
    String? clipboardHint;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && data!.text!.isNotEmpty) {
        final text = data.text!.trim();
        if (_validateCookie(text) == null) {
          initialText = text;
          clipboardHint = '已从剪贴板识别到有效 Cookie';
        } else {
          clipboardHint = '剪贴板内容不是有效 Cookie，请手动粘贴';
        }
      }
    } catch (_) {}

    if (!mounted) return;
    final controller = TextEditingController(text: initialText);
    final size = MediaQuery.of(context).size;
    final dialogWidth = size.width * 0.85;
    final dialogHeight = size.height * 0.5;

    final cookie = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          // 实时解析显示字段数
          final liveText = controller.text;
          final keyCount = _countKeyFields(liveText);
          final allCount = _countAllFields(liveText);
          final hasError =
              liveText.isNotEmpty && _validateCookie(liveText) != null;

          return AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.edit_note, size: 20),
                SizedBox(width: 8),
                Text('输入 Cookie'),
              ],
            ),
            content: SizedBox(
              width: dialogWidth.clamp(320, 640),
              height: dialogHeight.clamp(240, 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (clipboardHint != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: initialText.isNotEmpty
                            ? Colors.green.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            initialText.isNotEmpty
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                            size: 16,
                            color: initialText.isNotEmpty
                                ? Colors.green
                                : Colors.orange,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              clipboardHint,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: AppTextField(
                      controller: controller,
                      hintText: '粘贴 Cookie 内容...',
                      expands: true,
                      contentPadding: const EdgeInsets.all(12),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 14,
                          color: hasError
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        '已识别: $allCount 个字段',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasError
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (keyCount > 0) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.verified,
                            size: 14, color: Colors.green.shade700),
                        const SizedBox(width: 4),
                        Text(
                          '关键字段: $keyCount/${_keyCookieFields.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null && mounted) {
                    controller.text = data!.text!.trim();
                    setState(() {});
                  }
                },
                icon: const Icon(Icons.content_paste, size: 16),
                label: const Text('从剪贴板'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('保存'),
              ),
            ],
          );
        },
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

    // 校验
    final validationError = _validateCookie(cookie);
    if (validationError != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(validationError),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
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
        SnackBar(
          content: Text(
            '已保存 (${_countAllFields(cookie)} 个字段)',
          ),
        ),
      );
    }
  }

  /// 统计所有 key=value 字段
  int _countAllFields(String cookie) {
    if (cookie.trim().isEmpty) return 0;
    return cookie
        .split(';')
        .where((s) => s.contains('=') && s.trim().isNotEmpty)
        .length;
  }

  /// 统计关键字段命中数
  int _countKeyFields(String cookie) {
    if (cookie.trim().isEmpty) return 0;
    int count = 0;
    for (final key in _keyCookieFields) {
      if (cookie.contains('$key=')) count++;
    }
    return count;
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
    required this.onDelete,
    required this.onTap,
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
