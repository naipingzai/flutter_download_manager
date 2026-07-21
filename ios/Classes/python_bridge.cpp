#include "python_bridge.h"
#include <Python.h>
#include <string>
#include <mutex>
#include <cstring>
#include <cstdio>

static std::mutex g_pyMutex;
static bool g_initialized = false;
static std::string g_scriptDir;
static char g_resultBuffer[65536];

bool python_bridge_init(const char* python_home, const char* script_dir) {
    std::lock_guard<std::mutex> lock(g_pyMutex);
    if (g_initialized) return true;

    if (!Py_IsInitialized()) {
        if (python_home && strlen(python_home) > 0) {
            wchar_t* whome = Py_DecodeLocale(python_home, nullptr);
            if (whome) {
                Py_SetPythonHome(whome);
            }
        }
        Py_Initialize();
        if (!Py_IsInitialized()) {
            fprintf(stderr, "[PythonBridge] Failed to init\n");
            return false;
        }
    }

    if (script_dir) {
        g_scriptDir = script_dir;
        std::string cmd = "import sys; sys.path.insert(0, '" + g_scriptDir + "')";
        PyRun_SimpleString(cmd.c_str());
    }

    PyRun_SimpleString("import json, sys, os");
    g_initialized = true;
    fprintf(stdout, "[PythonBridge] initialized, script_dir=%s\n", script_dir ? script_dir : "null");
    return true;
}

void python_bridge_destroy() {
    std::lock_guard<std::mutex> lock(g_pyMutex);
    if (g_initialized) {
        if (Py_IsInitialized()) Py_Finalize();
        g_initialized = false;
    }
}

bool python_bridge_is_ready() {
    return g_initialized && Py_IsInitialized();
}

const char* python_bridge_get_version() {
    if (!Py_IsInitialized()) return "Python not initialized";
    static char ver[128];
    snprintf(ver, sizeof(ver), "Python %s", Py_GetVersion());
    return ver;
}

void python_bridge_add_path(const char* path) {
    if (path) {
        std::string cmd = "sys.path.insert(0, '" + std::string(path) + "')";
        PyRun_SimpleString(cmd.c_str());
    }
}

static const char* call_py_function(PyObject* module, const char* func_name, const char* args_json) {
    g_resultBuffer[0] = '\0';

    PyObject* func = PyObject_GetAttrString(module, func_name);
    if (!func || !PyCallable_Check(func)) {
        if (func) Py_DECREF(func);
        snprintf(g_resultBuffer, sizeof(g_resultBuffer),
            "{\"success\":false,\"message\":\"Function '%s' not found\"}", func_name);
        return g_resultBuffer;
    }

    PyObject* args = PyTuple_New(0);
    if (args_json && strlen(args_json) > 0) {
        PyObject* json_mod = PyImport_ImportModule("json");
        if (json_mod) {
            PyObject* loads = PyObject_GetAttrString(json_mod, "loads");
            if (loads) {
                PyObject* jstr = PyUnicode_FromString(args_json);
                PyObject* parsed = PyObject_CallFunctionObjArgs(loads, jstr, nullptr);
                Py_DECREF(jstr);
                Py_DECREF(loads);
                if (parsed) {
                    if (PyList_Check(parsed)) {
                        Py_DECREF(args);
                        args = PyList_AsTuple(parsed);
                        Py_DECREF(parsed);
                    } else if (PyTuple_Check(parsed)) {
                        Py_DECREF(args);
                        args = parsed;
                    } else {
                        Py_DECREF(args);
                        args = PyTuple_New(1);
                        PyTuple_SetItem(args, 0, parsed);
                    }
                }
            }
            Py_DECREF(json_mod);
        }
    }

    PyObject* result = PyObject_CallObject(func, args);
    Py_DECREF(args);
    Py_DECREF(func);

    if (!result) {
        PyObject *pt, *pv, *ptr;
        PyErr_Fetch(&pt, &pv, &ptr);
        const char* err = "Unknown error";
        if (pv) {
            PyObject* s = PyObject_Str(pv);
            if (s) { err = PyUnicode_AsUTF8(s); Py_DECREF(s); }
        }
        snprintf(g_resultBuffer, sizeof(g_resultBuffer),
            "{\"success\":false,\"message\":\"Python error: %s\"}", err);
        if (pt) Py_DECREF(pt);
        if (pv) Py_DECREF(pv);
        if (ptr) Py_DECREF(ptr);
        PyErr_Clear();
        return g_resultBuffer;
    }

    if (PyUnicode_Check(result)) {
        const char* s = PyUnicode_AsUTF8(result);
        if (s) strncpy(g_resultBuffer, s, sizeof(g_resultBuffer) - 1);
    } else if (PyDict_Check(result) || PyList_Check(result)) {
        PyObject* json_mod = PyImport_ImportModule("json");
        if (json_mod) {
            PyObject* dumps = PyObject_GetAttrString(json_mod, "dumps");
            if (dumps) {
                PyObject* jstr = PyObject_CallFunctionObjArgs(dumps, result, nullptr);
                if (jstr) {
                    const char* s = PyUnicode_AsUTF8(jstr);
                    if (s) strncpy(g_resultBuffer, s, sizeof(g_resultBuffer) - 1);
                    Py_DECREF(jstr);
                }
                Py_DECREF(dumps);
            }
            Py_DECREF(json_mod);
        }
    } else if (result == Py_None) {
        strcpy(g_resultBuffer, "null");
    } else {
        PyObject* s = PyObject_Str(result);
        if (s) {
            const char* str = PyUnicode_AsUTF8(s);
            if (str) strncpy(g_resultBuffer, str, sizeof(g_resultBuffer) - 1);
            Py_DECREF(s);
        }
    }
    g_resultBuffer[sizeof(g_resultBuffer) - 1] = '\0';
    Py_DECREF(result);
    return g_resultBuffer;
}

const char* python_bridge_call(const char* module_name, const char* function_name, const char* args_json) {
    std::lock_guard<std::mutex> lock(g_pyMutex);
    if (!g_initialized || !Py_IsInitialized()) {
        snprintf(g_resultBuffer, sizeof(g_resultBuffer),
            "{\"success\":false,\"message\":\"Python not initialized\"}");
        return g_resultBuffer;
    }

    PyObject* module = PyImport_ImportModule(module_name);
    if (!module) {
        PyErr_Print();
        snprintf(g_resultBuffer, sizeof(g_resultBuffer),
            "{\"success\":false,\"message\":\"Module '%s' not found\"}", module_name);
        return g_resultBuffer;
    }

    const char* result = call_py_function(module, function_name, args_json);
    Py_DECREF(module);
    return result;
}
