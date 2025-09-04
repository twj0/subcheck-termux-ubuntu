# SubCheck - 订阅节点测试工具

一个专为中国大陆网络环境优化的订阅节点测试工具，支持多种代理协议的连通性和速度测试。

## ✨ 特性

- 🚀 **高性能并发测试** - 智能代理池，减少启动延迟
- 📊 **多协议支持** - VLESS、VMess、Trojan、Shadowsocks
- 🌍 **中国大陆优化** - GitHub代理、DNS优化、网络适配
- 📈 **智能配置** - 自动计算最优并发数，基于网络带宽
- 🔧 **灵活配置** - YAML配置文件，支持用户自定义
- 📱 **跨平台支持** - Ubuntu、Termux、WSL

## 🚀 快速开始

### 1. 安装

```bash
# 克隆项目
git clone https://github.com/your-repo/subcheck-termux-ubuntu.git
cd subcheck-termux-ubuntu

# 一键安装（支持GitHub代理）
bash scripts/install.sh
```

### 2. 配置

```bash
# 编辑订阅源
nano config/subscription.txt

# 调整配置（可选）
nano config/config.yaml
```

### 3. 运行

```bash
# 方式1: 使用Python CLI（推荐）
python3 src/cli/main.py run config/subscription.txt -n 50

# 方式2: 使用Shell脚本
bash scripts/test.sh 50

# 方式3: 分步执行
python3 src/cli/main.py parse config/subscription.txt
python3 src/cli/main.py test data/cache/parsed_nodes.json -n 50
```

## 📁 项目结构

```
subcheck-termux-ubuntu/
├── 📁 config/              # 配置文件
│   ├── config.yaml         # 主配置文件
│   └── subscription.txt    # 订阅源列表
├── 📁 src/                 # 源代码
│   ├── 📁 core/            # 核心模块
│   │   ├── config_manager.py
│   │   ├── subscription_parser.py
│   │   └── optimized_network_tester.py
│   ├── 📁 cli/             # 命令行接口
│   │   └── main.py         # 主入口
│   └── 📁 utils/           # 工具模块
├── 📁 scripts/             # 脚本文件
│   ├── install.sh          # 安装脚本
│   ├── test.sh            # 测试脚本
│   └── 📁 legacy/          # 旧版脚本
├── 📁 data/                # 数据目录
│   ├── 📁 cache/           # 缓存文件
│   ├── 📁 logs/            # 日志文件
│   ├── 📁 results/         # 测试结果
│   └── 📁 temp/            # 临时文件
└── 📁 docs/                # 文档
```

## ⚙️ 配置说明

### 网络设置
```yaml
network:
  user_bandwidth: 300        # 用户网速(Mbps)
  auto_concurrent: true      # 自动计算并发数
  manual_concurrent: 5       # 手动并发数
```

### 测试参数
```yaml
test:
  max_nodes: 50             # 最大测试节点数
  timeout:
    connect: 8              # TCP连接超时
    latency: 5              # 延迟测试超时
    speed: 15               # 速度测试超时
```

### 代理优化
```yaml
proxy:
  port_range:
    start: 10800            # 代理端口范围
    end: 10900
  startup:
    parallel_limit: 10      # 并行启动数量
    warmup_time: 1          # 预热时间
```

## 📊 使用示例

### 基础用法
```bash
# 测试50个节点
python3 src/cli/main.py run config/subscription.txt -n 50

# 只解析订阅，不测试
python3 src/cli/main.py parse config/subscription.txt

# 只测试已解析的节点
python3 src/cli/main.py test data/cache/parsed_nodes.json -n 30
```

### 高级用法
```bash
# 自定义输出路径
python3 src/cli/main.py run config/subscription.txt \
  --nodes-output custom_nodes.json \
  --results-output custom_results.json

# 使用Shell脚本（兼容旧版）
bash scripts/test.sh 100
```

## 🔧 性能优化

### 自动并发计算
基于用户网速自动计算最优并发数：
- 300Mbps → 48并发
- 100Mbps → 16并发  
- 50Mbps → 8并发

### 代理池技术
- 预启动10个空闲代理进程
- 动态重配置，避免重复启动
- 减少2-3秒的启动延迟

### GitHub代理支持
自动选择最快的GitHub代理：
- ghfast.top
- gh-proxy.com
- ghproxy.net
- mirror.ghproxy.com

## 📈 测试结果

### 输出格式
```json
{
  "name": "🇭🇰 香港节点",
  "server": "hk.example.com",
  "port": 443,
  "type": "vless",
  "tcp_latency": 45.2,
  "http_latency": 67.8,
  "download_speed": 25.6,
  "status": "success",
  "test_time": "2024-01-01T12:00:00"
}
```

### 结果分析
- **tcp_latency**: TCP连接延迟(ms)
- **http_latency**: HTTP请求延迟(ms)  
- **download_speed**: 下载速度(Mbps)
- **status**: 测试状态(success/failed)

## 🛠️ 故障排除

### 常见问题

**1. 成功率低**
```bash
# 检查配置
cat config/config.yaml

# 降低并发数
# 在config.yaml中设置: manual_concurrent: 3

# 增加超时时间
# 在config.yaml中设置: timeout.connect: 15
```

**2. Xray启动失败**
```bash
# 检查安装
xray version

# 重新安装
bash scripts/install.sh
```

**3. 订阅解析失败**
```bash
# 检查网络
curl -I https://www.google.com

# 查看日志
tail -f data/logs/subcheck.log
```

### 日志位置
- 主日志: `data/logs/subcheck.log`
- 详细日志: 程序运行时控制台输出

## 🚀 性能对比

| 版本 | 并发数 | 代理启动 | 测试50节点 | 成功率 |
|------|--------|----------|------------|--------|
| 旧版 | 3      | 2-3秒    | ~5分钟     | 2%     |
| 新版 | 48     | 0.5秒    | ~1分钟     | 预期>20% |

## 📝 开发

### 添加新协议
1. 在 `src/core/subscription_parser.py` 添加解析逻辑
2. 在 `src/core/optimized_network_tester.py` 添加配置生成
3. 更新测试用例

### 贡献代码
1. Fork 项目
2. 创建功能分支: `git checkout -b feature/new-feature`
3. 提交更改: `git commit -am 'Add new feature'`
4. 推送分支: `git push origin feature/new-feature`
5. 提交 Pull Request

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

感谢所有贡献者和开源项目的支持！

---

**⚠️ 免责声明**: 本工具仅用于网络测试目的，请遵守当地法律法规。
