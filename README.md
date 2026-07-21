# Flutter Download Manager

多平台媒体下载器，支持抖音、小红书等平台的视频/图片下载。

## 技术架构

```
┌─────────────────────────────────────────────────┐
│                   Flutter UI                     │
├─────────────────────────────────────────────────┤
│         DouyinBridge      XhsBridge             │
│              (Dart FFI → C++)                   │
├─────────────────────────────────────────────────┤
│         C++ python_bridge (src/)                │
│         ┌─ 嵌入 Python 解释器                   │
│         ├─ 调用 dy_bridge.py                    │
│         └─ 调用 xhs_bridge.py                   │
├─────────────────────────────────────────────────┤
│  Python 脚本 (python/)                          │
│  ┌─ dy_bridge: 抖音解析 + ABogus签名 + 下载     │
│  └─ xhs_bridge: 小红书解析 + 下载               │
└─────────────────────────────────────────────────┘
```

## 依赖要求

- Flutter SDK >= 3.0.0
- CMake >= 3.10
- C++17 编译器
- Python 3.8+ (嵌入式，需 python3-dev)

## 编译运行

```bash
# 安装 Flutter 依赖
flutter pub get

# 安装 Python 依赖
pip3 install -r python/requirements.txt

# 编译 C++ python_bridge 库
mkdir -p src/build && cd src/build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
cd ../..

# 运行
flutter run
```

## 项目结构

```
├── lib/
│   ├── main.dart                          # 入口
│   ├── model/
│   │   └── download_task.dart             # 任务数据模型
│   ├── service/
│   │   ├── python_service.dart            # FFI 桥接服务 (调用C++库)
│   │   ├── download_task_manager.dart     # 任务管理器
│   │   ├── database_service.dart          # SQLite 数据库
│   │   └── cookie_store.dart              # Cookie 持久化
│   ├── framework/
│   │   ├── platform_plugin.dart           # 平台插件抽象
│   │   └── plugin_registry.dart           # 插件注册表
│   ├── platform/
│   │   ├── douyin/
│   │   │   ├── douyin_bridge.dart         # 抖音桥接 (调用Python)
│   │   │   └── douyin_plugin.dart         # 抖音平台插件
│   │   └── xhs/
│   │       ├── xhs_bridge.dart            # 小红书桥接 (调用Python)
│   │       └── xhs_plugin.dart            # 小红书平台插件
│   └── ui/
│       ├── screens/                       # 页面
│       └── theme/                         # 主题
├── src/                                   # C++ 源码
│   ├── CMakeLists.txt
│   ├── python_bridge.h                    # C FFI 接口
│   └── python_bridge.cpp                  # 嵌入 Python 解释器
├── python/                                # Python 脚本
│   ├── dy_bridge.py                       # 抖音下载核心
│   ├── xhs_bridge.py                      # 小红书下载核心
│   ├── runner.py                          # CLI 调试入口
│   └── requirements.txt
└── pubspec.yaml
```

## 功能特性

- [x] 任务模型定义
- [x] SQLite 数据库持久化
- [x] Cookie 管理
- [x] C++ 嵌入 Python 解释器 (FFI)
- [x] 抖音视频/图集下载
- [x] 小红书笔记下载
- [x] 抖音直播录制
- [x] 抖音评论采集
- [x] ABogus 签名算法
- [x] msToken / ttwid 自动获取
- [ ] 断点续传
- [ ] 下载速度优化
- [ ] 批量下载账号/合集/收藏夹

## License

MIT
