import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../model/download_task.dart';

/// 数据库服务，对应原项目 AppDatabase + DownloadTaskDao
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'download_manager.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE download_tasks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        url TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'video',
        status TEXT NOT NULL DEFAULT 'queued',
        downloadedSize INTEGER NOT NULL DEFAULT 0,
        totalSize INTEGER NOT NULL DEFAULT 0,
        filePath TEXT NOT NULL DEFAULT '',
        errorMessage TEXT NOT NULL DEFAULT '',
        createdAt INTEGER NOT NULL,
        source TEXT NOT NULL DEFAULT 'douyin',
        priority INTEGER NOT NULL DEFAULT 0,
        retryCount INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// 插入任务
  Future<void> insert(DownloadTask task) async {
    final db = await database;
    await db.insert(
      'download_tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 更新任务
  Future<void> update(DownloadTask task) async {
    final db = await database;
    await db.update(
      'download_tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  /// 更新进度
  Future<void> updateProgress(
    String id,
    int downloadedSize,
    int totalSize,
    String title,
  ) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE download_tasks SET downloadedSize = ?, totalSize = ?, title = ? WHERE id = ?',
      [downloadedSize, totalSize, title, id],
    );
  }

  /// 删除任务
  Future<void> deleteById(String id) async {
    final db = await database;
    await db.delete('download_tasks', where: 'id = ?', whereArgs: [id]);
  }

  /// 按状态删除
  Future<void> deleteByStatus(TaskStatus status) async {
    final db = await database;
    await db.delete(
      'download_tasks',
      where: 'status = ?',
      whereArgs: [status.name],
    );
  }

  /// 根据ID获取任务
  Future<DownloadTask?> getById(String id) async {
    final db = await database;
    final maps = await db.query(
      'download_tasks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return DownloadTask.fromMap(maps.first);
  }

  /// 根据URL查找任务
  Future<DownloadTask?> findByUrl(String url) async {
    final db = await database;
    final maps = await db.query(
      'download_tasks',
      where: 'url = ?',
      whereArgs: [url],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return DownloadTask.fromMap(maps.first);
  }

  /// 获取所有任务
  Future<List<DownloadTask>> getAllTasks() async {
    final db = await database;
    final maps = await db.query('download_tasks', orderBy: 'createdAt DESC');
    return maps.map((m) => DownloadTask.fromMap(m)).toList();
  }

  /// 按来源获取任务
  Future<List<DownloadTask>> getTasksBySource(String source) async {
    final db = await database;
    final maps = await db.query(
      'download_tasks',
      where: 'source = ?',
      whereArgs: [source],
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => DownloadTask.fromMap(m)).toList();
  }

  /// 获取待处理任务
  Future<List<DownloadTask>> getPendingTasks() async {
    final db = await database;
    final maps = await db.query(
      'download_tasks',
      where: "status IN ('queued', 'downloading', 'paused')",
      orderBy: 'priority DESC, createdAt ASC',
    );
    return maps.map((m) => DownloadTask.fromMap(m)).toList();
  }

  /// 递增重试次数
  Future<void> incrementRetry(String id) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE download_tasks SET retryCount = retryCount + 1 WHERE id = ?',
      [id],
    );
  }

  /// 清理旧任务
  Future<void> cleanupOldTasks({int daysToKeep = 30}) async {
    final db = await database;
    final cutoff =
        DateTime.now().millisecondsSinceEpoch -
        daysToKeep * 24 * 60 * 60 * 1000;
    await db.delete(
      'download_tasks',
      where: "status IN ('completed', 'failed') AND createdAt < ?",
      whereArgs: [cutoff],
    );
  }
}
