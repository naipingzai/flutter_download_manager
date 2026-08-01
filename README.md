# 高级下载器 (Advanced Downloader)

> 聚合多平台内容下载工具 — Flutter 跨平台版本

基于 [TikTokDownloader](https://github.com/JoeanAmier/TikTokDownloader)、[XHS-Downloader](https://github.com/JoeanAmier/XHS-Downloader) 和 [AdvanceDownload](https://github.com/naipingzai/AdvanceDownload) 项目，使用 Flutter 重写的跨平台版本。

## 支持平台

| 平台 | 视频 | 图集 | 直播 | 状态 |
|------|------|------|------|------|
| 抖音 | ✅ | ✅ | 🚧 | 已支持 |
| 小红书 | ✅ | ✅ | - | 已支持 |
| 快手 | ✅ | 🚧 | 🚧 | 已支持 |

## 主要功能

- **多平台支持** — 抖音、小红书、快手
- **链接解析** — 自动解析短链接、提取作品ID
- **批量下载** — 支持多个链接同时粘贴下载
- **作者作品** — 按作者目录分类保存
- **任务管理** — 暂停/继续/重试/删除
- **进度显示** — 实时下载进度和速度
- **Cookie管理** — 多Cookie切换，关键字段校验
- **相册集成** — 下载完成后自动保存到系统相册
- **内嵌Python** — 所有平台均内嵌Python环境，无需系统安装
- **跨平台** — Android / iOS / Windows / macOS / Linux

## 项目结构

```
lib/
├── main.dart                          # 入口
├── app.dart                           # 应用路由
├── core/
│   └── task_manager/
│       ├── download_task.dart         # 任务数据模型
│       └── download_task_manager.dart # 任务管理器
├── design_system/                     # 设计系统
│   ├── buttons/                       # 按钮组件
│   ├── inputs/                        # 输入组件
│   ├── surfaces/                      # 弹窗组件
│   ├── navigation/                    # 导航组件
│   ├── platform/                      # 平台适配
│   └── theme/                         # 主题配置
├── services/
│   ├── download/
│   │   ├── bridge_base.dart           # 下载桥接基类
│   │   ├── douyin_bridge.dart         # 抖音桥接
│   │   ├── xhs_bridge.dart            # 小红书桥接
│   │   ├── kuaishou_bridge.dart       # 快手桥接
│   │   └── native_download_service.dart # 原生下载服务
│   ├── python/
│   │   └── python_runner.dart         # Python运行器
│   ├── storage/
│   │   ├── cookie_store.dart          # Cookie存储
│   │   ├── database_service.dart      # 数据库服务
│   │   └── storage_service.dart       # 存储服务
│   └── platform/
│       └── gallery_service.dart       # 相册服务
└── ui/
    └── screens/
        ├── home_screen.dart           # 首页(平台选择)
        ├── platform_shell.dart        # 平台导航框架
        ├── download_screen.dart       # 下载页
        ├── tasks_screen.dart          # 任务列表页
        ├── settings_screen.dart       # 设置页
        └── cookie_manage_screen.dart  # Cookie管理页

assets/
└── python/
    ├── dy_bridge.py                   # 抖音Python桥接
    ├── xhs_bridge.py                  # 小红书Python桥接
    └── ks_bridge.py                   # 快手Python桥接

python/
├── douyin_downloader/                 # 抖音下载核心
├── xhs_downloader/                    # 小红书下载核心
└── ks_downloader/                     # 快手下载核心
```

## 技术栈

- **Flutter** — 跨平台UI框架
- **Provider** — 状态管理
- **Python (Chaquopy)** — Android端Python运行环境
- **Dart:io** — 文件下载和网络请求
- **SharedPreferences** — 轻量级持久化
- **Material 3** — 设计系统

## 开发环境

```bash
# 安装依赖
flutter pub get

# 运行 (Android)
flutter run -d android

# 运行 (iOS)
flutter run -d ios

# 运行 (Desktop)
flutter run -d windows  # 或 macos / linux
```

## 内嵌 Python 环境

所有平台均使用**内嵌 Python**，不依赖系统 Python 安装。Python 运行时**预下载**到项目本地，不会在运行时下载。

### 准备工作

```bash
# 预下载 Python 运行时到 python_runtime/ 目录
bash scripts/download_python.sh
```

此脚本会自动下载 [python-build-standalone](https://github.com/indygreg/python-build-standalone) 的预编译 Python 3.12，并安装所需依赖包 (httpx, pyyaml, gmssl)。

### Android
使用 [Chaquopy](https://chaquo.com/chaquopy/) 内嵌 Python 3.12，Python脚本打包在 `android/app/src/main/python/` 目录，依赖通过 `build.gradle.kts` 的 `pip` 块自动安装。

### iOS
使用预编译的 CPython 静态库，通过 MethodChannel 调用。Python脚本从 `assets/python/` 解压到应用沙盒。

### Desktop (Windows / macOS / Linux)
使用预下载的 `python_runtime/` 目录中的 Python 运行时，通过 `scripts/download_python.sh` 脚本提前下载。

### Python 依赖
- `httpx` — HTTP客户端
- `gmssl` — SM3签名算法 (抖音ABogus签名)
- `pyyaml` — YAML解析

## 致谢

- [TikTokDownloader](https://github.com/JoeanAmier/TikTokDownloader) — 抖音下载核心
- [XHS-Downloader](https://github.com/JoeanAmier/XHS-Downloader) — 小红书下载核心
- [AdvanceDownload](https://github.com/naipingzai/AdvanceDownload) — 安卓版本参考

## 开源协议

GPL-3.0
