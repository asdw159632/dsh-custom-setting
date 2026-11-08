#Requires -Version 5.1
<#
.SYNOPSIS
  端到端校验「标·准· 模式」：把「已安装」的真实 profile 复制一份到 tmp/ 起临时实例，
  在完整 bundle 栈（含第三方插件）下同时探测 standard 与 standard-assistant 并对照。

.DESCRIPTION
  为什么需要这一步（Windows 特有）：
    * verify.ps1 用的是 web 模板 profile，只有 @deepseek-ai/dsh-base + dsh-web-app
      两个 bundle，证明不了第三方 bundle（dsh-web-all / better-sidebar / dshmarket 等）
      与「标·准· 模式」共存时仍能挂载；
    * 桌面客户端不允许 CLI 直接组合它的 profile：
      `dsh --profile desktop --dump-config` → profile is managed exclusively by the Electron application。

  做法：在 tmp/ 下建临时 DSH_HOME → 复制真实 profile 的 package.json + cordis.patch.yml
  + 本地插件（persona-prefix-first.mjs）→ node_modules 指向真实 profile（junction）
  → 追加探针行 → 起临时实例探测后杀掉。
  （不用 web 模板骨架：真实 patch 里引用了第三方 bundle 的条目，骨架里没有那些条目，
    --dump-config 会报 patch entry not found。）

  全程只写仓库 tmp/，不碰真实 profile（真实 profile 只被读取/junction）。

.PARAMETER SourceProfileDir
  源 profile 目录，缺省 $env:DSH_PROFILE_DIR，否则 $env:USERPROFILE\.dsh\profiles\desktop。

.PARAMETER Port
  临时实例端口，缺省 3126（避开 verify.ps1 的 3128 与 custom 的 3123/3125）。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-standard-assistant\tools\verify-real-profile.ps1
#>
[CmdletBinding()]
param(
  [string]$SourceProfileDir,
  [int]$Port = 3126,
  [string]$Cli,
  [int]$ProbeDelayMs = 5000,
  [int]$TimeoutSec = 150,
  [string]$ProfileName = 'sarealverify'
)

$ErrorActionPreference = 'Stop'

$PERSONA_TEXT  = 'You are a helpful software engineer assistant.'
$IDENTITY_TEXT = 'You are an AI agent powered by DeepSeek Harness.'
$PRESET_ID     = 'standard-assistant'
$REFERENCE_ID  = 'standard'

$HERE = Split-Path -Parent $MyInvocation.MyCommand.Path
$MOD  = Split-Path -Parent $HERE
$REPO = (Resolve-Path (Join-Path $MOD '..\..')).Path
$WORK = Join-Path $REPO 'tmp\standard-assistant-real'
$DSHHOME = Join-Path $WORK 'dsh-home'
$PROFILE = Join-Path $DSHHOME "profiles\$ProfileName"
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
if (-not (Select-String -Path (Join-Path $SourceProfileDir 'cordis.patch.yml') -Pattern 'id: preset-standard-assistant' -Quiet)) {
  throw "verify-real: 源 profile 的 cordis.patch.yml 里没有 preset-standard-assistant；先跑 install.ps1。"
}

$CLI = Resolve-DshCli -Explicit $Cli
Write-Host "verify-real: CLI = $CLI（$((& $CLI --version 2>&1 | Select-Object -First 1))）"
Write-Host "verify-real: 源 profile = $SourceProfileDir"

if (Test-Path -LiteralPath $WORK) { Remove-Item -LiteralPath $WORK -Recurse -Force }
New-Item -ItemType Directory -Force -Path $DSHHOME | Out-Null
New-Item -ItemType Directory -Force -Path $PROBEDIR | Out-Null

$savedHome = $env:DSH_HOME
$env:DSH_HOME = $DSHHOME
$merged = ''
try {
  Write-Host "[1/4] 建临时 profile 目录：$PROFILE"
  New-Item -ItemType Directory -Force -Path $PROFILE | Out-Null
  $pathPatch = Join-Path $WORK 'paths.txt'
  "REPO=$REPO`nPROFILE=$PROFILE`nWORK=$WORK" | Set-Content -LiteralPath $pathPatch -Encoding UTF8
  Write-Host '      OK：目录已建（下一步复制真实 profile 文件）'

  Write-Host '[2/4] 换成真实 profile 的 package.json + cordis.patch.yml + 本地插件（node_modules 走 junction）'
  Copy-Item -LiteralPath (Join-Path $SourceProfileDir 'package.json') -Destination (Join-Path $PROFILE 'package.json') -Force
  Copy-Item -LiteralPath (Join-Path $SourceProfileDir 'cordis.patch.yml') -Destination $PATCHF -Force
  Copy-Item -LiteralPath (Join-Path $SourceProfileDir 'persona-prefix-first.mjs') -Destination (Join-Path $PROFILE 'persona-prefix-first.mjs') -Force

  # 真实 profile 里有历史遗留的 patch 行，指向已从 bundle 移除的条目（如
  # web-ui-model-capabilities），`--dump-config` 会因此直接失败；这与本预设无关，
  # 只在**临时副本**里剔除，源 profile 一个字节都不改。
  $staleText = [IO.File]::ReadAllText($PATCHF, [Text.Encoding]::UTF8)
  $stalePattern = '(?m)^- id: web-ui-model-capabilities\r?\n(?:  [^\r\n]*\r?\n)*'
  if ($staleText -match $stalePattern) {
    $staleText = [regex]::Replace($staleText, $stalePattern, '')
    [IO.File]::WriteAllText($PATCHF, $staleText, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host '      （临时副本已剔除历史遗留行 web-ui-model-capabilities）'
  }
  $srcNm = Join-Path $SourceProfileDir 'node_modules'
  if (Test-Path -LiteralPath $srcNm) {
    New-Item -ItemType Junction -Path (Join-Path $PROFILE 'node_modules') -Target $srcNm | Out-Null
  } else {
    Write-Host '      （源 profile 没有 node_modules，跳过 junction——第三方 bundle 可能解析不到）'
  }
  Copy-Item -LiteralPath (Join-Path $HERE 'probe-preset.mjs') -Destination (Join-Path $PROFILE 'probe-preset.mjs') -Force
  $probeRow = @(
    ''
    '# verify-real-profile.ps1 临时追加（仅临时 profile）'
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
  & $CLI --profile $ProfileName --dump-config > (Join-Path $WORK 'compose-real.yml') 2> (Join-Path $WORK 'compose-real.err')
  if ($LASTEXITCODE -ne 0) {
    Get-Content (Join-Path $WORK 'compose-real.err') | Select-Object -First 20 | ForEach-Object { Write-Host "      $_" }
    throw "verify-real: 组合失败（exit $LASTEXITCODE）"
  }
  if (Select-String -Path (Join-Path $WORK 'compose-real.yml') -Pattern 'id: preset-standard-assistant' -Quiet) {
    Write-Host '      OK: 组合里出现 preset-standard-assistant'
  } else {
    throw 'verify-real: 组合里没有 preset-standard-assistant'
  }

  Write-Host "[4/4] 起临时实例（端口 $Port），同时探测 $REFERENCE_ID 与 $PRESET_ID"
  $targets = Get-LaunchTargets -CmdPath $CLI
  $savedNode = $env:ELECTRON_RUN_AS_NODE
  $proc = $null
  try {
    $env:ELECTRON_RUN_AS_NODE = '1'
    $argLine = '--expose-internals "{0}" --profile {1} --no-open --port {2}' -f $targets.Entry, $ProfileName, $Port
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
Write-Host '--- 预设挂载诊断（应为空）---'
$warnLines = @(($merged -split "`r?`n") | Where-Object { $_ -match "agent preset (standard|standard-assistant):" })
if ($warnLines.Count -eq 0) { Write-Host '（无告警）' } else { $warnLines | ForEach-Object { Write-Host $_ } }

$ok = $true
if ($warnLines.Count -gt 0) { $ok = $false }
foreach ($f in @($PROBEJSON, $STDJSON)) {
  if (-not (Test-Path -LiteralPath $f)) {
    $errFile = [IO.Path]::ChangeExtension($f, '.error.txt')
    if (Test-Path -LiteralPath $errFile) { Write-Host "--- 探针错误 $f ---"; Get-Content -LiteralPath $errFile | Select-Object -First 15 | ForEach-Object { Write-Host $_ } }
    Write-Host "FAIL: 没有探针输出 $f（日志见 $BOOTLOG）" -ForegroundColor Red
    $ok = $false
  }
}
if (-not $ok) { Write-Host 'verify-real: FAILED' -ForegroundColor Red; exit 1 }

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

$personaSection = @($data.sections | Where-Object { $_.name -eq 'deployment:persona-prefix' })
if ($actualNames.Count -gt 0 -and $actualNames[0] -eq 'deployment:persona-prefix') {
  if ($personaSection.Count -eq 1 -and $personaSection[0].text -ceq $PERSONA_TEXT) {
    Write-Host '[check] 第一项 = persona-prefix（文案正确、只出现一次）  OK' -ForegroundColor Green
  } else {
    Write-Host "[FAIL] 第一项文案不符（出现 $($personaSection.Count) 次）：$($personaSection[0].text)" -ForegroundColor Red; $ok = $false
  }
} else {
  Write-Host "[FAIL] 第一项不是 deployment:persona-prefix（实际：$($actualNames[0])）" -ForegroundColor Red; $ok = $false
}

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
  Write-Host "[check] 其余 $($stdTail.Count) 段与标准模式一致  OK" -ForegroundColor Green
} else {
  Write-Host '[FAIL] 段序列与标准模式不一致（见上面 DIFF）' -ForegroundColor Red; $ok = $false
}

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
Write-Host "产物：$WORK（probe\*.json / compose-real.yml / boot.log）"
if (-not $ok) { Write-Host 'verify-real: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'verify-real: PASSED' -ForegroundColor Green
exit 0
