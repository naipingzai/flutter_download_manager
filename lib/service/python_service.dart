import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

/// Python 解释器 FFI 绑定类型
typedef NativePythonInitC = Bool Function(Pointer<Utf8>, Pointer<Utf8>);
typedef NativePythonInitDart = bool Function(Pointer<Utf8>, Pointer<Utf8>);

typedef NativePythonDestroyC = Void Function();
typedef NativePythonDestroyDart = void Function();

typedef NativePythonCallC =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef NativePythonCallDart =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef NativePythonExecScriptC =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef NativePythonExecScriptDart =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef NativePythonIsReadyC = Bool Function();
typedef NativePythonIsReadyDart = bool Function();

typedef NativePythonGetVersionC = Pointer<Utf8> Function();
typedef NativePythonGetVersionDart = Pointer<Utf8> Function();

typedef NativePythonSetEnvC = Void Function(Pointer<Utf8>, Pointer<Utf8>);
typedef NativePythonSetEnvDart = void Function(Pointer<Utf8>, Pointer<Utf8>);

typedef NativePythonAddPathC = Void Function(Pointer<Utf8>);
typedef NativePythonAddPathDart = void Function(Pointer<Utf8>);

/// Python 服务 - 管理嵌入式 Python 解释器
/// 通过 C++ 层的 python_bridge 调用原始 Python 脚本
class PythonService {
  static PythonService? _instance;
  late DynamicLibrary _lib;

  late NativePythonInitDart _init;
  late NativePythonDestroyDart _destroy;
  late NativePythonCallDart _call;
  late NativePythonExecScriptDart _execScript;
  late NativePythonIsReadyDart _isReady;
  late NativePythonGetVersionDart _getVersion;
  late NativePythonSetEnvDart _setEnv;
  late NativePythonAddPathDart _addPath;

  bool _initialized = false;
  String _scriptDir = '';

  PythonService._();

  static PythonService get instance {
    _instance ??= PythonService._();
    return _instance!;
  }

  /// 初始化加载动态库并绑定函数
  void _loadLib() {
    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libdownload_engine.so');
    } else if (Platform.isLinux) {
      _lib = DynamicLibrary.open('libdownload_engine.so');
    } else if (Platform.isMacOS) {
      _lib = DynamicLibrary.open('libdownload_engine.dylib');
    } else if (Platform.isWindows) {
      _lib = DynamicLibrary.open('download_engine.dll');
    }

    _init = _lib.lookupFunction<NativePythonInitC, NativePythonInitDart>(
      'python_bridge_init',
    );
    _destroy = _lib
        .lookupFunction<NativePythonDestroyC, NativePythonDestroyDart>(
          'python_bridge_destroy',
        );
    _call = _lib.lookupFunction<NativePythonCallC, NativePythonCallDart>(
      'python_bridge_call',
    );
    _execScript = _lib
        .lookupFunction<NativePythonExecScriptC, NativePythonExecScriptDart>(
          'python_bridge_exec_script',
        );
    _isReady = _lib
        .lookupFunction<NativePythonIsReadyC, NativePythonIsReadyDart>(
          'python_bridge_is_ready',
        );
    _getVersion = _lib
        .lookupFunction<NativePythonGetVersionC, NativePythonGetVersionDart>(
          'python_bridge_get_version',
        );
    _setEnv = _lib.lookupFunction<NativePythonSetEnvC, NativePythonSetEnvDart>(
      'python_bridge_set_env',
    );
    _addPath = _lib
        .lookupFunction<NativePythonAddPathC, NativePythonAddPathDart>(
          'python_bridge_add_path',
        );
  }

  /// 初始化 Python 解释器
  Future<bool> init({String? pythonHome, String? scriptDir}) async {
    if (_initialized) return true;

    _loadLib();

    if (scriptDir != null) {
      _scriptDir = scriptDir;
    } else {
      if (Platform.isAndroid || Platform.isIOS) {
        final appDir = await getApplicationDocumentsDirectory();
        _scriptDir = '${appDir.path}/python';
      } else {
        _scriptDir = 'python';
      }
    }

    final homePtr = (pythonHome ?? '').toNativeUtf8();
    final scriptPtr = _scriptDir.toNativeUtf8();

    try {
      _initialized = _init(homePtr, scriptPtr);
      if (_initialized) addPath(_scriptDir);
      return _initialized;
    } finally {
      calloc.free(homePtr);
      calloc.free(scriptPtr);
    }
  }

  void destroy() {
    if (_initialized) {
      _destroy();
      _initialized = false;
    }
  }

  bool get isReady => _initialized && _isReady();

  String getVersion() => _getVersion().toDartString();

  void setEnv(String key, String value) {
    final keyPtr = key.toNativeUtf8();
    final valuePtr = value.toNativeUtf8();
    try {
      _setEnv(keyPtr, valuePtr);
    } finally {
      calloc.free(keyPtr);
      calloc.free(valuePtr);
    }
  }

  void addPath(String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      _addPath(pathPtr);
    } finally {
      calloc.free(pathPtr);
    }
  }

  String callFunction(String moduleName, String functionName, String argsJson) {
    if (!_initialized) {
      return '{"success": false, "message": "Python not initialized"}';
    }

    final modulePtr = moduleName.toNativeUtf8();
    final funcPtr = functionName.toNativeUtf8();
    final argsPtr = argsJson.toNativeUtf8();

    try {
      final resultPtr = _call(modulePtr, funcPtr, argsPtr);
      return resultPtr.toDartString();
    } finally {
      calloc.free(modulePtr);
      calloc.free(funcPtr);
      calloc.free(argsPtr);
    }
  }

  String execScript(String scriptPath, String functionName, String argsJson) {
    if (!_initialized) {
      return '{"success": false, "message": "Python not initialized"}';
    }

    final scriptPtr = scriptPath.toNativeUtf8();
    final funcPtr = functionName.toNativeUtf8();
    final argsPtr = argsJson.toNativeUtf8();

    try {
      final resultPtr = _execScript(scriptPtr, funcPtr, argsPtr);
      return resultPtr.toDartString();
    } finally {
      calloc.free(scriptPtr);
      calloc.free(funcPtr);
      calloc.free(argsPtr);
    }
  }

  String callDyBridge(String functionName, String argsJson) {
    return callFunction('dy_bridge', functionName, argsJson);
  }

  String callXhsBridge(String functionName, String argsJson) {
    return callFunction('xhs_bridge', functionName, argsJson);
  }
}
