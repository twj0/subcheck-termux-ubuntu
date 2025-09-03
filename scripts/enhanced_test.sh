#!/bin/bash

# 增强版节点测试脚本
# 支持多协议测试和详细性能分析

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NODES_FILE="$PROJECT_DIR/parsed_nodes.json"
RESULTS_FILE="$PROJECT_DIR/test_results.json"
XRAY_CONFIG="/tmp/xray_config.json"
XRAY_LOG="/tmp/xray.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置参数
SOCKS_PORT=10808
TEST_TIMEOUT=10
SPEED_TEST_SIZE=1048576  # 1MB
MAX_CONCURRENT=3

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

# 主函数
main() {
    log_info "开始节点测试"
    
    if [[ ! -f "$NODES_FILE" ]]; then
        log_error "节点文件不存在: $NODES_FILE"
        log_info "请先运行解析脚本: bash scripts/enhanced_parse.sh"
        exit 1
    fi
    
    # 检查依赖
    for cmd in jq bc xray; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "缺少依赖: $cmd"
            exit 1
        fi
    done
    
    local nodes=$(cat "$NODES_FILE")
    local node_count=$(echo "$nodes" | jq 'length')
    
    if [[ "$node_count" -eq 0 ]]; then
        log_error "没有找到可测试的节点"
        exit 1
    fi
    
    log_info "找到 $node_count 个节点，开始测试..."
    
    local results="[]"
    local success_count=0
    
    # 逐个测试节点
    for i in $(seq 0 $((node_count - 1))); do
        local node=$(echo "$nodes" | jq ".[$i]")
        local result=$(test_node "$node")
        
        if echo "$result" | jq -e '.status == "success"' >/dev/null; then
            success_count=$((success_count + 1))
        fi
        
        results=$(echo "$results" | jq ". += [$result]")
        
        # 进度显示
        echo -e "${BLUE}进度: $((i + 1))/$node_count${NC}"
    done
    
    # 保存结果
    echo "$results" | jq '.' > "$RESULTS_FILE"
    
    # 显示摘要
    echo -e "\n${YELLOW}=== 测试摘要 ===${NC}"
    echo "总节点数: $node_count"
    echo "成功节点: $success_count"
    echo "失败节点: $((node_count - success_count))"
    echo "结果保存到: $RESULTS_FILE"
    
    # 显示最佳节点
    if [[ "$success_count" -gt 0 ]]; then
        echo -e "\n${GREEN}=== 最佳节点 (按延迟排序) ===${NC}"
        echo "$results" | jq -r '.[] | select(.status == "success") | "\(.latency)ms - \(.speed)Mbps - \(.name)"' | sort -n | head -5
    fi
}

# 执行主函数
main "$@"