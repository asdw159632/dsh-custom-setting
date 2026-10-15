#Requires -Version 5.1
<#
.SYNOPSIS
  校验「PowerShell 里的 dsh 是否已由桌面端接管」。纯只读，不修改任何系统状态。

.DESCRIPTION
  「管理 dsh 命令…」安装完成后运行本脚本，逐项核对官方命令安装器的应有状态：
    [1/7] 桌面端自带 CLI 启动器存在且版本 = 0.2.0-rc.2（与 GUI 宿主一致）
    [2/7] 用户 PATH 注册表值首位 = <DSH>\resources\runtime\cli\bin
    [3/7] 归属键 HKCU\Software\DeepSeekHarness\Command\Directory 指向同一目录
    [4/7] PATH 解析顺序中「先命中的 dsh」就是桌面端启动器（关键项：压过 npm 旧 shim）
    [5/7] 当前会话里 dsh 的实际来源（注意：PATH 变更不回溯已运行进程，本项看的是当前会话环境）
    [6/7] 旧 npm 全局包仍在（属于「保留但被遮蔽」的预期状态）
    [7/7] 无陈旧重复的 PATH 项

  只读保证：仅读取注册表（HKCU/HKLM）、文件系统、PATH 环境变量；不写注册表、不装包、不改 PATH。
  PATH 解析顺序是按「注册表值 + 本进程 PATHEXT」模拟的，等价于新开终端里的解析结果。

.PARAMETER ExpectedVersion
  期望的桌面端版本，缺省 0.2.0-rc.2。留空跳过版本比对。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File mods\dsh-command-desktop\verify.ps1

.NOTES
  本脚本可在 DSH 沙箱内运行（纯读）。但「安装」动作本身不行——见同目录 README.md。
#>
[CmdletBinding()]
param(
  [string]$ExpectedVersion = '0.2.0-rc.2'
)

$ErrorActionPreference = 'Stop'

$script:Fail = 0
$script:Warn = 0

function Ok   { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Bad  { param([string]$m) Write-Host "  [FAIL] $m" -ForegroundColor Red;    $script:Fail++ }
function Warn { param([string]$m) Write-Host "  [WARN] $m" -ForegroundColor Yellow; $script:Warn++ }
function Info { param([string]$m) Write-Host "         $m" }

# ── 定位桌面端安装树：优先从 shim 反推，否则探测已知位置 ──
function Find-DesktopRoot {
  $cands = New-Object System.Collections.Generic.List[string]
  if ($env:DSH_DESKTOP_ROOT) { $cands.Add($env:DSH_DESKTOP_ROOT) }
  $cands.Add('D:\software\DSH')
  $cands.Add((Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness'))
  $cands.Add((Join-Path $env:ProgramFiles 'DeepSeek Harness'))
  $cands.Add((Join-Path ${env:ProgramFiles(x86)} 'DeepSeek Harness'))
  foreach ($c in $cands) {
    if (-not $c) { continue }
    if (Test-Path -LiteralPath (Join-Path $c 'resources\app.asar')) { return (Resolve-Path -LiteralPath $c).Path }
  }
  return $null
}

function Get-UserPathRaw {
  # DoNotExpandEnvironmentNames：要拿到「注册表里原样」的值，才能判断首位与重复项
  $k = Get-Item -LiteralPath 'HKCU:\Environment' -ErrorAction SilentlyContinue
  if (-not $k) { return $null }
  return $k.GetValue('Path', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
}

function Get-MachinePathRaw {
  $k = Get-Item -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -ErrorAction SilentlyContinue
  if (-not $k) { return '' }
  $v = $k.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  if ($v -isnot [string]) { return '' }
  return $v
}

function Normalize([string]$p) {
  if (-not $p) { return '' }
  $e = [Environment]::ExpandEnvironmentVariables($p.Trim().Trim('"'))
  try { return [IO.Path]::GetFullPath($e).TrimEnd('\', '/').ToUpperInvariant() } catch { return $e.ToUpperInvariant() }
}

# 模拟 PowerShell / Windows 的命令解析（已实测确认的语义）：
#   按 PATH 顺序找「第一个含 dsh shim 的目录」，然后在**该目录内**按
#   .ps1 → PATHEXT(.COM/.EXE/.BAT/.CMD/...) 的顺序取命令。
#   实测结论：前面的目录只有 dsh.cmd、后面的目录有 dsh.ps1 时，仍命中前面的 dsh.cmd
#   （目录优先级 > 扩展名优先级），所以桌面端「只有 dsh.cmd」足以接管。
function Resolve-DshInPath {
  param([string]$MachinePath, [string]$UserPath)
  $exts = if ($env:PATHEXT) { @($env:PATHEXT -split ';') } else { @('.COM', '.EXE', '.BAT', '.CMD') }
  foreach ($seg in (($MachinePath + ';' + $UserPath) -split ';')) {
    if (-not $seg.Trim()) { continue }
    $expanded = [Environment]::ExpandEnvironmentVariables($seg.Trim().Trim('"'))
    try { $rooted = [IO.Path]::IsPathRooted($expanded) } catch { continue }
    if (-not $rooted) { continue }
    foreach ($ext in (@('.ps1') + $exts)) {
      $cand = Join-Path $expanded ('dsh' + $ext)
      if (Test-Path -LiteralPath $cand -PathType Leaf) { return $cand }
    }
  }
  return $null
}

$ROOT = Find-DesktopRoot
Write-Host ''
Write-Host '=== dsh 命令接管校验（只读）===' -ForegroundColor Cyan
Write-Host "桌面端安装树: $ROOT"
if (-not $ROOT) {
  Write-Host '  无法定位桌面端安装树；用 $env:DSH_DESKTOP_ROOT 指定。' -ForegroundColor Red
  exit 1
}

$CLI_DIR = Join-Path $ROOT 'resources\runtime\cli\bin'
$CLI_CMD = Join-Path $CLI_DIR 'dsh.cmd'
$NPM_DIR = Join-Path $env:APPDATA 'npm'
$NPM_CMD = Join-Path $NPM_DIR 'dsh.cmd'

# ── [1/7] 启动器与版本 ──
Write-Host ''
Write-Host '[1/7] 桌面端自带 CLI 启动器' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $CLI_CMD -PathType Leaf)) {
  Bad "启动器不存在：$CLI_CMD"
} else {
  Ok "启动器存在：$CLI_CMD"
  $ver = $null
  try { $ver = (& $CLI_CMD --version 2>&1 | Select-Object -First 1) } catch { }
  if (-not $ver) {
    Warn '无法取得启动器版本（--version 无输出）'
  } elseif ($ExpectedVersion -and ($ver.Trim() -ne $ExpectedVersion)) {
    Warn "启动器版本 = $ver（期望 $ExpectedVersion，可能是应用已升级）"
  } else {
    Ok "启动器版本 = $ver"
  }
}

# ── [2/7] 用户 PATH 首位 ──
Write-Host ''
Write-Host '[2/7] 用户 PATH 注册表值首位' -ForegroundColor Cyan
$userPath = Get-UserPathRaw
if ($null -eq $userPath) {
  Bad 'HKCU:\Environment 没有 Path 值'
} else {
  $first = @(($userPath -split ';') | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
  if ($first.Count -eq 0) {
    Bad '用户 PATH 为空'
  } elseif ((Normalize $first[0]) -eq (Normalize $CLI_DIR)) {
    Ok "首位 = $($first[0])"
  } else {
    Bad "首位不是桌面端 CLI 目录，而是：$($first[0])"
    Info "期望首位：$CLI_DIR"
  }
}

# ── [3/7] 归属键 ──
Write-Host ''
Write-Host '[3/7] 归属键 HKCU\Software\DeepSeekHarness\Command' -ForegroundColor Cyan
$owner = Get-ItemProperty -LiteralPath 'HKCU:\Software\DeepSeekHarness\Command' -ErrorAction SilentlyContinue
if (-not $owner) {
  Bad '归属键不存在 → 桌面端命令管理器认为「未安装」'
} else {
  $dir = $owner.Directory
  if (-not $dir) {
    Bad '归属键存在但没有 Directory 值'
  } elseif ((Normalize $dir) -eq (Normalize $CLI_DIR)) {
    Ok "Directory = $dir"
    Info ("PathWasAbsent={0}  RetainedEntries={1}" -f $owner.PathWasAbsent, $owner.RetainedEntries)
  } else {
    Bad "Directory 不匹配：$dir"
  }
}

# ── [4/7] PATH 解析顺序（关键项）──
Write-Host ''
Write-Host '[4/7] PATH 解析顺序中先命中的 dsh（关键项）' -ForegroundColor Cyan
$machinePath = Get-MachinePathRaw
$resolved = Resolve-DshInPath -MachinePath $machinePath -UserPath $userPath
if (-not $resolved) {
  Bad '在 PATH 里找不到任何 dsh'
} elseif ((Normalize $resolved) -eq (Normalize $CLI_CMD)) {
  Ok "先命中桌面端：$resolved"
} else {
  Bad "先命中的不是桌面端：$resolved"
  Info "期望先命中：$CLI_CMD"
  Info '→ 说明旧 npm shim 的目录排在桌面端目录之前，安装未生效或 PATH 被改动。'
}

# ── [5/7] 当前会话环境 ──
Write-Host ''
Write-Host '[5/7] 当前会话里 dsh 的实际来源' -ForegroundColor Cyan
$sessionCmd = Get-Command dsh -All -ErrorAction SilentlyContinue
if (-not $sessionCmd) {
  Warn '当前会话 PATH 里没有 dsh'
} else {
  $src = @($sessionCmd)[0].Source
  if (-not $src) { $src = @($sessionCmd)[0].Definition }
  Info "Get-Command dsh → $src"
  if ($src -and ((Normalize $src) -in @((Normalize $CLI_CMD), (Normalize (Join-Path $CLI_DIR 'dsh.ps1'))))) {
    Ok '本会话已使用桌面端命令'
  } else {
    Warn '本会话仍是旧命令 → PATH 变更不回溯已运行进程，请新开一个终端再验'
  }
}

# ── [6/7] 旧 npm 全局包（预期保留）──
Write-Host ''
Write-Host '[6/7] 旧 npm 全局 dsh（按约定保留、应被遮蔽）' -ForegroundColor Cyan
if (Test-Path -LiteralPath $NPM_CMD -PathType Leaf) {
  $npmVer = $null
  try { $npmVer = (& $NPM_CMD --version 2>&1 | Select-Object -First 1) } catch { }
  Ok "旧 shim 仍在：$NPM_CMD（版本 $npmVer）"
  if ($ExpectedVersion -and $npmVer -and ($npmVer.Trim() -eq $ExpectedVersion)) {
    Warn '旧 shim 报出了桌面端版本 → 可能它已被改写，而不是靠 PATH 顺序遮蔽'
  }
} else {
  Warn "旧 shim 已不存在：$NPM_CMD（若已用 npm rm -g 清理，属预期）"
}

# ── [7/7] 陈旧/重复项 ──
Write-Host ''
Write-Host '[7/7] 用户 PATH 中的重复与陈旧项' -ForegroundColor Cyan
$parts = @(($userPath -split ';') | Where-Object { $_.Trim() -ne '' })
$dupCli = @($parts | Where-Object { (Normalize $_) -eq (Normalize $CLI_DIR) })
if ($dupCli.Count -gt 1) {
  Warn "桌面端 CLI 目录在用户 PATH 中出现 $($dupCli.Count) 次（应只 1 次）"
} else {
  Ok "桌面端 CLI 目录出现 $($dupCli.Count) 次"
}
$dupAny = @($parts | Group-Object { Normalize $_ } | Where-Object { $_.Count -gt 1 })
if ($dupAny.Count -gt 0) {
  Warn ("用户 PATH 有 {0} 组重复项：{1}" -f $dupAny.Count, (($dupAny | ForEach-Object { $_.Name }) -join ' | '))
} else {
  Ok '用户 PATH 无重复项'
}

# ── 结论 ──
Write-Host ''
Write-Host '=== 结论 ===' -ForegroundColor Cyan
Write-Host ("FAIL={0}  WARN={1}" -f $script:Fail, $script:Warn)
if ($script:Fail -gt 0) {
  Write-Host 'verify: FAILED' -ForegroundColor Red
  exit 1
}
Write-Host 'verify: PASSED' -ForegroundColor Green
exit 0
