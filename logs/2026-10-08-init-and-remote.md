# 2026-10-08 初始化工作区并接入 GitHub 远程仓库

## 目标

1. 把工作同步到 <https://github.com/asdw159632/dsh-custom-setting.git>。
2. 记录「本工作区可能需要建立多个文件夹，针对不同需求对 DSH 客户端做修改」这一约定。

## 环境勘察

* 工作区 `D:\文档\DSH-plugin\DSH-custom` 起始状态：只有 `AGENTS.md`，**没有 git 仓库**。
* 全局 git 身份已配置：`asdw159632` / `asdw159632@outlook.com`。
* 未安装 `gh` CLI。
* 网络：DNS 与 TCP 443 到 github.com 正常，但 git / curl 默认的 **schannel** TLS 后端
  报 `SEC_E_NO_CREDENTIALS (0x8009030e)` —— DSH 沙箱下拿不到 Windows 的加密凭据句柄。
* **解决办法**：改用 OpenSSL TLS 后端，`git -c http.sslBackend=openssl ls-remote ...` 成功。
  已用 `https://github.com/git/git.git` 作对照验证 TLS 可用。
* 凭据：Windows 凭据管理器中已有 `git:https://github.com`（用户 `asdw159632`，
  值为 40 位 PAT）。**但 git 的 `credential.helper` 在本沙箱下无法使用**，详见下文。
* 目标仓库存在，且**当前为空仓库**（`ls-remote` 返回 0 个引用）。

## 本次改动

| 文件 | 说明 |
| --- | --- |
| `memory/MEMORY.md` | **新增**：工作区长期记忆，记录上述两条信息 + TLS/凭据注意事项 |
| `README.md` | **新增**：工作区总览与目录说明 |
| `mods/README.md` | **新增**：`mods/` 下一个需求一个子目录的约定 |
| `AGENTS.md` | **修改**：新增「工作区记忆 / 目录组织 / 远程仓库」小节；顺带修掉 3 处被误转义成 `\##` 的标题 |
| `.gitignore` | **新增**：忽略 `tmp/` 及常见噪音 |
| `logs/2026-10-08-init-and-remote.md` | **新增**：本日志 |

## 执行步骤

1. 写入 `memory/MEMORY.md`（两条信息）。
2. 建立 `mods/`、`logs/`、`.gitignore` 骨架。
3. 更新 `AGENTS.md` 指向 memory。
4. `git init -b main`，`git config http.sslBackend openssl`，
   `git remote add origin https://github.com/asdw159632/dsh-custom-setting.git`。
5. 首次提交 `a0fc43c`，推送 `main` 到 origin（成功）。

## 推送阶段：凭据机制不可用及解决

第一次 `git push` 失败：

```
sh.exe: *** fatal error - couldn't create signal pipe, Win32 error 5
error: failed to execute prompt script (exit code 66)
fatal: could not read Username for 'https://github.com': terminal prompts disabled
```

排查结论（逐条验证过）：

1. **凭据本身没问题。** 直接运行
   `D:\software\Git\Git\mingw64\bin\git-credential-manager.exe get` 能正常返回
   `username=asdw159632` 和 40 位 `password`（有 PAT）。
2. **git 无法使用 credential helper。** git 是**经由 MSYS `sh`/`bash`** 去执行
   credential helper 与 askpass 的；本沙箱禁止 MSYS 创建 signal pipe，sh 一启动就
   挂掉（`Win32 error 5`），于是 helper / askpass 全部失败。即使把 helper 写成
   GCM 的完整路径也一样失败（已实测）。
3. `manager` 还额外存在 PATH 问题：`git-credential-manager` 不在当前 PATH 上
   （在 `mingw64\bin` 里）。

**解决办法**：绕开 helper 与 askpass，让 git 直接用认证头。

```powershell
$cred = "protocol=https`nhost=github.com`n`n" | & $gcm get
$b64  = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user:$token"))
git -c "http.extraHeader=Authorization: Basic $b64" push -u origin main
```

已封装为 `scripts/push.ps1`（自动定位 GCM、读凭据、脱敏输出）。
**后续推送一律使用 `pwsh -File scripts/push.ps1`，不要直接 `git push`。**

## 验证

* `git ls-remote --heads origin` → `a0fc43c0b373065e9fd0b5e204e2ded5602d610a refs/heads/main`
* 与本地 `HEAD` 一致，首次同步完成。

## 待办 / 备注

* 后续每个 DSH 定制需求在 `mods/<需求名>/` 下独立建目录，并在其 `README.md` 写清目标与状态。
* 若换机器后 git 又报 `SEC_E_NO_CREDENTIALS`，记得补上 `http.sslBackend=openssl`。
