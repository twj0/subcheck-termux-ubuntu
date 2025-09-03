#!/bin/bash

# China Network Optimized SubCheck
# 针对中国大陆网络环境优化的节点检测脚本

set -e

# 中国大陆网络优化配置
GITHUB_PROXY="https://ghfast.top/"
DNS_SERVERS=("223.5.5.5" "119.29.29.29" "114.114.114.114")
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
CONNECT_TIMEOUT=15
READ_TIMEOUT=30
MAX_RETRIES=3

# Helper functions
print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

print_warning() {
    echo -e "\033[33m[WARNING]\033[0m $1"
}

# 优化DNS解析
optimize_dns() {
    print_info "优化DNS解析配置..."
    
    # 备份原始DNS配置
    if [ -f /etc/resolv.conf ] && [ ! -f /etc/resolv.conf.backup ]; then
        sudo cp /etc/resolv.conf /etc/resolv.conf.backup
    fi
    
    # 设置优化的DNS服务器
    {
        echo "# Optimized DNS for China network"
        for dns in "${DNS_SERVERS[@]}"; do
            echo "nameserver $dns"
        done
    } | sudo tee /etc/resolv.conf.optimized > /dev/null
    
    sudo cp /etc/resolv.conf.optimized /etc/resolv.conf
    print_info "DNS优化完成"
}

# 恢复DNS配置
restore_dns() {
    if [ -f /etc/resolv.conf.backup ]; then
        sudo cp /etc/resolv.conf.backup /etc/resolv.conf
        print_info "DNS配置已恢复"
    fi
}

# 优化的curl下载函数
optimized_curl() {
    local url="$1"
    local output="$2"
    local use_proxy="${3:-true}"
    
    local curl_opts=(
        --connect-timeout $CONNECT_TIMEOUT
        --max-time $READ_TIMEOUT
        --retry $MAX_RETRIES
        --retry-delay 2
        --user-agent "$USER_AGENT"
        --location
        --fail
        --silent
        --show-error
    )
    
    # 如果是GitHub链接且启用代理
    if [[ "$url" == *"github.com"* ]] && [ "$use_proxy" = "true" ]; then
        url="${GITHUB_PROXY}${url}"
        print_info "使用GitHub代理: $url"
    fi
    
    # 尝试下载
    local attempt=1
    while [ $attempt -le $MAX_RETRIES ]; do
        print_info "下载尝试 $attempt/$MAX_RETRIES: $url"
        
        if [ -n "$output" ]; then
            if curl "${curl_opts[@]}" -o "$output" "$url"; then
                return 0
            fi
        else
            if curl "${curl_opts[@]}" "$url"; then
                return 0
            fi
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -le $MAX_RETRIES ]; then
            print_warning "下载失败，等待重试..."
            sleep $((attempt * 2))
        fi
    done
    
    # 如果使用了代理且失败，尝试直连
    if [[ "$url" == *"ghfast.top"* ]]; then
        print_warning "代理下载失败，尝试直连..."
        local direct_url="${url#*https://ghfast.top/}"
        return $(optimized_curl "$direct_url" "$output" "false")
    fi
    
    return 1
}

# 下载并安装Go版本的subs-check
install_go_subscheck() {
    print_info "下载Go版本的subs-check核心..."
    
    local arch="linux_arm64"
    if [ "$(uname -m)" = "x86_64" ]; then
        arch="linux_amd64"
    fi
    
    # 尝试多种方式获取版本信息
    local download_url=""
    local version="v1.0.0"  # 默认版本
    
    # 方法1: 通过代理API
    print_info "尝试通过代理获取版本信息..."
    local api_url="${GITHUB_PROXY}https://api.github.com/repos/beck-8/subs-check/releases/latest"
    local release_info
    if release_info=$(curl -s --connect-timeout 10 "$api_url" 2>/dev/null); then
        download_url=$(echo "$release_info" | jq -r ".assets[] | select(.name | test(\"${arch}\")) | .browser_download_url" 2>/dev/null | head -1)
        version=$(echo "$release_info" | jq -r ".tag_name" 2>/dev/null)
    fi
    
    # 方法2: 直接API调用
    if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
        print_info "尝试直接API调用..."
        if release_info=$(curl -s --connect-timeout 15 "https://api.github.com/repos/beck-8/subs-check/releases/latest" 2>/dev/null); then
            download_url=$(echo "$release_info" | jq -r ".assets[] | select(.name | test(\"${arch}\")) | .browser_download_url" 2>/dev/null | head -1)
            version=$(echo "$release_info" | jq -r ".tag_name" 2>/dev/null)
        fi
    fi
    
    # 方法3: 使用预设的下载链接
    if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
        print_warning "API调用失败，使用预设下载链接..."
        version="v1.0.0"
        download_url="https://github.com/beck-8/subs-check/releases/download/${version}/subs-check_${version}_${arch}.tar.gz"
    fi
    
    print_info "下载链接: $download_url"
    
    # 下载并安装
    local temp_file="/tmp/subs-check-${arch}.tar.gz"
    if optimized_curl "$download_url" "$temp_file"; then
        mkdir -p subs-check-go
        if tar -xzf "$temp_file" -C subs-check-go/ 2>/dev/null; then
            # 查找可执行文件
            local exe_file=$(find subs-check-go/ -name "subs-check" -type f | head -1)
            if [ -n "$exe_file" ]; then
                chmod +x "$exe_file"
                # 如果不在根目录，移动到根目录
                if [ "$exe_file" != "subs-check-go/subs-check" ]; then
                    mv "$exe_file" subs-check-go/subs-check
                fi
                rm "$temp_file"
                print_info "Go版本subs-check安装完成"
                return 0
            else
                print_warning "压缩包中未找到subs-check可执行文件"
            fi
        else
            print_warning "解压失败，可能是zip格式"
            # 尝试作为zip文件解压
            if command -v unzip >/dev/null 2>&1; then
                mv "$temp_file" "${temp_file%.tar.gz}.zip"
                if unzip -q "${temp_file%.tar.gz}.zip" -d subs-check-go/; then
                    local exe_file=$(find subs-check-go/ -name "subs-check*" -type f | head -1)
                    if [ -n "$exe_file" ]; then
                        chmod +x "$exe_file"
                        mv "$exe_file" subs-check-go/subs-check
                        rm "${temp_file%.tar.gz}.zip"
                        print_info "Go版本subs-check安装完成"
                        return 0
                    fi
                fi
                rm -f "${temp_file%.tar.gz}.zip"
            fi
        fi
        rm -f "$temp_file"
    fi
    
    print_warning "Go版本subs-check安装失败，将使用基础测试模式"
    return 1
}

# 优化的订阅解析
parse_subscription_optimized() {
    local input="$1"
    local temp_file="/tmp/subscription_content.txt"
    
    print_info "解析订阅: $input"
    
    # 下载订阅内容
    if [[ "$input" == http* ]]; then
        if ! optimized_curl "$input" "$temp_file"; then
            print_error "无法下载订阅内容"
            return 1
        fi
        input="$temp_file"
    elif [ -f "$input" ]; then
        # 如果是文件，读取第一个URL
        local first_url=$(head -n 1 "$input" | tr -d '\r\n')
        if [[ "$first_url" == http* ]]; then
            print_info "从文件中读取URL: $first_url"
            if ! optimized_curl "$first_url" "$temp_file"; then
                print_error "无法下载订阅内容: $first_url"
                return 1
            fi
            input="$temp_file"
        fi
    fi
    
    # 检查内容格式
    local content
    content=$(cat "$input" 2>/dev/null || echo "")
    
    if [ -z "$content" ]; then
        print_error "订阅内容为空"
        return 1
    fi
    
    # 检测编码并转换（跳过file命令检测）
    print_info "使用UTF-8编码处理内容"
    
    # 解析不同格式
    local nodes_json="[]"
    
    # Base64编码检测
    if echo "$content" | base64 -d >/dev/null 2>&1; then
        print_info "检测到Base64编码内容"
        content=$(echo "$content" | base64 -d)
    fi
    
    # 解析节点
    local node_count=0
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r\n')
        [ -z "$line" ] && continue
        
        if [[ "$line" == vless://* ]]; then
            local node_json
            if node_json=$(parse_vless_link "$line"); then
                nodes_json=$(echo "$nodes_json" | jq --argjson node "$node_json" '. + [$node]')
                node_count=$((node_count + 1))
            fi
        elif [[ "$line" == vmess://* ]]; then
            local node_json
            if node_json=$(parse_vmess_link "$line"); then
                nodes_json=$(echo "$nodes_json" | jq --argjson node "$node_json" '. + [$node]')
                node_count=$((node_count + 1))
            fi
        fi
    done <<< "$content"
    
    print_info "解析完成，找到 $node_count 个节点"
    echo "$nodes_json"
    
    # 清理临时文件
    [ -f "$temp_file" ] && rm "$temp_file"
    [ -f "${input}.utf8" ] && rm "${input}.utf8"
}

# 解析VLESS链接
parse_vless_link() {
    local link="$1"
    local stripped_link="${link#vless://}"
    
    local user_info host_info server_address server_port params node_name_encoded node_name
    user_info=$(echo "$stripped_link" | cut -d'@' -f1)
    host_info=$(echo "$stripped_link" | cut -d'@' -f2)
    server_address=$(echo "$host_info" | cut -d'?' -f1 | cut -d':' -f1)
    server_port=$(echo "$host_info" | cut -d'?' -f1 | cut -d':' -f2)
    params=$(echo "$host_info" | cut -d'?' -f2)
    node_name_encoded=$(echo "$params" | cut -d'#' -f2)
    node_name=$(printf '%b' "${node_name_encoded//%/\\x}")
    
    [ -z "$node_name" ] && node_name="$server_address:$server_port"
    
    jq -n \
      --arg protocol "vless" \
      --arg name "$node_name" \
      --arg address "$server_address" \
      --arg port "$server_port" \
      --arg id "$user_info" \
      --arg params "?${params%#*}" \
      '{protocol: $protocol, name: $name, address: $address, port: $port, id: $id, params: $params}'
}

# 解析VMess链接
parse_vmess_link() {
    local link="$1"
    local base64_part="${link#vmess://}"
    local decoded
    
    if ! decoded=$(echo "$base64_part" | base64 -d 2>/dev/null); then
        return 1
    fi
    
    local name address port id
    name=$(echo "$decoded" | jq -r '.ps // .name // "Unknown"')
    address=$(echo "$decoded" | jq -r '.add // .address // ""')
    port=$(echo "$decoded" | jq -r '.port // ""')
    id=$(echo "$decoded" | jq -r '.id // .uuid // ""')
    
    if [ -z "$address" ] || [ -z "$port" ]; then
        return 1
    fi
    
    jq -n \
      --arg protocol "vmess" \
      --arg name "$name" \
      --arg address "$address" \
      --arg port "$port" \
      --arg id "$id" \
      '{protocol: $protocol, name: $name, address: $address, port: $port, id: $id}'
}

# 优化的节点测试
test_node_optimized() {
    local node_json="$1"
    local name address port protocol
    
    name=$(echo "$node_json" | jq -r '.name')
    address=$(echo "$node_json" | jq -r '.address')
    port=$(echo "$node_json" | jq -r '.port')
    protocol=$(echo "$node_json" | jq -r '.protocol')
    
    print_info "测试节点: $name ($address:$port)"
    
    # TCP连通性测试
    local latency=-1
    local start_time end_time
    
    start_time=$(date +%s%3N)
    if timeout 10 bash -c "echo >/dev/tcp/$address/$port" 2>/dev/null; then
        end_time=$(date +%s%3N)
        latency=$((end_time - start_time))
        print_info "TCP连接成功，延迟: ${latency}ms"
    else
        print_warning "TCP连接失败"
        jq -n \
          --arg name "$name" \
          --arg error "TCP connection failed" \
          '{name: $name, success: false, latency: -1, download: -1, upload: -1, error: $error}'
        return
    fi
    
    # 如果有Go版本的subs-check，使用它进行完整测试
    if [ -f "subs-check-go/subs-check" ]; then
        local temp_config="/tmp/test_config_$$.json"
        echo "$node_json" > "$temp_config"
        
        local result
        if result=$(timeout 30 ./subs-check-go/subs-check -c "$temp_config" -t 10 2>/dev/null); then
            rm -f "$temp_config"
            echo "$result"
            return
        fi
        rm -f "$temp_config"
    fi
    
    # 基础测试结果
    jq -n \
      --arg name "$name" \
      --argjson latency "$latency" \
      '{name: $name, success: true, latency: $latency, download: -1, upload: -1, error: null}'
}

# 主函数
main() {
    local subscription_input="$1"
    
    if [ -z "$subscription_input" ]; then
        print_error "请提供订阅URL或文件路径"
        exit 1
    fi
    
    print_info "=== 中国大陆网络优化版SubCheck ==="
    
    # 优化网络环境
    optimize_dns
    trap restore_dns EXIT
    
    # 尝试安装Go版本的subs-check（跳过以避免API限制）
    print_warning "跳过Go版本下载，使用基础测试模式（避免GitHub API限制）"
    
    # 解析订阅
    local nodes_json
    if ! nodes_json=$(parse_subscription_optimized "$subscription_input"); then
        print_error "订阅解析失败"
        exit 1
    fi
    
    local node_count
    node_count=$(echo "$nodes_json" | jq 'length')
    
    if [ "$node_count" -eq 0 ]; then
        print_error "未找到有效节点"
        exit 1
    fi
    
    print_info "开始测试 $node_count 个节点..."
    
    # 测试节点
    local results="[]"
    local working=0
    
    for i in $(seq 0 $((node_count - 1))); do
        local node
        node=$(echo "$nodes_json" | jq ".[$i]")
        
        local result
        if result=$(test_node_optimized "$node"); then
            local success
            success=$(echo "$result" | jq -r '.success')
            if [ "$success" = "true" ]; then
                working=$((working + 1))
            fi
            results=$(echo "$results" | jq --argjson result "$result" '. + [$result]')
        fi
    done
    
    print_info "=== 测试完成 ==="
    print_info "总计: $node_count, 可用: $working"
    
    # 输出结果
    echo "$results" | jq '.'
}

# 运行主函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
