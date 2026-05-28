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

$script:Step = 0
$script:Total = 6
$script:RunAlreadyRunning = $false

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
  Write-Ok "Node.js 安装成功：$nodeVersion"
}

function Get-LatestWindowsAsset {
  Write-Info '正在查询最新 Run 版本...'
  $latestResponse = Invoke-WebRequest -Uri "$ReleasesBase/latest" -MaximumRedirection 10 -UseBasicParsing
  $latestTag = Split-Path $latestResponse.BaseResponse.ResponseUri.AbsolutePath -Leaf
  if (-not ($latestTag -match '^v\d+\.\d+\.\d+$')) {
    throw "当前没有可安装的 Run 正式版本（解析到的 release: $latestTag）。请等待 Run-Releases 发布 vX.Y.Z 正式版本后重试。"
  }
  $version = $latestTag.Substring(1)
  $candidates = @(
    "Run-Setup-$version.exe",
    "Run-$version-x64.exe",
    "Run-$version-x64.msi"
  )
  foreach ($name in $candidates) {
    $url = "$ReleasesBase/download/$latestTag/$name"
    try {
      Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 20 | Out-Null
      return [PSCustomObject]@{
        Version = $latestTag
        Name = $name
        Url = $url
      }
    } catch {
      continue
    }
  }
  throw '未找到 Windows x64 安装包。'
}

function Get-RunProcesses {
  return @(Get-Process -Name 'Run' -ErrorAction SilentlyContinue)
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
  $latest = Get-LatestWindowsAsset
  Write-Ok "最新版本：$($latest.Version)"
  Write-Ok "安装包：$($latest.Name)"

  $installerPath = Join-Path $TempDir $latest.Name
  Download-File $latest.Url $installerPath '正在下载 Run Windows 安装包...'

  Write-Info '准备启动 Run 安装程序...'
  switch -Regex ($latest.Name) {
    '\.msi$' {
      Write-Warn '即将打开 Windows Installer 安装界面，请在弹出的向导中完成安装。'
      $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i', $installerPath, '/passive', '/norestart' -Wait -PassThru
    }
    default {
      Write-Warn '即将打开 Run 安装向导，请不要关闭安装窗口，并按向导完成安装。'
      $process = Start-Process -FilePath $installerPath -Wait -PassThru
    }
  }

  if ($process.ExitCode -ne 0) {
    throw "Run 安装失败，退出码：$($process.ExitCode)"
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
    Write-Ok 'GitHub 连通性正常'
  } else {
    Show-GitHubFallback
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

  Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
  Write-Ok '临时文件已清理'

  $runExe = Find-RunExecutable
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

  Write-Host ''
  Write-Host '  ✓  Git 和 Node.js 已就绪，现在可以正常使用 Run。' -ForegroundColor Green
  Write-Host ''
} catch {
  Write-Host ''
  Write-Host ("  ✗  安装失败：{0}" -f $_.Exception.Message) -ForegroundColor Red
  Write-Host ''
  Pause-IfInteractive '按 Enter 退出...'
  exit 1
}
