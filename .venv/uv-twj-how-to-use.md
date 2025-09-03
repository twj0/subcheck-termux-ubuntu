# 🔮 uv 高级使用指南 (twj 定制版)

由您的专属 uv-twj 命令在 $(Get-Date) 自动生成。

---

## 一、基础核心用法 (日常必备)

这些是您每天都会用到的命令。

- **创建环境 (您刚已执行)**:
  uv-twj -p 3.11
  > 如果本地没有 Python 3.11，uv 会像 
vm 一样自动为您下载！

- **激活环境**:
  .\.venv\Scripts\activate
  > 在 VS Code 中，通常只需选择一次解释器，终端就会自动激活。

- **安装包**:
  uv pip install numpy pandas "fastapi[all]"
  > 速度是传统 pip 的 10-100 倍。

- **固化环境到文件**:
  uv pip freeze > requirements.txt
  > 将当前环境所有包的精确版本记录下来，用于分享和部署。

- **从文件恢复环境**:
  uv pip install -r requirements.txt
  > 在新机器上或为同事快速复刻一模一样的环境。

---

## 二、进阶知识 (冷门但极其有用)

掌握这些，让您超越大多数使用者。

### 1. uv pip sync：真正的环境同步利器

这可能是 uv 最强大的命令之一。它和 install -r 有本质区别：

- uv pip install -r requirements.txt: **只会添加和更新** equirements.txt 中列出的包。
- uv pip sync requirements.txt: **会严格同步**！它会确保您的虚拟环境**不多不少**，与  equirements.txt  文件**完全一致**。如果环境中有多余的包，sync 会**自动将它们卸载**。
  > **最佳实践**: 在 CI/CD 或部署生产环境时，永远使用 sync 而不是 install，确保环境的纯净和可复现性。

### 2. uv cache：缓存管理

uv 的高速来自于其智能的全局缓存。

- **查看缓存信息**: uv cache dir (显示缓存目录的位置)
- **清理缓存**: uv cache clean
  > **场景**: 当您遇到奇怪的包安装问题，或者想释放一些磁盘空间时，可以尝试清理缓存。

### 3. --seed：创建带基础工具的环境

默认 uv venv 创建的是一个“纯净”环境，里面连 pip 都没有。

- uv-twj -p 3.11 --seed
  > 这个 --seed 参数会在创建环境时，自动为您预装 pip, setuptools 和 wheel 这三个基础包。这样您就可以在新环境里直接使用 pip 命令了 (虽然我们更推荐用 uv pip ...)。

### 4. uv pip tree：依赖关系透视镜

当您遇到复杂的依赖冲突时（比如 "A 需要版本 1.0 的 X，但 B 需要版本 2.0 的 X"），uv pip list 就不够用了。

- uv pip tree
  > 它会以树状图的形式，清晰地展示出哪个包依赖了哪个包，让您对整个环境的依赖关系一目了然，是排查问题的神器。

### 5. --offline：离线模式

在没有网络连接或需要极速构建的环境 (如 Docker build) 中非常有用。

- uv pip install --offline -r requirements.txt
  > uv 会只使用本地缓存中的包进行安装，不会尝试连接网络。前提是所有需要的包都已经在缓存中了。

### 6. 直接从 Git 仓库安装

- uv pip install git+https://github.com/psf/requests.git
  > 可以直接安装最新的、还未发布到 PyPI 的开发版代码。

---

希望这份指南对您有帮助！
