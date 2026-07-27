#!/usr/bin/env bash
# 编译 Web Release
# 自动确保 web 平台已启用（fresh checkout 可能缺失 web/ 目录）
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# 检查 web 平台是否已配置
if [ ! -d "web" ] || [ ! -f "web/index.html" ]; then
  echo "[SETUP] web 目录不完整，启用 web 平台..."
  flutter create --platforms=web --org=com.advancedownloader --project-name=flutter_download_manager . 2>&1 | tail -5
fi

echo "=== 编译 Web Release ==="
flutter build web --release

WEB_DIR="build/web"
if [ -d "$WEB_DIR" ] && [ -f "$WEB_DIR/index.html" ]; then
  SIZE=$(du -sh "$WEB_DIR" | cut -f1)
  echo ""
  echo "=== 编译成功 ==="
  echo "Web 资源: $PROJECT_DIR/$WEB_DIR ($SIZE)"
  echo "入口: $PROJECT_DIR/$WEB_DIR/index.html"
else
  echo "[错误] 编译失败，未找到 $WEB_DIR/index.html"
  exit 1
fi
