#!/bin/bash

# 超级简化测试脚本 - 仅测试基本连通性

print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

# 简单的TCP测试
test_tcp() {
    local host="$1"
    local port="$2"
    timeout 3 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
}

# 获取订阅URL
FIRST_URL=$(head -n 1 subscription.txt 2>/dev/null | tr -d '\r\n')

if [ -z "$FIRST_URL" ]; then
    print_error "无法读取subscription.txt"
    exit 1
fi

print_info "=== 超级简化测试 ==="
print_info "URL: $FIRST_URL"

# 下载内容
print_info "下载订阅内容..."
CONTENT=$(curl -L -s --connect-timeout 10 "$FIRST_URL" 2>/dev/null)

if [ -z "$CONTENT" ]; then
    print_error "下载失败"
    exit 1
fi

# 检查Base64
if echo "$CONTENT" | base64 -d >/dev/null 2>&1; then
    print_info "解码Base64..."
    CONTENT=$(echo "$CONTENT" | base64 -d)
fi

# 计算节点数
NODE_COUNT=$(echo "$CONTENT" | grep -c "vless://\|vmess://" || echo "0")
print_info "找到 $NODE_COUNT 个节点"

if [ "$NODE_COUNT" -eq 0 ]; then
    print_error "未找到节点"
    exit 1
fi

# 测试前3个节点的连通性
count=0
while IFS= read -r line && [ $count -lt 3 ]; do
    if [[ "$line" == vless://* ]]; then
        # 简单解析VLESS
        stripped="${line#vless://}"
        host_info=$(echo "$stripped" | cut -d'@' -f2)
        addr_port=$(echo "$host_info" | cut -d'?' -f1)
        host=$(echo "$addr_port" | cut -d':' -f1)
        port=$(echo "$addr_port" | cut -d':' -f2)
        
        if [[ "$port" =~ ^[0-9]+$ ]]; then
            count=$((count + 1))
            echo -n "[$count] 测试 $host:$port... "
            if test_tcp "$host" "$port"; then
                echo "✅"
            else
                echo "❌"
            fi
        fi
    fi
done <<< "$CONTENT"

print_info "测试完成!"
