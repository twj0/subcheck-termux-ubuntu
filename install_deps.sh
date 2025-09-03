#!/bin/bash

# 依赖安装脚本
# 适用于Ubuntu/Debian系统

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用root权限运行此脚本"
        exit 1
    fi
}

# 更新包管理器
update_packages() {
    log_info "更新包管理器..."
    apt update -y
    log_success "包管理器更新完成"
}

# 安装基础工具
install_basic_tools() {
    log_info "安装基础工具..."
    apt install -y curl wget jq bc netcat-openbsd python3 python3-pip
    log_success "基础工具安装完成"
}

# 安装Xray
install_xray() {
    log_info "安装Xray核心..."
    
    # 创建xray目录
    mkdir -p /usr/local/bin
    
    # 下载Xray
    local xray_version="1.8.4"
    local download_url="https://github.com/XTLS/Xray-core/releases/download/v${xray_version}/Xray-linux-64.zip"
    
    # 使用GitHub代理加速下载
    if curl -s --connect-timeout 5 "https://github.com" >/dev/null; then
        log_info "直接从GitHub下载Xray"
    else
        log_info "使用GitHub代理下载Xray"
        download_url="https://ghfast.top/${download_url}"
    fi
    
    # 下载并安装
    cd /tmp
    if wget -q --timeout=60 "$download_url" -O xray.zip; then
        unzip -q xray.zip
        chmod +x xray
        mv xray /usr/local/bin/
        log_success "Xray安装完成"
    else
        log_warning "Xray下载失败，尝试使用包管理器安装"
        # 备选方案：使用脚本安装
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    fi
    
    # 验证安装
    if command -v xray >/dev/null 2>&1; then
        local version=$(xray version | head -1)
        log_success "Xray安装成功: $version"
    else
        log_error "Xray安装失败"
        return 1
    fi
}

# 配置系统优化
optimize_system() {
    log_info "配置系统优化..."
    
    # 增加文件描述符限制
    echo "* soft nofile 65536" >> /etc/security/limits.conf
    echo "* hard nofile 65536" >> /etc/security/limits.conf
    
    # 优化网络参数
    cat >> /etc/sysctl.conf << EOF

# SubCheck网络优化
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr
EOF
    
    # 应用配置
    sysctl -p >/dev/null 2>&1 || true
    
    log_success "系统优化完成"
}

# 创建工作目录
setup_workspace() {
    log_info "设置工作目录..."
    
    local workspace="/root/subcheck/subcheck-termux-ubuntu"
    mkdir -p "$workspace"
    cd "$workspace"
    
    # 设置权限
    chmod +x *.sh 2>/dev/null || true
    chmod +x scripts/*.sh 2>/dev/null || true
    
    log_success "工作目录设置完成: $workspace"
}

# 测试安装
test_installation() {
    log_info "测试安装..."
    
    # 测试基础命令
    local commands=("curl" "wget" "jq" "bc" "nc" "python3" "xray")
    local failed_commands=()
    
    for cmd in "${commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_success "✓ $cmd 可用"
        else
            log_error "✗ $cmd 不可用"
            failed_commands+=("$cmd")
        fi
    done
    
    if [[ ${#failed_commands[@]} -eq 0 ]]; then
        log_success "所有依赖安装成功!"
        return 0
    else
        log_error "以下命令安装失败: ${failed_commands[*]}"
        return 1
    fi
}

# 主函数
main() {
    echo -e "${BLUE}=== SubCheck 依赖安装脚本 ===${NC}"
    echo "适用于Ubuntu/Debian系统"
    echo
    
    check_root
    update_packages
    install_basic_tools
    install_xray
    optimize_system
    setup_workspace
    
    echo
    if test_installation; then
        echo -e "${GREEN}=== 安装完成! ===${NC}"
        echo "现在可以运行测速脚本:"
        echo "  bash simple_subcheck.sh    # 简化版测速"
        echo "  bash enhanced_subcheck.sh test  # 完整版测速"
    else
        echo -e "${RED}=== 安装失败! ===${NC}"
        echo "请检查错误信息并重新运行"
        exit 1
    fi
}

# 执行主函数
main "$@"