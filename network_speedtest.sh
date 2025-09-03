#!/bin/bash

# 网络测速工具 - 针对中国大陆网络优化
echo "=== 网络测速工具启动 ==="
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"

# 测试服务器
TEST_SERVERS=(
    "http://www.google.com/gen_204"
    "http://connectivitycheck.gstatic.com/generate_204"
    "http://www.baidu.com"
)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 测量延迟函数
measure_latency() {
    local url=$1
    echo -e "${BLUE}测试延迟: $url${NC}"
    
    result=$(curl -o /dev/null -s -w "time_connect:%{time_connect}\n" \
              --connect-timeout 5 --max-time 5 "$url" 2>&1)
    
    if echo "$result" | grep -q "time_connect:"; then
        latency=$(echo "$result" | grep "time_connect:" | cut -d':' -f2)
        latency_ms=$(echo "scale=2; $latency * 1000" | bc)
        echo -e "${GREEN}延迟: ${latency_ms}ms${NC}"
        return 0
    else
        echo -e "${RED}失败: $(echo $result | head -1)${NC}"
        return 1
    fi
}

# 主测试流程
main() {
    echo -e "\n${YELLOW}=== 网络连通性测试 ===${NC}"
    for server in "${TEST_SERVERS[@]}"; do
        measure_latency "$server"
    done
    echo -e "\n${YELLOW}=== 测试完成 ===${NC}"
}

main