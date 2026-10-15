#Requires -Version 5.1
<#
.SYNOPSIS
  把「定制模式」（agent preset id: custom）装进目标 dsh profile 的 cordis.patch.yml。

.DESCRIPTION
  移植自同目录 Linux 版 install.sh 的行为，逐条对应：
    * 先整份备份 cordis.patch.yml（同目录 .bak-<时间戳>）；
    * 以块标记插入/替换本 mod 的托管块（幂等，重复执行不会叠加）；
    * 目标文件是空模板 [] 时整体重写，避免 `- insert:` 跟在 `[]` 后面变成非法 YAML；
    * 额外：保留原文件的 BOM 有无与换行风格（LF / CRLF）。

.PARAMETER ProfileDir
  profile 目录。缺省顺序：
    1. -ProfileDir 显式传入；
    2. $env:DSH_PROFILE_DIR（在 DSH 会话里 = 当前 GUI 正在用的 profile）；
    3. $env:DSH_HOME\profiles\desktop；
    4. $env:USERPROFILE\.dsh\profiles\desktop。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-custom\install.ps1

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-custom\install.ps1 `
    -ProfileDir D:\tmp\dsh-home\profiles\verify
#>
[CmdletBinding()]
param(
  [string]$ProfileDir
)

$ErrorActionPreference = 'Stop'

# ── 托管块标记：与 Linux 版 install.sh / uninstall.sh 逐字一致，便于两边对账 ──
$BEGIN_MARK = '# >>> agent-preset-custom (定制模式) managed block >>>'
$END_MARK   = '# <<< agent-preset-custom (定制模式) managed block <<<'

$HERE      = Split-Path -Parent $MyInvocation.MyCommand.Path
$PATCH_SRC = Join-Path $HERE 'custom.patch.yml'

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
  # File.ReadAllText 会自行识别并剥掉 BOM；这里只把「原来有没有 BOM」记下来以便原样写回。
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

# ── 前置检查 ──
if (-not (Test-Path -LiteralPath $PATCH_SRC)) { throw "install: 缺少 $PATCH_SRC" }
$PROFILE_DIR = Resolve-ProfileDir -Explicit $ProfileDir
$PATCH_FILE  = Join-Path $PROFILE_DIR 'cordis.patch.yml'
if (-not (Test-Path -LiteralPath $PROFILE_DIR)) { throw "install: profile 目录不存在：$PROFILE_DIR" }
if (-not (Test-Path -LiteralPath $PATCH_FILE))  { throw "install: profile patch 不存在：$PATCH_FILE" }

$STAMP  = Get-Date -Format 'yyyyMMdd-HHmmss'
$BACKUP = "$PATCH_FILE.bak-$STAMP"
Copy-Item -LiteralPath $PATCH_FILE -Destination $BACKUP -Force

$current = Read-PatchText -Path $PATCH_FILE
$body    = Remove-ManagedBlock -Text $current.Text

# 去掉注释与空行后还剩什么（判断是否空模板）
$core = (($body -split "`n") | Where-Object {
  $t = $_.Trim()
  $t -ne '' -and -not $t.StartsWith('#')
}) -join ''
$isEmptyTemplate = ($core.Trim() -eq '' -or $core.Trim() -eq '[]')

$srcText = ([IO.File]::ReadAllText($PATCH_SRC, [Text.Encoding]::UTF8) -replace "`r`n", "`n").TrimEnd("`n")
$block   = @(
  $BEGIN_MARK
  '# 由 mods/agent-preset-custom/install.ps1 写入；手改请改 mods 里的 custom.patch.yml 后重跑。'
) + ($srcText -split "`n") + @($END_MARK)

if ($isEmptyTemplate) {
  # 空模板 [] 必须整体重写：`- insert:` 直接跟在 `[]` 后面不是合法 YAML。
  $head = @(
    '# Your patch layer for this dsh profile, applied after every bundle layer:'
    '# a top-level YAML array of loader patch entries (id-targeted config'
    '# overrides, disables, and insert lists; `!!js` expressions allowed).'
    '#'
    '# 「定制模式」预设行由 mods/agent-preset-custom/install.ps1 托管（块标记见下）。'
  )
  $newText = (($head + $block) -join "`n").TrimEnd("`n") + "`n"
} else {
  $newText = ($body.TrimEnd("`n") + "`n`n" + ($block -join "`n")).TrimEnd("`n") + "`n"
}

Write-PatchText -Path $PATCH_FILE -Text $newText -HasBom $current.HasBom -Eol $current.Eol

Write-Host "install: 已写入 $PATCH_FILE"
Write-Host "install: 备份   $BACKUP"
Write-Host "install: 重启客户端（DSH GUI / dsh web）后，新建任务 →「Agent 预设 → 自定义」里即可看到「定制模式」。"
