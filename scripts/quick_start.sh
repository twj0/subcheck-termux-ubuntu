#!/bin/bash

# SubCheck 快速启动脚本
# 一键运行完整测试流程

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
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

# 显示欢迎信息
show_welcome() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    SubCheck 快速启动                         ║"
    echo "║              订阅节点测试工具 - 中国大陆优化版                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 检查环境
check_environment() {
    log_info "检查运行环境..."
    
    # 检查Python
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "Python3 未安装，请先运行: bash scripts/install.sh"
        exit 1
    fi
    
    # 检查Xray
    if ! command -v xray >/dev/null 2>&1; then
        log_warning "Xray 未安装，正在安装..."
        if ! bash "$PROJECT_DIR/scripts/install.sh"; then
            log_error "Xray 安装失败"
            exit 1
        fi
    fi
    
    # 检查配置文件
    if [[ ! -f "$PROJECT_DIR/config/config.yaml" ]]; then
        log_error "配置文件不存在: config/config.yaml"
        log_info "请先运行: bash scripts/install.sh"
        exit 1
    fi
    
    if [[ ! -f "$PROJECT_DIR/config/subscription.txt" ]]; then
        log_error "订阅文件不存在: config/subscription.txt"
        log_info "请编辑 config/subscription.txt 添加订阅链接"
        exit 1
    fi
    
    log_success "环境检查完成"
}

# 显示配置信息
show_config() {
    log_info "当前配置信息:"
    
    # 读取配置
    if command -v yq >/dev/null 2>&1; then
        local bandwidth=$(yq eval '.network.user_bandwidth' "$PROJECT_DIR/config/config.yaml" 2>/dev/null || echo "300")
        local max_nodes=$(yq eval '.test.max_nodes' "$PROJECT_DIR/config/config.yaml" 2>/dev/null || echo "50")
        local auto_concurrent=$(yq eval '.network.auto_concurrent' "$PROJECT_DIR/config/config.yaml" 2>/dev/null || echo "true")
    else
        local bandwidth="300"
        local max_nodes="50"
        local auto_concurrent="true"
    fi
    
    echo "  - 网络带宽: ${bandwidth}Mbps"
    echo "  - 最大测试节点: ${max_nodes}"
    echo "  - 自动并发: ${auto_concurrent}"
    
    if [[ "$auto_concurrent" == "true" ]]; then
        local optimal_concurrent=$((bandwidth * 80 / 100 / 5))
        optimal_concurrent=$((optimal_concurrent > 50 ? 50 : optimal_concurrent))
        optimal_concurrent=$((optimal_concurrent < 1 ? 1 : optimal_concurrent))
        echo "  - 计算并发数: ${optimal_concurrent}"
    fi
    
    # 显示订阅源数量
    local sub_count=$(grep -v '^#' "$PROJECT_DIR/config/subscription.txt" | grep -v '^$' | wc -l)
    echo "  - 订阅源数量: ${sub_count}"
}

# 运行测试
run_test() {
    local max_nodes="${1:-50}"
    
    log_info "开始运行测试 (最大节点数: $max_nodes)"
    
    cd "$PROJECT_DIR"
    
    # 检查Python依赖
    if ! python3 -c "import aiohttp, yaml, json" 2>/dev/null; then
        log_warning "Python依赖缺失，正在安装..."
        pip3 install -r requirements.txt
    fi
    
    # 运行测试
    local start_time=$(date +%s)
    
    if python3 src/cli/main.py run config/subscription.txt -n "$max_nodes"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        log_success "测试完成！耗时: ${duration}秒"
        
        # 显示结果摘要
        show_results_summary
    else
        log_error "测试失败，请查看日志"
        return 1
    fi
}

# 显示结果摘要
show_results_summary() {
    local results_file="$PROJECT_DIR/data/results/test_results.json"
    
    if [[ ! -f "$results_file" ]]; then
        log_warning "结果文件不存在"
        return
    fi
    
    log_info "测试结果摘要:"
    
    # 使用Python分析结果
    python3 -c "
import json
import sys

try:
    with open('$results_file', 'r', encoding='utf-8') as f:
        results = json.load(f)
    
    total = len(results)
    success = [r for r in results if r.get('status') == 'success']
    success_count = len(success)
    
    print(f'  - 总节点数: {total}')
    print(f'  - 成功节点: {success_count}')
    print(f'  - 成功率: {success_count/total*100:.1f}%')
    
    if success:
        # 按延迟排序
        success.sort(key=lambda x: x.get('http_latency') or x.get('tcp_latency') or 9999)
        
        print('\n🏆 最佳节点 (前5名):')
        for i, r in enumerate(success[:5]):
            name = r.get('name', 'Unknown')[:30]
            latency = r.get('http_latency') or r.get('tcp_latency') or 'N/A'
            speed = r.get('download_speed') or 'N/A'
            print(f'  {i+1}. {name:<30} {latency:>6}ms {speed:>8}Mbps')
        
        print(f'\n📁 详细结果: {results_file}')
    else:
        print('\n❌ 没有测试成功的节点')
        
        # 分析失败原因
        errors = {}
        for r in results:
            if r.get('status') == 'failed':
                error = r.get('error', 'Unknown error')
                errors[error] = errors.get(error, 0) + 1
        
        if errors:
            print('\n主要失败原因:')
            for error, count in sorted(errors.items(), key=lambda x: x[1], reverse=True)[:3]:
                print(f'  - {error}: {count}次')

except Exception as e:
    print(f'分析结果时出错: {e}')
    sys.exit(1)
"
}

# 显示使用提示
show_tips() {
    echo ""
    log_info "使用提示:"
    echo "  📝 编辑配置: nano config/config.yaml"
    echo "  📋 编辑订阅: nano config/subscription.txt"
    echo "  🔍 查看日志: tail -f data/logs/subcheck.log"
    echo "  📊 查看结果: cat data/results/test_results.json | jq"
    echo ""
    echo "  🚀 重新测试: bash scripts/quick_start.sh [节点数]"
    echo "  🔧 完整安装: bash scripts/install.sh"
}

# 主函数
main() {
    local max_nodes="${1:-50}"
    
    show_welcome
    check_environment
    show_config
    
    echo ""
    read -p "按回车键开始测试，或 Ctrl+C 取消..."
    echo ""
    
    if run_test "$max_nodes"; then
        show_tips
    else
        echo ""
        log_error "测试失败，请检查配置和网络连接"
        echo ""
        echo "常见解决方案:"
        echo "  1. 检查网络连接: curl -I https://www.google.com"
        echo "  2. 降低并发数: 在config.yaml中设置 manual_concurrent: 3"
        echo "  3. 增加超时时间: 在config.yaml中设置 timeout.connect: 15"
        echo "  4. 查看详细日志: tail -f data/logs/subcheck.log"
        exit 1
    fi
}

# 执行主函数
main "$@"
