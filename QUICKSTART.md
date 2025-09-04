# 🚀 SubCheck 快速开始指南

## 30秒快速测试

```bash
# 1. 克隆项目
git clone https://github.com/your-repo/subcheck-termux-ubuntu.git
cd subcheck-termux-ubuntu

# 2. 一键安装
bash scripts/install.sh

# 3. 立即测试
python3 src/cli/main.py run config/subscription.txt -n 20
```

## 📋 使用方法

### 方式1: Python CLI（推荐）

```bash
# 完整流程
python3 src/cli/main.py run config/subscription.txt -n 50

# 分步执行
python3 src/cli/main.py parse config/subscription.txt
python3 src/cli/main.py test data/cache/parsed_nodes.json -n 30
```

### 方式2: Shell脚本（兼容旧版）

```bash
bash scripts/test.sh 50
```

## ⚙️ 配置你的网速

编辑 `config/config.yaml`：

```yaml
network:
  user_bandwidth: 300  # 改为你的实际网速(Mbps)
```

系统会自动计算最优并发数：
- 300Mbps → 48并发
- 100Mbps → 16并发
- 50Mbps → 8并发

## 📊 查看结果

```bash
# 查看测试结果
cat data/results/test_results.json | jq '.[] | select(.status == "success") | {name, http_latency, download_speed}'

# 查看最佳节点
cat data/results/test_results.json | jq 'sort_by(.http_latency) | .[] | select(.status == "success") | {name, http_latency, download_speed}' | head -20
```

## 🔧 常见问题

**成功率低？**
- 降低并发数：在config.yaml中设置 `manual_concurrent: 3`
- 增加超时：设置 `timeout.connect: 15`

**安装失败？**
- 使用GitHub代理：`export GITHUB_PROXY="https://ghfast.top/"`
- 重新运行：`bash scripts/install.sh`

**Xray错误？**
- 检查安装：`xray version`
- 重新安装：`sudo rm /usr/local/bin/xray && bash scripts/install.sh`

## 📁 重要文件

- `config/config.yaml` - 主配置文件
- `config/subscription.txt` - 订阅源列表
- `data/results/test_results.json` - 测试结果
- `data/logs/subcheck.log` - 运行日志

## 🎯 性能提升

相比旧版本：
- ⚡ **速度提升**: 5分钟 → 1分钟 (测试50节点)
- 🚀 **并发优化**: 3并发 → 48并发 (300Mbps网速)
- 💾 **内存优化**: 代理池技术，减少资源占用
- 🌐 **网络优化**: GitHub代理，适配中国大陆网络

立即开始测试你的订阅节点吧！
