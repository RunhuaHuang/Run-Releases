<div align="center">

# Run

**一个基于 Claude Agent SDK 构建的通用 AI Agent 桌面应用**

本仓库托管 Run 的公开发行版与一键安装入口。产品源码在独立的私有仓库中维护。

[最新版本](https://github.com/RunhuaHuang/Run-Releases/releases/latest) · [全部版本](https://github.com/RunhuaHuang/Run-Releases/releases)

</div>

---

## 一键安装

> 根据你的网络环境，**直接选对应的那条命令**——脚本不再自动探测 GitHub 连通性（实测国内不挂代理有时也能连上但速度极慢，会骗过探测），你用哪条命令，就走哪条下载通道。

### macOS（Apple Silicon）

**有 VPN / 能直连 GitHub**（满速直连）：

```bash
curl -fsSL https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.sh | bash
```

**无 VPN**（走 `ghproxy.net` 代理）：

```bash
curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.sh | RUN_GH_PROXY=https://ghproxy.net bash
```

### Windows x64（管理员 PowerShell）

**有 VPN / 能直连 GitHub**（满速直连）：

```powershell
irm https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex
```

**无 VPN**（走 `ghproxy.net` 代理）：

```powershell
$env:RUN_GH_PROXY='https://ghproxy.net'; irm https://ghproxy.net/https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex
```

> [!NOTE]
> 所有安装包均带 **sha512 完整性校验**。`ghproxy.net` 为第三方公共代理，若偶发不可用，可把命令里的 `ghproxy.net` 临时改成 `gh-proxy.com`（**两处都要换**：脚本前缀和 `RUN_GH_PROXY`）。

---

## 安装做了什么

两个脚本都会按顺序完成：**安装 Run 主程序 → 检测并安装 Git → 检测并安装 Node.js → 收尾启动**。所有依赖（Git / Node）都从固定的 `bootstrap` 发行版下载并经 SHA256 校验，无需手动配置环境。

- macOS：自动移除隔离属性（quarantine）并首次启动
- Windows：静默安装全部依赖到默认路径

安装完成后，应用内置自动更新，默认通过 `ghproxy.net` 代理下载新版本；若下载较慢，可在「设置 → 关于」的下载进度处一键切换线路（`ghproxy.net` / `gh-proxy.com` / GitHub 直连）。

---

## 致谢

Run 站在众多优秀开源项目的肩膀上构建，特别感谢：

- **Claude Agent SDK** —— Agent 能力的核心基石
- **Proma**
- **Cherry Studio**

以及其他为开源社区持续贡献的项目与开发者。Run 从这些项目中汲取了大量设计思路与工程经验，在此一并致谢。
