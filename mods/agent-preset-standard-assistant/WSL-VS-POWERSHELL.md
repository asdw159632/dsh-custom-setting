# 讨论：把「标·准· 模式」的命令行工具从 PowerShell 换成 WSL？

> 记录日期：2026-11-08（宿主 0.2.2-rc.1）
> 关联：`README.md`（模式组成）、`C:\Users\Zhang Liang\.dsh\profiles\desktop`（实装位置）、
> `memory/MEMORY.md` §8（WSL 可行性 A/B 实测）。
>
> 本文是**方案讨论**，没有改动模式本身。要做的话建议按第 5 节的路线 A 落地。

---

## 1. 结论（急着看这里）

* **可以换，但不是「改一个配置项」的换。** 这个模式的命令工具是标准模式带来的
  `pwsh`（`@deepseek-ai/dsh-tool-pwsh` + 宿主固定的 `ctx.shell`＝`pwsh-sandbox`），
  **宿主没有给 preset 暴露「把 shell 换成 wsl.exe」的开关**。
* 最省事、可控的做法：**在预设里加一个本地插件，注册一个 `bash` 工具，内部用
  `ctx.subprocess.spawn(['C:\Windows\System32\wsl.exe', '--cd', <Windows cwd>, '--', 'bash', '-lc', <command>])`**。
  * WSL 里那套完整环境（node/npm/pnpm/python3/git…）全部可用，登录 shell 会读你的 profile；
  * 代价：**绕过 DSH 的 Windows 文件沙箱**（命令在 WSL 里能写到哪，DSH 管不到）；每条命令一次新 shell（与现在的 `pwsh` 一致）；
  * 在 `workspace-write` 这种受限会话里也能用（因为 `ctx.subprocess` 本身不做 confine），
    但这也正是「沙箱失效」的原因，属于知情取舍。
* 不建议直接拿官方持久 bash + `shellPath: wsl.exe`：会被沙箱 `confine` 拒掉（只有「完全访问」能用），
  而且 shell 就绪标记依赖 `PS1`/`PROMPT_COMMAND` 环境变量，WSL 默认不继承 Windows 环境变量。
* 如果只是偶尔想用 WSL：**保持 `pwsh`，命令里自己写 `wsl.exe -- bash -lc '…'`** 也行，
  但同样只在「完全访问」会话可用。

---

## 2. 现状：这个模式的「命令行工具」到底是什么

| 项 | 事实 |
| --- | --- |
| 工具名 | `pwsh` |
| 来源 | 标准模式的 `tool-pwsh` 行 → `@deepseek-ai/dsh-tool-pwsh` |
| 执行器 | 宿主固定的 `ctx.shell`（Windows 上是 `dsh-pwsh-sandbox`，见 memory §7） |
| 语义 | **一次调用一个全新 PowerShell 进程**（不是持久 shell），不保留 `cd`/变量 |
| 沙箱 | 受限会话里由 Windows ACL 沙箱包裹；`danger-full-access` 才直接起进程 |
| 本机实际解释器 | 无 PowerShell 7（`C:\Program Files\PowerShell\7\pwsh.exe` 不存在），落到 **Windows PowerShell 5.1** |
| WSL 现状 | 默认发行版 Ubuntu-22.04（另有 Ubuntu-18.04）；工作区映射 `D:\…` ⇄ `/mnt/d/…`；`node v22.23.3`、`pnpm`、`python3`、`git 2.43.2` 都在 |

关键点：**`pwsh` 是宿主组合（profile 层）决定的，preset 只能「挂不挂这个工具」，不能改它的执行器/shell 路径。**
所以「换成 WSL」本质上要么换工具，要么换整个宿主。

---

## 3. 四条可选路线

### 路线 A（推荐）：本地插件注册一个 WSL `bash` 工具

* 机制：插件里 `ctx.tools.register(...)`，执行时 `ctx.subprocess.spawn([wsl.exe, '--cd', winCwd, '--', 'bash', '-lc', command])`。
* 优点：
  * WSL 完整环境（登录 shell、PATH、conda/nvm/pyenv 等）直接可用；
  * 工具名/描述/参数都能按需要写，模型看到的是「bash」，提示词语义自然；
  * `ctx.subprocess` 不经过 `ctx.sandbox.confine()`（已核对 `dsh-subprocess-local` 源码里没有 confine 逻辑），
    因此**受限会话也能跑**；
  * 实现量小（约 100–150 行，工作区里已有同类模板
    `~/.dsh/.agent-presets/anchored-standard/custom-bash.mjs`，只要把 argv 换成 wsl.exe 并做路径处理）。
* 缺点 / 代价：
  * **Windows 文件沙箱对 WSL 命令无效**：命令能写到 WSL 用户能写的任何地方（含 `/mnt/c`），
    这是「换 WSL」的固有属性，不是实现缺陷；
  * 每条命令一次新 shell（与现有 `pwsh` 一致；要持久状态需另做，见路线 B）；
  * 路径要翻译：Windows cwd `D:\文档\…` → WSL 侧由 `--cd` 自动处理，
    但命令里如果拿到的是 Windows 路径字符串，需要 `wslpath` 或手工映射；
  * 换行/编码：Windows 侧参数走 UTF-8，WSL 输出 UTF-8，通常没问题；CRLF 脚本要注意；
  * 工具清单与标准模式不再一致（`pwsh` → `bash`），这是**有意的差异**，需要接受。
* 适合：**你主要想在 WSL 环境里跑命令/脚本**，且会话经常是「完全访问」或你接受沙箱取舍。

### 路线 B：官方持久 bash（`tool-bash-persistent` + `terminal-bash`）把 `shellPath` 指到 wsl.exe

* 机制：`@deepseek-ai/dsh-terminal-bash` 的 `shellPath` / `shellArgs` 是配置项，理论上可写 `C:\Windows\System32\wsl.exe`。
* 阻塞点（两条，都实测过）：
  1. `terminal-bash` 的 `spawnArgv()` 在非 `danger-full-access` 时会 `sandbox.confine(argv, policy)`；
     Windows 沙箱下 `wsl.exe` 直接被拒（`Wsl/E_ACCESSDENIED`，memory §8 的 A/B 实测）⇒ **只有完全访问能用**。
  2. 就绪判定依赖 bash 方言注入的 `PS1` / `PROMPT_COMMAND` 环境变量；**WSL 默认不继承 Windows 环境变量**
     （实测：`$env:FOO='abc'` 后 `wsl.exe -e bash -lc 'echo $FOO'` 为空；只有 `WSLENV` 列出的变量才会过去）。
     `terminal-bash` 没有「设置 WSLENV」的配置项，且默认参数 `--noprofile --norc -i` 传给 `wsl.exe` 也不合法，
     需要自己改 `shellArgs`（`['-e','bash','--noprofile','--norc','-i']`）并另想办法让标记过去。
* 结论：**理论可行、工程上脆**，不建议为了「换 WSL」走这条。

### 路线 C：保持 `pwsh`，在命令里手写 `wsl.exe …`

* 零改动，今天就能用（本会话就是 `danger-full-access`，实测 `wsl.exe --cd … -- bash -lc '…'` 正常）。
* 但在受限会话里会被沙箱拒绝；而且引号/路径要过两层（PowerShell → wsl → bash），可读性差。
* 适合：**偶尔用一次**，不适合当默认工作方式。

### 路线 D：官方 SSH 插件把 WSL 当 Linux 远主机（`web-ui-ssh` / `@linxin666/dsh-ssh`）

* 桌面 profile 里 `web-ui-ssh` 已经是 `disabled: false`，启用后在插件里配置主机即可，会多出 6 个 `ssh_*` 工具。
* 在 WSL 里跑 sshd + 配好密钥，就得到一个「完整的 Linux 远主机」：
  * 不经过 Windows 沙箱（远程执行，本来就不该由本地沙箱管）；
  * 有官方的文件读写/上传下载/端口转发工具，比自定义工具稳；
  * 代价：要维护 sshd、端口、密钥；工具清单变多；WSL 的 IP 可能随重启变化（可用 `localhost` + WSL2 端口转发，或 `127.0.0.1`）。
* 适合：**想长期把 WSL 当主力 Linux 环境**，且愿意多一层 SSH。

### 路线 E（另一类问题）：把整个 DSH 跑在 WSL 里

* 那是另一个 Linux 安装/另一个 GUI 实例，不解决「当前 Windows 客户端里的这个模式」；
  但如果你要的是「原生 Linux 沙箱 + 完整环境」，这是最彻底的路线。本文不展开。

---

## 4. 对比表

| | A 本地 WSL bash 工具 | B 持久 bash + wsl.exe | C pwsh 里手写 wsl | D SSH 到 WSL |
| --- | --- | --- | --- | --- |
| 受限会话可用 | ✅（绕过沙箱） | ❌ 被 confine 拒 | ❌ 被拒 | ✅（远程） |
| 完整 WSL 环境 | ✅ | ⚠️ 取决于标记/启动方式 | ✅ | ✅ |
| 持久 shell 状态 | ❌ 每条新 shell | ✅（若能用） | ❌ | ⚠️ 每个 SSH 会话内 |
| Windows 文件沙箱 | ❌ 失效 | ❌ 失效（且本来就被拒） | ❌ 失效 | ❌ 不适用 |
| 实现/维护量 | 小（一个 .mjs） | 中（要改标记方案） | 0 | 中（sshd + 配置） |
| 推荐度 | **★★★★☆** | ★☆☆☆☆ | ★★☆☆☆（应急） | ★★★★（长期） |

---

## 5. 如果走路线 A：具体怎么做（草案）

1. 在 `mods/agent-preset-standard-assistant/` 增加 `wsl-bash.mjs`（随 `install.ps1` 一起复制进 profile）。
2. 预设 patch 里：
   * 去掉 `tool-pwsh` 行（或保留，二选一；两个命令工具会重复占提示词）；
   * 加一行 `- id: wsl-bash` / `name: './wsl-bash.mjs'`。
3. 插件要点：
   * `export const inject = ['subprocess', 'tools']`；
   * `argv = ['C:\\Windows\\System32\\wsl.exe', '--cd', winCwd, '--', 'bash', '-lc', args.command]`；
   * `winCwd = args.workdir ?? exec.agent.session.header.cwd`；
   * `stdout/stderr` 有界收集，非零退出按 `[exit code: N]` 报告（不要 throw，和官方工具一致）；
   * 描述里写明「runs inside WSL；no Windows sandbox；use /mnt/d/... paths」；
   * 可选：`distro` 配置（`-d Ubuntu-22.04`）、`shell` 配置（默认 `bash -lc`）。
4. 校验：沿用本目录的 `verify.ps1` 思路，在临时 profile 里探测工具清单；真实 profile 用
   `tools/verify-real-profile.ps1`。
5. 注意：`read/write/edit/glob/grep` 仍然是 **Windows 侧**的工具，不会因为命令工具换了 WSL 就变成 Linux 路径；
   `/mnt/d/…` 与 `D:\…` 指向同一批文件，混用没问题，但不要指望 `~` 是同一个家目录。

## 6. 需要你拍板的两件事

1. **替换还是并存？** 替换 = 模式里只有 `bash`（WSL），最干净；并存 = `pwsh` + `bash` 两个工具，模型自己选，但提示词更长。
2. **接受沙箱失效吗？** 只要命令进 WSL，Windows 文件沙箱就不再是边界（WSL 能写 `/mnt/c`、能联网）。
   如果这个模式主要用于「完全访问」会话，这条代价其实已经付过了；如果你常用 `workspace-write` 当护栏，建议改用路线 D（SSH）。
