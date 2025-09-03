#!/bin/bash

# Termux Ubuntu 环境特殊优化安装脚本
# 针对手机Termux + Ubuntu24环境的特殊配置

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

# 检测Termux环境
detect_termux() {
    if [ -n "$TERMUX_VERSION" ] || [ -d "/data/data/com.termux" ]; then
        print_info "检测到Termux环境"
        return 0
    else
        print_warning "未检测到Termux环境，继续安装..."
        return 1
    fi
}

# Termux特殊优化
optimize_for_termux() {
    print_info "应用Termux环境优化..."
    
    # 1. 设置合适的并发数（手机性能限制）
    sed -i 's/CONCURRENT=20/CONCURRENT=5/' termux_scheduler.sh
    sed -i 's/DEFAULT_CONCURRENT="10"/DEFAULT_CONCURRENT="5"/' termux_scheduler.sh
    
    # 2. 增加超时时间（移动网络不稳定）
    sed -i 's/TIMEOUT=30/TIMEOUT=45/' termux_scheduler.sh
    sed -i 's/DEFAULT_TIMEOUT="30"/DEFAULT_TIMEOUT="45"/' termux_scheduler.sh
    
    # 3. 减少测试频率（省电）
    sed -i 's/DEFAULT_INTERVAL="3600"/DEFAULT_INTERVAL="7200"/' termux_scheduler.sh  # 2小时
    
    # 4. 启用低功耗模式
    cat >> termux_scheduler.sh << 'EOF'

# Termux低功耗模式
enable_power_saving() {
    # 降低CPU频率（如果支持）
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        echo "powersave" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true
    fi
    
    # 设置进程优先级
    renice 10 $$ 2>/dev/null || true
}
EOF
    
    print_info "Termux优化完成"
}

# 安装Python依赖（Termux方式）
install_python_termux() {
    print_info "安装Python依赖（Termux优化）..."
    
    # 检查Python版本
    if ! python3 --version >/dev/null 2>&1; then
        print_error "Python3未安装，请先安装: pkg install python"
        return 1
    fi
    
    # 安装轻量级HTTP服务器依赖
    pip3 install --user --no-cache-dir requests 2>/dev/null || {
        print_warning "pip安装失败，使用系统包管理器"
        apt-get update && apt-get install -y python3-requests || true
    }
}

# 配置网络优化
configure_network() {
    print_info "配置网络优化..."
    
    # 创建网络优化配置
    cat > network_optimize.sh << 'EOF'
#!/bin/bash
# 网络优化脚本 - 适用于移动网络环境

# DNS优化
configure_dns() {
    local dns_file="/etc/resolv.conf"
    if [ -w "$dns_file" ]; then
        {
            echo "# 中国大陆优化DNS"
            echo "nameserver 223.5.5.5"
            echo "nameserver 119.29.29.29"
            echo "nameserver 114.114.114.114"
            echo "nameserver 8.8.8.8"
        } > "$dns_file"
    fi
}

# TCP优化
optimize_tcp() {
    # 设置TCP参数（如果有权限）
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null || true
    sysctl -w net.core.rmem_max=16777216 2>/dev/null || true
    sysctl -w net.core.wmem_max=16777216 2>/dev/null || true
}

# 执行优化
configure_dns
optimize_tcp
EOF
    
    chmod +x network_optimize.sh
    print_info "网络优化配置完成"
}

# 创建Termux专用启动脚本
create_termux_launcher() {
    print_info "创建Termux专用启动脚本..."
    
    cat > start_subcheck.sh << 'EOF'
#!/bin/bash

# SubCheck Termux 启动脚本
# 一键启动所有服务

print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

# 检查权限和环境
check_environment() {
    print_info "检查运行环境..."
    
    # 检查必要命令
    for cmd in curl jq python3; do
        if ! command -v $cmd >/dev/null 2>&1; then
            print_error "缺少依赖: $cmd"
            echo "请安装: pkg install $cmd"
            exit 1
        fi
    done
    
    # 检查网络连接
    if ! curl -s --connect-timeout 5 https://www.baidu.com >/dev/null; then
        print_error "网络连接失败，请检查网络设置"
        exit 1
    fi
    
    print_info "环境检查通过"
}

# 应用网络优化
apply_optimizations() {
    print_info "应用网络优化..."
    bash network_optimize.sh 2>/dev/null || true
}

# 启动服务
start_services() {
    print_info "启动SubCheck服务..."
    
    # 设置权限
    chmod +x *.sh
    
    # 初始化配置
    bash termux_scheduler.sh config 2>/dev/null || true
    
    # 启动守护进程
    print_info "启动后台服务..."
    nohup bash termux_scheduler.sh daemon > subcheck.log 2>&1 &
    
    local pid=$!
    echo $pid > subcheck.pid
    
    print_info "服务已启动，PID: $pid"
    print_info "日志文件: subcheck.log"
    print_info "Web界面: http://localhost:8080"
    
    # 等待服务启动
    sleep 3
    
    # 检查服务状态
    if kill -0 $pid 2>/dev/null; then
        print_info "✅ 服务启动成功"
    else
        print_error "❌ 服务启动失败，请检查日志"
        exit 1
    fi
}

# 显示状态
show_status() {
    echo ""
    echo "=== SubCheck Termux 状态 ==="
    
    if [ -f subcheck.pid ]; then
        local pid=$(cat subcheck.pid)
        if kill -0 $pid 2>/dev/null; then
            echo "状态: 🟢 运行中 (PID: $pid)"
            echo "内存使用: $(ps -o rss= -p $pid 2>/dev/null | awk '{print int($1/1024)"MB"}' || echo "未知")"
        else
            echo "状态: 🔴 已停止"
            rm -f subcheck.pid
        fi
    else
        echo "状态: 🔴 未运行"
    fi
    
    echo "配置目录: ~/.subcheck"
    echo "Web界面: http://localhost:8080"
    echo ""
    echo "管理命令:"
    echo "  查看日志: tail -f subcheck.log"
    echo "  停止服务: kill \$(cat subcheck.pid)"
    echo "  重启服务: bash start_subcheck.sh"
}

# 主函数
main() {
    case "${1:-start}" in
        start)
            check_environment
            apply_optimizations
            start_services
            show_status
            ;;
        status)
            show_status
            ;;
        stop)
            if [ -f subcheck.pid ]; then
                local pid=$(cat subcheck.pid)
                kill $pid 2>/dev/null && echo "服务已停止" || echo "停止失败"
                rm -f subcheck.pid
            else
                echo "服务未运行"
            fi
            ;;
        restart)
            $0 stop
            sleep 2
            $0 start
            ;;
        logs)
            tail -f subcheck.log
            ;;
        test)
            bash simple_china_test.sh subscription.txt
            ;;
        *)
            echo "用法: $0 {start|stop|restart|status|logs|test}"
            echo ""
            echo "命令说明:"
            echo "  start   - 启动服务"
            echo "  stop    - 停止服务"
            echo "  restart - 重启服务"
            echo "  status  - 查看状态"
            echo "  logs    - 查看日志"
            echo "  test    - 手动测试"
            ;;
    esac
}

main "$@"
EOF
    
    chmod +x start_subcheck.sh
    print_info "Termux启动脚本创建完成: start_subcheck.sh"
}

# 创建自动启动配置
setup_autostart() {
    print_info "配置自动启动..."
    
    # 创建Termux自动启动脚本
    local termux_boot_dir="$HOME/.termux/boot"
    mkdir -p "$termux_boot_dir"
    
    cat > "$termux_boot_dir/subcheck-autostart" << EOF
#!/bin/bash
# SubCheck自动启动脚本

# 等待网络就绪
sleep 30

# 切换到项目目录
cd "\$HOME/subcheck/subcheck-termux-ubuntu" || exit 1

# 启动服务
bash start_subcheck.sh start

# 记录启动日志
echo "\$(date): SubCheck自动启动完成" >> "\$HOME/.subcheck/autostart.log"
EOF
    
    chmod +x "$termux_boot_dir/subcheck-autostart"
    
    print_info "自动启动配置完成"
    print_info "重启Termux后将自动启动SubCheck服务"
}

# 主安装函数
main() {
    print_info "=== SubCheck Termux 环境优化安装 ==="
    
    # 检测环境
    detect_termux
    
    # 应用Termux优化
    optimize_for_termux
    
    # 安装Python依赖
    install_python_termux
    
    # 配置网络优化
    configure_network
    
    # 创建启动脚本
    create_termux_launcher
    
    # 设置自动启动
    setup_autostart
    
    # 设置权限
    chmod +x *.sh
    
    print_info "=== 安装完成 ==="
    echo ""
    echo "🎉 SubCheck Termux版本安装完成！"
    echo ""
    echo "快速开始:"
    echo "  1. 启动服务: bash start_subcheck.sh"
    echo "  2. 查看状态: bash start_subcheck.sh status"
    echo "  3. 手动测试: bash start_subcheck.sh test"
    echo "  4. 访问Web界面: http://localhost:8080"
    echo ""
    echo "特性:"
    echo "  ✅ 针对Termux环境优化"
    echo "  ✅ 中国大陆网络优化"
    echo "  ✅ 低功耗模式"
    echo "  ✅ 自动启动支持"
    echo "  ✅ Web管理界面"
    echo "  ✅ 定时测速功能"
    echo ""
    echo "配置文件: ~/.subcheck/scheduler.conf"
    echo "订阅文件: ~/.subcheck/subscriptions.txt"
}

# 运行主函数
main "$@"
