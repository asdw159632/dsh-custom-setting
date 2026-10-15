#Requires -Version 5.1
<#
.SYNOPSIS
  校验「定制模式」：静态组合检查 + 起一个临时 web 实例，实测该预设对模型可见的工具清单。

.DESCRIPTION
  移植自同目录 Linux 版 verify.sh，四步一一对应：
    [1/4] 在仓库 tmp/ 下建临时 DSH_HOME，用 web 模板生成临时 profile verify；
    [2/4] 把托管块装进该临时 profile，并追加探针行；
    [3/4] --dump-config 组合检查（应出现 preset-custom）；
    [4/4] 起临时实例（--no-open --port），读探针打印的工具清单后杀掉进程。

  为什么需要临时实例：预设行是运行时挂载的，config dump 只能证明 patch 组合正确，
  证明不了 read_image 之类「要等 attachments 服务」的行真的注册成功。探针插件
  （tools/probe-preset-tools.mjs）读 preset standing scope 的工具视图，等价于模型
  在该模式下看到的工具目录。

  全程只写仓库 tmp/，不碰真实 DSH_HOME，不需要提权。

.PARAMETER Port
  临时实例监听端口，缺省 3123。

.PARAMETER Cli
  dsh CLI（0.2.0-rc.2 宿主自带），缺省自动探测：
  $env:DSH_CLI → $env:DSH_CLI_CANDIDATES → D:\software\DSH\resources\runtime\cli\bin\dsh.cmd
  → %LOCALAPPDATA%\Programs\DeepSeek Harness\... → %ProgramFiles%\DeepSeek Harness\...

.PARAMETER ProbeDelayMs
  探针延迟（毫秒），缺省 4000。

.PARAMETER TimeoutSec
  等待探针输出的上限秒数，缺省 90。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-custom\verify.ps1
#>
[CmdletBinding()]
param(
  [int]$Port = 3123,
  [string]$Cli,
  [int]$ProbeDelayMs = 4000,
  [int]$TimeoutSec = 90
)

$ErrorActionPreference = 'Stop'

# ── 期望工具清单：Windows 上极简模式生效的是 persistent-pwsh（工具名 pwsh），
#    Linux 上才是 persistent-bash（工具名 bash）。两者是同一份 custom.patch.yml。──
$Expect = if ($env:OS -eq 'Windows_NT') {
  @('pwsh', 'read', 'read_image', 'write', 'edit', 'ask_user_question')
} else {
  @('bash', 'read', 'read_image', 'write', 'edit', 'ask_user_question')
}

$HERE     = Split-Path -Parent $MyInvocation.MyCommand.Path
$REPO     = (Resolve-Path (Join-Path $HERE '..\..')).Path
$WORK     = Join-Path $REPO 'tmp\agent-preset-custom-verify'
$DSHHOME  = Join-Path $WORK 'dsh-home'
$PROFILE  = Join-Path $DSHHOME 'profiles\verify'
$PATCHF   = Join-Path $PROFILE 'cordis.patch.yml'
$OUTLOG   = Join-Path $WORK 'boot.out.log'
$ERRLOG   = Join-Path $WORK 'boot.err.log'
$BOOTLOG  = Join-Path $WORK 'boot.log'

function Resolve-DshCli {
  param([string]$Explicit)
  $cands = New-Object System.Collections.Generic.List[string]
  if ($Explicit) { $cands.Add($Explicit) }
  if ($env:DSH_CLI) { $cands.Add($env:DSH_CLI) }
  $cands.Add('D:\software\DSH\resources\runtime\cli\bin\dsh.cmd')
  $cands.Add((Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\resources\runtime\cli\bin\dsh.cmd'))
  $cands.Add((Join-Path $env:ProgramFiles 'DeepSeek Harness\resources\runtime\cli\bin\dsh.cmd'))
  foreach ($c in $cands) {
    if ($c -and (Test-Path -LiteralPath $c)) { return (Resolve-Path -LiteralPath $c).Path }
  }
  throw 'verify: 找不到桌面客户端自带的 dsh CLI；用 -Cli <path\to\dsh.cmd> 指定。'
}

# dsh.cmd 里是 `set ELECTRON_RUN_AS_NODE=1` + `"<root>\DeepSeek Harness.exe" --expose-internals
# "<root>\resources\app.asar\dsh\...\cli.js"`。这里把 %~dp0 展开，解析出可直接 Start-Process
# 的 exe 与 asar 内的入口 js（入口在 asar 里，不能 Test-Path）。
function Get-LaunchTargets {
  param([string]$CmdPath)
  $binDir = Split-Path -Parent $CmdPath
  $text   = [IO.File]::ReadAllText($CmdPath, [Text.Encoding]::UTF8)
  $exe = $null
  $entry = $null
  foreach ($m in [regex]::Matches($text, '"([^"]+)"')) {
    $expanded = $m.Groups[1].Value.Replace('%~dp0', "$binDir\")
    if ($expanded -match '\.exe$')     { $exe   = [IO.Path]::GetFullPath($expanded) }
    elseif ($expanded -match '\.js$')  { $entry = [IO.Path]::GetFullPath($expanded) }
  }
  if (-not $exe)   { throw "verify: 无法从 $CmdPath 解析出宿主可执行文件" }
  if (-not $entry) { throw "verify: 无法从 $CmdPath 解析出 CLI 入口 js" }
  return [pscustomobject]@{ Exe = $exe; Entry = $entry }
}

function Read-LogSafe {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return '' }
  try { return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) } catch { return '' }
}

$CLI = Resolve-DshCli -Explicit $Cli
$version = (& $CLI --version 2>&1 | Select-Object -First 1)
Write-Host "verify: CLI = $CLI"
Write-Host "verify: 宿主版本 = $version"

if (Test-Path -LiteralPath $WORK) { Remove-Item -LiteralPath $WORK -Recurse -Force }
New-Item -ItemType Directory -Force -Path $DSHHOME | Out-Null

$savedHome = $env:DSH_HOME
$env:DSH_HOME = $DSHHOME
try {
  Write-Host "[1/4] 用 web 模板建临时 profile：$PROFILE"
  & $CLI --profile verify --from-default-profile web --dump-config > (Join-Path $WORK 'compose-base.yml')
  if ($LASTEXITCODE -ne 0) { throw "verify: 模板 profile 生成失败（exit $LASTEXITCODE）" }

  Write-Host '[2/4] 安装托管块 + 探针行'
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $HERE 'install.ps1') -ProfileDir $PROFILE > (Join-Path $WORK 'install.log')
  if ($LASTEXITCODE -ne 0) { throw "verify: install.ps1 失败（exit $LASTEXITCODE）" }
  Copy-Item -LiteralPath (Join-Path $HERE 'tools\probe-preset-tools.mjs') -Destination (Join-Path $PROFILE 'probe-preset-tools.mjs') -Force

  $probeRow = @(
    ''
    '# verify.ps1 临时追加（仅临时 profile）'
    '- insert:'
    '    - id: probe-preset-tools'
    "      name: './probe-preset-tools.mjs'"
    '      config:'
    '        presetIds: [minimal, custom]'
    "        delayMs: $ProbeDelayMs"
    "        expect: [$($Expect -join ', ')]"
  ) -join "`n"
  [IO.File]::AppendAllText($PATCHF, $probeRow, (New-Object System.Text.UTF8Encoding($false)))

  Write-Host '[3/4] 组合检查（--dump-config）'
  & $CLI --profile verify --dump-config > (Join-Path $WORK 'compose-verify.yml')
  if ($LASTEXITCODE -ne 0) { throw "verify: 组合失败（exit $LASTEXITCODE）" }
  if (Select-String -Path (Join-Path $WORK 'compose-verify.yml') -Pattern 'id: preset-custom' -Quiet) {
    Write-Host '      OK: 组合里出现 preset-custom'
  } else {
    throw 'verify: 组合里没有 preset-custom'
  }

  Write-Host "[4/4] 起临时实例（端口 $Port），读探针输出"
  $targets = Get-LaunchTargets -CmdPath $CLI
  if (-not (Test-Path -LiteralPath $targets.Exe)) { throw "verify: 宿主可执行文件不存在：$($targets.Exe)" }

  $savedNode = $env:ELECTRON_RUN_AS_NODE
  $proc = $null
  try {
    $env:ELECTRON_RUN_AS_NODE = '1'
    $argLine = '--expose-internals "{0}" --profile verify --no-open --port {1}' -f $targets.Entry, $Port
    $proc = Start-Process -FilePath $targets.Exe -ArgumentList $argLine -NoNewWindow -PassThru `
              -RedirectStandardOutput $OUTLOG -RedirectStandardError $ERRLOG -WorkingDirectory $REPO

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
      Start-Sleep -Milliseconds 1000
      if ((Read-LogSafe -Path $OUTLOG) -match '\[probe\] preset=') { break }
      if ($proc.HasExited) { break }
    }
  } finally {
    if ($proc -and -not $proc.HasExited) {
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
      try { $null = $proc.WaitForExit(10000) } catch { }
    }
    $env:ELECTRON_RUN_AS_NODE = $savedNode
  }

  $merged = (Read-LogSafe -Path $OUTLOG) + "`n" + (Read-LogSafe -Path $ERRLOG)
  [IO.File]::WriteAllText($BOOTLOG, $merged, (New-Object System.Text.UTF8Encoding($false)))
} finally {
  $env:DSH_HOME = $savedHome
}

# ── 判读 ──
$lines = $merged -split "`r?`n"
Write-Host '--- 探针输出 ---'
$probeLines = @($lines | Where-Object { $_ -match '\[probe\]' })
if ($probeLines.Count -eq 0) { Write-Host "（没有探针输出，日志见 $BOOTLOG）" } else { $probeLines | ForEach-Object { Write-Host $_ } }

Write-Host '--- 预设挂载诊断（应为空）---'
$warnLines = @($lines | Where-Object { $_ -match 'agent preset [A-Za-z0-9_-]+:\s' })
if ($warnLines.Count -eq 0) { Write-Host '（无告警）' } else { $warnLines | ForEach-Object { Write-Host $_ } }

$customLine = @($probeLines | Where-Object { $_ -match '\[probe\] preset=custom\s+tools\(' })[0]
$failedLine = @($probeLines | Where-Object { $_ -match '\[probe\] preset=custom\s+FAILED' })

$ok = $true
if (-not $customLine) { Write-Host 'FAIL: 没有读到 preset=custom 的工具清单' -ForegroundColor Red; $ok = $false }
if ($failedLine.Count -gt 0) { Write-Host 'FAIL: 预设挂载失败（见上面的 FAILED 行）' -ForegroundColor Red; $ok = $false }
if ($warnLines.Count -gt 0) { Write-Host 'FAIL: 出现 agent preset 挂载告警' -ForegroundColor Red; $ok = $false }

if ($customLine) {
  $names = @(($customLine -replace '^.*tools\(\d+\):\s*', '') -split ',\s*' | Where-Object { $_ -ne '' })
  $missing = @($Expect | Where-Object { $names -notcontains $_ })
  $present = @($Expect | Where-Object { $names -contains $_ })
  Write-Host ("[check] expect {0}: {1}/{2} PRESENT" -f ($Expect -join '/'), $present.Count, $Expect.Count)
  if ($missing.Count -gt 0) { Write-Host ("FAIL: 缺少工具 {0}" -f ($missing -join ', ')) -ForegroundColor Red; $ok = $false }
}

Write-Host ''
Write-Host "产物：$WORK（compose-verify.yml / boot.log）"
if (-not $ok) { Write-Host 'verify: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'verify: PASSED' -ForegroundColor Green
exit 0
