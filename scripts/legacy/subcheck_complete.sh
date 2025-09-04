#!/bin/bash

# SubCheck - 完整功能的订阅测速工具
# 适用于 Termux Ubuntu 环境
# 支持 VMess/VLESS/Trojan 协议的完整测试

set -e

# ==================== 配置参数 ====================
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBSCRIPTION_FILE="$SCRIPT_DIR/subscription.txt"
RESULTS_FILE="$SCRIPT_DIR/test_results.json"
CONFIG_FILE="$SCRIPT_DIR/config.yaml"
TEMP_DIR="/tmp/subcheck_$$"
PID_FILE="/tmp/subcheck.pid"

# 默认配置
DEFAULT_MAX_NODES=20
DEFAULT_TEST_TIMEOUT=10
DEFAULT_SOCKS_PORT=10808
DEFAULT_INTERVAL=3600

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==================== 工具函数 ====================
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

log_debug() {
    [[ "${DEBUG:-0}" == "1" ]] && echo -e "${CYAN}[$(date '+%H:%M:%S')] [DEBUG]${NC} $1"
}

# 清理函数
cleanup() {
    log_debug "执行清理操作"
    pkill -f "xray.*$TEMP_DIR" 2>/dev/null || true
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}

# 设置清理陷阱
trap cleanup EXIT

# 检查依赖
check_dependencies() {
    local missing_deps=()
    
    for cmd in curl base64 bc; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "缺少依赖: ${missing_deps[*]}"
        log_info "请安装: apt update && apt install -y ${missing_deps[*]}"
        return 1
    fi
    
    if ! command -v xray >/dev/null 2>&1; then
        log_warning "Xray未安装，将跳过代理测试"
        return 2
    fi
    
    return 0
}

# 加载配置
load_config() {
    # 设置默认值
    MAX_NODES=$DEFAULT_MAX_NODES
    TEST_TIMEOUT=$DEFAULT_TEST_TIMEOUT
    SOCKS_PORT=$DEFAULT_SOCKS_PORT
    INTERVAL=$DEFAULT_INTERVAL
    
    # 从配置文件读取
    if [[ -f "$CONFIG_FILE" ]]; then
        log_debug "加载配置文件: $CONFIG_FILE"
        
        # 简单的YAML解析
        while IFS=': ' read -r key value; do
            case "$key" in
                "max_nodes") MAX_NODES="$value" ;;
                "test_timeout") TEST_TIMEOUT="$value" ;;
                "socks_port") SOCKS_PORT="$value" ;;
                "interval") INTERVAL="$value" ;;
            esac
        done < "$CONFIG_FILE"
    fi
    
    log_debug "配置: MAX_NODES=$MAX_NODES, TIMEOUT=$TEST_TIMEOUT, PORT=$SOCKS_PORT"
}

# ==================== 订阅处理 ====================
# 获取订阅内容
fetch_subscription() {
    local url="$1"
    local content=""
    
    log_debug "获取订阅: $url"
    
    if [[ "$url" == http* ]]; then
        # 网络订阅，支持GitHub加速
        local github_proxy=""
        if [[ "$url" == *"github.com"* ]]; then
            github_proxy="https://ghproxy.com/"
        fi
        
        content=$(curl -s --connect-timeout 15 --max-time 60 \
                      -H "User-Agent: SubCheck/$VERSION" \
                      "${github_proxy}${url}" 2>/dev/null || echo "")
    else
        # 本地文件
        content=$(cat "$url" 2>/dev/null || echo "")
    fi
    
    if [[ -z "$content" ]]; then
        log_warning "无法获取订阅内容: $url"
        return 1
    fi
    
    # 检测并解码Base64
    if [[ "$content" != *"://"* ]]; then
        log_debug "检测到Base64编码，正在解码"
        local decoded=$(echo "$content" | base64 -d 2>/dev/null || echo "")
        if [[ -n "$decoded" ]]; then
            content="$decoded"
        fi
    fi
    
    echo "$content"
}

# 解析VMess节点
parse_vmess() {
    local vmess_url="$1"
    local config_b64="${vmess_url#vmess://}"
    
    # 添加Base64 padding
    local padding=$((4 - ${#config_b64} % 4))
    if [[ $padding -ne 4 ]]; then
        config_b64="${config_b64}$(printf '=%.0s' $(seq 1 $padding))"
    fi
    
    local config_json=$(echo "$config_b64" | base64 -d 2>/dev/null || echo "")
    if [[ -z "$config_json" ]]; then
        return 1
    fi
    
    log_debug "VMess配置: $config_json"
    
    # 使用多种方法解析JSON
    local server port uuid name net tls
    
    if command -v jq >/dev/null 2>&1; then
        # 使用jq解析
        server=$(echo "$config_json" | jq -r '.add // empty' 2>/dev/null)
        port=$(echo "$config_json" | jq -r '.port // empty' 2>/dev/null)
        uuid=$(echo "$config_json" | jq -r '.id // empty' 2>/dev/null)
        name=$(echo "$config_json" | jq -r '.ps // empty' 2>/dev/null)
        net=$(echo "$config_json" | jq -r '.net // "tcp"' 2>/dev/null)
        tls=$(echo "$config_json" | jq -r '.tls // "none"' 2>/dev/null)
    else
        # 使用grep解析
        server=$(echo "$config_json" | grep -o '"add"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
        port=$(echo "$config_json" | grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
        uuid=$(echo "$config_json" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
        name=$(echo "$config_json" | grep -o '"ps"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
        net=$(echo "$config_json" | grep -o '"net"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
        tls=$(echo "$config_json" | grep -o '"tls"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
        
        # 设置默认值
        [[ -z "$net" ]] && net="tcp"
        [[ -z "$tls" ]] && tls="none"
    fi
    
    if [[ -n "$server" && -n "$port" && -n "$uuid" ]]; then
        echo "vmess|$server|$port|$uuid|${name:-VMess}|$net|$tls"
    fi
}

# 解析VLESS节点
parse_vless() {
    local vless_url="$1"
    local config="${vless_url#vless://}"
    
    # 提取UUID
    local uuid="${config%%@*}"
    local rest="${config#*@}"
    
    # 提取服务器和端口
    local server_port="${rest%%\?*}"
    local server="${server_port%%:*}"
    local port="${server_port#*:}"
    
    # 提取查询参数
    local params="${rest#*\?}"
    local name=""
    if [[ "$vless_url" == *"#"* ]]; then
        name="${vless_url##*#}"
        # URL解码
        if command -v python3 >/dev/null 2>&1; then
            name=$(echo "$name" | python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))" 2>/dev/null || echo "$name")
        fi
    fi
    
    # 解析参数
    local net="tcp"
    local tls="none"
    local sni=""
    
    if [[ "$params" == *"type="* ]]; then
        net=$(echo "$params" | grep -o 'type=[^&]*' | cut -d'=' -f2)
    fi
    if [[ "$params" == *"security="* ]]; then
        tls=$(echo "$params" | grep -o 'security=[^&]*' | cut -d'=' -f2)
    fi
    if [[ "$params" == *"sni="* ]]; then
        sni=$(echo "$params" | grep -o 'sni=[^&]*' | cut -d'=' -f2)
    fi
    
    if [[ -n "$server" && -n "$port" && -n "$uuid" ]]; then
        echo "vless|$server|$port|$uuid|${name:-VLESS}|$net|$tls|$sni"
    fi
}

# 解析Trojan节点
parse_trojan() {
    local trojan_url="$1"
    local password="${trojan_url#trojan://}"
    password="${password%%@*}"
    
    local rest="${trojan_url#*@}"
    local server_port="${rest%%\?*}"
    local server="${server_port%%:*}"
    local port="${server_port#*:}"
    
    local name=""
    if [[ "$trojan_url" == *"#"* ]]; then
        name="${trojan_url##*#}"
        if command -v python3 >/dev/null 2>&1; then
            name=$(echo "$name" | python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))" 2>/dev/null || echo "$name")
        fi
    fi
    
    if [[ -n "$server" && -n "$port" && -n "$password" ]]; then
        echo "trojan|$server|$port|$password|${name:-Trojan}|tcp|tls"
    fi
}

# ==================== 代理测试 ====================
# 生成Xray配置
generate_xray_config() {
    local protocol="$1"
    local server="$2"
    local port="$3"
    local auth="$4"  # UUID或密码
    local net="${5:-tcp}"
    local tls="${6:-none}"
    local sni="$7"
    local config_file="$8"
    
    local outbound_config=""
    
    case "$protocol" in
        "vmess")
            outbound_config=$(cat << EOF
{
    "protocol": "vmess",
    "settings": {
        "vnext": [{
            "address": "$server",
            "port": $port,
            "users": [{
                "id": "$auth",
                "alterId": 0
            }]
        }]
    },
    "streamSettings": {
        "network": "$net"
EOF
            if [[ "$tls" != "none" ]]; then
                outbound_config+=",\"security\": \"$tls\""
                if [[ "$tls" == "tls" && -n "$sni" ]]; then
                    outbound_config+=",\"tlsSettings\": {\"serverName\": \"$sni\"}"
                fi
            fi
            outbound_config+="}"
            ;;
            
        "vless")
            outbound_config=$(cat << EOF
{
    "protocol": "vless",
    "settings": {
        "vnext": [{
            "address": "$server",
            "port": $port,
            "users": [{
                "id": "$auth",
                "encryption": "none"
            }]
        }]
    },
    "streamSettings": {
        "network": "$net"
EOF
            if [[ "$tls" != "none" ]]; then
                outbound_config+=",\"security\": \"$tls\""
                if [[ "$tls" == "tls" && -n "$sni" ]]; then
                    outbound_config+=",\"tlsSettings\": {\"serverName\": \"$sni\"}"
                fi
            fi
            outbound_config+="}"
            ;;
            
        "trojan")
            outbound_config=$(cat << EOF
{
    "protocol": "trojan",
    "settings": {
        "servers": [{
            "address": "$server",
            "port": $port,
            "password": "$auth"
        }]
    }
}
EOF
            ;;
    esac
    
    # 生成完整配置
    cat > "$config_file" << EOF
{
    "log": {"loglevel": "warning"},
    "inbounds": [{
        "port": $SOCKS_PORT,
        "protocol": "socks",
        "settings": {"udp": true}
    }],
    "outbounds": [$outbound_config}]
}
EOF
}

# 启动Xray代理
start_xray() {
    local config_file="$1"
    local log_file="$TEMP_DIR/xray.log"
    
    # 停止现有进程
    pkill -f "xray.*$config_file" 2>/dev/null || true
    sleep 1
    
    # 启动Xray
    xray -c "$config_file" > "$log_file" 2>&1 &
    local xray_pid=$!
    
    # 等待启动
    sleep 3
    
    # 检查是否启动成功
    if kill -0 "$xray_pid" 2>/dev/null; then
        log_debug "Xray启动成功 (PID: $xray_pid)"
        echo "$xray_pid"
        return 0
    else
        log_warning "Xray启动失败"
        [[ -f "$log_file" ]] && cat "$log_file"
        return 1
    fi
}

# 测试延迟
test_latency() {
    local test_urls=(
        "http://www.google.com/generate_204"
        "http://connectivitycheck.gstatic.com/generate_204"
        "https://www.cloudflare.com/cdn-cgi/trace"
        "http://www.baidu.com"
    )
    
    for url in "${test_urls[@]}"; do
        local start_time=$(date +%s%N)
        if curl -s --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
                --connect-timeout 5 --max-time $TEST_TIMEOUT \
                -o /dev/null "$url" 2>/dev/null; then
            local end_time=$(date +%s%N)
            local latency=$(( (end_time - start_time) / 1000000 ))
            echo "$latency"
            return 0
        fi
    done
    
    echo "-1"
    return 1
}

# 测试下载速度
test_download_speed() {
    local test_files=(
        "http://speedtest.tele2.net/100KB.zip"
        "https://proof.ovh.net/files/100Kb.dat"
        "http://ipv4.download.thinkbroadband.com/100KB.zip"
    )
    
    for test_file in "${test_files[@]}"; do
        local start_time=$(date +%s)
        local result=$(curl -s --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
                           --connect-timeout 5 --max-time 20 \
                           -w "%{size_download}" \
                           -o /dev/null "$test_file" 2>/dev/null)
        
        if [[ -n "$result" && "$result" -gt 0 ]]; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            if [[ "$duration" -gt 0 ]]; then
                local speed=$(echo "scale=2; ($result * 8) / ($duration * 1000000)" | bc 2>/dev/null || echo "0")
                echo "$speed"
                return 0
            fi
        fi
    done
    
    echo "-1"
    return 1
}

# 测试单个节点
test_node() {
    local node_info="$1"
    IFS='|' read -r protocol server port auth name net tls sni <<< "$node_info"
    
    log_info "测试节点: $name ($server:$port)"
    
    # 生成配置文件
    local config_file="$TEMP_DIR/config_$$.json"
    generate_xray_config "$protocol" "$server" "$port" "$auth" "$net" "$tls" "$sni" "$config_file"
    
    # 启动Xray
    local xray_pid=$(start_xray "$config_file")
    if [[ $? -ne 0 ]]; then
        echo "{\"name\":\"$name\",\"server\":\"$server\",\"port\":$port,\"protocol\":\"$protocol\",\"status\":\"failed\",\"error\":\"Xray启动失败\"}"
        return 1
    fi
    
    # 测试延迟
    local latency=$(test_latency)
    local speed="-1"
    local status="failed"
    local error=""
    
    if [[ "$latency" != "-1" ]]; then
        status="success"
        # 测试速度
        speed=$(test_download_speed)
        log_success "节点可用: $name - 延迟: ${latency}ms, 速度: ${speed}Mbps"
    else
        error="连接超时"
        log_warning "节点不可用: $name"
    fi
    
    # 停止Xray
    kill "$xray_pid" 2>/dev/null || true
    sleep 1
    
    # 返回JSON结果
    cat << EOF
{
    "name": "$name",
    "server": "$server",
    "port": $port,
    "protocol": "$protocol",
    "network": "$net",
    "security": "$tls",
    "latency": $latency,
    "speed": $speed,
    "status": "$status",
    "error": "$error",
    "timestamp": "$(date -Iseconds)"
}
EOF
}

# ==================== 主要功能 ====================
# 执行测试
run_test() {
    log_info "开始订阅测速测试"
    log_info "版本: $VERSION"
    
    # 检查依赖
    check_dependencies
    local dep_status=$?
    if [[ $dep_status -eq 1 ]]; then
        exit 1
    fi
    
    # 创建临时目录
    mkdir -p "$TEMP_DIR"
    
    # 检查订阅文件
    if [[ ! -f "$SUBSCRIPTION_FILE" ]]; then
        log_error "订阅文件不存在: $SUBSCRIPTION_FILE"
        exit 1
    fi
    
    # 初始化结果
    local results="[]"
    local total_nodes=0
    local success_nodes=0
    local tested_nodes=0
    
    # 处理订阅
    while IFS= read -r subscription_url && [[ $tested_nodes -lt $MAX_NODES ]]; do
        [[ -z "$subscription_url" ]] && continue
        [[ "$subscription_url" == \#* ]] && continue
        
        log_info "处理订阅: $(basename "$subscription_url")"
        
        # 获取订阅内容
        local content=$(fetch_subscription "$subscription_url")
        if [[ -z "$content" ]]; then
            continue
        fi
        
        # 解析节点
        while IFS= read -r line && [[ $tested_nodes -lt $MAX_NODES ]]; do
            [[ -z "$line" ]] && continue
            
            total_nodes=$((total_nodes + 1))
            
            local node_info=""
            if [[ "$line" == vmess://* ]]; then
                node_info=$(parse_vmess "$line")
            elif [[ "$line" == vless://* ]]; then
                node_info=$(parse_vless "$line")
            elif [[ "$line" == trojan://* ]]; then
                node_info=$(parse_trojan "$line")
            fi
            
            if [[ -n "$node_info" ]]; then
                tested_nodes=$((tested_nodes + 1))
                
                # 测试节点
                local test_result=$(test_node "$node_info")
                
                # 检查是否成功
                if echo "$test_result" | grep -q '"status":"success"'; then
                    success_nodes=$((success_nodes + 1))
                fi
                
                # 添加到结果
                if command -v jq >/dev/null 2>&1; then
                    results=$(echo "$results" | jq ". += [$test_result]")
                else
                    # 简单的JSON数组构建
                    if [[ "$results" == "[]" ]]; then
                        results="[$test_result]"
                    else
                        results="${results%]}, $test_result]"
                    fi
                fi
            fi
            
        done <<< "$content"
        
    done < "$SUBSCRIPTION_FILE"
    
    # 保存结果
    echo "$results" > "$RESULTS_FILE"
    
    # 显示摘要
    echo -e "\n${YELLOW}=== 测试摘要 ===${NC}"
    echo "发现节点: $total_nodes"
    echo "测试节点: $tested_nodes"
    echo "成功节点: $success_nodes"
    if [[ $tested_nodes -gt 0 ]]; then
        echo "成功率: $(( success_nodes * 100 / tested_nodes ))%"
    fi
    echo "结果文件: $RESULTS_FILE"
    
    # 显示最佳节点
    if [[ $success_nodes -gt 0 ]]; then
        echo -e "\n${GREEN}=== 最佳节点 (按延迟排序) ===${NC}"
        if command -v jq >/dev/null 2>&1; then
            echo "$results" | jq -r '.[] | select(.status == "success") | "\(.latency)ms \(.speed)Mbps \(.name)"' | sort -n | head -5 | nl -w2 -s'. '
        else
            grep '"status":"success"' "$RESULTS_FILE" | head -5 | nl -w2 -s'. '
        fi
    fi
    
    log_success "测试完成!"
}

# 显示结果
show_results() {
    local count=${1:-10}
    
    if [[ ! -f "$RESULTS_FILE" ]]; then
        log_error "结果文件不存在: $RESULTS_FILE"
        return 1
    fi
    
    echo -e "${YELLOW}=== 最近测试结果 ===${NC}"
    
    if command -v jq >/dev/null 2>&1; then
        local results=$(cat "$RESULTS_FILE")
        local total=$(echo "$results" | jq 'length')
        local success=$(echo "$results" | jq '[.[] | select(.status == "success")] | length')
        
        echo "总节点: $total, 成功: $success"
        echo -e "\n${GREEN}=== 可用节点 ===${NC}"
        echo "$results" | jq -r '.[] | select(.status == "success") | "\(.latency)ms \(.speed)Mbps \(.name) (\(.server):\(.port))"' | sort -n | head -$count | nl -w2 -s'. '
        
        echo -e "\n${RED}=== 失败节点 ===${NC}"
        echo "$results" | jq -r '.[] | select(.status == "failed") | "\(.name) (\(.server):\(.port)) - \(.error)"' | head -5
    else
        cat "$RESULTS_FILE"
    fi
}

# 守护进程模式
daemon_mode() {
    log_info "启动守护进程模式，间隔: ${INTERVAL}s"
    
    # 保存PID
    echo $$ > "$PID_FILE"
    
    # 信号处理
    trap 'log_info "收到停止信号"; rm -f "$PID_FILE"; exit 0' TERM INT
    
    while true; do
        run_test
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
            log_success "守护进程已停止 (PID: $pid)"
            rm -f "$PID_FILE"
        else
            log_warning "守护进程未运行"
            rm -f "$PID_FILE"
        fi
    else
        log_warning "未找到PID文件"
    fi
}

# 检查状态
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

# 显示帮助
show_help() {
    cat << EOF
${BLUE}SubCheck v$VERSION - 订阅测速工具${NC}

${YELLOW}用法:${NC}
  $0 [命令] [选项]

${YELLOW}命令:${NC}
  test          执行一次测试
  start         启动守护进程
  stop          停止守护进程
  status        检查守护进程状态
  results [N]   显示最近N个结果 (默认10)
  help          显示此帮助信息

${YELLOW}选项:${NC}
  -n, --max-nodes NUM     最大测试节点数 (默认: $DEFAULT_MAX_NODES)
  -t, --timeout SEC       测试超时时间 (默认: $DEFAULT_TEST_TIMEOUT)
  -p, --port PORT         SOCKS代理端口 (默认: $DEFAULT_SOCKS_PORT)
  -i, --interval SEC      守护进程间隔 (默认: $DEFAULT_INTERVAL)
  -d, --debug             启用调试模式
  -v, --version           显示版本信息

${YELLOW}示例:${NC}
  $0 test                 # 执行一次测试
  $0 test -n 50           # 测试最多50个节点
  $0 start -i 1800        # 启动守护进程，30分钟间隔
  $0 results 20           # 显示最近20个结果
  $0 stop                 # 停止守护进程

${YELLOW}文件:${NC}
  $SUBSCRIPTION_FILE    # 订阅链接文件
  $RESULTS_FILE         # 测试结果文件
  $CONFIG_FILE          # 配置文件

${YELLOW}配置文件格式:${NC}
  max_nodes: 20
  test_timeout: 10
  socks_port: 10808
  interval: 3600
EOF
}

# ==================== 主程序入口 ====================
main() {
    local command="$1"
    shift
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--max-nodes)
                MAX_NODES="$2"
                shift 2
                ;;
            -t|--timeout)
                TEST_TIMEOUT="$2"
                shift 2
                ;;
            -p|--port)
                SOCKS_PORT="$2"
                shift 2
                ;;
            -i|--interval)
                INTERVAL="$2"
                shift 2
                ;;
            -d|--debug)
                DEBUG=1
                shift
                ;;
            -v|--version)
                echo "SubCheck v$VERSION"
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done
    
    # 加载配置
    load_config
    
    # 执行命令
    case "$command" in
        "test")
            run_test
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
            show_results "$1"
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