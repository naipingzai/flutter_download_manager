import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef NativeInitC = Bool Function(Pointer<Utf8>, Pointer<Utf8>);
typedef NativeInitDart = bool Function(Pointer<Utf8>, Pointer<Utf8>);

typedef NativeDestroyC = Void Function();
typedef NativeDestroyDart = void Function();

typedef NativeCallC = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef NativeCallDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef NativeGetVersionC = Pointer<Utf8> Function();
typedef NativeGetVersionDart = Pointer<Utf8> Function();

typedef NativeAddPathC = Void Function(Pointer<Utf8>);
typedef NativeAddPathDart = void Function(Pointer<Utf8>);

class PythonService {
  static PythonService? _instance;
  DynamicLibrary? _lib;
  bool _initialized = false;

  late NativeInitDart _init;
  late NativeDestroyDart _destroy;
  late NativeCallDart _call;
  late NativeGetVersionDart _getVersion;
  late NativeAddPathDart _addPath;

  PythonService._();
  static PythonService get instance => _instance ??= PythonService._();

  bool get isReady => _initialized;

  Future<bool> init({String? scriptDir}) async {
    if (_initialized) return true;

    try {
      _loadLib();
    } catch (e) {
      return false;
    }

    final homePtr = ''.toNativeUtf8();
    final scriptPtr = (scriptDir ?? _defaultScriptDir()).toNativeUtf8();
    try {
      _initialized = _init(homePtr, scriptPtr);
      if (_initialized) _addPath(scriptPtr);
      return _initialized;
    } finally {
      calloc.free(homePtr);
      calloc.free(scriptPtr);
    }
  }

  String _defaultScriptDir() => '${Directory.current.path}/python';

  void _loadLib() {
    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libpython_bridge.so');
    } else if (Platform.isIOS) {
      _lib = DynamicLibrary.process();
    } else if (Platform.isLinux) {
      _lib = DynamicLibrary.open('${Directory.current.path}/src/build/libpython_bridge.so');
    } else if (Platform.isMacOS) {
      _lib = DynamicLibrary.open('libpython_bridge.dylib');
    } else if (Platform.isWindows) {
      _lib = DynamicLibrary.open('python_bridge.dll');
    }

    _init = _lib!.lookupFunction<NativeInitC, NativeInitDart>('python_bridge_init');
    _destroy = _lib!.lookupFunction<NativeDestroyC, NativeDestroyDart>('python_bridge_destroy');
    _call = _lib!.lookupFunction<NativeCallC, NativeCallDart>('python_bridge_call');
    _getVersion = _lib!.lookupFunction<NativeGetVersionC, NativeGetVersionDart>('python_bridge_get_version');
    _addPath = _lib!.lookupFunction<NativeAddPathC, NativeAddPathDart>('python_bridge_add_path');
  }

  void destroy() {
    if (_initialized) { _destroy(); _initialized = false; }
  }

  String get version => _initialized ? _getVersion().toDartString() : 'N/A';

  String callFunction(String moduleName, String functionName, String argsJson) {
    if (!_initialized) return '{"success":false,"message":"Python 未初始化"}';
    final mPtr = moduleName.toNativeUtf8();
    final fPtr = functionName.toNativeUtf8();
    final aPtr = argsJson.toNativeUtf8();
    try {
      return _call(mPtr, fPtr, aPtr).toDartString();
    } finally {
      calloc.free(mPtr);
      calloc.free(fPtr);
      calloc.free(aPtr);
    }
  }

  Future<void> saveCookie(String platform, String cookie) async {
    final configPath = '${_defaultScriptDir()}/.cookie_config.json';
    try {
      final config = <String, dynamic>{'${platform}_cookie': cookie};
      final file = File(configPath);
      if (await file.exists()) {
        config.addAll(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      }
      config['${platform}_cookie'] = cookie;
      await file.writeAsString(jsonEncode(config));
    } catch (_) {}
  }

  String callDyBridge(String functionName, String argsJson) => callFunction('dy_bridge', functionName, argsJson);
  String callXhsBridge(String functionName, String argsJson) => callFunction('xhs_bridge', functionName, argsJson);
}
