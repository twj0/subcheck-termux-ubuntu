#!/bin/bash

# 简化版中国网络优化测试脚本
# 专注于基本功能，避免复杂依赖

set -e

print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

print_warning() {
    echo -e "\033[33m[WARNING]\033[0m $1"
}

# 简化的curl下载函数
simple_curl() {
    local url="$1"
    local output="$2"
    
    # 如果是GitHub链接，使用代理
    if [[ "$url" == *"github.com"* ]] || [[ "$url" == *"githubusercontent.com"* ]]; then
        url="https://ghfast.top/${url}"
        print_info "使用GitHub代理下载"
    fi
    
    if [ -n "$output" ]; then
        curl -L -s --connect-timeout 10 --max-time 30 -o "$output" "$url"
    else
        curl -L -s --connect-timeout 10 --max-time 30 "$url"
    fi
}

# 解析VLESS链接
parse_vless() {
    local link="$1"
    local stripped="${link#vless://}"
    
    local user_info host_info server_address server_port params node_name
    user_info=$(echo "$stripped" | cut -d'@' -f1)
    host_info=$(echo "$stripped" | cut -d'@' -f2)
    
    # 解析地址和端口
    local addr_port=$(echo "$host_info" | cut -d'?' -f1)
    server_address=$(echo "$addr_port" | cut -d':' -f1)
    server_port=$(echo "$addr_port" | cut -d':' -f2)
    
    # 验证端口是否为数字
    if ! [[ "$server_port" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    params=$(echo "$host_info" | cut -d'?' -f2)
    
    # 提取节点名称
    if [[ "$params" == *"#"* ]]; then
        node_name=$(echo "$params" | cut -d'#' -f2 | sed 's/%20/ /g' | sed 's/%2B/+/g' | sed 's/%E2%80%8B//g')
    else
        node_name="$server_address:$server_port"
    fi
    
    # 清理节点名称中的特殊字符
    node_name=$(echo "$node_name" | tr -d '\u200B\u200C\u200D\uFEFF')
    
    echo "{\"name\":\"$node_name\",\"address\":\"$server_address\",\"port\":\"$server_port\",\"protocol\":\"vless\"}"
}

# 解析VMess链接
parse_vmess() {
    local link="$1"
    local base64_part="${link#vmess://}"
    
    if ! decoded=$(echo "$base64_part" | base64 -d 2>/dev/null); then
        return 1
    fi
    
    local name address port
    name=$(echo "$decoded" | grep -o '"ps":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "Unknown")
    address=$(echo "$decoded" | grep -o '"add":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
    port=$(echo "$decoded" | grep -o '"port":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
    
    if [ -z "$address" ] || [ -z "$port" ]; then
        return 1
    fi
    
    echo "{\"name\":\"$name\",\"address\":\"$address\",\"port\":\"$port\",\"protocol\":\"vmess\"}"
}

# 测试TCP连接
test_tcp_connection() {
    local address="$1"
    local port="$2"
    local timeout=5
    
    # 验证端口是否为数字
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "-1"
        return 1
    fi
    
    local start_time end_time latency
    start_time=$(date +%s%3N)
    
    if timeout $timeout bash -c "echo >/dev/tcp/$address/$port" 2>/dev/null; then
        end_time=$(date +%s%3N)
        latency=$((end_time - start_time))
        echo "$latency"
        return 0
    else
        echo "-1"
        return 1
    fi
}

# 主函数
main() {
    local input="$1"
    
    if [ -z "$input" ]; then
        print_error "用法: $0 <订阅URL或文件>"
        exit 1
    fi
    
    print_info "=== 简化版中国网络优化测试 ==="
    
    # 处理输入
    local temp_file="/tmp/subscription_$$.txt"
    
    if [[ "$input" == http* ]]; then
        print_info "下载订阅: $input"
        if ! simple_curl "$input" "$temp_file"; then
            print_error "下载失败"
            exit 1
        fi
    elif [ -f "$input" ]; then
        # 读取文件中的第一个URL
        local first_url=$(head -n 1 "$input" | tr -d '\r\n')
        if [[ "$first_url" == http* ]]; then
            print_info "从文件读取URL: $first_url"
            if ! simple_curl "$first_url" "$temp_file"; then
                print_error "下载失败: $first_url"
                exit 1
            fi
        else
            cp "$input" "$temp_file"
        fi
    else
        print_error "无效输入: $input"
        exit 1
    fi
    
    # 读取内容
    local content
    content=$(cat "$temp_file" 2>/dev/null || echo "")
    
    if [ -z "$content" ]; then
        print_error "内容为空"
        rm -f "$temp_file"
        exit 1
    fi
    
    # 检查是否为Base64编码
    if echo "$content" | base64 -d >/dev/null 2>&1; then
        print_info "检测到Base64编码，解码中..."
        content=$(echo "$content" | base64 -d)
    fi
    
    # 解析节点
    local node_count=0
    local working_count=0
    local results="[]"
    
    print_info "开始解析和测试节点..."
    
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r\n')
        [ -z "$line" ] && continue
        
        local node_json=""
        
        if [[ "$line" == vless://* ]]; then
            node_json=$(parse_vless "$line" 2>/dev/null || echo "")
        elif [[ "$line" == vmess://* ]]; then
            node_json=$(parse_vmess "$line" 2>/dev/null || echo "")
        fi
        
        if [ -n "$node_json" ]; then
            node_count=$((node_count + 1))
            
            local name address port
            name=$(echo "$node_json" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
            address=$(echo "$node_json" | grep -o '"address":"[^"]*"' | cut -d'"' -f4)
            port=$(echo "$node_json" | grep -o '"port":"[^"]*"' | cut -d'"' -f4)
            
            # 验证地址和端口
            if [ -z "$address" ] || [ -z "$port" ]; then
                echo "[$node_count] 跳过无效节点: $name"
                continue
            fi
            
            echo -n "[$node_count] 测试 $name ($address:$port)... "
            
            local latency
            latency=$(test_tcp_connection "$address" "$port")
            
            if [ "$latency" != "-1" ]; then
                working_count=$((working_count + 1))
                echo "✅ ${latency}ms"
                local result="{\"name\":\"$name\",\"address\":\"$address\",\"port\":\"$port\",\"latency\":$latency,\"success\":true}"
            else
                echo "❌ 连接失败"
                local result="{\"name\":\"$name\",\"address\":\"$address\",\"port\":\"$port\",\"latency\":-1,\"success\":false}"
            fi
            
            # 添加到结果中（简化JSON处理）
            if [ "$results" = "[]" ]; then
                results="[$result]"
            else
                results="${results%]}, $result]"
            fi
        fi
        
        # 限制测试数量避免过长
        if [ $node_count -ge 10 ]; then
            print_warning "已测试10个节点，停止测试"
            break
        fi
        
    done <<< "$content"
    
    # 清理临时文件
    rm -f "$temp_file"
    
    # 输出结果
    print_info "=== 测试完成 ==="
    print_info "总节点数: $node_count"
    print_info "可用节点: $working_count"
    
    if [ $working_count -gt 0 ]; then
        print_info "✅ 测试成功，找到可用节点"
        echo ""
        echo "JSON结果:"
        echo "$results"
        exit 0
    else
        print_error "❌ 未找到可用节点"
        exit 1
    fi
}

# 运行主函数
main "$@"
