import 'package:flutter/foundation.dart';
import '../model/download_task.dart';
import 'database_service.dart';

/// 下载任务管理器
/// 使用 ChangeNotifier 实现响应式状态管理
class DownloadTaskManager extends ChangeNotifier {
  static final DownloadTaskManager _instance = DownloadTaskManager._internal();
  factory DownloadTaskManager() => _instance;
  DownloadTaskManager._internal();

  final DatabaseService _db = DatabaseService();
  final List<DownloadTask> _tasks = [];
  bool _initialized = false;

  /// 全部任务（按插入顺序倒序：最新在前）
  List<DownloadTask> get tasks => List<DownloadTask>.from(_tasks);

  /// 初始化，从数据库加载任务
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final loaded = await _db.getAllTasks();
    _tasks
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  /// 添加任务
  Future<void> addTask(DownloadTask task) async {
    await _db.insert(task);
    _tasks.removeWhere((t) => t.id == task.id);
    _tasks.insert(0, task);
    notifyListeners();
  }

  /// 更新任务
  Future<void> updateTask(DownloadTask task) async {
    await _db.update(task);
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      _tasks[index] = task;
    }
    notifyListeners();
  }

  /// 删除任务
  Future<void> removeTask(String id) async {
    await _db.deleteById(id);
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  /// 按状态删除
  Future<void> removeByStatus(TaskStatus status) async {
    await _db.deleteByStatus(status);
    _tasks.removeWhere((t) => t.status == status);
    notifyListeners();
  }

  /// 根据ID获取任务
  DownloadTask? getById(String id) {
    final index = _tasks.indexWhere((t) => t.id == id);
    return index >= 0 ? _tasks[index] : null;
  }

  /// 根据URL查找任务
  DownloadTask? findByUrl(String url) {
    final index = _tasks.indexWhere((t) => t.url == url);
    return index >= 0 ? _tasks[index] : null;
  }
}
