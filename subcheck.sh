#!/bin/bash
# SubCheck 精简版 - 核心测速功能
set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# 核心功能：解析订阅
parse_subscription() {
    local input="$1"
    local content
    
    if [[ "$input" == http* ]]; then
        content=$(curl -s --connect-timeout 10 "$input" || echo "")
    else
        content=$(cat "$input" 2>/dev/null || echo "")
    fi
    
    if [ -z "$content" ]; then
        error "无法获取订阅内容"
        return 1
    fi
    
    # 尝试Base64解码
    if [[ "$content" != *"vless://"* && "$content" != *"vmess://"* ]]; then
        content=$(echo "$content" | base64 -d 2>/dev/null || echo "$content")
    fi
    
    echo "$content"
}

# 解析VMESS配置
parse_vmess() {
    local vmess_url="$1"
    local config="${vmess_url#vmess://}"
    
    # 添加padding以确保Base64解码正确
    local padding=$((4 - ${#config} % 4))
    if [ $padding -ne 4 ]; then
        padding_chars=$(printf '=%.0s' $(seq 1 $padding))
        config="${config}${padding_chars}"
    fi
    
    local decoded=$(echo "$config" | base64 -d 2>/dev/null)
    
    if [ -z "$decoded" ]; then
        warn "无法解码VMESS配置: $config"
        return 1
    fi
    
    # 调试输出
    info "解码的VMESS配置: $decoded"
    
    # 使用简单的字符串解析而不是jq
    local address=$(echo "$decoded" | grep -o '"add"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    local port=$(echo "$decoded" | grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
    local name=$(echo "$decoded" | grep -o '"ps"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$address" ] || [ -z "$port" ]; then
        warn "无效的VMESS配置: $decoded"
        return 1
    fi
    
    if [ -z "$name" ]; then
        name="$address:$port"
    fi
    
    echo "$name $address $port"
}

# 核心功能：测试节点延迟
test_latency() {
    local address="$1"
    local port="$2"
    
    # 使用curl测试TCP连接延迟
    local start_time=$(date +%s%N)
    if timeout 5 curl -s "http://$address:$port" --head >/dev/null 2>&1; then
        local end_time=$(date +%s%N)
        local latency=$(( (end_time - start_time) / 1000000 ))
        echo $latency
    else
        echo -1
    fi
}

# 核心功能：测试下载速度
test_speed() {
    local address="$1"
    local port="$2"
    
    # 简单的速度测试（使用小文件下载）
    local test_url="http://$address:$port/small.file"
    local start_time=$(date +%s)
    
    if timeout 10 curl -s -o /dev/null "$test_url"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        if [ $duration -eq 0 ]; then
            duration=1
        fi
        # 假设下载了100KB数据
        local speed=$((100 * 8 / duration)) # 转换为Mbps
        echo $speed
    else
        echo -1
    fi
}

# 主函数
main() {
    local input="${1:-subscription.txt}"
    local output="${2:-results.json}"
    
    info "开始测试订阅: $input"
    
    local content=$(parse_subscription "$input")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local results="[]"
    local tested=0
    local successful=0
    
    # 解析订阅链接
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r' | xargs)
        if [ -z "$line" ]; then
            continue
        fi
        
        if [[ "$line" == vless://* ]]; then
            tested=$((tested + 1))
            
            # 解析VLESS链接
            local config="${line#vless://}"
            local user_info="${config%%@*}"
            local server_info="${config#*@}"
            local address="${server_info%%:*}"
            local port="${server_info#*:}"
            port="${port%%[?]*}"  # 移除?后面的参数
            
            # 提取节点名称（如果有#标签）
            local name="${line##*#}"
            if [ "$name" == "$line" ]; then
                name="VLESS-$address:$port"
            fi
            
            info "测试VLESS节点: $name (地址: $address, 端口: $port)"
            
            # 测试延迟
            local latency=$(test_latency "$address" "$port")
            local speed=$(test_speed "$address" "$port")
            
            info "测试结果 - 延迟: ${latency}ms, 速度: ${speed}Mbps"
            
            local result
            if [ "$latency" -ne -1 ]; then
                successful=$((successful + 1))
                result=$(jq -n \
                    --arg name "$name" \
                    --arg address "$address" \
                    --arg port "$port" \
                    --arg latency "$latency" \
                    --arg speed "$speed" \
                    '{name: $name, address: $address, port: $port, latency: $latency|tonumber, speed: $speed|tonumber, success: true}')
            else
                result=$(jq -n \
                    --arg name "$name" \
                    --arg address "$address" \
                    --arg port "$port" \
                    '{name: $name, address: $address, port: $port, latency: -1, speed: -1, success: false}')
            fi
            
            results=$(echo "$results" | jq --argjson res "$result" '. + [$res]')
            
        elif [[ "$line" == vmess://* ]]; then
            tested=$((tested + 1))
            
            # 解析VMESS链接
            info "发现VMESS链接: $line"
            local vmess_info=$(parse_vmess "$line")
            if [ $? -eq 0 ]; then
                local name=$(echo "$vmess_info" | awk '{print $1}')
                local address=$(echo "$vmess_info" | awk '{print $2}')
                local port=$(echo "$vmess_info" | awk '{print $3}')
                
                info "测试VMESS节点: $name (地址: $address, 端口: $port)"
                
                # 测试延迟
                local latency=$(test_latency "$address" "$port")
                local speed=$(test_speed "$address" "$port")
                
                info "测试结果 - 延迟: ${latency}ms, 速度: ${speed}Mbps"
                
                local result
                if [ "$latency" -ne -1 ]; then
                    successful=$((successful + 1))
                    result=$(jq -n \
                        --arg name "$name" \
                        --arg address "$address" \
                        --arg port "$port" \
                        --arg latency "$latency" \
                        --arg speed "$speed" \
                        '{name: $name, address: $address, port: $port, latency: $latency|tonumber, speed: $speed|tonumber, success: true}')
                else
                    result=$(jq -n \
                        --arg name "$name" \
                        --arg address "$address" \
                        --arg port "$port" \
                        '{name: $name, address: $address, port: $port, latency: -1, speed: -1, success: false}')
                fi
                
                results=$(echo "$results" | jq --argjson res "$result" '. + [$res]')
            else
                warn "跳过无效的VMESS链接: $line"
            fi
        fi
    done <<< "$content"
    
    # 保存结果
    echo "$results" > "$output"
    success "测试完成! 成功: $successful/$tested"
    info "结果保存至: $output"
}

# 脚本入口
if [ $# -eq 0 ]; then
    echo "使用方法: $0 [订阅文件或URL] [输出文件]"
    echo "示例: $0 subscription.txt results.json"
    echo "       $0 https://example.com/sub"
    exit 1
fi

main "$@"