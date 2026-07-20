# Flutter Download Manager

多平台媒体下载器 — Flutter + C++ 版本，参考 [AdvanceDownload](https://github.com/naipingzai/AdvanceDownload) 项目移植。

## 功能

- 下载抖音视频、图集、动图、直播录制
- 下载小红书视频、图片、LivePhoto
- 批量下载（收藏夹、收藏音乐、用户作品、合集）
- 从 TXT 文件导入链接批量下载
- 评论采集、封面下载、音频提取
- 下载历史记录管理
- 下载任务管理（暂停/恢复）
- Cookie 管理（多账号切换）
- Material You 动态取色主题

## 技术架构

| 层级 | 技术 |
|------|------|
| UI | Flutter + Material Design 3 |
| 架构 | 插件化框架（PlatformPlugin + PluginRegistry） |
| Python 桥接 | C++ 嵌入 CPython 解释器（dart:ffi） |
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
│   │   └── python_service.dart        # C++ Python 解释器 FFI
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
│   ├── dy_bridge.py                   # 抖音桥接（2596行）
│   └── xhs_bridge.py                  # 小红书桥接（1353行）
├── src/                               # C++ 源码
│   ├── CMakeLists.txt                 # CMake 构建配置
│   ├── download_engine.h/.cpp         # 下载引擎
│   └── python_bridge.h/.cpp           # CPython 嵌入桥接
├── android/                           # Android 平台
├── ios/                               # iOS 平台
├── linux/                             # Linux 平台
└── .github/workflows/build.yml        # CI/CD 自动编译
```

## 快速开始

### 环境要求

| 工具 | 最低版本 |
|------|----------|
| Flutter | 3.x |
| Dart SDK | 3.8+ |
| Python | 3.12+ |
| Android SDK | 35 |
| JDK | 17 |

### 构建运行

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

### CI/CD 自动编译

推送到 GitHub 后，GitHub Actions 自动编译：
- **Android**: Release APK
- **iOS**: 无签名 IPA

产物在 GitHub Actions → Artifacts 页面下载。

## Cookie 设置

使用前需要在 **设置 → Cookie 管理** 中分别填入抖音和小红书的 Cookie：

- 抖音 Cookie 获取：参考 [TikTokDownloader Cookie 教程](https://github.com/JoeanAmier/TikTokDownloader/blob/master/docs/Cookie%E8%8E%B7%E5%8F%96%E6%95%99%E7%A8%8B.md)
- 小红书 Cookie 获取：参考 [XHS-Downloader Cookie 教程](https://github.com/JoeanAmier/XHS-Downloader#cookie)

## 参考项目

本项目使用了以下开源项目的核心代码：

### TikTokDownloader (DouK-Downloader)

- **仓库**: https://github.com/JoeanAmier/TikTokDownloader
- **版本**: v5.8
- **作者**: [JoeanAmier](https://github.com/JoeanAmier)
- **许可证**: GNU General Public License v3.0 (GPL-3.0)

### XHS-Downloader

- **仓库**: https://github.com/JoeanAmier/XHS-Downloader
- **版本**: v2.8
- **作者**: [JoeanAmier](https://github.com/JoeanAmier)
- **许可证**: GNU General Public License v3.0 (GPL-3.0)

## 许可证

本项目遵循 **GNU General Public License v3.0 (GPL-3.0)** 许可证。

## 免责声明

- 本工具仅供学习和研究使用
- 请遵守相关法律法规和平台使用条款
- 不得将本工具用于任何违法用途
- 使用者需自行承担一切风险和法律责任
