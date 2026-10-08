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
* 凭据：Windows 凭据管理器中已有 `git:https://github.com`（用户 `asdw159632`），
  系统级 `credential.helper=manager` 会自动取用。
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
5. 首次提交并 `git push -u origin main`。

## 待办 / 备注

* 后续每个 DSH 定制需求在 `mods/<需求名>/` 下独立建目录，并在其 `README.md` 写清目标与状态。
* 若换机器后 git 又报 `SEC_E_NO_CREDENTIALS`，记得补上 `http.sslBackend=openssl`。
