# 用法（管理员 PowerShell）：
#   有 VPN（直连）:
#     irm https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex
#   无 VPN（走 gh-proxy.com 代理）:
#     $env:RUN_GH_PROXY='https://gh-proxy.com'; irm https://gh-proxy.com/https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex
# 稳定安装入口配置（仅安装协议变化时才需要更新）
$ErrorActionPreference = 'Stop'

# 强制 TLS 1.2：Windows PowerShell 5.1 默认协议栈偏低，而清华 TUNA 镜像 / GitHub
# 均要求 TLS 1.2+，不显式设置会导致 HttpWebRequest 握手失败（下载 Git/Node/Run 全挂）。
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoOwner = 'RunhuaHuang'
$RepoName = 'Run-Releases'
$ReleasesBase = "https://github.com/$RepoOwner/$RepoName/releases"
# raw.githubusercontent.com 上的 VERSION 文件：版本号发现的通用通道。
# 三家代理（gh-proxy.com / ghfast.top / ghproxy.net）都能代理 raw 与「带版本号的」
# 资产下载，但只有前两家能代理 /releases/latest/download 的重定向链（ghproxy.net 会 502），
# 所以版本发现一律走 raw VERSION，yml/资产一律走 /releases/download/vX.Y.Z/ 带版本号路径。
$RawBase = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/main"
$BootstrapTag = 'bootstrap'
$WindowsFallbackUrl = 'https://ug.link/piercehome/filemgr/share-download/?id=207b7aee11f6446b85fb5f431cb745a6'
# Git 安装包：走清华 TUNA 镜像（镜像 Git for Windows 官方 GitHub Releases），
# 国内直连极速，不再依赖 Run-Releases（GitHub）与 gh-proxy 代理，避免国内下载慢/超时。
$GitInstallerName = 'Git-2.54.0-64-bit.exe'
$GitInstallerUrl = 'https://mirrors.tuna.tsinghua.edu.cn/github-release/git-for-windows/git/Git%20for%20Windows%20v2.54.0.windows.1/Git-2.54.0-64-bit.exe'
$GitInstallerSha256 = '2b96e7854f0520f0f6b709c21041d9801b1be44d5e1a0d9fa621b2fbc40f1983'
# Node.js 安装包：走清华 TUNA 镜像（镜像 nodejs.org 官方分发），国内直连极速，
# 不再依赖 nodejs.org 直连与 gh-proxy 代理。版本与 Git 来源保持「国内可直达」原则统一。
$NodeInstallerName = 'node-v24.1.0-x64.msi'
$NodeInstallerUrl = 'https://mirrors.tuna.tsinghua.edu.cn/nodejs-release/v24.1.0/node-v24.1.0-x64.msi'
$NodeInstallerSha256 = '082fb5a7fbd4eff935aa39d9d3ba4973e5fe0ceb30f500f0d49a7151b7d3dd28'
$AppName = 'Run'

# GitHub 代理前缀：由用户选择的安装命令决定，脚本内部不再做连通性探测。
# 实测国内不挂代理有时也能连上 GitHub（能过连通性测试）但速度极慢，探测会被
# 这种「能连但龟速」骗过，所以改为「用哪条命令走哪条路」：
#   - 直连命令：不设 $env:RUN_GH_PROXY              → 全程直连 GitHub（适合有 VPN/能直连的用户）
#   - 代理命令：$env:RUN_GH_PROXY='https://gh-proxy.com' → 所有 github.com 下载都套此前缀（适合无 VPN 用户）
$script:GhProxy = if ($env:RUN_GH_PROXY) { $env:RUN_GH_PROXY } else { '' }

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
  Write-Host '    智能 AI 桌面助理  ·  Windows 全自动安装' -ForegroundColor DarkGray
  Write-Host '  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
  Write-Host '    本次安装为全自动进行：Run / Git / Node 将静默安装到默认位置。' -ForegroundColor Yellow
  Write-Host '    全程无需操作，请保持网络畅通，耐心等待完成。' -ForegroundColor Yellow
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

# 错误路径专用阻塞：无论何种宿主都先尝试 Read-Host 等待用户确认；stdin 被重定向
# （非交互式）读不到时退化为短时挂起，保证错误信息不会被一闪而过的关闭动作吞掉。
function Wait-Visible($Prompt = '按 Enter 关闭...') {
  try {
    Read-Host $Prompt | Out-Null
  } catch {
    Start-Sleep -Seconds 5
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

# ── Spinner（转圈动画）─────────────────────────────────────────
# 对标 install.sh 的 _spinner_start/_spinner_stop：包裹那些只有「开始/结束」、
# 中间没有进度百分比的耗时操作（静默安装、SHA 校验、版本查询等），用转圈动画告诉
# 用户「正在工作，没有卡死」。PowerShell 的 Start-Process -Wait 会阻塞主线程，
# 所以动画必须跑在独立的 Timer 回调里（Timer 在后台线程池触发，不被主线程阻塞）。
$script:SpinnerState = $null
function Start-Spinner($Message) {
  Stop-Spinner
  $script:SpinnerState = [PSCustomObject]@{
    Message = $Message
    Frames  = [char[]]@([char]0x280B,[char]0x2819,[char]0x2839,[char]0x2838,[char]0x283C,[char]0x2834,[char]0x2826,[char]0x2827,[char]0x2807,[char]0x280F)
    Index   = 0
    Timer   = $null
  }
  $state = $script:SpinnerState
  # System.Threading.Timer 在后台线程触发回调，主线程即便被 Start-Process -Wait
  # 阻塞，回调仍会按周期刷新动画帧，实现「后台转圈」效果。
  $script:SpinnerState.Timer = New-Object System.Threading.Timer(
    [System.Threading.TimerCallback]{
      param($n)
      try {
        $f = $state.Frames[$state.Index % $state.Frames.Length]
        $state.Index++
        # \r 回到行首覆盖上一帧；避免闪烁，不换行。
        [Console]::Write("`r    {0}  {1}   " -f $f, $state.Message)
      } catch {}
    },
    $null, 80, 80)
}
function Stop-Spinner {
  if ($script:SpinnerState -and $script:SpinnerState.Timer) {
    $script:SpinnerState.Timer.Dispose()
  }
  $script:SpinnerState = $null
  # 用空格覆盖整行再回到行首，清除残留的转圈字符。不依赖 ANSI \x1b[K（旧版
  # Windows conhost / PS 5.1 不识别 ANSI 转义会输出乱码），空格覆盖任何终端都有效。
  [Console]::Write((' ' * 60) + "`r")
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
  Pause-IfInteractive '请在记下命令后按 Enter 继续...'
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

  # 下载重试：国内访问 GitHub / 清华镜像偶发连接重置或超时，单次失败直接进外层
  # catch 会触发 exit 关窗（见文件末尾注释），所以这里先内联重试 3 次，每次重试
  # 前清掉半截文件。重试全失败才抛出，让外层 catch 显示明确错误。
  $maxAttempts = 3
  $lastError = $null
  for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    if ($attempt -gt 1) {
      $backoff = $attempt * 3
      Write-Warn "下载失败，第 $attempt/$maxAttempts 次重试（${backoff}s 后开始）..."
      Start-Sleep -Seconds $backoff
      Remove-Item -Force $Destination -ErrorAction SilentlyContinue
    }

    try {
      $request = [System.Net.HttpWebRequest]::Create($Url)
      $request.AllowAutoRedirect = $true
      $request.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
      $request.UserAgent = 'RunInstaller/1.0'
      # 显式超时：建立连接 30s、整体请求 600s。不设置时 HttpWebRequest 默认 100s，
      # 但断连的 socket 可能长时间不抛错导致 stream.Read 长期卡死，显式超时避免卡死。
      $request.Timeout = 30000
      $request.ReadWriteTimeout = 600000

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

        # 校验：ContentLength 已知时，实际下载数必须与之相符，否则视为不完整（连接
        # 提前断开但 Read 未抛错的边缘情况），避免把残缺文件当成功。
        if ($contentLength -gt 0 -and $totalRead -ne $contentLength) {
          throw "下载不完整：期望 $contentLength 字节，实际 $totalRead 字节"
        }

        Write-Progress -Activity $Label -Completed
        Write-Ok ("下载完成（{0}）" -f (Format-Bytes $totalRead))
        return
      } finally {
        # 资源释放逐个 try/catch 保护：finally 里抛出的异常会掩盖 try 里的原始异常，
        # 导致 $lastError 记录的是"对象已释放"之类的清理错误而非真正的下载失败原因，
        # 用户看到的报错毫无意义。这里吞掉释放异常，保留外层 catch 捕获的原始错误。
        foreach ($d in @($fileStream, $stream, $response)) {
          if ($d) { try { $d.Dispose() } catch {} }
        }
      }
    } catch {
      $lastError = $_
      # 进度条残留清理，避免下一次重试时叠画。
      Write-Progress -Activity $Label -Completed
    }
  }
  throw "下载失败（已重试 $maxAttempts 次）：$($lastError.Exception.Message)"
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

# 取回 yml 文本（处理 PowerShell 5.1 把 application/octet-stream 当 byte[] 返回的情况）。
function Get-YmlText($Url) {
  $content = (Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 20).Content
  # Windows PowerShell 5.1 下，GitHub 以 application/octet-stream 返回 yml，
  # Invoke-WebRequest 的 .Content 会是 byte[]（而非字符串），需手动按 UTF-8 解码，
  # 否则按行 split/正则匹配会全部失败，导致“无法解析”。
  if ($content -is [byte[]]) {
    $content = [System.Text.Encoding]::UTF8.GetString($content)
  }
  return $content
}

# 解析最新版本号：优先 raw 上的 VERSION 文件（三家代理通用），失败回退 latest.yml 的 version 字段。
# 返回形如 v0.10.18。
function Get-LatestVersion {
  try {
    $raw = Get-YmlText (Convert-GhUrl "$RawBase/VERSION")
    $ver = ($raw -split "`n")[0].Trim().TrimEnd("`r")
    if ($ver -match '^[0-9]+\.[0-9]+\.[0-9]+$') { return "v$ver" }
  } catch { }
  # 回退：从 /releases/latest/download/latest.yml 读取 version
  $content = Get-YmlText (Convert-GhUrl "$ReleasesBase/latest/download/latest.yml")
  foreach ($line in ($content -split "`n")) {
    if ($line -match '^version:\s*(.+)$') { return "v$($Matches[1].Trim())" }
  }
  throw '无法解析最新版本号。'
}

# 从指定版本的 latest.yml 读取 Windows 安装包信息（文件名 / sha512），
# 用带版本号的路径（/releases/download/vX.Y.Z/latest.yml），三家代理通用。
function Get-LatestYmlInfo {
  $version = Get-LatestVersion
  $url = Convert-GhUrl "$ReleasesBase/download/$version/latest.yml"
  $content = Get-YmlText $url
  $name = $null
  $sha512 = $null
  foreach ($line in ($content -split "`n")) {
    $line = $line.TrimEnd("`r")
    if ($line -match '^path:\s*(.+)$') { $name = $Matches[1].Trim() }
    elseif (-not $sha512 -and $line -match '^\s*sha512:\s*(.+)$') { $sha512 = $Matches[1].Trim() }
  }
  if (-not $name) {
    throw '无法从 latest.yml 解析最新 Windows 安装包信息。'
  }
  return [PSCustomObject]@{
    Version = $version
    Name = $name
    Url = "$ReleasesBase/download/$version/$name"
    Sha512 = $sha512
  }
}

function Refresh-Path {
  $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
}



function Install-GitIfNeeded($TempDir) {
  $gitVersion = Get-CommandVersion 'git'
  if ($gitVersion) {
    Write-Ok "Git 已安装：$gitVersion"
    return
  }

  $installer = Join-Path $TempDir $GitInstallerName
  Download-File $GitInstallerUrl $installer '正在下载 Git 安装包...'
  Start-Spinner '正在校验 Git 安装包完整性...'
  Assert-Sha256 $installer $GitInstallerSha256
  Stop-Spinner
  Write-Ok 'Git 安装包校验通过'

  Start-Spinner '正在静默安装 Git（无需操作，请耐心等待，最长约三分钟）...'
  $process = Start-Process -FilePath $installer -ArgumentList '/VERYSILENT', '/NORESTART' -Wait -PassThru
  Stop-Spinner
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
  Download-File $NodeInstallerUrl $installer '正在下载 Node.js 安装包...'
  Start-Spinner '正在校验 Node.js 安装包完整性...'
  Assert-Sha256 $installer $NodeInstallerSha256
  Stop-Spinner
  Write-Ok 'Node.js 安装包校验通过'

  Start-Spinner '正在静默安装 Node.js（无需操作，请耐心等待，最长约三分钟）...'
  $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i', $installer, '/qn', '/norestart' -Wait -PassThru
  Stop-Spinner
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
  Start-Spinner '正在查询最新 Run 版本...'
  $latest = Get-LatestYmlInfo
  Stop-Spinner
  if (-not ($latest.Version -match '^v\d+\.\d+\.\d+$')) {
    throw "当前没有可安装的 Run 正式版本（解析到的 release: $($latest.Version)）。请等待 Run-Releases 发布 vX.Y.Z 正式版本后重试。"
  }
  Write-Ok "最新版本：$($latest.Version)"
  Write-Ok "安装包：$($latest.Name)"

  $installerPath = Join-Path $TempDir $latest.Name
  Download-File (Convert-GhUrl $latest.Url) $installerPath '正在下载 Run Windows 安装包...'

  # 完整性校验：与 latest.yml 中的 sha512 比对（尤其是走代理时防篡改）
  if ($latest.Sha512) {
    Start-Spinner '正在校验 Run 安装包完整性...'
    Assert-Sha512Base64 $installerPath $latest.Sha512
    Stop-Spinner
    Write-Ok '安装包完整性校验通过'
  } else {
    Write-Warn '未能取得安装包校验值，跳过完整性校验'
  }

  Start-Spinner '正在静默安装 Run（无需操作，请耐心等待，最长约三分钟）...'
  switch -Regex ($latest.Name) {
    '\.msi$' {
      # msi 静默安装：/qn 无界面，装到默认路径
      $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i', $installerPath, '/qn', '/norestart' -Wait -PassThru
    }
    default {
      # NSIS 静默安装：/S 无向导界面，装到默认路径（%LOCALAPPDATA%\Programs\Run）
      $process = Start-Process -FilePath $installerPath -ArgumentList '/S' -Wait -PassThru
    }
  }
  Stop-Spinner

  if ($process.ExitCode -ne 0) {
    throw "Run 安装失败，退出码：$($process.ExitCode)。请重新运行本安装命令重试。"
  }

  $runExe = Find-RunExecutable
  if (-not $runExe) {
    throw '安装程序已退出，但未检测到 Run.exe。请重新运行本安装命令重试。'
  }

  # 静默安装(/S)默认不自动启动应用；检测是否已有实例在运行（比如用户之前开着）。
  Start-Sleep -Seconds 2
  if ((Get-RunProcesses).Count -gt 0) {
    $script:RunAlreadyRunning = $true
    Write-Ok 'Run 安装完成（检测到已有实例在运行）'
  } else {
    Write-Ok 'Run 安装完成'
  }
  Write-Ok "安装位置：$runExe"
}

try {
  Write-Banner

  if (-not (Test-Admin)) {
    Show-AdminGuidance
    # 非管理员：Show-AdminGuidance 已显示引导并等待用户确认，脚本级 return 终止
    # 主流程（只结束本次 iex 执行，不关窗口）。
    return
  }

  Write-Step '检测系统环境'
  if (-not [Environment]::Is64BitOperatingSystem) {
    throw '仅支持 Windows x64。'
  }
  Write-Ok '已检测到 Windows x64'

  # 下载通道由用户选择的命令决定（见文件头注释），不再做连通性探测。
  Write-Step '确认下载通道'
  if ([string]::IsNullOrEmpty($script:GhProxy)) {
    Write-Ok '下载通道：GitHub 直连'
  } else {
    Write-Ok "下载通道：代理（$script:GhProxy）"
    Write-Warn '代理为第三方公共服务，速度可能较慢，请耐心等待。'
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
  Stop-Spinner
  Write-Host ''
  Write-Host ("  ✗  安装失败：{0}" -f $_.Exception.Message) -ForegroundColor Red
  Write-Host ''
  Write-Warn '如果这是下载超时或安装失败，请重新运行下面的命令重试：'
  Write-Host '     irm https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex' -ForegroundColor Gray
  if ([string]::IsNullOrEmpty($script:GhProxy)) {
    Write-Host ''
    Write-Warn '若你在国内且没有 VPN，直连 GitHub 很可能超时或极慢，请改用「无 VPN」代理命令：'
    Write-Host "     `$env:RUN_GH_PROXY='https://gh-proxy.com'; irm https://gh-proxy.com/https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.ps1 | iex" -ForegroundColor Gray
  }
  Write-Host ''
  Write-Dim "  仍不行可用手动备用方式：$WindowsFallbackUrl （下载并安装 Run、Git、Node.js，全部用默认路径）"
  Write-Host ''
  # return 而非 exit：避免 `irm | iex` 模式下 exit 关闭整个终端窗口，
  # 用户看不到上面的错误信息。Wait-Visible 无条件等待用户确认后再回到提示符。
  Wait-Visible '按 Enter 回到 PowerShell 提示符...'
  return
}
