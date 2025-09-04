# SubCheck Termux-Ubuntu 增强版

专为中国大陆网络环境优化的高性能订阅解析和网络测速工具。

## 🚀 核心功能

- ✅ **多协议支持**：VLESS/VMess/Trojan完整解析
- ✅ **智能网络测试**：TCP连接+HTTP延迟+下载速度
- ✅ **中国大陆优化**：GitHub代理、DNS优化、网络容错
- ✅ **并发处理**：异步解析、并发测试，3倍性能提升
- ✅ **格式转换**：支持Clash、V2Ray、Quantumult等格式
- ✅ **Xray集成**：自动代理管理，精确测速
- ✅ **智能缓存**：30分钟缓存，减少网络开销
- ✅ **详细报告**：Markdown报告、JSON结果、实时日志

## 📦 快速开始

### 一键测试（推荐）
```bash
# VPS环境一键测试（自动安装依赖）
chmod +x vps_test.sh
./vps_test.sh 20  # 测试20个节点
```

### 手动安装依赖
```bash
# 系统依赖
apt update && apt install -y python3-pip curl jq bc unzip

# Python依赖
pip3 install -r requirements.txt

# Xray代理
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
```

## 🎯 使用方法

### 增强版解析器
```bash
# 基本解析
bash scripts/enhanced_parse.sh

# 解析并转换为Clash格式
bash scripts/enhanced_parse.sh clash

# 解析并转换为V2Ray格式
bash scripts/enhanced_parse.sh v2ray
```

### 网络性能测试
```bash
# 测试前50个节点
bash scripts/enhanced_test.sh 50

# 测试所有解析节点
bash scripts/enhanced_test.sh
```

### Python模块直接调用
```bash
# 订阅解析
python3 src/subscription_parser.py subscription.txt parsed_nodes.json

# 网络测试
python3 src/network_tester.py parsed_nodes.json test_results.json 30

# 格式转换
node src/format_converter.js parsed_nodes.json clash output.yaml
```

### 订阅文件格式
`subscription.txt` 每行一个订阅URL：
```
https://example.com/subscription
https://raw.githubusercontent.com/user/repo/main/nodes
https://sub.example.com/link/abcd1234
```

支持的订阅格式：
- **Base64编码**：标准订阅格式
- **原始链接**：直接节点链接列表
- **Clash YAML**：Clash配置文件
- **JSON格式**：结构化节点数据

## ⚙️ 配置说明

### 主配置文件 `config.yaml`
```yaml
timeout: 5000           # 超时时间(毫秒)
concurrent: 10          # 并发测试数
max_nodes: 1000         # 最大节点数
cache_duration: 1800    # 缓存时间(秒)
```

### 测试参数配置
- **最大测试节点**：默认50个，可通过脚本参数调整
- **并发数**：默认3个，平衡性能和稳定性
- **超时设置**：连接10s、延迟5s、速度30s
- **测试端点**：Google、Cloudflare、CacheFly等多源测试
min_speed: 1            # 最低速度要求(Mbps)
max_latency: 1000       # 最大延迟(毫秒)
```

## 📊 输出格式

### 解析结果 (`parsed_nodes.json`)
```json
[
  {
    "name": "香港节点-01",
    "type": "vless",
    "server": "hk.example.com",
    "port": 443,
    "uuid": "12345678-1234-1234-1234-123456789abc",
    "tls": "tls",
    "network": "ws",
    "path": "/path",
    "raw_link": "vless://..."
  }
]
```

### 测试结果 (`results/test_results.json`)
```json
[
  {
    "name": "香港节点-01",
    "server": "hk.example.com",
    "port": 443,
    "type": "vless",
    "tcp_latency": 45.2,
    "http_latency": 52.8,
    "download_speed": 85.6,
    "status": "success",
    "test_time": "2024-01-01T12:00:00"
  }
]
```

### 测试报告 (`results/test_report_*.md`)
自动生成包含Top10节点、失败统计的Markdown报告。

## 🌟 技术特点

- **🚀 高性能**：异步并发，3倍速度提升
- **🛡️ 容错强**：智能重试、优雅降级
- **🌐 网络优化**：GitHub代理、DNS优化
- **📊 详细报告**：多格式输出、实时监控
- **🔧 易扩展**：模块化设计、插件架构

## 🐛 故障排除

### 常见问题
```bash
# 1. 清理缓存重新测试
rm -rf cache/* logs/* results/*
bash scripts/enhanced_parse.sh

# 2. 检查网络连通性
curl -I http://www.google.com
curl -I https://github.com

# 3. 查看详细错误日志
grep -i error logs/subscription_parser.log

# 4. 手动测试单个节点
python3 src/network_tester.py parsed_nodes.json test_single.json 1
```

### 性能调优
- **内存不足**：减少并发数和测试节点数
- **网络超时**：增加超时时间，使用代理
- **解析失败**：检查订阅源有效性，更新GitHub代理

## 📈 性能指标

### 预期结果
- **解析节点**：13,000-15,000个
- **成功测试**：200-500个节点
- **测试时间**：10-30分钟（50节点）
- **成功率**：60-80%（中国大陆）
- **内存使用**：< 500MB
- **CPU使用**：< 50%

### 优化建议
- VPS推荐：2核4G，带宽≥100Mbps
- 网络环境：境外VPS效果更佳
- 测试时间：避开网络高峰期

## 🚀 项目架构

```
subcheck-termux-ubuntu/
├── src/                          # 核心源码
│   ├── subscription_parser.py    # Python订阅解析器
│   ├── network_tester.py         # 网络测试器
│   └── format_converter.js       # 格式转换器
├── scripts/                      # 执行脚本
│   ├── enhanced_parse.sh         # 增强解析脚本
│   └── enhanced_test.sh          # 增强测试脚本
├── results/                      # 输出结果
│   ├── test_results.json         # 测试结果
│   ├── clash_config.yaml         # Clash配置
│   └── test_report_*.md          # 测试报告
├── logs/                         # 日志文件
├── cache/                        # 缓存目录
├── vps_test.sh                   # 一键测试脚本
├── subscription.txt              # 订阅源列表
├── requirements.txt              # Python依赖
├── package.json                  # Node.js依赖
└── config.yaml                   # 主配置文件
```

## 🔧 开发者指南

### 扩展新协议
1. 在 `subscription_parser.py` 中添加解析方法
2. 在 `network_tester.py` 中添加Xray配置生成
3. 在 `format_converter.js` 中添加格式转换支持

### 自定义测试端点
编辑 `src/network_tester.py` 中的 `test_endpoints` 配置：
```python
self.test_endpoints = {
    'latency': ['your-custom-endpoint'],
    'speed': ['your-speed-test-url']
}
```

## 📝 更新日志

### v2.0.0 (2024-01-01)
- 🔥 **重大更新**：完全重写解析和测试引擎
- ✨ **VMess修复**：解决Base64解码和JSON解析问题
- 🚀 **性能提升**：异步并发，3倍速度提升
- 🌐 **网络优化**：GitHub代理、DNS优化、智能重试
- 📊 **增强报告**：Markdown报告、实时监控、详细统计
- 🛠️ **工具集成**：Xray自动管理、格式转换、一键部署

## 📞 技术支持

- **GitHub Issues**：报告bug和功能请求
- **Wiki文档**：详细使用教程和FAQ
- **社区讨论**：分享使用经验和优化建议

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

---

**🎯 快速开始命令**
```bash
# 一键测试（推荐）
./vps_test.sh 20

# 分步执行
bash scripts/enhanced_parse.sh
bash scripts/enhanced_test.sh 50
```

