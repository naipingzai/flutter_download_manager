#pragma once

#include "download_engine.h"

#ifdef __cplusplus
extern "C" {
#endif

/// 初始化 Python 解释器
EXPORT bool python_bridge_init(const char* python_home, const char* script_dir);

/// 销毁 Python 解释器
EXPORT void python_bridge_destroy();

/// 调用 Python 模块函数，返回 JSON 字符串结果
EXPORT const char* python_bridge_call(
    const char* module_name,
    const char* function_name,
    const char* args_json
);

/// 调用 Python 脚本文件
EXPORT const char* python_bridge_exec_script(
    const char* script_path,
    const char* function_name,
    const char* args_json
);

/// 检查 Python 解释器是否已初始化
EXPORT bool python_bridge_is_ready();

/// 获取 Python 版本信息
EXPORT const char* python_bridge_get_version();

/// 设置 Python 环境变量
EXPORT void python_bridge_set_env(const char* key, const char* value);

/// 添加 Python 模块搜索路径
EXPORT void python_bridge_add_path(const char* path);

#ifdef __cplusplus
}
#endif
