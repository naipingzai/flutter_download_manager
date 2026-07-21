import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../model/download_task.dart';

/// 数据库服务 — 纯 Dart JSON 文件实现，零外部依赖
/// 使用 path_provider 获取正确的应用文档目录
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  File? _file;
  List<DownloadTask> _tasks = [];
  bool _initialized = false;
  final _lock = _AsyncLock();

  Future<List<DownloadTask>> getAllTasks() async {
    await _ensureInit();
    return List.unmodifiable(_tasks);
  }

  Future<void> insert(DownloadTask task) async {
    await _ensureInit();
    await _lock.synchronized(() async {
      _tasks.removeWhere((t) => t.id == task.id);
      _tasks.insert(0, task);
      await _flush();
    });
  }

  Future<void> update(DownloadTask task) async {
    await _ensureInit();
    await _lock.synchronized(() async {
      final i = _tasks.indexWhere((t) => t.id == task.id);
      if (i >= 0) _tasks[i] = task;
      await _flush();
    });
  }

  Future<void> updateProgress(
    String id,
    int downloadedSize,
    int totalSize,
    String title,
  ) async {
    await _ensureInit();
    await _lock.synchronized(() async {
      final i = _tasks.indexWhere((t) => t.id == id);
      if (i >= 0) {
        _tasks[i] = _tasks[i].copyWith(
          downloadedSize: downloadedSize,
          totalSize: totalSize,
          title: title,
        );
        await _flush();
      }
    });
  }

  Future<void> deleteById(String id) async {
    await _ensureInit();
    await _lock.synchronized(() async {
      _tasks.removeWhere((t) => t.id == id);
      await _flush();
    });
  }

  Future<void> deleteByStatus(TaskStatus status) async {
    await _ensureInit();
    await _lock.synchronized(() async {
      _tasks.removeWhere((t) => t.status == status);
      await _flush();
    });
  }

  Future<DownloadTask?> getById(String id) async {
    await _ensureInit();
    return _lock.synchronized(() async {
      final i = _tasks.indexWhere((t) => t.id == id);
      return i >= 0 ? _tasks[i] : null;
    });
  }

  Future<DownloadTask?> findByUrl(String url) async {
    await _ensureInit();
    return _lock.synchronized(() async {
      final i = _tasks.indexWhere((t) => t.url == url);
      return i >= 0 ? _tasks[i] : null;
    });
  }

  Future<List<DownloadTask>> getTasksBySource(String source) async {
    await _ensureInit();
    return _lock.synchronized(() async {
      return List.unmodifiable(
          _tasks.where((t) => t.source == source).toList());
    });
  }

  Future<List<DownloadTask>> getPendingTasks() async {
    await _ensureInit();
    return _lock.synchronized(() async {
      return List.unmodifiable(_tasks
          .where((t) =>
              t.status == TaskStatus.queued ||
              t.status == TaskStatus.downloading ||
              t.status == TaskStatus.paused)
          .toList());
    });
  }

  Future<void> incrementRetry(String id) async {
    await _ensureInit();
    await _lock.synchronized(() async {
      final i = _tasks.indexWhere((t) => t.id == id);
      if (i >= 0) {
        _tasks[i] = _tasks[i].copyWith(retryCount: _tasks[i].retryCount + 1);
        await _flush();
      }
    });
  }

  Future<void> cleanupOldTasks({int daysToKeep = 30}) async {
    await _ensureInit();
    await _lock.synchronized(() async {
      final cutoff = DateTime.now().millisecondsSinceEpoch -
          daysToKeep * 24 * 60 * 60 * 1000;
      _tasks.removeWhere((t) =>
          (t.status == TaskStatus.completed || t.status == TaskStatus.failed) &&
          t.createdAt < cutoff);
      await _flush();
    });
  }

  // ═══ 内部实现 ═══

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _lock.synchronized(() async {
      if (_initialized) return;
      try {
        _file = await _resolveFile();
        if (!await _file!.exists()) {
          _tasks = [];
          await _flush();
        } else {
          try {
            final content = await _file!.readAsString();
            final list = jsonDecode(content) as List;
            _tasks = list
                .map((m) => DownloadTask.fromMap(m as Map<String, dynamic>))
                .toList();
          } catch (_) {
            _tasks = [];
          }
        }
      } catch (_) {
        // 初始化失败，使用内存存储
        _tasks = [];
      }
      _initialized = true;
    });
  }

  Future<File> _resolveFile() async {
    // 使用 path_provider 获取系统提供的应用文档目录
    // iOS: ~/Documents/
    // Android: /data/data/<package>/files/
    // Linux: ~/.local/share/<app>/
    // macOS: ~/Library/Application Support/
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/download_manager_data');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/tasks.json');
  }

  Future<void> _flush() async {
    if (_file == null) return;
    final json = jsonEncode(_tasks.map((t) => t.toMap()).toList());
    await _file!.writeAsString(json, flush: true);
  }
}

class _AsyncLock {
  Future<void> _last = Future.value();
  Future<T> synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final prev = _last;
    _last = completer.future.then((_) {}, onError: (_) {});
    prev.whenComplete(() async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}
