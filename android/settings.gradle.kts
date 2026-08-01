pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        // Chaquopy Python 仓库
        maven("https://chaquo.com/maven")
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

// 解决 jni 1.0.1 与 AGP 9+ 兼容问题：
// jni 1.0.1 的 build.gradle 中有 `if (agpMajor < 9) { apply plugin: 'kotlin-android' }`，
// AGP 9+ 时不会自动 apply，导致 `kotlin { ... }` 块调用 kotlin() 方法失败。
// 通过 `gradle.beforeProject` 钩子在项目 evaluate 之前 apply 插件。
gradle.beforeProject {
    if (name == "jni") {
        try {
            plugins.apply("org.jetbrains.kotlin.android")
        } catch (_: Throwable) {
            // 忽略
        }
    }
}

include(":app")
