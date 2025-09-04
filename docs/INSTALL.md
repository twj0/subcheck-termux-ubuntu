# 安装指南

## 系统要求

- **操作系统**: Ubuntu 18.04+, Debian 10+, Termux, WSL
- **Python**: 3.8+
- **内存**: 最少512MB，推荐1GB+
- **网络**: 稳定的互联网连接

## 快速安装

### 方式1: 一键安装脚本（推荐）

```bash
# 下载并运行安装脚本
curl -fsSL https://raw.githubusercontent.com/your-repo/subcheck-termux-ubuntu/main/scripts/install.sh | bash

# 或者克隆后安装
git clone https://github.com/your-repo/subcheck-termux-ubuntu.git
cd subcheck-termux-ubuntu
bash scripts/install.sh
```

### 方式2: 手动安装

#### 1. 安装系统依赖

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install -y curl jq unzip bc python3 python3-pip
```

**Termux:**
```bash
pkg update
pkg install -y curl jq unzip bc python python-pip
```

#### 2. 安装Python依赖

```bash
# 使用国内镜像源
pip3 install -i https://pypi.tuna.tsinghua.edu.cn/simple -r requirements.txt

# 或使用默认源
pip3 install -r requirements.txt
```

#### 3. 安装Xray

**自动安装:**
```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
```

**手动安装:**
```bash
# 检测架构
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="64" ;;
    aarch64|arm64) ARCH="arm64-v8a" ;;
    armv7l) ARCH="arm32-v7a" ;;
esac

# 下载Xray
curl -L "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH}.zip" -o xray.zip
unzip xray.zip
sudo cp xray /usr/local/bin/
sudo chmod +x /usr/local/bin/xray
rm xray.zip xray
```

## 配置设置

### 1. 基础配置

```bash
# 复制配置模板
cp config/config.yaml.example config/config.yaml

# 编辑配置文件
nano config/config.yaml
```

### 2. 订阅源配置

```bash
# 编辑订阅源
nano config/subscription.txt

# 添加你的订阅链接，每行一个
# 示例:
# https://example.com/subscription1
# https://example.com/subscription2
```

### 3. 网络优化配置

根据你的网络环境调整配置：

**高速网络 (100Mbps+):**
```yaml
network:
  user_bandwidth: 300
  auto_concurrent: true

test:
  timeout:
    connect: 5
    latency: 3
    speed: 10
```

**普通网络 (50-100Mbps):**
```yaml
network:
  user_bandwidth: 100
  auto_concurrent: true

test:
  timeout:
    connect: 8
    latency: 5
    speed: 15
```

**慢速网络 (<50Mbps):**
```yaml
network:
  user_bandwidth: 50
  auto_concurrent: false
  manual_concurrent: 3

test:
  timeout:
    connect: 15
    latency: 10
    speed: 30
```

## 验证安装

### 1. 检查依赖

```bash
# 检查Python
python3 --version

# 检查Xray
xray version

# 检查工具
curl --version
jq --version
```

### 2. 运行测试

```bash
# 快速测试
python3 src/cli/main.py parse config/subscription.txt

# 如果解析成功，运行完整测试
python3 src/cli/main.py run config/subscription.txt -n 5
```

## 常见问题

### 1. 权限问题

```bash
# 如果遇到权限错误
sudo chown -R $USER:$USER .
chmod +x scripts/*.sh
```

### 2. Python模块缺失

```bash
# 重新安装依赖
pip3 install --upgrade pip
pip3 install -r requirements.txt --force-reinstall
```

### 3. Xray安装失败

```bash
# 使用GitHub代理重试
export GITHUB_PROXY="https://ghfast.top/"
bash scripts/install.sh
```

### 4. 网络连接问题

```bash
# 测试网络连接
curl -I https://www.google.com

# 测试GitHub连接
curl -I https://github.com

# 使用代理测试
curl -I --proxy socks5://127.0.0.1:1080 https://www.google.com
```

## 卸载

```bash
# 停止所有进程
pkill -f xray
pkill -f python3.*subcheck

# 删除Xray
sudo rm -f /usr/local/bin/xray

# 删除项目文件
rm -rf subcheck-termux-ubuntu

# 删除Python依赖（可选）
pip3 uninstall -r requirements.txt -y
```

## 更新

```bash
# 拉取最新代码
git pull origin main

# 更新依赖
pip3 install -r requirements.txt --upgrade

# 重新安装Xray（如果需要）
bash scripts/install.sh
```
