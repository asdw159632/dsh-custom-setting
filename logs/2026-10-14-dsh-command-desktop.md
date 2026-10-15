# 2026-10-14 PowerShell 的 `dsh` 命令改由桌面端接管

## 起因

用户提出：「我想让当前使用的 dsh 桌面端代替 powershell 中的 dsh cli（旧版本）的 dsh 命令。
首先明确 powershell 中 dsh 命令指向哪个文件，然后考虑如何替换为 dsh 桌面端」

分两步：**先定位**，**再定替换方案**。

## 做法

### 第一步：定位 `dsh` 指向哪个文件

1. `Get-Command dsh -All` + `where.exe dsh` → 命中 `C:\Users\Zhang Liang\AppData\Roaming\npm\dsh.cmd`
   （同目录还有 `dsh.ps1`、`dsh`）；`npm config get prefix` 确认该目录就是 npm 全局前缀，
   且它在用户 PATH 末位、**不在机器 PATH**。
2. 读 `dsh.cmd` → 执行 `node "…\node_modules\@deepseek-ai\dsh\lib\bin.js"`；
   该目录是 **junction** → `D:\software\DeepseekHarness\node_modules\@deepseek-ai\dsh`，
   版本 **0.1.0-rc.8**（与 `dsh --version` 实测一致）。
3. 排除干扰：当前会话无 `dsh` 别名/函数；`.local\bin`、`scoop\shims`、`WindowsApps`、
   `C:\Program Files\nodejs` 下均无 `dsh*` ⇒ 全机唯一安装。

### 第二步：桌面端那边有什么

4. 列 `D:\software\DSH\resources` → 发现 `runtime\cli\bin\dsh.cmd`（另有 `command-manager.js`、
   `command-path.ps1`、`primary-runtime\dependencies\node\bin\node.exe`、`runtime\pnpm`）。
5. 读 `dsh.cmd`：`ELECTRON_RUN_AS_NODE=1 "<DSH>\DeepSeek Harness.exe" --expose-internals
   "<DSH>\resources\app.asar\…\dsh-desktop-host\lib\cli.js"` ⇒ **Electron 可执行文件当 Node 用**。
   实测 `--version` = **0.2.0-rc.2**（与 GUI 宿主 `runtime.json` 的 `desktopVersion` 一致）。
6. 读 `command-path.ps1` / `command-manager.js`：官方接管机制 ——
   Windows 上把 `runtime\cli\bin` **插到用户 PATH 首位** + 归属记录
   `HKCU\Software\DeepSeekHarness\Command`（可修复/移除并原样恢复，**从不删别人的安装**）；
   macOS 才是 `/usr/local/bin/dsh` 符号链接 + `.dsh-desktop-command.json` 收据。
7. 核对现状：归属键**不存在**、`runtime\cli\bin` **不在**用户 PATH ⇒ **从未安装过**。
8. 用 `tmp/find-entry.mjs` / `dump-asar.mjs` 定位 GUI 入口：asar `/lib/main.js` 的
   `DesktopCommandManager` + `applicationItems()`（`cliCommandMenu` → `commandManager.show()`），
   中文文案 `zh.cliCommandMenu = "管理 dsh 命令…"`。win32 的原生菜单栏只剩不可见 devTools 项、
   托盘菜单只有「打开应用/退出」⇒ 继续查 `/lib/preload-app.cjs` 的 `installWindowsMenu()`，
   确认入口是 **preload 注入的自绘 40px 标题栏菜单：「应用」按钮**（旁边「编辑」），
   点击后 `invoke("dsh-desktop:windows-menu","application",…)` 弹出 `applicationItems()`。
   菜单项顺序：关于 / ── / 检查更新… / **管理 dsh 命令…（第 4 项）** / ── / 退出。
   一个后台并行检索独立复核了同一结论，并补齐两个要点：
   * **挂载门槛**：`installWindowsMenu()` 只在 `[data-shell-overlay]` 出现后才挂按钮；
   * **⚠️ 仅 Electron 主窗口**：调用被包在
     `location.protocol === "dsh-app:" && location.hostname === "app"` 内
     ⇒ **浏览器里的 `dsh web` 页面（含 `DSH_WEB_URL=http://127.0.0.1:19387`）没有 preload，
     没有「应用/编辑」按钮**。这条对"用户此刻正用浏览器跟我对话"很关键。

### 第三步：两个限制 + 沙箱边界

9. `dsh --profile desktop --help` → `error: profile "desktop" is managed exclusively by the
   Electron application` ⇒ 桌面端 `dsh` **不能 boot GUI 的 desktop profile**。
10. `dsh --profile web --dump-config`（想只读探测）→ 该命令**会写** `<profile>\cordis.yml`，
    被沙箱拒（EPERM）；同时暴露桌面 CLI 会**跳过 3 个 0.1.x 线不兼容插件**。
    事后核对 `cordis.yml` 时间戳（10-15 10:49 vs 探测 15:02）与无 `.tmp`/`.lock` ⇒ **未留副作用**。
11. 沙箱实测：写 `HKCU` 被 `UnauthorizedAccessException` 拒；`node command-manager.js inspect`
    报 `{"ok":false,"code":"EPERM","message":"spawn EPERM"}` ⇒ **本会话无法代装**，必须用户点 GUI。
12. 反直觉点验证：桌面端目录**只有 `dsh.cmd`、没有 `dsh.ps1`**，而 npm 目录 `dsh.ps1` 也在。
    担心 PowerShell 里 `ExternalScript` 压过 `Application`。写 `tmp/path-resolve-test.ps1`
    造 `new`（只有 .cmd）/ `old`（.cmd + .ps1）两目录实测：
    **命中 `new\dsh.cmd`** ⇒ 解析是「先按 PATH 找目录，再在目录内挑扩展名」，
    **目录优先级 > 扩展名优先级**，官方机制在 PowerShell 里有效。

## 结论

* **`dsh` 当前指向**：npm 全局 shim（`%APPDATA%\npm\dsh.cmd`）→ junction →
  `D:\software\DeepseekHarness\…\@deepseek-ai\dsh@0.1.0-rc.8` 的 `lib\bin.js`。
* **替换方案（用户已确认 A + 保留旧包）**：走官方机制，点 GUI
  「应用」按钮 →「管理 dsh 命令…」→「安装」→「继续」→ 新开终端。
  旧 npm 包保留、被 PATH 顺序遮蔽，可随时「移除」还原。
* **装完必须新开终端**（PATH 变更不回溯已运行进程）。
* **验证**：`mods/dsh-command-desktop/verify.ps1`（纯只读 7 项）+ `dsh --version` 应为 0.2.0-rc.2。
* 未采用的方案 B/C/D/E（硬改 shim / 改 junction / 只改本会话 / 用 dsh 开 GUI）见需求 README §7。

## 产物

* `mods/dsh-command-desktop/README.md` —— 定位证据、官方机制、入口位置、操作步骤、备选方案、验证
* `mods/dsh-command-desktop/verify.ps1` —— 纯只读 7 项校验（安装前基线 `FAIL=3 WARN=2`）
* `mods/dsh-command-desktop/confirm.ps1` —— 纯只读入口前置检查（客户端是否在跑 / profile / 监听端口）
* `memory/MEMORY.md` §9 + 变更记录
* `tmp/path-resolve-test.ps1` —— 解析优先级实验（tmp 不入库）
* `tmp/asar-dump/lib/main.js`、`tmp/asar-dump/lib/preload-app.cjs` —— 只读导出物（tmp 不入库）

## 状态

**待用户在 GUI 点「安装」**。本会话为 workspace-write 沙箱，无法写 HKCU，也无法 spawn 安装器；
未修改任何系统状态（注册表/PATH/文件均保持原样）。
