import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../model/download_task.dart';
import '../../service/download_task_manager.dart';
import '../../platform/douyin/douyin_bridge.dart';
import '../../platform/xhs/xhs_bridge.dart';

/// 任务管理页面 — 参考百度网盘/迅雷设计
class TasksScreen extends StatelessWidget {
  final String platform;
  final int scrollToTop;

  const TasksScreen({super.key, this.platform = '', this.scrollToTop = 0});

  @override
  Widget build(BuildContext context) {
    final taskManager = context.watch<DownloadTaskManager>();
    final tasks = platform.isEmpty
        ? taskManager.tasks
        : taskManager.tasks.where((t) => t.source == platform).toList();

    final hasDownloading = tasks.any((t) => t.status == TaskStatus.downloading);
    final hasPausedOrFailed = tasks.any(
      (t) => t.status == TaskStatus.paused || t.status == TaskStatus.failed,
    );
    final hasCompleted = tasks.any((t) => t.status == TaskStatus.completed);

    return Scaffold(
      body: tasks.isEmpty
          ? _buildEmpty(context)
          : ListView.builder(
              padding: const EdgeInsets.only(
                  top: 8, left: 12, right: 12, bottom: 80),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return _TaskCard(
                  task: task,
                  onTap: () => _showTaskDetail(context, task),
                  onPauseResume: () => _pauseResume(context, task, taskManager),
                  onRetry: () => _retry(context, task, taskManager),
                  onDelete: () => _delete(context, task, taskManager),
                );
              },
            ),
      // 底部固定操作栏
      bottomNavigationBar: tasks.isEmpty
          ? null
          : BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: hasDownloading
                        ? () => _pauseAll(context, tasks, taskManager)
                        : null,
                    icon: const Icon(Icons.pause_circle_outline),
                    label: const Text('全部暂停'),
                  ),
                  TextButton.icon(
                    onPressed: hasPausedOrFailed
                        ? () => _resumeAll(context, tasks, taskManager)
                        : null,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('全部继续'),
                  ),
                  TextButton.icon(
                    onPressed: hasCompleted
                        ? () {
                            taskManager.removeByStatus(TaskStatus.completed);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已清理完成任务')),
                              );
                            }
                          }
                        : null,
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('清理已完成'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_outlined,
            size: 64,
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant
                .withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text('暂无下载任务',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
          const SizedBox(height: 8),
          Text('去下载页粘贴链接开始下载',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
        ],
      ),
    );
  }

  void _pauseResume(
      BuildContext context, DownloadTask task, DownloadTaskManager manager) {
    if (task.status == TaskStatus.downloading) {
      if (task.source == 'xhs') {
        XhsBridge.pauseTask(task.id);
      } else {
        DouyinBridge.pauseTask(task.id);
      }
      manager.updateTask(task.copyWith(status: TaskStatus.paused));
    } else if (task.status == TaskStatus.paused ||
        task.status == TaskStatus.failed) {
      if (task.source == 'xhs') {
        XhsBridge.resumeTask(task.id);
      } else {
        DouyinBridge.resumeTask(task.id);
      }
      manager.updateTask(
        task.copyWith(status: TaskStatus.downloading, errorMessage: ''),
      );
    }
  }

  void _retry(
      BuildContext context, DownloadTask task, DownloadTaskManager manager) {
    manager.updateTask(
      task.copyWith(status: TaskStatus.downloading, errorMessage: ''),
    );
  }

  void _delete(
      BuildContext context, DownloadTask task, DownloadTaskManager manager) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('确定删除「${task.title}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              manager.removeTask(task.id);
              Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _pauseAll(BuildContext context, List<DownloadTask> tasks,
      DownloadTaskManager manager) {
    for (final task in tasks.where((t) => t.status == TaskStatus.downloading)) {
      if (task.source == 'xhs') {
        XhsBridge.pauseTask(task.id);
      } else {
        DouyinBridge.pauseTask(task.id);
      }
      manager.updateTask(task.copyWith(status: TaskStatus.paused));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已暂停全部')),
    );
  }

  void _resumeAll(BuildContext context, List<DownloadTask> tasks,
      DownloadTaskManager manager) {
    for (final task in tasks.where((t) =>
        t.status == TaskStatus.paused || t.status == TaskStatus.failed)) {
      if (task.source == 'xhs') {
        XhsBridge.resumeTask(task.id);
      } else {
        DouyinBridge.resumeTask(task.id);
      }
      manager.updateTask(
          task.copyWith(status: TaskStatus.downloading, errorMessage: ''));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已开始全部')),
    );
  }

  void _showTaskDetail(BuildContext context, DownloadTask task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('任务详情'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _detailRow('状态', task.status.displayName),
            _detailRow('来源', task.source == 'xhs' ? '小红书' : '抖音'),
            _detailRow('类型', task.type),
            if (task.totalSize > 0) _detailRow('大小', task.totalSizeStr),
            if (task.filePath.isNotEmpty) _detailRow('文件', task.filePath),
            if (task.errorMessage.isNotEmpty)
              _detailRow('错误', task.errorMessage, color: Colors.red),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 13, color: color)),
          ),
        ],
      ),
    );
  }
}

/// 任务卡片 — 参考网盘/迅雷设计
class _TaskCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onTap;
  final VoidCallback onPauseResume;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  const _TaskCard({
    required this.task,
    required this.onTap,
    required this.onPauseResume,
    required this.onRetry,
    required this.onDelete,
  });

  IconData _getTypeIcon() {
    switch (task.type) {
      case 'video':
        return Icons.video_file;
      case 'live':
        return Icons.live_tv;
      case 'comments':
        return Icons.comment;
      default:
        return Icons.image;
    }
  }

  Color _getStatusColor(BuildContext context) {
    switch (task.status) {
      case TaskStatus.queued:
        return Colors.grey;
      case TaskStatus.downloading:
        return Theme.of(context).colorScheme.primary;
      case TaskStatus.paused:
        return Colors.orange;
      case TaskStatus.completed:
        return Colors.green;
      case TaskStatus.failed:
        return Theme.of(context).colorScheme.error;
    }
  }

  String _getStatusText() {
    switch (task.status) {
      case TaskStatus.queued:
        return '排队中';
      case TaskStatus.downloading:
        if (task.totalSize > 0) {
          final percent = (task.progress * 100).toStringAsFixed(0);
          return '下载中 $percent% (${task.downloadedSizeStr}/${task.totalSizeStr})';
        }
        return '解析中...';
      case TaskStatus.paused:
        if (task.totalSize > 0) {
          return '已暂停 (${task.downloadedSizeStr}/${task.totalSizeStr})';
        }
        return '已暂停';
      case TaskStatus.completed:
        return '已完成 ${task.totalSizeStr}';
      case TaskStatus.failed:
        return '失败';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // 第一行：图标 + 标题 + 状态图标
              Row(
                children: [
                  // 类型图标
                  Icon(_getTypeIcon(),
                      size: 24, color: _getStatusColor(context)),
                  const SizedBox(width: 8),
                  // 标题
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  // 状态图标
                  if (task.status == TaskStatus.completed)
                    const Icon(Icons.check_circle,
                        size: 18, color: Colors.green)
                  else if (task.status == TaskStatus.failed)
                    Icon(Icons.error, size: 18, color: _getStatusColor(context))
                  else if (task.status == TaskStatus.downloading)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: task.progress > 0 ? task.progress : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // 第二行：状态文字
              Row(
                children: [
                  Text(
                    _getStatusText(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _getStatusColor(context),
                        ),
                  ),
                  const Spacer(),
                  // 操作按钮
                  if (task.status == TaskStatus.downloading)
                    IconButton(
                      icon: const Icon(Icons.pause, size: 18),
                      onPressed: onPauseResume,
                      visualDensity: VisualDensity.compact,
                      tooltip: '暂停',
                    )
                  else if (task.status == TaskStatus.paused)
                    IconButton(
                      icon: const Icon(Icons.play_arrow, size: 18),
                      onPressed: onPauseResume,
                      visualDensity: VisualDensity.compact,
                      tooltip: '继续',
                    )
                  else if (task.status == TaskStatus.failed)
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      onPressed: onRetry,
                      visualDensity: VisualDensity.compact,
                      tooltip: '重试',
                    ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                    tooltip: '删除',
                  ),
                ],
              ),
              // 进度条
              if (task.status == TaskStatus.downloading ||
                  task.status == TaskStatus.paused) ...[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: task.progress,
                    minHeight: 4,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
