import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../model/download_task.dart';
import '../../service/download_task_manager.dart';

/// 任务页面
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
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text('下载任务 (${tasks.length})',
                          style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
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
              ],
            ),
    );
  }
}

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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showDownloadLog(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(_statusIcon(), size: 24, color: _statusColor(context)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      task.totalSize > 0 ? task.totalSizeStr : task.type,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (task.status == TaskStatus.downloading)
                IconButton(
                  icon: const Icon(Icons.stop, size: 20),
                  onPressed: _togglePause,
                  tooltip: '暂停',
                )
              else if (task.status == TaskStatus.paused) ...[
                IconButton(
                  icon: const Icon(Icons.play_arrow, size: 20),
                  onPressed: _togglePause,
                  tooltip: '继续',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => taskManager.removeTask(task.id),
                  tooltip: '删除',
                ),
              ] else if (task.status == TaskStatus.failed) ...[
                IconButton(
                  icon: Icon(Icons.refresh,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  onPressed: _retry,
                  tooltip: '重试',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => taskManager.removeTask(task.id),
                  tooltip: '删除',
                ),
              ] else if (task.status == TaskStatus.completed) ...[
                IconButton(
                  icon: const Icon(Icons.check_circle,
                      size: 20, color: Colors.green),
                  onPressed: null,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => taskManager.removeTask(task.id),
                  tooltip: '删除',
                ),
              ] else
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => taskManager.removeTask(task.id),
                  tooltip: '删除',
                ),
            ],
          ),
        ),
      ),
    );
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
            _infoRow('类型', task.type),
            _infoRow('来源', task.source == 'xhs' ? '小红书' : '抖音'),
            _infoRow('状态', task.status.displayName),
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
            const SizedBox(height: 12),
            Container(
              height: 120,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView(
                children: [
                  if (task.status == TaskStatus.downloading)
                    Text('▶ 正在下载: ${task.title}',
                        style: const TextStyle(fontSize: 12)),
                  if (task.totalSize > 0)
                    Text('📦 文件大小: ${task.totalSizeStr}',
                        style: const TextStyle(fontSize: 12)),
                  if (task.filePath.isNotEmpty)
                    Text('📁 保存到: ${task.filePath}',
                        style: const TextStyle(fontSize: 12)),
                  if (task.status == TaskStatus.completed)
                    Text('✅ 下载完成',
                        style: TextStyle(fontSize: 12, color: Colors.green)),
                  if (task.status == TaskStatus.failed)
                    Text('❌ 下载失败: ${task.errorMessage}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.error)),
                  if (task.status == TaskStatus.paused)
                    Text('⏸ 已暂停',
                        style: TextStyle(fontSize: 12, color: Colors.orange)),
                ],
              ),
            ),
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
