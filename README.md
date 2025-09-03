# SubCheck Termux - 轻量级节点检查工具

专为 Termux + Ubuntu 等轻量级环境设计的代理节点检查工具。基于 Shell 脚本实现，支持多种代理协议的解析、延迟测试和速度测试。

## ✨ 功能特性

- **轻量级设计**：无需 Docker，纯 Shell 脚本 + Linux 工具链
- **多协议支持**：
    - VLESS/VMess 协议解析
    - Base64 编码订阅链接
    - Clash YAML 配置文件
- **智能测试**：
    - TCP 连接延迟测试
    - 下载/上传速度测试  
    - 可配置超时和重试机制
- **配置驱动**：支持 YAML 配置文件，可自定义所有参数
- **多输出格式**：JSON/YAML/Base64 格式输出
- **质量过滤**：支持最低速度和最大延迟阈值过滤

## 🔧 环境要求

- 一个基于 Debian/Ubuntu 的 Linux 环境 (专为 Termux PRoot Ubuntu 设计)。
- `sudo` 权限。
- 依赖的命令行工具 (将由 `init.sh` 自动安装):
    - `curl`
    - `wget`
    - `jq`
    - `yq`
    - `speedtest-cli`
    - `unzip`

## 🚀 快速开始

### 1. 克隆项目

```bash
git clone <your-repository-url>
cd subcheck-termux-ubuntu
```

### 2. 初始化环境

首次使用时，必须运行初始化脚本。它将安装所有必要的工具并下载 Xray 核心。

```bash
bash init.sh
```
该脚本会自动检查依赖和 Xray-core 是否存在，可以安全地重复运行。

### 3. 运行测试

使用 `main.sh` 脚本来启动测试。

**基本语法:**
```bash
bash main.sh -i <输入源> [-o <输出文件>]
```

- `-i <输入源>`: **必需参数**。可以是远程订阅链接 (URL) 或本地配置文件路径 (例如 `config.yaml`)。
- `-o <输出文件>`: **可选参数**。如果提供，测试结果将以 JSON 格式保存到指定文件；否则，将直接打印在控制台。

**示例:**

- **从 URL 订阅进行测试，并在控制台查看结果:**
  ```bash
  bash main.sh -i "https://example.com/your/subscription/link"
  ```

- **从本地 Clash 配置文件测试，并将结果保存到 `results.json`:**
  ```bash
  bash main.sh -i config_example.yaml -o results.json
  ```

## 📊 输出格式说明

脚本最终会输出一个 JSON 数组，其中每个对象代表一个节点的测试结果。

**成功节点的示例:**
```json
{
  "name": "Your-Node-Name-01",
  "success": true,
  "latency": 150,
  "download": 85.5,
  "upload": 20.1,
  "error": null
}
```

**失败节点的示例:**
```json
{
  "name": "Your-Node-Name-02",
  "success": false,
  "latency": -1,
  "download": -1,
  "upload": -1,
  "error": "Latency test failed (timeout or error)."
}
```

- `name` (string): 节点名称。
- `success` (boolean): `true` 表示测试成功, `false` 表示失败。
- `latency` (integer): 连接延迟（毫秒）。失败时为 `-1`。
- `download` (float): 下载速度 (Mbit/s)。失败时为 `-1`。
- `upload` (float): 上传速度 (Mbit/s)。失败时为 `-1`。
- `error` (string|null): 如果测试失败，这里会提供简要的错误信息。
