# Run Releases

This repository hosts Run's public release assets and one-line installer entrypoints.

- Latest desktop releases: https://github.com/RunhuaHuang/Run-Releases/releases/latest
- Product source code is maintained separately in the private RunAI repository.

## 安装命令

根据你的网络环境，**直接选对应的那条命令**——脚本不再自动探测 GitHub 连通性（实测国内不挂代理有时也能连上但速度极慢，会骗过探测），你用哪条命令就走哪条下载通道。

### macOS (Apple Silicon)

有 VPN / 能直连 GitHub（满速直连）：

```bash
curl -fsSL https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.sh | bash
```

无 VPN（走 `ghproxy.net` 代理）：

```bash
curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.sh | RUN_GH_PROXY=https://ghproxy.net bash
```

### Windows x64（管理员 PowerShell）

有 VPN / 能直连 GitHub（满速直连）：

```powershell
irm https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex
```

无 VPN（走 `ghproxy.net` 代理）：

```powershell
$env:RUN_GH_PROXY='https://ghproxy.net'; irm https://ghproxy.net/https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex
```

> 安装包均带 sha512 完整性校验。`ghproxy.net` 为第三方公共代理，若偶发不可用，可把命令里的 `ghproxy.net`（两处都要换：脚本前缀和 `RUN_GH_PROXY`）临时改成 `gh-proxy.com`。
