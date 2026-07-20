#include "python_bridge.h"
#include <Python.h>
#include <string>
#include <mutex>
#include <cstring>

#ifdef __ANDROID__
#include <android/log.h>
#define LOG_TAG "PythonBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[PY INFO] " __VA_ARGS__); printf("\n")
#define LOGE(...) printf("[PY ERROR] " __VA_ARGS__); printf("\n")
#endif

static std::mutex g_pyMutex;
static bool g_initialized = false;
static std::string g_scriptDir;
static char g_resultBuffer[65536]; // 64KB 结果缓冲区

bool python_bridge_init(const char* python_home, const char* script_dir) {
    std::lock_guard<std::mutex> lock(g_pyMutex);
    
    if (g_initialized) {
        LOGI("Python bridge already initialized");
        return true;
    }

    if (!Py_IsInitialized()) {
        // 设置 Python Home
        if (python_home && strlen(python_home) > 0) {
            Py_SetPythonHome(Py_DecodeLocale(python_home, nullptr));
        }

        // 初始化 Python 解释器
        Py_Initialize();
        
        if (!Py_IsInitialized()) {
            LOGE("Failed to initialize Python interpreter");
            return false;
        }
    }

    // 设置脚本目录
    if (script_dir) {
        g_scriptDir = script_dir;
        // 将脚本目录添加到 sys.path
        PyRun_SimpleString(
            ("import sys; sys.path.insert(0, '" + g_scriptDir + "')").c_str()
        );
        LOGI("Script directory: %s", script_dir);
    }

    // 导入必要的模块
    PyRun_SimpleString("import json, sys, os");

    g_initialized = true;
    LOGI("Python bridge initialized successfully");
    return true;
}

void python_bridge_destroy() {
    std::lock_guard<std::mutex> lock(g_pyMutex);
    if (g_initialized) {
        if (Py_IsInitialized()) {
            Py_Finalize();
        }
        g_initialized = false;
        LOGI("Python bridge destroyed");
    }
}

bool python_bridge_is_ready() {
    return g_initialized && Py_IsInitialized();
}

const char* python_bridge_get_version() {
    if (!Py_IsInitialized()) {
        return "Python not initialized";
    }
    static char version[128];
    snprintf(version, sizeof(version), "Python %s", Py_GetVersion());
    return version;
}

void python_bridge_set_env(const char* key, const char* value) {
    if (key && value) {
        std::string cmd = std::string("os.environ['") + key + "'] = '" + value + "'";
        PyRun_SimpleString(cmd.c_str());
    }
}

void python_bridge_add_path(const char* path) {
    if (path) {
        std::string cmd = std::string("sys.path.insert(0, '") + path + "')";
        PyRun_SimpleString(cmd.c_str());
    }
}

/// 调用 Python 函数的通用实现
static const char* _call_python_function(
    PyObject* module,
    const char* function_name,
    const char* args_json) {
    
    g_resultBuffer[0] = '\0';
    
    // 获取函数对象
    PyObject* func = PyObject_GetAttrString(module, function_name);
    if (!func || !PyCallable_Check(func)) {
        if (func) Py_DECREF(func);
        LOGE("Function '%s' not found or not callable", function_name);
        snprintf(g_resultBuffer, sizeof(g_resultBuffer),
            "{\"success\": false, \"message\": \"Function '%s' not found\"}", 
            function_name);
        return g_resultBuffer;
    }

    // 准备参数：将 JSON 字符串作为参数传递
    PyObject* args = nullptr;
    if (args_json && strlen(args_json) > 0) {
        // 解析 JSON 参数
        PyObject* json_module = PyImport_ImportModule("json");
        if (json_module) {
            PyObject* loads = PyObject_GetAttrString(json_module, "loads");
            if (loads) {
                PyObject* json_str = PyUnicode_FromString(args_json);
                args = PyObject_CallFunctionObjArgs(loads, json_str, nullptr);
                Py_DECREF(json_str);
                Py_DECREF(loads);
                
                // 如果解析结果是列表，展开为参数
                if (args && PyList_Check(args)) {
                    PyObject* tuple = PyList_AsTuple(args);
                    Py_DECREF(args);
                    args = tuple;
                } else if (args && !PyTuple_Check(args)) {
                    // 如果是单个值，包装为元组
                    PyObject* tuple = PyTuple_New(1);
                    PyTuple_SetItem(tuple, 0, args);
                    args = tuple;
                }
            }
            Py_DECREF(json_module);
        }
    }

    if (!args) {
        args = PyTuple_New(0);
    }

    // 调用函数
    PyObject* result = PyObject_CallObject(func, args);
    Py_DECREF(args);
    Py_DECREF(func);

    if (!result) {
        // 获取异常信息
        PyObject *ptype, *pvalue, *ptraceback;
        PyErr_Fetch(&ptype, &pvalue, &ptraceback);
        const char* error_msg = "Unknown error";
        if (pvalue) {
            PyObject* str = PyObject_Str(pvalue);
            if (str) {
                error_msg = PyUnicode_AsUTF8(str);
                Py_DECREF(str);
            }
        }
        LOGE("Python function call failed: %s", error_msg);
        snprintf(g_resultBuffer, sizeof(g_resultBuffer),
            "{\"success\": false, \"message\": \"Python error: %s\"}", error_msg);
        if (ptype) Py_DECREF(ptype);
        if (pvalue) Py_DECREF(pvalue);
        if (ptraceback) Py_DECREF(ptraceback);
        PyErr_Clear();
        return g_resultBuffer;
    }

    // 将结果转换为 JSON 字符串
    if (PyUnicode_Check(result)) {
        // 如果结果已经是字符串，直接返回
        const char* str = PyUnicode_AsUTF8(result);
        if (str) {
            strncpy(g_resultBuffer, str, sizeof(g_resultBuffer) - 1);
            g_resultBuffer[sizeof(g_resultBuffer) - 1] = '\0';
        }
    } else if (PyDict_Check(result) || PyList_Check(result) || PyTuple_Check(result)) {
        // 将 dict/list/tuple 转换为 JSON 字符串
        PyObject* json_module = PyImport_ImportModule("json");
        if (json_module) {
            PyObject* dumps = PyObject_GetAttrString(json_module, "dumps");
            if (dumps) {
                PyObject* json_str = PyObject_CallFunctionObjArgs(dumps, result, nullptr);
                if (json_str) {
                    const char* str = PyUnicode_AsUTF8(json_str);
                    if (str) {
                        strncpy(g_resultBuffer, str, sizeof(g_resultBuffer) - 1);
                        g_resultBuffer[sizeof(g_resultBuffer) - 1] = '\0';
                    }
                    Py_DECREF(json_str);
                }
                Py_DECREF(dumps);
            }
            Py_DECREF(json_module);
        }
    } else if (PyBool_Check(result)) {
        snprintf(g_resultBuffer, sizeof(g_resultBuffer), "%s", 
            result == Py_True ? "true" : "false");
    } else if (PyLong_Check(result)) {
        snprintf(g_resultBuffer, sizeof(g_resultBuffer), "%ld", PyLong_AsLong(result));
    } else if (PyFloat_Check(result)) {
        snprintf(g_resultBuffer, sizeof(g_resultBuffer), "%f", PyFloat_AsDouble(result));
    } else if (result == Py_None) {
        snprintf(g_resultBuffer, sizeof(g_resultBuffer), "null");
    } else {
        PyObject* str = PyObject_Str(result);
        if (str) {
            const char* s = PyUnicode_AsUTF8(str);
            if (s) {
                strncpy(g_resultBuffer, s, sizeof(g_resultBuffer) - 1);
                g_resultBuffer[sizeof(g_resultBuffer) - 1] = '\0';
            }
            Py_DECREF(str);
        }
    }

    Py_DECREF(result);
    return g_resultBuffer;
}

const char* python_bridge_call(
    const char* module_name,
    const char* function_name,
    const char* args_json) {
    
    std::lock_guard<std::mutex> lock(g_pyMutex);
    
    if (!g_initialized || !Py_IsInitialized()) {
        snprintf(g_resultBuffer, sizeof(g_resultBuffer),
            "{\"success\": false, \"message\": \"Python not initialized\"}");
        return g_resultBuffer;
    }

    // 导入模块
    PyObject* module = PyImport_ImportModule(module_name);
    if (!module) {
        LOGE("Failed to import module '%s'", module_name);
        PyErr_Print();
        snprintf(g_resultBuffer, sizeof(g_resultBuffer),
            "{\"success\": false, \"message\": \"Module '%s' not found\"}", 
            module_name);
        return g_resultBuffer;
    }

    const char* result = _call_python_function(module, function_name, args_json);
    Py_DECREF(module);
    return result;
}

const char* python_bridge_exec_script(
    const char* script_path,
    const char* function_name,
    const char* args_json) {
    
    std::lock_guard<std::mutex> lock(g_pyMutex);
    
    if (!g_initialized || !Py_IsInitialized()) {
        snprintf(g_resultBuffer, sizeof(g_resultBuffer),
            "{\"success\": false, \"message\": \"Python not initialized\"}");
        return g_resultBuffer;
    }

    // 读取并执行脚本文件
    FILE* fp = fopen(script_path, "r");
    if (!fp) {
        LOGE("Failed to open script: %s", script_path);
        snprintf(g_resultBuffer, sizeof(g_resultBuffer),
            "{\"success\": false, \"message\": \"Script not found: %s\"}", 
            script_path);
        return g_resultBuffer;
    }
    fclose(fp);

    // 从路径中提取模块名
    std::string path_str(script_path);
    size_t last_slash = path_str.find_last_of("/\\");
    size_t last_dot = path_str.find_last_of('.');
    std::string module_name;
    if (last_dot != std::string::npos && last_dot > last_slash) {
        module_name = path_str.substr(last_slash + 1, last_dot - last_slash - 1);
    } else {
        module_name = path_str.substr(last_slash + 1);
    }

    // 如果脚本所在目录不在 sys.path 中，添加它
    std::string script_dir = path_str.substr(0, last_slash);
    std::string add_path_cmd = "if '" + script_dir + "' not in sys.path: sys.path.insert(0, '" + script_dir + "')";
    PyRun_SimpleString(add_path_cmd.c_str());

    // 导入模块
    PyObject* module = PyImport_ImportModule(module_name.c_str());
    if (!module) {
        // 如果导入失败，尝试重新加载
        PyErr_Print();
        module = PyImport_ImportModule(module_name.c_str());
        if (!module) {
            LOGE("Failed to import script module '%s'", module_name.c_str());
            PyErr_Print();
            snprintf(g_resultBuffer, sizeof(g_resultBuffer),
                "{\"success\": false, \"message\": \"Failed to load script: %s\"}", 
                module_name.c_str());
            return g_resultBuffer;
        }
    }

    const char* result = _call_python_function(module, function_name, args_json);
    Py_DECREF(module);
    return result;
}
