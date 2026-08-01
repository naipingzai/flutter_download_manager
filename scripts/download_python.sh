#!/bin/bash
# ============================================================================
# Python Runtime 预下载脚本
# 将 python-build-standalone 下载到项目本地，避免运行时下载
# 使用方式: bash scripts/download_python.sh
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RUNTIME_DIR="$PROJECT_DIR/python_runtime"
PYTHON_VERSION="3.12.3"
PYTHON_BUILD_DATE="20240415"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 下载 URL 列表
WINDOWS_URL="https://github.com/indygreg/python-build-standalone/releases/download/${PYTHON_BUILD_DATE}/cpython-${PYTHON_VERSION}+${PYTHON_BUILD_DATE}-x86_64-pc-windows-msvc-shared-install_only.tar.gz"
MACOS_ARM64_URL="https://github.com/indygreg/python-build-standalone/releases/download/${PYTHON_BUILD_DATE}/cpython-${PYTHON_VERSION}+${PYTHON_BUILD_DATE}-aarch64-apple-darwin-install_only.tar.gz"
MACOS_X86_64_URL="https://github.com/indygreg/python-build-standalone/releases/download/${PYTHON_BUILD_DATE}/cpython-${PYTHON_VERSION}+${PYTHON_BUILD_DATE}-x86_64-apple-darwin-install_only.tar.gz"
LINUX_URL="https://github.com/indygreg/python-build-standalone/releases/download/${PYTHON_BUILD_DATE}/cpython-${PYTHON_VERSION}+${PYTHON_BUILD_DATE}-x86_64-unknown-linux-gnu-install_only.tar.gz"

download_and_extract() {
    local url="$1"
    local target_dir="$2"
    local platform_name="$3"
    
    if [ -d "$target_dir" ] && [ -f "$target_dir/bin/python3" -o -f "$target_dir/python.exe" ]; then
        log_info "$platform_name Python 已存在，跳过下载"
        return 0
    fi
    
    log_info "下载 $platform_name Python ${PYTHON_VERSION}..."
    log_info "URL: $url"
    
    mkdir -p "$target_dir"
    local temp_file=$(mktemp)
    
    # 下载
    if command -v curl &> /dev/null; then
        curl -L --progress-bar -o "$temp_file" "$url"
    elif command -v wget &> /dev/null; then
        wget --progress=bar:force -O "$temp_file" "$url"
    else
        log_error "需要 curl 或 wget"
        return 1
    fi
    
    # 解压
    log_info "解压到 $target_dir ..."
    tar xzf "$temp_file" -C "$target_dir" --strip-components=1
    
    # 清理
    rm -f "$temp_file"
    
    # 安装 Python 依赖
    local python_exe=""
    if [ -f "$target_dir/python.exe" ]; then
        python_exe="$target_dir/python.exe"
    elif [ -f "$target_dir/bin/python3" ]; then
        python_exe="$target_dir/bin/python3"
        chmod +x "$python_exe"
    fi
    
    if [ -n "$python_exe" ]; then
        log_info "安装 Python 依赖..."
        "$python_exe" -m pip install httpx pyyaml gmssl --quiet 2>/dev/null || true
    fi
    
    log_info "$platform_name Python 下载完成"
}

# ============================================================================
# 主流程
# ============================================================================

log_info "=========================================="
log_info "Python Runtime 预下载"
log_info "Python 版本: ${PYTHON_VERSION}"
log_info "目标目录: ${RUNTIME_DIR}"
log_info "=========================================="

mkdir -p "$RUNTIME_DIR"

# 检测当前平台
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux)
        log_info "检测到 Linux ${ARCH}"
        download_and_extract "$LINUX_URL" "$RUNTIME_DIR/linux" "Linux"
        ;;
    Darwin)
        log_info "检测到 macOS ${ARCH}"
        if [ "$ARCH" = "arm64" ]; then
            download_and_extract "$MACOS_ARM64_URL" "$RUNTIME_DIR/macos" "macOS (ARM64)"
        else
            download_and_extract "$MACOS_X86_64_URL" "$RUNTIME_DIR/macos" "macOS (x86_64)"
        fi
        ;;
    MINGW*|MSYS*|CYGWIN*)
        log_info "检测到 Windows"
        download_and_extract "$WINDOWS_URL" "$RUNTIME_DIR/windows" "Windows"
        ;;
    *)
        log_error "不支持的操作系统: $OS"
        exit 1
        ;;
esac

# 复制 Python 脚本到运行时目录
log_info "复制 Python 脚本..."
if [ -d "$PROJECT_DIR/assets/python" ]; then
    cp -v "$PROJECT_DIR/assets/python/"*.py "$RUNTIME_DIR/" 2>/dev/null || true
fi

log_info "=========================================="
log_info "Python Runtime 预下载完成!"
log_info "=========================================="
log_info ""
log_info "目录结构:"
find "$RUNTIME_DIR" -maxdepth 2 -type f -name "python*" | head -5
log_info ""
log_info "如需下载其他平台的 Python，可手动运行:"
log_info "  WINDOWS_URL=$WINDOWS_URL bash scripts/download_python.sh"
log_info "  MACOS_URL=$MACOS_ARM64_URL bash scripts/download_python.sh"
