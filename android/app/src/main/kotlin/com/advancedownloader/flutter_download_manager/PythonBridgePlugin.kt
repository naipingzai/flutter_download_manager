package com.advancedownloader.flutter_download_manager

import android.os.Environment
import com.chaquo.python.Python
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

/**
 * Python Bridge Plugin
 * 通过 Chaquopy 在 Android 上运行 Python 脚本，与 Flutter 通过 MethodChannel 通信。
 */
class PythonBridgePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var isPythonReady = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.advancedownloader/python_bridge")
        channel.setMethodCallHandler(this)
        // 初始化 Python 环境
        try {
            if (!Python.isStarted()) {
                Python.start()
            }
            isPythonReady = true
        } catch (e: Exception) {
            isPythonReady = false
            println("[PythonBridge] Failed to start Python: ${e.message}")
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> {
                result.success(isPythonReady)
            }
            "getStatus" -> {
                if (isPythonReady) {
                    try {
                        val py = Python.getInstance()
                        val sys = py.getModule("sys")
                        result.success(mapOf(
                            "available" to true,
                            "version" to sys["version"].toString(),
                            "platform" to sys["platform"].toString(),
                        ))
                    } catch (e: Exception) {
                        result.success(mapOf("available" to false, "error" to e.message))
                    }
                } else {
                    result.success(mapOf("available" to false, "error" to "Python not initialized"))
                }
            }
            "callPython" -> {
                val moduleName = call.argument<String>("module")
                val funcName = call.argument<String>("function")
                val args = call.argument<List<Any>>("args") ?: emptyList()

                if (moduleName == null || funcName == null) {
                    result.error("INVALID_ARGS", "module and function are required", null)
                    return
                }

                thread {
                    try {
                        val py = Python.getInstance()
                        val module = py.getModule(moduleName)
                        val pyArgs = args.map { arg ->
                            when (arg) {
                                is String -> arg
                                is Int -> arg
                                is Long -> arg
                                is Double -> arg
                                is Boolean -> arg
                                else -> arg.toString()
                            }
                        }.toTypedArray()

                        val pyResult = module.callAttr(funcName, *pyArgs)
                        val resultStr = pyResult?.toString() ?: ""
                        // 尝试解析为 JSON
                        if (resultStr.startsWith("{") || resultStr.startsWith("[")) {
                            try {
                                val json = org.json.JSONObject(resultStr)
                                // 转为 Map 返回
                                result.success(jsonToMap(json))
                            } catch (e: Exception) {
                                try {
                                    val jsonArray = org.json.JSONArray(resultStr)
                                    result.success(jsonArrayToList(jsonArray))
                                } catch (_: Exception) {
                                    result.success(resultStr)
                                }
                            }
                        } else {
                            result.success(resultStr)
                        }
                    } catch (e: Exception) {
                        result.error("PYTHON_ERROR", e.message, e.stackTraceToString())
                    }
                }
            }
            "getDownloadPath" -> {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                    "DyDownload"
                )
                dir.mkdirs()
                result.success(dir.absolutePath)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun jsonToMap(json: org.json.JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        for (key in json.keys()) {
            val value = json.get(key)
            map[key] = when (value) {
                is org.json.JSONObject -> jsonToMap(value)
                is org.json.JSONArray -> jsonArrayToList(value)
                is Boolean -> value
                is Int -> value
                is Long -> value
                is Double -> value
                org.json.JSONObject.NULL -> null
                else -> value.toString()
            }
        }
        return map
    }

    private fun jsonArrayToList(jsonArray: org.json.JSONArray): List<Any?> {
        val list = mutableListOf<Any?>()
        for (i in 0 until jsonArray.length()) {
            val value = jsonArray.get(i)
            list.add(when (value) {
                is org.json.JSONObject -> jsonToMap(value)
                is org.json.JSONArray -> jsonArrayToList(value)
                is Boolean -> value
                is Int -> value
                is Long -> value
                is Double -> value
                org.json.JSONObject.NULL -> null
                else -> value.toString()
            })
        }
        return list
    }
}
