#!/usr/bin/env bash
# 编译 macOS Release（必须在 macOS 环境下运行）
set -e
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"
if [[ "$OSTYPE" != "darwin"* ]]; then
  echo "[提示] macOS 编译必须在 macOS 环境下运行。当前系统: $OSTYPE"
  echo "       在 macOS 上执行: bash build_macos.sh"
  exit 1
fi
echo "=== 编译 macOS Release ==="
flutter build macos --release
APP="build/macos/Build/Products/Release/flutter_download_manager.app"
if [ -d "$APP" ]; then
  SIZE=$(du -sh "$APP" | cut -f1)
  echo ""
  echo "=== 编译成功 ==="
  echo "App 包: $PROJECT_DIR/$APP ($SIZE)"
else
  echo "[错误] 编译失败，未找到 $APP"
  exit 1
fi
