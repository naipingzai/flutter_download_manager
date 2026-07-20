/// 下载任务状态枚举
enum TaskStatus {
  queued,
  downloading,
  paused,
  completed,
  failed;

  String get displayName {
    switch (this) {
      case TaskStatus.queued:
        return '排队中';
      case TaskStatus.downloading:
        return '下载中';
      case TaskStatus.paused:
        return '已暂停';
      case TaskStatus.completed:
        return '已完成';
      case TaskStatus.failed:
        return '失败';
    }
  }

  static TaskStatus fromString(String value) {
    return TaskStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TaskStatus.queued,
    );
  }
}

/// 下载任务数据模型，与原项目 DownloadTask 对应
class DownloadTask {
  final String id;
  final String title;
  final String url;
  final String type;
  final TaskStatus status;
  final int downloadedSize;
  final int totalSize;
  final String filePath;
  final String errorMessage;
  final int createdAt;
  final String source;
  final int priority;
  final int retryCount;

  DownloadTask({
    required this.id,
    required this.title,
    required this.url,
    this.type = 'video',
    this.status = TaskStatus.queued,
    this.downloadedSize = 0,
    this.totalSize = 0,
    this.filePath = '',
    this.errorMessage = '',
    int? createdAt,
    this.source = 'douyin',
    this.priority = 0,
    this.retryCount = 0,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  /// 计算下载进度 (0.0 ~ 1.0)
  double get progress {
    if (totalSize <= 0) return 0.0;
    return (downloadedSize / totalSize).clamp(0.0, 1.0);
  }

  /// 格式化下载大小
  String get downloadedSizeStr => _formatBytes(downloadedSize);
  String get totalSizeStr => _formatBytes(totalSize);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  DownloadTask copyWith({
    String? id,
    String? title,
    String? url,
    String? type,
    TaskStatus? status,
    int? downloadedSize,
    int? totalSize,
    String? filePath,
    String? errorMessage,
    int? createdAt,
    String? source,
    int? priority,
    int? retryCount,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      type: type ?? this.type,
      status: status ?? this.status,
      downloadedSize: downloadedSize ?? this.downloadedSize,
      totalSize: totalSize ?? this.totalSize,
      filePath: filePath ?? this.filePath,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      source: source ?? this.source,
      priority: priority ?? this.priority,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'type': type,
      'status': status.name,
      'downloadedSize': downloadedSize,
      'totalSize': totalSize,
      'filePath': filePath,
      'errorMessage': errorMessage,
      'createdAt': createdAt,
      'source': source,
      'priority': priority,
      'retryCount': retryCount,
    };
  }

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    return DownloadTask(
      id: map['id'] as String,
      title: map['title'] as String,
      url: map['url'] as String,
      type: map['type'] as String? ?? 'video',
      status: TaskStatus.fromString(map['status'] as String),
      downloadedSize: map['downloadedSize'] as int? ?? 0,
      totalSize: map['totalSize'] as int? ?? 0,
      filePath: map['filePath'] as String? ?? '',
      errorMessage: map['errorMessage'] as String? ?? '',
      createdAt: map['createdAt'] as int?,
      source: map['source'] as String? ?? 'douyin',
      priority: map['priority'] as int? ?? 0,
      retryCount: map['retryCount'] as int? ?? 0,
    );
  }

  @override
  String toString() {
    return 'DownloadTask(id: $id, title: $title, status: $status, progress: ${(progress * 100).toStringAsFixed(1)}%)';
  }
}
