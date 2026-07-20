# Flutter Download Manager

多平台媒体下载器 — Flutter + Python 版本，参考 [AdvanceDownload](https://github.com/naipingzai/AdvanceDownload) 项目移植。

## 功能

- 下载抖音视频、图集、动图、直播录制
- 下载小红书视频、图片、LivePhoto
- 批量下载（收藏夹、收藏音乐、用户作品、合集）
- 评论采集、封面下载、音频提取
- 下载任务管理（暂停/恢复）
- Cookie 管理（多账号切换）
- Material You 动态取色主题

## 技术架构

| 层级 | 技术 |
|------|------|
| UI | Flutter + Material Design 3 |
| 架构 | 插件化框架（PlatformPlugin + PluginRegistry） |
| Python 桥接 | Process.run 调用 python3 脚本 |
| 抖音采集 | TikTokDownloader v5.8 核心（Python） |
| 小红书采集 | XHS-Downloader v2.8 核心（Python） |
| 本地存储 | sqflite + SQLite |
| 构建 | Flutter 3.x + Gradle |

## 项目结构

```
flutter_download_manager/
├── lib/
│   ├── main.dart                      # 应用入口
│   ├── framework/                     # 插件化框架
│   │   ├── platform_plugin.dart       # 平台插件接口
│   │   └── plugin_registry.dart       # 插件注册中心
│   ├── model/
│   │   └── download_task.dart         # 下载任务模型
│   ├── platform/
│   │   ├── douyin/                    # 抖音模块
│   │   │   ├── douyin_plugin.dart     # 抖音插件
│   │   │   └── douyin_bridge.dart     # 抖音桥接层
│   │   └── xhs/                       # 小红书模块
│   │       ├── xhs_plugin.dart        # 小红书插件
│   │       └── xhs_bridge.dart        # 小红书桥接层
│   ├── service/
│   │   ├── database_service.dart      # SQLite 数据库
│   │   ├── download_task_manager.dart # 下载任务管理器
│   │   ├── cookie_store.dart          # Cookie 多账号存储
│   │   └── python_runner.dart         # Python 脚本调用器
│   └── ui/
│       ├── theme/app_theme.dart       # Material 3 主题
│       └── screens/
│           ├── home_screen.dart       # 首页（平台选择）
│           ├── platform_shell.dart    # 平台导航框架
│           ├── download_screen.dart   # 下载页面
│           ├── tasks_screen.dart      # 任务管理页面
│           ├── settings_screen.dart   # 设置页面
│           └── cookie_manage_screen.dart # Cookie 管理
├── python/                            # Python 源码
│   ├── runner.py                      # Python CLI 入口
│   ├── dy_bridge.py                   # 抖音桥接（2596行）
│   └── xhs_bridge.py                  # 小红书桥接（1353行）
├── android/                           # Android 平台
├── ios/                               # iOS 平台
├── linux/                             # Linux 平台
└── .github/workflows/build.yml        # CI/CD 自动编译
```

## 环境要求

| 工具 | 最低版本 |
|------|----------|
| Flutter | 3.x |
| Dart SDK | 3.0+ |
| Python | 3.8+ |
| Android SDK | 35 |
| JDK | 17 |

## 构建运行

```bash
# 安装依赖
flutter pub get

# Linux 运行
flutter run -d linux

# Android APK
flutter build apk --release

# iOS (需要 macOS + Xcode)
flutter build ios --release --no-codesign
```

## Cookie 设置

使用前在 **设置 → Cookie 管理** 中填入抖音/小红书的 Cookie。

- 抖音 Cookie：参考 [TikTokDownloader 教程](https://github.com/JoeanAmier/TikTokDownloader/blob/master/docs/Cookie%E8%8E%B7%E5%8F%96%E6%95%99%E7%A8%8B.md)
- 小红书 Cookie：参考 [XHS-Downloader 教程](https://github.com/JoeanAmier/XHS-Downloader#cookie)

## 参考项目

- [TikTokDownloader](https://github.com/JoeanAmier/TikTokDownloader) v5.8 - GPL-3.0
- [XHS-Downloader](https://github.com/JoeanAmier/XHS-Downloader) v2.8 - GPL-3.0

## 许可证

GPL-3.0
