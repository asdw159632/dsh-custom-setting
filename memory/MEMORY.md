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
  2. `scripts\push.cmd` ← **不要直接用 `git push`**，原因见下面的「凭据」
* **TLS 注意事项（本机环境）**：
  * 在 DSH 沙箱环境下，git 默认的 `schannel` TLS 后端会报
    `schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS (0x8009030e)`。
  * 解决办法：使用 OpenSSL 后端。仓库本地已固化配置
    `git config http.sslBackend openssl`。
  * 若在别的克隆中遇到同样的 TLS 报错，改用
    `git -c http.sslBackend=openssl <命令>`。
* **凭据（重要，勿踩坑）**：
  * GitHub 凭据**确实存在**，存放在 Windows 凭据管理器
    （`cmdkey` 目标 `git:https://github.com`，用户 `asdw159632`，
    值为一个 40 位 PAT）。
  * **但在 DSH 沙箱下 `credential.helper` 完全不可用。** 原因：git 是**通过
    MSYS `sh`/`bash`** 去执行 credential helper 与 askpass 的，而沙箱禁止
    MSYS 创建 signal pipe，于是必然报：
    ```
    sh.exe: *** fatal error - couldn't create signal pipe, Win32 error 5
    error: failed to execute prompt script (exit code 66)
    fatal: could not read Username for 'https://github.com'
    ```
    系统级 `credential.helper=manager` 也因此失效（`manager` 还不一定在 PATH 上）。
  * **可行做法：绕开 helper，用 `http.extraHeader` 直接携带 Basic 认证头。**
    已封装为脚本，推送一律走它：

    ```powershell
    scripts\push.cmd
    ```

    脚本内部：`git-credential-manager get` 取到 PAT（直接调用可正常工作，
    只有经过 git 的 helper 机制才会挂）→ 拼 `Authorization: Basic <base64(user:pat)>`
    → `git -c http.extraHeader=... push`。
  * 本机**只有 Windows PowerShell 5.1（无 `pwsh`）**，且 `.ps1` 需
    `-ExecutionPolicy Bypass`，所以用 `push.cmd` 包装调用：
    `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\push.ps1`。
  * `scripts\push.ps1` **必须保存为 UTF-8 with BOM**：PS 5.1 对无 BOM 的
    `.ps1` 按系统 ANSI 代码页（本机 GBK）解析，中文注释会导致语法错误。
  * 手工应急写法（token 从别处取）：
    ```powershell
    git -c "http.extraHeader=Authorization: Basic <base64(user:token)>" push origin main
    ```
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
  ├── scripts/push.cmd     # 推送脚本（沙箱下唯一可行的推送方式）
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
| 2026-10-08 | 修正凭据记录：`credential.helper` 在沙箱下不可用，推送改用 `scripts/push.ps1`（`http.extraHeader`）。 |
| 2026-10-08 | 补充：本机无 `pwsh`，改用 `scripts\push.cmd`；`.ps1` 必须存为 UTF-8 with BOM。 |
