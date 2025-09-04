#!/bin/bash

# SubCheck 最佳技术栈实现
# 学习subscheck-win-gui的核心逻辑，精简高效

set -e

# 配置参数
MAX_NODES=10
TEST_TIMEOUT=8
SOCKS_PORT=10808
RESULTS_FILE="test_results.txt"

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

# 核心函数1: 获取订阅内容
fetch_subscription() {
    local url="$1"
    local content=""
    
    if [[ "$url" == http* ]]; then
        content=$(curl -s --connect-timeout 10 --max-time 30 "$url" 2>/dev/null || echo "")
    else
        content=$(cat "$url" 2>/dev/null || echo "")
    fi
    
    # 自动检测Base64编码
    if [[ -n "$content" && "$content" != *"://"* ]]; then
        content=$(echo "$content" | base64 -d 2>/dev/null || echo "$content")
    fi
    
    echo "$content"
}

# 核心函数2: 解析节点信息
parse_node() {
    local line="$1"
    
    if [[ "$line" == vmess://* ]]; then
        # VMess解析
        local config="${line#vmess://}"
        local decoded=$(echo "$config" | base64 -d 2>/dev/null || echo "")
        
        if [[ -n "$decoded" ]]; then
            # 简单JSON解析（避免依赖jq）
            local server=$(echo "$decoded" | grep -o '"add"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
            local port=$(echo "$decoded" | grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
            local uuid=$(echo "$decoded" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
            local name=$(echo "$decoded" | grep -o '"ps"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
            
            if [[ -n "$server" && -n "$port" && -n "$uuid" ]]; then
                echo "vmess|$server|$port|$uuid|${name:-VMess}"
            fi
        fi
        
    elif [[ "$line" == vless://* ]]; then
        # VLESS解析
        local config="${line#vless://}"
        local uuid="${config%%@*}"
        local rest="${config#*@}"
        local server_port="${rest%%\?*}"
        local server="${server_port%%:*}"
        local port="${server_port#*:}"
        local name=""
        
        if [[ "$line" == *"#"* ]]; then
            name="${line##*#}"
            # URL解码
            name=$(echo "$name" | python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))" 2>/dev/null || echo "$name")
        fi
        
        if [[ -n "$server" && -n "$port" && -n "$uuid" ]]; then
            echo "vless|$server|$port|$uuid|${name:-VLESS}"
        fi
    fi
}

# 核心函数3: 生成Xray配置
generate_config() {
    local protocol="$1"
    local server="$2"
    local port="$3"
    local uuid="$4"
    local config_file="$5"
    
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
    elif [[ "$protocol" == "vless" ]]; then
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

# 核心函数4: 测试节点
test_node() {
    local protocol="$1"
    local server="$2"
    local port="$3"
    local uuid="$4"
    local name="$5"
    
    info "测试: $name ($server:$port)"
    
    # 生成配置
    local config_file="/tmp/xray_$$.json"
    generate_config "$protocol" "$server" "$port" "$uuid" "$config_file"
    
    # 启动Xray
    if ! command -v xray >/dev/null 2>&1; then
        warn "Xray未安装，跳过"
        echo "$name|$server|$port|跳过|Xray未安装"
        return
    fi
    
    xray -c "$config_file" >/dev/null 2>&1 &
    local xray_pid=$!
    sleep 2
    
    # 测试延迟
    local latency=-1
    local speed=-1
    local status="失败"
    
    if kill -0 "$xray_pid" 2>/dev/null; then
        # 延迟测试
        local start_time=$(date +%s%N)
        if curl -s --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
                --connect-timeout 3 --max-time $TEST_TIMEOUT \
                -o /dev/null "http://www.google.com/generate_204" 2>/dev/null; then
            local end_time=$(date +%s%N)
            latency=$(( (end_time - start_time) / 1000000 ))
            status="成功"
            
            # 速度测试（简化版）
            local speed_start=$(date +%s)
            local downloaded=$(curl -s --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
                                   --connect-timeout 3 --max-time 10 \
                                   -w "%{size_download}" \
                                   -o /dev/null "http://speedtest.tele2.net/100KB.zip" 2>/dev/null || echo "0")
            
            if [[ "$downloaded" -gt 0 ]]; then
                local speed_end=$(date +%s)
                local duration=$((speed_end - speed_start))
                if [[ "$duration" -gt 0 ]]; then
                    speed=$(echo "scale=1; ($downloaded * 8) / ($duration * 1000000)" | bc 2>/dev/null || echo "0")
                fi
            fi
        fi
    fi
    
    # 停止Xray
    kill "$xray_pid" 2>/dev/null || true
    rm -f "$config_file"
    
    if [[ "$status" == "成功" ]]; then
        success "$name - 延迟: ${latency}ms, 速度: ${speed}Mbps"
    else
        warn "$name - 连接失败"
    fi
    
    echo "$name|$server|$port|$status|延迟:${latency}ms 速度:${speed}Mbps"
}

# 主函数
main() {
    echo -e "${BLUE}=== SubCheck 最佳技术栈版本 ===${NC}"
    info "开始时间: $(date '+%H:%M:%S')"
    
    if [[ ! -f "subscription.txt" ]]; then
        error "订阅文件不存在: subscription.txt"
        exit 1
    fi
    
    # 初始化结果文件
    echo "# SubCheck 测试结果 - $(date '+%Y-%m-%d %H:%M:%S')" > "$RESULTS_FILE"
    echo "# 格式: 节点名称|服务器|端口|状态|详情" >> "$RESULTS_FILE"
    
    local total_tested=0
    local total_success=0
    
    # 处理订阅
    while IFS= read -r subscription_url && [[ $total_tested -lt $MAX_NODES ]]; do
        [[ -z "$subscription_url" ]] && continue
        [[ "$subscription_url" == \#* ]] && continue
        
        info "处理订阅: $(basename "$subscription_url")"
        
        local content=$(fetch_subscription "$subscription_url")
        [[ -z "$content" ]] && continue
        
        # 解析节点
        while IFS= read -r line && [[ $total_tested -lt $MAX_NODES ]]; do
            [[ -z "$line" ]] && continue
            
            local node_info=$(parse_node "$line")
            if [[ -n "$node_info" ]]; then
                total_tested=$((total_tested + 1))
                
                IFS='|' read -r protocol server port uuid name <<< "$node_info"
                local result=$(test_node "$protocol" "$server" "$port" "$uuid" "$name")
                
                if [[ "$result" == *"|成功|"* ]]; then
                    total_success=$((total_success + 1))
                fi
                
                echo "$result" >> "$RESULTS_FILE"
            fi
            
        done <<< "$content"
        
    done < "subscription.txt"
    
    # 显示摘要
    echo -e "\n${YELLOW}=== 测试摘要 ===${NC}"
    echo "测试节点: $total_tested"
    echo "成功节点: $total_success"
    if [[ $total_tested -gt 0 ]]; then
        echo "成功率: $(( total_success * 100 / total_tested ))%"
    fi
    echo "结果文件: $RESULTS_FILE"
    
    # 显示最佳节点
    if [[ $total_success -gt 0 ]]; then
        echo -e "\n${GREEN}=== 可用节点 ===${NC}"
        grep "|成功|" "$RESULTS_FILE" | head -5 | while IFS='|' read -r name server port status details; do
            echo "  $name ($server:$port) - $details"
        done
    fi
    
    success "测试完成!"
}

# 执行
main "$@"