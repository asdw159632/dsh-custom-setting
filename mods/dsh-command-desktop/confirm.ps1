#Requires -Version 5.1
<#
.SYNOPSIS
  确认「管理 dsh 命令…」这个 GUI 入口的前置条件是否具备（纯只读）。

.DESCRIPTION
  该入口只存在于 Electron 桌面客户端的主窗口（dsh-app://app/），浏览器里的 dsh web 页面没有。
  本脚本回答三个问题：
    [1] 桌面客户端在跑吗？跑的是哪个 profile？（不同 profile 是不同的 DSH_HOME 视角）
    [2] 它用的是哪个 DSH_HOME / 用户数据目录？
    [3] 当前是否有 DSH 的 HTTP 监听端口（可能你正通过浏览器访问它）

  只读：仅枚举进程与命令行、读注册表/文件、查 TCP 监听；不写任何状态。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File mods\dsh-command-desktop\confirm.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '=== 桌面客户端入口前置条件（只读）===' -ForegroundColor Cyan

# ── [1] 进程与命令行 ──
Write-Host ''
Write-Host '[1] DeepSeek Harness 进程' -ForegroundColor Cyan
$procs = @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue)
if ($procs.Count -eq 0) {
  Write-Host '  [INFO] 桌面客户端没有在运行。' -ForegroundColor Yellow
  Write-Host '         → 启动它，然后在**它的窗口里**操作（浏览器里的 dsh web 页面没有该入口）。'
} else {
  $main = 0; $helper = 0
  $cmdlines = @{}
  $cmdOk = $true
  try {
    foreach ($c in (Get-CimInstance Win32_Process -Filter "Name = 'DeepSeek Harness.exe'" -ErrorAction Stop)) {
      $cmdlines[[int]$c.ProcessId] = [string]$c.CommandLine
    }
  } catch {
    $cmdOk = $false
    Write-Host "         （无法读取命令行：$($_.Exception.Message)）"
    Write-Host '         → 沙箱会话下常被拒；此时下面的「主/辅助」划分只是"未识别出 --type="的近似。'
  }
  foreach ($p in $procs) {
    $cl = $cmdlines[[int]$p.Id]
    $isHelper = $cl -and ($cl -match '--type=')
    if ($isHelper) { $helper++ } else { $main++ }
  }
  Write-Host ("  进程总数 = {0}（未识别为 --type= 辅助进程的 {1} 个 / 辅助进程 {2} 个）" -f $procs.Count, $main, $helper)
  if (-not $cmdOk) {
    Write-Host '  [INFO] 命令行不可读，无法精确区分主进程；但只要有进程在跑，Electron 主窗口就存在。' -ForegroundColor Yellow
  } elseif ($main -gt 0) {
    Write-Host '  [OK] 主进程在运行 → 其窗口里有「应用 / 编辑」按钮' -ForegroundColor Green
  } else {
    Write-Host '  [WARN] 只看到辅助进程，没识别出主进程' -ForegroundColor Yellow
  }
  foreach ($p in $procs) {
    if ($cmdlines.ContainsKey([int]$p.Id)) {
      $cl = $cmdlines[[int]$p.Id]
      if ($cl -match '--user-data-dir="?([^"\s]+)') {
        Write-Host ("  user-data-dir = {0}" -f $Matches[1])
      }
    }
  }
}

# ── [2] profile / DSH_HOME ──
Write-Host ''
Write-Host '[2] 当前会话的 profile 与 DSH_HOME' -ForegroundColor Cyan
Write-Host ("  DSH_PROFILE     = {0}" -f $(if ($env:DSH_PROFILE) { $env:DSH_PROFILE } else { '(未设置)' }))
Write-Host ("  DSH_HOME        = {0}" -f $(if ($env:DSH_HOME) { $env:DSH_HOME } else { '(未设置)' }))
Write-Host ("  DSH_PROFILE_DIR = {0}" -f $(if ($env:DSH_PROFILE_DIR) { $env:DSH_PROFILE_DIR } else { '(未设置)' }))
Write-Host '  注意：本脚本所在会话的 profile 与你点 GUI 的那个客户端是同一个（默认都是 desktop），'
Write-Host '        但**入口按钮只在 Electron 窗口里有**。'

# ── [3] HTTP 监听端口 ──
Write-Host ''
Write-Host '[3] DSH 的 HTTP 监听端口（可能你正通过浏览器访问）' -ForegroundColor Cyan
$listen = @()
$tcpOk = $true
try {
  $listen = @(Get-NetTCPConnection -State Listen -ErrorAction Stop |
    Where-Object { $_.LocalPort -ge 1024 -and $_.LocalPort -le 65535 })
} catch {
  $tcpOk = $false
  Write-Host "         （无法查询 TCP 连接：$($_.Exception.Message)）"
  Write-Host '         → DSH 沙箱会话里这个查询常被拒，结果不可当「没有端口」读。'
  Write-Host '           想看真实监听，请在**非沙箱**的 PowerShell 里跑：'
  Write-Host '             netstat -ano | findstr LISTENING'
}
$dshPorts = @()
foreach ($c in $listen) {
  $owner = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
  if ($owner -and $owner.ProcessName -like 'DeepSeek Harness*') {
    $dshPorts += [pscustomobject]@{ Port = $c.LocalPort; Pid = $c.OwningProcess }
  }
}
if (-not $tcpOk) {
  Write-Host '  （未取得端口信息，原因见上）'
} elseif ($dshPorts.Count -eq 0) {
  Write-Host '  （没找到属于 DeepSeek Harness 进程的监听端口）'
} else {
  foreach ($d in ($dshPorts | Sort-Object Port -Unique)) {
    Write-Host ("  pid {0} 监听 {1}  → http://127.0.0.1:{1}" -f $d.Pid, $d.Port)
  }
}
if ($env:DSH_WEB_URL) { Write-Host ("  本会话报告的 DSH_WEB_URL = {0}" -f $env:DSH_WEB_URL) }

# ── 结论 ──
Write-Host ''
Write-Host '=== 怎么用 ===' -ForegroundColor Cyan
Write-Host '  1. 切到 **DeepSeek Harness 桌面客户端窗口**（不是浏览器标签页）；'
Write-Host '  2. 左上角标题栏、侧栏折叠按钮右侧，左键点「应用」；'
Write-Host '  3. 菜单第 4 项「管理 dsh 命令…」→「安装」→「继续」；'
Write-Host '  4. 新开终端，跑 mods\dsh-command-desktop\verify.ps1 校验。'
Write-Host ''
Write-Host '  ⚠️ 浏览器里的 dsh web 页面（含本会话的 DSH_WEB_URL）没有 preload，'
Write-Host '     因此**没有**「应用/编辑」按钮——在浏览器里找不到是正常的。'
Write-Host ''
exit 0
