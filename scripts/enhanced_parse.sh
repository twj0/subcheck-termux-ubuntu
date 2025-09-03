#!/bin/bash

# 增强版订阅解析脚本
# 支持多种订阅格式和节点类型

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SUBSCRIPTION_FILE="$PROJECT_DIR/subscription.txt"
NODES_OUTPUT="$PROJECT_DIR/parsed_nodes.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Base64解码函数
decode_base64() {
    local input="$1"
    if command -v base64 >/dev/null 2>&1; then
        echo "$input" | base64 -d 2>/dev/null
    else
        echo "$input" | python3 -c "import sys, base64; print(base64.b64decode(sys.stdin.read().strip()).decode('utf-8', errors='ignore'))" 2>/dev/null
    fi
}

# 解析VLESS链接
parse_vless() {
    local url="$1"
    local server_info=$(echo "$url" | sed 's/vless:\/\///' | cut -d'@' -f2 | cut -d'?' -f1)
    local server=$(echo "$server_info" | cut -d':' -f1)
    local port=$(echo "$server_info" | cut -d':' -f2)
    local uuid=$(echo "$url" | sed 's/vless:\/\///' | cut -d'@' -f1)
    
    # 提取查询参数
    local query_string=$(echo "$url" | cut -d'?' -f2 | cut -d'#' -f1)
    local name=$(echo "$url" | cut -d'#' -f2 | python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))" 2>/dev/null || echo "Unknown")
    
    # 解析查询参数
    local security="none"
    local sni=""
    local type="tcp"
    
    if [[ "$query_string" == *"security="* ]]; then
        security=$(echo "$query_string" | grep -o 'security=[^&]*' | cut -d'=' -f2)
    fi
    
    if [[ "$query_string" == *"sni="* ]]; then
        sni=$(echo "$query_string" | grep -o 'sni=[^&]*' | cut -d'=' -f2)
    fi
    
    if [[ "$query_string" == *"type="* ]]; then
        type=$(echo "$query_string" | grep -o 'type=[^&]*' | cut -d'=' -f2)
    fi
    
    # 生成JSON
    cat << EOF
{
    "protocol": "vless",
    "server": "$server",
    "port": $port,
    "uuid": "$uuid",
    "security": "$security",
    "sni": "$sni",
    "network": "$type",
    "name": "$name"
}
EOF
}

# 解析VMess链接
parse_vmess() {
    local url="$1"
    local base64_part=$(echo "$url" | sed 's/vmess:\/\///')
    local decoded=$(decode_base64 "$base64_part")
    
    if [[ -n "$decoded" ]] && echo "$decoded" | jq . >/dev/null 2>&1; then
        # 标准化JSON格式
        echo "$decoded" | jq '{
            protocol: "vmess",
            server: .add,
            port: (.port | tonumber),
            uuid: .id,
            alterId: (.aid | tonumber),
            security: .scy,
            network: .net,
            name: .ps
        }'
    else
        log_error "无法解析VMess链接: $url"
        return 1
    fi
}

# 解析Trojan链接
parse_trojan() {
    local url="$1"
    local password=$(echo "$url" | sed 's/trojan:\/\///' | cut -d'@' -f1)
    local server_info=$(echo "$url" | sed 's/trojan:\/\///' | cut -d'@' -f2 | cut -d'?' -f1)
    local server=$(echo "$server_info" | cut -d':' -f1)
    local port=$(echo "$server_info" | cut -d':' -f2)
    local name=$(echo "$url" | cut -d'#' -f2 | python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))" 2>/dev/null || echo "Unknown")
    
    cat << EOF
{
    "protocol": "trojan",
    "server": "$server",
    "port": $port,
    "password": "$password",
    "name": "$name"
}
EOF
}

# 获取订阅内容
fetch_subscription() {
    local url="$1"
    log_info "获取订阅内容: $url"
    
    if [[ "$url" == http* ]]; then
        # 网络订阅
        if command -v curl >/dev/null 2>&1; then
            curl -s --connect-timeout 10 --max-time 30 "$url"
        elif command -v wget >/dev/null 2>&1; then
            wget -q -O - --timeout=30 "$url"
        else
            log_error "需要curl或wget工具"
            return 1
        fi
    else
        # 本地文件或直接内容
        if [[ -f "$url" ]]; then
            cat "$url"
        else
            echo "$url"
        fi
    fi
}

# 主解析函数
parse_subscription() {
    local subscription_content="$1"
    local nodes_array="[]"
    
    # 尝试Base64解码
    local decoded_content=$(decode_base64 "$subscription_content")
    if [[ -n "$decoded_content" ]]; then
        subscription_content="$decoded_content"
    fi
    
    # 逐行解析
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        if [[ "$line" == vless://* ]]; then
            log_info "解析VLESS节点"
            node_json=$(parse_vless "$line")
            if [[ $? -eq 0 ]] && [[ -n "$node_json" ]]; then
                nodes_array=$(echo "$nodes_array" | jq ". += [$node_json]")
            fi
        elif [[ "$line" == vmess://* ]]; then
            log_info "解析VMess节点"
            node_json=$(parse_vmess "$line")
            if [[ $? -eq 0 ]] && [[ -n "$node_json" ]]; then
                nodes_array=$(echo "$nodes_array" | jq ". += [$node_json]")
            fi
        elif [[ "$line" == trojan://* ]]; then
            log_info "解析Trojan节点"
            node_json=$(parse_trojan "$line")
            if [[ $? -eq 0 ]] && [[ -n "$node_json" ]]; then
                nodes_array=$(echo "$nodes_array" | jq ". += [$node_json]")
            fi
        fi
    done <<< "$subscription_content"
    
    echo "$nodes_array"
}

# 主函数
main() {
    log_info "开始解析订阅文件: $SUBSCRIPTION_FILE"
    
    if [[ ! -f "$SUBSCRIPTION_FILE" ]]; then
        log_error "订阅文件不存在: $SUBSCRIPTION_FILE"
        exit 1
    fi
    
    # 检查依赖
    if ! command -v jq >/dev/null 2>&1; then
        log_error "需要安装jq工具: apt install jq"
        exit 1
    fi
    
    local total_nodes=0
    local all_nodes="[]"
    
    # 读取订阅文件
    while IFS= read -r subscription_url; do
        [[ -z "$subscription_url" ]] && continue
        [[ "$subscription_url" == \#* ]] && continue
        
        log_info "处理订阅: $subscription_url"
        
        subscription_content=$(fetch_subscription "$subscription_url")
        if [[ $? -ne 0 ]] || [[ -z "$subscription_content" ]]; then
            log_warning "无法获取订阅内容: $subscription_url"
            continue
        fi
        
        nodes=$(parse_subscription "$subscription_content")
        node_count=$(echo "$nodes" | jq 'length')
        
        if [[ "$node_count" -gt 0 ]]; then
            all_nodes=$(echo "$all_nodes" | jq ". += $nodes")
            total_nodes=$((total_nodes + node_count))
            log_success "解析到 $node_count 个节点"
        else
            log_warning "未找到有效节点"
        fi
        
    done < "$SUBSCRIPTION_FILE"
    
    # 保存结果
    echo "$all_nodes" | jq '.' > "$NODES_OUTPUT"
    log_success "总共解析到 $total_nodes 个节点，保存到: $NODES_OUTPUT"
    
    # 显示节点摘要
    if [[ "$total_nodes" -gt 0 ]]; then
        echo -e "\n${YELLOW}=== 节点摘要 ===${NC}"
        echo "$all_nodes" | jq -r '.[] | "\(.protocol) - \(.server):\(.port) - \(.name)"' | head -10
        if [[ "$total_nodes" -gt 10 ]]; then
            echo "... 还有 $((total_nodes - 10)) 个节点"
        fi
    fi
}

# 执行主函数
main "$@"