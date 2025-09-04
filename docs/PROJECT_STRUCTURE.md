# SubCheck 项目结构说明

## 目录结构

```
subcheck-termux-ubuntu/
├── docs/                   # 文档目录
│   ├── README.md          # 主要文档
│   ├── INSTALL.md         # 安装指南
│   ├── CONFIG.md          # 配置说明
│   └── API.md             # API文档
├── src/                   # 源代码目录
│   ├── core/              # 核心模块
│   │   ├── __init__.py
│   │   ├── config_manager.py      # 配置管理
│   │   ├── subscription_parser.py # 订阅解析
│   │   ├── network_tester.py      # 网络测试
│   │   └── optimized_network_tester.py # 优化版测试器
│   ├── utils/             # 工具模块
│   │   ├── __init__.py
│   │   ├── logger.py      # 日志工具
│   │   ├── proxy_manager.py # 代理管理
│   │   └── report_generator.py # 报告生成
│   └── cli/               # 命令行接口
│       ├── __init__.py
│       └── main.py        # 主入口
├── scripts/               # 脚本目录
│   ├── install.sh         # 安装脚本
│   ├── test.sh           # 测试脚本
│   ├── parse.sh          # 解析脚本
│   └── legacy/           # 旧版脚本
├── config/               # 配置目录
│   ├── config.yaml       # 主配置文件
│   ├── subscription.txt  # 订阅源
│   └── templates/        # 配置模板
├── data/                 # 数据目录
│   ├── cache/           # 缓存文件
│   ├── logs/            # 日志文件
│   ├── results/         # 测试结果
│   └── temp/            # 临时文件
├── tests/               # 测试目录
│   ├── __init__.py
│   ├── test_parser.py   # 解析器测试
│   └── test_tester.py   # 测试器测试
├── requirements.txt     # Python依赖
├── pyproject.toml      # 项目配置
├── .gitignore          # Git忽略文件
└── README.md           # 项目说明
```

## 核心组件

### 1. 配置管理 (config_manager.py)
- 统一配置文件管理
- 动态参数计算
- 网络带宽自适应

### 2. 订阅解析 (subscription_parser.py)
- 多格式订阅解析
- GitHub代理支持
- 智能缓存机制

### 3. 网络测试 (optimized_network_tester.py)
- 代理池管理
- 并发测试优化
- 实时性能监控

### 4. 脚本工具
- 一键安装脚本
- 自动化测试脚本
- 结果分析脚本

## 使用流程

1. **安装**: `bash scripts/install.sh`
2. **配置**: 编辑 `config/config.yaml` 和 `config/subscription.txt`
3. **测试**: `bash scripts/test.sh [节点数量]`
4. **查看结果**: `data/results/` 目录下的文件

## 配置说明

主要配置文件位于 `config/config.yaml`，包含：
- 网络设置（带宽、并发数）
- 测试参数（超时、重试）
- 代理配置（端口范围、启动优化）
- GitHub代理（镜像源）
- 日志设置
