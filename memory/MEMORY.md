# 工作区记忆（Memory）

> 本文件记录本工作区长期有效的事实与约定。**每个新会话开始工作前先读本文件。**
> 新增记忆请追加到对应小节，并写明日期。

工作区路径：`D:\文档\DSH-plugin\DSH-custom`

---

## 1. 远程仓库同步目标

* **远程仓库（origin）**：https://github.com/asdw159632/dsh-custom-setting.git
  * 记录日期：2026-10-08
  * 该仓库是**本工作区所有工作的同步目标**。工作区的每一次阶段性提交都要推送到这里。
* **提交 / 推送约定**：完成阶段性工作后
  1. `git add -A && git commit -m "<说明>"`
  2. `git push origin main`
* **TLS 注意事项（本机环境）**：
  * 在 DSH 沙箱环境下，git 默认的 `schannel` TLS 后端会报
    `schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS (0x8009030e)`。
  * 解决办法：使用 OpenSSL 后端。仓库本地已固化配置
    `git config http.sslBackend openssl`。
  * 若在别的克隆中遇到同样的 TLS 报错，改用
    `git -c http.sslBackend=openssl <命令>`。
* **凭据**：GitHub 凭据已存放在 Windows 凭据管理器
  （`cmdkey` 目标 `git:https://github.com`，用户 `asdw159632`），
  通过系统级 `credential.helper=manager` 自动取用。
* 本工作区**不是**裸仓库 + 工作仓库的模式，而是直接以工作区本身作为仓库，
  远程指向上面的 GitHub 仓库。

## 2. 工作区目录组织约定

* 本工作区的用途：**针对不同需求，对 DSH 客户端做定制修改。**
* **不同需求使用不同文件夹**，一个需求一个独立目录，互不干扰：

  ```
  DSH-custom/
  ├── AGENTS.md            # 工作区约定（给 agent 的指令）
  ├── README.md            # 工作区总览
  ├── memory/MEMORY.md     # 本文件：长期记忆
  ├── mods/                # 各个 DSH 定制需求，一个需求一个子目录
  │   └── <需求名>/        # 内含该需求的源码、说明、状态
  ├── logs/                # 工作日志（每个阶段一篇）
  └── tmp/                 # 临时脚本，不提交
  ```

* 新增需求时的做法：
  1. 建立 `mods/<需求名>/`；
  2. 在其中放 `README.md`，写明：需求目标、涉及 DSH 的哪个部分、当前状态；
  3. 涉及的改动只放在该需求目录内，避免跨需求互相污染。
* 命名建议：需求目录用简短小写英文 + 连字符，例如 `mods/theme-dark/`、
  `mods/tool-panel/`。

## 3. 临时文件

* 临时脚本一律放工作区根目录的 `tmp/`，不要在系统 `/tmp` 中创建或执行。
* `tmp/` 已在 `.gitignore` 中忽略。

---

## 变更记录

| 日期 | 内容 |
| --- | --- |
| 2026-10-08 | 建立本文件；记录远程同步目标与多文件夹组织约定。 |
