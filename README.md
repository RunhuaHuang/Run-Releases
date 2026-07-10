<div align="center">

# Run

**面向通用任务的 AI Agent 桌面应用**

本仓库托管 Run 的公开发行版与一键安装入口，产品源码于独立仓库维护。

[最新版本](https://github.com/RunhuaHuang/Run-Releases/releases/latest) · [全部版本](https://github.com/RunhuaHuang/Run-Releases/releases)

</div>

---

## 📦 安装包下载

> 以下链接随每次发版自动更新为最新版本（当前 v0.14.17）。

不想用命令行一键安装？也可直接下载安装包，解压后双击对应文件即可，全程自动配置 Git 与 Node.js。

### macOS（Apple Silicon）

下载 **DMG 安装镜像**：

👉 [`Run-0.14.17-arm64.dmg`](https://github.com/RunhuaHuang/Run-Releases/releases/download/v0.14.17/Run-0.14.17-arm64.dmg)

下载后：

1. 双击 `.dmg` 挂载镜像；
2. 在弹出的安装窗口中双击 **`双击一键安装.command`**；
3. 脚本会自动完成：拷贝 Run.app 到「应用程序」→ 配置 Git → 配置 Node.js → 启动 Run。

### Windows x64

下载 **一键安装压缩包**：

👉 [`Run-Windows-OneClick-v0.14.17.zip`](https://github.com/RunhuaHuang/Run-Releases/releases/download/v0.14.17/Run-Windows-OneClick-v0.14.17.zip)

下载后：

1. 解压 ZIP（建议右键 →「全部解压缩」）；
2. 进入解压后的文件夹，双击 **`双击一键安装.bat`**；
3. 弹出 UAC 提权窗口时点击「是」，脚本会自动完成：安装 Run 主程序 → 配置 Git → 配置 Node.js → 启动 Run。

> [!TIP]
> 安装包内的脚本与下方「一键安装」命令做的事完全一样，区别只是：下载安装包 = 手动下载文件；一键安装 = 用一条命令自动下载 + 安装。

---

## 一键安装

请根据你的网络环境选择对应命令：

- **能直连 GitHub**（有 VPN）：用「直连」命令。
- **不能直连 GitHub**（无 VPN，国内网络）：用任意一组「代理」命令。两家代理速度各异，可逐一尝试取最快的一组；其中 `gh-proxy.com` 通常最快。

### macOS（Apple Silicon）

直连：

```bash
curl -fsSL https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.sh | bash
```

代理 gh-proxy.com：

```bash
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.sh | RUN_GH_PROXY=https://gh-proxy.com bash
```

代理 ghproxy.net：

```bash
curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.sh | RUN_GH_PROXY=https://ghproxy.net bash
```

### Windows x64（管理员 PowerShell）

直连：

```powershell
irm https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex
```

代理 gh-proxy.com：

```powershell
$env:RUN_GH_PROXY='https://gh-proxy.com'; irm https://gh-proxy.com/https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex
```

代理 ghproxy.net：

```powershell
$env:RUN_GH_PROXY='https://ghproxy.net'; irm https://ghproxy.net/https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex
```

> [!NOTE]
> 所有安装包均经 sha512 完整性校验。两家均为第三方公共代理，可用性与速度可能随时间波动；如某一组失败或过慢，请换用另一组。

---

## 安装流程

安装脚本会自动完成主程序与运行环境的部署：**安装 Run → 配置 Git → 配置 Node.js → 启动**。所需依赖均从固定的 `bootstrap` 发行版下载并校验，无需手动配置。macOS 将自动解除隔离属性并完成首次启动，Windows 则静默安装至默认路径。

应用内置自动更新，默认通过 GitHub 直连下载新版本。如遇直连缓慢或失败，可在「设置 → 关于」处即时切换下载线路（GitHub 直连 / `gh-proxy.com` / `ghfast.top` / `ghproxy.net` 代理）。

---

## 致谢

Run 的实现离不开开源社区的诸多成果，谨致谢意：

- **Claude Agent SDK** —— Agent 能力的核心驱动框架
- **Proma** —— 整个项目改写的基础框架
- **Cherry Studio** —— 多渠道 LLM 管理的启发者

同时感谢所有为开源生态持续贡献的项目与开发者。
