#!/bin/bash

# Termux Ubuntu 定时测速调度器
# 基于SubsCheck-Win-GUI的架构，适配Ubuntu系统

set -e

# 配置文件路径
CONFIG_DIR="$HOME/.subcheck"
CONFIG_FILE="$CONFIG_DIR/scheduler.conf"
LOG_DIR="$CONFIG_DIR/logs"
RESULTS_DIR="$CONFIG_DIR/results"
SUBSCRIPTIONS_FILE="$CONFIG_DIR/subscriptions.txt"

# 默认配置
DEFAULT_INTERVAL="3600"  # 1小时
DEFAULT_CONCURRENT="10"
DEFAULT_TIMEOUT="30"
DEFAULT_MIN_SPEED="1"
DEFAULT_MAX_LATENCY="2000"
DEFAULT_SAVE_FORMAT="json"
DEFAULT_KEEP_DAYS="7"

# 颜色输出
print_info() {
    echo -e "\033[32m[INFO]\033[0m $(date '+%Y-%m-%d %H:%M:%S') $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
}

print_warning() {
    echo -e "\033[33m[WARNING]\033[0m $(date '+%Y-%m-%d %H:%M:%S') $1"
}

# 初始化目录结构
init_directories() {
    mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$RESULTS_DIR"
    
    # 创建默认配置文件
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
# SubCheck Termux 调度器配置文件
# 基于SubsCheck-Win-GUI的设计理念

# 测试间隔（秒）
INTERVAL=$DEFAULT_INTERVAL

# 并发数
CONCURRENT=$DEFAULT_CONCURRENT

# 超时时间（秒）
TIMEOUT=$DEFAULT_TIMEOUT

# 最低速度要求（MB/s）
MIN_SPEED=$DEFAULT_MIN_SPEED

# 最大延迟（毫秒）
MAX_LATENCY=$DEFAULT_MAX_LATENCY

# 保存格式（json/yaml/base64）
SAVE_FORMAT=$DEFAULT_SAVE_FORMAT

# 结果保留天数
KEEP_DAYS=$DEFAULT_KEEP_DAYS

# 启用Web界面
ENABLE_WEB=true

# Web端口
WEB_PORT=8080

# 启用通知
ENABLE_NOTIFICATION=false

# Telegram Bot Token（可选）
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
EOF
        print_info "创建默认配置文件: $CONFIG_FILE"
    fi
    
    # 创建默认订阅文件
    if [ ! -f "$SUBSCRIPTIONS_FILE" ]; then
        cp subscription.txt "$SUBSCRIPTIONS_FILE" 2>/dev/null || {
            echo "https://raw.githubusercontent.com/mfuu/v2ray/master/v2ray" > "$SUBSCRIPTIONS_FILE"
        }
        print_info "创建订阅文件: $SUBSCRIPTIONS_FILE"
    fi
}

# 加载配置
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        print_error "配置文件不存在: $CONFIG_FILE"
        return 1
    fi
}

# 执行单次测试
run_test() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local result_file="$RESULTS_DIR/test_$timestamp.$SAVE_FORMAT"
    local log_file="$LOG_DIR/test_$timestamp.log"
    
    print_info "开始定时测试 - $timestamp"
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 执行测试（使用我们优化的脚本）
    {
        echo "=== SubCheck 定时测试 - $timestamp ==="
        echo "配置: 并发=$CONCURRENT, 超时=${TIMEOUT}s, 最低速度=${MIN_SPEED}MB/s"
        echo ""
        
        # 遍历所有订阅
        local total_working=0
        local total_tested=0
        
        while IFS= read -r subscription_url; do
            [ -z "$subscription_url" ] && continue
            [[ "$subscription_url" == \#* ]] && continue
            
            echo "测试订阅: $subscription_url"
            
            # 使用我们的优化脚本进行测试
            local test_result
            if test_result=$(timeout $((TIMEOUT * 3)) bash simple_china_test.sh "$subscription_url" 2>&1); then
                echo "$test_result"
                
                # 统计结果
                local working=$(echo "$test_result" | grep -c "✅" || echo "0")
                local tested=$(echo "$test_result" | grep -c "测试" || echo "0")
                total_working=$((total_working + working))
                total_tested=$((total_tested + tested))
            else
                echo "订阅测试失败: $subscription_url"
            fi
            echo "---"
        done < "$SUBSCRIPTIONS_FILE"
        
        echo ""
        echo "=== 测试汇总 ==="
        echo "总测试节点: $total_tested"
        echo "可用节点: $total_working"
        echo "可用率: $(( total_tested > 0 ? total_working * 100 / total_tested : 0 ))%"
        
    } | tee "$log_file"
    
    # 计算耗时
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    print_info "测试完成，耗时 ${duration}s，日志: $log_file"
    
    # 发送通知（如果启用）
    if [ "$ENABLE_NOTIFICATION" = "true" ]; then
        send_notification "SubCheck测试完成" "耗时${duration}s，可用节点${total_working}/${total_tested}"
    fi
    
    # 清理旧文件
    cleanup_old_files
}

# 发送通知
send_notification() {
    local title="$1"
    local message="$2"
    
    # Telegram通知
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local telegram_message="🤖 $title\n\n$message\n\n⏰ $(date '+%Y-%m-%d %H:%M:%S')"
        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -d "chat_id=$TELEGRAM_CHAT_ID" \
            -d "text=$telegram_message" \
            -d "parse_mode=HTML" >/dev/null 2>&1 || true
    fi
    
    # 系统通知（如果支持）
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$message" || true
    fi
}

# 清理旧文件
cleanup_old_files() {
    print_info "清理 $KEEP_DAYS 天前的旧文件..."
    
    # 清理日志文件
    find "$LOG_DIR" -name "*.log" -mtime +$KEEP_DAYS -delete 2>/dev/null || true
    
    # 清理结果文件
    find "$RESULTS_DIR" -name "test_*" -mtime +$KEEP_DAYS -delete 2>/dev/null || true
}

# 启动Web界面
start_web_interface() {
    if [ "$ENABLE_WEB" != "true" ]; then
        return 0
    fi
    
    local web_script="$CONFIG_DIR/web_interface.py"
    
    # 创建Web界面脚本
    cat > "$web_script" << 'EOF'
#!/usr/bin/env python3
import os
import json
import glob
import subprocess
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import threading
import time

class SubCheckWebHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_html_response(self.get_dashboard_html())
        elif self.path == '/api/status':
            self.send_json_response(self.get_status())
        elif self.path == '/api/logs':
            self.send_json_response(self.get_recent_logs())
        elif self.path == '/api/results':
            self.send_json_response(self.get_recent_results())
        elif self.path.startswith('/api/test'):
            self.handle_manual_test()
        else:
            self.send_error(404)
    
    def send_html_response(self, html):
        self.send_response(200)
        self.send_header('Content-type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(html.encode())
    
    def send_json_response(self, data):
        self.send_response(200)
        self.send_header('Content-type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False, indent=2).encode())
    
    def get_status(self):
        config_dir = os.path.expanduser('~/.subcheck')
        return {
            'status': 'running',
            'timestamp': int(time.time()),
            'config_dir': config_dir,
            'version': '1.0.0-termux'
        }
    
    def get_recent_logs(self):
        log_dir = os.path.expanduser('~/.subcheck/logs')
        log_files = sorted(glob.glob(f'{log_dir}/*.log'), reverse=True)[:5]
        
        logs = []
        for log_file in log_files:
            try:
                with open(log_file, 'r', encoding='utf-8') as f:
                    content = f.read()
                logs.append({
                    'file': os.path.basename(log_file),
                    'content': content[-2000:]  # 最后2000字符
                })
            except:
                pass
        
        return logs
    
    def get_recent_results(self):
        results_dir = os.path.expanduser('~/.subcheck/results')
        result_files = sorted(glob.glob(f'{results_dir}/*'), reverse=True)[:10]
        
        results = []
        for result_file in result_files:
            try:
                stat = os.stat(result_file)
                results.append({
                    'file': os.path.basename(result_file),
                    'size': stat.st_size,
                    'mtime': stat.st_mtime
                })
            except:
                pass
        
        return results
    
    def handle_manual_test(self):
        # 启动手动测试
        try:
            subprocess.Popen(['bash', 'termux_scheduler.sh', 'test'], 
                           cwd=os.path.expanduser('~/subcheck/subcheck-termux-ubuntu'))
            self.send_json_response({'status': 'started', 'message': '手动测试已启动'})
        except Exception as e:
            self.send_json_response({'status': 'error', 'message': str(e)})
    
    def get_dashboard_html(self):
        return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SubCheck Termux - 节点检测面板</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .card { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .button { background: #3498db; color: white; padding: 10px 20px; border: none; border-radius: 4px; cursor: pointer; }
        .button:hover { background: #2980b9; }
        .log-content { background: #2c3e50; color: #ecf0f1; padding: 15px; border-radius: 4px; font-family: monospace; max-height: 400px; overflow-y: auto; }
        .status-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; }
        .status-item { text-align: center; padding: 15px; background: #ecf0f1; border-radius: 4px; }
        .status-value { font-size: 24px; font-weight: bold; color: #2c3e50; }
        .status-label { color: #7f8c8d; margin-top: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 SubCheck Termux</h1>
            <p>基于Ubuntu的节点检测系统 - 中国大陆网络优化版</p>
        </div>
        
        <div class="card">
            <h2>系统状态</h2>
            <div class="status-grid" id="statusGrid">
                <div class="status-item">
                    <div class="status-value" id="statusValue">检查中...</div>
                    <div class="status-label">运行状态</div>
                </div>
                <div class="status-item">
                    <div class="status-value" id="uptimeValue">--</div>
                    <div class="status-label">运行时间</div>
                </div>
                <div class="status-item">
                    <div class="status-value" id="testsValue">--</div>
                    <div class="status-label">测试次数</div>
                </div>
                <div class="status-item">
                    <div class="status-value" id="successValue">--%</div>
                    <div class="status-label">成功率</div>
                </div>
            </div>
        </div>
        
        <div class="card">
            <h2>操作面板</h2>
            <button class="button" onclick="startManualTest()">🧪 手动测试</button>
            <button class="button" onclick="refreshLogs()">🔄 刷新日志</button>
            <button class="button" onclick="downloadResults()">📥 下载结果</button>
        </div>
        
        <div class="card">
            <h2>最近日志</h2>
            <div class="log-content" id="logContent">加载中...</div>
        </div>
    </div>
    
    <script>
        function updateStatus() {
            fetch('/api/status')
                .then(r => r.json())
                .then(data => {
                    document.getElementById('statusValue').textContent = '🟢 运行中';
                })
                .catch(() => {
                    document.getElementById('statusValue').textContent = '🔴 离线';
                });
        }
        
        function refreshLogs() {
            fetch('/api/logs')
                .then(r => r.json())
                .then(logs => {
                    const content = logs.map(log => 
                        `=== ${log.file} ===\\n${log.content}`
                    ).join('\\n\\n');
                    document.getElementById('logContent').textContent = content || '暂无日志';
                })
                .catch(e => {
                    document.getElementById('logContent').textContent = '加载日志失败: ' + e.message;
                });
        }
        
        function startManualTest() {
            if(confirm('确定要启动手动测试吗？')) {
                fetch('/api/test')
                    .then(r => r.json())
                    .then(data => {
                        alert(data.message || '测试已启动');
                        setTimeout(refreshLogs, 2000);
                    })
                    .catch(e => alert('启动失败: ' + e.message));
            }
        }
        
        function downloadResults() {
            window.open('/api/results', '_blank');
        }
        
        // 初始化和定时刷新
        updateStatus();
        refreshLogs();
        setInterval(updateStatus, 30000);
        setInterval(refreshLogs, 60000);
    </script>
</body>
</html>'''

if __name__ == '__main__':
    import sys
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    server = HTTPServer(('0.0.0.0', port), SubCheckWebHandler)
    print(f'SubCheck Web界面启动在端口 {port}')
    print(f'访问: http://localhost:{port}')
    server.serve_forever()
EOF
    
    chmod +x "$web_script"
    
    # 启动Web服务（后台运行）
    if ! pgrep -f "python3.*web_interface.py" >/dev/null; then
        nohup python3 "$web_script" "$WEB_PORT" >/dev/null 2>&1 &
        print_info "Web界面已启动在端口 $WEB_PORT"
        print_info "访问地址: http://localhost:$WEB_PORT"
    fi
}

# 安装系统服务
install_service() {
    print_info "安装SubCheck定时服务..."
    
    # 创建systemd服务文件
    local service_file="/etc/systemd/system/subcheck-scheduler.service"
    
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=SubCheck Termux Scheduler
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/termux_scheduler.sh daemon
Restart=always
RestartSec=10
Environment=HOME=$HOME

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载systemd并启用服务
    sudo systemctl daemon-reload
    sudo systemctl enable subcheck-scheduler
    sudo systemctl start subcheck-scheduler
    
    print_info "系统服务安装完成"
    print_info "服务状态: $(systemctl is-active subcheck-scheduler)"
}

# 守护进程模式
daemon_mode() {
    print_info "启动SubCheck守护进程..."
    
    # 初始化
    init_directories
    load_config
    
    # 启动Web界面
    start_web_interface
    
    # 主循环
    while true; do
        run_test
        print_info "等待 ${INTERVAL}s 后进行下次测试..."
        sleep "$INTERVAL"
    done
}

# 显示状态
show_status() {
    load_config
    
    echo "=== SubCheck Termux 状态 ==="
    echo "配置目录: $CONFIG_DIR"
    echo "测试间隔: ${INTERVAL}s"
    echo "并发数: $CONCURRENT"
    echo "Web界面: $([ "$ENABLE_WEB" = "true" ] && echo "启用 (端口$WEB_PORT)" || echo "禁用")"
    echo ""
    
    # 检查服务状态
    if systemctl is-active subcheck-scheduler >/dev/null 2>&1; then
        echo "系统服务: 🟢 运行中"
    else
        echo "系统服务: 🔴 未运行"
    fi
    
    # 显示最近测试结果
    if [ -d "$LOG_DIR" ]; then
        local latest_log=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
        if [ -n "$latest_log" ]; then
            echo ""
            echo "最近测试: $(basename "$latest_log")"
            echo "测试时间: $(stat -c %y "$latest_log" | cut -d. -f1)"
        fi
    fi
}

# 显示帮助
show_help() {
    cat << EOF
SubCheck Termux 定时测速调度器

用法: $0 [命令]

命令:
  daemon        启动守护进程模式
  test          执行单次测试
  install       安装系统服务
  status        显示状态信息
  start         启动系统服务
  stop          停止系统服务
  restart       重启系统服务
  logs          查看日志
  config        编辑配置文件
  help          显示帮助信息

配置文件: $CONFIG_FILE
日志目录: $LOG_DIR
结果目录: $RESULTS_DIR

基于SubsCheck-Win-GUI架构，适配Ubuntu Termux环境
EOF
}

# 主函数
main() {
    case "${1:-help}" in
        daemon)
            daemon_mode
            ;;
        test)
            init_directories
            load_config
            run_test
            ;;
        install)
            init_directories
            install_service
            ;;
        status)
            show_status
            ;;
        start)
            sudo systemctl start subcheck-scheduler
            print_info "服务已启动"
            ;;
        stop)
            sudo systemctl stop subcheck-scheduler
            print_info "服务已停止"
            ;;
        restart)
            sudo systemctl restart subcheck-scheduler
            print_info "服务已重启"
            ;;
        logs)
            sudo journalctl -u subcheck-scheduler -f
            ;;
        config)
            init_directories
            ${EDITOR:-nano} "$CONFIG_FILE"
            ;;
        help|*)
            show_help
            ;;
    esac
}

# 运行主函数
main "$@"
