# Run Releases

This repository hosts Run's public release assets and one-line installer entrypoints.

- Latest desktop releases: https://github.com/RunhuaHuang/Run-Releases/releases/latest
- Product source code is maintained separately in the private RunAI repository.

## 安装命令

国内外用户统一用下面这条命令即可。脚本本身通过 `ghproxy.net` 拉取（仅 ~20KB），运行后会**自动检测 GitHub 连通性**：能直连 GitHub 就走 GitHub 满速下载安装包，连不上才把下载切到 `ghproxy.net` 代理通道。因此有代理 / 海外用户也不会损失下载速度。

macOS (Apple Silicon)：

```bash
curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.sh | bash
```

Windows x64（管理员 PowerShell）：

```powershell
irm https://ghproxy.net/https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex
```

> 安装包均带 sha512 完整性校验。`ghproxy.net` 为第三方公共代理，若偶发不可用，可把命令里的前缀临时换成 `https://gh-proxy.com`，或在能访问 GitHub 时直接去掉 `https://ghproxy.net/` 前缀走原始 GitHub 地址。
