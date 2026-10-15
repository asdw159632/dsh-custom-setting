# mods/dsh-command-desktop — 让 PowerShell 的 `dsh` 由桌面端接管

> 状态：调查完成，**待用户在 GUI 里点一下「安装」**（方案 A 已确认）。
> 记录日期：2026-10-14

## 1. 需求

当前 PowerShell 里的 `dsh` 指向**旧版 CLI 0.1.0-rc.8**；希望换成**正在使用的桌面客户端自带的那套**（0.2.0-rc.2，与当前 GUI 宿主同版本）。

约定（用户已确认）：

* 走**官方机制**（桌面端内置的命令管理器 + GUI 对话框），不硬改 npm 文件；
* 旧的 npm 全局包**保留但被遮蔽**，随时可一键「移除」还原。

## 2. 调查结论：`dsh` 现在指向哪里

`npm prefix` = `C:\Users\Zhang Liang\AppData\Roaming\npm`（该目录在用户 PATH 末位）。

| 层 | 路径 | 说明 |
| --- | --- | --- |
| shim（`Get-Command` 命中） | `...\AppData\Roaming\npm\dsh.cmd`（另有 `dsh.ps1`、`dsh`） | 342 B 的 node 包装脚本 |
| 包实体（junction） | `...\Roaming\npm\node_modules\@deepseek-ai\dsh` → `D:\software\DeepseekHarness\node_modules\@deepseek-ai\dsh` | **0.1.0-rc.8** |
| 最终入口 | 该包 `lib\bin.js` | `dsh --version` = `0.1.0-rc.8` |

已排除的干扰：当前会话无 `dsh` 别名/函数；`.local\bin`、`scoop\shims`、`WindowsApps`、`C:\Program Files\nodejs` 下均无 `dsh*`。**全机只有这一个 `dsh` 安装**。

### 桌面端自带的那套（原本不在 PATH 上）

* 启动器：`<DSH>\resources\runtime\cli\bin\dsh.cmd`（5 行）
* 实际执行：

  ```bat
  set ELECTRON_RUN_AS_NODE=1
  "<DSH>\DeepSeek Harness.exe" --expose-internals "<DSH>\resources\app.asar\dsh\node_modules\@deepseek-ai\dsh-desktop-host\lib\cli.js" %*
  ```

* 实测 `--version` = **0.2.0-rc.2**（与 GUI 宿主一致）
* 即：桌面端把 Electron 可执行文件当 Node 运行时用，CLI 逻辑在 asar 内，不需要另装 Node。

## 3. 桌面端的官方接管机制（本机从未运行过）

实现位于 `<DSH>\resources\runtime\cli\command-manager.js` 与 `command-path.ps1`
（由主进程 `/lib/main.js` 的 `DesktopCommandManager` 调用；主进程入口见 §6 证据）。

**Windows 上的做法不是覆盖 shim，而是"PATH 首位 + 归属记录"：**

1. 把 `<DSH>\resources\runtime\cli\bin` **插到用户 PATH 首位** → 天然压过 `...\Roaming\npm`；
2. 归属记录写入 `HKCU\Software\DeepSeekHarness\Command`（`Directory` / `PathWasAbsent` / `RetainedEntries`）；
3. 因此可"修复/移除"并**原样恢复** PATH，且**从不删除**其他安装；
4. 变更后调用 `SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, "Environment")` 广播。

**本机现状 = 未安装**：

* `HKCU:\Software\DeepSeekHarness\Command` 不存在；
* `<DSH>\resources\runtime\cli\bin` 不在用户 PATH；
* `cli\bin` 内无归属记录（macOS 才用 `.dsh-desktop-command.json` 收据，Windows 走注册表）。

对照：桌面端**自己**解析 dsh 时读的是 `HKCU:\Environment` 的 `Path`（不展开、不合并机器 PATH）。

## 4. 两个必须知道的限制

### 4.0 为什么"PATH 首位"在 PowerShell 里也管用（已实测）

担心点：桌面端目录里**只有 `dsh.cmd`，没有 `dsh.ps1`**；而 npm 目录里 `dsh.cmd` + `dsh.ps1` 都有。
PowerShell 里 `ExternalScript` 是否会把 `Application` 压过去？

**实测结论：不会。解析顺序是「先按 PATH 找目录，再在该目录内挑扩展名」——目录优先级高于扩展名优先级。**

实验（`tmp/path-resolve-test.ps1`）：造两个临时目录，`new` 在前、`old` 在后：

| 情形 | new 目录内容 | old 目录内容 | `Get-Command dsh` 命中 |
| --- | --- | --- | --- |
| A | 只有 `dsh.cmd` | `dsh.cmd` + `dsh.ps1` | **`new\dsh.cmd`** ✅ |
| B | `dsh.cmd` + `dsh.ps1` | 同左 | `new\dsh.ps1` |

⇒ 只要桌面端目录排在 PATH 前面，`dsh` 就会被它接管，缺 `dsh.ps1` 不影响。
`verify.ps1` 的 `[4/7]` 项即按此语义模拟解析（顺序与 PowerShell 一致）。

### 4.1 desktop profile 被 Electron 独占

```text
$ dsh --profile desktop --help
dsh: error: profile "desktop" is managed exclusively by the Electron application
```

源码位置：asar `/dsh/node_modules/@deepseek-ai/dsh/lib/*` 内
`if (profile.toLowerCase() === "desktop") program.error(...)`。

⇒ 桌面端 `dsh` **不能 boot 当前 GUI 用的 `desktop` profile**。它能带的是其他 profile（`web` / `tui` / 自建）以及 `headless`。
⇒ 如果需求其实是"用 dsh 打开 GUI"，那是另一个方向，见 §7。

### 4.2 桌面 CLI boot 旧 profile 会自动屏蔽不兼容插件

探测 `dsh --profile web --dump-config` 时（只读探测，见 §5 副作用核对），桌面 CLI 报：

```text
dsh: skipping profile bundle "dshmarket": Plugin dshmarket@1.18.0 is incompatible with dsh 0.2.0-rc.2: peerDependencies {"@deepseek-ai/dsh-settings":"^0.1.0-rc.7"}
dsh: skipping profile bundle "dsh-chat-import": ... peerDependencies {"@deepseek-ai/dsh-tools":"^0.1.0-rc.6"}
dsh: skipping profile bundle "dsh-better-sidebar": Plugin dsh-better-sidebar@0.18.0 ... peerDependencies {... ^0.1.2-rc.1}
```

`web` profile 装的是 0.1.x 线插件（`@linxin666/dsh-web-ui-all@^0.3.3`、`dsh-better-sidebar@^0.18.0` 等），
用 0.2.0-rc.2 CLI 去 boot 会有**能力差异**（这三个包被跳过）。这与 MEMORY §6 的"版本必须按宿主线选"一致。

## 5. 本会话沙箱的限制（重要）

**当前会话是 `workspace-write` 沙箱，装不了这个命令**，已实测：

| 动作 | 结果 |
| --- | --- |
| 写 `HKCU:\Software\__dsh_probe_test` | `UnauthorizedAccessException` 拒绝 |
| `node command-manager.js inspect` | `{"ok":false,"code":"EPERM","message":"spawn EPERM"}` |
| `dsh --profile web --dump-config` | 被拒写 `~\.dsh\profiles\web\cordis.yml`（EPERM） |

**副作用核对**：探测后核对 `cordis.yml` 时间戳 = `2026-10-15 10:49:32`，早于探测时刻 `15:02`，
无 `.tmp` / `.lock` 残留 ⇒ `--dump-config` 的写入被沙箱挡下，**没有改动任何文件**。

⇒ 因此走 GUI 菜单（方案 A）：GUI 由用户启动，其子进程**不受本会话沙箱约束**，
`command-manager.js` 以 `<DSH>\resources\runtime\primary-runtime\dependencies\node\bin\node.exe` 直跑，
再 spawn 系统 Windows PowerShell 5.1 执行 `command-path.ps1`，正常权限写 HKCU。

## 6. 操作步骤（方案 A）

### 6.1 入口在哪（已定位到源码级）

Windows 上**没有**传统的窗口菜单栏：主进程 `Menu.setApplicationMenu(...)` 在 win32 只塞了两个不可见的
devTools 项，窗口还有 `autoHideMenuBar: true` / `setMenu(null)`；托盘菜单也只有「打开应用 / 退出」。

真正的入口由 **preload 注入**：`/lib/preload-app.cjs` 的 `installWindowsMenu()` 在页面里
shadow DOM 挂了一条 40px 高的自绘标题栏菜单，`position: fixed; top: 0; left: 48px`，
两个按钮：

| 按钮文案 | 作用 |
| --- | --- |
| **「应用」**（英文 `Application`） | `ipcRenderer.invoke("dsh-desktop:windows-menu", "application", …)` → 主进程 `applicationItems()` |
| 「编辑」（英文 `Edit`） | 同上，`"edit"` → 撤销/重做/剪切/复制/粘贴 |

`applicationItems()` 的项依次是：关于 DeepSeek Harness / 检查更新… / **管理 dsh 命令…** / 退出
（macOS 上才在系统菜单栏；win32 走上面这个自绘按钮）。

⇒ **点窗口标题栏（左上角，大约在窗口图标右侧）的「应用」按钮**，弹出的菜单里第 3 项就是 **「管理 dsh 命令…」**。
若看不见：按 `Alt` 试试，或先用 `Tab` 把焦点移到标题栏再按 `↓` 展开（按钮支持方向键）。

### 6.2 安装

1. 打开 DeepSeek Harness 桌面客户端；
2. 点标题栏左上角 **「应用」** 按钮 → **「管理 dsh 命令…」**（英文 "Manage dsh Command…"）；
3. 对话框会显示三行：`Desktop 命令：` / `当前 dsh 命令：` / `当前启动器目标：`；
   未安装时会额外警告 *"另一个 dsh 的优先级更高。请移除或调整该安装的顺序…"*；
4. 点 **「安装」**；出现"继续使用 Desktop 命令？"确认框时点 **「继续」**
   （文案保证：*"现有命令会被保留，不会修改其他安装或 shell 启动文件。"*）；
5. 安装完成对话框会提示：*"打开新终端并运行 `dsh --version`。"*；
6. **新开一个终端**（PATH 变更不回溯已运行进程），按 §9 验证。

### 6.3 回退

同一入口 →「管理 dsh 命令…」→ **「移除」**：恢复原 PATH 并清掉归属键；旧 npm 包全程未被改动。

## 7. 备选方案（未采用）

| 方案 | 做法 | 为什么不用 |
| --- | --- | --- |
| B 硬替换 shim | 改 `...\Roaming\npm\dsh.cmd` / `dsh.ps1` / `dsh` 指向桌面端 | 越界写 npm 全局目录；`npm i -g` 更新旧包会还原；无归属记录、不可逆 |
| C 改 junction 目标 | 把 `node_modules\@deepseek-ai\dsh` 指向 `D:\software\DSH\...` | 桌面端的 dsh 在 asar 内，junction 指不进去；且会连累同目录其他 npm 包 |
| D 只改本会话 | `$env:PATH` 前插 `runtime\cli\bin` | 仅当前会话有效，重启失效；适合临时试用 |
| E 用 dsh 打开 GUI | 包装 `"D:\software\DSH\DeepSeek Harness.exe"` | 与"替换 CLI"是不同需求；若要，另开需求目录 |

## 8. 验证

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File mods\dsh-command-desktop\verify.ps1
```

`verify.ps1` 是**纯只读**的 7 项检查（不改注册表、不装包、不改 PATH）：

| 项 | 内容 | 安装前基线 | 安装后应 |
| --- | --- | --- | --- |
| 1/7 | 启动器存在 + 版本 | OK（0.2.0-rc.2） | OK |
| 2/7 | 用户 PATH 首位 = `runtime\cli\bin` | FAIL（首位是 `.local\bin`） | OK |
| 3/7 | 归属键 `HKCU\Software\DeepSeekHarness\Command` | FAIL（不存在） | OK |
| 4/7 | PATH 解析先命中桌面端（关键项） | FAIL（命中 npm shim） | OK |
| 5/7 | 当前会话 dsh 来源 | WARN（仍是旧命令） | 新终端里 OK |
| 6/7 | 旧 npm shim 仍在（按约定保留） | OK（0.1.0-rc.8） | OK（仍 0.1.0-rc.8） |
| 7/7 | PATH 重复/陈旧项 | WARN（`WindowsApps` 重复 1 次，既有问题） | 同左 |

安装前基线实测：`FAIL=3 WARN=2` → `verify: FAILED`（符合预期）。

> ⚠️ 维护注意：`verify.ps1` **必须保存为 UTF-8 with BOM**（MEMORY §4 同款坑）。
> PS 5.1 会把无 BOM 的 `.ps1` 按系统 ANSI（本机 GBK）解析，中文注释直接语法错误。
> 用本仓库的编辑器改完脚本后，确认前 3 字节是 `EF BB BF`；丢了就补：
>
> ```powershell
> $p='mods\dsh-command-desktop\verify.ps1'
> $t=[IO.File]::ReadAllText($p,[Text.Encoding]::UTF8)
> [IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding($true)))
> ```

补充手工验证：

```powershell
dsh --version            # 期望 0.2.0-rc.2（安装前是 0.1.0-rc.8）
where.exe dsh            # 期望首先命中 D:\software\DSH\resources\runtime\cli\bin\dsh.cmd
```

## 9. 后续注意

* **新装/升级桌面端后**，如果安装位置变化（例如换到 `%LOCALAPPDATA%\Programs\`），PATH 里的旧目录会失效；
  届时重开「管理 dsh 命令…」→ 应显示"需要修复" → 点「修复」。
* **不要用旧 CLI 管 desktop profile**（MEMORY §4）：旧 CLI 自带 pnpm 11.22.0，会改写 profile 的
  `pnpm-lock.yaml`，而 desktop profile 由应用自带 pnpm 11.7.0 管理。装好桌面端命令后，
  `dsh plugin --profile <p> add <pkg>` 由 0.2.0-rc.2 转发，版本线才对。
* 想回退：菜单 →「管理 dsh 命令…」→ **「移除」**（会恢复原 PATH 并清归属键）；
  旧 npm 包始终未被改动。
* 本会话实为沙箱会话，**无法代替你点 GUI**，也无法直接写 HKCU——这正是选方案 A 的原因。

## 10. 证据索引（只读复现命令）

```powershell
# 1) dsh 指向哪里
Get-Command dsh -All | Format-List Name,CommandType,Source,Definition
where.exe dsh
Get-Content "$env:APPDATA\npm\dsh.cmd" -Raw
Get-Item "$env:APPDATA\npm\node_modules\@deepseek-ai\dsh" | Select-Object LinkType,Target

# 2) 桌面端自带 CLI
& 'D:\software\DSH\resources\runtime\cli\bin\dsh.cmd' --version      # 0.2.0-rc.2
Get-Content 'D:\software\DSH\resources\runtime\cli\bin\dsh.cmd' -Raw
Get-Content 'D:\software\DSH\resources\runtime\cli\command-path.ps1' -Raw
Get-Content 'D:\software\DSH\resources\runtime\cli\command-manager.js' -Raw

# 3) 当前安装状态
Get-ItemProperty 'HKCU:\Software\DeepSeekHarness\Command' -ErrorAction SilentlyContinue
(Get-Item 'HKCU:\Environment').GetValue('Path',$null,'DoNotExpandEnvironmentNames')

# 4) desktop profile 被独占
& 'D:\software\DSH\resources\runtime\cli\bin\dsh.cmd' --profile desktop --help

# 5) PATH 首位能否接管 dsh（解析语义实验）
powershell -NoProfile -ExecutionPolicy Bypass -File tmp\path-resolve-test.ps1
```

asar 只读检索工具（`tmp/`，不入库）：`list-entries.mjs` / `find-entry.mjs` / `dump-asar.mjs` / `scan-strings.mjs`。

本需求用到的关键证据（导出物在 `tmp/asar-dump/`）：

| 文件 | 位置 | 内容 |
| --- | --- | --- |
| `/lib/main.js` | 约 7236 行 | `DesktopCommandManager`（inspect/install/remove + 三个原生对话框） |
| `/lib/main.js` | 约 11874 行 | `applicationItems()`：`cliCommandMenu` → `commandManager.show()` |
| `/lib/main.js` | 约 6653 行 | 中文文案 `zh.cliCommandMenu = "管理 dsh 命令…"` |
| `/lib/main.js` | 约 11930 行 | win32 只注册不可见 devTools 菜单（所以入口不在原生菜单栏） |
| `/lib/preload-app.cjs` | 约 454 行 | `installWindowsMenu()`：自绘标题栏「应用 / 编辑」按钮 |
| `/lib/preload-app.cjs` | 约 515 行 | `ipcRenderer.invoke(DESKTOP_IPC.windowsMenu, "application", …)` |
| `/lib/preload-app.cjs` | 约 298/318 行 | 中文文案 `application: "应用"` / `edit: "编辑"` |

