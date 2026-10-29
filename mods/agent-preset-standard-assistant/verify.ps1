#Requires -Version 5.1
<#
.SYNOPSIS
  校验「标·准· 模式」：临时 DSH_HOME 里装一遍，实测工具清单 + 装配后的系统提示词。

.DESCRIPTION
  流程与 mods/agent-preset-custom/verify.ps1 一致：
    [1/4] 用 web 模板在 tmp/ 建临时 DSH_HOME + verify profile；
    [2/4] 跑 install.ps1（托管块 + 本地插件）并追加探针行；
    [3/4] --dump-config 组合检查（应出现 preset-standard-assistant）；
    [4/4] 起临时实例，读探针 JSON，断言：
          * 工具清单 = 标准模式的 30 个工具；
          * 系统提示词第一项 = deployment:persona-prefix / "You are a helpful software engineer assistant."；
          * 第二项 = harness:identity；
          * 其余非空段的名称序列与标准模式一致（只把人设段换掉、并挪到最前）。

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

# 0.2.1-rc.3 实测的非空段顺序（人设段换成本模式的文案并排到最前，其余与标准模式一致）。
$ExpectedSections = @(
  'deployment:persona-prefix'
  'harness:identity'
  'tool:pwsh'
  'tool:read'
  'tool:write'
  'tool:edit'
  'tool:glob'
  'tool:grep'
  'tool:jobs'
  'tool:web_search'
  'tool:web_fetch'
  'tool:goal'
  'tool:workflow'
  'tool:subagent_fork'
  'ui:deliverable-file-references'
  'harness:source'
  'app:web-surface'
)

$ExpectedTools = @(
  'ask_user_question', 'create_goal', 'edit', 'exit_plan_mode', 'get_goal', 'glob', 'grep',
  'interrupt_agent', 'job_kill', 'job_list', 'job_output', 'list_agents', 'present', 'pwsh',
  'read', 'read_image', 'schedule_create', 'schedule_delete', 'schedule_list', 'schedule_update',
  'send_message', 'skill', 'subagent_fork', 'todo_write', 'update_goal', 'web_fetch',
  'web_search', 'workflow', 'working_directory', 'write'
) | Sort-Object

$HERE    = Split-Path -Parent $MyInvocation.MyCommand.Path
$REPO    = (Resolve-Path (Join-Path $HERE '..\..')).Path
$WORK    = Join-Path $REPO 'tmp\standard-assistant-verify'
$DSHHOME = Join-Path $WORK 'dsh-home'
$PROFILE = Join-Path $DSHHOME 'profiles\verify'
$PATCHF  = Join-Path $PROFILE 'cordis.patch.yml'
$OUTLOG  = Join-Path $WORK 'boot.out.log'
$ERRLOG  = Join-Path $WORK 'boot.err.log'
$BOOTLOG = Join-Path $WORK 'boot.log'
$PROBEJSON = Join-Path $WORK 'probe.json'

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
    "        presetId: $PRESET_ID"
    "        outFile: '$($PROBEJSON.Replace('\', '/'))'"
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
    $done = "$PROBEJSON.done"
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
$warnLines = @(($merged -split "`r?`n") | Where-Object { $_ -match "agent preset $PRESET_ID`:" })
if ($warnLines.Count -eq 0) { Write-Host '（无告警）' } else { $warnLines | ForEach-Object { Write-Host $_ }; $ok = $false }

if (-not (Test-Path -LiteralPath $PROBEJSON)) {
  $errFile = "$PROBEJSON.error.txt"
  if (Test-Path -LiteralPath $errFile) { Write-Host '--- 探针错误 ---'; Get-Content -LiteralPath $errFile | Select-Object -First 15 | ForEach-Object { Write-Host $_ } }
  Write-Host "FAIL: 没有探针输出（日志见 $BOOTLOG）" -ForegroundColor Red
  exit 1
}

$data = Get-Content -LiteralPath $PROBEJSON -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host "--- 工具清单（$($data.tools.Count) 个）---"
Write-Host ("  " + ($data.tools -join ', '))

$actualNames = @($data.sections | Where-Object { $_.text -and $_.text.Length -gt 0 } | ForEach-Object { $_.name })
Write-Host '--- 系统提示词非空段顺序 ---'
for ($i = 0; $i -lt $actualNames.Count; $i++) { Write-Host ("  {0,2}. {1}" -f ($i + 1), $actualNames[$i]) }

# 1) 第一项必须是 persona-prefix（且文案正确）
if ($actualNames.Count -gt 0 -and $actualNames[0] -eq 'deployment:persona-prefix') {
  $firstText = @($data.sections | Where-Object { $_.name -eq 'deployment:persona-prefix' })[0].text
  if ($firstText -ceq $PERSONA_TEXT) {
    Write-Host "[check] 第一项 = deployment:persona-prefix / `"$PERSONA_TEXT`"  OK" -ForegroundColor Green
  } else {
    Write-Host "[FAIL] 第一项文案不符：$firstText" -ForegroundColor Red; $ok = $false
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

# 3) 其余段顺序应与标准模式一致（人设段换掉并前移）
$sameSequence = ($actualNames.Count -eq $ExpectedSections.Count)
if ($sameSequence) {
  for ($i = 0; $i -lt $ExpectedSections.Count; $i++) {
    if ($actualNames[$i] -ne $ExpectedSections[$i]) { $sameSequence = $false; Write-Host "  DIFF @${i}: 期望 $($ExpectedSections[$i]) 实际 $($actualNames[$i])" }
  }
}
if ($sameSequence) { Write-Host '[check] 段序列与预期一致  OK' -ForegroundColor Green }
else { Write-Host '[FAIL] 段序列与预期不一致（见上面 DIFF）' -ForegroundColor Red; $ok = $false }

# 4) 工具清单应与标准模式一致
$actualTools = @($data.tools | Sort-Object)
$missing = @($ExpectedTools | Where-Object { $actualTools -notcontains $_ })
$extra   = @($actualTools | Where-Object { $ExpectedTools -notcontains $_ })
if ($missing.Count -eq 0 -and $extra.Count -eq 0) {
  Write-Host "[check] 工具清单 = 标准模式的 $($ExpectedTools.Count) 个  OK" -ForegroundColor Green
} else {
  if ($missing.Count -gt 0) { Write-Host ("[FAIL] 缺少工具：{0}" -f ($missing -join ', ')) -ForegroundColor Red }
  if ($extra.Count -gt 0)   { Write-Host ("[FAIL] 多出工具：{0}" -f ($extra -join ', ')) -ForegroundColor Red }
  $ok = $false
}

Write-Host ''
Write-Host "产物：$WORK（probe.json / compose-verify.yml / boot.log）"
if (-not $ok) { Write-Host 'verify: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'verify: PASSED' -ForegroundColor Green
exit 0
