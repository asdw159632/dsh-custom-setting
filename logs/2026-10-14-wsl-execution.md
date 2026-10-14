# 2026-10-14 DSH 能否在工作区切到 WSL 环境

## 起因

用户追问：「那 dsh 可以直接在工作区切换到 wsl 环境进行操作吗」

## 做法

1. 先在**当前沙箱会话（workspace-write）**里跑 `wsl.exe -l -q` / `wsl.exe -e bash -lc ...`：
   失败，`Wsl/E_ACCESSDENIED`，exit -1。
2. 检查 WSL 是否真的装了：注册表 `HKCU:\...\Lxss` 有 Ubuntu-22.04（默认，`\\?\W:\Ubuntu-22.04`）
   与 Ubuntu-18.04（`D:\Ubuntu-18.04`），另有 Store 包 Ubuntu20.04LTS ⇒ 环境正常。
3. 用一次性 `danger-full-access` 重跑同一命令做 A/B：`wsl.exe -l -q` 成功列出两个发行版；
   `wsl.exe --cd 'D:\文档\DSH-plugin\DSH-custom' -- bash -lc 'uname -a; pwd; ls -1'` 成功返回
   WSL2 内核版本与 `/mnt/d/文档/DSH-plugin/DSH-custom`。
4. 回到沙箱模式复测：又是 `E_ACCESSDENIED` ⇒ 挡住 WSL 的是 DSH 沙箱，不是 WSL。
5. 查 DSH 侧机制：Windows 沙箱后端 `dsh-sandbox-windows-acl`（WRITE_RESTRICTED 受限令牌 + Low 完整性）；
   `dsh-pwsh-sandbox` 与 `dsh-terminal-bash.spawnArgv()` 在非 danger-full-access 时用
   `ctx.sandbox.confine()` 包裹启动 argv。查 base patch 确认 Windows 上 `ctx.shell` 固定为 `pwsh-sandbox`，
   preset 不能换执行世界/沙箱栈。
6. 查可选路线：`dsh-terminal-bash` 的 `shellPath`/`shellArgs`；`@linxin666/dsh-ssh`（desktop profile 已装，
   `web-ui-ssh` 行默认 disabled）；侧栏终端默认 shell 已是 wsl.exe（走 subprocess provider，不受沙箱管）。

## 结论

* **没有一键切换开关**；可行路线 4 条：
  A. 会话权限切「完全访问」→ 现有 pwsh 工具直接 `wsl.exe`（已实测可用，代价=无沙箱）；
  B. 自定义工具走 `ctx.subprocess.spawn(['wsl.exe', ...])`（不经 sandbox.confine，workspace-write 也能用，
     代价=该工具绕过文件沙箱，模板见 `~/.dsh/.agent-presets/anchored-standard/custom-bash.mjs`）；
  C. 官方持久 shell 换 `shellPath: wsl.exe`（仍被 confine → 只有完全访问可行；env 转发/就绪标记未验证）；
  D. 启用 `@linxin666/dsh-ssh`，WSL 里跑 sshd，用 `ssh_exec` 等 6 个工具（Host 直连，绕过 Windows 沙箱）。
* 工作区映射：`D:\文档\DSH-plugin\DSH-custom` ⇄ `/mnt/d/文档/DSH-plugin/DSH-custom`（中文路径正常）。
* 侧栏终端本来就能用 WSL（人用），但 Agent 不驱动它。
* 安全边界：命令一旦进 WSL，DSH 的 Windows 文件沙箱不再是边界。

## 产物

* `mods/wsl-execution/README.md` —— A/B 证据、四条路线、代价与未验证项
* `memory/MEMORY.md` §8
* 本次为一次性 `danger-full-access` 批准运行，未修改任何配置/插件/asar

## 未做

* 未实测「自定义 WSL 工具在 workspace-write 下」的端到端效果（需要建 preset 并跑会话）。
* 未实测侧栏终端里 wsl.exe 的实际启动（按文档判断，属人交互通道）。
* 未实测 WSL 侧写 /mnt/d 是否真的绕过 DSH 的 ACL 边界（机制推断，见 README 说明）。
