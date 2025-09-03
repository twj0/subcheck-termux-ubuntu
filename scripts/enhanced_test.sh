#!/bin/bash

# 增强版节点测试脚本 - 中国大陆网络优化版
# 集成Python网络测试器，支持并发测试和智能代理管理

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NODES_FILE="$PROJECT_DIR/parsed_nodes.json"
RESULTS_FILE="$PROJECT_DIR/results/test_results.json"
LOGS_DIR="$PROJECT_DIR/logs"
RESULTS_DIR="$PROJECT_DIR/results"

# 创建必要目录
mkdir -p "$LOGS_DIR" "$RESULTS_DIR"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置参数
MAX_TEST_NODES=50
MAX_CONCURRENT=3
TEST_TIMEOUT=30
PYTHON_TESTER="$PROJECT_DIR/src/network_tester.py"

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

# 生成Xray配置
generate_xray_config() {
    local node_json="$1"
    local protocol=$(echo "$node_json" | jq -r '.protocol')
    
    case "$protocol" in
        "vless")
            generate_vless_config "$node_json"
            ;;
        "vmess")
            generate_vmess_config "$node_json"
            ;;
        "trojan")
            generate_trojan_config "$node_json"
            ;;
        *)
            log_error "不支持的协议: $protocol"
            return 1
            ;;
    esac
}

# 生成VLESS配置
generate_vless_config() {
    local node="$1"
    local server=$(echo "$node" | jq -r '.server')
    local port=$(echo "$node" | jq -r '.port')
    local uuid=$(echo "$node" | jq -r '.uuid')
    local security=$(echo "$node" | jq -r '.security // "none"')
    local sni=$(echo "$node" | jq -r '.sni // ""')
    local network=$(echo "$node" | jq -r '.network // "tcp"')
    
    cat > "$XRAY_CONFIG" << EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": $SOCKS_PORT,
            "protocol": "socks",
            "settings": {
                "udp": true
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": "$server",
                        "port": $port,
                        "users": [
                            {
                                "id": "$uuid",
                                "encryption": "none"
                            }
                        ]
                    }
                ]
            },
            "streamSettings": {
                "network": "$network",
                "security": "$security"
                $(if [[ "$security" == "tls" && -n "$sni" ]]; then
                    echo ",\"tlsSettings\": {\"serverName\": \"$sni\"}"
                fi)
            }
        }
    ]
}
EOF
}

# 生成VMess配置
generate_vmess_config() {
    local node="$1"
    local server=$(echo "$node" | jq -r '.server')
    local port=$(echo "$node" | jq -r '.port')
    local uuid=$(echo "$node" | jq -r '.uuid')
    local alterId=$(echo "$node" | jq -r '.alterId // 0')
    local security=$(echo "$node" | jq -r '.security // "auto"')
    local network=$(echo "$node" | jq -r '.network // "tcp"')
    
    cat > "$XRAY_CONFIG" << EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": $SOCKS_PORT,
            "protocol": "socks",
            "settings": {
                "udp": true
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "vmess",
            "settings": {
                "vnext": [
                    {
                        "address": "$server",
                        "port": $port,
                        "users": [
                            {
                                "id": "$uuid",
                                "alterId": $alterId,
                                "security": "$security"
                            }
                        ]
                    }
                ]
            },
            "streamSettings": {
                "network": "$network"
            }
        }
    ]
}
EOF
}

# 生成Trojan配置
generate_trojan_config() {
    local node="$1"
    local server=$(echo "$node" | jq -r '.server')
    local port=$(echo "$node" | jq -r '.port')
    local password=$(echo "$node" | jq -r '.password')
    
    cat > "$XRAY_CONFIG" << EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": $SOCKS_PORT,
            "protocol": "socks",
            "settings": {
                "udp": true
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "trojan",
            "settings": {
                "servers": [
                    {
                        "address": "$server",
                        "port": $port,
                        "password": "$password"
                    }
                ]
            }
        }
    ]
}
EOF
}

# 启动Xray
start_xray() {
    log_info "启动Xray代理服务"
    
    # 检查Xray是否已安装
    if ! command -v xray >/dev/null 2>&1; then
        log_error "Xray未安装，请先安装Xray"
        return 1
    fi
    
    # 停止现有进程
    pkill -f "xray.*$XRAY_CONFIG" 2>/dev/null
    sleep 1
    
    # 启动Xray
    xray -c "$XRAY_CONFIG" > "$XRAY_LOG" 2>&1 &
    local xray_pid=$!
    
    # 等待启动
    sleep 2
    
    # 检查是否启动成功
    if kill -0 "$xray_pid" 2>/dev/null; then
        log_success "Xray启动成功 (PID: $xray_pid)"
        echo "$xray_pid"
        return 0
    else
        log_error "Xray启动失败"
        cat "$XRAY_LOG"
        return 1
    fi
}

# 停止Xray
stop_xray() {
    local pid="$1"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        sleep 1
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid"
        fi
        log_info "Xray进程已停止"
    fi
}

# 测试连通性
test_connectivity() {
    local proxy_url="socks5://127.0.0.1:$SOCKS_PORT"
    local test_urls=(
        "http://www.google.com/generate_204"
        "http://connectivitycheck.gstatic.com/generate_204"
        "https://www.cloudflare.com/cdn-cgi/trace"
    )
    
    for url in "${test_urls[@]}"; do
        log_info "测试连通性: $url"
        
        local result=$(curl -s --proxy "$proxy_url" \
                           --connect-timeout 5 \
                           --max-time 10 \
                           -w "time_total:%{time_total}\nhttp_code:%{http_code}\n" \
                           -o /dev/null "$url" 2>&1)
        
        if echo "$result" | grep -q "http_code:20[0-9]"; then
            local time_total=$(echo "$result" | grep "time_total:" | cut -d':' -f2)
            local latency_ms=$(echo "scale=2; $time_total * 1000" | bc)
            log_success "连通性测试成功，延迟: ${latency_ms}ms"
            echo "$latency_ms"
            return 0
        fi
    done
    
    log_error "连通性测试失败"
    return 1
}

# 测试下载速度
test_download_speed() {
    local proxy_url="socks5://127.0.0.1:$SOCKS_PORT"
    local test_files=(
        "http://speedtest.tele2.net/1MB.zip"
        "https://proof.ovh.net/files/1Mb.dat"
        "http://ipv4.download.thinkbroadband.com/1MB.zip"
    )
    
    for test_file in "${test_files[@]}"; do
        log_info "测试下载速度: $test_file"
        
        local start_time=$(date +%s.%N)
        local result=$(curl -s --proxy "$proxy_url" \
                           --connect-timeout 5 \
                           --max-time 30 \
                           -w "size_download:%{size_download}\ntime_total:%{time_total}\n" \
                           -o /dev/null "$test_file" 2>&1)
        
        if echo "$result" | grep -q "size_download:" && echo "$result" | grep -q "time_total:"; then
            local size_download=$(echo "$result" | grep "size_download:" | cut -d':' -f2)
            local time_total=$(echo "$result" | grep "time_total:" | cut -d':' -f2)
            
            if (( $(echo "$size_download > 0" | bc -l) )) && (( $(echo "$time_total > 0" | bc -l) )); then
                local speed_mbps=$(echo "scale=2; ($size_download * 8) / ($time_total * 1000000)" | bc)
                log_success "下载速度: ${speed_mbps} Mbps"
                echo "$speed_mbps"
                return 0
            fi
        fi
    done
    
    log_warning "下载速度测试失败"
    echo "0"
    return 1
}

# 测试单个节点
test_node() {
    local node_json="$1"
    local node_name=$(echo "$node_json" | jq -r '.name')
    local server=$(echo "$node_json" | jq -r '.server')
    local port=$(echo "$node_json" | jq -r '.port')
    local protocol=$(echo "$node_json" | jq -r '.protocol')
    
    echo -e "\n${YELLOW}=== 测试节点: $node_name ===${NC}"
    echo -e "${BLUE}服务器: $server:$port ($protocol)${NC}"
    
    # 生成配置
    if ! generate_xray_config "$node_json"; then
        return 1
    fi
    
    # 启动代理
    local xray_pid=$(start_xray)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # 测试结果
    local test_result='{
        "name": "'"$node_name"'",
        "server": "'"$server"'",
        "port": '"$port"',
        "protocol": "'"$protocol"'",
        "timestamp": "'"$(date -Iseconds)"'",
        "status": "failed",
        "latency": null,
        "speed": null,
        "error": null
    }'
    
    # 连通性测试
    local latency=$(test_connectivity)
    if [[ $? -eq 0 ]]; then
        # 速度测试
        local speed=$(test_download_speed)
        
        test_result=$(echo "$test_result" | jq \
            --arg latency "$latency" \
            --arg speed "$speed" \
            '.status = "success" | .latency = ($latency | tonumber) | .speed = ($speed | tonumber)')
        
        log_success "节点测试完成 - 延迟: ${latency}ms, 速度: ${speed}Mbps"
    else
        test_result=$(echo "$test_result" | jq '.error = "连接失败"')
        log_error "节点测试失败"
    fi
    
    # 停止代理
    stop_xray "$xray_pid"
    
    echo "$test_result"
}

# 检查环境和依赖
check_environment() {
    log_info "检查测试环境"
    
    # 检查节点文件
    if [[ ! -f "$NODES_FILE" ]]; then
        log_error "节点文件不存在: $NODES_FILE"
        log_info "请先运行解析脚本: bash scripts/enhanced_parse.sh"
        exit 1
    fi
    
    # 检查Python测试器
    if [[ ! -f "$PYTHON_TESTER" ]]; then
        log_error "Python测试器不存在: $PYTHON_TESTER"
        exit 1
    fi
    
    # 检查Xray
    if ! command -v xray >/dev/null 2>&1; then
        log_warning "Xray未安装，尝试安装..."
        if ! install_xray; then
            log_error "Xray安装失败，请手动安装"
            exit 1
        fi
    fi
    
    # 检查Python依赖
    local python_cmd="python3"
    if command -v uv >/dev/null 2>&1; then
        python_cmd="uv run python"
    fi
    
    if ! $python_cmd -c "import aiohttp, json, asyncio" 2>/dev/null; then
        log_warning "Python依赖缺失，尝试安装..."
        install_python_deps
    fi
    
    log_success "环境检查完成"
}

# 安装Xray
install_xray() {
    log_info "安装Xray..."
    
    # 检查系统架构
    local arch=$(uname -m)
    case $arch in
        x86_64) arch="64" ;;
        aarch64|arm64) arch="arm64-v8a" ;;
        armv7l) arch="arm32-v7a" ;;
        *) log_error "不支持的架构: $arch"; return 1 ;;
    esac
    
    # 下载Xray
    local xray_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${arch}.zip"
    local temp_dir=$(mktemp -d)
    
    if curl -L "$xray_url" -o "$temp_dir/xray.zip" && 
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
    
    if command -v uv >/dev/null 2>&1; then
        uv sync
    elif command -v pip3 >/dev/null 2>&1; then
        pip3 install -r requirements.txt
    else
        log_error "无法找到Python包管理器"
        return 1
    fi
}

# 使用Python测试器进行测试
run_python_tester() {
    local max_nodes="${1:-$MAX_TEST_NODES}"
    
    log_info "使用Python网络测试器进行测试"
    log_info "最大测试节点数: $max_nodes"
    
    cd "$PROJECT_DIR"
    
    local python_cmd="python3"
    if command -v uv >/dev/null 2>&1; then
        python_cmd="uv run python"
    fi
    
    # 运行Python测试器
    if $python_cmd "$PYTHON_TESTER" "$NODES_FILE" "$RESULTS_FILE" "$max_nodes"; then
        log_success "Python测试器执行成功"
        return 0
    else
        log_error "Python测试器执行失败"
        return 1
    fi
}

# 生成测试报告
generate_report() {
    if [[ ! -f "$RESULTS_FILE" ]]; then
        log_error "测试结果文件不存在"
        return 1
    fi
    
    local report_file="$RESULTS_DIR/test_report_$(date +%Y%m%d_%H%M%S).md"
    
    log_info "生成测试报告: $report_file"
    
    # 统计数据
    local total_nodes=$(jq 'length' "$RESULTS_FILE")
    local success_nodes=$(jq '[.[] | select(.status == "success")] | length' "$RESULTS_FILE")
    local failed_nodes=$((total_nodes - success_nodes))
    
    # 生成Markdown报告
    cat > "$report_file" << EOF
# SubCheck 网络测试报告

**测试时间**: $(date '+%Y-%m-%d %H:%M:%S')
**测试节点总数**: $total_nodes
**成功节点数**: $success_nodes
**失败节点数**: $failed_nodes
**成功率**: $(echo "scale=2; $success_nodes * 100 / $total_nodes" | bc -l)%

## 最佳节点 (Top 10)

| 排名 | 节点名称 | 服务器 | 延迟(ms) | 速度(Mbps) | 协议 |
|------|----------|--------|----------|------------|------|
EOF
    
    # 添加最佳节点
    jq -r '.[] | select(.status == "success") | [.name, .server, .tcp_latency, .download_speed, .type] | @tsv' "$RESULTS_FILE" | 
    sort -k3 -n | head -10 | 
    awk 'BEGIN{OFS="|"} {printf "| %d | %s | %s | %s | %s | %s |\n", NR, $1, $2, $3, $4, $5}' >> "$report_file"
    
    cat >> "$report_file" << EOF

## 失败节点统计

EOF
    
    # 添加失败原因统计
    jq -r '.[] | select(.status == "failed") | .error // "未知错误"' "$RESULTS_FILE" | 
    sort | uniq -c | sort -nr | 
    awk '{printf "- %s: %d个节点\n", substr($0, index($0,$2)), $1}' >> "$report_file"
    
    log_success "测试报告已生成: $report_file"
}

# 主函数
main() {
    local max_nodes="${1:-$MAX_TEST_NODES}"
    
    echo -e "${BLUE}=== SubCheck 增强版网络测试 ===${NC}"
    echo -e "${BLUE}中国大陆网络环境优化版${NC}"
    echo ""
    
    # 环境检查
    check_environment
    
    # 显示节点信息
    local node_count=$(jq 'length' "$NODES_FILE")
    log_info "发现 $node_count 个解析节点"
    
    if [[ $node_count -eq 0 ]]; then
        log_error "没有可测试的节点"
        exit 1
    fi
    
    # 运行测试
    if run_python_tester "$max_nodes"; then
        # 生成报告
        generate_report
        
        # 显示简要结果
        echo -e "\n${YELLOW}=== 测试完成 ===${NC}"
        
        local success_count=$(jq '[.[] | select(.status == "success")] | length' "$RESULTS_FILE")
        local total_count=$(jq 'length' "$RESULTS_FILE")
        
        echo "测试节点: $total_count"
        echo "成功节点: $success_count"
        echo "成功率: $(echo "scale=1; $success_count * 100 / $total_count" | bc -l)%"
        
        if [[ $success_count -gt 0 ]]; then
            echo -e "\n${GREEN}=== 最佳节点 (前5名) ===${NC}"
            jq -r '.[] | select(.status == "success") | "\(.http_latency // .tcp_latency)ms - \(.download_speed // 0)Mbps - \(.name)"' "$RESULTS_FILE" | 
            sort -n | head -5 | nl
        fi
        
        echo -e "\n详细结果: $RESULTS_FILE"
    else
        log_error "测试失败"
        exit 1
    fi
}

# 执行主函数
main "$@"