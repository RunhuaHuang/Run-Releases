# Run Releases

This repository hosts Run's public release assets and one-line installer entrypoints.

- Latest desktop releases: https://github.com/RunhuaHuang/Run-Releases/releases/latest
- Product source code is maintained separately in the private RunAI repository.

## 安装命令

### 能访问 GitHub（已有代理 / VPN）

macOS (Apple Silicon)：

```bash
curl -fsSL https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.sh | bash
```

Windows x64（管理员 PowerShell）：

```powershell
irm https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex
```

### 无法访问 GitHub（中国大陆 / 无代理）

下面命令通过 GitHub 代理拉取脚本；脚本运行后会自动检测连通性，把所有下载也切换到代理通道。

macOS (Apple Silicon)：

```bash
curl -fsSL https://ghproxy.com/https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.sh | bash
```

Windows x64（管理员 PowerShell）：

```powershell
irm https://ghproxy.com/https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex
```

> 代理为第三方公共服务，速度可能较慢且可能失效；若某个代理不可用，可改用 `ghfast.top` / `gh-proxy.com` / `gh.ddlc.top` 等其它前缀。安装包均带 sha512 完整性校验。
