#!/usr/bin/env bash
# 编译 Android Release APK
# 自动修复 jni 1.0.1 与 AGP 9+ 的兼容问题（不同环境下 ~/.pub-cache 路径可能不同）
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# 查找本机所有可能的 pub-cache 路径
fix_jni() {
  local cache_dirs=(
    "$HOME/.pub-cache"
    "/home/runner/.pub-cache"
    "/root/.pub-cache"
    "$HOME/.flutter/.pub-cache"
  )

  local fixed=0
  for cache_dir in "${cache_dirs[@]}"; do
    local jni_build="$cache_dir/hosted/pub.dev/jni-1.0.1/android/build.gradle"
    if [ -f "$jni_build" ]; then
      # 检查是否已经修复过
      if grep -q "if (true) {" "$jni_build" 2>/dev/null; then
        echo "[OK] jni 已修复: $jni_build"
        fixed=$((fixed+1))
        continue
      fi
      echo "[FIX] 修复 jni 兼容: $jni_build"
      sed -i 's/if (agpMajor < 9) {/if (true) {/' "$jni_build"
      fixed=$((fixed+1))
    fi
  done
  echo "  共修复 $fixed 处 jni 包"
}

echo "=== 1. 修复 jni 兼容（AGP 9+） ==="
fix_jni

echo ""
echo "=== 2. 编译 Android Release APK ==="
flutter build apk --release

APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [ -f "$APK_PATH" ]; then
  SIZE=$(du -h "$APK_PATH" | cut -f1)
  echo ""
  echo "=== 编译成功 ==="
  echo "APK 路径: $PROJECT_DIR/$APK_PATH"
  echo "大小: $SIZE"
else
  echo "[错误] 编译失败，未找到 $APK_PATH"
  exit 1
fi
