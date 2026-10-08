<#
.SYNOPSIS
    Restore the OFFICIAL @deepseek-ai/dsh-client-ui-workspace/lib/client.js into the
    desktop client's app.asar, replacing the locally patched copy.

.DESCRIPTION
    One logical job: put the official (backup) bytes of the asar entry

        /dsh/node_modules/@deepseek-ai/dsh-client-ui-workspace/lib/client.js

    back into the asar, and repair everything that depends on that entry's length.

    TWO LAYOUTS ARE HANDLED
    -----------------------
    (a) IN-PLACE OVERWRITE
        The current entry size equals the backup size (length-neutral patch).
        The backup bytes are written in place; nothing else changes.

    (b) REORDER / REBUILD  (the layout in use since 2026-10-08)
        The patched entry GREW (200124 -> 204728 bytes, +4604) and the asar was rebuilt
        by tmp\write_back_asar.mjs: every data-area entry was copied forward, every
        `offset` recomputed, every `integrity.hash` recomputed. Restoring the smaller
        official file therefore has to:
          1. write the backup bytes at the target entry's CURRENT offset;
          2. shift every entry after the target back by the size delta;
          3. rewrite the target entry's `size`;
          4. shift the `offset` of every entry after the target by -delta;
          5. recompute the target entry's `integrity.hash`;
          6. truncate the file to the new data end.
        The header JSON is edited as TEXT, and the edit is asserted to be
        byte-length-neutral, so the 16-byte pickle prefix (offsets 4 / 8 / 12) and the
        header length stay untouched.

    SAFETY
    ------
      * Refuses to run unless the backup's SHA256 equals the known-official hash of the
        0.2.0-rc.2 file (override only with -Force).
      * Prints entry offset/size, header lengths and hashes BEFORE and AFTER.
      * Refuses on implausible geometry: delta not integral, target not last in the
        data area, data end beyond EOF, ambiguous header tokens, header length drift.
      * Verifies AFTER writing by re-parsing the header, re-hashing the target entry,
        and asserting the new file length.

    ROLLBACK OF THE ROLLBACK
    ------------------------
    To go forward again, re-run tmp\build_active_workspaces_patch.mjs and then
    tmp\write_back_asar.mjs apply. Keeping a whole-asar copy before any write makes
    this trivial; nothing in this script creates one.

.PARAMETER AsarPath
    Path of the app.asar to repair. Default: the desktop client asar.

.PARAMETER BackupPath
    Path of the official client.js backup. Default: the newest matching file in the
    workspace tmp\ folder (patterns: backup-asar-entry-client*.js,
    backup-asar-ui-workspace-*.js, official-ui-workspace-client*.js).

.PARAMETER WhatIfOnly
    Print the plan (geometry, delta, hashes) and write nothing.

.PARAMETER Force
    Proceed even when the backup hash is not the known-official constant. Use only if
    the constant below is stale for a newer client build.

.NOTES
    SANDBOX / PRIVILEGE
    -------------------
    The asar lives OUTSIDE the DSH workspace write scope
    (workspace: D:\文档\DSH-plugin\DSH-custom; asar: D:\software\DeepSeek Harness\...).
    Under the default `workspace-write` sandbox the write fails with
    "[sandbox: file access denied under workspace-write mode]". Run this script once
    with a one-shot elevation (permission mode danger-full-access) for the write step.
    A delegated subagent cannot elevate itself; ask the human / team lead.

    WINDOWS POWERSHELL 5.1
    ----------------------
    This machine has no `pwsh`. Run with:
        powershell -NoProfile -ExecutionPolicy Bypass -File <this file>
    The file is kept ASCII-only and stored as UTF-8 with BOM, because PS 5.1 reads a
    BOM-less .ps1 with the system ANSI code page (GBK here).

    CLOSE THE CLIENT FIRST IF YOU CAN. The asar can be opened r+ while the client runs,
    but a running client may re-read files; a clean exit avoids surprises.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File mods\active-workspaces\scripts\restore-official-ui-workspace.ps1 -WhatIfOnly

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File mods\active-workspaces\scripts\restore-official-ui-workspace.ps1
#>
[CmdletBinding()]
param(
    [string]$AsarPath = 'D:\software\DeepSeek Harness\resources\app.asar',
    [string]$BackupPath = '',
    [switch]$WhatIfOnly,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

$EntrySegments = @('dsh', 'node_modules', '@deepseek-ai', 'dsh-client-ui-workspace', 'lib', 'client.js')

# Official client.js of package 0.2.0-rc.2 (client build of 2026-10-08).
$OfficialSha256 = '29c34ce1c2a437cf8a50ba35d1ae44741114439e37a17153dfd4b1aa942aa955'

# Workspace root: <root>\mods\active-workspaces\scripts\this.ps1
$WorkspaceRoot    = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$DefaultBackupDir = Join-Path $WorkspaceRoot 'tmp'
$BackupPatterns   = @('backup-asar-entry-client*.js', 'backup-asar-ui-workspace-*.js', 'official-ui-workspace-client*.js')

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Get-Sha256Hex {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Read-AsarHeader {
    <#  Read the 16-byte pickle prefix plus the header JSON. Never writes. #>
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $prefix = New-Object byte[] 16
        $read = $stream.Read($prefix, 0, 16)
        if ($read -ne 16) { throw "asar too short to contain a header: $Path" }

        $headerSize = [BitConverter]::ToUInt32($prefix, 4)
        $jsonSize   = [BitConverter]::ToUInt32($prefix, 12)
        $base       = 16L + [long]$jsonSize

        $jsonBytes = New-Object byte[] $jsonSize
        $stream.Seek(16, [System.IO.SeekOrigin]::Begin) | Out-Null
        $got = $stream.Read($jsonBytes, 0, $jsonSize)
        if ($got -ne $jsonSize) { throw "short read of asar header ($got of $jsonSize bytes)" }

        $jsonText = [System.Text.Encoding]::UTF8.GetString($jsonBytes)

        # --- 诊断开始 ---
Write-Host ("prefix 16 bytes : {0}" -f (($prefix | ForEach-Object { '{0:X2}' -f $_ }) -join ' '))
Write-Host ("u32@0  = {0}   (expected 4)"     -f [BitConverter]::ToUInt32($prefix, 0))
Write-Host ("u32@4  = {0}   (headerSize)"     -f $headerSize)
Write-Host ("u32@8  = {0}"                     -f [BitConverter]::ToUInt32($prefix, 8))
Write-Host ("u32@12 = {0}   (jsonSize)"       -f $jsonSize)
Write-Host ("first 200 chars of jsonText:")
Write-Host ($jsonText.Substring(0, [Math]::Min(200, $jsonText.Length)))
# --- 诊断结束 ---

        $header   = ConvertFrom-Json $jsonText
    } finally {
        $stream.Dispose()
    }

    return [pscustomobject]@{
        Path        = $Path
        HeaderSize  = $headerSize
        JsonSize    = $jsonSize
        PayloadBase = $base
        JsonText    = $jsonText
        Json        = $header
    }
}

function Find-AsarEntry {
    param($Header, [string[]]$Segments)

    $node = $Header
    $walked = @()
    foreach ($seg in $Segments) {
        $walked += $seg
        $child = $node.files.$seg
        if ($null -eq $child) {
            throw ("asar entry not found; failed at segment '{0}' (walked: {1})" -f $seg, ($walked -join '/'))
        }
        $node = $child
    }
    if ($null -eq $node.offset -or $null -eq $node.size) {
        throw "resolved node is a directory, not a file: $($Segments -join '/')"
    }
    return $node
}

function Get-AsarEntries {
    <#  Flatten data-area entries. Directories and `unpacked` nodes (1497 of them, which
        have no offset and live in app.asar.unpacked) are skipped. Order follows the
        JSON property order, i.e. the order the repacker wrote them. #>
    param($Node, [string]$Prefix = '')

    $out = New-Object System.Collections.ArrayList
    if ($null -eq $Node -or $null -eq $Node.files) { return $out }
    $targetPath = '/' + ($EntrySegments -join '/')
    foreach ($prop in $Node.files.PSObject.Properties) {
        $name  = $prop.Name
        $child = $prop.Value
        $q = $Prefix + '/' + $name
        if ($null -ne $child.files) {
            foreach ($item in (Get-AsarEntries -Node $child -Prefix $q)) { [void]$out.Add($item) }
            continue
        }
        if ($null -ne $child.unpacked -or $null -eq $child.offset) { continue }
        [void]$out.Add([pscustomobject]@{
            Path     = $q
            Node     = $child
            Offset   = [long]$child.offset
            Size     = [long]$child.size
            IsTarget = ($q -eq $targetPath)
        })
    }
    return $out
}

function Resolve-BackupPath {
    param([string]$Explicit, [string]$Dir, [string[]]$Patterns)

    if ($Explicit -ne '') {
        if (-not (Test-Path -LiteralPath $Explicit -PathType Leaf)) { throw "backup file not found: $Explicit" }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }
    if (-not (Test-Path -LiteralPath $Dir)) { throw "default backup directory not found: $Dir" }

    $found = @()
    foreach ($p in $Patterns) {
        $found += @(Get-ChildItem -LiteralPath $Dir -Filter $p -File -ErrorAction SilentlyContinue)
    }
    if ($found.Count -eq 0) {
        throw "no backup found in $Dir (patterns: $($Patterns -join ', ')). Pass -BackupPath explicitly."
    }
    # Prefer the canonical single-entry backup over timestamped or legacy copies.
    $canonical = @($found | Where-Object { $_.Name -like 'backup-asar-entry-client*.js' })
    $pool = if ($canonical.Count -gt 0) { $canonical } else { $found }
    if ($pool.Count -gt 1) {
        Write-Host "note: $($pool.Count) candidate backups, using the newest one." -ForegroundColor DarkGray
        Write-Host "      (pass -BackupPath to pick a specific one)" -ForegroundColor DarkGray
    }
    return ($pool | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

function Copy-FileRegion {
    <#  Copy $Length bytes from $Source@$SourceOffset to $Dest@$DestOffset with a bounded
        buffer, so the 118 MB data area is never held in memory. Source and Dest may be
        the same handle; forward movement makes the overlapping copies safe. #>
    param(
        [Parameter(Mandatory = $true)][System.IO.FileStream]$Source,
        [Parameter(Mandatory = $true)][System.IO.FileStream]$Dest,
        [Parameter(Mandatory = $true)][long]$SourceOffset,
        [Parameter(Mandatory = $true)][long]$DestOffset,
        [Parameter(Mandatory = $true)][long]$Length,
        [int]$BufferSize = 8388608
    )

    $buf = New-Object byte[] ([int][Math]::Min([long]$BufferSize, [Math]::Max($Length, 1)))
    $remaining = $Length
    $srcPos = $SourceOffset
    $dstPos = $DestOffset
    while ($remaining -gt 0) {
        $want = [int][Math]::Min([long]$buf.Length, $remaining)
        $Source.Seek($srcPos, [System.IO.SeekOrigin]::Begin) | Out-Null
        $got = $Source.Read($buf, 0, $want)
        if ($got -le 0) { throw "unexpected end of source while copying ($remaining bytes left)" }
        $Dest.Seek($dstPos, [System.IO.SeekOrigin]::Begin) | Out-Null
        $Dest.Write($buf, 0, $got)
        $srcPos    += $got
        $dstPos    += $got
        $remaining -= $got
    }
}

function Format-Int {
    param([long]$Value)
    return $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '=== restore official dsh-client-ui-workspace/lib/client.js into app.asar ===' -ForegroundColor Cyan
Write-Host "asar  : $AsarPath"
Write-Host "entry : /$($EntrySegments -join '/')"
Write-Host ''

if (-not (Test-Path -LiteralPath $AsarPath -PathType Leaf)) { throw "asar not found: $AsarPath" }

$backup = Resolve-BackupPath -Explicit $BackupPath -Dir $DefaultBackupDir -Patterns $BackupPatterns
Write-Host "backup: $backup"

$backupBytes = [System.IO.File]::ReadAllBytes($backup)
$backupHash  = Get-Sha256Hex -Bytes $backupBytes
Write-Host ("backup sha256 : {0}  ({1} bytes)" -f $backupHash, $backupBytes.Length)
if ($backupHash -ne $OfficialSha256) {
    $msg = "backup sha256 is not the known-official hash for 0.2.0-rc.2 ($OfficialSha256)."
    if ($Force) {
        Write-Host "WARNING: $msg Continuing because -Force was given." -ForegroundColor Yellow
    } else {
        throw "$msg Refusing to write. Re-check the backup, or pass -Force if this client build genuinely moved on."
    }
}

$hdr   = Read-AsarHeader -Path $AsarPath
$entry = Find-AsarEntry -Header $hdr.Json -Segments $EntrySegments

$entryOffset = [long]$entry.offset
$entrySize   = [long]$entry.size
$entryStart  = $hdr.PayloadBase + $entryOffset

$currentBytes = New-Object byte[] $entrySize
$rs = [System.IO.File]::Open($AsarPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
try {
    $rs.Seek($entryStart, [System.IO.SeekOrigin]::Begin) | Out-Null
    $got = $rs.Read($currentBytes, 0, $entrySize)
    if ($got -ne $entrySize) { throw "short read of the current entry ($got of $entrySize bytes)" }
} finally { $rs.Dispose() }
$currentHash = Get-Sha256Hex -Bytes $currentBytes

$fileLength   = (Get-Item -LiteralPath $AsarPath).Length
$delta        = $entrySize - $backupBytes.Length        # >0 => the asar must shrink
$needsRebuild = ($delta -ne 0)

Write-Host ''
Write-Host '--- BEFORE ---'
Write-Host ("file length      : {0}" -f $fileLength)
Write-Host ("headerSize       : {0}   jsonSize: {1}   payload base: {2}" -f $hdr.HeaderSize, $hdr.JsonSize, $hdr.PayloadBase)
Write-Host ("entry offset     : {0}   (absolute {1})" -f $entryOffset, $entryStart)
Write-Host ("entry size       : {0}" -f $entrySize)
Write-Host ("entry sha256     : {0}" -f $currentHash)
Write-Host ("header integrity : {0}" -f $entry.integrity.hash)
Write-Host ("backup size      : {0}   delta = {1}" -f $backupBytes.Length, $delta)
if ($needsRebuild) {
    Write-Host 'mode             : REORDER/REBUILD (entry size differs from the backup)' -ForegroundColor Yellow
} else {
    Write-Host 'mode             : IN-PLACE OVERWRITE (same length)'
}

if ($currentHash -eq $backupHash) {
    Write-Host ''
    Write-Host 'The entry already contains the official bytes -- nothing to restore.' -ForegroundColor Yellow
    if ([string]$entry.integrity.hash -ne $currentHash) {
        Write-Host 'note: the header integrity hash disagrees with the content; re-run the repacker if that matters.' -ForegroundColor DarkGray
    }
    exit 0
}

if ([string]$currentHash -ne [string]$entry.integrity.hash) {
    Write-Host ''
    Write-Host 'WARNING: the current entry does not match its own header integrity hash.' -ForegroundColor Yellow
    Write-Host '         Expected for an asar left behind by a repacker that failed its self-check;' -ForegroundColor DarkGray
    Write-Host '         it means the header hash is stale, not that the content is wrong.' -ForegroundColor DarkGray
}

# --- geometry -------------------------------------------------------------
if ($entryStart + $entrySize -gt $fileLength) {
    throw ("implausible geometry: the entry ends at {0} but the file is {1} bytes" -f ($entryStart + $entrySize), $fileLength)
}

$entries     = @(Get-AsarEntries -Node $hdr.Json)
$afterTarget = @($entries | Where-Object { $_.Offset -gt $entryOffset } | Sort-Object Offset)
$dataEnd     = 0L
foreach ($item in $entries) {
    if (($item.Offset + $item.Size) -gt $dataEnd) { $dataEnd = $item.Offset + $item.Size }
}

Write-Host ''
Write-Host '--- PLAN ---'
Write-Host ("data-area entries : {0}   highest end offset: {1}" -f $entries.Count, $dataEnd)

if ($needsRebuild) {
    if ($dataEnd -ne ($entryOffset + $entrySize)) {
        throw ("cannot rebuild: the target entry is not the last content of the data area " +
               "(its end {0} != highest end {1}). This is not the layout the documented repacker " +
               "produces; restore the whole asar from a backup instead." -f ($entryOffset + $entrySize), $dataEnd)
    }
    Write-Host ("will shift {0} entries that follow the target back by {1} bytes" -f $afterTarget.Count, $delta)
    Write-Host ("new file length   : {0}" -f ($fileLength - $delta))
    Write-Host ("new entry size    : {0}" -f $backupBytes.Length)
    Write-Host ("new data end      : {0}" -f ($entryOffset + $backupBytes.Length))
}

if ($WhatIfOnly) {
    Write-Host ''
    Write-Host 'WhatIfOnly: no bytes written.' -ForegroundColor Yellow
    Write-Host 'Removing -WhatIfOnly performs the restore described above.'
    exit 0
}

# --- write ----------------------------------------------------------------
Write-Host ''
Write-Host 'writing the official bytes into the asar...' -ForegroundColor Cyan

$fs = [System.IO.File]::Open($AsarPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
try {
    # 1) the target entry's new content
    $fs.Seek($entryStart, [System.IO.SeekOrigin]::Begin) | Out-Null
    $fs.Write($backupBytes, 0, $backupBytes.Length)

    # 2) pull every later entry back by delta (forward copy; overlapping-safe)
    $moved = 0
    foreach ($item in $afterTarget) {
        Copy-FileRegion -Source $fs -Dest $fs `
            -SourceOffset ($hdr.PayloadBase + $item.Offset) `
            -DestOffset   ($hdr.PayloadBase + ($item.Offset - $delta)) `
            -Length       $item.Size
        $moved++
    }
    if ($needsRebuild) { Write-Host ("  shifted {0} trailing entries" -f $moved) }

    # 3) the file now ends at the new data end
    $newLength = $fileLength - $delta
    $fs.SetLength($newLength)

    # 4) header JSON edits, text-level, asserted byte-length-neutral
    $jsonText  = $hdr.JsonText
    $newOffset = Format-Int $entryOffset
    $newSize   = Format-Int $backupBytes.Length

    # 4a) offsets of the shifted entries
    foreach ($item in $afterTarget) {
        $oldTok = '"offset":"' + (Format-Int $item.Offset) + '"'
        $newTok = '"offset":"' + (Format-Int ($item.Offset - $delta)) + '"'
        if ($oldTok -eq $newTok) { continue }
        $count = ([regex]::Matches($jsonText, [regex]::Escape($oldTok))).Count
        if ($count -ne 1) {
            throw ("ambiguous offset token {0}: {1} occurrences; refusing to patch the header" -f $oldTok, $count)
        }
        $jsonText = $jsonText.Replace($oldTok, $newTok)
    }

    # 4b) the target entry's size (key order in this asar: "size":N,"offset":"..." )
    $oldSizeTok = '"size":' + (Format-Int $entrySize) + ',"offset":"' + $newOffset + '"'
    $newSizeTok = '"size":' + $newSize + ',"offset":"' + $newOffset + '"'
    if (-not $jsonText.Contains($oldSizeTok)) {
        throw ("could not locate the target entry's size/offset pair in the header text ({0}); " +
               "the JSON layout changed and a text-level edit is no longer safe" -f $oldSizeTok)
    }
    $count = ([regex]::Matches($jsonText, [regex]::Escape($oldSizeTok))).Count
    if ($count -ne 1) { throw ("ambiguous size token ({0} occurrences); refusing to patch the header" -f $count) }
    $jsonText = $jsonText.Replace($oldSizeTok, $newSizeTok)

    # 4c) the target entry's integrity hash
    $oldHash = [string]$entry.integrity.hash
    if ($oldHash -ne '') {
        $count = ([regex]::Matches($jsonText, [regex]::Escape($oldHash))).Count
        if ($count -ne 1) {
            throw ("integrity hash {0} appears {1} times in the header; refusing to patch it" -f $oldHash, $count)
        }
        $jsonText = $jsonText.Replace($oldHash, $backupHash)
    } else {
        Write-Host 'note: the entry has no integrity field; only size and offset were patched.' -ForegroundColor DarkGray
    }

    $newJsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonText)
    if ($newJsonBytes.Length -ne $hdr.JsonSize) {
        throw ("header edit changed the JSON length ({0} -> {1}); aborting before writing the header. " +
               "The data area has already been rewritten, so re-run tmp\write_back_asar.mjs apply to recover." -f $hdr.JsonSize, $newJsonBytes.Length)
    }
    $fs.Seek(16, [System.IO.SeekOrigin]::Begin) | Out-Null
    $fs.Write($newJsonBytes, 0, $newJsonBytes.Length)
    $fs.Flush()
} finally {
    $fs.Dispose()
}

# --- verify ---------------------------------------------------------------
$after      = Read-AsarHeader -Path $AsarPath
$entryAfter = Find-AsarEntry -Header $after.Json -Segments $EntrySegments
$verifyBytes = New-Object byte[] ([long]$entryAfter.size)
$vs = [System.IO.File]::Open($AsarPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
try {
    $vs.Seek($after.PayloadBase + [long]$entryAfter.offset, [System.IO.SeekOrigin]::Begin) | Out-Null
    $got = $vs.Read($verifyBytes, 0, $verifyBytes.Length)
    if ($got -ne $verifyBytes.Length) { throw "short read while verifying ($got of $($verifyBytes.Length) bytes)" }
} finally { $vs.Dispose() }
$verifyHash  = Get-Sha256Hex -Bytes $verifyBytes
$finalLength = (Get-Item -LiteralPath $AsarPath).Length

Write-Host ''
Write-Host '--- AFTER ---'
Write-Host ("file length      : {0}" -f $finalLength)
Write-Host ("headerSize       : {0}   jsonSize: {1}   payload base: {2}" -f $after.HeaderSize, $after.JsonSize, $after.PayloadBase)
Write-Host ("entry offset     : {0}" -f $entryAfter.offset)
Write-Host ("entry size       : {0}" -f $entryAfter.size)
Write-Host ("entry sha256     : {0}" -f $verifyHash)
Write-Host ("header integrity : {0}" -f $entryAfter.integrity.hash)

if ($verifyHash -ne $backupHash) { throw "VERIFY FAILED: entry hash $verifyHash != backup hash $backupHash" }
if ([long]$entryAfter.size -ne $backupBytes.Length) { throw "VERIFY FAILED: entry size $($entryAfter.size) != backup size $($backupBytes.Length)" }
if ([long]$entryAfter.offset -ne $entryOffset) { throw "VERIFY FAILED: the entry offset moved ($entryOffset -> $($entryAfter.offset))" }
if ($null -ne $entryAfter.integrity.hash -and [string]$entryAfter.integrity.hash -ne $backupHash) { throw 'VERIFY FAILED: the integrity hash was not updated' }
if ($needsRebuild -and $finalLength -ne ($fileLength - $delta)) { throw "VERIFY FAILED: file length $finalLength != expected $($fileLength - $delta)" }

Write-Host ''
Write-Host 'RESTORE OK - the official client.js is back in place.' -ForegroundColor Green
Write-Host 'Next steps:'
Write-Host '  1. fully restart the desktop client (a page reload does not reload host-side code).'
Write-Host '  2. the active/silent workspace sections and the moon/sun buttons must be gone.'
Write-Host '  3. record the rollback in the work log.'
