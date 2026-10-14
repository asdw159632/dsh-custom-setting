# 2026-10-14 极简模式（preset `minimal`）与 PowerShell 可用性调研

## 起因

用户提问：「dsh 在极简模式下能否使用 powershell」。

## 做法（全程只读，未改 asar）

1. 在客户端 app.asar（`D:\software\DSH\resources\app.asar`，121348951 字节，宿主 0.2.0-rc.2）
   原始字节里搜「极简」，定位到 preset 文案与 `dsh-web-app` 的 preset 文件。
2. 用 `tmp\list-entries.mjs` / `tmp\find-entry.mjs` / `tmp\dump-asar.mjs` 定位并导出
   `@deepseek-ai/dsh-web-app/presets/minimal.patch.yml` 与相关包。
3. 顺藤查 `profiles/desktop/package.json` 的 bundles、`dsh-web-app/package.json` 的
   `dsh.bundle.patch`，确认当前 GUI 确实加载该 preset 文件。
4. 查 `dsh-terminal-bash` → `shellDialect: pwsh` → `resolvePwshPath()` 的解析顺序，
   并在本机实测 PS7 / PATH pwsh 是否存在。
5. 查 `dsh-terminal-bash` 的 `spawnArgv()` 确认沙箱包裹逻辑。

## 结论

* 极简模式在 Windows 上只提供**一个**模型可见工具：`pwsh`
  （`@deepseek-ai/dsh-tool-pwsh-persistent`，ConPTY 持久 shell，300 s/命令）；同组的 bash 两行被
  `disabled: process.platform === 'win32'` 干掉。所以 PowerShell 不仅可用，而且是唯一可用工具。
* 本机没有 PowerShell 7，也没有 PATH 里的 `pwsh`，`resolvePwshPath()` 回退到
  Windows PowerShell **5.1.26100.9549**（工具名仍叫 `pwsh`）。
* 非 `danger-full-access` 时终端 shell 的启动 argv 会经 `ctx.sandbox.confine()` 包裹 → 极简模式的
  PowerShell 同样受工作区沙箱约束；read-only 下可能 ConstrainedLanguage（已知限制，可能导致
  非 ASCII 输出跟随宿主代码页）。
* 极简模式不含 AGENTS.md 指令、Skills、todo/planning、压缩、subagent/workflow、文件工具与 web 工具，
  只用固定 persona + 一个持久 shell。

## 产物

* `mods/agent-preset-minimal/README.md` —— 完整证据链与复现命令
* `memory/MEMORY.md` §7 —— 长期记忆条目
* `tmp/scan-strings.mjs`、`tmp/find-entry.mjs`、`tmp/list-entries.mjs` —— 新增只读 asar 检索工具（tmp 不入库）

## 未做

* 未真正开一个极简模式会话做端到端验证（需消耗模型额度，且属于用户侧动作）。
* 未在会话内直接跑 node-pty/ConPTY 冒烟测试：本会话的进程打不开命名管道，
  ConPTY 输出通道会 EPERM，测出来是假阴性。

## 耗时/影响

* 未修改 app.asar、profile 或任何插件；工作区仅新增上述文档与 tmp 工具。
