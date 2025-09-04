#!/bin/bash

# SubCheck 安装脚本 - 支持GitHub代理
# 针对中国大陆网络环境优化

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# GitHub代理列表
GITHUB_PROXIES=(
    "https://ghfast.top/"
    "https://gh-proxy.com/"
    "https://ghproxy.net/"
    "https://mirror.ghproxy.com/"
    "https://ghproxy.cc/"
    ""  # 直连作为备选
)

# 日志函数
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

# 测试GitHub代理可用性
test_github_proxy() {
    local proxy="$1"
    local test_url="${proxy}https://raw.githubusercontent.com/XTLS/Xray-core/main/README.md"
    
    if curl -s --connect-timeout 5 --max-time 10 "$test_url" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 获取可用的GitHub代理
get_working_github_proxy() {
    log_info "测试GitHub代理可用性..."
    
    for proxy in "${GITHUB_PROXIES[@]}"; do
        if [[ -z "$proxy" ]]; then
            log_info "测试直连..."
        else
            log_info "测试代理: $proxy"
        fi
        
        if test_github_proxy "$proxy"; then
            if [[ -z "$proxy" ]]; then
                log_success "直连可用"
            else
                log_success "代理可用: $proxy"
            fi
            echo "$proxy"
            return 0
        fi
    done
    
    log_error "所有GitHub代理都不可用"
    return 1
}

# 检测系统架构
detect_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64) echo "64" ;;
        aarch64|arm64) echo "arm64-v8a" ;;
        armv7l) echo "arm32-v7a" ;;
        *) 
            log_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
}

# 安装Xray
install_xray() {
    log_info "安装Xray核心..."
    
    # 检查是否已安装
    if command -v xray >/dev/null 2>&1; then
        log_success "Xray已安装"
        return 0
    fi
    
    # 获取GitHub代理
    local github_proxy=$(get_working_github_proxy)
    if [[ $? -ne 0 ]]; then
        log_error "无法获取GitHub代理，安装失败"
        return 1
    fi
    
    # 检测架构
    local arch=$(detect_architecture)
    local xray_url="${github_proxy}https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${arch}.zip"
    
    # 创建临时目录
    local temp_dir=$(mktemp -d)
    
    log_info "下载Xray: $xray_url"
    
    # 下载并安装
    if curl -L --connect-timeout 10 --max-time 300 "$xray_url" -o "$temp_dir/xray.zip" && 
       unzip -q "$temp_dir/xray.zip" -d "$temp_dir" && 
       sudo cp "$temp_dir/xray" /usr/local/bin/ && 
       sudo chmod +x /usr/local/bin/xray; then
        
        log_success "Xray安装成功"
        rm -rf "$temp_dir"
        return 0
    else
        log_error "Xray安装失败"
        rm -rf "$temp_dir"
        return 1
    fi
}

# 安装Python依赖
install_python_deps() {
    log_info "安装Python依赖..."
    
    cd "$PROJECT_DIR"
    
    # 检查Python包管理器
    if command -v uv >/dev/null 2>&1; then
        log_info "使用uv安装依赖"
        if uv sync; then
            log_success "Python依赖安装成功 (uv)"
            return 0
        else
            log_warning "uv安装失败，尝试pip"
        fi
    fi
    
    if command -v pip3 >/dev/null 2>&1; then
        log_info "使用pip3安装依赖"
        
        # 使用中国镜像源
        local pip_index="https://pypi.tuna.tsinghua.edu.cn/simple"
        
        if pip3 install -i "$pip_index" -r requirements.txt; then
            log_success "Python依赖安装成功 (pip3)"
            return 0
        else
            log_warning "清华镜像失败，尝试阿里镜像"
            pip_index="https://mirrors.aliyun.com/pypi/simple"
            
            if pip3 install -i "$pip_index" -r requirements.txt; then
                log_success "Python依赖安装成功 (pip3 阿里镜像)"
                return 0
            else
                log_error "Python依赖安装失败"
                return 1
            fi
        fi
    fi
    
    log_error "未找到Python包管理器"
    return 1
}

# 创建必要目录
create_directories() {
    log_info "创建项目目录结构..."
    
    local dirs=(
        "logs"
        "results"
        "cache"
        "xray_configs"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$PROJECT_DIR/$dir"
    done
    
    log_success "目录结构创建完成"
}

# 检查依赖
check_dependencies() {
    log_info "检查系统依赖..."
    
    local missing_deps=()
    
    # 检查基础工具
    local required_tools=("curl" "unzip" "jq" "bc")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_deps+=("$tool")
        fi
    done
    
    # 检查Python
    if ! command -v python3 >/dev/null 2>&1; then
        missing_deps+=("python3")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_warning "缺少依赖: ${missing_deps[*]}"
        log_info "尝试自动安装..."
        
        # 检测包管理器并安装
        if command -v apt >/dev/null 2>&1; then
            sudo apt update && sudo apt install -y "${missing_deps[@]}"
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y "${missing_deps[@]}"
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm "${missing_deps[@]}"
        else
            log_error "无法自动安装依赖，请手动安装: ${missing_deps[*]}"
            return 1
        fi
    fi
    
    log_success "系统依赖检查完成"
}

# 配置优化
optimize_config() {
    log_info "优化配置文件..."
    
    # 检测网络带宽并更新配置
    local bandwidth=$(detect_bandwidth)
    if [[ $bandwidth -gt 0 ]]; then
        log_info "检测到网络带宽: ${bandwidth}Mbps"
        
        # 更新config.yaml中的带宽设置
        if command -v yq >/dev/null 2>&1; then
            yq eval ".network.user_bandwidth = $bandwidth" -i "$PROJECT_DIR/config.yaml"
        else
            # 使用sed简单替换
            sed -i "s/user_bandwidth: [0-9]*/user_bandwidth: $bandwidth/" "$PROJECT_DIR/config.yaml"
        fi
    fi
    
    log_success "配置优化完成"
}

# 检测网络带宽
detect_bandwidth() {
    log_info "检测网络带宽..."
    
    # 简单的带宽检测
    local test_url="http://cachefly.cachefly.net/1mb.test"
    local start_time=$(date +%s.%N)
    
    if curl -s --max-time 10 "$test_url" -o /dev/null; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)
        local speed_mbps=$(echo "scale=0; 8 / $duration" | bc)
        
        # 限制范围
        if [[ $speed_mbps -lt 10 ]]; then
            speed_mbps=50  # 默认最小值
        elif [[ $speed_mbps -gt 1000 ]]; then
            speed_mbps=1000  # 默认最大值
        fi
        
        echo "$speed_mbps"
    else
        echo "100"  # 默认值
    fi
}

# 运行初始测试
run_initial_test() {
    log_info "运行初始测试..."
    
    cd "$PROJECT_DIR"
    
    # 首先解析订阅
    log_info "解析订阅源..."
    if python3 src/subscription_parser.py subscription.txt parsed_nodes.json; then
        local node_count=$(jq 'length' parsed_nodes.json 2>/dev/null || echo "0")
        log_success "订阅解析完成: $node_count 个节点"
        
        if [[ $node_count -gt 0 ]]; then
            # 运行小规模测试
            log_info "运行小规模测试 (5个节点)..."
            if python3 src/optimized_network_tester.py parsed_nodes.json test_results_sample.json; then
                local success_count=$(jq '[.[] | select(.status == "success")] | length' test_results_sample.json 2>/dev/null || echo "0")
                log_success "初始测试完成: $success_count 个节点成功"
                
                if [[ $success_count -eq 0 ]]; then
                    log_warning "没有节点测试成功，可能需要调整配置"
                    analyze_test_failures
                fi
            else
                log_error "初始测试失败"
            fi
        else
            log_warning "没有解析到有效节点"
        fi
    else
        log_error "订阅解析失败"
    fi
}

# 分析测试失败原因
analyze_test_failures() {
    log_info "分析测试失败原因..."
    
    if [[ -f "test_results_sample.json" ]]; then
        # 统计失败原因
        local errors=$(jq -r '.[] | select(.status == "failed") | .error' test_results_sample.json 2>/dev/null | sort | uniq -c | sort -nr)
        
        if [[ -n "$errors" ]]; then
            log_warning "主要失败原因:"
            echo "$errors" | while read -r count reason; do
                echo "  - $reason: $count 次"
            done
            
            # 给出建议
            if echo "$errors" | grep -q "TCP连接失败"; then
                log_info "建议: 大部分节点TCP连接失败，可能是节点质量问题或网络环境限制"
            fi
            
            if echo "$errors" | grep -q "代理启动失败"; then
                log_info "建议: 代理启动失败，检查Xray是否正确安装"
            fi
        fi
    fi
}

# 主函数
main() {
    echo -e "${BLUE}=== SubCheck 安装脚本 ===${NC}"
    echo -e "${BLUE}中国大陆网络环境优化版${NC}"
    echo ""
    
    # 检查依赖
    check_dependencies || exit 1
    
    # 创建目录
    create_directories
    
    # 安装Xray
    install_xray || exit 1
    
    # 安装Python依赖
    install_python_deps || exit 1
    
    # 优化配置
    optimize_config
    
    # 运行初始测试
    run_initial_test
    
    echo ""
    log_success "安装完成！"
    echo ""
    echo -e "${GREEN}使用方法:${NC}"
    echo "  1. 编辑 subscription.txt 添加订阅链接"
    echo "  2. 运行: bash scripts/enhanced_test.sh [节点数量]"
    echo "  3. 查看结果: cat results/test_results.json"
    echo ""
    echo -e "${YELLOW}配置文件: config.yaml${NC}"
    echo -e "${YELLOW}日志目录: logs/${NC}"
    echo -e "${YELLOW}结果目录: results/${NC}"
}

# 执行主函数
main "$@"
