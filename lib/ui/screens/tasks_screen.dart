import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/task_manager/download_task.dart';
import '../../core/task_manager/download_task_manager.dart';

/// 任务页面 — 参考百度网盘/迅雷设计
class TasksScreen extends StatelessWidget {
  final String platform;

  const TasksScreen({super.key, this.platform = ''});

  @override
  Widget build(BuildContext context) {
    final taskManager = context.watch<DownloadTaskManager>();
    final tasks = platform.isEmpty
        ? taskManager.tasks
        : taskManager.tasks.where((t) => t.platform.id == platform).toList();

    return Scaffold(
      body: tasks.isEmpty
          ? _buildEmptyState(context)
          : _buildTaskList(context, tasks, taskManager),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
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

  Widget _buildTaskList(
      BuildContext context, List<DownloadTask> tasks, DownloadTaskManager taskManager) {
    final downloadingCount =
        tasks.where((t) => t.status == TaskStatus.downloading).length;

    return Column(
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('下载任务 (${tasks.length})',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (downloadingCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '下载中 $downloadingCount',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'completed') {
                    taskManager.removeByStatus(TaskStatus.completed);
                  } else if (value == 'failed') {
                    taskManager.removeByStatus(TaskStatus.failed);
                  } else if (value == 'all') {
                    for (final t in tasks) {
                      taskManager.removeTask(t.id);
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                      value: 'completed', child: Text('清理已完成')),
                  const PopupMenuItem(
                      value: 'failed', child: Text('清理失败')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                      value: 'all',
                      child: Text('清空全部',
                          style: TextStyle(color: Colors.red))),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('清理',
                          style: Theme.of(context).textTheme.bodySmall),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
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
              return _TaskCard(task: task, taskManager: taskManager);
            },
          ),
        ),

        // 底部操作栏
        if (tasks.isNotEmpty) _buildBottomBar(context, tasks, taskManager),
      ],
    );
  }

  Widget _buildBottomBar(
      BuildContext context, List<DownloadTask> tasks, DownloadTaskManager taskManager) {
    final hasDownloading =
        tasks.any((t) => t.status == TaskStatus.downloading);
    final hasPausedOrFailed = tasks.any(
        (t) => t.status == TaskStatus.paused || t.status == TaskStatus.failed);
    final hasCompleted =
        tasks.any((t) => t.status == TaskStatus.completed);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: hasDownloading
                    ? () {
                        for (final t in tasks) {
                          if (t.status == TaskStatus.downloading) {
                            taskManager
                                .updateTask(t.copyWith(status: TaskStatus.paused));
                          }
                        }
                      }
                    : null,
                icon: const Icon(Icons.pause, size: 16),
                label: const Text('全部暂停'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: hasPausedOrFailed
                    ? () {
                        for (final t in tasks) {
                          if (t.status == TaskStatus.paused ||
                              t.status == TaskStatus.failed) {
                            taskManager.updateTask(t.copyWith(
                                status: TaskStatus.downloading,
                                errorMessage: ''));
                          }
                        }
                      }
                    : null,
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('全部继续'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: hasCompleted
                    ? () {
                        taskManager.removeByStatus(TaskStatus.completed);
                      }
                    : null,
                icon: const Icon(Icons.delete_sweep, size: 16),
                label: const Text('清理完成'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: hasCompleted
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 任务卡片 — 参考百度网盘/迅雷设计
class _TaskCard extends StatelessWidget {
  final DownloadTask task;
  final DownloadTaskManager taskManager;

  const _TaskCard({required this.task, required this.taskManager});

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

  IconData _statusIcon() {
    switch (task.status) {
      case TaskStatus.queued:
        return Icons.schedule;
      case TaskStatus.downloading:
        return Icons.downloading;
      case TaskStatus.paused:
        return Icons.pause_circle;
      case TaskStatus.completed:
        return Icons.check_circle;
      case TaskStatus.failed:
        return Icons.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isActive =
        task.status == TaskStatus.downloading || task.status == TaskStatus.paused;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showDownloadLog(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行: 图标 + 标题 + 操作按钮
              Row(
                children: [
                  // 类型图标
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _statusColor(context).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_statusIcon(),
                        size: 20, color: _statusColor(context)),
                  ),
                  const SizedBox(width: 10),
                  // 标题 + 状态
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          task.statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: _statusColor(context),
                                  ),
                        ),
                      ],
                    ),
                  ),
                  // 操作按钮
                  _buildActionButtons(context),
                ],
              ),

              // 进度条 (下载中/暂停时显示)
              if (isActive) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: task.progress > 0 ? task.progress : null,
                    minHeight: 6,
                    backgroundColor:
                        scheme.surfaceContainerHighest,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(_statusColor(context)),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      task.totalSize > 0
                          ? '${task.downloadedSizeStr} / ${task.totalSizeStr}'
                          : '下载中...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                    ),
                    Text(
                      '${(task.progress * 100).toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _statusColor(context),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                    ),
                  ],
                ),
              ],

              // 平台标识
              if (task.status == TaskStatus.completed) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.folder_outlined,
                        size: 12, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        task.filePath.isNotEmpty
                            ? task.filePath.split('/').last
                            : task.platform.displayName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      task.totalSizeStr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                    ),
                  ],
                ),
              ],

              // 错误信息
              if (task.status == TaskStatus.failed &&
                  task.errorMessage.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  task.errorMessage,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                        fontSize: 11,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    switch (task.status) {
      case TaskStatus.downloading:
        return IconButton(
          icon: const Icon(Icons.pause, size: 20),
          onPressed: _togglePause,
          tooltip: '暂停',
          visualDensity: VisualDensity.compact,
        );
      case TaskStatus.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_arrow, size: 20),
              onPressed: _togglePause,
              tooltip: '继续',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => taskManager.removeTask(task.id),
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
            ),
          ],
        );
      case TaskStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.refresh,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              onPressed: _retry,
              tooltip: '重试',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => taskManager.removeTask(task.id),
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
            ),
          ],
        );
      case TaskStatus.completed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check_circle, size: 20, color: Colors.green),
              onPressed: null,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => taskManager.removeTask(task.id),
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
            ),
          ],
        );
      default:
        return IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          onPressed: () => taskManager.removeTask(task.id),
          tooltip: '删除',
          visualDensity: VisualDensity.compact,
        );
    }
  }

  void _togglePause() {
    if (task.status == TaskStatus.downloading) {
      taskManager.updateTask(task.copyWith(status: TaskStatus.paused));
    } else if (task.status == TaskStatus.paused ||
        task.status == TaskStatus.failed) {
      taskManager.updateTask(
          task.copyWith(status: TaskStatus.downloading, errorMessage: ''));
    }
  }

  void _retry() {
    taskManager.updateTask(task.copyWith(
      status: TaskStatus.downloading,
      downloadedSize: 0,
      errorMessage: '',
    ));
  }

  void _showDownloadLog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) =>
          _DownloadLogDialog(task: task, taskManager: taskManager),
    );
  }
}

class _DownloadLogDialog extends StatelessWidget {
  final DownloadTask task;
  final DownloadTaskManager taskManager;

  const _DownloadLogDialog({required this.task, required this.taskManager});

  @override
  Widget build(BuildContext context) {
    final isActive = task.status == TaskStatus.downloading ||
        task.status == TaskStatus.paused;

    return AlertDialog(
      title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('类型', task.contentType.displayName),
            _infoRow('来源', task.platform.displayName),
            _infoRow('状态', task.status.displayName),
            if (task.author.isNotEmpty) _infoRow('作者', task.author),
            if (task.totalSize > 0) _infoRow('大小', task.totalSizeStr),
            if (task.filePath.isNotEmpty)
              _infoRow('文件', task.filePath.split('/').last),
            if (task.errorMessage.isNotEmpty)
              _infoRow('错误', task.errorMessage, color: Colors.red),
            if (isActive) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: task.progress > 0 ? task.progress : null,
                  minHeight: 8,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                task.totalSize > 0
                    ? '${(task.progress * 100).toStringAsFixed(1)}%  (${task.downloadedSizeStr} / ${task.totalSizeStr})'
                    : '下载中...',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (task.status == TaskStatus.downloading)
          TextButton.icon(
            onPressed: () {
              taskManager.updateTask(task.copyWith(status: TaskStatus.paused));
              Navigator.pop(context);
            },
            icon: const Icon(Icons.pause),
            label: const Text('暂停'),
          ),
        if (task.status == TaskStatus.paused)
          TextButton.icon(
            onPressed: () {
              taskManager.updateTask(task.copyWith(
                  status: TaskStatus.downloading, errorMessage: ''));
              Navigator.pop(context);
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('继续'),
          ),
        if (task.status == TaskStatus.failed)
          TextButton.icon(
            onPressed: () {
              taskManager.updateTask(task.copyWith(
                status: TaskStatus.downloading,
                downloadedSize: 0,
                errorMessage: '',
              ));
              Navigator.pop(context);
            },
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value, {Color? color}) {
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
