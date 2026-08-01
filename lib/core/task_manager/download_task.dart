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

/// 下载内容类型
enum ContentType {
  video,
  images,
  live,
  note;

  String get displayName {
    switch (this) {
      case ContentType.video:
        return '视频';
      case ContentType.images:
        return '图集';
      case ContentType.live:
        return '直播';
      case ContentType.note:
        return '笔记';
    }
  }

  String get icon {
    switch (this) {
      case ContentType.video:
        return '📹';
      case ContentType.images:
        return '🖼️';
      case ContentType.live:
        return '🎥';
      case ContentType.note:
        return '📝';
    }
  }

  static ContentType fromString(String value) {
    return ContentType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ContentType.video,
    );
  }
}

/// 平台类型
enum PlatformType {
  douyin,
  xhs,
  kuaishou;

  String get displayName {
    switch (this) {
      case PlatformType.douyin:
        return '抖音';
      case PlatformType.xhs:
        return '小红书';
      case PlatformType.kuaishou:
        return '快手';
    }
  }

  String get id {
    switch (this) {
      case PlatformType.douyin:
        return 'douyin';
      case PlatformType.xhs:
        return 'xhs';
      case PlatformType.kuaishou:
        return 'kuaishou';
    }
  }

  static PlatformType fromId(String id) {
    return PlatformType.values.firstWhere(
      (e) => e.id == id,
      orElse: () => PlatformType.douyin,
    );
  }
}

/// 下载任务数据模型
class DownloadTask {
  final String id;
  final String title;
  final String url;
  final ContentType contentType;
  final TaskStatus status;
  final int downloadedSize;
  final int totalSize;
  final String filePath;
  final String errorMessage;
  final int createdAt;
  final PlatformType platform;
  final int priority;
  final int retryCount;
  final int imageCount; // 图集总张数
  final int imageDownloaded; // 图集已下载张数
  final String author;
  final String description;

  DownloadTask({
    required this.id,
    required this.title,
    required this.url,
    this.contentType = ContentType.video,
    this.status = TaskStatus.queued,
    this.downloadedSize = 0,
    this.totalSize = 0,
    this.filePath = '',
    this.errorMessage = '',
    int? createdAt,
    this.platform = PlatformType.douyin,
    this.priority = 0,
    this.retryCount = 0,
    this.imageCount = 0,
    this.imageDownloaded = 0,
    this.author = '',
    this.description = '',
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  /// 计算下载进度 (0.0 ~ 1.0)
  double get progress {
    if (contentType == ContentType.images && imageCount > 0) {
      return (imageDownloaded / imageCount).clamp(0.0, 1.0);
    }
    if (totalSize <= 0) return 0.0;
    return (downloadedSize / totalSize).clamp(0.0, 1.0);
  }

  /// 格式化下载大小
  String get downloadedSizeStr => _formatBytes(downloadedSize);
  String get totalSizeStr => _formatBytes(totalSize);

  /// 状态文本
  String get statusText {
    switch (status) {
      case TaskStatus.queued:
        return '排队中';
      case TaskStatus.downloading:
        if (contentType == ContentType.images && imageCount > 0) {
          return '下载中 $imageDownloaded/$imageCount 张';
        }
        if (totalSize > 0) {
          return '下载中 ${(progress * 100).toStringAsFixed(1)}% ($downloadedSizeStr/$totalSizeStr)';
        }
        return '下载中...';
      case TaskStatus.paused:
        if (totalSize > 0) {
          return '已暂停 ($downloadedSizeStr/$totalSizeStr)';
        }
        return '已暂停';
      case TaskStatus.completed:
        return '已完成 $totalSizeStr';
      case TaskStatus.failed:
        return '失败: $errorMessage';
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
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
    ContentType? contentType,
    TaskStatus? status,
    int? downloadedSize,
    int? totalSize,
    String? filePath,
    String? errorMessage,
    int? createdAt,
    PlatformType? platform,
    int? priority,
    int? retryCount,
    int? imageCount,
    int? imageDownloaded,
    String? author,
    String? description,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      contentType: contentType ?? this.contentType,
      status: status ?? this.status,
      downloadedSize: downloadedSize ?? this.downloadedSize,
      totalSize: totalSize ?? this.totalSize,
      filePath: filePath ?? this.filePath,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      platform: platform ?? this.platform,
      priority: priority ?? this.priority,
      retryCount: retryCount ?? this.retryCount,
      imageCount: imageCount ?? this.imageCount,
      imageDownloaded: imageDownloaded ?? this.imageDownloaded,
      author: author ?? this.author,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'contentType': contentType.name,
      'status': status.name,
      'downloadedSize': downloadedSize,
      'totalSize': totalSize,
      'filePath': filePath,
      'errorMessage': errorMessage,
      'createdAt': createdAt,
      'platform': platform.id,
      'priority': priority,
      'retryCount': retryCount,
      'imageCount': imageCount,
      'imageDownloaded': imageDownloaded,
      'author': author,
      'description': description,
    };
  }

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    return DownloadTask(
      id: map['id'] as String,
      title: map['title'] as String,
      url: map['url'] as String,
      contentType: ContentType.fromString(map['contentType'] as String? ?? map['type'] as String? ?? 'video'),
      status: TaskStatus.fromString(map['status'] as String),
      downloadedSize: map['downloadedSize'] as int? ?? 0,
      totalSize: map['totalSize'] as int? ?? 0,
      filePath: map['filePath'] as String? ?? '',
      errorMessage: map['errorMessage'] as String? ?? '',
      createdAt: map['createdAt'] as int?,
      platform: PlatformType.fromId(map['platform'] as String? ?? map['source'] as String? ?? 'douyin'),
      priority: map['priority'] as int? ?? 0,
      retryCount: map['retryCount'] as int? ?? 0,
      imageCount: map['imageCount'] as int? ?? 0,
      imageDownloaded: map['imageDownloaded'] as int? ?? 0,
      author: map['author'] as String? ?? '',
      description: map['description'] as String? ?? '',
    );
  }

  @override
  String toString() {
    return 'DownloadTask(id: $id, title: $title, status: $status, progress: ${(progress * 100).toStringAsFixed(1)}%)';
  }
}
