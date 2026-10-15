# 日志：在 Windows 桌面客户端复刻「定制模式」（agent preset `custom`）

日期：2026-10-15
工作区：`D:\文档\DSH-plugin\DSH-custom`
需求目录：`mods/agent-preset-custom/`
宿主：桌面客户端自带 **dsh 0.2.0-rc.2**（`D:\software\DSH\resources\app.asar` 内）
GUI：桌面客户端，profile **`desktop`**（`C:\Users\Zhang Liang\.dsh\profiles\desktop`）

## 1. 需求

> 「我在本机的 wsl 中新建了一个自定义的『定制模式』：`wsl:~/dsh-custom` 你去查看一下，
> 然后搞一个同样的」

即：读懂 WSL 侧 `~/dsh-custom/mods/agent-preset-custom/` 做出来的模式，在 Windows 这边
（当前工作区 + 当前 GUI 的 desktop profile）做一个同样的。

## 2. 侦察：WSL 侧是什么

* `wsl.exe` 在本会话 `workspace-write` 沙箱下被拒（`Wsl/E_ACCESSDENIED`，与 §8 记录一致），
  UNC 路径 `\\wsl.localhost\...` 同样 `Access is denied`；→ 用**一次 `danger-full-access` 提权**
  跑只读命令，把 `~/dsh-custom` 的 `mods/agent-preset-custom`（不含 .git）+ `logs/` +
  `memory/MEMORY.md` 打成 tar.gz 再用 base64 带出来，解到 `tmp/wsl-export/`。
* WSL 侧那套是**独立工作区**（`/home/zhangliang/dsh-custom`，不是 git 仓库），宿主 0.2.0-rc.2，
  GUI = `dsh web` profile `web`；需求目录里有 `custom.patch.yml` / `install.sh` /
  `uninstall.sh` / `verify.sh` / `tools/probe-preset-tools.mjs` / `README.md`，还有它自己的
  裸仓库 `mods/agent-preset-custom.git`。
* 模式组成（结论）：**定制模式 = 极简模式（逐字复制）+ `@deepseek-ai/dsh-tool-fs`
  （read / read_image / write / edit）+ `@deepseek-ai/dsh-tool-ask-user`（ask_user_question）**；
  两个坑（Linux 上极简自带的工具名就叫 `bash`，再加 `dsh-tool-bash` 会同名冲突整预设挂载失败；
  `read_image` 只能随 `dsh-tool-fs` 整组加入）都已写在它的 README 里。

## 3. Windows 侧可行性（先把机制钉死）

* 桌面客户端自带 0.2.0-rc.2 的 CLI：`D:\software\DSH\resources\runtime\cli\bin\dsh.cmd`
  = `ELECTRON_RUN_AS_NODE=1 "<DSH>\DeepSeek Harness.exe" --expose-internals
  "<DSH>\resources\app.asar\dsh\node_modules\@deepseek-ai\dsh-desktop-host\lib\cli.js"`
  → 实测 `--version` = `0.2.0-rc.2`，**不需要另装 Node**（Electron 就是它的运行时）。
* asar 内 0.2.0-rc.2 工具包齐全：`dsh-tool-fs` / `dsh-tool-ask-user` / `dsh-agent-preset` /
  `dsh-persona` / `dsh-terminal` / `dsh-terminal-bash` / `dsh-tool-bash-persistent` /
  `dsh-tool-pwsh-persistent` 全在 ⇒ 同一份 `custom.patch.yml` 在 Windows 上直接可用
  （`!!js process.platform === 'win32'` 那两行让 bash 组关、pwsh 组开）。
* 环境锚点（DSH 会话自带）：`DSH_HOME` / `DSH_PROFILE=desktop` / `DSH_PROFILE_DIR`，
  安装脚本的缺省 profile 目录就用它们，避免再次踩「路径会变」的坑。
* 临时 `DSH_HOME` + `--from-default-profile web --dump-config` 在 Windows 上**可跑通**
  （exit 0，模板 bundle 只有 `dsh-base` + `dsh-web-app`），所以 Linux 版 verify.sh 的四步
  在 Windows 上能一一对应地重写。

## 4. 交付物（`mods/agent-preset-custom/`）

| 文件 | 说明 |
| --- | --- |
| `custom.patch.yml` | **与 WSL 版逐字节一致**（sha256 `E81590C3…AEFB`）：唯一的事实来源 |
| `install.ps1` | 托管块方式装进目标 profile 的 `cordis.patch.yml`（幂等 / 先备份 / 保留 BOM 与换行风格），Linux 版 install.sh 的逐条移植 |
| `uninstall.ps1` | 摘掉托管块（摘空写回 `[]` 模板） |
| `verify.ps1` | Linux 版 verify.sh 的移植：临时 DSH_HOME → 装块 + 探针 → `--dump-config` → 起临时实例读工具清单 |
| `tools/verify-real-profile.ps1` | **Windows 特有**：复制真实 profile（package.json + 已打补丁的 cordis.patch.yml，`node_modules` 走 junction）起临时实例，端到端复核第三方 bundle 共存 |
| `tools/probe-preset-tools.mjs` | 探针，与 WSL 版逐字节一致 |
| `README.md` / `.gitignore` | 事实速览 / 安装 / 校验 / 回滚 / 后续修改要点 |

三个 `.ps1` 均存为 **UTF-8 with BOM**（PS 5.1 对无 BOM 脚本按 GBK 解析，中文注释会语法错误），
且都要求用 `powershell -NoProfile -ExecutionPolicy Bypass -File` 调用（本机默认执行策略禁止运行脚本）。

## 5. 实测证据（两次都是退出码 0）

**① 模板 profile（`verify.ps1`，端口 3123）**

```
[probe] preset=minimal tools(1): pwsh
[probe] preset=custom  tools(6): ask_user_question, edit, pwsh, read, read_image, write
--- 预设挂载诊断（应为空）---
（无告警）
[check] expect pwsh/read/read_image/write/edit/ask_user_question: 6/6 PRESENT
```

**② 真实 desktop profile 副本（`tools/verify-real-profile.ps1`，端口 3125）**

```
OK: 组合里出现 preset-custom（组合行数 = 1525）
[probe] preset=minimal tools(18): pwsh, task_board_* ×17
[probe] preset=custom  tools(23): ask_user_question, edit, pwsh, read, read_image, write, task_board_* ×17
--- 预设挂载诊断（应为空）---（无告警）
[check] … 6/6 PRESENT
```

* 与 Linux 版的差别只有一处：**工具名 `bash` → `pwsh`**（平台门禁），其余完全对应。
* ②里多出的 17 个 `task_board_*` 来自 profile 里的第三方插件
  （`@linxin666/dsh-client-ui-task-board`），注册在 **profile 层**，所以所有模式都能看到
  （极简模式也有 18 个）；不是本模式引入的。
* ②的日志里有 1 条 `better-sidebar (dsh-better-sidebar): failed to import`
  （`1 entry did not activate`）——与 WSL 侧 real-verify 记的伪影同源（插件文件在真实 profile 目录、
  解析按副本 baseUrl 生效），不涉及 preset/tool 行，不影响结论。

## 6. 实装（真实 desktop profile）

* `C:\Users\Zhang Liang\.dsh\profiles\desktop\cordis.patch.yml`：
  3267 B `710E84A5…321E` → **8406 B** `F898226A…D11B`，备份
  `cordis.patch.yml.bak-20261015-152454`。
* 原 92 行**逐字保留**（行级比对 = True，managed block 追加在末尾）。
* profile 目录内其余文件哈希未变（`package.json` / `pnpm-lock.yaml` / `cordis.yml`）；
  写 profile 需一次提权（工作区外）。
* **活宿主已加载**：`cordis_inspect_query`（host `Config` / `listConfigs`，
  `name=@deepseek-ai/dsh-agent-preset`）在安装后返回 **5 行**：
  standard / ptc / minimal / cordis / **custom**（`include:preset-custom`，
  `packageDir` = asar 内 `@deepseek-ai/dsh-agent-preset`）。安装前实测是 4 行。
  ⇒ 桌面客户端**热加载**了 profile 补丁；若 GUI 的预设选择器没刷新，重启一次客户端即可。

## 7. 踩到/确认的事实

1. **`dsh --profile desktop --dump-config` 被桌面端独占**：
   `error: profile "desktop" is managed exclusively by the Electron application`
   ⇒ 真实 profile 想端到端校验，只能「复制 profile + junction node_modules + 换个 profile 名」
   （`tools/verify-real-profile.ps1` 的 `realverify`）。这条与同工作区另一会话在
   `mods/dsh-command-desktop/` 测到的结论一致（见 `memory/MEMORY.md` §9）。
2. 本机 `pwsh` 工具与终端都是 **Windows PowerShell 5.1**：`.ps1` 必须带 BOM、
   必须用 `-ExecutionPolicy Bypass` 起（`& .\x.ps1` 直接被拒）。
3. `Get-CimInstance` 在沙箱里被拒（`拒绝访问`），查进程只能用 `Get-Process`；
   起临时实例必须 `Start-Process -PassThru` 拿 PID 再 `Stop-Process`，
   跑完确认端口已释放（`Get-NetTCPConnection -State Listen`）。
4. **并发写入事故（轻度）**：本会话进行中，同工作区另一个会话（`mods/dsh-command-desktop`）
   在 15:09:59 用仓库级 `git add` 提交时，**把我刚创建、还没提交的 6 个文件一并卷进了它的提交**
   `4ed60e8`（commit message 里没有它们）。已核对：blob 哈希与我的工作区**逐字节一致**，
   内容无损；本会话收尾时只 `git add` 自己那条路径，不再用 `-A`。
   * 教训：同一工作区多会话并行时，`git add -A` 会把别人的在建文件卷走；
     提交前先 `git status -uall`，并按路径 add。

## 8. 后续

* 改配置 → 改 `custom.patch.yml` → 重跑 `install.ps1` → 重启客户端（或看 GUI 是否热加载）。
* 想加工具：先查该包注册的工具名是否与现有工具重名（重名 = 整个预设挂载失败），
  `verify.ps1` 能立刻测出来。
* Windows 与 WSL 两套 `custom.patch.yml` 保持逐字节一致（`sha256 E81590C3…AEFB`），
  改一边记得同步另一边。
