# 使用指南

## 基本使用

### 1. 快速开始

```bash
# 完整流程：解析订阅 + 测试节点
python3 src/cli/main.py run config/subscription.txt -n 50

# 使用Shell脚本（兼容旧版）
bash scripts/test.sh 50
```

### 2. 分步操作

```bash
# 步骤1: 解析订阅源
python3 src/cli/main.py parse config/subscription.txt

# 步骤2: 测试节点
python3 src/cli/main.py test data/cache/parsed_nodes.json -n 30
```

## 命令详解

### CLI命令

```bash
# 查看帮助
python3 src/cli/main.py --help

# 解析订阅
python3 src/cli/main.py parse <订阅文件> [-o 输出文件]

# 测试节点
python3 src/cli/main.py test <节点文件> [-o 输出文件] [-n 最大节点数]

# 完整流程
python3 src/cli/main.py run <订阅文件> [-n 最大节点数] [--nodes-output 节点输出] [--results-output 结果输出]
```

### 参数说明

- `-n, --max-nodes`: 最大测试节点数
- `-o, --output`: 输出文件路径
- `--nodes-output`: 节点文件输出路径
- `--results-output`: 测试结果输出路径

## 配置调优

### 网络配置

根据你的网络环境调整 `config/config.yaml`:

```yaml
network:
  user_bandwidth: 300        # 你的网速(Mbps)
  auto_concurrent: true      # 自动计算并发数
```

### 测试参数

```yaml
test:
  max_nodes: 50             # 最大测试节点数
  timeout:
    connect: 8              # TCP连接超时(秒)
    latency: 5              # 延迟测试超时(秒)
    speed: 15               # 速度测试超时(秒)
```

### 代理优化

```yaml
proxy:
  startup:
    parallel_limit: 10      # 并行启动代理数
    warmup_time: 1          # 代理预热时间(秒)
    health_check: true      # 启动后健康检查
```

## 高级用法

### 1. 自定义输出路径

```bash
# 自定义所有输出路径
python3 src/cli/main.py run config/subscription.txt \
  --nodes-output /tmp/my_nodes.json \
  --results-output /tmp/my_results.json \
  -n 100
```

### 2. 批量测试

```bash
# 创建批量测试脚本
cat > batch_test.sh << 'EOF'
#!/bin/bash
for count in 10 20 50 100; do
    echo "Testing $count nodes..."
    python3 src/cli/main.py run config/subscription.txt -n $count \
      --results-output "data/results/test_${count}_nodes.json"
    sleep 60  # 等待1分钟
done
EOF

chmod +x batch_test.sh
./batch_test.sh
```

### 3. 定时测试

```bash
# 添加到crontab
crontab -e

# 每小时测试一次
0 * * * * cd /path/to/subcheck && python3 src/cli/main.py run config/subscription.txt -n 30

# 每天凌晨2点完整测试
0 2 * * * cd /path/to/subcheck && python3 src/cli/main.py run config/subscription.txt -n 100
```

## 结果分析

### 1. 查看测试结果

```bash
# 查看JSON结果
cat data/results/test_results.json | jq '.[] | select(.status == "success") | {name, server, http_latency, download_speed}'

# 按延迟排序
cat data/results/test_results.json | jq 'sort_by(.http_latency) | .[] | select(.status == "success") | {name, http_latency, download_speed}'

# 统计成功率
total=$(cat data/results/test_results.json | jq 'length')
success=$(cat data/results/test_results.json | jq '[.[] | select(.status == "success")] | length')
echo "成功率: $((success * 100 / total))%"
```

### 2. 生成报告

```bash
# 使用内置报告生成器
python3 -c "
import json
with open('data/results/test_results.json') as f:
    results = json.load(f)

success = [r for r in results if r['status'] == 'success']
print(f'总节点: {len(results)}')
print(f'成功节点: {len(success)}')
print(f'成功率: {len(success)/len(results)*100:.1f}%')

if success:
    success.sort(key=lambda x: x.get('http_latency', 9999))
    print('\n最佳节点:')
    for i, r in enumerate(success[:5]):
        print(f'{i+1}. {r[\"name\"][:30]} - {r.get(\"http_latency\", \"N/A\")}ms')
"
```

## 故障排除

### 1. 调试模式

```bash
# 启用详细日志
export PYTHONPATH=$PWD/src
python3 -c "
from core.config_manager import config
config.update_config('logging.level', 'DEBUG')
config.save_config()
"

# 运行测试
python3 src/cli/main.py run config/subscription.txt -n 5
```

### 2. 单节点测试

```bash
# 提取单个节点进行测试
cat data/cache/parsed_nodes.json | jq '.[0:1]' > single_node.json
python3 src/cli/main.py test single_node.json
```

### 3. 网络诊断

```bash
# 检查网络连接
curl -I https://www.google.com

# 检查DNS解析
nslookup google.com 223.5.5.5

# 测试代理连接
curl --proxy socks5://127.0.0.1:10808 -I https://www.google.com
```

## 性能优化建议

### 1. 根据硬件调整

**高性能服务器 (8核+, 16GB+):**
```yaml
network:
  user_bandwidth: 1000
test:
  max_nodes: 200
proxy:
  startup:
    parallel_limit: 20
performance:
  cpu_cores: 8
  async_io:
    connector_limit: 200
```

**普通VPS (2核, 4GB):**
```yaml
network:
  user_bandwidth: 300
test:
  max_nodes: 50
proxy:
  startup:
    parallel_limit: 10
performance:
  cpu_cores: 2
  async_io:
    connector_limit: 100
```

**低配置设备 (1核, 1GB):**
```yaml
network:
  user_bandwidth: 100
  auto_concurrent: false
  manual_concurrent: 3
test:
  max_nodes: 20
proxy:
  startup:
    parallel_limit: 5
performance:
  memory_limit: 256
  async_io:
    connector_limit: 50
```

### 2. 网络环境优化

**中国大陆:**
```yaml
github_proxy:
  enabled: true
  auto_select: true
subscription:
  concurrent_parse: 5  # 降低并发避免被限制
```

**海外环境:**
```yaml
github_proxy:
  enabled: false
subscription:
  concurrent_parse: 15  # 可以提高并发
```

## 常见使用场景

### 1. 日常节点筛选

```bash
# 快速筛选可用节点
python3 src/cli/main.py run config/subscription.txt -n 30

# 查看最佳节点
cat data/results/test_results.json | jq '[.[] | select(.status == "success")] | sort_by(.http_latency) | .[0:5] | .[] | {name, server, http_latency, download_speed}'
```

### 2. 节点质量监控

```bash
# 创建监控脚本
cat > monitor.sh << 'EOF'
#!/bin/bash
while true; do
    echo "$(date): Starting test..."
    python3 src/cli/main.py run config/subscription.txt -n 50 \
      --results-output "data/results/monitor_$(date +%Y%m%d_%H%M%S).json"
    
    # 分析结果
    latest=$(ls -t data/results/monitor_*.json | head -1)
    success_rate=$(cat "$latest" | jq '[.[] | select(.status == "success")] | length / length * 100')
    echo "$(date): Success rate: ${success_rate}%"
    
    sleep 3600  # 每小时测试一次
done
EOF
```

### 3. 节点对比分析

```bash
# 对比不同时间的测试结果
python3 -c "
import json, glob
files = sorted(glob.glob('data/results/test_*.json'))
for f in files[-3:]:  # 最近3次测试
    with open(f) as file:
        results = json.load(file)
    success = len([r for r in results if r['status'] == 'success'])
    print(f'{f}: {success}/{len(results)} ({success/len(results)*100:.1f}%)')
"
```
