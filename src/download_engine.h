#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <map>

#ifdef _WIN32
    #define EXPORT __declspec(dllexport)
#else
    #define EXPORT __attribute__((visibility("default")))
#endif

extern "C" {

/// 下载状态枚举
enum DownloadStatus {
    QUEUED = 0,
    DOWNLOADING = 1,
    PAUSED = 2,
    COMPLETED = 3,
    FAILED = 4
};

/// 进度回调函数类型
typedef void (*ProgressCallback)(const char* task_id, int64_t downloaded, int64_t total, const char* title, void* user_data);

/// 完成回调函数类型
typedef void (*CompletionCallback)(const char* task_id, bool success, const char* message, void* user_data);

/// 初始化下载引擎
EXPORT void download_engine_init();

/// 销毁下载引擎
EXPORT void download_engine_destroy();

/// 创建下载任务
EXPORT const char* download_engine_create_task(
    const char* url,
    const char* save_path,
    const char* file_name,
    const char* platform,
    const char* headers_json
);

/// 开始下载任务
EXPORT bool download_engine_start_task(const char* task_id);

/// 暂停下载任务
EXPORT bool download_engine_pause_task(const char* task_id);

/// 恢复下载任务
EXPORT bool download_engine_resume_task(const char* task_id);

/// 取消下载任务
EXPORT bool download_engine_cancel_task(const char* task_id);

/// 设置进度回调
EXPORT void download_engine_set_progress_callback(ProgressCallback callback, void* user_data);

/// 设置完成回调
EXPORT void download_engine_set_completion_callback(CompletionCallback callback, void* user_data);

/// 获取任务状态
EXPORT int download_engine_get_task_status(const char* task_id);

/// 获取任务已下载大小
EXPORT int64_t download_engine_get_downloaded_size(const char* task_id);

/// 获取任务总大小
EXPORT int64_t download_engine_get_total_size(const char* task_id);

/// 获取错误信息
EXPORT const char* download_engine_get_error_message(const char* task_id);

/// 设置 HTTP 头部（全局）
EXPORT void download_engine_set_global_header(const char* key, const char* value);

/// 设置 Cookie
EXPORT void download_engine_set_cookie(const char* cookie);

/// 获取引擎版本
EXPORT const char* download_engine_get_version();

/// 解析链接（平台特定）
EXPORT const char* download_engine_parse_link(
    const char* url,
    const char* platform,
    const char* cookie,
    const char* save_path
);

/// 批量下载
EXPORT const char* download_engine_batch_download(
    const char* urls_json,
    const char* platform,
    const char* cookie,
    const char* save_path
);

} // extern "C"
