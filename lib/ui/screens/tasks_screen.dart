import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../model/download_task.dart';
import '../../service/download_task_manager.dart';

/// 任务页面 — 简洁设计，专注下载进度展示
class TasksScreen extends StatelessWidget {
  final String platform;

  const TasksScreen({super.key, this.platform = ''});

  @override
  Widget build(BuildContext context) {
    final taskManager = context.watch<DownloadTaskManager>();
    final tasks = platform.isEmpty
        ? taskManager.tasks
        : taskManager.tasks.where((t) => t.source == platform).toList();

    return Scaffold(
      body: tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_download_outlined,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  Text('暂无下载任务',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                  const SizedBox(height: 8),
                  Text('去下载页粘贴链接开始下载',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                ],
              ),
            )
          : Column(
              children: [
                // 顶部操作栏
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text('下载任务 (${tasks.length})',
                          style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          taskManager.removeByStatus(TaskStatus.completed);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已清理完成任务')),
                          );
                        },
                        child: const Text('清理已完成'),
                      ),
                    ],
                  ),
                ),
                // 任务列表
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return _TaskCard(
                        task: task,
                        onTap: () => _showTaskDetail(context, task),
                        onPauseResume: () => _togglePause(taskManager, task),
                        onDelete: () => taskManager.removeTask(task.id),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  void _togglePause(DownloadTaskManager manager, DownloadTask task) {
    if (task.status == TaskStatus.downloading) {
      manager.updateTask(task.copyWith(status: TaskStatus.paused));
    } else if (task.status == TaskStatus.paused ||
        task.status == TaskStatus.failed) {
      manager.updateTask(
        task.copyWith(status: TaskStatus.downloading, errorMessage: ''),
      );
    }
  }

  void _showTaskDetail(BuildContext context, DownloadTask task) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            onPressed: () => Navigator.pop(ctx),
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

/// 任务卡片
class _TaskCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onTap;
  final VoidCallback onPauseResume;
  final VoidCallback onDelete;

  const _TaskCard({
    required this.task,
    required this.onTap,
    required this.onPauseResume,
    required this.onDelete,
  });

  Color _statusColor(BuildContext context) {
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

  String _statusText() {
    switch (task.status) {
      case TaskStatus.queued:
        return '排队中';
      case TaskStatus.downloading:
        if (task.totalSize > 0) {
          return '下载中 ${(task.progress * 100).toStringAsFixed(0)}% (${task.downloadedSizeStr}/${task.totalSizeStr})';
        }
        return '下载中...';
      case TaskStatus.paused:
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _statusText(),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: _statusColor(context)),
                        ),
                      ],
                    ),
                  ),
                  if (task.status == TaskStatus.downloading)
                    IconButton(
                      icon: const Icon(Icons.pause, size: 20),
                      onPressed: onPauseResume,
                      tooltip: '暂停',
                    )
                  else if (task.status == TaskStatus.paused ||
                      task.status == TaskStatus.failed)
                    IconButton(
                      icon: const Icon(Icons.play_arrow, size: 20),
                      onPressed: onPauseResume,
                      tooltip: '继续',
                    )
                  else if (task.status == TaskStatus.completed)
                    IconButton(
                      icon: const Icon(Icons.check_circle,
                          size: 20, color: Colors.green),
                      onPressed: null,
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: onDelete,
                    tooltip: '删除',
                  ),
                ],
              ),
              // 进度条
              if (task.status == TaskStatus.downloading ||
                  task.status == TaskStatus.paused) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: task.progress > 0 ? task.progress : null,
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
