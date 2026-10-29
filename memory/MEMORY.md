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

## 6. 右侧栏「编辑器」选型结论（重要，别再重复调研）

> 记录日期：2026-10-08。详见 `mods/sidebar-editor/README.md`。

* **当前 GUI = desktop profile**，装的是 `@linxin666/dsh-web-all@0.4.5` 那套；
  它对侧栏只做「加行 / 加席位 / 套皮肤」，**没有编辑能力**。
* **宿主自带官方右侧栏**（都是 0.2.0-rc.2）：
  `dsh-client-ui-sidebar-right` / `-sidebar-files`（文件树）/ `-sidebar-documentpreview`
  （Office/PDF/图片/表格/文本预览）/ `-sidebar-terminal` / `-sidebar-browser`。
* **官方预览是只读，且是设计**：`sidebar-documentpreview` 文档明写「预览而非编辑」；
  宿主 `dsh-api-workspace-files` 只有 `read`/`readBytes`/`stat`/`list`/`changes`，
  **没有写方法**（写入只在 host 侧 `ctx.fs`）。所以官方路线永远拿不到编辑器。
* **补编辑器的唯一现成方案：`dsh-better-sidebar@0.24.1`**（peer `^0.2.0-rc.1`，
  14 条 peer 对宿主全部满足）。它 v0.19.0 起接原生右侧栏、**接管内置「文件」页**，
  提供可编辑 CodeMirror（`Ctrl+S` / 脏标记 / mtime 冲突检测）。
  * **版本必须按宿主线选**：0.2.0-rc.x 宿主 → `0.24.1`；0.1.7 线 → `0.22.1`；
    0.1.2 线 → `0.18.x`（= web profile 里现存那个，**在 desktop 上会被启动预检整行禁用**）。
  * `@linxin666/dsh-client-ui-aionui-panel` 是 0.1.x 线（依赖 0.2 宿主没有的
    `dsh-client-runtime`），**不要**装到 desktop。
* **安装入口**：侧栏「**插件**」页 →「添加插件」（官方 `dsh-client-ui-plugin-manager` 的
  安装对话框，Host 自带 pnpm 11.7.0、失败自动还原 profile）。
  ⚠️ **设置 → 内置插件**是只读清单，装不了东西。
* 装完 **必须重启客户端**（该插件有 host 半区 `/sidebar/api/*` 路由）。
* ⚠️ 该插件 v0.23.0 起 fs 路由**取消了工作区包含检查**（可读写宿主用户能访问的任意路径）
  —— 已知安全取舍，知情后再装。
* **与 `dsh-web-all@0.4.5` 不冲突（2026-10-08 实测）**：家族无任何 better-sidebar 挂载行
  （无双挂载）；对右栏只做只读探测 `sidebarRightTabs.get('browser')` + `openTab`（无注册）；
  路由前缀不重叠（better-sidebar 占 `/sidebar/*`）。
  * 家族插件管理器里的 `bundle-guard`（注释点名 `duplicate prefix route "/sidebar/api"`）是给
    **web profile 的 `@linxin666/dsh-web-ui-all`** 写的——那一套才挂 better-sidebar，desktop 这套不挂。
  * 已知小缺口：`dsh-remote-web-ui` 的 `wsPaths` 白名单没有 better-sidebar 0.24.1 的
    `/sidebar/ws/fs-watch` → 仅**手机远程访问**时文件树目录自动刷新可能不工作，本地无影响。
  * 唯一真冲突：**同一插件装两遍**（两个通道）→ `duplicate loader entry id` / 重复路由。只装一次。
* **dshmarket「这是终端插件」提醒 = 文案启发式，不是兼容性判定**（2026-10-08 实测）：
  * 文案在 `dshmarket/src/client/locales.ts:135-138`（`terminalCautionTitle/Body/Startup/Link`：
    「可能不适用于网页版 / 这是终端插件，网页版里可能用不了。/ 也可能让 DeepSeek Harness 起不来。」），
    由安装确认弹窗 `MarketSection.tsx:7138` 在 `looksTerminal()` 为真时渲染。
  * `looksTerminal()`（`market-data.ts:382`）只对**插件名 + 市场描述**跑正则
    `tui|cli|tty|terminal|终端|命令行`；命中原因 = 目录源描述里有 "terminal"
    （指它侧栏那个**由 DSH 官方 ui-sidebar-terminal 提供**的 tab）。
  * 对 0.24.1 **不成立**：无 `node-pty`、无原生依赖、无构建脚本（0.18.0 才有 node-pty）；
    市场自己的兼容缓存（`.dsh-market\discovery-compatibility-v1.json`）也判 0.24.1 可用
    （`enginesDsh: null`，peers 全 `^0.2.0-rc.1`）。
  * 该提醒为真的场景 = 自带 xterm+node-pty 的终端插件（要构建脚本 + DSH 启动全有全无）。
  * 另注：dshmarket 有会话在跑时**拒绝安装**（`log.ndjson` 的 `install-blocked`）——被挡就走官方「插件」页。
* **可复用的只读工具**（`tmp/`，不进 git）：
  * `tmp\list-host-official-packages.mjs` → 列 asar 内官方包名与版本
  * `tmp\dump-asar.mjs <asar 内路径前缀>` → 把官方包源码/README 导出到 `tmp\asar-dump\`
  * 两者只读，不改 asar，可放心跑。

## 7. 极简模式（agent preset `minimal`）与 PowerShell（2026-10-14）

> 详见 `mods/agent-preset-minimal/README.md`、日志 `logs/2026-10-14-minimal-mode-powershell.md`。
> 结论一句话：**Windows 上极简模式唯一可用的工具就是 PowerShell 工具 `pwsh`。**

* preset 声明在 asar 内 `@deepseek-ai/dsh-web-app/presets/minimal.patch.yml`；当前 GUI（desktop profile）
  会加载它，因为 `~/.dsh/profiles/desktop/package.json` 的 bundles 含 `@deepseek-ai/dsh-web-app`，
  而该包 `dsh.bundle.patch` 把 `presets/{standard,ptc,minimal,cordis}.patch.yml` 全部注册（默认 `standard`）。
* 4 个内置 preset 的 id/文案：`standard` 标准模式、`ptc` PTC 模式、`minimal` 极简模式、`cordis` 创造模式
  （字典在 `@deepseek-ai/dsh-client-ui-agent-preset`）。
* 极简模式组成 = `persona`（固定提示词、无 runtime context）+ `persistent-shell` 组
  （pty + terminal-bash/persistent-bash〔win32 禁用〕+ terminal-bash(pwsh)/persistent-pwsh〔非 win32 禁用〕）。
  → Windows 下模型可见工具只有 `pwsh`（`@deepseek-ai/dsh-tool-pwsh-persistent`，ConPTY 持久 shell，300 s/命令）。
* 可执行文件解析（`@deepseek-ai/dsh-pwsh-local` 的 `resolvePwshPath`）：PS7（`%ProgramFiles%\PowerShell\7\pwsh.exe`）
  → PATH 里的 `pwsh.exe` → Windows PowerShell 5.1。**本机无 PS7、PATH 无 pwsh → 实际跑的是 PS 5.1（5.1.26100.9549）**，
  工具名却仍叫 `pwsh`；本会话自己的 `pwsh` 工具同理。
* 沙箱：`dsh-terminal-bash` 的 `spawnArgv()` 在非 `danger-full-access` 时用 `ctx.sandbox.confine()` 包裹
  shell 启动 argv → workspace-write 下极简模式 PowerShell 同样受限；read-only 下可能以 ConstrainedLanguage
  启动（编码固定/prompt 标记可能被拒，非 ASCII 输出可能跟随宿主代码页）。
* 极简模式**不含**：AGENTS.md 指令、Skills、todo/planning、上下文压缩、subagent/workflow、文件读写工具、web 工具。
* 新增只读 asar 检索工具（`tmp/`，不入库）：`scan-strings.mjs`（原文搜中文/英文串）、
  `find-entry.mjs <关键词> [路径子串]`（按内容定位条目）、`list-entries.mjs <路径子串>`（只列路径）。

## 8. 能不能「切到 WSL 环境」操作（2026-10-14）

> 详见 `mods/wsl-execution/README.md`、日志 `logs/2026-10-14-wsl-execution.md`。
> 一句话：**没有一键切换开关；沙箱会话里 `wsl.exe` 被拒（E_ACCESSDENIED），完全访问会话里可用。**

* **实测 A/B（同机同命令，只改会话权限）**：
  * `workspace-write`：`wsl.exe -l -q` → `Wsl/E_ACCESSDENIED`，exit -1；切回沙箱后复测仍是拒绝。
  * `danger-full-access`：`wsl.exe -l -q` 成功（Ubuntu-22.04 默认 / Ubuntu-18.04）；
    `wsl.exe --cd 'D:\文档\DSH-plugin\DSH-custom' -- bash -lc 'uname -a; pwd; ls -1'` 成功，
    `pwd` = `/mnt/d/文档/DSH-plugin/DSH-custom`。
  * ⇒ 挡住 WSL 的是 DSH 沙箱，不是 WSL 本身。
* **机制**：Windows 沙箱 = `dsh-sandbox-windows-acl`（`WRITE_RESTRICTED` 受限令牌 + Low 完整性 + ACL）；
  `dsh-pwsh-sandbox` 与 `dsh-terminal-bash.spawnArgv()` 在非 `danger-full-access` 时用
  `ctx.sandbox.confine(argv, policy)` 包裹启动 argv，子进程继承受限令牌。Windows 上 `ctx.shell` 固定是
  `pwsh-sandbox`；preset 只能选工具，换不了执行世界/沙箱栈（都在 host 平面）。
* **工作区映射**：`D:\文档\DSH-plugin\DSH-custom` ⇄ `/mnt/d/文档/DSH-plugin/DSH-custom`。
* **本机 WSL**：注册表 `HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss` 有
  Ubuntu-22.04（默认，BasePath `\\?\W:\Ubuntu-22.04`）与 Ubuntu-18.04（`D:\Ubuntu-18.04`）；
  `C:\Windows\System32\bash.exe` 是 WSL shim，PATH 上的 `bash` 就是它。
* **四条可行路线**：A 切「完全访问」+ pwsh 里调 `wsl.exe`（已验证，代价=无沙箱）；
  B 自定义工具走 `ctx.subprocess.spawn(['wsl.exe', ...])`（不经 confine，workspace-write 也能用，
  模板 `~/.dsh/.agent-presets/anchored-standard/custom-bash.mjs`，代价=绕过文件沙箱）；
  C `dsh-terminal-bash` 的 `shellPath: wsl.exe`（仍被 confine，只有完全访问可行；env/就绪标记未验证）；
  D 启用 `@linxin666/dsh-ssh`（`web-ui-ssh` 行默认 disabled，可在插件管理器启用）→ 6 个 `ssh_*` 工具
  由 Host 直连，WSL 里跑 sshd 即可当 Linux 远主机用。
* **侧栏终端**：`~/.dsh/profiles/desktop/cordis.patch.yml` 已把默认 shell 设成 `wsl.exe`；该通道由
  `dsh-api-terminal-controller` 经 subprocess provider 启动，sandbox policy 只用于给无 cwd 的会话定默认目录
  → 不受 shell 沙箱约束（按文档；人交互通道，Agent 不驱动）。
* **安全边界**：命令一旦进 WSL，DSH 的 Windows 文件沙箱就不再是边界（WSL 侧经 9p 访问 /mnt/d）。

---

## 9. PowerShell 里的 `dsh` 命令由谁接管（2026-10-14）

> 详见 `mods/dsh-command-desktop/README.md`、日志 `logs/2026-10-14-dsh-command-desktop.md`。
> 一句话：**本机 PowerShell 的 `dsh` = npm 全局 shim 指向旧 CLI 0.1.0-rc.8；
> 桌面端自带 0.2.0-rc.2 的 `dsh.cmd` 且有官方接管机制（PATH 首位 + 归属键），但从未安装过。**

* **`dsh` 指向哪儿**：`npm prefix` = `C:\Users\Zhang Liang\AppData\Roaming\npm`（用户 PATH 末位），
  `dsh.cmd` / `dsh.ps1` / `dsh` 三个 shim → `node_modules\@deepseek-ai\dsh`（**junction**）
  → `D:\software\DeepseekHarness\node_modules\@deepseek-ai\dsh` = **0.1.0-rc.8**。
  全机只有这一个 `dsh` 安装；无别名/函数。
* **桌面端自带的那套**：`D:\software\DSH\resources\runtime\cli\bin\dsh.cmd`（5 行）→
  `ELECTRON_RUN_AS_NODE=1 "<DSH>\DeepSeek Harness.exe" --expose-internals
  "<DSH>\resources\app.asar\dsh\node_modules\@deepseek-ai\dsh-desktop-host\lib\cli.js"`，
  实测 `--version` = **0.2.0-rc.2**（= GUI 宿主）。**Electron 可执行文件就是它的 Node 运行时**，
  不用另装 Node；另有 `<DSH>\resources\runtime\primary-runtime\dependencies\node\bin\node.exe`（24.x）。
* **官方接管机制（Windows 不是覆盖 shim）**：`runtime\cli\command-manager.js` + `command-path.ps1`：
  把 `runtime\cli\bin` **插到用户 PATH 首位**，归属记录写 `HKCU\Software\DeepSeekHarness\Command`
  （`Directory` / `PathWasAbsent` / `RetainedEntries`）→ 可"修复/移除"并原样恢复，**从不删别人的安装**。
  macOS 才是 `/usr/local/bin/dsh` 符号链接 + `.dsh-desktop-command.json` 收据。
* **本机现状 = 未安装**（2026-10-14 核对）：归属键不存在、`runtime\cli\bin` 不在 PATH。
* **入口在自绘标题栏**：win32 的 `Menu.setApplicationMenu` 只有不可见 devTools 项，托盘菜单只有
  「打开应用/退出」。真正的入口是 preload（`/lib/preload-app.cjs` `installWindowsMenu()`）
  注入的 40px 标题栏菜单，**「应用」按钮**（旁边是「编辑」）→ 弹出 `applicationItems()`：
  关于 / ── / 检查更新… / **管理 dsh 命令…（第 4 项）** / ── / 退出。
  **⚠️ 该入口只在 Electron 客户端主窗口（`dsh-app://app/`）里**：preload 的调用被包在
  `location.protocol === "dsh-app:" && hostname === "app"` 内 ⇒ **浏览器打开的 `dsh web` 页面
  （含 `DSH_WEB_URL`）没有 preload、没有这两个按钮**，在那里找不到是正常的。
  按钮位置：侧栏展开时在左上角折叠按钮右侧 48px，收起时移到「新建会话」之后 84px。
* **⚠️ desktop profile 被 Electron 独占**：`dsh --profile desktop` 报
  `error: profile "desktop" is managed exclusively by the Electron application`
  ⇒ 桌面端 `dsh` **不能 boot GUI 那个 profile**，只能带 `web` / `tui` / `headless` 等。
  且用 0.2.0-rc.2 boot 旧 `web` profile 会**跳过 3 个 0.1.x 线插件**
  （dshmarket@1.18.0 / dsh-chat-import@0.7.0 / dsh-better-sidebar@0.18.0）。
* **PowerShell 命令解析语义（实测，反直觉但很关键）**：按 PATH 顺序找**第一个含 `dsh` shim 的目录**，
  再在**该目录内**按 `.ps1` → PATHEXT 取命令 —— **目录优先级 > 扩展名优先级**。
  所以桌面端目录**只有 `dsh.cmd`、没有 `dsh.ps1`**，照样压过后面 npm 目录里的 `dsh.ps1`。
  实验脚本 `tmp\path-resolve-test.ps1`。
* **沙箱行为**：`workspace-write` 会话里**装不了**——写 HKCU 被 `UnauthorizedAccessException` 拒，
  `node command-manager.js inspect` 报 `{"ok":false,"code":"EPERM","message":"spawn EPERM"}`
  （沙箱禁 MSYS/子进程 signal pipe 同款限制）。⇒ 安装必须由用户点 GUI（GUI 子进程不受沙箱约束）。
* **`dsh --dump-config` 会写 `<profile>\cordis.yml`**（不是纯只读！），沙箱下报 EPERM。

## 10. 定制模式（agent preset `custom`）— Windows 桌面客户端（2026-10-15）

> 详见 `mods/agent-preset-custom/README.md`、日志 `logs/2026-10-15-agent-preset-custom-windows.md`。
> 一句话：**定制模式 = 极简模式（逐字复制）+ `@deepseek-ai/dsh-tool-fs` + `@deepseek-ai/dsh-tool-ask-user`。**

* 来源：用户先在 **WSL 侧工作区**（`/home/zhangliang/dsh-custom`）做了这个模式，本工作区按同样组成复刻。
  **两边 `custom.patch.yml` 与探针逐字节一致**（sha256 `E81590C3…AEFB`）；安装/校验脚本按平台分开：
  Linux 的 `install.sh`/`uninstall.sh`/`verify.sh` ↔ Windows 的 `install.ps1`/`uninstall.ps1`/`verify.ps1`
  （+ Windows 特有的 `tools/verify-real-profile.ps1`）。
* **同一份 patch，两个平台工具名不同**：Linux 极简 = `bash`（`dsh-tool-bash-persistent`）、
  Windows 极简 = `pwsh`（`dsh-tool-pwsh-persistent`），靠 `!!js process.platform === 'win32'` 切换。
  0.2.0-rc.2 实测：
  * 模板 profile（`verify.ps1`）：`minimal tools(1)=pwsh`；`custom tools(6)=ask_user_question, edit, pwsh, read, read_image, write`
  * 真实 desktop profile 副本：`minimal tools(18)`（pwsh + 第三方 task-board 的 17 个 `task_board_*`）、
    `custom tools(23)`（上述 + read/read_image/write/edit/ask_user_question）。那 17 个注册在 **profile 层**，
    所有模式都看得到，不是本模式引入的。
* **两条硬约束（别再试）**：① Linux 上极简自带的工具名就叫 `bash`，再挂 `@deepseek-ai/dsh-tool-bash`
  会同名冲突致**整个预设挂载失败**（`tool "bash" is already registered in this scope`）；
  ② `read_image` 只存在于 `@deepseek-ai/dsh-tool-fs`，该包无条件注册 read/read_image/write/edit，没有开关 ⇒ 只能整组加。
* 落地：`~\.dsh\profiles\desktop\cordis.patch.yml` 里由 `install.ps1` 写入托管块
  （标记 `# >>> agent-preset-custom (定制模式) managed block >>>` … `<<<`，与 Linux 版同标记），
  幂等、先整份备份 `.bak-<时间戳>`。本次实装 3267 B `710E84A5…321E` → 8406 B `F898226A…D11B`，
  原 92 行逐字保留，profile 内其它文件哈希未变。
* 运行中的宿主**已加载**：`cordis_inspect_query`（host `Config`/`listConfigs`，
  `name=@deepseek-ai/dsh-agent-preset`）安装前 4 行、安装后 **5 行**（多出 `include:preset-custom`）
  ⇒ 桌面客户端**热加载** profile 补丁，不必以「重启后才有」为前提。
* **校验方式（Windows，可复用）**：
  * `verify.ps1`：临时 `DSH_HOME`（`--from-default-profile web`）→ 装托管块 + 探针行 → `--dump-config`
    → `Start-Process` 起临时实例读 `[probe]` 行 → `Stop-Process`；产物在 `tmp/agent-preset-custom-verify/`。
  * `tools/verify-real-profile.ps1`：复制真实 profile（`node_modules` 走 junction，profile 名改 `realverify`
    以绕过 Electron 独占）起临时实例；产物在 `tmp/real-verify/`。
  * 两条都**退出码 0、`agent preset` 告警为空**。`verify.ps1` 不需要提权（只写 `tmp/`）。
* Windows 侧注意：`.ps1` 必须 **UTF-8 with BOM** 且用 `-ExecutionPolicy Bypass -File` 起；
  profile 在工作区外，`workspace-write` 会话里安装需一次提权；`Get-CimInstance` 在沙箱里被拒，查进程用 `Get-Process`。
* ⚠️ **并发会话教训**：本模式的文件曾被同工作区另一会话（`mods/dsh-command-desktop`）的仓库级 `git add`
  卷进它的提交 `4ed60e8`（内容无损，blob 一致）。多会话并行时**提交前先 `git status -uall`，按路径 add，不要 `-A`**。

## 11. 系统提示词装配与「极简 vs 标准」实测差异（2026-10-29）

> 详见 `logs/2026-10-29-preset-prompt-compare.md`、探针 `tmp/prompt-compare/probe-system-prompt.mjs`。
> 一句话：**极简模式用 persona `complete: true` 把整份系统提示词压成一句话（46 字符）+
> 3 个工具；标准模式 20 段（17 非空，5347 字符）+ 30 个工具 + 6 类运行时上下文。**

* **⚠️ 宿主已升级到 0.2.1-rc.3，安装路径全变**（§4/§5 里记的 `D:\software\DSH` 已失效，以本节为准）：
  旧路径不存在，现在是 `D:\software\DeepseekHarness\desktop\resources\app.asar`；自带 CLI =
  `D:\software\DeepseekHarness\desktop\resources\runtime\cli\bin\dsh.cmd`（`--version` = 0.2.1-rc.3，
  `D:\software\DeepseekHarness\node_modules` 那套仍是旧的 0.1.0-rc.8，勿混）；GUI 仍监听 `127.0.0.1:19387`，
  `~/.dsh` 未变。旧脚本/文档里写死的 `D:\software\DSH\...` 都要按新路径替换。
* **系统提示词装配入口**：`ctx.systemPrompt.assemble({ scope })`（`@deepseek-ai/dsh-system-prompt`），
  返回 `{ sections, contexts, tools, variables }`；`scope` 取 `agentPresets.acquireScope(presetId).key`。
  四类输入：段（拼成文本，按 order 升序）、**动态上下文（不进系统提示词文本，是带来源的 user 角色快照）**、
  工具 schema、变量（`{{model}}` 等）。渲染用 `renderPrompt()` / `renderContextSnapshot()`。
  ⇒ **任何 preset 都能在 profile 层探针里直接装配，不必改 preset 本身**。
* **不进系统提示词的三条消息通道**（标准模式才有；极简不挂这些行）：
  ① AGENTS.md（`dsh-agent-instructions`，`<system-reminder>` 包裹的 **user 消息**，上限 64 KB）；
  ② 技能目录（`dsh-skill-filesystem` + `dsh-tool-skill`，`<available_skills>` 提醒）；
  ③ 时间行（`dsh-time-context`，每步 `Time sampled while preparing turn N, step M: …`）。
* **实测差异（干净 web 模板 profile，0.2.1-rc.3）**：
  * standard：20 段（17 非空，**5347 字符 / 33 行**）= `harness:identity` + persona 前缀 +
    `plan:policy`（plan 关闭时为空）+ 13 个 `tool:*` 工具用法段 + `ui:deliverable-file-references`
    + `harness:source` + `app:web-surface` + 空 persona 后缀；工具 **30 个**；可选上下文 6 类
    （cwd / sandbox / approval / 委派深度 / checkout / GUI URL）。
  * minimal：**1 段 46 字符**（`You are a helpful software engineer assistant.`）；工具 **3 个**
    （`pwsh`、`read_image`、`working_directory`）；上下文只剩**必需**的 cwd。
  * 根因：minimal 的 persona `complete: true`（组装仍求值上下文/工具/变量，但最终只保留 persona
    前缀段，身份/后缀/工具引导/监听器都写不进去）+ `includeRuntimeContext: false`
    （调 `suppressRuntimeContext()`，只压**可选**上下文，标记 required 的仍保留，例如 cwd）。
    standard 的 persona 前缀与部署级默认值（`dsh-system-prompt.config.personaPrefix`）逐字相同，
    等于没改身份。
* **`dsh-tool-fs` 已有按工具开关**（`read`/`readImage`/`write`/`edit`）：minimal 用
  `read:false, readImage:true, write:false, edit:false` ⇒ 只拿 `read_image`。
  **0.2.0-rc.2 时代「read_image 只能整组加」的结论在 0.2.1-rc.3 已不成立**
  （`mods/agent-preset-custom` 当时据此把 read/write/edit 一起加了；要收窄可改开关式）。
* **复现方法**：`tmp/prompt-compare/probe-system-prompt.mjs` 挂进临时 profile（profile patch 里
  `- insert:` 一行 `name: './probe-system-prompt.mjs'`，config 给 `presetIds` / `outDir` / `delayMs`）
  → 起临时实例 → 读 `out/<preset>.json`。`--dump-config` 只能看组合，看不到装配后的文本。

## 12. 标·准· 模式（agent preset `standard-assistant`，原「助手标准模式」，2026-10-29）

> 需求目录 `mods/agent-preset-standard-assistant/`。
> 一句话：**标准模式的 plugins 逐字复制，只把人设段换成「You are a helpful software engineer assistant.」，
> 并用同名遮蔽把它注册到 order −2000，使其成为系统提示词第一项。**

* 组成：`@deepseek-ai/dsh-web-app/presets/standard.patch.yml` 的 `plugins` 原样复制，去掉
  `@deepseek-ai/dsh-persona` 行，换成本地插件 `persona-prefix-first.mjs`；其余行
  （agent-instructions / time-context / tool-* / planning / compaction / delegation / skill /
  goal / web / todo / present …）一字不改。显示名「标·准· 模式」（2026-10-29 改名），order 6。
* **机制（可复用）**：段顺序由段自己的 `order` 决定（`SECTION_ORDERS`：`harness:identity` = −1000、
  内置 persona = 0、PLAN_POLICY = 500、tool 段 1000+）。`ctx.systemPrompt.section()` 支持
  **同名遮蔽**（scoped 段覆盖同名 global 段，且带自己的 order）⇒ **想在标准模式里把某段排到最前/最后，
  不必改上游包，在 preset 里挂个本地插件重注册同名段即可**（本模式就是这么把人设段排到身份段之前的）。
* **本地插件在 preset 里的相对路径** `./x.mjs` 以「插入该预设行的 patch 文件所在目录」为锚点
  （= profile 目录）⇒ install 必须把 `.mjs` 复制进 profile，且**先放插件再写 patch**
  （桌面端热加载窗口里先写 patch 会解析不到插件）。
* 实测（0.2.1-rc.3，干净 web 模板 profile；`verify.ps1` 退出码 0、无挂载告警）：
  * 非空段 17 个：`deployment:persona-prefix`（**第一项**，新文案）→ `harness:identity`（第二项）→
    `tool:pwsh/read/write/edit/glob/grep/jobs/web_search/web_fetch/goal/workflow/subagent_fork` →
    `ui:deliverable-file-references` → `harness:source` → `app:web-surface`；
  * 工具 **30 个**，与标准模式完全一致；运行时上下文与标准模式相同（不抑制）。
* 实装：desktop profile patch 8935 B → 17275 B（原 200 行逐字保留，备份 `.bak-20261029-134215`），
  插件 `persona-prefix-first.mjs` 落在 profile 目录；活宿主 inspect 安装后 **6 行**
  （standard / ptc / minimal / cordis / custom / standard-assistant）⇒ 热加载成功。

## 13. 侧栏「全局面板」折叠插件与 UI 插件开发路径（2026-10-29）

> 需求目录 `mods/sidebar-panellist-collapse/`，日志 `logs/2026-10-29-sidebar-panellist-collapse.md`。
> 一句话：**在侧栏底部官方扩展位 `sidebar.footer.action` 加一个按钮，折叠 `nav[role="navigation"]`
> 的「全局面板」列表，状态存 localStorage。**

* **UI 结构（0.2.1-rc.3 + `orca-link` 皮肤实测）**：
  * 「全局面板」列表 = 侧栏 `nav`（`role="navigation"`，名「全局面板」），内容是 slot
    **`sidebar.panellist`** 的 occupant：plugins / schedules / task-board / skill-explorer / agents / git / ssh；
  * `sidebar.panellist` 的 **`data-slot` 座位是逐面板项渲染的**（隐藏它只掉图标、文字还在），
    折叠整列要命中 `nav[role="navigation"]`，兜底 `[class*="panelList"]`
    （宿主类名 = hash 前缀 + 语义名，如 `wtg9ga_panelList`，**不能写死 hash**）；
  * 侧栏底部官方扩展位 = slot **`sidebar.footer.action`**（`replaceRisk: none`，`ownerProps: { wide }`），
    内置 occupant：update / remote-bridge / cordis-panel / remote-web-ui；
  * 皮肤 `orca-link` 是**纯资产目录**（`~\.dsh\skins\orca-link\`：`skin.json` / `skin.css` / `patches.css` /
    `hooks.mjs` / `assets/`），由 profile 里的 `dsh-client-ui-skin-center` 加载；它的角色动图是 hooks
    注入的**绝对定位覆盖层**，不在布局流里（所以列表收起后动图会叠到工作区顶部）。
* **本地 UI 插件（bundle）开发路径**（走 `cordis-plugin-development` skill）：
  1. workspace 建目录：`package.json`（`dsh.bundle.patch` + `dsh.client:{platform:'web',immediately:true,inject:[所属 UI 包]}`）
     + `cordis.patch.yml`（insert 一行）+ `index.js`（Host 半区，可空）+ `client.js`
     （`window.__ModuleLoader__.load({ id, factory(require){ ... return { inject, apply(ctx) } } })`）
     + `locale/en.json`、`locale/zh.json`（`meta.title` / `meta.description`）+ `icon.svg`；
  2. `plugin_manager install_bundle target=<绝对目录>` → 看返回的 `application` / `warnings`（本次 applied、无 warning）；
  3. 本地目录是 **pnpm link**：改 `client.js` 后**刷新页面**即生效，不必重装；
  4. 验证：host `Config.listConfigs` 查 `include:<id>`（无 Config 的插件 `status: absent` 属正常）；
     client `Slots.listSubTree root=<slot>` 看 occupant（active/order）；浏览器 `navigate + screenshot` 看实际效果
     （snapshot 过大时会落到 spill 文件，用 grep 找节点）。
* **两个坑**：① 宿主对 footer `button` 有更具体的 CSS → 纯 class 的 `width/height` 会被覆盖（按钮被拉成整行、
  换行到图标行之上），要用**内联 style** + 单元格 `flex: 0 0 auto`；② slot 的 `data-slot` 座位粒度可能是
  「逐项」而不是「整列」，选中目标前先看实际 DOM 盒。
* 已知外观：折叠后皮肤动图（绝对定位）会叠在工作区上方；要「连动图一起收起」得加皮肤内部选择器
  （依赖皮肤结构，皮肤更新可能失效），按需再做。

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
| 2026-10-08 | 新增 §6「右侧栏编辑器选型」：查明宿主自带官方右侧栏（files/documentpreview/terminal/browser），但官方预览只读 + `dsh-api-workspace-files` 无写方法；选型 = 装 `dsh-better-sidebar@0.24.1`（走侧栏「插件」页安装），需求目录 `mods/sidebar-editor/`，日志 `logs/2026-10-08-sidebar-editor.md`。 |
| 2026-10-08 | 补充 §6：实测 `dsh-better-sidebar` 与 `dsh-web-all@0.4.5` **不冲突**（无双挂载 / 无右栏注册 / 无前缀重叠）；家族 `bundle-guard` 针对的是 web profile 的 `dsh-web-ui-all` 那一套；已知小缺口 = 远程访问白名单缺 `/sidebar/ws/fs-watch`。 |
| 2026-10-14 | 新增 §7：极简模式（preset `minimal`）在 Windows 上唯一工具就是 `pwsh`（持久 ConPTY PowerShell）；本机无 PS7/pwsh，实际回退 Windows PowerShell 5.1；终端 shell 同样受 `ctx.sandbox.confine()` 沙箱；需求目录 `mods/agent-preset-minimal/`。 |
| 2026-10-14 | 新增 §8：WSL 可用性 A/B 实测——沙箱会话（read-only/workspace-write）里 `wsl.exe` 被拒（`Wsl/E_ACCESSDENIED`），`danger-full-access` 下正常；工作区 = `/mnt/d/文档/DSH-plugin/DSH-custom`；无官方「切 WSL」开关，可行路线 A/B/C/D 见 `mods/wsl-execution/`。 |
| 2026-10-14 | 新增 §9：PowerShell 的 `dsh` = npm 全局 shim → 旧 CLI **0.1.0-rc.8**；桌面端自带 **0.2.0-rc.2** 的 `dsh.cmd` 且有官方接管机制（用户 PATH 首位 + `HKCU\Software\DeepSeekHarness\Command` 归属键），**从未安装**。入口在 preload 自绘标题栏的「应用」按钮 →「管理 dsh 命令…」。实测 PowerShell 解析**目录优先级 > 扩展名优先级**（只有 `dsh.cmd` 也能压过 `dsh.ps1`）。desktop profile 被 Electron 独占，CLI 不能 boot。沙箱内装不了（HKCU 拒写 / spawn EPERM）。需求目录 `mods/dsh-command-desktop/`（含只读校验 `verify.ps1`），日志 `logs/2026-10-14-dsh-command-desktop.md`。**待用户点 GUI 安装**。 |
| 2026-10-15 | 新增 §10：把 WSL 侧的**「定制模式」**（preset `custom` = 极简 + `tool-fs` + `tool-ask-user`）复刻到 Windows 桌面客户端并实装进 desktop profile。同一份 patch 在 Windows 上工具名是 `pwsh`（Linux 是 `bash`）；实测 6 工具（模板 profile）/ 23 工具（真实 profile 副本，含第三方 task-board 的 17 个）。活宿主 inspect 安装后 5 行（多出 `include:preset-custom`）⇒ 热加载。需求目录 `mods/agent-preset-custom/`，日志 `logs/2026-10-15-agent-preset-custom-windows.md`。 |
| 2026-10-29 | 新增 §11：用探针 `ctx.systemPrompt.assemble({scope})` 实测**极简 vs 标准**的系统提示词差异（宿主已升到 **0.2.1-rc.3**）：极简 = 1 段 46 字符 + 3 工具（`complete:true` 压掉其余一切，可选上下文也抑制），标准 = 20 段/5347 字符 + 30 工具 + 6 类上下文；AGENTS.md / 技能目录 / 时间行走「消息通道」而非系统提示词。同时记录：安装路径改为 `D:\software\DeepseekHarness\desktop\resources\app.asar`（旧 `D:\software\DSH` 已删）、`dsh-tool-fs` 新增 read/readImage/write/edit 开关（旧结论「read_image 只能整组加」已过时）。日志 `logs/2026-10-29-preset-prompt-compare.md`。 |
| 2026-10-29 | 新增 §12：新建**「助手标准模式」**（preset `standard-assistant`）= 标准模式 plugins 逐字复制 + 人设段换成 `You are a helpful software engineer assistant.`。关键机制：`ctx.systemPrompt.section()` 的**同名遮蔽** + 自定 `order`，把 `deployment:persona-prefix` 注册到 −2000 排到 `harness:identity`(−1000) 之前，成为系统提示词第一项（其余 16 段顺序与标准模式一致、30 工具一致）。本地插件行 `./x.mjs` 锚定 profile 目录，install 需复制插件且先放插件后写 patch。已实装 desktop profile，活宿主 6 行预设。需求目录 `mods/agent-preset-standard-assistant/`。 |
| 2026-10-29 | 把新建的「助手标准模式」**改名为「标·准· 模式」**（preset id standard-assistant 不变，托管块标记去掉显示名）。同日用户在 desktop profile 装了通知插件 dsh-notify-me@1.17.0（另把 dsh-web-all/better-sidebar/dshmarket/dsh-meme 一并升级/新增）。 |
| 2026-10-29 | 新增 §13：新建本地 UI 插件 **`@local/dsh-panellist-collapse`**（需求目录 `mods/sidebar-panellist-collapse/`）：在侧栏底部 `sidebar.footer.action` 加折叠按钮，折叠 `nav[role="navigation"]` 的「全局面板」列表，状态存 `localStorage`；实测折叠/展开/刷新持久均通过。同时记录本地 bundle 的开发-安装-验证路径与两个坑（宿主 CSS 覆盖按钮尺寸、`data-slot` 是逐项座位）。 |