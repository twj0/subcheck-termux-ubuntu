#!/bin/bash

# 增强版订阅解析脚本 - 集成Python和Node.js组件
# 支持多种订阅格式和GitHub代理优化

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$PROJECT_ROOT/src"
SUBSCRIPTION_FILE="$PROJECT_ROOT/subscription.txt"
OUTPUT_FILE="$PROJECT_ROOT/parsed_nodes.json"
CACHE_DIR="$PROJECT_ROOT/cache"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] [INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] [SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] [WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] [ERROR]${NC} $1"
}

# 检查Python环境和依赖
check_python_env() {
    log_info "检查Python环境..."
    
    # 检查Python
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "Python3 未安装"
        return 1
    fi
    
    # 检查uv包管理器
    if command -v uv >/dev/null 2>&1; then
        log_info "发现uv包管理器，使用uv安装依赖"
        cd "$PROJECT_ROOT"
        if [ ! -f ".venv/pyvenv.cfg" ]; then
            log_info "创建虚拟环境..."
            uv venv
        fi
        
        log_info "安装Python依赖..."
        uv pip install -r requirements.txt
        PYTHON_CMD="uv run python"
    else
        log_info "使用pip安装依赖..."
        pip3 install -r "$PROJECT_ROOT/requirements.txt" --user
        PYTHON_CMD="python3"
    fi
    
    return 0
}

# 检查Node.js环境
check_nodejs_env() {
    log_info "检查Node.js环境..."
    
    if ! command -v node >/dev/null 2>&1; then
        log_warning "Node.js 未安装，跳过格式转换功能"
        return 1
    fi
    
    local node_version=$(node --version | cut -d'v' -f2)
    log_info "Node.js版本: $node_version"
    
    return 0
}

# 创建必要目录
setup_directories() {
    mkdir -p "$CACHE_DIR"
    mkdir -p "$PROJECT_ROOT/results"
    mkdir -p "$PROJECT_ROOT/logs"
}

# 使用Python解析器解析订阅
parse_subscriptions_python() {
    log_info "使用Python解析器解析订阅..."
    
    cd "$PROJECT_ROOT"
    
    # 运行Python解析器
    if $PYTHON_CMD "$SRC_DIR/subscription_parser.py" "$SUBSCRIPTION_FILE" "$OUTPUT_FILE"; then
        log_success "Python解析器执行成功"
        return 0
    else
        log_error "Python解析器执行失败"
        return 1
    fi
}

# 使用Node.js转换格式
convert_formats_nodejs() {
    local input_file="$1"
    local format="$2"
    local output_file="$3"
    
    if ! command -v node >/dev/null 2>&1; then
        log_warning "Node.js未安装，跳过格式转换"
        return 1
    fi
    
    log_info "转换为 $format 格式..."
    
    cd "$PROJECT_ROOT"
    
    if node "$SRC_DIR/format_converter.js" "$input_file" "$format" "$output_file"; then
        log_success "$format 格式转换完成: $output_file"
        return 0
    else
        log_error "$format 格式转换失败"
        return 1
    fi
}

# 生成统计报告
generate_report() {
    local nodes_file="$1"
    
    if [ ! -f "$nodes_file" ]; then
        log_warning "节点文件不存在，跳过报告生成"
        return 1
    fi
    
    log_info "生成解析报告..."
    
    local total_nodes=0
    local valid_nodes=0
    
    if command -v jq >/dev/null 2>&1; then
        total_nodes=$(jq 'length' "$nodes_file" 2>/dev/null || echo "0")
        valid_nodes=$(jq '[.[] | select(.server and .port)] | length' "$nodes_file" 2>/dev/null || echo "0")
    else
        # 简单统计
        total_nodes=$(grep -c '"name"' "$nodes_file" 2>/dev/null || echo "0")
        valid_nodes=$total_nodes
    fi
    
    local report_file="$PROJECT_ROOT/results/parse_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
=== SubCheck 订阅解析报告 ===
解析时间: $(date '+%Y-%m-%d %H:%M:%S')
订阅文件: $SUBSCRIPTION_FILE
输出文件: $nodes_file

=== 统计信息 ===
总节点数: $total_nodes
有效节点: $valid_nodes
有效率: $(echo "scale=2; $valid_nodes * 100 / $total_nodes" | bc 2>/dev/null || echo "N/A")%

=== 文件信息 ===
节点文件大小: $(du -h "$nodes_file" 2>/dev/null | cut -f1 || echo "N/A")
缓存目录: $CACHE_DIR
缓存文件数: $(ls -1 "$CACHE_DIR" 2>/dev/null | wc -l || echo "0")

=== 环境信息 ===
Python版本: $(python3 --version 2>/dev/null || echo "未安装")
Node.js版本: $(node --version 2>/dev/null || echo "未安装")
系统信息: $(uname -a 2>/dev/null || echo "未知")
EOF
    
    log_success "解析报告已生成: $report_file"
    
    # 显示简要统计
    echo -e "\n${YELLOW}=== 解析统计 ===${NC}"
    echo "总节点数: $total_nodes"
    echo "有效节点: $valid_nodes"
    if [ $total_nodes -gt 0 ]; then
        echo "有效率: $(echo "scale=1; $valid_nodes * 100 / $total_nodes" | bc 2>/dev/null || echo "N/A")%"
    fi
}

# 清理缓存
cleanup_cache() {
    local max_age_hours=${1:-24}  # 默认24小时
    
    log_info "清理 ${max_age_hours} 小时前的缓存文件..."
    
    if [ -d "$CACHE_DIR" ]; then
        find "$CACHE_DIR" -name "*.cache" -mtime "+$(echo "$max_age_hours/24" | bc)" -delete 2>/dev/null || true
        local remaining=$(ls -1 "$CACHE_DIR" 2>/dev/null | wc -l || echo "0")
        log_info "缓存清理完成，剩余 $remaining 个文件"
    fi
}

# 主函数
main() {
    local format="${1:-json}"  # 默认输出JSON格式
    local cleanup_hours="${2:-24}"  # 默认清理24小时前的缓存
    
    log_info "=== SubCheck 订阅解析器启动 ==="
    log_info "输出格式: $format"
    log_info "项目根目录: $PROJECT_ROOT"
    
    # 初始化
    setup_directories
    
    # 检查订阅文件
    if [ ! -f "$SUBSCRIPTION_FILE" ]; then
        log_error "订阅文件不存在: $SUBSCRIPTION_FILE"
        exit 1
    fi
    
    local subscription_count=$(grep -c "^http" "$SUBSCRIPTION_FILE" 2>/dev/null || echo "0")
    log_info "发现 $subscription_count 个订阅链接"
    
    # 检查Python环境
    if ! check_python_env; then
        log_error "Python环境检查失败"
        exit 1
    fi
    
    # 检查Node.js环境
    check_nodejs_env
    local nodejs_available=$?
    
    # 清理旧缓存
    cleanup_cache "$cleanup_hours"
    
    # 解析订阅
    if ! parse_subscriptions_python; then
        log_error "订阅解析失败"
        exit 1
    fi
    
    # 验证输出文件
    if [ ! -f "$OUTPUT_FILE" ]; then
        log_error "解析输出文件不存在: $OUTPUT_FILE"
        exit 1
    fi
    
    # 格式转换（如果需要且Node.js可用）
    if [ "$format" != "json" ] && [ $nodejs_available -eq 0 ]; then
        local format_output="$PROJECT_ROOT/results/nodes_$(date +%Y%m%d_%H%M%S).$format"
        
        case "$format" in
            "clash"|"yaml")
                convert_formats_nodejs "$OUTPUT_FILE" "clash" "${format_output%.clash}.yaml"
                ;;
            "v2ray"|"base64")
                convert_formats_nodejs "$OUTPUT_FILE" "v2ray" "${format_output%.v2ray}.txt"
                ;;
            "quantumult")
                convert_formats_nodejs "$OUTPUT_FILE" "quantumult" "${format_output%.quantumult}.conf"
                ;;
            *)
                log_warning "不支持的输出格式: $format，保持JSON格式"
                ;;
        esac
    fi
    
    # 生成报告
    generate_report "$OUTPUT_FILE"
    
    log_success "=== 订阅解析完成 ==="
    log_info "主要输出: $OUTPUT_FILE"
    log_info "详细报告: $PROJECT_ROOT/results/"
}

# 显示帮助信息
show_help() {
    cat << EOF
SubCheck 订阅解析器 - 增强版

用法: $0 [格式] [缓存清理时间]

参数:
  格式           输出格式 (json|clash|v2ray|quantumult) 默认: json
  缓存清理时间   清理多少小时前的缓存 默认: 24

示例:
  $0                    # 解析为JSON格式
  $0 clash              # 解析并转换为Clash格式
  $0 v2ray 12           # 解析为V2Ray格式，清理12小时前的缓存

环境要求:
  - Python 3.8+
  - 推荐使用uv包管理器
  - Node.js 14+ (可选，用于格式转换)

文件结构:
  $SUBSCRIPTION_FILE    # 订阅链接列表
  $OUTPUT_FILE          # JSON格式输出
  $PROJECT_ROOT/results/            # 转换格式和报告
  $CACHE_DIR/           # 缓存目录
EOF
}

# 处理命令行参数
case "${1:-}" in
    "-h"|"--help"|"help")
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac