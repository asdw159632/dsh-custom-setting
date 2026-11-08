# 修复「标·准· 模式」失效 + 命令行工具换 WSL 讨论

* 日期：2026-11-08
* 需求目录：`mods/agent-preset-standard-assistant/`
* 宿主：`0.2.2-rc.1`（`D:\software\DeepseekHarness\desktop\resources\app.asar`，213202918 B）
* 结果：**已修复并实装**；两段校验 PASSED（33 工具，与标准模式逐项一致）。
* 附带：`WSL-VS-POWERSHELL.md`（换 WSL 的可行性讨论，未改动模式本身）。

---

## 1. 症状

用户报告「标·准· 模式」（agent preset `standard-assistant`）失效。表现为预设还在列表里，
但选中它新建会话时模式没有生效（工具/提示词都不对，或直接挂载失败）。

## 2. 诊断

1. 活宿主 `cordis_inspect_query`（host `Config`/`listConfigs`, `name=@deepseek-ai/dsh-agent-preset`）
   仍有 6 行：standard / ptc / minimal / cordis / custom / **standard-assistant**
   ⇒ 预设**声明**还在，问题在「挂载」而不是「注册」。
2. 用旧版 `verify.ps1` 在临时 DSH_HOME 里复现，探针报：
   ```
   RemoteError: tool-subagent-list-agents (@deepseek-ai/dsh-tool-subagent-control/list-agents): never started
       at Proxy.retain (.../@deepseek-ai/dsh-agent-preset-registry/lib/index.js)
       at async Proxy.acquireScope (...)
   ```
3. 对照 `0.2.2-rc.1` 的标准模式（`tmp/standard-022.patch.yml`，从 asar 取出）：
   * 上游已删除 `- id: tool-subagent-list-agents` 行；
   * `@deepseek-ai/dsh-tool-subagent-control` 的 `exports` 里确实不再有 `./list-agents`
     （只有 `lib/index.js`）；
   * 预设里保留的这行是**死引用** → 整个预设 composition 起不来。

## 3. 根因

宿主从 `0.2.1-rc.3` 升级到 `0.2.2-rc.1`，标准模式删掉了 `list-agents` 插件行；
「标·准· 模式」是标准模式 `plugins` 的逐字副本，于是把这行也带进了预置，形成死引用。

同轮上游还有三处差异（一并同步）：
* `tool-subagent`：`modelSelectionSettings: true` → `modelSelection: true` + `modelDiscovery: true`；
* `tool-fs`：新增 `applyPatch: false`；
* `tool-plugin-manager`：`disabled` 改为 `!!js "!ctx.get('profileContext')"`。

## 4. 修复内容

### 4.1 新增 `tools/gen-patch.mjs`

从上游 `standard.patch.yml` 生成预设声明：换 `preset-standard`/`standard`/`order`，
并把 persona 行为换成本地 `persona-prefix-first`；其余行逐字照抄。
带自检：生成结果不得再引用内置 persona、不得出现 `list-agents`。

```
node mods\agent-preset-standard-assistant\tools\gen-patch.mjs tmp\standard-022.patch.yml
# written ...\standard-assistant.patch.yml (8268 bytes)
```

### 4.2 `verify.ps1` 改为动态对照

不再硬编码 0.2.1-rc.3 的段名/工具名；在同一临时实例里同时探测 `standard` 与
`standard-assistant`（`tools/probe-preset.mjs` 支持 `presetIds` + `outDir`），断言：

* 无 `agent preset (standard|standard-assistant):` 挂载告警；
* 工具清单与标准模式**完全一致**；
* 第一项 `deployment:persona-prefix` = 本模式文案，且只出现一次；
* 第二项 `harness:identity`；
* 其余段 = 标准模式去掉自己 `deployment:persona-prefix` 段后的序列。

### 4.3 新增 `tools/verify-real-profile.ps1`

复制真实 desktop profile（package.json + cordis.patch.yml + 本地插件；`node_modules` 走 junction；
profile 名改 `sarealverify` 绕开 Electron 独占）起临时实例，在完整 bundle 栈下再验一遍。

过程中发现真实 profile 有一行历史遗留：

```
- id: web-ui-model-capabilities
  disabled: true
```

对应条目已被 `@linxin666/dsh-web-all@0.4.16` 删除。活宿主容忍它，但
`dsh --profile <副本> --dump-config` 会报 `patch: entry "web-ui-model-capabilities" not found` 并失败。
已从真实 profile 删除该 2 行（备份 `cordis.patch.yml.bak-20261108-092018-pre-stale-clean`）；
校验脚本里也保留「临时副本剔除该残留」的兜底。

### 4.4 实装

```
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-standard-assistant\install.ps1
# 已写入 ...\profiles\desktop\cordis.patch.yml（17777 B，备份 .bak-20261108-091448）
```

## 5. 验证结果

```
verify.ps1: PASSED（临时 web 模板 profile）
  - 工具 33 个 = 标准模式
  - 段 1 deployment:persona-prefix / 段 2 harness:identity / 其余 17 段一致

tools\verify-real-profile.ps1: PASSED（真实 desktop profile 副本）
  - 工具 33 个 = 标准模式
  - 段 1 deployment:persona-prefix（文案正确、只出现一次）/ 段 2 harness:identity
  - 其余 17 段与标准模式一致
  - 无 agent preset 挂载告警
```

活宿主：inspect 仍见 6 行预设（热加载已重新执行）；真实定义是否已在运行中的 GUI 生效
无法在线断言，若新会话仍报旧错，重启客户端即可。

## 6. 命令行工具换 WSL 的讨论（摘要）

详见 `mods/agent-preset-standard-assistant/WSL-VS-POWERSHELL.md`。

* 现有工具是 `pwsh`（`dsh-tool-pwsh` + 宿主 `ctx.shell`=`pwsh-sandbox`，一次性进程）；
  preset 只能「挂/不挂」，**没有换 shell 的配置项**。
* 本机无 PowerShell 7 → 实际是 Windows PowerShell 5.1。
* 路线：
  * **A（推荐）** 本地插件注册 WSL `bash`，`ctx.subprocess.spawn(['wsl.exe','--cd',<win cwd>,'--','bash','-lc',cmd])`；
    `dsh-subprocess-local` 不做 confine（已核对源码），受限会话也能用；代价 = Windows 文件沙箱对 WSL 命令失效。
  * B 官方持久 bash + `shellPath: wsl.exe`：被 `confine` 拒（只有完全访问可用）；
    就绪标记依赖 `PS1`/`PROMPT_COMMAND`，WSL 默认不继承 Windows 环境变量（实测 `FOO` 为空，`WSLENV` 可传）；
    默认参数也不合法。不推荐。
  * C 保持 pwsh，命令里手写 `wsl.exe …`：仅完全访问可用，应急。
  * D `web-ui-ssh` 把 WSL 当 Linux 远主机：官方、稳，需 sshd + 密钥。
* 待用户拍板：替换 vs 并存；是否接受沙箱失效。

## 7. 产物

* 修改：
  * `mods/agent-preset-standard-assistant/standard-assistant.patch.yml`（按 0.2.2-rc.1 重新生成）
  * `mods/agent-preset-standard-assistant/verify.ps1`（动态对照）
  * `mods/agent-preset-standard-assistant/tools/probe-preset.mjs`（多 preset）
  * `mods/agent-preset-standard-assistant/README.md`
  * `memory/MEMORY.md`（§15）
* 新增：
  * `mods/agent-preset-standard-assistant/tools/gen-patch.mjs`
  * `mods/agent-preset-standard-assistant/tools/verify-real-profile.ps1`
  * `mods/agent-preset-standard-assistant/WSL-VS-POWERSHELL.md`
  * 本日志
* 真实 profile 变更（工作区外）：
  * `~/.dsh/profiles/desktop/cordis.patch.yml` 重写托管块（备份 `.bak-20261108-091448`）
  * 删除 `web-ui-model-capabilities` 残留行（备份 `.bak-20261108-092018-pre-stale-clean`）
