# 极简模式（agent preset `minimal`）里能否用 PowerShell

* 需求目标：确认宿主内置的「极简模式」是否还能执行 PowerShell 命令、用的是哪个 PowerShell、有没有沙箱限制。
* 涉及 DSH 的部分：agent preset 声明（`@deepseek-ai/dsh-web-app/presets/minimal.patch.yml`）、
  `@deepseek-ai/dsh-tool-pwsh-persistent`、`@deepseek-ai/dsh-terminal-bash`、`@deepseek-ai/dsh-pwsh-local`。
* 结论（已确认）：**能，而且 Windows 上极简模式唯一可用的工具就是 PowerShell 工具 `pwsh`。**
* 状态：调研完成（未做端到端会话验证，见文末）。
* 日期：2026-10-14

---

## 1. 极简模式的定义位置

| 事实 | 证据 |
| --- | --- |
| preset 声明 | asar 内 `/dsh/node_modules/@deepseek-ai/dsh-web-app/presets/minimal.patch.yml`（3184 字节，sha256 `71ef887f43d8a37931ba3b014e5b116f79018af873d06625fb22e280a23c1dfc`） |
| 当前 GUI 会加载它 | `~/.dsh/profiles/desktop/package.json` 的 `dsh.profile.bundles` 含 `@deepseek-ai/dsh-web-app` |
| 四个内置 preset 一起注册 | `@deepseek-ai/dsh-web-app/package.json` 的 `dsh.bundle.patch` 依次列出 `cordis.patch.yml` → `presets/{standard,ptc,minimal,cordis}.patch.yml`；registry 默认值 `standard` |
| 显示名 | `@deepseek-ai/dsh-client-ui-agent-preset` 字典：`presetMinimalName: "极简模式"`、`presetMinimalDescription: "Agent 仅使用终端工具完成任务，适合测试和对比其基础表现。"` |

## 2. 极简模式里到底装了什么（`minimal.patch.yml` 全文要点）

```
persona            @deepseek-ai/dsh-persona（固定提示词，complete: true，includeRuntimeContext: false）
persistent-shell   cordis:group（isolate: terminals: true）
  ├─ pty                    @deepseek-ai/dsh-terminal
  ├─ terminal-bash          @deepseek-ai/dsh-terminal-bash           disabled: process.platform === 'win32'
  ├─ persistent-bash        @deepseek-ai/dsh-tool-bash-persistent    disabled: process.platform === 'win32'
  ├─ terminal-pwsh          @deepseek-ai/dsh-terminal-bash  { shellDialect: pwsh }   disabled: platform !== 'win32'
  └─ persistent-pwsh        @deepseek-ai/dsh-tool-pwsh-persistent    disabled: platform !== 'win32'
```

于是 **在 Windows 上：bash 两行被禁用，pwsh 两行被启用 → 模型可见工具只有一个：`pwsh`。**

* 工具实现：`@deepseek-ai/dsh-tool-pwsh-persistent`；ConPTY 持久 shell，cwd / `$env:` / 函数 / 后台任务跨调用保留；
  单条命令 `timeoutMs: 300000`；超时或 `exit` 会丢弃 shell 并重置。
* 极简模式**不含**：AGENTS.md 指令（`dsh-agent-instructions`）、Skills、planning/`todo_write`、
  上下文压缩、subagent/workflow、`read`/`write`/`edit`/搜索类文件工具、web 工具、runtime context。
  所有工作都要靠这一个 shell 工具完成（UI 帮助文案也这么写：「极简模式会通过终端命令完成这些操作」）。

## 3. 实际跑起来的是哪个 PowerShell

`@deepseek-ai/dsh-terminal-bash` 在 `shellDialect: pwsh` 时用
`resolvePwshPath()`（来自 `@deepseek-ai/dsh-pwsh-local`）解析可执行文件，顺序为：

1. `%ProgramFiles%\PowerShell\7\pwsh.exe`（PowerShell 7）
2. `PATH` 里的 `pwsh.exe`
3. `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`（Windows PowerShell 5.1）

**本机实测**：

* `C:\Program Files\PowerShell\7\pwsh.exe` 不存在；
* `Get-Command pwsh` 报 `CommandNotFoundException`（PATH 里没有 pwsh）；
* 于是回退到 `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`，
  版本 **5.1.26100.9549 / Desktop**（本会话自己的 `pwsh` 工具也是同一个回退结果）。

即：工具名叫 `pwsh`，但在这台机器上真正执行的是 **Windows PowerShell 5.1**。

## 4. 沙箱与权限

* `dsh-terminal-bash` 的 `spawnArgv()`：权限模式不是 `danger-full-access` 时，
  启动参数会经 `ctx.sandbox.confine(argv, policy)` 包裹；只有 `danger-full-access` 才直接返回原始 argv。
  → workspace-write 下极简模式的 PowerShell 同样受文件沙箱约束。
* read-only 权限下 pwsh 可能以 ConstrainedLanguage 启动（该包 README 已列为已知限制）：
  引导用的 `[Console]::` 编码固定与 prompt 标记可能被拒，命令改走可打印提示符/静默层级结算，
  非 ASCII 输出可能跟随宿主代码页。
* 权限模式在持久终端会话打开期间不允许切换（`cannot change sandbox mode ... while persistent terminal sessions are open`）。

## 5. 顺带纠正一个容易误读的点

preset 给模型的工具描述里写着 `You don't have access to the internet via this tool.` ——
那是**给模型的文案**，不是沙箱强制项；能否联网取决于环境与权限，而不是这句话。

## 6. 复现方式（只读工具，均在 `tmp/`）

```powershell
node tmp\dump-asar.mjs /dsh/node_modules/@deepseek-ai/dsh-web-app/presets/minimal.patch.yml
node tmp\find-entry.mjs presetMinimalName          # 定位 preset 文案所在条目
node tmp\list-entries.mjs pwsh                     # 列出 pwsh 相关包
```

## 7. 尚未做的验证（如需可补）

* 没有端到端真正开一个「极简模式」会话（要消耗模型额度）：可在任务看板建一张卡、
  把 mode 设为 `minimal`，提示词要求「运行 `$PSVersionTable.PSVersion` 并报告」，
  即可同时验证 preset 能否组合成功 + pwsh 工具是否可用。
* 没有单独验证 ConPTY 在本机沙箱下的行为：本会话自身的命令进程打不开命名管道
  （`node-pty` 的 ConPTY 走 conout 命名管道），所以从会话内直接跑 node-pty 会得到
  与宿主无关的假阴性，故未做。
