import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Cookie 存储 - 对应原项目 CookieStore
/// 支持多个 Cookie 存储和切换
class CookieStore {
  final String platform;
  List<CookieEntry> _cookies = [];
  String _activeName = '';

  CookieStore({required this.platform});

  String get _prefsKey => '${platform}_cookies';
  String get _activeKey => '${platform}_active_cookie';

  /// 加载所有 Cookie
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_prefsKey);
    _activeName = prefs.getString(_activeKey) ?? '';
    if (json != null && json.isNotEmpty) {
      try {
        final list = jsonDecode(json) as List;
        _cookies = list
            .map((e) => CookieEntry.fromMap(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _cookies = [];
      }
    }
  }

  /// 保存到 SharedPreferences
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_cookies.map((e) => e.toMap()).toList()),
    );
    await prefs.setString(_activeKey, _activeName);
  }

  /// 获取所有 Cookie 列表
  List<CookieEntry> getAll() => List.unmodifiable(_cookies);

  /// 获取当前激活的 Cookie 名称
  String getActiveName() => _activeName;

  /// 获取当前激活的 Cookie 内容
  String? getActiveCookie() {
    if (_activeName.isEmpty) return null;
    try {
      final entry = _cookies.firstWhere((e) => e.name == _activeName);
      return entry.cookie;
    } catch (_) {
      return null;
    }
  }

  /// 添加 Cookie
  Future<void> add(String name, String cookie) async {
    _cookies.add(CookieEntry(name: name, cookie: cookie));
    await _save();
  }

  /// 设置激活的 Cookie
  Future<void> setActiveName(String name) async {
    _activeName = name;
    await _save();
  }

  /// 删除指定位置的 Cookie
  Future<void> removeAt(int index) async {
    if (index >= 0 && index < _cookies.length) {
      final removed = _cookies.removeAt(index);
      if (_activeName == removed.name) {
        _activeName = _cookies.isNotEmpty ? _cookies.first.name : '';
      }
      await _save();
    }
  }

  /// 获取 Cookie 字段数
  int getKeyCount(String cookie) {
    return cookie.split(';').where((s) => s.contains('=')).length;
  }
}

/// Cookie 条目
class CookieEntry {
  final String name;
  final String cookie;

  CookieEntry({required this.name, required this.cookie});

  Map<String, dynamic> toMap() => {'name': name, 'cookie': cookie};

  factory CookieEntry.fromMap(Map<String, dynamic> map) =>
      CookieEntry(name: map['name'] as String, cookie: map['cookie'] as String);
}
