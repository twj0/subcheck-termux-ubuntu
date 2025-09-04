#!/bin/bash

# SubCheck - 调试版本
set -e

# 配置
MAX_NODES=3  # 减少到3个用于调试
TEST_TIMEOUT=8
SOCKS_PORT=10808

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { echo -e "${YELLOW}[DEBUG]${NC} $1"; }

# 环境检查
check_environment() {
    info "检查环境..."
    
    # 检查必要工具
    local missing_tools=()
    for tool in curl base64 bc; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error "缺少工具: ${missing_tools[*]}"
        info "安装命令: apt update && apt install -y curl coreutils bc"
        exit 1
    fi
    
    # 检查Xray
    if command -v xray >/dev/null 2>&1; then
        success "Xray已安装: $(xray version | head -1)"
    else
        warn "Xray未安装，将跳过代理测试"
    fi
    
    # 检查订阅文件
    if [[ -f "subscription.txt" ]]; then
        local line_count=$(wc -l < "subscription.txt")
        success "订阅文件存在，共 $line_count 行"
    else
        error "订阅文件不存在: subscription.txt"
        exit 1
    fi
}

# 获取订阅内容（调试版）
get_subscription_debug() {
    local url="$1"
    debug "获取订阅: $url"
    
    local content=""
    if [[ "$url" == http* ]]; then
        debug "HTTP订阅，使用curl获取"
        content=$(curl -s --connect-timeout 10 --max-time 30 "$url" 2>/dev/null || echo "")
    else
        debug "本地文件，直接读取"
        content=$(cat "$url" 2>/dev/null || echo "")
    fi
    
    if [[ -z "$content" ]]; then
        warn "订阅内容为空"
        return 1
    fi
    
    debug "原始内容长度: ${#content}"
    
    # Base64解码检测
    if [[ "$content" != *"://"* ]]; then
        debug "检测到Base64编码，尝试解码"
        local decoded=$(echo "$content" | base64 -d 2>/dev/null || echo "")
        if [[ -n "$decoded" && "$decoded" == *"://"* ]]; then
            content="$decoded"
            debug "Base64解码成功，解码后长度: ${#content}"
        else
            debug "Base64解码失败或结果无效"
        fi
    fi
    
    # 统计节点数量
    local vmess_count=$(echo "$content" | grep -c "^vmess://" || echo "0")
    local vless_count=$(echo "$content" | grep -c "^vless://" || echo "0")
    local trojan_count=$(echo "$content" | grep -c "^trojan://" || echo "0")
    
    debug "节点统计 - VMess: $vmess_count, VLESS: $vless_count, Trojan: $trojan_count"
    
    echo "$content"
}

# 解析节点（调试版）
parse_node_debug() {
    local line="$1"
    debug "解析节点: ${line:0:50}..."
    
    if [[ "$line" == vmess://* ]]; then
        debug "VMess节点"
        local config="${line#vmess://}"
        local decoded=$(echo "$config" | base64 -d 2>/dev/null || echo "")
        
        if [[ -n "$decoded" ]]; then
            debug "VMess配置解码成功: ${decoded:0:100}..."
            
            # 使用更简单的方法提取字段
            local server=$(echo "$decoded" | sed -n 's/.*"add"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            local port=$(echo "$decoded" | sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
            local uuid=$(echo "$decoded" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            local name=$(echo "$decoded" | sed -n 's/.*"ps"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            
            debug "解析结果 - 服务器: $server, 端口: $port, UUID: ${uuid:0:8}..., 名称: $name"
            
            if [[ -n "$server" && -n "$port" && -n "$uuid" ]]; then
                echo "vmess|$server|$port|$uuid|${name:-VMess}"
                return 0
            fi
        fi
        
    elif [[ "$line" == vless://* ]]; then
        debug "VLESS节点"
        local config="${line#vless://}"
        local uuid="${config%%@*}"
        local rest="${config#*@}"
        local server_port="${rest%%\?*}"
        local server="${server_port%%:*}"
        local port="${server_port#*:}"
        local name=""
        
        if [[ "$line" == *"#"* ]]; then
            name="${line##*#}"
            # 简单的URL解码
            name=$(echo "$name" | sed 's/%20/ /g; s/%21/!/g; s/%23/#/g')
        fi
        
        debug "解析结果 - 服务器: $server, 端口: $port, UUID: ${uuid:0:8}..., 名称: $name"
        
        if [[ -n "$server" && -n "$port" && -n "$uuid" ]]; then
            echo "vless|$server|$port|$uuid|${name:-VLESS}"
            return 0
        fi
    fi
    
    debug "节点解析失败"
    return 1
}

# 简单连接测试（不使用代理）
test_direct_connection() {
    local server="$1" port="$2" name="$3"
    
    debug "直接连接测试: $server:$port"
    
    # 使用nc测试端口连通性
    if command -v nc >/dev/null 2>&1; then
        if timeout 5 nc -z "$server" "$port" 2>/dev/null; then
            success "端口连通: $server:$port"
            return 0
        else
            warn "端口不通: $server:$port"
        fi
    else
        # 使用curl测试
        if curl -s --connect-timeout 5 --max-time 5 "http://$server:$port" >/dev/null 2>&1; then
            success "连接成功: $server:$port"
            return 0
        else
            warn "连接失败: $server:$port"
        fi
    fi
    
    return 1
}

# 主调试函数
debug_test() {
    info "开始调试测试"
    
    check_environment
    
    local tested=0
    local parsed=0
    local connected=0
    
    # 只处理第一个订阅进行调试
    local first_sub=$(head -1 "subscription.txt")
    info "调试订阅: $first_sub"
    
    local content=$(get_subscription_debug "$first_sub")
    if [[ -z "$content" ]]; then
        error "无法获取订阅内容"
        exit 1
    fi
    
    info "开始解析节点..."
    
    # 解析前几个节点进行测试
    while IFS= read -r line && [[ $tested -lt $MAX_NODES ]]; do
        [[ -z "$line" ]] && continue
        
        tested=$((tested + 1))
        info "测试节点 $tested: ${line:0:50}..."
        
        local node_info=$(parse_node_debug "$line")
        if [[ -n "$node_info" ]]; then
            parsed=$((parsed + 1))
            
            IFS='|' read -r protocol server port uuid name <<< "$node_info"
            success "解析成功: $name ($protocol://$server:$port)"
            
            # 简单连接测试
            if test_direct_connection "$server" "$port" "$name"; then
                connected=$((connected + 1))
            fi
        else
            warn "解析失败"
        fi
        
        echo "---"
        
    done <<< "$content"
    
    # 显示调试摘要
    echo -e "\n${YELLOW}=== 调试摘要 ===${NC}"
    echo "测试节点: $tested"
    echo "解析成功: $parsed"
    echo "连接成功: $connected"
    
    if [[ $parsed -eq 0 ]]; then
        error "所有节点解析失败，请检查订阅格式"
    elif [[ $connected -eq 0 ]]; then
        warn "所有节点连接失败，可能是网络问题"
    else
        success "调试完成，发现可用节点"
    fi
}

# 运行调试
debug_test