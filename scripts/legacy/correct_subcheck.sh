#!/bin/bash

# SubCheck 正确实现版本
# 完整的订阅解析 -> Xray代理 -> 网络测试流程

set -e

# 配置参数
SOCKS_PORT=10808
TEMP_DIR="/tmp/subcheck_$$"
RESULTS_FILE="test_results.txt"
MAX_NODES=10
TEST_TIMEOUT=10

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] [INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] [SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] [ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] [WARNING]${NC} $1"
}

# 清理函数
cleanup() {
    # 停止所有xray进程
    pkill -f "xray.*$TEMP_DIR" 2>/dev/null || true
    # 清理临时文件
    rm -rf "$TEMP_DIR"
}

# 设置清理陷阱
trap cleanup EXIT

# 创建临时目录
setup_temp_dir() {
    mkdir -p "$TEMP_DIR"
}

# 获取订阅内容并解码
fetch_and_decode_subscription() {
    local url="$1"
    log_info "获取订阅: $url"
    
    local content=""
    if [[ "$url" == http* ]]; then
        content=$(curl -s --connect-timeout 10 --max-time 30 "$url" 2>/dev/null || echo "")
    else
        content=$(cat "$url" 2>/dev/null || echo "")
    fi
    
    if [[ -z "$content" ]]; then
        log_error "无法获取订阅内容: $url"
        return 1
    fi
    
    # 检查是否需要Base64解码
    if [[ "$content" != *"vmess://"* && "$content" != *"vless://"* && "$content" != *"trojan://"* ]]; then
        log_info "检测到Base64编码，正在解码..."
        content=$(echo "$content" | base64 -d 2>/dev/null || echo "$content")
    fi
    
    echo "$content"
}

# 解析VMess节点
parse_vmess() {
    local vmess_url="$1"
    local config_b64="${vmess_url#vmess://}"
    
    # Base64解码
    local config_json=$(echo "$config_b64" | base64 -d 2>/dev/null || echo "")
    if [[ -z "$config_json" ]]; then
        return 1
    fi
    
    # 使用jq解析JSON
    if command -v jq >/dev/null 2>&1; then
        local server=$(echo "$config_json" | jq -r '.add // empty')
        local port=$(echo "$config_json" | jq -r '.port // empty')
        local uuid=$(echo "$config_json" | jq -r '.id // empty')
        local name=$(echo "$config_json" | jq -r '.ps // empty')
        local net=$(echo "$config_json" | jq -r '.net // "tcp"')
        local tls=$(echo "$config_json" | jq -r '.tls // "none"')
        
        if [[ -n "$server" && -n "$port" && -n "$uuid" ]]; then
            echo "$name|$server|$port|vmess|$uuid|$net|$tls"
        fi
    else
        # 简单的grep解析（备选方案）
        local server=$(echo "$config_json" | grep -o '"add"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
        local port=$(echo "$config_json" | grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
        local uuid=$(echo "$config_json" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
        local name=$(echo "$config_json" | grep -o '"ps"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
        
        if [[ -n "$server" && -n "$port" && -n "$uuid" ]]; then
            echo "$name|$server|$port|vmess|$uuid|tcp|none"
        fi
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
    
    # 提取参数
    local params="${rest#*\?}"
    local name=""
    if [[ "$vless_url" == *"#"* ]]; then
        name="${vless_url##*#}"
        # URL解码
        name=$(echo "$name" | python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))" 2>/dev/null || echo "$name")
    fi
    
    # 提取网络类型和安全设置
    local net="tcp"
    local tls="none"
    if [[ "$params" == *"type="* ]]; then
        net=$(echo "$params" | grep -o 'type=[^&]*' | cut -d'=' -f2)
    fi
    if [[ "$params" == *"security="* ]]; then
        tls=$(echo "$params" | grep -o 'security=[^&]*' | cut -d'=' -f2)
    fi
    
    if [[ -n "$server" && -n "$port" && -n "$uuid" ]]; then
        echo "${name:-VLESS}|$server|$port|vless|$uuid|$net|$tls"
    fi
}

# 生成Xray配置文件
generate_xray_config() {
    local server="$1"
    local port="$2"
    local protocol="$3"
    local uuid="$4"
    local net="${5:-tcp}"
    local tls="${6:-none}"
    local config_file="$7"
    
    local outbound_config=""
    
    if [[ "$protocol" == "vmess" ]]; then
        outbound_config=$(cat << EOF
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
                        "alterId": 0
                    }
                ]
            }
        ]
    },
    "streamSettings": {
        "network": "$net"
EOF
        if [[ "$tls" != "none" ]]; then
            outbound_config+=",\"security\": \"$tls\""
            if [[ "$tls" == "tls" ]]; then
                outbound_config+=",\"tlsSettings\": {\"serverName\": \"$server\"}"
            fi
        fi
        outbound_config+="}"
    elif [[ "$protocol" == "vless" ]]; then
        outbound_config=$(cat << EOF
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
        "network": "$net"
EOF
        if [[ "$tls" != "none" ]]; then
            outbound_config+=",\"security\": \"$tls\""
            if [[ "$tls" == "tls" ]]; then
                outbound_config+=",\"tlsSettings\": {\"serverName\": \"$server\"}"
            fi
        fi
        outbound_config+="}"
    fi
    
    # 生成完整配置
    cat > "$config_file" << EOF
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
        $outbound_config
        }
    ]
}
EOF
}

# 测试节点连通性和速度
test_node() {
    local name="$1"
    local server="$2"
    local port="$3"
    local protocol="$4"
    local uuid="$5"
    local net="$6"
    local tls="$7"
    
    log_info "测试节点: $name ($server:$port)"
    
    # 生成配置文件
    local config_file="$TEMP_DIR/config_$$.json"
    generate_xray_config "$server" "$port" "$protocol" "$uuid" "$net" "$tls" "$config_file"
    
    # 检查xray是否可用
    if ! command -v xray >/dev/null 2>&1; then
        log_warning "Xray未安装，跳过测试"
        echo "-1|-1|失败"
        return
    fi
    
    # 启动xray
    local log_file="$TEMP_DIR/xray_$$.log"
    xray -c "$config_file" > "$log_file" 2>&1 &
    local xray_pid=$!
    
    # 等待启动
    sleep 3
    
    # 检查xray是否启动成功
    if ! kill -0 "$xray_pid" 2>/dev/null; then
        log_warning "Xray启动失败"
        echo "-1|-1|失败"
        return
    fi
    
    # 测试延迟
    local latency=$(test_latency)
    local speed=$(test_speed)
    
    # 停止xray
    kill "$xray_pid" 2>/dev/null || true
    sleep 1
    
    # 清理文件
    rm -f "$config_file" "$log_file"
    
    local status="失败"
    if [[ "$latency" != "-1" ]]; then
        status="成功"
    fi
    
    echo "$latency|$speed|$status"
}

# 测试延迟
test_latency() {
    local test_urls=(
        "http://www.google.com/generate_204"
        "http://connectivitycheck.gstatic.com/generate_204"
        "https://www.cloudflare.com/cdn-cgi/trace"
    )
    
    for url in "${test_urls[@]}"; do
        local start_time=$(date +%s%N)
        if curl -s --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
                --connect-timeout 5 --max-time $TEST_TIMEOUT \
                -o /dev/null "$url" 2>/dev/null; then
            local end_time=$(date +%s%N)
            local latency=$(( (end_time - start_time) / 1000000 ))
            echo "$latency"
            return
        fi
    done
    
    echo "-1"
}

# 测试速度
test_speed() {
    local test_files=(
        "http://speedtest.tele2.net/100KB.zip"
        "https://proof.ovh.net/files/100Kb.dat"
    )
    
    for test_file in "${test_files[@]}"; do
        local start_time=$(date +%s)
        local result=$(curl -s --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
                           --connect-timeout 5 --max-time 15 \
                           -w "%{size_download}" \
                           -o /dev/null "$test_file" 2>/dev/null)
        
        if [[ -n "$result" && "$result" -gt 0 ]]; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            if [[ "$duration" -gt 0 ]]; then
                local speed=$(echo "scale=2; ($result * 8) / ($duration * 1000000)" | bc)
                echo "$speed"
                return
            fi
        fi
    done
    
    echo "-1"
}

# 主函数
main() {
    echo -e "${BLUE}=== SubCheck 正确实现版本 ===${NC}"
    log_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    setup_temp_dir
    
    if [[ ! -f "subscription.txt" ]]; then
        log_error "订阅文件不存在: subscription.txt"
        exit 1
    fi
    
    # 初始化结果文件
    echo "# SubCheck 测试结果 - $(date '+%Y-%m-%d %H:%M:%S')" > "$RESULTS_FILE"
    echo "# 格式: 节点名称|服务器|端口|协议|延迟(ms)|速度(Mbps)|状态" >> "$RESULTS_FILE"
    
    local total_nodes=0
    local success_nodes=0
    local tested_nodes=0
    
    # 读取订阅文件
    while IFS= read -r subscription_url && [[ $tested_nodes -lt $MAX_NODES ]]; do
        [[ -z "$subscription_url" ]] && continue
        [[ "$subscription_url" == \#* ]] && continue
        
        # 获取并解码订阅内容
        local content=$(fetch_and_decode_subscription "$subscription_url")
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
            fi
            
            if [[ -n "$node_info" ]]; then
                tested_nodes=$((tested_nodes + 1))
                
                # 解析节点信息
                IFS='|' read -r name server port protocol uuid net tls <<< "$node_info"
                
                # 测试节点
                local test_result=$(test_node "$name" "$server" "$port" "$protocol" "$uuid" "$net" "$tls")
                IFS='|' read -r latency speed status <<< "$test_result"
                
                if [[ "$status" == "成功" ]]; then
                    success_nodes=$((success_nodes + 1))
                    log_success "节点可用: $name - 延迟: ${latency}ms, 速度: ${speed}Mbps"
                else
                    log_warning "节点不可用: $name"
                fi
                
                # 记录结果
                echo "$name|$server|$port|$protocol|$latency|$speed|$status" >> "$RESULTS_FILE"
            fi
            
        done <<< "$content"
        
    done < "subscription.txt"
    
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
        echo -e "\n${GREEN}=== 可用节点 (按延迟排序) ===${NC}"
        grep "|成功$" "$RESULTS_FILE" | sort -t'|' -k5 -n | head -5 | while IFS='|' read -r name server port protocol latency speed status; do
            echo "  $name ($server:$port) - 延迟: ${latency}ms, 速度: ${speed}Mbps"
        done
    fi
    
    log_success "测试完成!"
}

# 执行主函数
main "$@"