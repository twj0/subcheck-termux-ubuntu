# SubCheck 精简版

一个轻量级的网络节点测速工具，专注于核心功能。

## 🚀 核心功能

- ✅ 订阅解析（VLESS/VMess）
- ✅ 延迟测试
- ✅ 速度测试  
- ✅ JSON结果输出
- ✅ 中国网络优化

## 📦 安装依赖

```bash
# Termux
pkg install curl jq

# Ubuntu/Debian
apt install curl jq
```

## 🎯 使用方法

### 基本使用
```bash
# 测试订阅文件
./subcheck.sh subscription.txt

# 测试URL订阅
./subcheck.sh https://example.com/sub

# 指定输出文件
./subcheck.sh subscription.txt results.json
```

### 订阅文件格式
每行一个订阅URL或节点链接：
```
https://example.com/subscription
vless://uuid@domain:443?type=tls&security=reality#节点名称
```

## ⚙️ 配置说明

编辑 `config.yaml` 文件：

```yaml
timeout: 5000           # 超时时间(毫秒)
concurrent: 10          # 并发测试数
min_speed: 1            # 最低速度要求(Mbps)
max_latency: 1000       # 最大延迟(毫秒)
```

## 📊 输出格式

JSON格式结果：
```json
[
  {
    "name": "节点名称",
    "address": "1.2.3.4",
    "port": "443",
    "latency": 150,
    "speed": 50,
    "success": true
  }
]
```

## 🌟 特点

- **轻量级**: 单个脚本文件，无需复杂依赖
- **快速**: 优化的测试算法，减少等待时间
- **稳定**: 完善的错误处理和超时机制
- **兼容**: 支持Termux和标准Linux环境

## 🐛 问题排查

如果遇到问题：
1. 检查网络连接
2. 确认订阅URL有效
3. 查看脚本输出错误信息

## 📄 许可证

MIT License