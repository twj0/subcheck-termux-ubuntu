#!/bin/bash

# 增强版订阅测速主控制脚本
# 实现定时测速和结果管理功能

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_SCRIPT="$SCRIPT_DIR/scripts/enhanced_parse.sh"
TEST_SCRIPT="$SCRIPT_DIR/scripts/enhanced_test.sh"
CONFIG_FILE="$SCRIPT_DIR/config.yaml"
RESULTS_DIR="$SCRIPT_DIR/results"
PID_FILE="/tmp/subcheck.pid"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 默认配置
DEFAULT_INTERVAL=3600  # 1小时
DEFAULT_MAX_NODES=50   # 最大测试节点数

# 日志函数
log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $1"
}

# 读取配置
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # 简单的YAML解析
        INTERVAL=$(grep "^interval:" "$CONFIG_FILE" | cut -d':' -f2 | tr -d ' ' || echo "$DEFAULT_INTERVAL")
        MAX_NODES=$(grep "^max_nodes:" "$CONFIG_FILE" | cut -d':' -f2 | tr -d ' ' || echo "$DEFAULT_MAX_NODES")
    else
        INTERVAL=$DEFAULT_INTERVAL
        MAX_NODES=$DEFAULT_MAX_NODES
    fi
    
    log_info "配置加载完成 - 测试间隔: ${INTERVAL}s, 最大节点数: $MAX_NODES"
}

# 创建结果目录
setup_directories() {
    mkdir -p "$RESULTS_DIR"
    log_info "结果目录: $RESULTS_DIR"
}

# 执行一次完整测试
run_test_cycle() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local result_file="$RESULTS_DIR/test_$timestamp.json"
    
    log_info "开始测试周期: $timestamp"
    
    # 解析订阅
    log_info "步骤 1/2: 解析订阅链接"
    if ! bash "$PARSE_SCRIPT"; then
        log_error "订阅解析失败"
        return 1
    fi
    
    # 测试节点
    log_info "步骤 2/2: 测试节点性能"
    if ! bash "$TEST_SCRIPT"; then
        log_error "节点测试失败"
        return 1
    fi
    
    # 复制结果
    if [[ -f "test_results.json" ]]; then
        cp "test_results.json" "$result_file"
        log_success "测试完成，结果保存到: $result_file"
        
        # 生成简要报告
        generate_summary_report "$result_file"
    else
        log_error "未找到测试结果文件"
        return 1
    fi
}

# 生成摘要报告
generate_summary_report() {
    local result_file="$1"
    local summary_file="${result_file%.json}_summary.txt"
    
    if ! command -v jq >/dev/null 2>&1; then
        log_warning "jq未安装，跳过摘要报告生成"
        return
    fi
    
    local results=$(cat "$result_file")
    local total_nodes=$(echo "$results" | jq 'length')
    local success_nodes=$(echo "$results" | jq '[.[] | select(.status == "success")] | length')
    local failed_nodes=$((total_nodes - success_nodes))
    
    # 生成摘要
    cat > "$summary_file" << EOF
=== SubCheck 测试报告 ===
测试时间: $(date '+%Y-%m-%d %H:%M:%S')
总节点数: $total_nodes
成功节点: $success_nodes
失败节点: $failed_nodes
成功率: $(echo "scale=2; $success_nodes * 100 / $total_nodes" | bc)%

=== 最佳节点 (按延迟排序) ===
EOF
    
    # 添加最佳节点列表
    echo "$results" | jq -r '.[] | select(.status == "success") | "\(.latency)ms \(.speed)Mbps \(.name)"' | \
        sort -n | head -10 | nl -w2 -s'. ' >> "$summary_file"
    
    log_info "摘要报告: $summary_file"
}

# 清理旧结果
cleanup_old_results() {
    local keep_days=7
    log_info "清理 $keep_days 天前的测试结果"
    
    find "$RESULTS_DIR" -name "test_*.json" -mtime +$keep_days -delete 2>/dev/null || true
    find "$RESULTS_DIR" -name "test_*_summary.txt" -mtime +$keep_days -delete 2>/dev/null || true
}

# 守护进程模式
daemon_mode() {
    log_info "启动守护进程模式，测试间隔: ${INTERVAL}s"
    
    # 保存PID
    echo $$ > "$PID_FILE"
    
    # 信号处理
    trap 'log_info "收到停止信号，退出守护进程"; rm -f "$PID_FILE"; exit 0' TERM INT
    
    while true; do
        # 执行测试
        run_test_cycle
        
        # 清理旧结果
        cleanup_old_results
        
        # 等待下次测试
        log_info "等待 ${INTERVAL}s 后进行下次测试..."
        sleep "$INTERVAL"
    done
}

# 停止守护进程
stop_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            log_info "守护进程已停止 (PID: $pid)"
            rm -f "$PID_FILE"
        else
            log_warning "守护进程未运行"
            rm -f "$PID_FILE"
        fi
    else
        log_warning "未找到PID文件，守护进程可能未运行"
    fi
}

# 检查守护进程状态
check_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_info "守护进程正在运行 (PID: $pid)"
            return 0
        else
            log_warning "PID文件存在但进程未运行"
            rm -f "$PID_FILE"
            return 1
        fi
    else
        log_info "守护进程未运行"
        return 1
    fi
}

# 显示最近结果
show_recent_results() {
    local count=${1:-5}
    log_info "显示最近 $count 次测试结果"
    
    local recent_files=$(ls -t "$RESULTS_DIR"/test_*.json 2>/dev/null | head -$count)
    
    if [[ -z "$recent_files" ]]; then
        log_warning "没有找到测试结果"
        return
    fi
    
    for file in $recent_files; do
        local basename=$(basename "$file" .json)
        local timestamp=$(echo "$basename" | cut -d'_' -f2-)
        local formatted_time=$(echo "$timestamp" | sed 's/_/ /' | sed 's/\(..\)\(..\)\(..\)/\1:\2:\3/')
        
        echo -e "\n${YELLOW}=== $formatted_time ===${NC}"
        
        if command -v jq >/dev/null 2>&1 && [[ -f "$file" ]]; then
            local results=$(cat "$file")
            local total=$(echo "$results" | jq 'length')
            local success=$(echo "$results" | jq '[.[] | select(.status == "success")] | length')
            
            echo "节点总数: $total, 成功: $success"
            echo "最佳节点:"
            echo "$results" | jq -r '.[] | select(.status == "success") | "\(.latency)ms \(.speed)Mbps \(.name)"' | \
                sort -n | head -3 | sed 's/^/  /'
        fi
    done
}

# 显示帮助信息
show_help() {
    cat << EOF
SubCheck - 订阅测速工具

用法: $0 [命令] [选项]

命令:
  test        执行一次测试
  start       启动守护进程
  stop        停止守护进程
  status      检查守护进程状态
  results     显示最近的测试结果
  help        显示此帮助信息

选项:
  -c, --config FILE    指定配置文件 (默认: config.yaml)
  -i, --interval SEC   设置测试间隔秒数 (默认: 3600)
  -n, --max-nodes NUM  设置最大测试节点数 (默认: 50)

示例:
  $0 test                    # 执行一次测试
  $0 start                   # 启动定时测试
  $0 start -i 1800           # 启动定时测试，间隔30分钟
  $0 results 10              # 显示最近10次结果
  $0 stop                    # 停止定时测试

配置文件格式 (config.yaml):
  interval: 3600      # 测试间隔(秒)
  max_nodes: 50       # 最大测试节点数
  
EOF
}

# 主函数
main() {
    local command="$1"
    shift
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -i|--interval)
                INTERVAL="$2"
                shift 2
                ;;
            -n|--max-nodes)
                MAX_NODES="$2"
                shift 2
                ;;
            *)
                break
                ;;
        esac
    done
    
    # 初始化
    load_config
    setup_directories
    
    # 执行命令
    case "$command" in
        "test")
            run_test_cycle
            ;;
        "start")
            if check_status; then
                log_warning "守护进程已在运行"
                exit 1
            fi
            daemon_mode
            ;;
        "stop")
            stop_daemon
            ;;
        "status")
            check_status
            ;;
        "results")
            show_recent_results "$1"
            ;;
        "help"|"--help"|"-h"|"")
            show_help
            ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"