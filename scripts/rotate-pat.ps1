#Requires -Version 5.1
<#
.SYNOPSIS
    轮换 GitHub PAT：校验新 token → 写入 Windows 凭据管理器（git-credential-manager）→ 实测 git 认证。

.DESCRIPTION
    本机 git 的凭据由 Windows 凭据管理器保存（GCM 目标 git:https://github.com，用户名 asdw159632），
    系统级 credential.helper=manager。本脚本不打印 token，也不把 token 写进任何文件：

      1. 隐藏输入新 PAT（Read-Host -AsSecureString），或 -TokenFile 提供临时文件（读完删除）；
      2. 用 api.github.com 校验 token：打印账号与 scopes（repo 权限检查）；
      3. 通过 `git-credential-manager store` 写入凭据管理器（覆盖旧值）；
      4. 用 `git-credential-manager get` 回读，比对 SHA256 前缀确认写入成功；
      5. 用新 token 实测 `git ls-remote`（自动走系统代理），确认能访问仓库；
      6. 提示到 GitHub 页面删除旧 token。

.PARAMETER CheckOnly
    只检查当前凭据管理器里的 token 是否有效（不输入、不写入）。

.PARAMETER TokenFile
    从文件读取新 token（读后即删）。不传则交互式隐藏输入。

.PARAMETER User
    GitHub 用户名，默认 asdw159632。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\rotate-pat.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\rotate-pat.ps1 -CheckOnly
#>
[CmdletBinding()]
param(
    [string]$User = 'asdw159632',
    [switch]$CheckOnly,
    [string]$TokenFile
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$env:GIT_TERMINAL_PROMPT = '0'

function Resolve-Gcm {
    $cmd = Get-Command git-credential-manager -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $git = (Get-Command git -ErrorAction SilentlyContinue).Source
    if ($git) {
        $candidate = Join-Path (Split-Path (Split-Path $git -Parent) -Parent) 'mingw64\bin\git-credential-manager.exe'
        if (Test-Path $candidate) { return $candidate }
    }
    throw '找不到 git-credential-manager.exe'
}

function Get-GitProxy {
    if ($env:DSH_GIT_PROXY) { return $env:DSH_GIT_PROXY }
    if ($env:HTTPS_PROXY)   { return $env:HTTPS_PROXY }
    if ($env:https_proxy)   { return $env:https_proxy }
    try {
        $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ($ie.ProxyEnable -eq 1 -and $ie.ProxyServer) {
            $server = "$($ie.ProxyServer)".Split(';')[0]
            if ($server -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') { return $server }
            return "http://$server"
        }
    } catch { }
    return $null
}

function Read-StoredToken {
    param([string]$Gcm)
    $out = ("protocol=https`nhost=github.com`n`n" | & $Gcm get 2>$null)
    return (($out | Where-Object { $_ -like 'password=*' }) -replace '^password=', '')
}

function Show-Token([string]$Token) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Token)))
    return ('len={0} sha256={1}…' -f $Token.Length, $hash.Replace('-', '').Substring(0, 12))
}

function Test-GitHubToken {
    param([string]$Token)
    $proxy = Get-GitProxy
    $headers = @{ Authorization = "Bearer $Token"; 'User-Agent' = 'dsh-pat-rotate'; Accept = 'application/vnd.github+json' }
    $req = @{ Uri = 'https://api.github.com/user'; Headers = $headers; UseBasicParsing = $true; TimeoutSec = 30 }
    if ($proxy) { $req.Proxy = $proxy }
    $r = Invoke-WebRequest @req
    $scopes = $r.Headers['X-OAuth-Scopes']
    $me = $r.Content | ConvertFrom-Json
    return [pscustomobject]@{
        Login  = $me.login
        Scopes = if ($scopes) { ($scopes -join ' ') } else { '(fine-grained token / 无 scopes 头)' }
        Proxy  = $proxy
    }
}

$gcm = Resolve-Gcm
Write-Host "GCM: $gcm"
$startProxy = Get-GitProxy
Write-Host ("代理: " + $(if ($startProxy) { $startProxy } else { '(直连)' }))

if ($CheckOnly) {
    $token = Read-StoredToken -Gcm $gcm
    if (-not $token) { throw '凭据管理器里没有 github.com 的 token' }
    Write-Host "当前存储的 token：$(Show-Token $token)"
    $info = Test-GitHubToken -Token $token
    Write-Host "账号: $($info.Login)"
    Write-Host "scopes: $($info.Scopes)"
    Write-Host '当前 token 有效 ✓（如需轮换，去掉 -CheckOnly 重新运行）'
    exit 0
}

# ---- 1) 取新 token ----
$newToken = $null
if ($TokenFile) {
    if (-not (Test-Path -LiteralPath $TokenFile)) { throw "TokenFile 不存在：$TokenFile" }
    $newToken = ([IO.File]::ReadAllText($TokenFile)).Trim()
    Remove-Item -LiteralPath $TokenFile -Force
}
if (-not $newToken) {
    Write-Host '请粘贴新的 GitHub PAT（输入不会回显），回车确认：'
    $secure = Read-Host -AsSecureString
    if (-not $secure) { throw '没有输入 token' }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $newToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
if (-not $newToken) { throw '没有输入 token' }
if ($newToken -notmatch '^(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})$') {
    Write-Warning '输入不像 classic PAT（ghp_…）或 fine-grained PAT（github_pat_…），仍继续尝试。'
}

# ---- 2) 校验新 token ----
Write-Host '校验新 token …'
$info = Test-GitHubToken -Token $newToken
Write-Host "  账号: $($info.Login)"
Write-Host "  scopes: $($info.Scopes)"
if ($info.Scopes -notmatch 'repo' -and $info.Scopes -notmatch 'fine-grained') {
    Write-Warning '该 token 似乎没有 repo 权限，push/建仓会失败。classic token 请至少勾选 repo。'
}

# ---- 3) 写入 Windows 凭据管理器 ----
Write-Host '写入 Windows 凭据管理器（覆盖旧值）…'
$storeInput = "protocol=https`nhost=github.com`nusername=$($info.Login)`npassword=$newToken`n`n"
$storeOut = $storeInput | & $gcm store 2>&1
if ($LASTEXITCODE -ne 0) { $storeOut | ForEach-Object { "  $_" }; throw "git-credential-manager store 失败 (exit=$LASTEXITCODE)" }

# ---- 4) 回读校验 ----
$readback = Read-StoredToken -Gcm $gcm
$same = [bool]($readback -and $readback -eq $newToken)
Write-Host "回读校验: 新 token $(Show-Token $newToken)"
Write-Host "回读校验: 存储值   $(if ($readback) { Show-Token $readback } else { '(空)' })"
Write-Host "一致: $same"
if (-not $same) { throw '回读的 token 与新 token 不一致，写入可能被别的凭据源覆盖（检查 credential.helper 配置）' }

# ---- 5) 实测 git 认证 ----
$basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($info.Login):$newToken"))
$proxy = Get-GitProxy
$gitArgs = @('-c', 'http.sslBackend=openssl')
if ($proxy) { $gitArgs += @('-c', "http.proxy=$proxy") }
$gitArgs += @('-c', "http.extraHeader=Authorization: Basic $basic", 'ls-remote', 'https://github.com/asdw159632/dsh-custom-setting.git', 'refs/heads/main')
$lsr = & git @gitArgs 2>&1
$code = $LASTEXITCODE
($lsr | ForEach-Object { "$_".Replace($newToken, '<REDACTED>').Replace($basic, '<REDACTED>') }) | ForEach-Object { "  $_" }
if ($code -ne 0) { throw "新 token 的 git ls-remote 失败 (exit=$code)" }

Write-Host ''
Write-Host '新 token 已生效 ✓ 下一步：'
Write-Host '  1) 打开 https://github.com/settings/tokens ，删除旧 token（你怀疑泄露的那个）；'
Write-Host '  2) 运行 scripts\push.cmd 验证完整推送链路；'
Write-Host '  3) 本工作区若配置过 GITHUB_TOKEN 环境变量，也一并更新（当前未设置）。'
