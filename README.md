# Flutter Download Manager

抖音 / 小红书媒体下载器，Flutter 纯 Dart 实现，零原生核心依赖。

支持平台：Android、iOS、Linux、macOS、Windows

## 功能特性

- 抖音视频 / 图集 / Live Photo 下载
- 小红书图文 / 视频笔记下载
- 多 Cookie 管理与切换
- 下载进度实时显示
- 任务暂停 / 继续 / 重试
- 自动保存到系统相册（iOS PhotoKit / Android MediaStore）

## 技术架构

```
┌─────────────────────────────────────────────┐
│           Application / Flutter UI          │
├─────────────────────────────────────────────┤
│       lib/ui/screens/  (业务页面层)          │
├─────────────────────────────────────────────┤
│       lib/design_system/  (Design System)   │
│       - AppButton / AppDialog / AppNavigation│
│       - PlatformAdapter (集中 Platform.isX)  │
├─────────────────────────────────────────────┤
│       lib/services/  (服务层)                │
│       - download/  (Douyin/Xhs Bridge)       │
│       - storage/   (Database / Cookie)       │
│       - platform/   (GalleryService)          │
├─────────────────────────────────────────────┤
│       lib/core/  (核心数据)                  │
│       - DownloadTask + DownloadTaskManager    │
└─────────────────────────────────────────────┘
```

零外部核心依赖：不需要 C++ / FFI / Python 嵌入，仅用 Dart 标准库。

## 项目结构

```
lib/
├── main.dart                              # 应用入口
├── app.dart                               # MaterialApp + 根路由
│
├── core/                                  # 核心模型
│   └── task_manager/
│       ├── download_task.dart
│       └── download_task_manager.dart       # ChangeNotifier
│
├── design_system/                         # Design System
│   ├── design_system.dart                 # 统一导出
│   ├── platform/platform_adapter.dart      # 唯一 Platform.isX 调用点
│   ├── theme/app_theme.dart               # Material 3 主题
│   ├── buttons/app_button.dart            # 语义化按钮 (4 variant × 3 size)
│   ├── inputs/app_text_field.dart         # 统一输入框
│   ├── navigation/app_navigation.dart     # 响应式导航 (<600dp Bar / ≥600dp Rail)
│   └── surfaces/app_dialog.dart           # 统一对话框
│
├── services/                              # 服务层
│   ├── download/
│   │   ├── native_download_service.dart   # HTTP + ABogus + INITIAL_STATE 解析
│   │   ├── bridge_base.dart               # 去重 / 节流 / 任务生命周期
│   │   ├── douyin_bridge.dart
│   │   └── xhs_bridge.dart
│   ├── platform/
│   │   └── gallery_service.dart           # 系统相册 (gal)
│   └── storage/
│       ├── storage_service.dart           # 应用目录封装
│       ├── database_service.dart          # JSON 文件持久化
│       └── cookie_store.dart              # 多 Cookie 切换
│
└── ui/                                    # 业务页面层
    └── screens/
        ├── home_screen.dart               # 首页 — 平台选择
        ├── download_screen.dart           # 下载页
        ├── tasks_screen.dart              # 任务页
        ├── settings_screen.dart           # 设置页
        ├── cookie_manage_screen.dart      # Cookie 管理
        └── platform_shell.dart            # 平台容器 (顶/底部 Tab 导航)

android/  ios/  linux/  macos/  windows/    # 各平台原生工程
```

## UI 设计规范

详见 [DESIGN.md](./DESIGN.md)

## 编译运行

### 准备

```bash
flutter pub get
```

### 各平台编译

```bash
# Android APK
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk

# iOS
flutter build ios --release --no-codesign

# Linux
flutter build linux --release
# → build/linux/x64/release/bundle/flutter_download_manager

# macOS
flutter build macos --release

# Windows
flutter build windows --release
```

### 静态检查

```bash
flutter analyze
```

## 平台特定说明

### 移动端 (Android / iOS)

- 全功能运行
- `gal` 插件将媒体保存到系统相册
- `path_provider` 提供应用沙箱目录

### 桌面端 (Linux / macOS / Windows)

- `AppButton` / `AppDialog` 自动适配视觉风格
- `gal` 在桌面端自动跳过相册操作

## License

GPL-3.0
