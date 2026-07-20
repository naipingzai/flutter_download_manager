import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Python Runner - 通过 Process.run 调用 Python 脚本
class PythonRunner {
  static PythonRunner? _instance;
  late String _scriptDir;
  late String _pythonPath;
  bool _initialized = false;

  PythonRunner._();

  static PythonRunner get instance {
    _instance ??= PythonRunner._();
    return _instance!;
  }

  /// 初始化，确定脚本路径和 Python 路径
  Future<void> init({String? scriptDir, String? pythonPath}) async {
    if (_initialized) return;

    if (scriptDir != null) {
      _scriptDir = scriptDir;
    } else {
      if (Platform.isAndroid || Platform.isIOS) {
        final appDir = await getApplicationDocumentsDirectory();
        _scriptDir = '${appDir.path}/python';
      } else {
        // Linux/Mac: 使用项目目录下的 python 目录
        _scriptDir = '${Directory.current.path}/python';
      }
    }

    _pythonPath = pythonPath ?? 'python3';
    _initialized = true;
  }

  /// 调用 Python 模块函数
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

      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      } else {
        final stderr = result.stderr.toString().trim();
        final stdout = result.stdout.toString().trim();
        return stdout.isNotEmpty
            ? stdout
            : '{"success": false, "message": "Python error: $stderr"}';
      }
    } catch (e) {
      return '{"success": false, "message": "Failed to run Python: $e"}';
    }
  }

  /// 调用抖音 bridge 函数
  Future<String> callDyBridge(String functionName, String argsJson) {
    return callFunction('dy_bridge', functionName, argsJson);
  }

  /// 调用小红书 bridge 函数
  Future<String> callXhsBridge(String functionName, String argsJson) {
    return callFunction('xhs_bridge', functionName, argsJson);
  }

  /// 检查 Python 是否可用
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
