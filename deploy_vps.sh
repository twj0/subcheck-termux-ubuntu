#!/bin/bash

# Ubuntu VPS 部署脚本
# 自动化部署SubCheck到Ubuntu VPS服务器

set -e

# 配置变量
VPS_USER="root"
VPS_HOST=""
VPS_PORT="22"
DEPLOY_PATH="/opt/subcheck"
SERVICE_NAME="subcheck"
WEB_PORT="8080"

# 颜色输出
print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

print_warning() {
    echo -e "\033[33m[WARNING]\033[0m $1"
}

show_help() {
    cat << EOF
Ubuntu VPS 部署脚本

用法: $0 [选项] <VPS_IP>

选项:
  -u, --user USER       SSH用户名 (默认: root)
  -p, --port PORT       SSH端口 (默认: 22)
  -d, --deploy-path PATH 部署路径 (默认: /opt/subcheck)
  -w, --web-port PORT   Web服务端口 (默认: 8080)
  -h, --help           显示帮助信息

示例:
  $0 192.168.1.100
  $0 -u ubuntu -p 2222 your-vps.com
  $0 --deploy-path /home/subcheck --web-port 9000 vps.example.com

部署后访问: http://VPS_IP:$WEB_PORT
EOF
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user)
            VPS_USER="$2"
            shift 2
            ;;
        -p|--port)
            VPS_PORT="$2"
            shift 2
            ;;
        -d|--deploy-path)
            DEPLOY_PATH="$2"
            shift 2
            ;;
        -w|--web-port)
            WEB_PORT="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            print_error "未知选项: $1"
            show_help
            exit 1
            ;;
        *)
            VPS_HOST="$1"
            shift
            ;;
    esac
done

if [ -z "$VPS_HOST" ]; then
    print_error "请提供VPS IP地址或域名"
    show_help
    exit 1
fi

# SSH连接测试
test_ssh_connection() {
    print_info "测试SSH连接到 $VPS_USER@$VPS_HOST:$VPS_PORT..."
    if ssh -o ConnectTimeout=10 -o BatchMode=yes -p "$VPS_PORT" "$VPS_USER@$VPS_HOST" "echo 'SSH连接成功'" 2>/dev/null; then
        print_info "SSH连接测试成功"
        return 0
    else
        print_error "SSH连接失败，请检查:"
        echo "  1. VPS IP地址和端口是否正确"
        echo "  2. SSH密钥是否已配置"
        echo "  3. 防火墙设置是否允许SSH连接"
        return 1
    fi
}

# 创建部署包
create_deployment_package() {
    print_info "创建部署包..."
    
    local temp_dir="/tmp/subcheck-deploy-$$"
    mkdir -p "$temp_dir"
    
    # 复制核心文件
    cp -r scripts/ "$temp_dir/"
    cp *.sh "$temp_dir/"
    cp *.yaml "$temp_dir/" 2>/dev/null || true
    cp *.txt "$temp_dir/" 2>/dev/null || true
    
    # 创建VPS优化的配置
    cat > "$temp_dir/vps_config.yaml" << 'EOL'
# VPS优化配置
concurrent: 20
timeout: 8000
speedtest-timeout: 15
min-speed: 0.5
max-latency: 2000
output-format: json
output-file: results.json
save-working-nodes: true
retry-count: 3
retry-delay: 2

# VPS网络优化
user-agent: "SubCheck-VPS/1.0"
github-proxy: "https://ghfast.top/"
EOL
    
    # 创建Web服务脚本
    cat > "$temp_dir/web_server.py" << 'EOL'
#!/usr/bin/env python3
import os
import json
import subprocess
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import time

class SubCheckHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(self.get_index_html().encode())
        elif self.path == '/api/test':
            self.handle_test_request()
        elif self.path == '/api/status':
            self.handle_status_request()
        else:
            self.send_error(404)
    
    def do_POST(self):
        if self.path == '/api/test':
            self.handle_test_request()
        else:
            self.send_error(404)
    
    def handle_test_request(self):
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length).decode()
            
            # 解析请求数据
            data = json.loads(post_data) if post_data else {}
            subscription_url = data.get('url', '')
            
            if not subscription_url:
                self.send_json_response({'error': '请提供订阅URL'}, 400)
                return
            
            # 启动测试
            result = self.run_subcheck(subscription_url)
            self.send_json_response(result)
            
        except Exception as e:
            self.send_json_response({'error': str(e)}, 500)
    
    def handle_status_request(self):
        status = {
            'server': 'SubCheck VPS',
            'version': '1.0',
            'timestamp': int(time.time()),
            'status': 'running'
        }
        self.send_json_response(status)
    
    def run_subcheck(self, url):
        try:
            # 使用中国优化版本
            cmd = ['bash', 'china_optimized.sh', url]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            
            if result.returncode == 0:
                return {'success': True, 'data': json.loads(result.stdout)}
            else:
                return {'success': False, 'error': result.stderr}
                
        except subprocess.TimeoutExpired:
            return {'success': False, 'error': '测试超时'}
        except Exception as e:
            return {'success': False, 'error': str(e)}
    
    def send_json_response(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False, indent=2).encode())
    
    def get_index_html(self):
        return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SubCheck VPS - 节点检测服务</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        .header { text-align: center; margin-bottom: 30px; }
        .form-group { margin-bottom: 20px; }
        label { display: block; margin-bottom: 5px; font-weight: bold; }
        input[type="url"] { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 4px; }
        button { background: #007cba; color: white; padding: 10px 20px; border: none; border-radius: 4px; cursor: pointer; }
        button:hover { background: #005a87; }
        button:disabled { background: #ccc; cursor: not-allowed; }
        .results { margin-top: 30px; }
        .node { border: 1px solid #ddd; margin: 10px 0; padding: 15px; border-radius: 4px; }
        .node.success { border-color: #28a745; background: #f8fff9; }
        .node.failed { border-color: #dc3545; background: #fff8f8; }
        .loading { text-align: center; padding: 20px; }
        .error { color: #dc3545; background: #fff8f8; padding: 10px; border-radius: 4px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚀 SubCheck VPS</h1>
        <p>节点检测服务 - 中国大陆网络优化版</p>
    </div>
    
    <div class="form-group">
        <label for="subscriptionUrl">订阅链接:</label>
        <input type="url" id="subscriptionUrl" placeholder="https://example.com/subscription" />
    </div>
    
    <div class="form-group">
        <button onclick="startTest()" id="testBtn">开始测试</button>
    </div>
    
    <div id="results" class="results"></div>
    
    <script>
        async function startTest() {
            const url = document.getElementById('subscriptionUrl').value;
            const btn = document.getElementById('testBtn');
            const results = document.getElementById('results');
            
            if (!url) {
                alert('请输入订阅链接');
                return;
            }
            
            btn.disabled = true;
            btn.textContent = '测试中...';
            results.innerHTML = '<div class="loading">正在测试节点，请稍候...</div>';
            
            try {
                const response = await fetch('/api/test', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({url: url})
                });
                
                const data = await response.json();
                displayResults(data);
                
            } catch (error) {
                results.innerHTML = `<div class="error">测试失败: ${error.message}</div>`;
            } finally {
                btn.disabled = false;
                btn.textContent = '开始测试';
            }
        }
        
        function displayResults(data) {
            const results = document.getElementById('results');
            
            if (!data.success) {
                results.innerHTML = `<div class="error">测试失败: ${data.error}</div>`;
                return;
            }
            
            const nodes = data.data;
            let html = `<h3>测试结果 (共 ${nodes.length} 个节点)</h3>`;
            
            nodes.forEach(node => {
                const status = node.success ? 'success' : 'failed';
                const statusText = node.success ? '✅ 可用' : '❌ 不可用';
                const latency = node.latency > 0 ? `${node.latency}ms` : 'N/A';
                const download = node.download > 0 ? `${node.download}MB/s` : 'N/A';
                
                html += `
                    <div class="node ${status}">
                        <strong>${node.name}</strong> ${statusText}<br>
                        延迟: ${latency} | 下载速度: ${download}
                        ${node.error ? `<br><small>错误: ${node.error}</small>` : ''}
                    </div>
                `;
            });
            
            results.innerHTML = html;
        }
        
        // 回车键提交
        document.getElementById('subscriptionUrl').addEventListener('keypress', function(e) {
            if (e.key === 'Enter') startTest();
        });
    </script>
</body>
</html>'''

if __name__ == '__main__':
    import sys
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    server = HTTPServer(('0.0.0.0', port), SubCheckHandler)
    print(f'SubCheck VPS服务启动在端口 {port}')
    print(f'访问: http://localhost:{port}')
    server.serve_forever()
EOL
    
    # 创建systemd服务文件
    cat > "$temp_dir/subcheck.service" << EOL
[Unit]
Description=SubCheck VPS Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$DEPLOY_PATH
ExecStart=/usr/bin/python3 $DEPLOY_PATH/web_server.py $WEB_PORT
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL
    
    # 创建安装脚本
    cat > "$temp_dir/install.sh" << 'EOL'
#!/bin/bash
set -e

DEPLOY_PATH="$1"
WEB_PORT="$2"

echo "[INFO] 开始安装SubCheck VPS服务..."

# 更新系统
apt-get update
apt-get install -y python3 python3-pip curl jq wget unzip

# 创建部署目录
mkdir -p "$DEPLOY_PATH"
cd "$DEPLOY_PATH"

# 复制文件
cp /tmp/subcheck-deploy/* . 2>/dev/null || true

# 设置权限
chmod +x *.sh
chmod +x web_server.py

# 安装systemd服务
cp subcheck.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable subcheck
systemctl start subcheck

# 配置防火墙
if command -v ufw >/dev/null 2>&1; then
    ufw allow "$WEB_PORT"/tcp
fi

echo "[INFO] 安装完成!"
echo "[INFO] 服务状态: $(systemctl is-active subcheck)"
echo "[INFO] 访问地址: http://$(curl -s ifconfig.me):$WEB_PORT"
EOL
    
    chmod +x "$temp_dir/install.sh"
    
    # 创建压缩包
    tar -czf "subcheck-vps-deploy.tar.gz" -C "$temp_dir" .
    rm -rf "$temp_dir"
    
    print_info "部署包创建完成: subcheck-vps-deploy.tar.gz"
}

# 上传并部署
deploy_to_vps() {
    print_info "上传部署包到VPS..."
    
    # 上传文件
    scp -P "$VPS_PORT" subcheck-vps-deploy.tar.gz "$VPS_USER@$VPS_HOST:/tmp/"
    
    # 远程执行部署
    ssh -p "$VPS_PORT" "$VPS_USER@$VPS_HOST" << EOF
set -e
cd /tmp
tar -xzf subcheck-vps-deploy.tar.gz -C /tmp/subcheck-deploy/
mkdir -p /tmp/subcheck-deploy
tar -xzf subcheck-vps-deploy.tar.gz -C /tmp/subcheck-deploy/
bash /tmp/subcheck-deploy/install.sh "$DEPLOY_PATH" "$WEB_PORT"
rm -rf /tmp/subcheck-deploy /tmp/subcheck-vps-deploy.tar.gz
EOF
    
    print_info "部署完成!"
}

# 检查部署状态
check_deployment() {
    print_info "检查部署状态..."
    
    ssh -p "$VPS_PORT" "$VPS_USER@$VPS_HOST" << EOF
echo "=== 服务状态 ==="
systemctl status subcheck --no-pager
echo ""
echo "=== 端口监听 ==="
netstat -tlnp | grep :$WEB_PORT || echo "端口 $WEB_PORT 未监听"
echo ""
echo "=== 防火墙状态 ==="
if command -v ufw >/dev/null 2>&1; then
    ufw status | grep $WEB_PORT || echo "防火墙规则未找到"
fi
EOF
    
    # 获取VPS外网IP
    local vps_ip
    vps_ip=$(ssh -p "$VPS_PORT" "$VPS_USER@$VPS_HOST" "curl -s ifconfig.me" 2>/dev/null || echo "$VPS_HOST")
    
    print_info "=== 部署信息 ==="
    echo "VPS地址: $VPS_HOST"
    echo "外网IP: $vps_ip"
    echo "访问地址: http://$vps_ip:$WEB_PORT"
    echo "部署路径: $DEPLOY_PATH"
    echo ""
    echo "=== 管理命令 ==="
    echo "查看日志: ssh $VPS_USER@$VPS_HOST -p $VPS_PORT 'journalctl -u subcheck -f'"
    echo "重启服务: ssh $VPS_USER@$VPS_HOST -p $VPS_PORT 'systemctl restart subcheck'"
    echo "停止服务: ssh $VPS_USER@$VPS_HOST -p $VPS_PORT 'systemctl stop subcheck'"
}

# 主函数
main() {
    print_info "=== SubCheck VPS 部署工具 ==="
    print_info "目标VPS: $VPS_USER@$VPS_HOST:$VPS_PORT"
    print_info "部署路径: $DEPLOY_PATH"
    print_info "Web端口: $WEB_PORT"
    echo ""
    
    # 测试SSH连接
    if ! test_ssh_connection; then
        exit 1
    fi
    
    # 创建部署包
    create_deployment_package
    
    # 部署到VPS
    deploy_to_vps
    
    # 等待服务启动
    print_info "等待服务启动..."
    sleep 5
    
    # 检查部署状态
    check_deployment
    
    # 清理本地文件
    rm -f subcheck-vps-deploy.tar.gz
    
    print_info "🎉 部署完成! 现在可以通过Web界面使用SubCheck服务了"
}

# 运行主函数
main
