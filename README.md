# DSH-custom

针对 **DSH（DeepSeek Harness）客户端**的定制修改工作区。

不同的定制需求各自放在 `mods/` 下的独立文件夹中。

## 目录

| 路径 | 用途 |
| --- | --- |
| `memory/MEMORY.md` | **长期记忆**：远程同步目标、目录约定等，开工前先读 |
| `mods/<需求名>/` | 每个 DSH 定制需求一个目录 |
| `logs/` | 阶段性工作日志 |
| `scripts/push.ps1` | 推送到 GitHub 的脚本（绕开沙箱下不可用的 credential helper） |
| `tmp/` | 临时脚本（不提交） |
| `AGENTS.md` | 工作区约定（给 AI agent 的指令） |

## 远程仓库

本工作区同步到：<https://github.com/asdw159632/dsh-custom-setting.git>

```powershell
git add -A
git commit -m "说明"
pwsh -File scripts/push.ps1      # 不要用 git push，会因凭据问题失败
```

> **为什么不用 `git push`**：本机 DSH 沙箱下 git 的 `credential.helper` / askpass 不可用
> —— git 通过 MSYS `sh` 执行 helper，而沙箱禁止 MSYS 创建 signal pipe，报
> `couldn't create signal pipe` → `failed to execute prompt script (exit code 66)`。
> `scripts/push.ps1` 直接从 Windows 凭据管理器取 PAT，改用
> `http.extraHeader: Authorization: Basic ...` 推送。
>
> 另外本机 git 需使用 OpenSSL TLS 后端（默认 schannel 报 `SEC_E_NO_CREDENTIALS`），
> 仓库本地已配置 `git config http.sslBackend openssl`。
