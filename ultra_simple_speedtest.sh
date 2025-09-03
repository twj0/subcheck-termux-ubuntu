#!/bin/bash

# 超级简化版测速脚本
# 专为移动设备优化

set -e

# 配置
MAX_NODES=10
TIMEOUT=5
RESULTS_FILE="simple_results.txt"

# 颜色
G='\033[0;32m'  # 绿色
R='\033[0;31m'  # 红色
Y='\033[1;33m'  # 黄色
B='\033[0;34m'  # 蓝色
NC='\033[0m'    # 无颜色

# 简单日志
log() { echo -e "${B}[$(date '+%H:%M:%S')]${NC} $1"; }
ok() { echo -e "${G}✓${NC} $1"; }
fail() { echo -e "${R}✗${NC} $1"; }
warn() { echo -e "${Y}!${NC} $1"; }

# 解析VMess（超简化）
parse_vmess() {
    local url="$1"
    local config="${url#vmess://}"
    local decoded=$(echo "$config" | base64 -d 2>/dev/null || echo "$config")
    
    # 提取关键信息
    local server=$(echo "$decoded" | grep -o '"add"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    local port=$(echo "$decoded" | grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
    local name=$(echo "$decoded" | grep -o '"ps"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    
    [[ -n "$server" && -n "$port" ]] && echo "${name:-VMess}|$server|$port"
}

# 解析VLESS（超简化）
parse_vless() {
    local url="$1"
    local config="${url#vless://}"
    local server_part="${config#*@}"
    local server_info="${server_part%%\?*}"
    local server="${server_info%%:*}"
    local port="${server_info#*:}"
    local name="${url##*#}"
    
    [[ -n "$server" && -n "$port" ]] && echo "${name:-VLESS}|$server|$port"
}

# 测试连通性（超简化）
test_node() {
    local name="$1"
    local server="$2"
    local port="$3"
    
    # 使用nc测试TCP连接
    if timeout $TIMEOUT nc -z "$server" "$port" 2>/dev/null; then
        # 测试延迟
        local start=$(date +%s%N)
        if timeout $TIMEOUT nc -z "$server" "$port" 2>/dev/null; then
            local end=$(date +%s%N)
            local latency=$(( (end - start) / 1000000 ))
            echo "$latency|成功"
        else
            echo "-1|失败"
        fi
    else
        echo "-1|失败"
    fi
}

# 主函数
main() {
    echo -e "${B}=== SubCheck 超简版 ===${NC}"
    log "开始测速 (最多测试 $MAX_NODES 个节点)"
    
    # 初始化结果文件
    echo "# SubCheck 测试结果 - $(date)" > "$RESULTS_FILE"
    
    local tested=0
    local success=0
    
    # 读取订阅
    while IFS= read -r line && [[ $tested -lt $MAX_NODES ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        
        # 获取订阅内容
        local content=""
        if [[ "$line" == http* ]]; then
            content=$(curl -s --connect-timeout 5 --max-time 10 "$line" 2>/dev/null || echo "")
            # 尝试Base64解码
            if [[ "$content" != *"vmess://"* && "$content" != *"vless://"* ]]; then
                content=$(echo "$content" | base64 -d 2>/dev/null || echo "$content")
            fi
        else
            content="$line"
        fi
        
        # 解析节点
        while IFS= read -r node_line && [[ $tested -lt $MAX_NODES ]]; do
            [[ -z "$node_line" ]] && continue
            
            local node_info=""
            if [[ "$node_line" == vmess://* ]]; then
                node_info=$(parse_vmess "$node_line")
            elif [[ "$node_line" == vless://* ]]; then
                node_info=$(parse_vless "$node_line")
            fi
            
            if [[ -n "$node_info" ]]; then
                tested=$((tested + 1))
                IFS='|' read -r name server port <<< "$node_info"
                
                log "测试 [$tested/$MAX_NODES] $name ($server:$port)"
                
                local result=$(test_node "$name" "$server" "$port")
                IFS='|' read -r latency status <<< "$result"
                
                if [[ "$status" == "成功" ]]; then
                    success=$((success + 1))
                    ok "$name - 延迟: ${latency}ms"
                else
                    fail "$name - 连接失败"
                fi
                
                # 记录结果
                echo "$name|$server|$port|$latency|$status" >> "$RESULTS_FILE"
            fi
        done <<< "$content"
        
    done < "subscription.txt" 2>/dev/null || {
        warn "subscription.txt 不存在，请添加订阅链接"
        exit 1
    }
    
    # 显示摘要
    echo
    echo -e "${Y}=== 测试摘要 ===${NC}"
    echo "测试节点: $tested"
    echo "成功节点: $success"
    [[ $tested -gt 0 ]] && echo "成功率: $(( success * 100 / tested ))%"
    
    # 显示最佳节点
    if [[ $success -gt 0 ]]; then
        echo -e "\n${G}=== 可用节点 ===${NC}"
        grep "|成功$" "$RESULTS_FILE" | head -5 | while IFS='|' read -r name server port latency status; do
            echo "  $name ($server:$port) - ${latency}ms"
        done
    fi
    
    echo -e "\n${B}结果已保存到: $RESULTS_FILE${NC}"
}

# 帮助信息
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "SubCheck 超简版测速工具"
    echo
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -h, --help    显示帮助信息"
    echo
    echo "文件:"
    echo "  subscription.txt    订阅链接文件"
    echo "  simple_results.txt  测试结果文件"
    echo
    exit 0
fi

# 执行主函数
main "$@"