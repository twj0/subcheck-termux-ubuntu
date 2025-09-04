#!/bin/bash

# SubCheck 一键安装脚本
# 适用于Termux Ubuntu环境

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 显示Logo
show_logo() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════╗"
    echo "║           SubCheck 测速工具           ║"
    echo "║        一键安装 & 一键测速            ║"
    echo "╚══════════════════════════════════════╝"
    echo -e "${NC}"
}

# 日志函数
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检测系统架构
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64) echo "64" ;;
        aarch64|arm64) echo "arm64-v8a" ;;
        armv7l) echo "arm32-v7a" ;;
        *) echo "64" ;;
    esac
}

# 快速安装依赖
install_deps() {
    log "安装基础依赖..."
    
    # 更新包管理器（静默）
    apt update -qq
    
    # 安装必要工具
    apt install -y curl wget jq bc netcat-openbsd python3 unzip python3-yaml >/dev/null 2>&1
    
    log "✓ 基础工具安装完成"
}

# 安装Xray（简化版）
install_xray() {
    log "安装Xray代理核心..."
    
    local arch=$(detect_arch)
    local version="1.8.4"
    local url="https://github.com/XTLS/Xray-core/releases/download/v${version}/Xray-linux-${arch}.zip"
    
    # 使用GitHub加速
    if ! curl -s --connect-timeout 3 "https://github.com" >/dev/null; then
        url="https://ghfast.top/${url}"
        log "使用GitHub加速下载"
    fi
    
    # 下载并安装
    cd /tmp
    if wget -q --timeout=30 "$url" -O xray.zip 2>/dev/null; then
        unzip -q xray.zip xray
        chmod +x xray
        mv xray /usr/local/bin/
        log "✓ Xray安装成功"
    else
        error "Xray下载失败，将使用直连模式"
        return 1
    fi
}

# 创建一键测速脚本
create_speedtest() {
    log "创建一键测速脚本..."
    
    cat > /usr/local/bin/speedtest << 'EOF'
#!/bin/bash
cd /root/subcheck/subcheck-termux-ubuntu
bash simple_subcheck.sh "$@"
EOF
    
    chmod +x /usr/local/bin/speedtest
    log "✓ 一键测速命令创建完成"
}

# 创建结果查看脚本
create_results() {
    log "创建结果查看脚本..."
    
    cat > /usr/local/bin/results << 'EOF'
#!/bin/bash
cd /root/subcheck/subcheck-termux-ubuntu
if [[ -f "simple_results.txt" ]]; then
    echo -e "\033[0;32m=== 最新测速结果 ===\033[0m"
    tail -20 simple_results.txt | grep -v "^#" | while IFS='|' read -r name server port protocol latency speed status; do
        if [[ "$status" == "成功" ]]; then
            echo -e "\033[0;32m✓\033[0m $name ($server:$port) - 延迟: ${latency}ms 速度: ${speed}Mbps"
        else
            echo -e "\033[0;31m✗\033[0m $name ($server:$port) - 连接失败"
        fi
    done
else
    echo "还没有测试结果，请先运行: speedtest"
fi
EOF
    
    chmod +x /usr/local/bin/results
    log "✓ 结果查看命令创建完成"
}

# 优化订阅文件
optimize_subscription() {
    log "优化订阅配置..."
    
    # 如果订阅文件太大，只保留前20个链接
    if [[ -f "subscription.txt" ]]; then
        local line_count=$(wc -l < subscription.txt)
        if [[ $line_count -gt 20 ]]; then
            head -20 subscription.txt > subscription_optimized.txt
            mv subscription_optimized.txt subscription.txt
            log "✓ 订阅文件已优化（保留前20个链接）"
        fi
    fi
}

# 主安装流程
main() {
    show_logo
    
    log "开始一键安装..."
    
    # 检查权限
    if [[ $EUID -ne 0 ]]; then
        error "请使用root权限运行"
        exit 1
    fi
    
    # 安装步骤
    install_deps
    install_xray || true  # xray安装失败不影响整体
    create_speedtest
    create_results
    optimize_subscription
    
    # 完成提示
    echo -e "\n${GREEN}🎉 安装完成！${NC}\n"
    echo -e "${YELLOW}使用方法：${NC}"
    echo -e "  ${BLUE}speedtest${NC}     # 一键测速"
    echo -e "  ${BLUE}results${NC}       # 查看结果"
    echo -e "  ${BLUE}speedtest -h${NC}  # 查看帮助"
    echo
    echo -e "${YELLOW}示例：${NC}"
    echo -e "  speedtest                    # 测试所有节点"
    echo -e "  speedtest | grep '成功'       # 只显示成功的节点"
    echo -e "  results                      # 查看最新结果"
    echo
    
    # 自动运行一次测试
    read -p "是否立即运行一次测速？(y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "开始测速..."
        speedtest
    fi
}

# 执行安装
main "$@"