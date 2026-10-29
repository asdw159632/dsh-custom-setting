#Requires -Version 5.1
<#
.SYNOPSIS
  把「助手标准模式」（agent preset id: standard-assistant）装进目标 dsh profile 的 cordis.patch.yml。

.DESCRIPTION
  与同工作区 mods/agent-preset-custom/install.ps1 同一套做法：
    * 先整份备份 cordis.patch.yml（同目录 .bak-<时间戳>）；
    * 以块标记插入/替换本 mod 的托管块（幂等，重复执行不会叠加）；
    * 目标文件是空模板 [] 时整体重写，避免 `- insert:` 跟在 `[]` 后面变成非法 YAML；
    * 保留原文件的 BOM 有无与换行风格（LF / CRLF）。

  额外一步：把 persona-prefix-first.mjs 复制到 profile 目录。
  原因：预设声明里的插件行写的是相对路径 './persona-prefix-first.mjs'，
  Loader 以**插入该行的 patch 文件所在目录**（即 profile 目录）为锚点解析它。

.PARAMETER ProfileDir
  profile 目录。缺省顺序：
    1. -ProfileDir 显式传入；
    2. $env:DSH_PROFILE_DIR（在 DSH 会话里 = 当前 GUI 正在用的 profile）；
    3. $env:DSH_HOME\profiles\desktop；
    4. $env:USERPROFILE\.dsh\profiles\desktop。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-standard-assistant\install.ps1
#>
[CmdletBinding()]
param(
  [string]$ProfileDir
)

$ErrorActionPreference = 'Stop'

$BEGIN_MARK = '# >>> agent-preset-standard-assistant (助手标准模式) managed block >>>'
$END_MARK   = '# <<< agent-preset-standard-assistant (助手标准模式) managed block <<<'
$PLUGIN_NAME = 'persona-prefix-first.mjs'

$HERE       = Split-Path -Parent $MyInvocation.MyCommand.Path
$PATCH_SRC  = Join-Path $HERE 'standard-assistant.patch.yml'
$PLUGIN_SRC = Join-Path $HERE $PLUGIN_NAME

function Resolve-ProfileDir {
  param([string]$Explicit)
  if ($Explicit) { return $Explicit }
  if ($env:DSH_PROFILE_DIR) { return $env:DSH_PROFILE_DIR }
  $dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
  return (Join-Path $dshHome 'profiles\desktop')
}

function Read-PatchText {
  param([string]$Path)
  $bytes  = [IO.File]::ReadAllBytes($Path)
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
  $eol  = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
  return [pscustomobject]@{ Text = $text; HasBom = $hasBom; Eol = $eol }
}

function Write-PatchText {
  param([string]$Path, [string]$Text, [bool]$HasBom, [string]$Eol)
  $normalized = ($Text -replace "`r`n", "`n") -replace "`n", $Eol
  $enc = New-Object System.Text.UTF8Encoding($HasBom)
  [IO.File]::WriteAllText($Path, $normalized, $enc)
}

function Remove-ManagedBlock {
  param([string]$Text)
  $kept = New-Object System.Collections.Generic.List[string]
  $skip = $false
  foreach ($line in ($Text -replace "`r`n", "`n") -split "`n") {
    if (-not $skip -and $line.StartsWith($BEGIN_MARK)) { $skip = $true;  continue }
    if ($skip      -and $line.StartsWith($END_MARK))   { $skip = $false; continue }
    if (-not $skip) { $kept.Add($line) }
  }
  return ($kept -join "`n")
}

if (-not (Test-Path -LiteralPath $PATCH_SRC))  { throw "install: 缺少 $PATCH_SRC" }
if (-not (Test-Path -LiteralPath $PLUGIN_SRC)) { throw "install: 缺少 $PLUGIN_SRC" }

$PROFILE_DIR = Resolve-ProfileDir -Explicit $ProfileDir
$PATCH_FILE  = Join-Path $PROFILE_DIR 'cordis.patch.yml'
if (-not (Test-Path -LiteralPath $PROFILE_DIR)) { throw "install: profile 目录不存在：$PROFILE_DIR" }
if (-not (Test-Path -LiteralPath $PATCH_FILE))  { throw "install: profile patch 不存在：$PATCH_FILE" }

$STAMP  = Get-Date -Format 'yyyyMMdd-HHmmss'
$BACKUP = "$PATCH_FILE.bak-$STAMP"
Copy-Item -LiteralPath $PATCH_FILE -Destination $BACKUP -Force

$current = Read-PatchText -Path $PATCH_FILE
$body    = Remove-ManagedBlock -Text $current.Text

$core = (($body -split "`n") | Where-Object {
  $t = $_.Trim()
  $t -ne '' -and -not $t.StartsWith('#')
}) -join ''
$isEmptyTemplate = ($core.Trim() -eq '' -or $core.Trim() -eq '[]')

$srcText = ([IO.File]::ReadAllText($PATCH_SRC, [Text.Encoding]::UTF8) -replace "`r`n", "`n").TrimEnd("`n")
$block   = @(
  $BEGIN_MARK
  '# 由 mods/agent-preset-standard-assistant/install.ps1 写入；手改请改 mods 里的 standard-assistant.patch.yml 后重跑。'
) + ($srcText -split "`n") + @($END_MARK)

if ($isEmptyTemplate) {
  $head = @(
    '# Your patch layer for this dsh profile, applied after every bundle layer:'
    '# a top-level YAML array of loader patch entries (id-targeted config'
    '# overrides, disables, and insert lists; `!!js` expressions allowed).'
    '#'
    '# 「助手标准模式」预设行由 mods/agent-preset-standard-assistant/install.ps1 托管（块标记见下）。'
  )
  $newText = (($head + $block) -join "`n").TrimEnd("`n") + "`n"
} else {
  $newText = ($body.TrimEnd("`n") + "`n`n" + ($block -join "`n")).TrimEnd("`n") + "`n"
}

# 本地插件行按「patch 文件所在目录」解析，必须随 profile 一起放。
# 先放插件再写补丁：桌面端会热加载 cordis.patch.yml，若先写补丁，热加载瞬间可能
# 解析不到插件而让该预设挂载失败。
Copy-Item -LiteralPath $PLUGIN_SRC -Destination (Join-Path $PROFILE_DIR $PLUGIN_NAME) -Force

Write-PatchText -Path $PATCH_FILE -Text $newText -HasBom $current.HasBom -Eol $current.Eol

Write-Host "install: 已写入 $PATCH_FILE"
Write-Host "install: 已放置插件 $PROFILE_DIR\$PLUGIN_NAME"
Write-Host "install: 备份 $BACKUP"
Write-Host "install: 重启客户端（或等宿主热加载）后，新建任务 →「Agent 预设 → 自定义」里即可看到「助手标准模式」。"
