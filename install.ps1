# 用法: irm https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex
# 稳定安装入口配置（仅安装协议变化时才需要更新）
$ErrorActionPreference = 'Stop'

$RepoOwner = 'RunhuaHuang'
$RepoName = 'Run-Releases'
$ReleasesBase = "https://github.com/$RepoOwner/$RepoName/releases"
$BootstrapTag = 'bootstrap'
$WindowsFallbackUrl = 'https://ug.link/piercehome/filemgr/share-download/?id=207b7aee11f6446b85fb5f431cb745a6'
$GitInstallerName = 'Git-2.54.0-64-bit.exe'
$GitInstallerUrl = "$ReleasesBase/download/$BootstrapTag/$GitInstallerName"
$GitInstallerSha256 = '2b96e7854f0520f0f6b709c21041d9801b1be44d5e1a0d9fa621b2fbc40f1983'
$NodeInstallerName = 'node-v24.15.0-x64.msi'
$NodeInstallerUrl = "$ReleasesBase/download/$BootstrapTag/$NodeInstallerName"
$NodeInstallerSha256 = 'feffb8e5cb5ac47f793666636d496ef3e975be82c84c4da5d20e6aa8fa4eb806'
$AppName = 'Run'

# GitHub 代理前缀（无代理用户回退用）。GitHub 直连不通时，按顺序探测，
# 取第一个可用的，之后所有 github.com 下载都套上该前缀。
# 第三方公共代理，仅作兜底，失效时更新此列表即可。
$GhProxies = @(
  'https://ghproxy.com',
  'https://ghfast.top',
  'https://gh-proxy.com',
  'https://gh.ddlc.top'
)
# 运行时确定：空=直连；非空=代理前缀（形如 https://ghfast.top）
$script:GhProxy = ''

$script:Step = 0
$script:Total = 6
$script:RunAlreadyRunning = $false
$script:InstalledGitThisRun = $false
$script:InstalledNodeThisRun = $false
$script:RestartedRunThisRun = $false

function Write-Banner {
  Write-Host ''
  Write-Host '    ██████╗ ██╗   ██╗███╗   ██╗' -ForegroundColor Cyan
  Write-Host '    ██╔══██╗██║   ██║████╗  ██║' -ForegroundColor Cyan
  Write-Host '    ██████╔╝██║   ██║██╔██╗ ██║' -ForegroundColor Cyan
  Write-Host '    ██╔══██╗██║   ██║██║╚██╗██║' -ForegroundColor Cyan
  Write-Host '    ██║  ██║╚██████╔╝██║ ╚████║' -ForegroundColor Cyan
  Write-Host '    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝' -ForegroundColor Cyan
  Write-Host '    智能 AI 桌面助理  ·  Windows 安装向导' -ForegroundColor DarkGray
  Write-Host '  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
  Write-Host '    ⚠  本次安装设计为全自动进行；受限于 Windows 系统与安装器行为差异，' -ForegroundColor Yellow
  Write-Host '    ⚠  如下载或安装完成后终端未自动继续，请尝试手动按两次 Enter 继续。' -ForegroundColor Yellow
  Write-Host '    ⚠  Run 安装向导请使用默认路径，不要修改！不要修改！' -ForegroundColor Yellow
}

function Write-Step($Message) {
  $script:Step++
  Write-Host ''
  Write-Host ("  [{0}/{1}] {2}" -f $script:Step, $script:Total, $Message) -ForegroundColor Cyan
}

function Write-Ok($Message) {
  Write-Host ("    ✓  {0}" -f $Message) -ForegroundColor Green
}

function Write-Info($Message) {
  Write-Host ("    →  {0}" -f $Message) -ForegroundColor Blue
}

function Write-Warn($Message) {
  Write-Host ("    ⚠  {0}" -f $Message) -ForegroundColor Yellow
}

function Write-Dim($Message) {
  Write-Host $Message -ForegroundColor DarkGray
}

function Pause-IfInteractive($Prompt = '按 Enter 结束...') {
  try {
    if ($Host.Name -match 'ConsoleHost|Visual Studio Code Host|Windows PowerShell ISE Host') {
      Read-Host $Prompt | Out-Null
    }
  } catch {
    # ignore pause failures in non-interactive hosts
  }
}

function Prompt-KeepDownloads {
  Write-Host ''
  Write-Dim '    直接按 Enter：自动删除本次下载的安装包（推荐）'
  Write-Dim '    输入 K 后回车：保留安装包，便于排障或手动重装'
  try {
    $answer = Read-Host '    是否保留本次下载的安装包？[Enter=自动删除 / K=保留]'
    return $answer -match '^[Kk]$'
  } catch {
    return $false
  }
}

function Format-Bytes([long]$Bytes) {
  if ($Bytes -lt 1KB) { return "${Bytes} B" }
  if ($Bytes -lt 1MB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
  if ($Bytes -lt 1GB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
  return ('{0:N2} GB' -f ($Bytes / 1GB))
}

function Test-Admin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-AdminGuidance {
  Write-Host ''
  Write-Host '  ✗  当前 PowerShell 不是以管理员身份运行。' -ForegroundColor Red
  Write-Host ''
  Write-Host '  请按下面步骤重新运行：' -ForegroundColor Yellow
  Write-Dim  '    1. 关闭当前窗口'
  Write-Dim  '    2. 在开始菜单搜索 PowerShell'
  Write-Dim  '    3. 右键 PowerShell，选择“以管理员身份运行”'
  Write-Dim  '    4. 重新执行以下命令：'
  Write-Host ''
  Write-Host '       irm https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex' -ForegroundColor Gray
  Write-Host ''
  Pause-IfInteractive '请在记下命令后按 Enter 退出...'
  exit 1
}

function Get-CommandVersion($Command, $VersionArgs = '--version') {
  if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
    return $null
  }
  try {
    return (& $Command $VersionArgs 2>$null | Select-Object -First 1).ToString().Trim()
  } catch {
    return $Command
  }
}

function Download-File($Url, $Destination, $Label) {
  Write-Info $Label
  Write-Warn '下载完成后通常会自动继续；如果终端没有继续，请按两次 Enter。'

  $request = [System.Net.HttpWebRequest]::Create($Url)
  $request.AllowAutoRedirect = $true
  $request.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
  $request.UserAgent = 'RunInstaller/1.0'

  $response = $null
  $stream = $null
  $fileStream = $null
  try {
    $response = $request.GetResponse()
    $stream = $response.GetResponseStream()
    $fileStream = [System.IO.File]::Open($Destination, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)

    $buffer = New-Object byte[] 1048576
    $totalRead = 0L
    $contentLength = [long]$response.ContentLength
    $lastPercent = -1

    while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
      $fileStream.Write($buffer, 0, $read)
      $totalRead += $read
      if ($contentLength -gt 0) {
        $percent = [int][Math]::Min(100, [Math]::Floor(($totalRead * 100) / $contentLength))
        if ($percent -ne $lastPercent) {
          Write-Progress -Activity $Label -Status (("{0}% ({1}/{2})" -f $percent, (Format-Bytes $totalRead), (Format-Bytes $contentLength))) -PercentComplete $percent
          $lastPercent = $percent
        }
      } else {
        Write-Progress -Activity $Label -Status ("已下载 {0}" -f (Format-Bytes $totalRead)) -PercentComplete 0
      }
    }

    Write-Progress -Activity $Label -Completed
    Write-Ok ("下载完成（{0}）" -f (Format-Bytes $totalRead))
  } finally {
    if ($fileStream) { $fileStream.Dispose() }
    if ($stream) { $stream.Dispose() }
    if ($response) { $response.Dispose() }
  }
}

function Test-GitHubAccess {
  try {
    Invoke-WebRequest -Uri "$ReleasesBase/latest" -Method Head -UseBasicParsing -TimeoutSec 20 | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Show-GitHubFallback {
  Write-Host ''
  Write-Host '  ✗  无法连接 GitHub。' -ForegroundColor Red
  Write-Host '  请先尝试开启代理/VPN 后重新运行此脚本。' -ForegroundColor Yellow
  Write-Host ''
  Write-Dim '  如果当前网络无法访问 GitHub，请改用备用手动安装方式：'
  Write-Dim "    1. 打开：$WindowsFallbackUrl"
  Write-Dim '    2. 下载其中三个安装包：Run、Git、Node.js'
  Write-Dim '    3. 全部安装到默认路径，不要修改安装路径，否则可能无法正常使用'
  Write-Host ''
  Pause-IfInteractive '请在记下地址后按 Enter 退出...'
  exit 1
}

function Assert-Sha256($Path, $Expected) {
  $actual = (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
  if ($actual -ne $Expected.ToLowerInvariant()) {
    throw "文件校验失败：$([IO.Path]::GetFileName($Path))"
  }
}

# 校验文件的 base64 sha512（与 latest.yml 中的格式一致）
function Assert-Sha512Base64($Path, $Expected) {
  $bytes = [System.Security.Cryptography.SHA512]::Create().ComputeHash([System.IO.File]::ReadAllBytes($Path))
  $actual = [System.Convert]::ToBase64String($bytes)
  if ($actual -ne $Expected) {
    throw "文件校验失败：$([IO.Path]::GetFileName($Path))（完整性校验不通过，可能下载被篡改或损坏）"
  }
}

# 按需把 github.com 链接套上代理前缀。$script:GhProxy 为空时原样返回。
function Convert-GhUrl($Url) {
  if ([string]::IsNullOrEmpty($script:GhProxy)) { return $Url }
  return "$script:GhProxy/$Url"
}

# GitHub 直连失败时调用：按顺序探测代理，找到第一个能拉到 latest.yml 的就用它。
function Select-GhProxy {
  $probe = "$ReleasesBase/latest/download/latest.yml"
  foreach ($proxy in $GhProxies) {
    try {
      Invoke-WebRequest -Uri "$proxy/$probe" -Method Head -UseBasicParsing -TimeoutSec 15 | Out-Null
      $script:GhProxy = $proxy
      return $true
    } catch {
      continue
    }
  }
  return $false
}

# 从 latest.yml 读取最新 Windows 安装包信息（版本 / 文件名 / sha512），直连+代理通用。
function Get-LatestYmlInfo {
  $url = Convert-GhUrl "$ReleasesBase/latest/download/latest.yml"
  $content = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20).Content
  # Windows PowerShell 5.1 下，GitHub 以 application/octet-stream 返回 latest.yml，
  # Invoke-WebRequest 的 .Content 会是 byte[]（而非字符串），需手动按 UTF-8 解码，
  # 否则按行 split/正则匹配会全部失败，导致“无法解析”。
  if ($content -is [byte[]]) {
    $content = [System.Text.Encoding]::UTF8.GetString($content)
  }
  $version = $null
  $name = $null
  $sha512 = $null
  foreach ($line in ($content -split "`n")) {
    $line = $line.TrimEnd("`r")
    if ($line -match '^version:\s*(.+)$') { $version = $Matches[1].Trim() }
    elseif ($line -match '^path:\s*(.+)$') { $name = $Matches[1].Trim() }
    elseif (-not $sha512 -and $line -match '^\s*sha512:\s*(.+)$') { $sha512 = $Matches[1].Trim() }
  }
  if (-not $version -or -not $name) {
    throw '无法从 latest.yml 解析最新 Windows 安装包信息。'
  }
  return [PSCustomObject]@{
    Version = "v$version"
    Name = $name
    Url = "$ReleasesBase/download/v$version/$name"
    Sha512 = $sha512
  }
}

function Refresh-Path {
  $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
}

function Wait-InstallerProcess($Process, $Label = '等待安装器完成') {
  if (-not $Process) { return }
  while ($true) {
    try {
      $Process.Refresh()
      if ($Process.HasExited) { break }
    } catch {
      break
    }
    Start-Sleep -Milliseconds 500
  }
  Write-Host ''
}

function Start-RunInstallerWithRetry($InstallerPath) {
  for ($attempt = 1; $attempt -le 2; $attempt++) {
    if ($attempt -eq 1) {
      Write-Info '正在启动 Run 安装向导...'
    } else {
      Write-Warn 'Run 安装向导上次未能正常启动，正在自动重试一次...'
      Start-Sleep -Seconds 2
    }

    try {
      $process = Start-Process -FilePath $InstallerPath -PassThru
      Wait-InstallerProcess $process '等待 Run 安装向导完成'

      if ($process.ExitCode -eq 0) {
        return $process
      }

      Write-Warn "Run 安装向导异常退出，退出码：$($process.ExitCode)"
    } catch {
      Write-Warn ("Run 安装向导启动失败：{0}" -f $_.Exception.Message)
    }
  }

  throw 'Run 安装向导连续两次未能正常完成。请重新运行本安装命令重试。'
}

function Install-GitIfNeeded($TempDir) {
  $gitVersion = Get-CommandVersion 'git'
  if ($gitVersion) {
    Write-Ok "Git 已安装：$gitVersion"
    return
  }

  $installer = Join-Path $TempDir $GitInstallerName
  Download-File (Convert-GhUrl $GitInstallerUrl) $installer '正在下载 Git 安装包...'
  Assert-Sha256 $installer $GitInstallerSha256
  Write-Ok 'Git 安装包校验通过'

  Write-Info '正在静默安装 Git...'
  $process = Start-Process -FilePath $installer -ArgumentList '/VERYSILENT', '/NORESTART' -Wait -PassThru
  if ($process.ExitCode -ne 0) {
    throw "Git 安装失败，退出码：$($process.ExitCode)"
  }

  Refresh-Path
  $gitVersion = Get-CommandVersion 'git'
  if (-not $gitVersion) {
    throw 'Git 安装完成，但当前会话仍未检测到 git。'
  }
  $script:InstalledGitThisRun = $true
  Write-Ok "Git 安装成功：$gitVersion"
}

function Install-NodeIfNeeded($TempDir) {
  $nodeVersion = Get-CommandVersion 'node'
  if ($nodeVersion) {
    Write-Ok "Node.js 已安装：$nodeVersion"
    return
  }

  $installer = Join-Path $TempDir $NodeInstallerName
  Download-File (Convert-GhUrl $NodeInstallerUrl) $installer '正在下载 Node.js 安装包...'
  Assert-Sha256 $installer $NodeInstallerSha256
  Write-Ok 'Node.js 安装包校验通过'

  Write-Info '正在静默安装 Node.js...'
  $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i', $installer, '/qn', '/norestart' -Wait -PassThru
  if ($process.ExitCode -ne 0) {
    throw "Node.js 安装失败，退出码：$($process.ExitCode)"
  }

  Refresh-Path
  $nodeVersion = Get-CommandVersion 'node'
  if (-not $nodeVersion) {
    throw 'Node.js 安装完成，但当前会话仍未检测到 node。'
  }
  $script:InstalledNodeThisRun = $true
  Write-Ok "Node.js 安装成功：$nodeVersion"
}

function Get-RunProcesses {
  return @(Get-Process -Name 'Run' -ErrorAction SilentlyContinue)
}

function Restart-RunIfNeeded($RunExe) {
  if (-not $RunExe) { return $false }
  if (-not ($script:InstalledGitThisRun -or $script:InstalledNodeThisRun)) { return $false }

  $running = Get-RunProcesses
  if ($running.Count -gt 0) {
    Write-Info '检测到本轮补齐了 Git/Node.js，正在重启 Run 以加载最新运行时...'
    foreach ($proc in $running) {
      try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch {}
    }
    Start-Sleep -Seconds 2
  }

  Start-Process -FilePath $RunExe | Out-Null
  $script:RestartedRunThisRun = $true
  Write-Ok '已重启 Run'
  return $true
}

function Find-RunExecutable {
  $programFilesX86 = [System.Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Run\Run.exe'),
    (Join-Path $env:ProgramFiles 'Run\Run.exe'),
    $(if ($programFilesX86) { Join-Path $programFilesX86 'Run\Run.exe' })
  ) | Where-Object { $_ }

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  $uninstallRoots = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )

  foreach ($root in $uninstallRoots) {
    $match = Get-ItemProperty $root -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -eq 'Run' -and $_.InstallLocation } |
      Select-Object -First 1
    if ($match) {
      $candidate = Join-Path $match.InstallLocation 'Run.exe'
      if (Test-Path $candidate) {
        return $candidate
      }
    }
  }

  return $null
}

function Install-Run($TempDir) {
  Write-Info '正在查询最新 Run 版本...'
  $latest = Get-LatestYmlInfo
  if (-not ($latest.Version -match '^v\d+\.\d+\.\d+$')) {
    throw "当前没有可安装的 Run 正式版本（解析到的 release: $($latest.Version)）。请等待 Run-Releases 发布 vX.Y.Z 正式版本后重试。"
  }
  Write-Ok "最新版本：$($latest.Version)"
  Write-Ok "安装包：$($latest.Name)"

  $installerPath = Join-Path $TempDir $latest.Name
  Download-File (Convert-GhUrl $latest.Url) $installerPath '正在下载 Run Windows 安装包...'

  # 完整性校验：与 latest.yml 中的 sha512 比对（尤其是走代理时防篡改）
  if ($latest.Sha512) {
    Assert-Sha512Base64 $installerPath $latest.Sha512
    Write-Ok '安装包完整性校验通过'
  } else {
    Write-Warn '未能取得安装包校验值，跳过完整性校验'
  }

  Write-Info '准备启动 Run 安装程序...'
  switch -Regex ($latest.Name) {
    '\.msi$' {
      Write-Warn '即将打开 Windows Installer 安装界面，请在弹出的向导中完成安装。'
      $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i', $installerPath, '/passive', '/norestart' -PassThru
      Wait-InstallerProcess $process '等待 Windows Installer 完成'
    }
    default {
      Write-Warn '即将打开 Run 安装向导，请按向导完成安装。'
      Write-Warn '请务必安装到默认路径，不要修改！不要修改！'
      Write-Warn '关闭安装窗口后通常会自动继续；如果终端没有继续，请按两次 Enter。'
      $process = Start-RunInstallerWithRetry $installerPath
    }
  }

  if ($process.ExitCode -ne 0) {
    throw "Run 安装失败，退出码：$($process.ExitCode)。请重新运行本安装命令重试。"
  }

  $runExe = Find-RunExecutable
  if (-not $runExe) {
    throw '安装程序已退出，但未检测到 Run.exe。请确认是否在安装向导中取消了安装，或安装到了非默认路径。'
  }

  Start-Sleep -Seconds 2
  $runningAfterInstall = Get-RunProcesses
  if ($runningAfterInstall.Count -gt 0) {
    $script:RunAlreadyRunning = $true
    Write-Ok 'Run 安装完成（安装器已自动启动应用）'
  } else {
    $script:RunAlreadyRunning = $false
    Write-Ok 'Run 安装完成'
  }
  Write-Ok "安装位置：$runExe"
}

try {
  Write-Banner

  if (-not (Test-Admin)) {
    Show-AdminGuidance
  }

  Write-Step '检测系统环境'
  if (-not [Environment]::Is64BitOperatingSystem) {
    throw '仅支持 Windows x64。'
  }
  Write-Ok '已检测到 Windows x64'

  Write-Step '检测 GitHub 连通性'
  if (Test-GitHubAccess) {
    Write-Ok 'GitHub 连通性正常（直连下载）'
  } else {
    Write-Warn 'GitHub 直连失败，正在尝试国内代理通道...'
    if (Select-GhProxy) {
      Write-Ok "已启用代理通道：$script:GhProxy"
      Write-Warn '代理为第三方公共服务，速度可能较慢，请耐心等待。'
    } else {
      Show-GitHubFallback
    }
  }

  $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('run-bootstrap-' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tempDir | Out-Null

  Write-Step '下载并安装 Run'
  Install-Run $tempDir

  Write-Step '检查 Git'
  Install-GitIfNeeded $tempDir

  Write-Step '检查 Node.js'
  Install-NodeIfNeeded $tempDir

  Write-Step '完成'
  if (-not (Get-CommandVersion 'git')) {
    throw 'Git 尚未就绪，Run 还不能正常使用。'
  }
  if (-not (Get-CommandVersion 'node')) {
    throw 'Node.js 尚未就绪，Run 还不能正常使用。'
  }

  $keepDownloads = Prompt-KeepDownloads
  if ($keepDownloads) {
    Write-Ok "已保留下载文件：$tempDir"
  } else {
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    Write-Ok '安装包已自动删除'
  }

  $runExe = Find-RunExecutable
  if (Restart-RunIfNeeded $runExe) {
    # already restarted above
  } else {
    $runningRun = Get-RunProcesses
    if ($runningRun.Count -gt 0) {
      if ($script:RunAlreadyRunning) {
        Write-Ok '检测到安装器已自动启动 Run，脚本将跳过重复启动。'
      } else {
        Write-Ok '检测到 Run 已在运行，脚本将跳过重复启动。'
      }
    } elseif ($runExe) {
      Write-Info '正在启动 Run...'
      Start-Process -FilePath $runExe | Out-Null
      Write-Ok "已启动 $runExe"
    } else {
      Write-Warn '未定位到 Run.exe，请从开始菜单手动启动 Run。'
    }
  }

  Write-Host ''
  Write-Host '  ✓  现在可以关闭这个 PowerShell 窗口。' -ForegroundColor Green
  if ($script:RestartedRunThisRun) {
    Write-Host '  ✓  本轮已补装依赖，Run 已自动重启，可以正常使用。' -ForegroundColor Green
  } elseif ($script:InstalledGitThisRun -or $script:InstalledNodeThisRun) {
    Write-Host '  ✓  依赖已补齐，可以正常使用 Run。' -ForegroundColor Green
  } else {
    Write-Host '  ✓  依赖已齐全，无需重启 Run，可以正常使用。' -ForegroundColor Green
  }
  Write-Host ''
} catch {
  Write-Host ''
  Write-Host ("  ✗  安装失败：{0}" -f $_.Exception.Message) -ForegroundColor Red
  Write-Host ''
  Write-Warn '如果这是下载超时、安装器未弹出、安装器异常退出或终端未继续，请重新运行下面的命令重试：'
  Write-Host '     irm https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex' -ForegroundColor Gray
  Write-Host ''
  Pause-IfInteractive '按 Enter 退出...'
  exit 1
}
