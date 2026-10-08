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

## 4. DSH 安装树与 profile（易踩坑，务必先读）

* 本机有**两套** DSH 安装，混淆会得出完全错误的兼容性结论：

  | 安装树 | 路径 | DSH SDK 版本 |
  | --- | --- | --- |
  | **桌面客户端自带（当前 GUI 用的就是它）** | `D:\software\DeepSeek Harness\resources\app.asar` 内 `/dsh/node_modules/` | **0.2.0-rc.2** |
  | 独立 CLI / `dsh web` | `D:\software\DeepseekHarness\node_modules\` | 0.1.0-rc.8 |

* `C:\Users\Zhang Liang\.dsh\profiles\node_modules\@deepseek-ai\*` 是 **junction**，
  指向 `D:\software\DeepseekHarness` 那套（0.1.0-rc.8），**不代表客户端宿主的版本**。
  （记录日期：2026-10-08）
* 客户端 app.asar 里的宿主版本，可用 `node` 读 asar header 遍历 files 树取
  `/dsh/node_modules/@deepseek-ai/dsh/package.json` 得到。
* 全局 `dsh` CLI（`C:\Users\Zhang Liang\AppData\Roaming\npm`）= 0.1.0-rc.8，
  与客户端宿主不同版本；**不要用它改 desktop profile**（其自带 pnpm 11.22.0
  会改写 profile 的 `pnpm-lock.yaml`，而 profile 由应用自带的 pnpm 11.7.0 管理）。
* profile 清单：
  * `desktop`（当前 GUI）：`~/.dsh/profiles/desktop`，bundles 含 dshmarket 等
  * `web`（另一个 `dsh web` 实例）：`~/.dsh/profiles/web`，装着 dsh-better-sidebar、
    `@linxin666/dsh-web-ui-all` 等
* 装插件一律走**客户端内的插件管理界面**（应用自带 pnpm 11.7.0 + 正确的 profile 协调）。
* `dsh plugin --profile <p> add <pkg>` 只是把参数**转发给 profile 目录里的 pnpm**，
  不会自己写 `dsh.profile.bundles`（靠插件包自带的 bundle patch 挂载）。

## 5. 客户端 app.asar 的结构（事故教训，动它之前必读）

* **路径会变**：客户端重装过，新路径是 `D:\software\DSH\resources\app.asar`（**121348951 字节**）；
  旧路径 `D:\software\DeepSeek Harness` 已不存在。脚本路径统一读 `tmp\paths.json`。
* 头部布局（**实测确认**，唯一自洽解）：
  * 字节 0..15：`u0=4`、`u4=3392056`、`u8=3392052`、`u12=3392048`
  * **JSON 从字节 16 开始**，长度 = `u12` = 3392048；`u4 = u12 + 8`、`u8 = u12 + 4`
  * **数据区起点 = 16 + u12 = 3392064**
  * 判定方法（可靠）：拿多个候选布局去试，**用「第一个数据条目能否解析成 JSON」当判据**
    （`tmp\asar-independent-check.mjs` 就是干这个的）
  * 条目 `offset` 是**字符串**，相对数据区起点；做算术前必须转数字
  * 每个条目带 `integrity {algorithm:SHA256, hash, blockSize:4194304, blocks[]}`；
    只对**内容改动过的条目**重算，其余保持原值
  * **1497 个条目 `unpacked:true`、没有 offset**（内容在 `app.asar.unpacked`），
    重排数据区时必须跳过，否则报 `RangeError: position NaN`
* 沙箱：默认拒写工作区外文件；asar 本身**未被进程锁**，可 `r+` 打开。
* **⚠️ 2026-10-08 事故**：为改侧栏工作区分组写回 asar 时，头部 JSON 用 NUL 补齐、
  而长度字段仍声明原长 → 读取方 `JSON.parse` 撞 NUL → 客户端重启起不来。
  三条教训：
  1. 改 asar 前**必须整份备份**（当时只备份了目标条目）；
  2. 自检**不能复用与写入相同的头部假设**，要用独立读取器；
  3. **原样保留原头部 16 字节**，只替换 JSON 内容（长度恰好 = 原 jsonSize，
     不足用**空格**补，**绝不用 NUL**）。
* 正确写回器：`tmp\write_back_asar.mjs`（apply 前整份备份；原样保留头部；只重算目标条目
  integrity；写后做独立语义核对）。体检：`tmp\asar-independent-check.mjs`。
  事故全过程见 `mods\active-workspaces\EMERGENCY-RESTORE.md` 与 `PATCH-STATUS.md`。

---

## 变更记录

| 日期 | 内容 |
| --- | --- |
| 2026-10-08 | 建立本文件；记录远程同步目标与多文件夹组织约定。 |
| 2026-10-08 | 修正凭据记录：`credential.helper` 在沙箱下不可用，推送改用 `scripts/push.ps1`（`http.extraHeader`）。 |
| 2026-10-08 | 补充：本机无 `pwsh`，改用 `scripts\push.cmd`；`.ps1` 必须存为 UTF-8 with BOM。 |
| 2026-10-08 | 新增 §4「DSH 安装树与 profile」：桌面客户端宿主是 0.2.0-rc.2（在 app.asar 内），`profiles\node_modules` 的 junction 指向另一套 0.1.0-rc.8，勿混淆；装插件必须走客户端插件管理界面。 |
| 2026-10-08 | 需求 `mods/active-workspaces/`：侧栏工作区分活跃/沉默分组，需求已确认（REQUIREMENTS.md）、生态对比已做（COMPARISON.md）、dsh-web 安装前置已完成（INSTALL-DSH-WEB.md）。 |
| 2026-10-08 | **事故**：补丁写回 asar 时头部 JSON 长度/NUL 填充错误，客户端 app.asar 被写坏（121348951 → 121353555）；当次会话命令通道随后全面失效，未能修复。新增 §5 记录 asar 结构与教训，恢复脚本 `tmp\fix-asar-header.mjs`。 |
| 2026-10-08 | 该会话 pwsh/grep/read 子进程通道故障：`subprocess-local: Windows Job runner exited with exit code 1 before proving its managed range empty`。若再次遇到，视为环境故障，不要反复重试同类命令。 |
| 2026-10-08 | 客户端重装到 `D:\software\DSH`（旧 `D:\software\DeepSeek Harness` 已删），asar 恢复为干净的 121348951 字节。**补丁已成功写回**：头部 16 字节与其余全部字节保持一致，仅目标条目 200124→204716（+4592）。工具路径改为读 `tmp\paths.json`。 |
