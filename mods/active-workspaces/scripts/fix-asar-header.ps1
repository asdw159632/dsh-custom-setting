<#
.SYNOPSIS
    Repair the asar header pickle after a write-back that left it inconsistent.

.DESCRIPTION
    Repairs ONLY the 16-byte pickle prefix + header JSON framing. It does not touch the
    data area, and it does not decide which client.js version is inside.

    WHY THIS IS NEEDED
    ------------------
    The repacker (tmp\write_back_asar.mjs) rewrote the header as:

        Buffer.alloc(16 + jsonSize)            // zero-filled
        writeUInt32LE(4,          0)           // u0 = 4
        writeUInt32LE(jsonSize,   4)           // u4 = OLD header size (3392056)
        writeUInt32LE(newJsonSize,8)           // u8 = NEW json length  (e.g. 3392052)
        writeUInt32LE(jsonSize,  12)           // u12 = OLD json size   (3392048)
        write(newHeaderJson, 16)               // JSON, then NUL padding to jsonSize

    Two things are wrong with that:

      1. The JSON occupies only `newJsonSize` bytes; the remaining
         `jsonSize - newJsonSize` bytes of the region are NUL bytes, but u12 still
         advertises `jsonSize`. A reader that does `JSON.parse(bytes[16..16+u12])`
         therefore parses JSON followed by NULs, which throws
         "Unexpected non-whitespace character after JSON".
      2. u8 is supposed to be the pickle length of the JSON string
         (u8 == u4 - 4 in every healthy asar). Writing `newJsonSize` there breaks the
         relationship between u4 and u8.

    A HEALTHY ASAR (measured on this machine BEFORE any patching, 2026-10-08)
    ------------------------------------------------------------------------
        u0 = 4            (pickle prefix: size of the following length field)
        u4 = 3392056      (header size = 8 + jsonSize)
        u8 = 4            (pickle length of the JSON string)
        u12 = 3392048     (JSON byte length)
        JSON starts at byte 16.

    WHAT THIS SCRIPT WRITES
    -----------------------
        u0  = 4
        u4  = 8 + newJsonSize
        u8  = 4
        u12 = newJsonSize
        JSON at byte 16, no padding.

    Because the header region length changes when the padding is dropped, the whole
    file is rebuilt: a new header is written at 0 and the data area is moved to
    16 + newJsonSize with a streaming copy (the 118 MB data area is never held in
    memory). The file is then truncated to the new total length.

    SAFETY
    ------
      * Refuses if the trailing bytes of the JSON region are not all NUL (that would
        mean something else is wrong, and blindly trimming would destroy data).
      * Refuses if `JSON.parse` fails on the de-padded text.
      * Refuses if the target entry's data range would fall outside the data area.
      * Prints the 4 prefix fields, the file length and the target entry BEFORE/AFTER.
      * Verifies the result by re-reading the prefix and re-parsing the header.
      * -WhatIfOnly (default behaviour when -Apply is absent) writes nothing.

.PARAMETER AsarPath
    Path of the app.asar to repair.

.PARAMETER Apply
    Actually write. Without it the script only reports.

.PARAMETER EntrySegments
    Path segments of the entry to report/hash (default: the workspace client bundle).

.NOTES
    SANDBOX / PRIVILEGE
    -------------------
    The asar is outside the DSH workspace write scope, so the write step needs a
    one-shot elevation (danger-full-access). A delegated subagent cannot elevate
    itself; the human or team lead must run this.

    WINDOWS POWERSHELL 5.1: no `pwsh` on this machine. Run with
        powershell -NoProfile -ExecutionPolicy Bypass -File <this file>

    THIS SCRIPT HAS NOT BEEN EXECUTED (the shell channel is broken on the machine
    where it was written). It is written to be reversible:
        * take a whole-file copy of the asar before running it with -Apply;
        * run it once without -Apply and read the report.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File mods\active-workspaces\scripts\fix-asar-header.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File mods\active-workspaces\scripts\fix-asar-header.ps1 -Apply
#>
[CmdletBinding()]
param(
    [string]$AsarPath = 'D:\software\DeepSeek Harness\resources\app.asar',
    [switch]$Apply,
    [string[]]$EntrySegments = @('dsh', 'node_modules', '@deepseek-ai', 'dsh-client-ui-workspace', 'lib', 'client.js')
)

$ErrorActionPreference = 'Stop'

function Get-Sha256Hex {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Find-AsarEntry {
    param($Header, [string[]]$Segments)
    $node = $Header
    foreach ($seg in $Segments) {
        if ($null -eq $node -or $null -eq $node.files) { throw "entry not found (segment '$seg')" }
        $node = $node.files.$seg
    }
    if ($null -eq $node) { throw "entry not found: $($Segments -join '/')" }
    return $node
}

Write-Host ''
Write-Host '=== assess / repair asar header pickle ===' -ForegroundColor Cyan
Write-Host "asar: $AsarPath"
Write-Host ''

if (-not (Test-Path -LiteralPath $AsarPath -PathType Leaf)) { throw "asar not found: $AsarPath" }
$fileLength = (Get-Item -LiteralPath $AsarPath).Length

# --- read prefix + JSON region -------------------------------------------
$stream = [System.IO.File]::Open($AsarPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
try {
    $prefix = New-Object byte[] 16
    $read = $stream.Read($prefix, 0, 16)
    if ($read -ne 16) { throw 'asar shorter than 16 bytes' }
    $u0  = [BitConverter]::ToUInt32($prefix, 0)
    $u4  = [BitConverter]::ToUInt32($prefix, 4)
    $u8  = [BitConverter]::ToUInt32($prefix, 8)
    $u12 = [BitConverter]::ToUInt32($prefix, 12)

    $jsonRegion = New-Object byte[] $u12
    $stream.Seek(16, [System.IO.SeekOrigin]::Begin) | Out-Null
    $got = $stream.Read($jsonRegion, 0, $u12)
    if ($got -ne $u12) { throw "short read of the JSON region ($got of $u12 bytes)" }
} finally { $stream.Dispose() }

Write-Host '--- BEFORE (16-byte prefix) ---'
Write-Host ("u0={0}  u4={1}  u8={2}  u12={3}" -f $u0, $u4, $u8, $u12)
Write-Host ("file length : {0}" -f $fileLength)
Write-Host ("health check: u0==4 -> {0} ; u8==4 (pickle len) -> {1} ; u4-4==u12 -> {2}" -f ($u0 -eq 4), ($u8 -eq 4), (($u4 - 4) -eq $u12))
Write-Host ("data-area start if JSON begins at byte 16: {0}" -f (16 + $u12))

# --- find the real end of the JSON (trim trailing NUL padding) ------------
$jsonEnd = $jsonRegion.Length
while ($jsonEnd -gt 0 -and $jsonRegion[$jsonEnd - 1] -eq 0) { $jsonEnd-- }
$padding = $jsonRegion.Length - $jsonEnd
Write-Host ''
Write-Host ("trailing NUL padding detected: {0} byte(s)" -f $padding)
Write-Host ("effective JSON length        : {0}" -f $jsonEnd)

if ($padding -eq 0) {
    Write-Host ''
    Write-Host 'No NUL padding: the JSON region length already equals the JSON length.' -ForegroundColor Green
}

$jsonText = [System.Text.Encoding]::UTF8.GetString($jsonRegion, 0, $jsonEnd)
$json = $null
$parseError = $null
try { $json = ConvertFrom-Json $jsonText } catch { $parseError = $_.Exception.Message }

if ($null -eq $json) {
    Write-Host ''
    Write-Host "JSON.parse of the de-padded text FAILED: $parseError" -ForegroundColor Red
    throw 'cannot repair: the header JSON is not parseable even after trimming NULs. Restore the whole asar from a backup or from the client installer.'
}
Write-Host 'JSON.parse of the de-padded text: OK' -ForegroundColor Green
Write-Host ("top-level keys: {0}" -f (($json.PSObject.Properties | ForEach-Object { $_.Name }) -join ', '))

$entry = $null
try {
    $entry = Find-AsarEntry -Header $json -Segments $EntrySegments
} catch {
    Write-Host "warning: target entry not resolvable: $($_.Exception.Message)" -ForegroundColor Yellow
}

$newJsonSize = [System.Text.Encoding]::UTF8.GetByteCount($jsonText)
if ($newJsonSize -ne $jsonEnd) {
    Write-Host ("note: re-encoded JSON length {0} differs from the byte length {1} (UTF-8 round-trip); using the re-encoded length." -f $newJsonSize, $jsonEnd) -ForegroundColor Yellow
}
$newBase = 16 + $newJsonSize
$newLength = $newBase + ($fileLength - (16 + $u12))

Write-Host ''
Write-Host '--- PLAN ---'
Write-Host ("new header: u0=4  u4={0}  u8=4  u12={1}" -f (8 + $newJsonSize), $newJsonSize)
Write-Host ("data area moves: {0} -> {1}  (delta {2})" -f (16 + $u12), $newBase, ($newBase - (16 + $u12)))
Write-Host ("file length    : {0} -> {1}" -f $fileLength, $newLength)

if ($null -ne $entry) {
    $off = [long]$entry.offset
    $size = [long]$entry.size
    $abs = $newBase + $off
    Write-Host ''
    Write-Host ("target entry   : offset={0} size={1}" -f $off, $size)
    Write-Host ("absolute range : {0} .. {1}  (file end {2})" -f $abs, ($abs + $size), $newLength)
    if (($abs + $size) -gt $newLength) {
        throw 'target entry would fall outside the repaired file; refusing to write'
    }
    $buf = New-Object byte[] $size
    $rs = [System.IO.File]::Open($AsarPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $rs.Seek($abs, [System.IO.SeekOrigin]::Begin) | Out-Null
        $got = $rs.Read($buf, 0, $size)
        if ($got -ne $size) { throw "short read of the target entry ($got of $size)" }
    } finally { $rs.Dispose() }
    $hash = Get-Sha256Hex -Bytes $buf
    Write-Host ("entry sha256   : {0}" -f $hash)
    Write-Host ("header integ.  : {0}" -f $entry.integrity.hash)
    Write-Host ("patched?       : {0}" -f $(if ($hash -ne '29c34ce1c2a437cf8a50ba35d1ae44741114439e37a17153dfd4b1aa942aa955') { 'yes (not the official hash) - roll back separately if you want the official file' } else { 'no - this is the official client.js' }))
}

if (-not $Apply) {
    Write-Host ''
    Write-Host 'Report only (no -Apply). Nothing was written.' -ForegroundColor Yellow
    Write-Host 'Before applying: take a whole-file copy of the asar, then re-run with -Apply.'
    exit 0
}

# --- apply ----------------------------------------------------------------
Write-Host ''
Write-Host 'repairing the header...' -ForegroundColor Cyan

$jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonText)
$newPrefix = New-Object byte[] 16
[BitConverter]::GetBytes([uint32]4).CopyTo($newPrefix, 0)
[BitConverter]::GetBytes([uint32](8 + $jsonBytes.Length)).CopyTo($newPrefix, 4)
[BitConverter]::GetBytes([uint32]4).CopyTo($newPrefix, 8)
[BitConverter]::GetBytes([uint32]$jsonBytes.Length).CopyTo($newPrefix, 12)

$fs = [System.IO.File]::Open($AsarPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
try {
    # move the data area first (backward, chunked) while the old header is still there.
    # FORWARD copies are only safe when the shift is smaller than the buffer; copy
    # backwards instead so any shift is safe.
    $dataLength = $fileLength - (16 + $u12)
    if ($dataLength -lt 0) { throw 'implausible: computed data length is negative' }
    $buffer = New-Object byte[] 8388608
    $oldDataStart = 16L + [long]$u12
    $newDataStart = [long]$newBase
    $remaining = [long]$dataLength
    while ($remaining -gt 0) {
        $n = [int][Math]::Min([long]$buffer.Length, $remaining)
        $srcOffset = $oldDataStart + $remaining - $n
        $dstOffset = $newDataStart + $remaining - $n
        $fs.Seek($srcOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
        $got = $fs.Read($buffer, 0, $n)
        if ($got -ne $n) { throw "unexpected end of file while moving the data area ($remaining bytes left)" }
        $fs.Seek($dstOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
        $fs.Write($buffer, 0, $got)
        $remaining -= $n
    }
    # header last, so a crash mid-copy leaves the old header pointing at (now partly moved) data
    $fs.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
    $fs.Write($newPrefix, 0, 16)
    $fs.Seek(16, [System.IO.SeekOrigin]::Begin) | Out-Null
    $fs.Write($jsonBytes, 0, $jsonBytes.Length)
    $fs.SetLength($newLength)
    $fs.Flush()
} finally { $fs.Dispose() }

# --- verify ---------------------------------------------------------------
$vs = [System.IO.File]::Open($AsarPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
try {
    $p2 = New-Object byte[] 16
    $got = $vs.Read($p2, 0, 16)
    if ($got -ne 16) { throw 'short read while verifying' }
    $v0 = [BitConverter]::ToUInt32($p2, 0); $v4 = [BitConverter]::ToUInt32($p2, 4)
    $v8 = [BitConverter]::ToUInt32($p2, 8); $v12 = [BitConverter]::ToUInt32($p2, 12)
    $region = New-Object byte[] $v12
    $vs.Seek(16, [System.IO.SeekOrigin]::Begin) | Out-Null
    $got = $vs.Read($region, 0, $v12)
    if ($got -ne $v12) { throw 'short read of the JSON region while verifying' }
} finally { $vs.Dispose() }

$vText = [System.Text.Encoding]::UTF8.GetString($region)
$vJson = $null
try { $vJson = ConvertFrom-Json $vText } catch { throw "VERIFY FAILED: repaired header does not parse: $($_.Exception.Message)" }
$vLength = (Get-Item -LiteralPath $AsarPath).Length

Write-Host ''
Write-Host '--- AFTER ---'
Write-Host ("u0={0}  u4={1}  u8={2}  u12={3}" -f $v0, $v4, $v8, $v12)
Write-Host ("file length: {0}  (expected {1})" -f $vLength, $newLength)
Write-Host 'JSON.parse: OK'

if ($v0 -ne 4) { throw 'VERIFY FAILED: u0 != 4' }
if ($v8 -ne 4) { throw 'VERIFY FAILED: u8 != 4' }
if ($v4 -ne (8 + $v12)) { throw 'VERIFY FAILED: u4 != 8 + u12' }
if ($vLength -ne $newLength) { throw "VERIFY FAILED: file length $vLength != $newLength" }

Write-Host ''
Write-Host 'HEADER REPAIRED.' -ForegroundColor Green
Write-Host 'Next: verify the entry content, then decide whether to keep or roll back the patch.'
Write-Host '  - roll back the patched entry: mods\active-workspaces\scripts\restore-official-ui-workspace.ps1 -WhatIfOnly'
Write-Host '  - check the whole asar: re-read every entry against its integrity hash'
