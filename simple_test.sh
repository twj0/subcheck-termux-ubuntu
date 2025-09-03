#!/bin/bash

# 简化测试脚本 - 不依赖Xray进行基本连通性测试

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 解析VMess节点
parse_vmess() {
    local line="$1"
    local config="${line#vmess://}"
    local decoded=$(echo "$config" | base64 -d 2>/dev/null || echo "")
    
    if [[ -n "$decoded" ]]; then
        # 使用Python解析JSON（如果可用）
        if command -v python3 >/dev/null 2>&1; then
            python3 -c "
import json, sys
try:
    data = json.loads('$decoded')
    print(f\"{data.get('add', '')},{data.get('port', '')},{data.get('ps', 'VMess')}\")
except:
    pass
" 2>/dev/null
        else
            # 简单文本解析
            local server=$(echo "$decoded" | grep -o '"add"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
            local port=$(echo "$decoded" | grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
            local name=$(echo "$decoded" | grep -o '"ps"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
            [[ -n "$server" && -n "$port" ]] && echo "$server,$port,${name:-VMess}"
        fi
    fi
}

# 解析VLESS节点
parse_vless() {
    local line="$1"
    local config="${line#vless://}"
    local uuid="${config%%@*}"
    local rest="${config#*@}"
    local server_port="${rest%%\?*}"
    local server="${server_port%%:*}"
    local port="${server_port#*:}"
    local name=""
    
    if [[ "$line" == *"#"* ]]; then
        name="${line##*#}"
        name=$(echo "$name" | sed 's/%20/ /g; s/%21/!/g; s/%23/#/g')
    fi
    
    [[ -n "$server" && -n "$port" ]] && echo "$server,$port,${name:-VLESS}"
}

# 测试端口连通性
test_port() {
    local server="$1" port="$2" name="$3"
    
    info "测试 $name ($server:$port)"
    
    # 使用多种方法测试连通性
    local methods=()
    
    # 方法1: netcat
    if command -v nc >/dev/null 2>&1; then
        methods+=("nc")
    fi
    
    # 方法2: telnet
    if command -v telnet >/dev/null 2>&1; then
        methods+=("telnet")
    fi
    
    # 方法3: curl
    if command -v curl >/dev/null 2>&1; then
        methods+=("curl")
    fi
    
    # 方法4: timeout + bash
    methods+=("bash")
    
    for method in "${methods[@]}"; do
        local result=false
        local latency=-1
        
        case "$method" in
            "nc")
                local start_time=$(date +%s%N)
                if timeout 5 nc -z "$server" "$port" 2>/dev/null; then
                    local end_time=$(date +%s%N)
                    latency=$(( (end_time - start_time) / 1000000 ))
                    result=true
                fi
                ;;
            "telnet")
                if echo "quit" | timeout 5 telnet "$server" "$port" 2>/dev/null | grep -q "Connected"; then
                    result=true
                fi
                ;;
            "curl")
                local start_time=$(date +%s%N)
                if curl -s --connect-timeout 5 --max-time 5 "http://$server:$port" >/dev/null 2>&1; then
                    local end_time=$(date +%s%N)
                    latency=$(( (end_time - start_time) / 1000000 ))
                    result=true
                fi
                ;;
            "bash")
                local start_time=$(date +%s%N)
                if timeout 5 bash -c "exec 3<>/dev/tcp/$server/$port" 2>/dev/null; then
                    local end_time=$(date +%s%N)
                    latency=$(( (end_time - start_time) / 1000000 ))
                    result=true
                    exec 3>&- 2>/dev/null || true
                fi
                ;;
        esac
        
        if [[ "$result" == "true" ]]; then
            if [[ $latency -gt 0 ]]; then
                success "$name - 连通 (${latency}ms) [$method]"
            else
                success "$name - 连通 [$method]"
            fi
            echo "$server,$port,$name,success,$latency,$method"
            return 0
        fi
    done
    
    warn "$name - 连接失败"
    echo "$server,$port,$name,failed,-1,none"
    return 1
}

# 主测试函数
run_simple_test() {
    info "开始简化连通性测试"
    
    if [[ ! -f "subscription.txt" ]]; then
        error "订阅文件不存在"
        exit 1
    fi
    
    local total=0 success_count=0 tested=0
    local max_test=10  # 限制测试数量
    
    echo "server,port,name,status,latency,method" > "simple_results.csv"
    
    # 处理订阅
    while IFS= read -r sub_url && [[ $tested -lt $max_test ]]; do
        [[ -z "$sub_url" || "$sub_url" == \#* ]] && continue
        
        info "处理订阅: $(basename "$sub_url")"
        
        # 获取订阅内容
        local content=""
        if [[ "$sub_url" == http* ]]; then
            content=$(curl -s --connect-timeout 10 --max-time 30 "$sub_url" 2>/dev/null || echo "")
        else
            content=$(cat "$sub_url" 2>/dev/null || echo "")
        fi
        
        [[ -z "$content" ]] && continue
        
        # Base64解码
        if [[ "$content" != *"://"* ]]; then
            content=$(echo "$content" | base64 -d 2>/dev/null || echo "$content")
        fi
        
        # 解析并测试节点
        while IFS= read -r line && [[ $tested -lt $max_test ]]; do
            [[ -z "$line" ]] && continue
            
            local node_info=""
            if [[ "$line" == vmess://* ]]; then
                node_info=$(parse_vmess "$line")
            elif [[ "$line" == vless://* ]]; then
                node_info=$(parse_vless "$line")
            fi
            
            if [[ -n "$node_info" ]]; then
                tested=$((tested + 1))
                total=$((total + 1))
                
                IFS=',' read -r server port name <<< "$node_info"
                local result=$(test_port "$server" "$port" "$name")
                echo "$result" >> "simple_results.csv"
                
                [[ "$result" == *",success,"* ]] && success_count=$((success_count + 1))
            fi
            
        done <<< "$content"
        
        # 只测试第一个订阅
        break
        
    done < "subscription.txt"
    
    # 显示结果
    echo -e "\n${YELLOW}=== 简化测试结果 ===${NC}"
    echo "测试节点: $total"
    echo "连通节点: $success_count"
    [[ $total -gt 0 ]] && echo "连通率: $(( success_count * 100 / total ))%"
    
    if [[ $success_count -gt 0 ]]; then
        echo -e "\n${GREEN}=== 可连通节点 ===${NC}"
        grep ",success," "simple_results.csv" | head -5 | while IFS=',' read -r server port name status latency method; do
            if [[ $latency -gt 0 ]]; then
                echo "  $name ($server:$port) - ${latency}ms [$method]"
            else
                echo "  $name ($server:$port) [$method]"
            fi
        done
    fi
    
    success "简化测试完成，结果保存到 simple_results.csv"
}

# 运行测试
run_simple_test