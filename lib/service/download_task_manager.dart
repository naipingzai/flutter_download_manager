import 'dart:async';
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

  List<DownloadTask> get tasks => List<DownloadTask>.from(_tasks);
  List<DownloadTask> get downloadingTasks =>
      _tasks.where((t) => t.status == TaskStatus.downloading).toList();
  List<DownloadTask> get completedTasks =>
      _tasks.where((t) => t.status == TaskStatus.completed).toList();
  List<DownloadTask> get failedTasks =>
      _tasks.where((t) => t.status == TaskStatus.failed).toList();

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

  /// 更新进度
  Future<void> updateProgress(
    String id,
    int downloadedSize,
    int totalSize,
    String title,
  ) async {
    await _db.updateProgress(id, downloadedSize, totalSize, title);
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index >= 0) {
      _tasks[index] = _tasks[index].copyWith(
        downloadedSize: downloadedSize,
        totalSize: totalSize,
        title: title,
      );
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

  /// 递增重试次数
  Future<void> incrementRetry(String id) async {
    await _db.incrementRetry(id);
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index >= 0) {
      _tasks[index] =
          _tasks[index].copyWith(retryCount: _tasks[index].retryCount + 1);
    }
    notifyListeners();
  }

  /// 清理旧任务
  Future<void> cleanupOldTasks({int daysToKeep = 30}) async {
    await _db.cleanupOldTasks(daysToKeep: daysToKeep);
    final loaded = await _db.getAllTasks();
    _tasks
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }
}
