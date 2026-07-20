import 'dart:convert';
import 'dart:io';

/// Python Runner - 通过 Process.run 调用 Python 脚本
class PythonRunner {
  static PythonRunner? _instance;
  late String _scriptDir;
  late String _pythonPath;
  late String _configPath;
  bool _initialized = false;
  final Map<String, String> _cookies = {};

  PythonRunner._();

  static PythonRunner get instance {
    _instance ??= PythonRunner._();
    return _instance!;
  }

  Future<void> init({String? scriptDir, String? pythonPath}) async {
    if (_initialized) return;

    if (scriptDir != null) {
      _scriptDir = scriptDir;
    } else {
      _scriptDir = '${Directory.current.path}/python';
    }

    _pythonPath = pythonPath ?? 'python3';
    _configPath = '$_scriptDir/.cookie_config.json';
    _initialized = true;
  }

  /// 保存 cookie 到配置文件供 Python 脚本读取
  Future<void> saveCookie(String platform, String cookie) async {
    _cookies[platform] = cookie;
    try {
      final config = {
        'douyin_cookie': _cookies['douyin'] ?? '',
        'xhs_cookie': _cookies['xhs'] ?? '',
      };
      final file = File(_configPath);
      await file.writeAsString(jsonEncode(config));
    } catch (e) {
      // ignore
    }
  }

  Future<String> callFunction(
    String moduleName,
    String functionName,
    String argsJson,
  ) async {
    if (!_initialized) {
      return '{"success": false, "message": "PythonRunner not initialized"}';
    }

    try {
      final runnerPath = '$_scriptDir/runner.py';
      final result = await Process.run(
        _pythonPath,
        [runnerPath, moduleName, functionName, argsJson],
        workingDirectory: _scriptDir,
        environment: {'PYTHONPATH': _scriptDir},
      );

      final stdout = result.stdout.toString().trim();

      // 从 stdout 中提取最后一行 JSON（Python 可能输出调试日志）
      String jsonLine = stdout;
      final lines = stdout.split('\n');
      for (final line in lines.reversed) {
        final trimmed = line.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          jsonLine = trimmed;
          break;
        }
      }

      if (result.exitCode == 0) {
        return jsonLine;
      } else {
        final stderr = result.stderr.toString().trim();
        return jsonLine.isNotEmpty
            ? jsonLine
            : '{"success": false, "message": "Python error: $stderr"}';
      }
    } catch (e) {
      return '{"success": false, "message": "Failed to run Python: $e"}';
    }
  }

  Future<String> callDyBridge(String functionName, String argsJson) {
    return callFunction('dy_bridge', functionName, argsJson);
  }

  Future<String> callXhsBridge(String functionName, String argsJson) {
    return callFunction('xhs_bridge', functionName, argsJson);
  }

  Future<bool> checkPython() async {
    try {
      final result = await Process.run(_pythonPath, ['--version']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  String get scriptDir => _scriptDir;
  bool get isReady => _initialized;
}
