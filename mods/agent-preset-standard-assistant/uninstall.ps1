#Requires -Version 5.1
<#
.SYNOPSIS
  从目标 dsh profile 里摘掉「助手标准模式」：托管块 + 本地插件 persona-prefix-first.mjs。

.DESCRIPTION
  先整份备份 cordis.patch.yml，再按块标记摘除；摘完只剩注释/空行时写回空模板 []。
  保留原文件的 BOM 有无与换行风格。

.PARAMETER ProfileDir
  profile 目录。缺省顺序同 install.ps1。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-standard-assistant\uninstall.ps1
#>
[CmdletBinding()]
param(
  [string]$ProfileDir
)

$ErrorActionPreference = 'Stop'

$BEGIN_MARK  = '# >>> agent-preset-standard-assistant (助手标准模式) managed block >>>'
$END_MARK    = '# <<< agent-preset-standard-assistant (助手标准模式) managed block <<<'
$PLUGIN_NAME = 'persona-prefix-first.mjs'

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

$PROFILE_DIR = Resolve-ProfileDir -Explicit $ProfileDir
$PATCH_FILE  = Join-Path $PROFILE_DIR 'cordis.patch.yml'
if (-not (Test-Path -LiteralPath $PATCH_FILE)) { throw "uninstall: 找不到 $PATCH_FILE" }

$current = Read-PatchText -Path $PATCH_FILE
$pluginPath = Join-Path $PROFILE_DIR $PLUGIN_NAME

if (-not ($current.Text -replace "`r`n", "`n").Contains($BEGIN_MARK)) {
  Write-Host "uninstall: $PATCH_FILE 里没有托管块。"
} else {
  $STAMP  = Get-Date -Format 'yyyyMMdd-HHmmss'
  $BACKUP = "$PATCH_FILE.bak-$STAMP"
  Copy-Item -LiteralPath $PATCH_FILE -Destination $BACKUP -Force

  $body = Remove-ManagedBlock -Text $current.Text
  $core = (($body -split "`n") | Where-Object {
    $t = $_.Trim()
    $t -ne '' -and -not $t.StartsWith('#')
  }) -join ''

  if ($core.Trim() -eq '' -or $core.Trim() -eq '[]') {
    $newText = @(
      '# Your patch layer for this dsh profile, applied after every bundle layer:'
      '# a top-level YAML array of loader patch entries (id-targeted config'
      '# overrides, disables, and insert lists; `!!js` expressions allowed).'
      '[]'
    ) -join "`n"
    $newText = $newText.TrimEnd("`n") + "`n"
  } else {
    $newText = $body.TrimEnd("`n") + "`n"
  }

  Write-PatchText -Path $PATCH_FILE -Text $newText -HasBom $current.HasBom -Eol $current.Eol
  Write-Host "uninstall: 已从 $PATCH_FILE 移除托管块"
  Write-Host "uninstall: 备份 $BACKUP"
}

if (Test-Path -LiteralPath $pluginPath) {
  Remove-Item -LiteralPath $pluginPath -Force
  Write-Host "uninstall: 已删除本地插件 $pluginPath"
}

Write-Host "uninstall: 重启客户端后「助手标准模式」即消失。"
