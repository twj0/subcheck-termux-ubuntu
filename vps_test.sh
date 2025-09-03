#!/bin/bash

# SubCheck VPS 一键测试脚本
# 自动安装依赖、解析订阅、测试网络性能

set -e

echo "=== SubCheck VPS 一键测试脚本 ==="
echo "专为中国大陆网络环境优化"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# 检查系统
check_system() {
    log_info "检查系统环境..."
    
    echo "系统信息: $(uname -a)"
    echo "Python版本: $(python3 --version 2>/dev/null || echo '未安装')"
    echo "当前用户: $(whoami)"
    echo "工作目录: $(pwd)"
    echo ""
}

# 安装依赖
install_dependencies() {
    log_info "安装系统依赖..."
    
    # 更新包管理器
    if command -v apt >/dev/null 2>&1; then
        apt update >/dev/null 2>&1
        apt install -y python3-pip curl jq bc unzip >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y python3-pip curl jq bc unzip >/dev/null 2>&1
    fi
    
    # 安装Python依赖
    log_info "安装Python依赖..."
    pip3 install -r requirements.txt >/dev/null 2>&1
    
    # 安装Xray
    if ! command -v xray >/dev/null 2>&1; then
        log_info "安装Xray..."
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1
    fi
    
    log_success "依赖安装完成"
}

# 验证安装
verify_installation() {
    log_info "验证安装..."
    
    # 检查Python依赖
    if python3 -c "import aiohttp, json, asyncio" 2>/dev/null; then
        log_success "Python依赖验证通过"
    else
        log_error "Python依赖验证失败"
        exit 1
    fi
    
    # 检查Xray
    if command -v xray >/dev/null 2>&1; then
        log_success "Xray安装验证通过: $(xray version | head -1)"
    else
        log_error "Xray安装验证失败"
        exit 1
    fi
}

# 运行解析测试
run_parsing_test() {
    log_info "开始订阅解析测试..."
    
    # 清理旧结果
    rm -rf cache/* logs/* results/* 2>/dev/null || true
    mkdir -p cache logs results
    
    # 运行解析
    if bash scripts/enhanced_parse.sh; then
        local node_count=$(jq 'length' parsed_nodes.json 2>/dev/null || echo "0")
        local vmess_count=$(jq '[.[] | select(.type == "vmess")] | length' parsed_nodes.json 2>/dev/null || echo "0")
        local vless_count=$(jq '[.[] | select(.type == "vless")] | length' parsed_nodes.json 2>/dev/null || echo "0")
        
        log_success "解析完成 - 总节点: $node_count, VMess: $vmess_count, VLESS: $vless_count"
        
        if [[ $node_count -gt 0 ]]; then
            return 0
        else
            log_error "解析节点数为0"
            return 1
        fi
    else
        log_error "订阅解析失败"
        return 1
    fi
}

# 运行网络测试
run_network_test() {
    local max_nodes=${1:-20}
    
    log_info "开始网络性能测试 (最多$max_nodes个节点)..."
    
    if bash scripts/enhanced_test.sh $max_nodes; then
        local total=$(jq 'length' results/test_results.json 2>/dev/null || echo "0")
        local success=$(jq '[.[] | select(.status == "success")] | length' results/test_results.json 2>/dev/null || echo "0")
        
        if [[ $total -gt 0 ]]; then
            local success_rate=$(echo "scale=1; $success * 100 / $total" | bc 2>/dev/null || echo "0")
            log_success "网络测试完成 - 成功: $success/$total ($success_rate%)"
            return 0
        else
            log_error "网络测试无结果"
            return 1
        fi
    else
        log_error "网络测试失败"
        return 1
    fi
}

# 显示结果摘要
show_summary() {
    log_info "生成测试摘要..."
    
    echo ""
    echo "=== 📊 测试结果摘要 ==="
    
    # 解析结果
    if [[ -f "parsed_nodes.json" ]]; then
        local total_nodes=$(jq 'length' parsed_nodes.json 2>/dev/null || echo "0")
        local vmess_nodes=$(jq '[.[] | select(.type == "vmess")] | length' parsed_nodes.json 2>/dev/null || echo "0")
        local vless_nodes=$(jq '[.[] | select(.type == "vless")] | length' parsed_nodes.json 2>/dev/null || echo "0")
        local trojan_nodes=$(jq '[.[] | select(.type == "trojan")] | length' parsed_nodes.json 2>/dev/null || echo "0")
        
        echo "📋 解析节点统计:"
        echo "  总节点数: $total_nodes"
        echo "  VMess: $vmess_nodes"
        echo "  VLESS: $vless_nodes"
        echo "  Trojan: $trojan_nodes"
    fi
    
    # 测试结果
    if [[ -f "results/test_results.json" ]]; then
        local tested_nodes=$(jq 'length' results/test_results.json 2>/dev/null || echo "0")
        local success_nodes=$(jq '[.[] | select(.status == "success")] | length' results/test_results.json 2>/dev/null || echo "0")
        local failed_nodes=$((tested_nodes - success_nodes))
        
        echo ""
        echo "🚀 网络测试统计:"
        echo "  测试节点: $tested_nodes"
        echo "  成功节点: $success_nodes"
        echo "  失败节点: $failed_nodes"
        
        if [[ $tested_nodes -gt 0 ]]; then
            local success_rate=$(echo "scale=1; $success_nodes * 100 / $tested_nodes" | bc 2>/dev/null || echo "0")
            echo "  成功率: $success_rate%"
        fi
        
        # 显示最佳节点
        if [[ $success_nodes -gt 0 ]]; then
            echo ""
            echo "🏆 最佳节点 (前5名):"
            jq -r '.[] | select(.status == "success") | "\(.http_latency // .tcp_latency)ms - \(.download_speed // 0)Mbps - \(.name)"' results/test_results.json 2>/dev/null | \
            sort -n | head -5 | nl -w2 -s'. '
        fi
    fi
    
    echo ""
    echo "📁 输出文件:"
    echo "  解析结果: parsed_nodes.json"
    echo "  测试结果: results/test_results.json"
    echo "  详细日志: logs/subscription_parser.log"
    
    if ls results/test_report_*.md >/dev/null 2>&1; then
        echo "  测试报告: $(ls results/test_report_*.md | head -1)"
    fi
}

# 主函数
main() {
    local max_test_nodes=${1:-20}
    
    echo "开始时间: $(date)"
    echo "测试节点限制: $max_test_nodes"
    echo ""
    
    # 执行测试流程
    check_system
    install_dependencies
    verify_installation
    
    if run_parsing_test; then
        if run_network_test $max_test_nodes; then
            show_summary
            log_success "🎉 所有测试完成！"
        else
            log_warning "网络测试失败，但解析成功"
            show_summary
        fi
    else
        log_error "解析测试失败"
        exit 1
    fi
    
    echo ""
    echo "结束时间: $(date)"
}

# 执行主函数
main "$@"
