# Flutter Download Manager

抖音 / 小红书媒体下载器，Flutter 纯 Dart 实现，零原生核心依赖。

支持平台：Android、iOS、Linux、macOS、Web

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

android/  ios/  linux/  macos/  web/         # 各平台原生工程
build_android.sh  build_linux.sh  build_macos.sh  build_web.sh   # 编译脚本
```

## UI 设计规范

详见 [DESIGN.md](./DESIGN.md) — 参考百度网盘、迅雷、IDM 等主流下载工具规范。

## 编译运行

### ⚠️ 重要：必须用 build 脚本

> 直接用 `flutter build apk --release` / `flutter build web --release` 在某些环境会失败（如 CI runner 缺少 web 平台、jni 与 AGP 9+ 不兼容）。
> **请使用项目根目录的 4 个 build 脚本**，它们会：
> - 自动修复 ~/.pub-cache 中 jni 1.0.1 的 AGP 9+ 兼容问题
> - 自动检测并重新生成 web/ 目录（fresh checkout 缺失时）
> - 检查平台依赖（Linux 需要 cmake）
> - 检查 OSTYPE（macOS 脚本只在 macOS 上运行）

### 各平台编译

```bash
# 推荐：使用 build 脚本（自动处理环境问题）
bash build_android.sh    # Android APK
bash build_linux.sh      # Linux 桌面
bash build_macos.sh      # macOS 桌面（仅在 macOS 环境）
bash build_web.sh        # Web

# 调试运行
flutter run

# 静态分析
flutter analyze         # 0 issues

# 直接 flutter build（不推荐，需要手动处理环境问题）
flutter build apk --release
flutter build ios --release --no-codesign
flutter build linux --release
flutter build macos --release
flutter build web --release
```

### 输出位置

| 平台 | 路径 |
|---|---|
| Android APK | `build/app/outputs/flutter-apk/app-release.apk` (~51MB) |
| iOS | `build/ios/iphoneos/Runner.app` |
| Linux | `build/linux/x64/release/bundle/flutter_download_manager` (~25MB) |
| macOS | `build/macos/Build/Products/Release/flutter_download_manager.app` |
| Web | `build/web/index.html` + 静态资源 (~41MB) |

## 平台特定说明

### 移动端 (Android / iOS)

- 全功能运行
- `gal` 插件将媒体保存到系统相册
- `path_provider` 提供应用沙箱目录

### 桌面端 (Linux / macOS)

- 通过 `AppButton` / `AppDialog` 自动适配 Material / Cupertino 视觉风格
- `gal` 在桌面端自动跳过相册操作（仅保存到下载目录）

### Web

- 服务层 `dart:io` 调用通过 `PlatformAdapter` 自动降级
- Cookie / 数据库通过 SharedPreferences 持久化（浏览器 LocalStorage）
- 浏览器限制：跨域下载可能需要后端代理

## License

GPL-3.0
