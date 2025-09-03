#!/bin/bash

# SubCheck - 优化精简版订阅测速工具
# 去除冗余逻辑，保留核心功能

set -e

# 核心配置
MAX_NODES=15
TEST_TIMEOUT=8
SOCKS_PORT=10808
RESULTS_FILE="test_results.json"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 清理函数
cleanup() {
    pkill -f "xray.*subcheck" 2>/dev/null || true
    rm -f /tmp/xray_subcheck_*.json /tmp/xray_subcheck.log 2>/dev/null || true
}
trap cleanup EXIT

# 获取订阅内容
get_subscription() {
    local url="$1"
    local content=""
    
    if [[ "$url" == http* ]]; then
        content=$(curl -s --connect-timeout 10 --max-time 30 "$url" 2>/dev/null || echo "")
    else
        content=$(cat "$url" 2>/dev/null || echo "")
    fi
    
    # Base64解码检测
    if [[ -n "$content" && "$content" != *"://"* ]]; then
        content=$(echo "$content" | base64 -d 2>/dev/null || echo "$content")
    fi
    
    echo "$content"
}

# 解析节点（统一处理）
parse_node() {
    local line="$1"
    
    if [[ "$line" == vmess://* ]]; then
        local config="${line#vmess://}"
        local decoded=$(echo "$config" | base64 -d 2>/dev/null || echo "")
        
        if [[ -n "$decoded" ]]; then
            local server=$(echo "$decoded" | grep -o '"add"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
            local port=$(echo "$decoded" | grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
            local uuid=$(echo "$decoded" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
            local name=$(echo "$decoded" | grep -o '"ps"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
            
            [[ -n "$server" && -n "$port" && -n "$uuid" ]] && echo "vmess|$server|$port|$uuid|${name:-VMess}"
        fi
        
    elif [[ "$line" == vless://* ]]; then
        local config="${line#vless://}"
        local uuid="${config%%@*}"
        local rest="${config#*@}"
        local server_port="${rest%%\?*}"
        local server="${server_port%%:*}"
        local port="${server_port#*:}"
        local name=""
        
        if [[ "$line" == *"#"* ]]; then
            name="${line##*#}"
            name=$(python3 -c "import urllib.parse; print(urllib.parse.unquote('$name'))" 2>/dev/null || echo "$name")
        fi
        
        [[ -n "$server" && -n "$port" && -n "$uuid" ]] && echo "vless|$server|$port|$uuid|${name:-VLESS}"
    fi
}

# 生成Xray配置
create_config() {
    local protocol="$1" server="$2" port="$3" uuid="$4" config_file="$5"
    
    if [[ "$protocol" == "vmess" ]]; then
        cat > "$config_file" << EOF
{
    "inbounds": [{"port": $SOCKS_PORT, "protocol": "socks"}],
    "outbounds": [{
        "protocol": "vmess",
        "settings": {
            "vnext": [{
                "address": "$server",
                "port": $port,
                "users": [{"id": "$uuid", "alterId": 0}]
            }]
        }
    }]
}
EOF
    else
        cat > "$config_file" << EOF
{
    "inbounds": [{"port": $SOCKS_PORT, "protocol": "socks"}],
    "outbounds": [{
        "protocol": "vless",
        "settings": {
            "vnext": [{
                "address": "$server",
                "port": $port,
                "users": [{"id": "$uuid", "encryption": "none"}]
            }]
        }
    }]
}
EOF
    fi
}

# 测试节点
test_node() {
    local protocol="$1" server="$2" port="$3" uuid="$4" name="$5"
    
    info "测试: $name ($server:$port)"
    
    # 检查Xray
    if ! command -v xray >/dev/null 2>&1; then
        warn "Xray未安装"
        echo "{\"name\":\"$name\",\"server\":\"$server\",\"port\":$port,\"status\":\"skipped\",\"error\":\"Xray未安装\"}"
        return
    fi
    
    # 生成配置并启动
    local config_file="/tmp/xray_subcheck_$$.json"
    create_config "$protocol" "$server" "$port" "$uuid" "$config_file"
    
    xray -c "$config_file" > /tmp/xray_subcheck.log 2>&1 &
    local xray_pid=$!
    sleep 2
    
    local latency=-1 speed=-1 status="failed" error=""
    
    # 检查Xray是否启动
    if kill -0 "$xray_pid" 2>/dev/null; then
        # 测试延迟
        local start_time=$(date +%s%N)
        if curl -s --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
                --connect-timeout 3 --max-time $TEST_TIMEOUT \
                -o /dev/null "http://www.google.com/generate_204" 2>/dev/null; then
            local end_time=$(date +%s%N)
            latency=$(( (end_time - start_time) / 1000000 ))
            status="success"
            
            # 测试速度
            local speed_start=$(date +%s)
            local downloaded=$(curl -s --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
                                   --connect-timeout 3 --max-time 10 \
                                   -w "%{size_download}" \
                                   -o /dev/null "http://speedtest.tele2.net/100KB.zip" 2>/dev/null || echo "0")
            
            if [[ "$downloaded" -gt 0 ]]; then
                local speed_end=$(date +%s)
                local duration=$((speed_end - speed_start))
                [[ "$duration" -gt 0 ]] && speed=$(echo "scale=1; ($downloaded * 8) / ($duration * 1000000)" | bc 2>/dev/null || echo "0")
            fi
            
            success "$name - 延迟: ${latency}ms, 速度: ${speed}Mbps"
        else
            error="连接失败"
        fi
    else
        error="代理启动失败"
    fi
    
    # 清理
    kill "$xray_pid" 2>/dev/null || true
    rm -f "$config_file"
    
    # 输出结果
    cat << EOF
{
    "name": "$name",
    "server": "$server",
    "port": $port,
    "protocol": "$protocol",
    "latency": $latency,
    "speed": $speed,
    "status": "$status",
    "error": "$error",
    "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
}

# 主测试函数
run_test() {
    info "开始订阅测速测试"
    
    if [[ ! -f "subscription.txt" ]]; then
        error "订阅文件不存在: subscription.txt"
        exit 1
    fi
    
    local results="[]"
    local tested=0 success=0
    
    # 处理订阅
    while IFS= read -r sub_url && [[ $tested -lt $MAX_NODES ]]; do
        [[ -z "$sub_url" || "$sub_url" == \#* ]] && continue
        
        info "处理订阅: $(basename "$sub_url")"
        local content=$(get_subscription "$sub_url")
        [[ -z "$content" ]] && continue
        
        # 解析并测试节点
        while IFS= read -r line && [[ $tested -lt $MAX_NODES ]]; do
            [[ -z "$line" ]] && continue
            
            local node_info=$(parse_node "$line")
            if [[ -n "$node_info" ]]; then
                tested=$((tested + 1))
                
                IFS='|' read -r protocol server port uuid name <<< "$node_info"
                local result=$(test_node "$protocol" "$server" "$port" "$uuid" "$name")
                
                [[ "$result" == *'"status":"success"'* ]] && success=$((success + 1))
                
                # 添加到结果
                if [[ "$results" == "[]" ]]; then
                    results="[$result]"
                else
                    results="${results%]}, $result]"
                fi
            fi
        done <<< "$content"
        
    done < "subscription.txt"
    
    # 保存结果
    echo "$results" > "$RESULTS_FILE"
    
    # 显示摘要
    echo -e "\n${YELLOW}=== 测试摘要 ===${NC}"
    echo "测试节点: $tested"
    echo "成功节点: $success"
    [[ $tested -gt 0 ]] && echo "成功率: $(( success * 100 / tested ))%"
    echo "结果文件: $RESULTS_FILE"
    
    # 显示最佳节点
    if [[ $success -gt 0 ]]; then
        echo -e "\n${GREEN}=== 可用节点 ===${NC}"
        if command -v jq >/dev/null 2>&1; then
            jq -r '.[] | select(.status == "success") | "\(.latency)ms \(.speed)Mbps \(.name)"' "$RESULTS_FILE" | sort -n | head -5 | nl -w2 -s'. '
        else
            grep '"status":"success"' "$RESULTS_FILE" | head -5 | nl -w2 -s'. '
        fi
    fi
    
    success "测试完成!"
}

# 显示结果
show_results() {
    [[ ! -f "$RESULTS_FILE" ]] && { error "结果文件不存在"; exit 1; }
    
    if command -v jq >/dev/null 2>&1; then
        local total=$(jq 'length' "$RESULTS_FILE")
        local success_count=$(jq '[.[] | select(.status == "success")] | length' "$RESULTS_FILE")
        
        echo -e "${YELLOW}=== 测试结果 ===${NC}"
        echo "总节点: $total, 成功: $success_count"
        
        echo -e "\n${GREEN}=== 可用节点 ===${NC}"
        jq -r '.[] | select(.status == "success") | "\(.latency)ms \(.speed)Mbps \(.name) (\(.server):\(.port))"' "$RESULTS_FILE" | sort -n | head -10 | nl -w2 -s'. '
    else
        cat "$RESULTS_FILE"
    fi
}

# 帮助信息
show_help() {
    cat << EOF
${BLUE}SubCheck - 优化精简版订阅测速工具${NC}

${YELLOW}用法:${NC}
  $0 test         执行测试
  $0 results      显示结果
  $0 help         显示帮助

${YELLOW}配置:${NC}
  最大节点数: $MAX_NODES
  测试超时: $TEST_TIMEOUT 秒
  代理端口: $SOCKS_PORT

${YELLOW}文件:${NC}
  subscription.txt    订阅链接文件
  $RESULTS_FILE       测试结果文件
EOF
}

# 主程序
case "${1:-help}" in
    "test") run_test ;;
    "results") show_results ;;
    "help"|*) show_help ;;
esac