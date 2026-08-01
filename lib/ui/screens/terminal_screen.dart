import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../../services/python/embedded_python_manager.dart';

/// 终端模拟器 — 直接启动 Python 子进程，转发 stdin/stdout
/// Python 脚本自己负责打印菜单、等待输入、执行操作
/// Flutter 只做 I/O 转发，不干预任何交互逻辑
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
  Process? _process;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  @override
  void initState() {
    super.initState();
    _startPythonProcess();
  }

  @override
  void dispose() {
    _killProcess();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 启动 Python 子进程，运行交互式主脚本
  Future<void> _startPythonProcess() async {
    final manager = EmbeddedPythonManager.instance;
    await manager.initialize();

    if (!manager.isAvailable) {
      _addOutput('❌ Python 环境不可用', _LineType.error);
      _addOutput('请先运行: bash scripts/download_python.sh', _LineType.error);
      return;
    }

    // 查找主入口脚本
    final scriptsDir = manager.scriptsDir;
    final mainScript = _findMainScript(scriptsDir);
    if (mainScript == null) {
      _addOutput('❌ 未找到主入口脚本', _LineType.error);
      _addOutput('脚本目录: $scriptsDir', _LineType.info);
      return;
    }

    _addOutput('🐍 启动 Python 子进程...', _LineType.info);

    try {
      // 设置环境变量告诉 Python 脚本当前平台
      final env = <String, String>{
        'PLATFORM_ID': widget.platformId,
        'PLATFORM_NAME': widget.platformName,
      };

      if (manager.pythonHome != null) {
        env['PYTHONHOME'] = manager.pythonHome!;
      }

      // 启动 Python 子进程
      _process = await Process.start(
        manager.executablePath!,
        [mainScript],
        environment: env,
        workingDirectory: scriptsDir,
        mode: ProcessStartMode.normal,
      );

      _isRunning = true;

      // 监听 stdout
      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _addOutput(line, _LineType.output);
      });

      // 监听 stderr
      _stderrSub = _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _addOutput(line, _LineType.error);
      });

      // 监听进程退出
      _process!.exitCode.then((code) {
        _isRunning = false;
        _addOutput('\n🐍 Python 进程已退出 (exit code: $code)', _LineType.info);
        if (mounted) setState(() {});
      });

      if (mounted) setState(() {});
    } catch (e) {
      _addOutput('❌ 启动失败: $e', _LineType.error);
    }
  }

  /// 查找主入口脚本
  String? _findMainScript(String? scriptsDir) {
    // 按优先级查找
    final candidates = [
      if (scriptsDir != null) '$scriptsDir/main_cli.py',
      if (scriptsDir != null) '${Directory(scriptsDir).parent.path}/main_cli.py',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }

    // 查找 assets/python/main_cli.py
    final assetScript = '${Directory.current.path}/assets/python/main_cli.py';
    if (File(assetScript).existsSync()) return assetScript;

    return null;
  }

  /// 发送用户输入到 Python 进程的 stdin
  void _sendInput(String input) {
    if (_process == null || !_isRunning) {
      _addOutput('❌ Python 进程未运行', _LineType.error);
      return;
    }

    _process!.stdin.writeln(input);
    _process!.stdin.flush();
  }

  void _addOutput(String text, _LineType type) {
    if (!mounted) return;
    setState(() {
      _lines.add(_TerminalLine(text: text, type: type));
    });
    // 自动滚动到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _killProcess() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _process?.kill(ProcessSignal.sigterm);
    _process = null;
    _isRunning = false;
  }

  /// 重启 Python 进程
  Future<void> _restartProcess() async {
    _killProcess();
    setState(() => _lines.clear());
    await _startPythonProcess();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // 工具栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF0F0F0),
          child: Row(
            children: [
              Icon(
                _isRunning ? Icons.circle : Icons.circle_outlined,
                size: 10,
                color: _isRunning ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                _isRunning ? 'Python 运行中' : 'Python 未运行',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _restartProcess,
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('重启', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ),

        // 终端输出区域
        Expanded(
          child: Container(
            color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFAFAFA),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: _lines.length,
              itemBuilder: (context, index) {
                final line = _lines[index];
                return Text(
                  line.text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.3,
                    color: _getLineColor(line.type, isDark),
                  ),
                );
              },
            ),
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
            left: 8,
            right: 4,
            top: 6,
            bottom: MediaQuery.of(context).viewInsets.bottom + 6,
          ),
          child: Row(
            children: [
              Text(
                '❯ ',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _inputController,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: '输入回车发送到 Python...',
                    hintStyle: TextStyle(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      // 添加到历史
                      _history.insert(0, value);
                      // 显示用户输入（带 echo）
                      _addOutput('❯ $value', _LineType.userInput);
                      // 发送到 Python
                      _sendInput(value);
                      _inputController.clear();
                    }
                  },
                  enabled: _isRunning,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, size: 18),
                onPressed: _isRunning
                    ? () {
                        final value = _inputController.text;
                        if (value.isNotEmpty) {
                          _history.insert(0, value);
                          _addOutput('❯ $value', _LineType.userInput);
                          _sendInput(value);
                          _inputController.clear();
                        }
                      }
                    : null,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.content_paste, size: 16),
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

  Color _getLineColor(_LineType type, bool isDark) {
    switch (type) {
      case _LineType.output:
        return isDark ? const Color(0xFFD4D4D4) : const Color(0xFF1E1E1E);
      case _LineType.userInput:
        return isDark ? Colors.cyanAccent : Colors.blue;
      case _LineType.info:
        return isDark ? Colors.grey[400]! : Colors.grey[700]!;
      case _LineType.error:
        return isDark ? const Color(0xFFf48771) : const Color(0xFFcd3131);
    }
  }
}

enum _LineType {
  output,    // Python 标准输出
  userInput, // 用户输入（echo）
  info,      // Flutter 信息提示
  error,     // 错误输出
}

class _TerminalLine {
  final String text;
  final _LineType type;
  const _TerminalLine({required this.text, required this.type});
}
