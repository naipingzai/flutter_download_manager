#!/usr/bin/env bash
# 编译 Linux Release
set -e
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"
if ! command -v cmake &>/dev/null; then
  echo "[错误] cmake 未安装。请运行: sudo apt-get install -y cmake ninja-build libgtk-3-dev"
  exit 1
fi
echo "=== 编译 Linux Release ==="
flutter build linux --release
OUT="build/linux/x64/release/bundle/flutter_download_manager"
if [ -f "$OUT" ]; then
  SIZE=$(du -sh "$(dirname "$OUT")" | cut -f1)
  echo ""
  echo "=== 编译成功 ==="
  echo "可执行文件: $PROJECT_DIR/$OUT"
  echo "Bundle 大小: $SIZE"
else
  echo "[错误] 编译失败，未找到 $OUT"
  exit 1
fi
