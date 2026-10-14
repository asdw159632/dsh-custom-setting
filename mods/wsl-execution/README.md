# DSH 能否直接在工作区切到 WSL 环境操作

* 需求目标：搞清 DSH（桌面客户端 / 当前 GUI，desktop profile）能不能把操作环境切到 WSL，
  以及有哪些可行路线、代价是什么。
* 涉及 DSH 的部分：会话权限（`dsh-permission-presets`）、Windows 沙箱（`dsh-sandbox-local` +
  `dsh-sandbox-windows-acl`）、shell 执行器（`dsh-pwsh-sandbox`）、持久终端（`dsh-terminal-bash`）、
  侧栏终端（`dsh-api-terminal-controller`）、第三方 SSH 插件（`@linxin666/dsh-ssh`）。
* 结论：**没有「一键切到 WSL」的官方开关；但可以做到，且有 4 条路线，代价各不相同。**
* 日期：2026-10-14

---

## 1. 实测 A/B（同一台机器、同一条命令，只改会话权限）

| 会话权限 | 命令 | 结果 |
| --- | --- | --- |
| `workspace-write`（当前默认） | `wsl.exe -l -q` | **失败**：`Wsl/E_ACCESSDENIED`（访问被拒绝），exit `-1` |
| `read-only` | 同上（机制相同，未单独跑） | 预期同样失败 |
| `danger-full-access`（完全访问，本次经用户一次性批准） | `wsl.exe -l -q` | **成功**：`Ubuntu-22.04`（默认）、`Ubuntu-18.04` |
| `danger-full-access` | `wsl.exe --cd 'D:\文档\DSH-plugin\DSH-custom' -- bash -lc 'uname -a; pwd; ls -1'` | **成功**：`Linux LAPTOP-JL05C80Q 6.18.54.1-microsoft-standard-WSL2 x86_64`；`pwd` = `/mnt/d/文档/DSH-plugin/DSH-custom`；列出 `AGENTS.md README.md logs memory mods` |

同一会话内把权限切回沙箱模式后，`wsl.exe -l -v` 立刻又是 `E_ACCESSDENIED`。

**所以：WSL 本身完全正常，挡住它的是 DSH 的文件沙箱。**

* 机制：Windows 后端 `dsh-sandbox-windows-acl` 用 `WRITE_RESTRICTED` 受限令牌 + Low 完整性 + ACL 授权；
  `dsh-pwsh-sandbox`（Windows 上 `ctx.shell` 的唯一提供方）与 `dsh-terminal-bash.spawnArgv()`
  在权限不是 `danger-full-access` 时，都用 `ctx.sandbox.confine(argv, policy)` 包住要启动的进程，
  子进程（`wsl.exe`）继承该受限令牌 → 与 WSL 服务/发行版交互被系统拒绝。
* DSH 侧没有任何「把执行世界换成 WSL」的配置：preset 只能选**工具**，
  沙箱栈、subprocess、shell 执行器都在 host 平面；Windows 上 `ctx.shell` 固定是 `pwsh-sandbox`。

## 2. 工作区在 WSL 里的位置

* `D:\文档\DSH-plugin\DSH-custom` ⇄ `/mnt/d/文档/DSH-plugin/DSH-custom`（已实测，中文路径正常）。
* 本机发行版：`Ubuntu-22.04`（默认，BasePath `\\?\W:\Ubuntu-22.04`）、`Ubuntu-18.04`（`D:\Ubuntu-18.04`）；
  另有一个 Store 包 `CanonicalGroupLimited.Ubuntu20.04LTS`。
* 所以"工作区文件两边同一份"天然成立，缺的只是"让 Agent 在 Linux 侧执行"。

## 3. 四条可行路线

### 路线 A：会话权限切「完全访问」+ 现有 pwsh 工具直接调 wsl（最省事，已验证）

```powershell
wsl.exe -d Ubuntu-22.04 --cd 'D:\文档\DSH-plugin\DSH-custom' -- bash -lc 'make -j8'
```

* 优点：零改动，今天就能用；`--cd` 支持 Windows 路径。
* 代价：**完全访问 = 没有沙箱**（等于放弃工作区写入边界）；`pwsh` 工具每次调用是新进程，
  cwd/`$env:` 不跨调用保留；`wsl.exe -l -v` 输出是 UTF-16LE，PS 5.1 直接捕获会乱码，用 `-q` 或 `Out-String`。

### 路线 B：自定义工具（想长期在 WSL 里干活时推荐）

仿 `~/.dsh/.agent-presets/anchored-standard/custom-bash.mjs` 的写法，注册一个 `bash`（或 `wsl_bash`）工具：

```js
ctx.subprocess.spawn({
  argv: ['C:\\Windows\\System32\\wsl.exe', '-d', 'Ubuntu-22.04', '--cd', '/mnt/d/文档/DSH-plugin/DSH-custom',
         '--', 'bash', '-lc', command],
  ...
})
```

* 关键点：该工具走宿主插件的 `ctx.subprocess.spawn`，**不经过 shell executor 的 `sandbox.confine`**，
  所以在 `workspace-write` 会话里也能用（custom-bash 对 Git Bash 就是这么做的，注释里也写明了这个取舍）。
* 代价：这个工具自己绕过了 DSH 文件沙箱——它写工作区外的东西 DSH 拦不住，且 WSL 侧写 `/mnt/d`
  是经 WSL 服务的 9p 通道，不受 Windows 受限令牌约束。适合把它当"明确授权的 Linux 执行口"，
  不要给它配 `danger-full-access` 之外的错觉安全。

### 路线 C：把官方持久 shell 的后端换成 wsl.exe（能持久，但沙箱下会被拒）

`@deepseek-ai/dsh-terminal-bash` 有 `shellPath` / `shellArgs` 配置，理论上可做"WSL 里的持久 bash"：

```yaml
- id: terminal-wsl
  name: '@deepseek-ai/dsh-terminal-bash'
  config:
    shellDialect: bash
    shellPath: 'C:\Windows\System32\wsl.exe'
    shellArgs: ['-d', 'Ubuntu-22.04', '--cd', '/mnt/d/文档/DSH-plugin/DSH-custom', '--', 'bash']
- id: persistent-wsl
  name: '@deepseek-ai/dsh-tool-bash-persistent'
```

* 拦路虎：`spawnArgv()` 仍会调 `ctx.sandbox.confine()` → **`workspace-write` 下照样 E_ACCESSDENIED**，
  只有完全访问才跑得起来。
* 未验证项：bash 方言靠 `PS1`/`PROMPT_COMMAND` 的 OSC 133;D 标记判断就绪，
  而 WSL 默认不把 Windows 环境变量带进发行版（需要 `WSLENV`），标记可能不生效、退化到静默层级；
  另外 `wsl.exe` 在 ConPTY 下的交互行为需要实测。

### 路线 D：SSH 路线（把 WSL 当 Linux 远主机，Agent 侧不受 Windows 沙箱限制）

* desktop profile 里已经装了 `@linxin666/dsh-ssh`（`dsh-web-all` 的 `web-ui-ssh` 行**默认 `disabled: true`**，
  可在插件管理器里启用；当前会话的工具表里确实没有 `ssh_*`，说明还没启用）。
* 启用后 Agent 有 6 个工具：`ssh_list` / `ssh_exec` / `ssh_upload` / `ssh_download` / `ssh_tunnel` / `ssh_cluster`，
  全部由 Host 进程直连 SSH（`~/.dsh/dsh-ssh.json` 里已有 13 台集群主机）。
* 在 WSL 里跑 sshd、再加一台 `127.0.0.1:<port>` 主机，就能让 Agent 通过 `ssh_exec` 在 WSL 里执行；
  工作区在 `/mnt/d/...`，两边同一份文件。代价：要维护 sshd + 主机配置，且这条通道同样是宿主权限直连。

### 另外：侧栏终端本来就能用 WSL（但只给人用）

* 本机 `~/.dsh/profiles/desktop/cordis.patch.yml` 把 `terminal-controller` 的默认 shell 设成了
  `C:\Windows\System32\wsl.exe`，`shellCandidates` 里也列了 cmd / powershell / Git Bash / pwsh。
* 侧栏终端由 `dsh-api-terminal-controller` 经 **subprocess provider** 启动，
  sandbox policy 在那里只用来给"没有 cwd 的会话"提供默认目录（见该包 README），
  因此**它不受 shell 沙箱约束**——WSL 在侧栏终端里应该一直可用（按文档判断，本会话未实测）。
* 局限：那是人交互的终端，Agent 不驱动它；Agent 要用 WSL 还是得走 A/B/C/D。

## 4. 一句话结论

* 想让 Agent 立刻进 WSL：**把会话权限切「完全访问」，然后在 pwsh 工具里敲 `wsl.exe ...`**（已验证）。
* 想长期、频繁用：**写一个走 `ctx.subprocess.spawn` 的 WSL 工具**（路线 B），把它当成显式的 Linux 执行口。
* 无论哪条路，一旦命令进了 WSL，DSH 的 Windows 文件沙箱就不再是边界——别把这种会话当受限环境用。
