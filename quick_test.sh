#!/bin/bash

# 快速测试脚本 - 验证环境和基本功能

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

# 检查系统信息
check_system() {
    log_info "=== 系统信息检查 ==="
    echo "操作系统: $(uname -a)"
    echo "当前用户: $(whoami)"
    echo "当前目录: $(pwd)"
    echo "Python版本: $(python3 --version 2>/dev/null || echo '未安装')"
    echo
}

# 检查网络连接
check_network() {
    log_info "=== 网络连接检查 ==="
    
    local test_urls=(
        "www.google.com"
        "www.baidu.com"
        "github.com"
    )
    
    for url in "${test_urls[@]}"; do
        if ping -c 1 -W 3 "$url" >/dev/null 2>&1; then
            log_success "✓ $url 可达"
        else
            log_warning "✗ $url 不可达"
        fi
    done
    echo
}

# 检查必要工具
check_tools() {
    log_info "=== 工具可用性检查 ==="
    
    local tools=(
        "curl:HTTP客户端"
        "wget:下载工具"
        "jq:JSON处理器"
        "bc:计算器"
        "nc:网络工具"
        "python3:Python解释器"
        "xray:代理核心"
        "base64:编码工具"
    )
    
    local missing_tools=()
    
    for tool_info in "${tools[@]}"; do
        local tool="${tool_info%%:*}"
        local desc="${tool_info#*:}"
        
        if command -v "$tool" >/dev/null 2>&1; then
            log_success "✓ $tool ($desc)"
        else
            log_warning "✗ $tool ($desc) - 未安装"
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo
        log_warning "缺少工具: ${missing_tools[*]}"
        log_info "运行以下命令安装:"
        echo "  sudo apt update"
        echo "  sudo apt install -y curl wget jq bc netcat-openbsd python3"
        echo "  # 对于xray，运行: bash install_deps.sh"
    fi
    echo
}

# 测试订阅解析
test_subscription_parsing() {
    log_info "=== 订阅解析测试 ==="
    
    if [[ ! -f "subscription.txt" ]]; then
        log_warning "subscription.txt 不存在，跳过解析测试"
        return
    fi
    
    local line_count=$(wc -l < subscription.txt)
    log_info "订阅文件包含 $line_count 行"
    
    # 测试第一个订阅链接
    local first_url=$(head -1 subscription.txt | grep -v '^#' | head -1)
    if [[ -n "$first_url" ]]; then
        log_info "测试第一个订阅: $first_url"
        
        if command -v curl >/dev/null 2>&1; then
            local content=$(curl -s --connect-timeout 10 --max-time 30 "$first_url" | head -c 200)
            if [[ -n "$content" ]]; then
                log_success "✓ 订阅内容获取成功 (前200字符): ${content:0:50}..."
            else
                log_warning "✗ 订阅内容获取失败"
            fi
        else
            log_warning "curl不可用，跳过订阅测试"
        fi
    fi
    echo
}

# 测试脚本语法
test_script_syntax() {
    log_info "=== 脚本语法检查 ==="
    
    local scripts=(
        "simple_subcheck.sh"
        "enhanced_subcheck.sh"
        "install_deps.sh"
        "scripts/enhanced_parse.sh"
        "scripts/enhanced_test.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            if bash -n "$script" 2>/dev/null; then
                log_success "✓ $script 语法正确"
            else
                log_error "✗ $script 语法错误"
            fi
        else
            log_warning "? $script 不存在"
        fi
    done
    echo
}

# 生成测试报告
generate_report() {
    log_info "=== 环境就绪状态 ==="
    
    local ready=true
    
    # 检查基本工具
    if ! command -v curl >/dev/null 2>&1; then
        log_error "✗ curl 未安装 - 无法下载订阅"
        ready=false
    fi
    
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "✗ python3 未安装 - Base64解码可能失败"
        ready=false
    fi
    
    # 检查订阅文件
    if [[ ! -f "subscription.txt" ]]; then
        log_error "✗ subscription.txt 不存在"
        ready=false
    fi
    
    # 检查脚本
    if [[ ! -f "simple_subcheck.sh" ]]; then
        log_error "✗ simple_subcheck.sh 不存在"
        ready=false
    fi
    
    if [[ "$ready" == true ]]; then
        log_success "🎉 环境就绪！可以运行测速脚本"
        echo
        echo "推荐运行顺序:"
        echo "1. bash quick_test.sh              # 环境检查"
        echo "2. bash install_deps.sh            # 安装依赖(需要root)"
        echo "3. bash simple_subcheck.sh         # 简化版测速"
        echo "4. bash enhanced_subcheck.sh test  # 完整版测速"
    else
        log_warning "⚠️  环境未完全就绪，请先解决上述问题"
        echo
        echo "建议操作:"
        echo "1. 安装缺少的工具: apt install -y curl wget jq bc netcat-openbsd python3"
        echo "2. 运行依赖安装脚本: bash install_deps.sh"
        echo "3. 重新运行此测试: bash quick_test.sh"
    fi
}

# 主函数
main() {
    echo -e "${BLUE}=== SubCheck 快速测试工具 ===${NC}"
    echo "检查环境和依赖是否就绪"
    echo
    
    check_system
    check_network
    check_tools
    test_subscription_parsing
    test_script_syntax
    generate_report
    
    log_info "测试完成!"
}

# 执行主函数
main "$@"