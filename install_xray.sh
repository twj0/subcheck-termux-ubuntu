#!/bin/bash

# Xray安装脚本 - 适用于ARM64 Ubuntu

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检测系统架构
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64) echo "64" ;;
        aarch64|arm64) echo "arm64-v8a" ;;
        armv7l) echo "arm32-v7a" ;;
        *) echo "unknown" ;;
    esac
}

# 安装Xray
install_xray() {
    info "开始安装Xray..."
    
    # 检测架构
    local arch=$(detect_arch)
    if [[ "$arch" == "unknown" ]]; then
        error "不支持的系统架构: $(uname -m)"
        exit 1
    fi
    
    info "检测到架构: $arch"
    
    # 创建安装目录
    local install_dir="/usr/local/bin"
    local temp_dir="/tmp/xray_install"
    
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # 获取最新版本
    info "获取Xray最新版本信息..."
    local latest_version
    if command -v curl >/dev/null 2>&1; then
        latest_version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)
    else
        latest_version="v1.8.4"  # 备用版本
        warn "无法获取最新版本，使用备用版本: $latest_version"
    fi
    
    info "准备安装版本: $latest_version"
    
    # 构建下载URL
    local download_url="https://github.com/XTLS/Xray-core/releases/download/${latest_version}/Xray-linux-${arch}.zip"
    
    # 尝试使用GitHub加速
    local mirrors=(
        "$download_url"
        "https://ghproxy.com/$download_url"
        "https://mirror.ghproxy.com/$download_url"
    )
    
    local downloaded=false
    for mirror in "${mirrors[@]}"; do
        info "尝试下载: $mirror"
        if curl -L -o "xray.zip" --connect-timeout 30 --max-time 300 "$mirror" 2>/dev/null; then
            if [[ -f "xray.zip" && $(stat -c%s "xray.zip") -gt 1000 ]]; then
                downloaded=true
                success "下载成功"
                break
            fi
        fi
        warn "下载失败，尝试下一个镜像..."
    done
    
    if [[ "$downloaded" != "true" ]]; then
        error "所有下载源都失败"
        exit 1
    fi
    
    # 解压安装
    info "解压并安装..."
    if command -v unzip >/dev/null 2>&1; then
        unzip -q "xray.zip"
    else
        error "需要安装unzip: apt install unzip"
        exit 1
    fi
    
    # 安装到系统目录
    if [[ -f "xray" ]]; then
        chmod +x "xray"
        cp "xray" "$install_dir/"
        success "Xray安装完成: $install_dir/xray"
    else
        error "解压后未找到xray可执行文件"
        exit 1
    fi
    
    # 清理临时文件
    cd /
    rm -rf "$temp_dir"
    
    # 验证安装
    if command -v xray >/dev/null 2>&1; then
        success "安装验证成功"
        xray version
    else
        error "安装验证失败"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    info "安装必要依赖..."
    
    # 更新包列表
    apt update >/dev/null 2>&1 || true
    
    # 安装基础工具
    local packages=(
        "curl"
        "unzip" 
        "ca-certificates"
        "netcat-openbsd"
    )
    
    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$pkg "; then
            info "安装 $pkg..."
            apt install -y "$pkg" >/dev/null 2>&1 || warn "安装 $pkg 失败"
        fi
    done
}

# 主安装流程
main() {
    info "Xray安装程序启动"
    
    # 检查权限
    if [[ $EUID -ne 0 ]]; then
        error "需要root权限运行此脚本"
        exit 1
    fi
    
    # 检查是否已安装
    if command -v xray >/dev/null 2>&1; then
        warn "Xray已安装"
        xray version
        read -p "是否重新安装? (y/N): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
    fi
    
    # 安装流程
    install_dependencies
    install_xray
    
    success "Xray安装完成！"
    info "现在可以运行测速脚本了"
}

main "$@"