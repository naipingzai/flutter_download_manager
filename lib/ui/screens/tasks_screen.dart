import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../model/download_task.dart';
import '../../service/download_task_manager.dart';
import '../../platform/douyin/douyin_bridge.dart';
import '../../platform/xhs/xhs_bridge.dart';

/// 任务管理页面 - 完全复刻原项目 TasksScreen
/// 顶部操作栏（全部停止/全部开始 + 清理完成/清理失败）+ 任务卡片列表
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

    return Column(
      children: [
        // ── 顶部操作栏（常显）── 对应原项目顶部按钮区域
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: OutlinedButton(
                        onPressed: hasDownloading
                            ? () {
                                for (final task in tasks.where(
                                  (t) => t.status == TaskStatus.downloading,
                                )) {
                                  if (task.source == 'xhs') {
                                    XhsBridge.pauseTask(task.id);
                                  } else {
                                    DouyinBridge.pauseTask(task.id);
                                  }
                                  taskManager.updateTask(
                                    task.copyWith(status: TaskStatus.paused),
                                  );
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已暂停全部')),
                                );
                              }
                            : null,
                        child: const Text('全部停止'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: FilledButton(
                        onPressed: hasPausedOrFailed
                            ? () {
                                for (final task in tasks.where(
                                  (t) =>
                                      t.status == TaskStatus.paused ||
                                      t.status == TaskStatus.failed,
                                )) {
                                  if (task.source == 'xhs') {
                                    XhsBridge.resumeTask(task.id);
                                  } else {
                                    DouyinBridge.resumeTask(task.id);
                                  }
                                  taskManager.updateTask(
                                    task.copyWith(
                                      status: TaskStatus.downloading,
                                      errorMessage: '',
                                      downloadedSize: 0,
                                    ),
                                  );
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已开始全部')),
                                );
                              }
                            : null,
                        child: const Text('全部开始'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextButton(
                        onPressed: () {
                          taskManager.removeByStatus(TaskStatus.completed);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已清理完成任务')),
                          );
                        },
                        child: const Text('清理完成'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextButton(
                        onPressed: () {
                          taskManager.removeByStatus(TaskStatus.failed);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已清理失败任务')),
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        child: const Text('清理失败'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── 任务列表 ──
        Expanded(
          child: tasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_download_outlined,
                        size: 64,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暂无任务',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return _TaskCard(
                      task: tasks[index],
                      onTap: () => _showTaskDetail(context, task),
                      onPauseResume: () {
                        if (task.status == TaskStatus.downloading) {
                          if (task.source == 'xhs') {
                            XhsBridge.pauseTask(task.id);
                          } else {
                            DouyinBridge.pauseTask(task.id);
                          }
                          taskManager.updateTask(
                            task.copyWith(status: TaskStatus.paused),
                          );
                        } else if (task.status == TaskStatus.paused ||
                            task.status == TaskStatus.failed) {
                          if (task.source == 'xhs') {
                            XhsBridge.resumeTask(task.id);
                          } else {
                            DouyinBridge.resumeTask(task.id);
                          }
                          taskManager.updateTask(
                            task.copyWith(
                              status: TaskStatus.downloading,
                              errorMessage: '',
                              downloadedSize: 0,
                            ),
                          );
                        }
                      },
                      onDelete: () => taskManager.removeTask(task.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showTaskDetail(BuildContext context, DownloadTask task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('任务详情'),
        content: Text(
          '标题: ${task.title}\n'
          '状态: ${task.status.displayName}\n'
          '来源: ${task.source == "xhs" ? "小红书" : "抖音"}\n'
          '类型: ${task.type}\n'
          '链接: ${task.url}\n'
          '${task.totalSize > 0 ? "大小: ${task.totalSizeStr}\n" : ""}'
          '${task.filePath.isNotEmpty ? "文件: ${task.filePath}\n" : ""}'
          '${task.errorMessage.isNotEmpty ? "错误: ${task.errorMessage}\n" : ""}',
          style: Theme.of(context).textTheme.bodySmall,
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
}

/// 任务卡片 - 完全复刻原项目 TaskCard
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

  Color _getStatusColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (task.status) {
      case TaskStatus.queued:
        return scheme.outline;
      case TaskStatus.downloading:
        return scheme.primary;
      case TaskStatus.paused:
        return scheme.tertiary;
      case TaskStatus.completed:
        return Colors.green;
      case TaskStatus.failed:
        return scheme.error;
    }
  }

  String _getStatusText() {
    switch (task.status) {
      case TaskStatus.queued:
        return '排队中';
      case TaskStatus.downloading:
        return '下载中 ${task.totalSize > 0 ? "${(task.progress * 100).toStringAsFixed(1)}%" : ""}';
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
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  // 标题和状态
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
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              _getStatusText(),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: _getStatusColor(context)),
                            ),
                            if (task.status == TaskStatus.failed &&
                                task.errorMessage.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  task.errorMessage.length > 30
                                      ? '${task.errorMessage.substring(0, 30)}...'
                                      : task.errorMessage,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 操作按钮
                  if (task.status == TaskStatus.downloading)
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        icon: const Icon(Icons.pause, size: 20),
                        onPressed: onPauseResume,
                        padding: EdgeInsets.zero,
                      ),
                    )
                  else if (task.status == TaskStatus.paused ||
                      task.status == TaskStatus.failed)
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        icon: const Icon(Icons.play_arrow, size: 20),
                        onPressed: onPauseResume,
                        padding: EdgeInsets.zero,
                      ),
                    )
                  else if (task.status == TaskStatus.completed)
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        icon: Icon(
                          Icons.delete,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        onPressed: onDelete,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                ],
              ),

              // 进度条 - 仅下载中/暂停时显示
              if (task.status == TaskStatus.downloading ||
                  task.status == TaskStatus.paused) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 3,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
