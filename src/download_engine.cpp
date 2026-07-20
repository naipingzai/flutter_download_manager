#include "download_engine.h"
#include "http_client.h"

#include <string>
#include <map>
#include <mutex>
#include <thread>
#include <memory>
#include <cstring>
#include <sstream>

#ifdef __ANDROID__
#include <android/log.h>
#define LOG_TAG "DownloadEngine"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[INFO] " __VA_ARGS__); printf("\n")
#define LOGE(...) printf("[ERROR] " __VA_ARGS__); printf("\n")
#endif

/// 下载任务内部结构
struct DownloadTaskData {
    std::string id;
    std::string url;
    std::string savePath;
    std::string fileName;
    std::string platform;
    std::string headersJson;
    std::string errorMessage;
    DownloadStatus status;
    int64_t downloadedSize;
    int64_t totalSize;
    std::unique_ptr<HttpClient> httpClient;
    std::thread downloadThread;
};

/// 全局状态
static std::map<std::string, std::shared_ptr<DownloadTaskData>> g_tasks;
static std::mutex g_tasksMutex;
static ProgressCallback g_progressCallback = nullptr;
static CompletionCallback g_completionCallback = nullptr;
static void* g_progressUserData = nullptr;
static void* g_completionUserData = nullptr;
static std::map<std::string, std::string> g_globalHeaders;
static std::string g_cookie;

const char* download_engine_get_version() {
    return "1.0.0";
}

void download_engine_init() {
    std::lock_guard<std::mutex> lock(g_tasksMutex);
    LOGI("Download engine initialized");
}

void download_engine_destroy() {
    std::lock_guard<std::mutex> lock(g_tasksMutex);
    // 取消所有任务
    for (auto& pair : g_tasks) {
        auto& task = pair.second;
        if (task->httpClient) {
            task->httpClient->cancel();
        }
        if (task->downloadThread.joinable()) {
            task->downloadThread.join();
        }
    }
    g_tasks.clear();
    LOGI("Download engine destroyed");
}

const char* download_engine_create_task(
    const char* url,
    const char* save_path,
    const char* file_name,
    const char* platform,
    const char* headers_json) {
    
    std::lock_guard<std::mutex> lock(g_tasksMutex);
    
    // 生成任务 ID（简单实现）
    static int taskCounter = 0;
    char taskId[64];
    snprintf(taskId, sizeof(taskId), "task_%d_%ld", ++taskCounter, 
             static_cast<long>(time(nullptr)));
    
    auto task = std::make_shared<DownloadTaskData>();
    task->id = taskId;
    task->url = url ? url : "";
    task->savePath = save_path ? save_path : "";
    task->fileName = file_name ? file_name : "";
    task->platform = platform ? platform : "";
    task->headersJson = headers_json ? headers_json : "";
    task->status = QUEUED;
    task->downloadedSize = 0;
    task->totalSize = 0;
    task->httpClient = std::make_unique<HttpClient>();
    
    g_tasks[taskId] = task;
    
    // 复制任务 ID 到静态缓冲区
    static char resultBuffer[64];
    strncpy(resultBuffer, taskId, sizeof(resultBuffer) - 1);
    resultBuffer[sizeof(resultBuffer) - 1] = '\0';
    
    LOGI("Created task: %s", taskId);
    return resultBuffer;
}

bool download_engine_start_task(const char* task_id) {
    std::shared_ptr<DownloadTaskData> task;
    {
        std::lock_guard<std::mutex> lock(g_tasksMutex);
        auto it = g_tasks.find(task_id);
        if (it == g_tasks.end()) {
            LOGE("Task not found: %s", task_id);
            return false;
        }
        task = it->second;
    }
    
    if (task->status == DOWNLOADING) {
        return true; // 已在下载
    }
    
    task->status = DOWNLOADING;
    
    // 设置 HTTP 客户端
    for (const auto& header : g_globalHeaders) {
        task->httpClient->setHeader(header.first, header.second);
    }
    if (!g_cookie.empty()) {
        task->httpClient->setCookie(g_cookie);
    }
    
    // 在后台线程执行下载
    task->downloadThread = std::thread([task]() {
        std::string savePath = task->savePath + "/" + task->fileName;
        
        LOGI("Starting download: %s -> %s", task->url.c_str(), savePath.c_str());
        
        bool success = task->httpClient->downloadFile(
            task->url,
            savePath,
            [&task](int64_t downloaded, int64_t total) -> bool {
                task->downloadedSize = downloaded;
                task->totalSize = total;
                
                if (g_progressCallback) {
                    g_progressCallback(
                        task->id.c_str(),
                        downloaded,
                        total,
                        task->fileName.c_str(),
                        g_progressUserData
                    );
                }
                
                // 检查是否暂停或取消
                return !task->httpClient->getLastError().empty() == false;
            },
            false
        );
        
        if (success) {
            task->status = COMPLETED;
            LOGI("Download completed: %s", task->id.c_str());
        } else {
            task->status = FAILED;
            task->errorMessage = task->httpClient->getLastError();
            LOGE("Download failed: %s - %s", task->id.c_str(), task->errorMessage.c_str());
        }
        
        if (g_completionCallback) {
            g_completionCallback(
                task->id.c_str(),
                success,
                task->errorMessage.c_str(),
                g_completionUserData
            );
        }
    });
    
    return true;
}

bool download_engine_pause_task(const char* task_id) {
    std::lock_guard<std::mutex> lock(g_tasksMutex);
    auto it = g_tasks.find(task_id);
    if (it == g_tasks.end()) return false;
    
    auto& task = it->second;
    if (task->status == DOWNLOADING) {
        task->status = PAUSED;
        if (task->httpClient) {
            task->httpClient->pause();
        }
        LOGI("Task paused: %s", task_id);
    }
    return true;
}

bool download_engine_resume_task(const char* task_id) {
    std::lock_guard<std::mutex> lock(g_tasksMutex);
    auto it = g_tasks.find(task_id);
    if (it == g_tasks.end()) return false;
    
    auto& task = it->second;
    if (task->status == PAUSED) {
        task->status = DOWNLOADING;
        if (task->httpClient) {
            task->httpClient->resume();
        }
        LOGI("Task resumed: %s", task_id);
    }
    return true;
}

bool download_engine_cancel_task(const char* task_id) {
    std::lock_guard<std::mutex> lock(g_tasksMutex);
    auto it = g_tasks.find(task_id);
    if (it == g_tasks.end()) return false;
    
    auto& task = it->second;
    task->status = FAILED;
    task->errorMessage = "Cancelled by user";
    if (task->httpClient) {
        task->httpClient->cancel();
    }
    LOGI("Task cancelled: %s", task_id);
    return true;
}

void download_engine_set_progress_callback(ProgressCallback callback, void* user_data) {
    std::lock_guard<std::mutex> lock(g_tasksMutex);
    g_progressCallback = callback;
    g_progressUserData = user_data;
}

void download_engine_set_completion_callback(CompletionCallback callback, void* user_data) {
    std::lock_guard<std::mutex> lock(g_tasksMutex);
    g_completionCallback = callback;
    g_completionUserData = user_data;
}

int download_engine_get_task_status(const char* task_id) {
    std::lock_guard<std::mutex> lock(g_tasksMutex);
    auto it = g_tasks.find(task_id);
    if (it == g_tasks.end()) return -1;
    return static_cast<int>(it->second->status);
}

int64_t download_engine_get_downloaded_size(const char* task_id) {
    std::lock_guard<std::mutex> lock(g_tasksMutex);
    auto it = g_tasks.find(task_id);
    if (it == g_tasks.end()) return 0;
    return it->second->downloadedSize;
}

int64_t download_engine_get_total_size(const char* task_id) {
    std::lock_guard<std::mutex> lock(g_tasksMutex);
    auto it = g_tasks.find(task_id);
    if (it == g_tasks.end()) return 0;
    return it->second->totalSize;
}

const char* download_engine_get_error_message(const char* task_id) {
    std::lock_guard<std::mutex> lock(g_tasksMutex);
    auto it = g_tasks.find(task_id);
    if (it == g_tasks.end()) return "Task not found";
    
    static char errorBuffer[1024];
    strncpy(errorBuffer, it->second->errorMessage.c_str(), sizeof(errorBuffer) - 1);
    errorBuffer[sizeof(errorBuffer) - 1] = '\0';
    return errorBuffer;
}

void download_engine_set_global_header(const char* key, const char* value) {
    std::lock_guard<std::mutex> lock(g_tasksMutex);
    if (key && value) {
        g_globalHeaders[key] = value;
    }
}

void download_engine_set_cookie(const char* cookie) {
    std::lock_guard<std::mutex> lock(g_tasksMutex);
    g_cookie = cookie ? cookie : "";
}

const char* download_engine_parse_link(
    const char* url,
    const char* platform,
    const char* cookie,
    const char* save_path) {
    
    // 简化的链接解析实现
    // 在实际项目中，这里会根据平台调用不同的解析逻辑
    static char resultBuffer[4096];
    
    std::string urlStr = url ? url : "";
    std::string platformStr = platform ? platform : "";
    
    // 返回 JSON 格式的结果
    snprintf(resultBuffer, sizeof(resultBuffer),
        R"({"success": true, "platform": "%s", "url": "%s", "title": "Parsed from %s"})",
        platformStr.c_str(), urlStr.c_str(), platformStr.c_str());
    
    return resultBuffer;
}

const char* download_engine_batch_download(
    const char* urls_json,
    const char* platform,
    const char* cookie,
    const char* save_path) {
    
    static char resultBuffer[4096];
    
    // 简化的批量下载实现
    snprintf(resultBuffer, sizeof(resultBuffer),
        R"({"success": true, "message": "Batch download started", "count": 0})");
    
    return resultBuffer;
}
