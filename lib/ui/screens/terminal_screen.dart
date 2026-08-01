import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../services/python/python_runner.dart';
import '../../services/storage/cookie_store.dart';

/// 终端模拟器 — 作为 Python 脚本的输入输出壳
/// 用户输入命令 → 调用 Python → 显示输出
class TerminalScreen extends StatefulWidget {
  final String platformId;
  final String platformName;

  const TerminalScreen({
    super.key,
    required this.platformId,
    required this.platformName,
  });

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_TerminalLine> _lines = [];
  final List<String> _history = [];
  bool _isRunning = false;
  String _savePath = '';

  @override
  void initState() {
    super.initState();
    _initTerminal();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initTerminal() async {
    // 初始化保存路径
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dirName = switch (widget.platformId) {
        'xhs' => 'XhsDownload',
        'kuaishou' => 'KsDownload',
        _ => 'DyDownload',
      };
      _savePath = '${appDir.path}/$dirName';
      await Directory(_savePath).create(recursive: true);
    } catch (e) {
      _savePath = '/tmp/Download';
    }

    // 同步 Cookie
    await _syncCookie();

    // 显示欢迎信息
    _addOutput('╔══════════════════════════════════════════════════╗', _LineType.system);
    _addOutput('║  高级下载器 — ${widget.platformName}终端', _LineType.system);
    _addOutput('║  内嵌 Python 环境', _LineType.system);
    _addOutput('╚══════════════════════════════════════════════════╝', _LineType.system);
    _addOutput('', _LineType.system);
    _addOutput('📁 下载目录: $_savePath', _LineType.info);
    _addOutput('', _LineType.system);
    _showHelp();
  }

  void _showHelp() {
    _addOutput('─── 可用命令 ───', _LineType.system);

    // 通用命令
    _addOutput('  help / ?        显示帮助', _LineType.help);
    _addOutput('  clear / cls     清屏', _LineType.help);
    _addOutput('  cookie <内容>   设置 Cookie', _LineType.help);
    _addOutput('  status          查看 Python 环境状态', _LineType.help);

    // 直接粘贴链接下载
    _addOutput('', _LineType.system);
    _addOutput('─── 直接粘贴链接即可下载 ───', _LineType.system);
    _addOutput('  粘贴链接后回车自动下载', _LineType.help);

    if (widget.platformId == 'douyin') {
      _addOutput('', _LineType.system);
      _addOutput('─── 抖音专属命令 ───', _LineType.system);
      _addOutput('  detect <链接>       检测链接(作者/合集信息)', _LineType.help);
      _addOutput('  author <sec_uid>    下载作者全部作品', _LineType.help);
      _addOutput('  collect             浏览收藏夹', _LineType.help);
      _addOutput('  collect <id> <名称> 下载指定收藏夹', _LineType.help);
      _addOutput('  mix <id> <名称>     下载合集', _LineType.help);
      _addOutput('  live <链接>         录制直播', _LineType.help);
      _addOutput('  retry               从历史记录重新下载', _LineType.help);
    }

    _addOutput('', _LineType.system);
  }

  Future<void> _syncCookie() async {
    try {
      final store = CookieStore(platform: widget.platformId);
      await store.load();
      final cookie = store.getActiveCookie();
      if (cookie != null && cookie.isNotEmpty) {
        _addOutput('🍪 Cookie 已加载 (${store.getActiveName()})', _LineType.info);
      } else {
        _addOutput('⚠️ 未设置 Cookie，部分功能可能不可用', _LineType.warning);
        _addOutput('   使用 cookie <内容> 命令设置', _LineType.warning);
      }
    } catch (e) {
      _addOutput('⚠️ Cookie 加载失败: $e', _LineType.error);
    }
  }

  void _addOutput(String text, _LineType type) {
    setState(() {
      _lines.add(_TerminalLine(text: text, type: type));
    });
    // 自动滚动到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 执行用户输入
  Future<void> _executeCommand(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    // 添加到历史
    _history.insert(0, trimmed);

    // 显示用户输入
    _addOutput('❯ $trimmed', _LineType.userInput);

    if (_isRunning) {
      _addOutput('⚠️ 有命令正在执行，请等待完成', _LineType.warning);
      return;
    }

    _setRunning(true);

    try {
      await _processCommand(trimmed);
    } catch (e) {
      _addOutput('❌ 错误: $e', _LineType.error);
    } finally {
      _setRunning(false);
    }
  }

  Future<void> _processCommand(String input) async {
    final parts = input.split(RegExp(r'\s+'));
    final cmd = parts[0].toLowerCase();

    switch (cmd) {
      case 'help':
      case '?':
        _showHelp();
        break;

      case 'clear':
      case 'cls':
        setState(() => _lines.clear());
        break;

      case 'cookie':
        await _handleCookie(input.substring(cmd.length).trim());
        break;

      case 'status':
        await _handleStatus();
        break;

      case 'detect':
        if (parts.length < 2) {
          _addOutput('用法: detect <链接>', _LineType.error);
        } else {
          await _handleDetect(parts[1]);
        }
        break;

      case 'author':
        if (parts.length < 2) {
          _addOutput('用法: author <sec_uid>', _LineType.error);
        } else {
          await _handleBatchAuthor(parts[1]);
        }
        break;

      case 'collect':
        if (parts.length < 2) {
          await _handleListCollects();
        } else {
          final collectId = parts[1];
          final collectName = parts.length > 2 ? parts.sublist(2).join(' ') : '收藏夹_$collectId';
          await _handleBatchCollect(collectId, collectName);
        }
        break;

      case 'mix':
        if (parts.length < 2) {
          _addOutput('用法: mix <mix_id> [名称]', _LineType.error);
        } else {
          final mixId = parts[1];
          final mixName = parts.length > 2 ? parts.sublist(2).join(' ') : '合集_$mixId';
          await _handleBatchMix(mixId, mixName);
        }
        break;

      case 'live':
        if (parts.length < 2) {
          _addOutput('用法: live <直播间链接>', _LineType.error);
        } else {
          await _handleLive(input.substring(cmd.length).trim());
        }
        break;

      case 'retry':
        await _handleRetry();
        break;

      default:
        // 不是命令，当作链接处理
        if (input.contains('http://') || input.contains('https://')) {
          await _handleDownload(input);
        } else {
          _addOutput('❓ 未知命令: $cmd', _LineType.error);
          _addOutput('   输入 help 查看可用命令', _LineType.help);
        }
    }
  }

  void _setRunning(bool value) {
    setState(() => _isRunning = value);
  }

  // ═══ 命令处理 ═══

  Future<void> _handleDownload(String link) async {
    _addOutput('🔍 解析链接中...', _LineType.info);

    try {
      final result = await _callPython(
        module: _getModuleName(),
        function: 'parse_link',
        args: [link, _savePath, ''],
      );
      _printResult(result);
    } catch (e) {
      _addOutput('❌ 下载失败: $e', _LineType.error);
    }
  }

  Future<void> _handleCookie(String cookie) async {
    if (cookie.isEmpty) {
      _addOutput('用法: cookie <Cookie内容>', _LineType.error);
      return;
    }
    try {
      final result = await _callPython(
        module: _getModuleName(),
        function: 'set_cookie',
        args: [cookie],
      );
      _addOutput('✅ Cookie 已设置', _LineType.success);
      if (result is Map && result['key_count'] != null) {
        _addOutput('   字段数: ${result['key_count']}', _LineType.info);
      }
    } catch (e) {
      _addOutput('❌ 设置失败: $e', _LineType.error);
    }
  }

  Future<void> _handleStatus() async {
    try {
      final status = await PythonRunner.instance.getStatus();
      _addOutput('─── Python 环境状态 ───', _LineType.system);
      _addOutput('  可用: ${status['available']}', _LineType.info);
      _addOutput('  版本: ${status['version']}', _LineType.info);
      _addOutput('  内嵌: ${status['embedded']}', _LineType.info);
      _addOutput('  平台: ${status['platform']}', _LineType.info);
      if (status['executable'] != null) {
        _addOutput('  路径: ${status['executable']}', _LineType.info);
      }
    } catch (e) {
      _addOutput('❌ 获取状态失败: $e', _LineType.error);
    }
  }

  Future<void> _handleDetect(String link) async {
    _addOutput('🔍 检测链接信息...', _LineType.info);
    try {
      final result = await _callPython(
        module: 'dy_bridge',
        function: 'detect_link_info',
        args: [link],
      );
      if (result is Map) {
        final r = Map<String, dynamic>.from(result);
        if (r['success'] == true) {
          final author = r['author'] as Map<String, dynamic>?;
          final mix = r['mix'] as Map<String, dynamic>?;
          _addOutput('📝 标题: ${r['title'] ?? ''}', _LineType.info);
          if (author != null) {
            _addOutput('👤 作者: ${author['nickname']} (UID: ${author['uid']})', _LineType.info);
            _addOutput('   sec_uid: ${author['sec_uid']}', _LineType.info);
            _addOutput('   抖音号: ${author['unique_id']}', _LineType.info);
            _addOutput('', _LineType.system);
            _addOutput('   下载作者全部作品: author ${author['sec_uid']}', _LineType.help);
          }
          if (mix != null) {
            _addOutput('📁 合集: ${mix['mix_name']} (${mix['count']}个作品)', _LineType.info);
            _addOutput('   mix_id: ${mix['mix_id']}', _LineType.info);
            _addOutput('', _LineType.system);
            _addOutput('   下载合集: mix ${mix['mix_id']} ${mix['mix_name']}', _LineType.help);
          }
        } else {
          _addOutput('❌ ${r['message'] ?? '检测失败'}', _LineType.error);
        }
      }
    } catch (e) {
      _addOutput('❌ 检测失败: $e', _LineType.error);
    }
  }

  Future<void> _handleBatchAuthor(String secUid) async {
    _addOutput('⬇️ 开始下载作者全部作品...', _LineType.info);
    try {
      final result = await _callPython(
        module: 'dy_bridge',
        function: 'batch_download_account',
        args: [secUid, '作者_$secUid', _savePath, ''],
      );
      _printResult(result);
    } catch (e) {
      _addOutput('❌ 下载失败: $e', _LineType.error);
    }
  }

  Future<void> _handleListCollects() async {
    _addOutput('📚 获取收藏夹列表...', _LineType.info);
    try {
      final result = await _callPython(
        module: 'dy_bridge',
        function: 'list_collect_folders',
        args: [],
      );
      if (result is Map) {
        final r = Map<String, dynamic>.from(result);
        if (r['success'] == true) {
          final folders = r['folders'] as List<dynamic>? ?? [];
          if (folders.isEmpty) {
            _addOutput('没有找到收藏夹', _LineType.warning);
            return;
          }
          _addOutput('─── 收藏夹列表 ───', _LineType.system);
          for (var i = 0; i < folders.length; i++) {
            final f = folders[i] as Map<String, dynamic>;
            _addOutput('  [${i + 1}] ${f['name']} (${f['count']}个作品)', _LineType.info);
            _addOutput('      ID: ${f['id']}', _LineType.info);
          }
          _addOutput('', _LineType.system);
          _addOutput('下载收藏夹: collect <ID> <名称>', _LineType.help);
        } else {
          _addOutput('❌ ${r['message']}', _LineType.error);
        }
      }
    } catch (e) {
      _addOutput('❌ 获取失败: $e', _LineType.error);
    }
  }

  Future<void> _handleBatchCollect(String collectId, String collectName) async {
    _addOutput('⬇️ 开始下载收藏夹: $collectName...', _LineType.info);
    try {
      final result = await _callPython(
        module: 'dy_bridge',
        function: 'batch_download_collect',
        args: [collectId, collectName, _savePath, ''],
      );
      _printResult(result);
    } catch (e) {
      _addOutput('❌ 下载失败: $e', _LineType.error);
    }
  }

  Future<void> _handleBatchMix(String mixId, String mixName) async {
    _addOutput('⬇️ 开始下载合集: $mixName...', _LineType.info);
    try {
      final result = await _callPython(
        module: 'dy_bridge',
        function: 'batch_download_mix',
        args: [mixId, mixName, _savePath, ''],
      );
      _printResult(result);
    } catch (e) {
      _addOutput('❌ 下载失败: $e', _LineType.error);
    }
  }

  Future<void> _handleLive(String liveUrl) async {
    _addOutput('🎥 开始录制直播...', _LineType.info);
    try {
      final result = await _callPython(
        module: 'dy_bridge',
        function: 'record_live',
        args: [liveUrl, _savePath, ''],
      );
      _printResult(result);
    } catch (e) {
      _addOutput('❌ 录制失败: $e', _LineType.error);
    }
  }

  Future<void> _handleRetry() async {
    _addOutput('🔄 从历史记录重新下载...', _LineType.info);
    try {
      final result = await _callPython(
        module: 'dy_bridge',
        function: 'redownload_from_history',
        args: [_savePath, ''],
      );
      _printResult(result);
    } catch (e) {
      _addOutput('❌ 重新下载失败: $e', _LineType.error);
    }
  }

  // ═══ 工具方法 ═══

  String _getModuleName() {
    switch (widget.platformId) {
      case 'xhs':
        return 'xhs_bridge';
      case 'kuaishou':
        return 'ks_bridge';
      default:
        return 'dy_bridge';
    }
  }

  Future<dynamic> _callPython({
    required String module,
    required String function,
    required List<dynamic> args,
  }) async {
    return await PythonRunner.instance.callPython(
      module: module,
      function: function,
      args: args,
    );
  }

  void _printResult(dynamic result) {
    if (result is Map) {
      final r = Map<String, dynamic>.from(result);
      if (r['success'] == true) {
        _addOutput('✅ ${r['title'] ?? '完成'}', _LineType.success);
        if (r['message'] != null && r['message'].toString().isNotEmpty) {
          _addOutput('   ${r['message']}', _LineType.info);
        }
        if (r['author'] != null) {
          _addOutput('   作者: ${r['author']}', _LineType.info);
        }
        if (r['path'] != null) {
          _addOutput('   路径: ${r['path']}', _LineType.info);
        }
        if (r['size'] != null && r['size'] > 0) {
          final mb = (r['size'] as int) / (1024 * 1024);
          _addOutput('   大小: ${mb.toStringAsFixed(1)} MB', _LineType.info);
        }
      } else {
        _addOutput('❌ ${r['message'] ?? '失败'}', _LineType.error);
      }
    } else {
      _addOutput('$result', _LineType.output);
    }
  }

  // ═══ UI ═══

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // 终端输出区域
        Expanded(
          child: Container(
            color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFAFAFA),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _lines.length,
              itemBuilder: (context, index) {
                final line = _lines[index];
                return _buildTerminalLine(line, isDark);
              },
            ),
          ),
        ),

        // 运行状态指示器
        if (_isRunning)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: scheme.primaryContainer,
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '执行中...',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),

        // 输入区域
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
            border: Border(
              top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          padding: EdgeInsets.only(
            left: 12,
            right: 8,
            top: 8,
            bottom: MediaQuery.of(context).viewInsets.bottom + 8,
          ),
          child: Row(
            children: [
              Text(
                '❯ ',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _inputController,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: '输入链接或命令...',
                    hintStyle: TextStyle(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (value) {
                    _executeCommand(value);
                    _inputController.clear();
                  },
                  enabled: !_isRunning,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, size: 20),
                onPressed: _isRunning
                    ? null
                    : () {
                        _executeCommand(_inputController.text);
                        _inputController.clear();
                      },
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.content_paste, size: 18),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    _inputController.text = data!.text!;
                  }
                },
                visualDensity: VisualDensity.compact,
                tooltip: '粘贴',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTerminalLine(_TerminalLine line, bool isDark) {
    final color = switch (line.type) {
      _LineType.userInput => isDark ? Colors.cyanAccent : Colors.blue,
      _LineType.output => isDark ? Colors.white : Colors.black87,
      _LineType.info => isDark ? Colors.grey[300] : Colors.grey[700],
      _LineType.success => Colors.green,
      _LineType.warning => Colors.orange,
      _LineType.error => Colors.red,
      _LineType.help => isDark ? Colors.grey[500] : Colors.grey[500],
      _LineType.system => isDark ? Colors.blue[300] : Colors.blue[700],
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        line.text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.4,
          color: color,
        ),
      ),
    );
  }
}

enum _LineType {
  userInput,
  output,
  info,
  success,
  warning,
  error,
  help,
  system,
}

class _TerminalLine {
  final String text;
  final _LineType type;
  const _TerminalLine({required this.text, required this.type});
}
