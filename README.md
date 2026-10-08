# DSH-custom

针对 **DSH（DeepSeek Harness）客户端**的定制修改工作区。

不同的定制需求各自放在 `mods/` 下的独立文件夹中。

## 目录

| 路径 | 用途 |
| --- | --- |
| `memory/MEMORY.md` | **长期记忆**：远程同步目标、目录约定等，开工前先读 |
| `mods/<需求名>/` | 每个 DSH 定制需求一个目录 |
| `logs/` | 阶段性工作日志 |
| `tmp/` | 临时脚本（不提交） |
| `AGENTS.md` | 工作区约定（给 AI agent 的指令） |

## 远程仓库

本工作区同步到：<https://github.com/asdw159632/dsh-custom-setting.git>

```powershell
git add -A
git commit -m "说明"
git push origin main
```

> 本机 git 需要 OpenSSL TLS 后端：`git config http.sslBackend openssl`
> （默认 schannel 在沙箱下报 `SEC_E_NO_CREDENTIALS`）。
