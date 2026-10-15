#Requires -Version 5.1
<#
.SYNOPSIS
  端到端校验：把「已安装」的真实 profile 复制一份到 tmp/ 起临时实例，实测定制模式在
  完整 bundle 栈（含第三方插件）下的工具清单。

.DESCRIPTION
  为什么需要这一步（Windows 特有）：
    * `verify.ps1` 用的是 web 模板 profile，只有 `@deepseek-ai/dsh-base` + `dsh-web-app`
      两个 bundle，证明不了第三方 bundle（dsh-web-all / better-sidebar / dshmarket）
      与本预设共存时是否仍能挂载；
    * 桌面客户端不允许 CLI 直接组合它的 profile：
      `dsh --profile desktop --dump-config` →
      `error: profile "desktop" is managed exclusively by the Electron application`。

  做法（与 Linux 版日志里的 real-verify 同思路）：
    在 tmp/ 下建临时 DSH_HOME → 用 web 模板生成骨架 profile → 用真实 profile 的
    package.json + cordis.patch.yml 覆盖 → node_modules 指向真实 profile（junction）
    → 追加探针行 → 起临时实例读工具清单后杀掉。

  全程只写仓库 tmp/，不碰真实 profile（真实 profile 只被读取/junction）。

.PARAMETER SourceProfileDir
  源 profile 目录，缺省 $env:DSH_PROFILE_DIR，否则 $env:USERPROFILE\.dsh\profiles\desktop。

.PARAMETER Port
  临时实例端口，缺省 3125（避开 verify.ps1 的 3123）。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-custom\tools\verify-real-profile.ps1
#>
[CmdletBinding()]
param(
  [string]$SourceProfileDir,
  [int]$Port = 3125,
  [string]$Cli,
  [int]$ProbeDelayMs = 4000,
  [int]$TimeoutSec = 150,
  [string]$ProfileName = 'realverify'
)

$ErrorActionPreference = 'Stop'

$Expect = if ($env:OS -eq 'Windows_NT') {
  @('pwsh', 'read', 'read_image', 'write', 'edit', 'ask_user_question')
} else {
  @('bash', 'read', 'read_image', 'write', 'edit', 'ask_user_question')
}

$HERE = Split-Path -Parent $MyInvocation.MyCommand.Path
$MOD  = Split-Path -Parent $HERE
$REPO = (Resolve-Path (Join-Path $MOD '..\..')).Path
$WORK = Join-Path $REPO 'tmp\real-verify'
$DSHHOME = Join-Path $WORK 'dsh-home'
$PROFILE = Join-Path $DSHHOME "profiles\$ProfileName"
$PATCHF  = Join-Path $PROFILE 'cordis.patch.yml'
$OUTLOG  = Join-Path $WORK 'boot.out.log'
$ERRLOG  = Join-Path $WORK 'boot.err.log'
$BOOTLOG = Join-Path $WORK 'boot.log'

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
  throw 'verify-real: 找不到桌面客户端自带的 dsh CLI；用 -Cli <path\to\dsh.cmd> 指定。'
}

function Get-LaunchTargets {
  param([string]$CmdPath)
  $binDir = Split-Path -Parent $CmdPath
  $text   = [IO.File]::ReadAllText($CmdPath, [Text.Encoding]::UTF8)
  $exe = $null
  $entry = $null
  foreach ($m in [regex]::Matches($text, '"([^"]+)"')) {
    $expanded = $m.Groups[1].Value.Replace('%~dp0', "$binDir\")
    if ($expanded -match '\.exe$')    { $exe   = [IO.Path]::GetFullPath($expanded) }
    elseif ($expanded -match '\.js$') { $entry = [IO.Path]::GetFullPath($expanded) }
  }
  if (-not $exe)   { throw "verify-real: 无法从 $CmdPath 解析出宿主可执行文件" }
  if (-not $entry) { throw "verify-real: 无法从 $CmdPath 解析出 CLI 入口 js" }
  return [pscustomobject]@{ Exe = $exe; Entry = $entry }
}

function Read-LogSafe {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return '' }
  try { return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) } catch { return '' }
}

if (-not $SourceProfileDir) {
  if ($env:DSH_PROFILE_DIR) { $SourceProfileDir = $env:DSH_PROFILE_DIR }
  else { $SourceProfileDir = Join-Path $env:USERPROFILE '.dsh\profiles\desktop' }
}
$SourceProfileDir = (Resolve-Path -LiteralPath $SourceProfileDir).Path
if (-not (Test-Path -LiteralPath (Join-Path $SourceProfileDir 'cordis.patch.yml'))) {
  throw "verify-real: $SourceProfileDir 不像一个 profile 目录（缺 cordis.patch.yml）"
}
if (-not (Select-String -Path (Join-Path $SourceProfileDir 'cordis.patch.yml') -Pattern 'id: preset-custom' -Quiet)) {
  throw "verify-real: 源 profile 的 cordis.patch.yml 里没有 preset-custom；先跑 install.ps1。"
}

$CLI = Resolve-DshCli -Explicit $Cli
$version = (& $CLI --version 2>&1 | Select-Object -First 1)
Write-Host "verify-real: CLI = $CLI（$version）"
Write-Host "verify-real: 源 profile = $SourceProfileDir"

if (Test-Path -LiteralPath $WORK) { Remove-Item -LiteralPath $WORK -Recurse -Force }
New-Item -ItemType Directory -Force -Path $DSHHOME | Out-Null

$savedHome = $env:DSH_HOME
$env:DSH_HOME = $DSHHOME
$merged = ''
try {
  Write-Host "[1/4] 建临时 profile 骨架：$PROFILE"
  & $CLI --profile $ProfileName --from-default-profile web --dump-config > (Join-Path $WORK 'compose-skeleton.yml')
  if ($LASTEXITCODE -ne 0) { throw "verify-real: 骨架 profile 生成失败（exit $LASTEXITCODE）" }

  Write-Host '[2/4] 换成真实 profile 的 package.json + cordis.patch.yml（node_modules 走 junction）'
  Copy-Item -LiteralPath (Join-Path $SourceProfileDir 'package.json') -Destination (Join-Path $PROFILE 'package.json') -Force
  Copy-Item -LiteralPath (Join-Path $SourceProfileDir 'cordis.patch.yml') -Destination $PATCHF -Force
  $srcNm = Join-Path $SourceProfileDir 'node_modules'
  if (Test-Path -LiteralPath $srcNm) {
    New-Item -ItemType Junction -Path (Join-Path $PROFILE 'node_modules') -Target $srcNm | Out-Null
  } else {
    Write-Host '      （源 profile 没有 node_modules，跳过 junction——第三方 bundle 可能解析不到）'
  }
  Copy-Item -LiteralPath (Join-Path $HERE 'probe-preset-tools.mjs') -Destination (Join-Path $PROFILE 'probe-preset-tools.mjs') -Force
  $probeRow = @(
    ''
    '# verify-real-profile.ps1 临时追加（仅临时 profile）'
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
  & $CLI --profile $ProfileName --dump-config > (Join-Path $WORK 'compose-real.yml') 2> (Join-Path $WORK 'compose-real.err')
  if ($LASTEXITCODE -ne 0) {
    Get-Content (Join-Path $WORK 'compose-real.err') | Select-Object -First 20 | ForEach-Object { Write-Host "      $_" }
    throw "verify-real: 组合失败（exit $LASTEXITCODE）"
  }
  if (Select-String -Path (Join-Path $WORK 'compose-real.yml') -Pattern 'id: preset-custom' -Quiet) {
    Write-Host '      OK: 组合里出现 preset-custom'
  } else {
    throw 'verify-real: 组合里没有 preset-custom'
  }
  $composedLines = (Get-Content (Join-Path $WORK 'compose-real.yml')).Count
  Write-Host "      组合行数 = $composedLines"

  Write-Host "[4/4] 起临时实例（端口 $Port），读探针输出"
  $targets = Get-LaunchTargets -CmdPath $CLI
  $savedNode = $env:ELECTRON_RUN_AS_NODE
  $proc = $null
  try {
    $env:ELECTRON_RUN_AS_NODE = '1'
    $argLine = '--expose-internals "{0}" --profile {1} --no-open --port {2}' -f $targets.Entry, $ProfileName, $Port
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

$lines = $merged -split "`r?`n"
Write-Host '--- 探针输出 ---'
$probeLines = @($lines | Where-Object { $_ -match '\[probe\]' })
if ($probeLines.Count -eq 0) { Write-Host "（没有探针输出，日志见 $BOOTLOG）" } else { $probeLines | ForEach-Object { Write-Host $_ } }

Write-Host '--- 预设挂载诊断（应为空）---'
$warnLines = @($lines | Where-Object { $_ -match 'agent preset [A-Za-z0-9_-]+:\s' })
if ($warnLines.Count -eq 0) { Write-Host '（无告警）' } else { $warnLines | ForEach-Object { Write-Host $_ } }

Write-Host '--- 第三方 bundle 伪影（仅供判读，不影响结论）---'
@($lines | Where-Object { $_ -match 'did not activate|degraded|skipped' }) | Select-Object -First 12 | ForEach-Object { Write-Host $_ }

$customLine = @($probeLines | Where-Object { $_ -match '\[probe\] preset=custom\s+tools\(' })[0]
$failedLine = @($probeLines | Where-Object { $_ -match '\[probe\] preset=custom\s+FAILED' })
$ok = $true
if (-not $customLine) { Write-Host 'FAIL: 没有读到 preset=custom 的工具清单' -ForegroundColor Red; $ok = $false }
if ($failedLine.Count -gt 0) { Write-Host 'FAIL: 预设挂载失败' -ForegroundColor Red; $ok = $false }
if ($warnLines.Count -gt 0) { Write-Host 'FAIL: 出现 agent preset 挂载告警' -ForegroundColor Red; $ok = $false }
if ($customLine) {
  $names = @(($customLine -replace '^.*tools\(\d+\):\s*', '') -split ',\s*' | Where-Object { $_ -ne '' })
  $present = @($Expect | Where-Object { $names -contains $_ })
  $missing = @($Expect | Where-Object { $names -notcontains $_ })
  Write-Host ("[check] expect {0}: {1}/{2} PRESENT" -f ($Expect -join '/'), $present.Count, $Expect.Count)
  if ($missing.Count -gt 0) { Write-Host ("FAIL: 缺少工具 {0}" -f ($missing -join ', ')) -ForegroundColor Red; $ok = $false }
}

Write-Host ''
Write-Host "产物：$WORK（compose-real.yml / boot.log）"
if (-not $ok) { Write-Host 'verify-real: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'verify-real: PASSED' -ForegroundColor Green
exit 0
