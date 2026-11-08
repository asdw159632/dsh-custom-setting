#Requires -Version 5.1
<#
.SYNOPSIS
  校验「标·准· 模式」：临时 DSH_HOME 里装一遍，与同实例里的标准模式对照装配结果。

.DESCRIPTION
  流程与 mods/agent-preset-custom/verify.ps1 一致：
    [1/4] 用 web 模板在 tmp/ 建临时 DSH_HOME + verify profile；
    [2/4] 跑 install.ps1（托管块 + 本地插件）并追加探针行；
    [3/4] --dump-config 组合检查（应出现 preset-standard-assistant）；
    [4/4] 起临时实例，同时探测 standard 与 standard-assistant，断言：
          * 挂载诊断里没有 `agent preset ...:` 告警（两个模式都不能挂载失败）；
          * 工具清单与同实例的标准模式**完全一致**（不写死工具名，宿主升级不误报）；
          * 系统提示词第一项 = deployment:persona-prefix / 本模式文案；
          * 第二项 = harness:identity；
          * 其余非空段的名称序列 = 标准模式去掉自己 persona 段后的序列。

  与旧版的差别：不再硬编码 0.2.1-rc.3 的段名/工具名，改为与同时探测的标准模式对照，
  因此宿主升级后（如 0.2.2-rc.1 删掉 list-agents、新增 apply_patch）不会假失败。

  全程只写仓库 tmp/，不碰真实 DSH_HOME，不需要提权。

.PARAMETER Port
  临时实例端口，缺省 3128（避开 custom 的 3123 / real-profile 的 3125）。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-standard-assistant\verify.ps1
#>
[CmdletBinding()]
param(
  [int]$Port = 3128,
  [string]$Cli,
  [int]$ProbeDelayMs = 6000,
  [int]$TimeoutSec = 90
)

$ErrorActionPreference = 'Stop'

$PERSONA_TEXT  = 'You are a helpful software engineer assistant.'
$IDENTITY_TEXT = 'You are an AI agent powered by DeepSeek Harness.'
$PRESET_ID     = 'standard-assistant'
$REFERENCE_ID  = 'standard'

$HERE    = Split-Path -Parent $MyInvocation.MyCommand.Path
$REPO    = (Resolve-Path (Join-Path $HERE '..\..')).Path
$WORK    = Join-Path $REPO 'tmp\standard-assistant-verify'
$DSHHOME = Join-Path $WORK 'dsh-home'
$PROFILE = Join-Path $DSHHOME 'profiles\verify'
$PATCHF  = Join-Path $PROFILE 'cordis.patch.yml'
$OUTLOG  = Join-Path $WORK 'boot.out.log'
$ERRLOG  = Join-Path $WORK 'boot.err.log'
$BOOTLOG = Join-Path $WORK 'boot.log'
$PROBEDIR = Join-Path $WORK 'probe'
$PROBEJSON = Join-Path $PROBEDIR "$PRESET_ID.json"
$STDJSON   = Join-Path $PROBEDIR "$REFERENCE_ID.json"

function Resolve-DshCli {
  param([string]$Explicit)
  $cands = New-Object System.Collections.Generic.List[string]
  if ($Explicit) { $cands.Add($Explicit) }
  if ($env:DSH_CLI) { $cands.Add($env:DSH_CLI) }
  $cands.Add('D:\software\DeepseekHarness\desktop\resources\runtime\cli\bin\dsh.cmd')
  $cands.Add((Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\resources\runtime\cli\bin\dsh.cmd'))
  $cands.Add((Join-Path $env:ProgramFiles 'DeepSeek Harness\resources\runtime\cli\bin\dsh.cmd'))
  foreach ($c in $cands) {
    if ($c -and (Test-Path -LiteralPath $c)) { return (Resolve-Path -LiteralPath $c).Path }
  }
  throw 'verify: 找不到桌面客户端自带的 dsh CLI；用 -Cli <path\to\dsh.cmd> 指定。'
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
Write-Host "verify: CLI = $CLI（$((& $CLI --version 2>&1 | Select-Object -First 1))）"

if (Test-Path -LiteralPath $WORK) { Remove-Item -LiteralPath $WORK -Recurse -Force }
New-Item -ItemType Directory -Force -Path $DSHHOME | Out-Null

$savedHome = $env:DSH_HOME
$env:DSH_HOME = $DSHHOME
$merged = ''
try {
  Write-Host "[1/4] 用 web 模板建临时 profile：$PROFILE"
  & $CLI --profile verify --from-default-profile web --dump-config > (Join-Path $WORK 'compose-base.yml')
  if ($LASTEXITCODE -ne 0) { throw "verify: 模板 profile 生成失败（exit $LASTEXITCODE）" }

  Write-Host '[2/4] 安装托管块 + 本地插件 + 探针行'
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $HERE 'install.ps1') -ProfileDir $PROFILE > (Join-Path $WORK 'install.log')
  if ($LASTEXITCODE -ne 0) { throw "verify: install.ps1 失败（exit $LASTEXITCODE）" }
  Copy-Item -LiteralPath (Join-Path $HERE 'tools\probe-preset.mjs') -Destination (Join-Path $PROFILE 'probe-preset.mjs') -Force

  $probeRow = @(
    ''
    '# verify.ps1 临时追加（仅临时 profile）'
    '- insert:'
    '    - id: probe-preset'
    "      name: './probe-preset.mjs'"
    '      config:'
    "        presetIds: ['$REFERENCE_ID', '$PRESET_ID']"
    "        outDir: '$($PROBEDIR.Replace('\', '/'))'"
    "        delayMs: $ProbeDelayMs"
  ) -join "`n"
  [IO.File]::AppendAllText($PATCHF, $probeRow, (New-Object System.Text.UTF8Encoding($false)))

  Write-Host '[3/4] 组合检查（--dump-config）'
  & $CLI --profile verify --dump-config > (Join-Path $WORK 'compose-verify.yml')
  if ($LASTEXITCODE -ne 0) { throw "verify: 组合失败（exit $LASTEXITCODE）" }
  if (Select-String -Path (Join-Path $WORK 'compose-verify.yml') -Pattern 'id: preset-standard-assistant' -Quiet) {
    Write-Host '      OK: 组合里出现 preset-standard-assistant'
  } else {
    throw 'verify: 组合里没有 preset-standard-assistant'
  }

  Write-Host "[4/4] 起临时实例（端口 $Port），同时探测 $REFERENCE_ID 与 $PRESET_ID"
  $targets = Get-LaunchTargets -CmdPath $CLI
  if (-not (Test-Path -LiteralPath $targets.Exe)) { throw "verify: 宿主可执行文件不存在：$($targets.Exe)" }

  $savedNode = $env:ELECTRON_RUN_AS_NODE
  $proc = $null
  try {
    $env:ELECTRON_RUN_AS_NODE = '1'
    $argLine = '--expose-internals "{0}" --profile verify --no-open --port {1}' -f $targets.Entry, $Port
    $proc = Start-Process -FilePath $targets.Exe -ArgumentList $argLine -NoNewWindow -PassThru `
              -RedirectStandardOutput $OUTLOG -RedirectStandardError $ERRLOG -WorkingDirectory $REPO
    $done = Join-Path $PROBEDIR 'all.done'
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
      Start-Sleep -Milliseconds 1000
      if (Test-Path -LiteralPath $done) { break }
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
$ok = $true
Write-Host '--- 预设挂载诊断（应为空）---'
$warnLines = @(($merged -split "`r?`n") | Where-Object { $_ -match "agent preset (standard|standard-assistant):" })
if ($warnLines.Count -eq 0) { Write-Host '（无告警）' } else { $warnLines | ForEach-Object { Write-Host $_ }; $ok = $false }

foreach ($f in @($PROBEJSON, $STDJSON)) {
  if (-not (Test-Path -LiteralPath $f)) {
    $errFile = [IO.Path]::ChangeExtension($f, '.error.txt')
    if (Test-Path -LiteralPath $errFile) { Write-Host "--- 探针错误 $f ---"; Get-Content -LiteralPath $errFile | Select-Object -First 15 | ForEach-Object { Write-Host $_ } }
    Write-Host "FAIL: 没有探针输出 $f（日志见 $BOOTLOG）" -ForegroundColor Red
    $ok = $false
  }
}
if (-not $ok) { Write-Host 'verify: FAILED' -ForegroundColor Red; exit 1 }

$data = Get-Content -LiteralPath $PROBEJSON -Raw -Encoding UTF8 | ConvertFrom-Json
$std  = Get-Content -LiteralPath $STDJSON  -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host "--- 工具清单（$($data.tools.Count) 个）---"
Write-Host ("  " + ($data.tools -join ', '))

function Get-NonEmptyNames {
  param($Probe)
  return @($Probe.sections | Where-Object { $_.text -and $_.text.Length -gt 0 } | ForEach-Object { $_.name })
}
$actualNames = Get-NonEmptyNames -Probe $data
$stdNames    = Get-NonEmptyNames -Probe $std
Write-Host '--- 系统提示词非空段顺序 ---'
for ($i = 0; $i -lt $actualNames.Count; $i++) { Write-Host ("  {0,2}. {1}" -f ($i + 1), $actualNames[$i]) }

# 1) 第一项必须是 persona-prefix（且文案正确）
$personaSection = @($data.sections | Where-Object { $_.name -eq 'deployment:persona-prefix' })
if ($actualNames.Count -gt 0 -and $actualNames[0] -eq 'deployment:persona-prefix') {
  if ($personaSection.Count -eq 1 -and $personaSection[0].text -ceq $PERSONA_TEXT) {
    Write-Host "[check] 第一项 = deployment:persona-prefix / `"$PERSONA_TEXT`"  OK" -ForegroundColor Green
  } else {
    Write-Host "[FAIL] 第一项文案不符（出现 $($personaSection.Count) 次）：$($personaSection[0].text)" -ForegroundColor Red; $ok = $false
  }
} else {
  Write-Host "[FAIL] 第一项不是 deployment:persona-prefix（实际：$($actualNames[0])）" -ForegroundColor Red; $ok = $false
}

# 2) 第二项必须是 harness:identity
if ($actualNames.Count -gt 1 -and $actualNames[1] -eq 'harness:identity') {
  $identityText = @($data.sections | Where-Object { $_.name -eq 'harness:identity' })[0].text
  if ($identityText -ceq $IDENTITY_TEXT) {
    Write-Host '[check] 第二项 = harness:identity  OK' -ForegroundColor Green
  } else {
    Write-Host "[FAIL] 身份段文案不符：$identityText" -ForegroundColor Red; $ok = $false
  }
} else {
  Write-Host "[FAIL] 第二项不是 harness:identity（实际：$($actualNames[1])）" -ForegroundColor Red; $ok = $false
}

# 3) 其余段 = 标准模式去掉它自己的 persona 段（逐项同名、同序）
$stdTail = @($stdNames | Where-Object { $_ -ne 'deployment:persona-prefix' })
$actTail = @()
if ($actualNames.Count -gt 0) { $actTail = @($actualNames[1..($actualNames.Count - 1)]) }
$sameSequence = ($actTail.Count -eq $stdTail.Count)
if ($sameSequence) {
  for ($i = 0; $i -lt $stdTail.Count; $i++) {
    if ($actTail[$i] -ne $stdTail[$i]) { $sameSequence = $false; Write-Host "  DIFF @${i}: 标准= $($stdTail[$i]) 实际= $($actTail[$i])" }
  }
}
if ($sameSequence) {
  Write-Host "[check] 其余 $($stdTail.Count) 段与标准模式一致（仅 persona 段被替换并前移）  OK" -ForegroundColor Green
} else {
  Write-Host '[FAIL] 段序列与标准模式不一致（见上面 DIFF）' -ForegroundColor Red; $ok = $false
}

# 4) 工具清单应与标准模式完全一致
$actualTools = @($data.tools | Sort-Object)
$stdTools    = @($std.tools | Sort-Object)
$missing = @($stdTools | Where-Object { $actualTools -notcontains $_ })
$extra   = @($actualTools | Where-Object { $stdTools -notcontains $_ })
if ($missing.Count -eq 0 -and $extra.Count -eq 0) {
  Write-Host "[check] 工具清单 = 标准模式的 $($stdTools.Count) 个  OK" -ForegroundColor Green
} else {
  if ($missing.Count -gt 0) { Write-Host ("[FAIL] 缺少工具：{0}" -f ($missing -join ', ')) -ForegroundColor Red }
  if ($extra.Count -gt 0)   { Write-Host ("[FAIL] 多出工具：{0}" -f ($extra -join ', ')) -ForegroundColor Red }
  $ok = $false
}

Write-Host ''
Write-Host "产物：$WORK（probe\*.json / compose-verify.yml / boot.log）"
if (-not $ok) { Write-Host 'verify: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'verify: PASSED' -ForegroundColor Green
exit 0
