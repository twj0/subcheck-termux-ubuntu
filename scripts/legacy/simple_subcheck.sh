#!/bin/bash

# 简化版订阅测速工具 - 不依赖jq
# 适用于资源受限的环境

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置参数
SUBSCRIPTION_FILE="subscription.txt"
RESULTS_FILE="simple_results.txt"
TEMP_DIR="/tmp/subcheck"
SOCKS_PORT=10808
TEST_TIMEOUT=10

# 日志函数
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

# 创建临时目录
setup_temp_dir() {
    mkdir -p "$TEMP_DIR"
}

# 清理临时文件
cleanup() {
    rm -rf "$TEMP_DIR"
    # 停止可能运行的xray进程
    pkill -f "xray.*$TEMP_DIR" 2>/dev/null || true
}

# 设置清理陷阱
trap cleanup EXIT

# Base64解码函数（不依赖base64命令）
decode_base64() {
    local input="$1"
    if command -v base64 >/dev/null 2>&1; then
        echo "$input" | base64 -d 2>/dev/null || echo "$input"
    else
        # 使用python作为备选
        echo "$input" | python3 -c "import sys, base64; print(base64.b64decode(sys.stdin.read().strip()).decode('utf-8', errors='ignore'))" 2>/dev/null || echo "$input"
    fi
}

# 获取订阅内容
fetch_subscription() {
    local url="$1"
    log_info "获取订阅: $url"
    
    if [[ "$url" == http* ]]; then
        if command -v curl >/dev/null 2>&1; then
            curl -s --connect-timeout 10 --max-time 30 "$url" 2>/dev/null || echo ""
        elif command -v wget >/dev/null 2>&1; then
            wget -q -O - --timeout=30 "$url" 2>/dev/null || echo ""
        else
            log_error "需要curl或wget工具"
            return 1
        fi
    else
        cat "$url" 2>/dev/null || echo ""
    fi
}

# 解析VLESS链接
parse_vless() {
    local url="$1"
    # 移除vless://前缀
    local config="${url#vless://}"
    
    # 提取UUID和服务器信息
    local uuid="${config%%@*}"
    local server_part="${config#*@}"
    
    # 提取服务器地址和端口
    local server_info="${server_part%%\?*}"
    local server="${server_info%%:*}"
    local port="${server_info#*:}"
    
    # 提取名称（如果有#标签）
    local name=""
    if [[ "$url" == *"#"* ]]; then
        name="${url##*#}"
        # URL解码名称
        name=$(echo "$name" | sed 's/%20/ /g' | sed 's/%E2%80%8B//g')
    fi
    
    if [[ -z "$name" ]]; then
        name="VLESS-$server:$port"
    fi
    
    echo "$name|$server|$port|vless|$uuid"
}

# 解析VMess链接
parse_vmess() {
    local url="$1"
    local config="${url#vmess://}"
    
    # 解码Base64
    local decoded=$(decode_base64 "$config")
    
    if [[ -z "$decoded" ]]; then
        return 1
    fi
    
    # 简单的JSON解析（不使用jq）
    local server=$(echo "$decoded" | grep -o '"add"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    local port=$(echo "$decoded" | grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
    local uuid=$(echo "$decoded" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    local name=$(echo "$decoded" | grep -o '"ps"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    
    if [[ -z "$server" || -z "$port" || -z "$uuid" ]]; then
        return 1
    fi
    
    if [[ -z "$name" ]]; then
        name="VMess-$server:$port"
    fi
    
    echo "$name|$server|$port|vmess|$uuid"
}

# 生成Xray配置文件
generate_xray_config() {
    local server="$1"
    local port="$2"
    local protocol="$3"
    local uuid="$4"
    local config_file="$5"
    
    if [[ "$protocol" == "vless" ]]; then
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
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "serverName": "$server"
                }
            }
        }
    ]
}
EOF
    elif [[ "$protocol" == "vmess" ]]; then
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
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "serverName": "$server"
                }
            }
        }
    ]
}
EOF
    fi
}

# 测试节点连通性
test_node_connectivity() {
    local name="$1"
    local server="$2"
    local port="$3"
    local protocol="$4"
    local uuid="$5"
    
    log_info "测试节点: $name ($server:$port)"
    
    # 生成配置文件
    local config_file="$TEMP_DIR/config_$$.json"
    generate_xray_config "$server" "$port" "$protocol" "$uuid" "$config_file"
    
    # 检查xray是否可用
    if ! command -v xray >/dev/null 2>&1; then
        log_warning "Xray未安装，跳过代理测试，使用直连测试"
        # 直连测试
        local latency=$(test_direct_latency "$server" "$port")
        echo "$latency|-1"
        return
    fi
    
    # 启动xray
    local log_file="$TEMP_DIR/xray_$$.log"
    xray -c "$config_file" > "$log_file" 2>&1 &
    local xray_pid=$!
    
    # 等待启动
    sleep 2
    
    # 检查xray是否启动成功
    if ! kill -0 "$xray_pid" 2>/dev/null; then
        log_warning "Xray启动失败，使用直连测试"
        local latency=$(test_direct_latency "$server" "$port")
        echo "$latency|-1"
        return
    fi
    
    # 测试延迟
    local latency=$(test_proxy_latency)
    local speed=$(test_proxy_speed)
    
    # 停止xray
    kill "$xray_pid" 2>/dev/null || true
    sleep 1
    
    # 清理文件
    rm -f "$config_file" "$log_file"
    
    echo "$latency|$speed"
}

# 直连延迟测试
test_direct_latency() {
    local server="$1"
    local port="$2"
    
    # 使用nc或telnet测试TCP连接
    if command -v nc >/dev/null 2>&1; then
        local start_time=$(date +%s%N)
        if timeout 5 nc -z "$server" "$port" 2>/dev/null; then
            local end_time=$(date +%s%N)
            local latency=$(( (end_time - start_time) / 1000000 ))
            echo "$latency"
        else
            echo "-1"
        fi
    else
        # 使用ping作为备选
        local ping_result=$(ping -c 1 -W 3 "$server" 2>/dev/null | grep "time=" | grep -o "time=[0-9.]*" | cut -d'=' -f2)
        if [[ -n "$ping_result" ]]; then
            echo "${ping_result%.*}"  # 去掉小数部分
        else
            echo "-1"
        fi
    fi
}

# 代理延迟测试
test_proxy_latency() {
    local test_urls=(
        "http://www.google.com/generate_204"
        "http://connectivitycheck.gstatic.com/generate_204"
        "https://www.cloudflare.com/cdn-cgi/trace"
    )
    
    for url in "${test_urls[@]}"; do
        local start_time=$(date +%s%N)
        if curl -s --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
                --connect-timeout 5 --max-time 10 \
                -o /dev/null "$url" 2>/dev/null; then
            local end_time=$(date +%s%N)
            local latency=$(( (end_time - start_time) / 1000000 ))
            echo "$latency"
            return
        fi
    done
    
    echo "-1"
}

# 代理速度测试
test_proxy_speed() {
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
                local speed=$(( (result * 8) / (duration * 1000000) ))
                echo "$speed"
                return
            fi
        fi
    done
    
    echo "-1"
}

# 主函数
main() {
    log_info "=== SubCheck 简化版测速工具 ==="
    log_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    setup_temp_dir
    
    if [[ ! -f "$SUBSCRIPTION_FILE" ]]; then
        log_error "订阅文件不存在: $SUBSCRIPTION_FILE"
        exit 1
    fi
    
    # 初始化结果文件
    echo "# SubCheck 测试结果 - $(date '+%Y-%m-%d %H:%M:%S')" > "$RESULTS_FILE"
    echo "# 格式: 节点名称|服务器|端口|协议|延迟(ms)|速度(Mbps)|状态" >> "$RESULTS_FILE"
    
    local total_nodes=0
    local success_nodes=0
    local tested_nodes=0
    
    # 读取订阅文件
    while IFS= read -r subscription_url; do
        [[ -z "$subscription_url" ]] && continue
        [[ "$subscription_url" == \#* ]] && continue
        
        log_info "处理订阅: $subscription_url"
        
        local content=$(fetch_subscription "$subscription_url")
        if [[ -z "$content" ]]; then
            log_warning "无法获取订阅内容: $subscription_url"
            continue
        fi
        
        # 尝试Base64解码
        if [[ "$content" != *"vless://"* && "$content" != *"vmess://"* ]]; then
            content=$(decode_base64 "$content")
        fi
        
        # 解析节点
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            
            total_nodes=$((total_nodes + 1))
            
            # 限制测试节点数量
            if [[ "$tested_nodes" -ge 10 ]]; then
                log_info "已测试10个节点，停止测试"
                break 2
            fi
            
            local node_info=""
            if [[ "$line" == vless://* ]]; then
                node_info=$(parse_vless "$line")
            elif [[ "$line" == vmess://* ]]; then
                node_info=$(parse_vmess "$line")
            fi
            
            if [[ -n "$node_info" ]]; then
                tested_nodes=$((tested_nodes + 1))
                
                # 解析节点信息
                IFS='|' read -r name server port protocol uuid <<< "$node_info"
                
                # 测试节点
                local test_result=$(test_node_connectivity "$name" "$server" "$port" "$protocol" "$uuid")
                IFS='|' read -r latency speed <<< "$test_result"
                
                local status="失败"
                if [[ "$latency" != "-1" ]]; then
                    success_nodes=$((success_nodes + 1))
                    status="成功"
                    log_success "节点可用: $name - 延迟: ${latency}ms"
                else
                    log_warning "节点不可用: $name"
                fi
                
                # 记录结果
                echo "$name|$server|$port|$protocol|$latency|$speed|$status" >> "$RESULTS_FILE"
            fi
            
        done <<< "$content"
        
    done < "$SUBSCRIPTION_FILE"
    
    # 显示摘要
    echo -e "\n${YELLOW}=== 测试摘要 ===${NC}"
    echo "发现节点: $total_nodes"
    echo "测试节点: $tested_nodes"
    echo "成功节点: $success_nodes"
    echo "成功率: $(( success_nodes * 100 / tested_nodes ))%" 2>/dev/null || echo "成功率: 0%"
    echo "结果文件: $RESULTS_FILE"
    
    # 显示最佳节点
    if [[ "$success_nodes" -gt 0 ]]; then
        echo -e "\n${GREEN}=== 可用节点 ===${NC}"
        grep "|成功$" "$RESULTS_FILE" | head -5 | while IFS='|' read -r name server port protocol latency speed status; do
            echo "  $name ($server:$port) - 延迟: ${latency}ms"
        done
    fi
    
    log_success "测试完成!"
}

# 执行主函数
main "$@"