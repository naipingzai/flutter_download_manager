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
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

// 解决 jni 1.0.1 与 AGP 9+ 兼容问题：
// jni 包在 AGP 9+ 时不再自动 apply kotlin-android，但仍执行 kotlin{} 块
// 我们必须在 settingsEvaluated 之前给所有 Android Library 子项目应用 kotlin-android
gradle.settingsEvaluated {
    gradle.beforeProject {
        if (this != rootProject && this.name != "app" &&
            this.plugins.hasPlugin("com.android.library")) {
            try {
                plugins.apply("org.jetbrains.kotlin.android")
            } catch (_: Throwable) {
                // 忽略
            }
        }
    }
}

include(":app")
