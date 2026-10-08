<#
.SYNOPSIS
    把本工作区的提交推送到 GitHub 远程仓库。

.DESCRIPTION
    在本机（DSH 沙箱）环境下，git 的 credential.helper / askpass 机制**不可用**：
    git 会通过 MSYS 的 sh/bash 去执行 helper，而沙箱禁止 MSYS 创建 signal pipe，
    必然报 "couldn't create signal pipe" → "failed to execute prompt script (exit code 66)"。

    本脚本绕开 helper：直接调用 git-credential-manager 从 Windows 凭据管理器读出
    PAT，然后用 http.extraHeader 携带 Basic 认证头完成 push。token 不会打印。

.PARAMETER Remote
    远程名，默认 origin。

.PARAMETER Branch
    分支名，默认 main。

.PARAMETER User
    GitHub 用户名，默认 asdw159632。

.PARAMETER SetUpstream
    是否带 -u 设置上游，默认 $true。

.EXAMPLE
    pwsh -File scripts/push.ps1
    pwsh -File scripts/push.ps1 -Branch main -Remote origin
#>
[CmdletBinding()]
param(
    [string]$Remote = 'origin',
    [string]$Branch = 'main',
    [string]$User   = 'asdw159632',
    [bool]  $SetUpstream = $true
)

$ErrorActionPreference = 'Stop'
$env:GIT_TERMINAL_PROMPT = '0'   # 不要在缺失凭据时挂起等输入

function Resolve-Gcm {
    <# 找到 git-credential-manager.exe：PATH 里没有，需要按 Git 安装位置推算 #>
    $cmd = Get-Command git-credential-manager -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $git = (Get-Command git -ErrorAction SilentlyContinue).Source
    if ($git) {
        $gitRoot = Split-Path (Split-Path $git -Parent) -Parent   # ...\Git\Git\cmd\git.exe -> ...\Git\Git
        $candidate = Join-Path $gitRoot 'mingw64\bin\git-credential-manager.exe'
        if (Test-Path $candidate) { return $candidate }
    }
    throw "找不到 git-credential-manager.exe，请手动指定 Git 安装目录。"
}

function Get-GitHubCredential {
    <# 从 Windows 凭据管理器取 GitHub 凭据。优先用环境变量 GITHUB_TOKEN #>
    if ($env:GITHUB_TOKEN) {
        return @{ User = $User; Token = $env:GITHUB_TOKEN }
    }

    $gcm = Resolve-Gcm
    $query = "protocol=https`nhost=github.com`n`n"
    $cred = $query | & $gcm get 2>$null

    $u = ($cred | Where-Object { $_ -like 'username=*' } | Select-Object -First 1) -replace '^username=', ''
    $t = ($cred | Where-Object { $_ -like 'password=*' } | Select-Object -First 1) -replace '^password=', ''

    if (-not $t) {
        throw "未能从凭据管理器取得 GitHub token。请先登录 git-credential-manager，或设置 `$env:GITHUB_TOKEN。"
    }
    if (-not $u) { $u = $User }
    return @{ User = $u; Token = $t }
}

$cred = Get-GitHubCredential
Write-Host "推送 $Branch -> $Remote （用户 $($cred.User)，token 长度 $($cred.Token.Length)）"

$basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($cred.User):$($cred.Token)"))

# http.sslBackend=openssl：本机 schannel 在沙箱下报 SEC_E_NO_CREDENTIALS
$gitArgs = @(
    '-c', 'http.sslBackend=openssl',
    '-c', "http.extraHeader=Authorization: Basic $basic",
    'push'
)
if ($SetUpstream) { $gitArgs += '-u' }
$gitArgs += @($Remote, $Branch)

# 注意：git push 的正常输出（"To <url>"、进度）是走 stderr 的。
# PowerShell 5.1 在 $ErrorActionPreference='Stop' 下会把原生命令的 stderr
# 当成终止性错误（NativeCommandError）抛出来，所以这里临时放宽，改按退出码判断。
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$out = & git @gitArgs 2>&1
$code = $LASTEXITCODE
$ErrorActionPreference = $prevEap

# 万一 git 把 URL/头部回显出来，做一次兜底脱敏
$out | ForEach-Object { "$_".Replace($cred.Token, '<REDACTED>').Replace($basic, '<REDACTED>') }

if ($code -ne 0) { throw "git push 失败，exit=$code" }
Write-Host "推送完成 ✓"
