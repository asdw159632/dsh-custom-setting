# 标·准· 模式（agent preset `standard-assistant`）

需求：**在标准模式基础上新建一个模式，系统提示词以
`deployment:persona-prefix = "You are a helpful software engineer assistant."` 为第一项开头，
再接上标准模式的其他提示词（去掉标准模式自己的 `deployment:persona-prefix`）。**

本目录既是这个模式的配置源，也是它的安装/校验工具。

---

## 1. 结论速览

| 事 | 事实（本机 0.2.2-rc.1 实测） |
| --- | --- |
| 模式组成 | **标准模式的 `plugins` 列表逐字复制**，唯一改动：把 `@deepseek-ai/dsh-persona` 行换成 `persona-prefix-first.mjs` |
| 系统提示词第一项 | `deployment:persona-prefix` = `You are a helpful software engineer assistant.`（order **−2000**） |
| 第二项 | `harness:identity`（标准模式的身份段，order −1000，原样保留） |
| 其余段 | 与标准模式**顺序与文案都一致**（plan / 14 个 `tool:*` / ui / harness:source / app:web-surface / persona 后缀） |
| 工具 | 与标准模式**逐项相同**（干净 web 模板下 33 个；真实 desktop profile 同样是 33 个） |
| 非空段数 | 18（标准模式也是 18，只是人设段换了文案并挪到最前） |

```
工具清单（33 个）：ask_user_question, create_goal, edit, exit_plan_mode, get_goal, glob, grep,
interrupt_agent, job_kill, job_list, job_output, list_agents, list_subagent_models,
plugin_manager, present, pwsh, read, read_image, schedule_*, send_message, skill, subagent,
subagent_fork, todo_write, update_goal, web_fetch, web_search, workflow, working_directory, write
[check] 第一项 = deployment:persona-prefix / "You are a helpful software engineer assistant."  OK
[check] 第二项 = harness:identity  OK
[check] 其余 17 段与标准模式一致  OK
[check] 工具清单 = 标准模式的 33 个  OK
verify: PASSED
```

> 0.2.2-rc.1 起校验改为**与同实例的标准模式动态对照**（不再写死段名/工具名），
> 宿主升级增删工具也不会假失败。

### 1.1 2026-11-08 修复：宿主升级到 0.2.2-rc.1 后模式「失效」

* 现象：预设仍在列表里（`include:preset-standard-assistant` 存在），但选中它新建会话时挂载失败，
  系统提示词/工具全都没有生效。
* 根因：宿主 0.2.2-rc.1 的标准模式删除了 `tool-subagent-list-agents` 行
  （`@deepseek-ai/dsh-tool-subagent-control/list-agents` 子路径已不存在），预设里仍指向它：
  ```
  RemoteError: tool-subagent-list-agents (@deepseek-ai/dsh-tool-subagent-control/list-agents): never started
  ```
  该行是一个死引用，导致**整个预设无法挂载**。同一轮上游还改了：
  * `tool-subagent` 的 `modelSelectionSettings: true` → `modelSelection: true` + `modelDiscovery: true`；
  * `tool-fs` 新增 `applyPatch: false`（`apply_patch` 工具）；
  * `tool-plugin-manager` 的 `disabled` 改为 `!!js "!ctx.get('profileContext')"`。
* 修复：`standard-assistant.patch.yml` 由 `tools/gen-patch.mjs` 从**新的**标准模式重新生成，
  逐行对齐上游；`verify.ps1` 升级为动态对照；新增 `tools/verify-real-profile.ps1`
  在真实 profile 副本上复验（完整 bundle 栈）。
* 附带发现：真实 desktop profile 的 `cordis.patch.yml` 里有一行历史遗留
  `- id: web-ui-model-capabilities`（对应的 bundle 条目已被 dsh-web-all 删除）。
  活宿主能容忍，但 `dsh --profile <副本> --dump-config` 会直接报
  `patch: entry "web-ui-model-capabilities" not found`。已从真实 profile 删除该 2 行
  （备份 `cordis.patch.yml.bak-20261108-092018-pre-stale-clean`）。


## 2. 为什么需要一个小插件（关键机制）

系统提示词段的顺序由各段自己的 `order` 决定（`@deepseek-ai/dsh-system-prompt`）：

* `harness:identity`（"You are an AI agent powered by DeepSeek Harness."）固定 order **−1000**；
* `deployment:persona-prefix` 由内置 `@deepseek-ai/dsh-persona` 注册，order 固定 **0**。

所以**只要还用内置 persona**，身份段就一定排在 persona 前面，做不到"persona 为第一项"。

`persona-prefix-first.mjs` 用的是注册表自带的**同名遮蔽**语义：
scoped 段覆盖同名 global 段，并带上自己的 `order`。这里在 preset scope 里重新注册
`deployment:persona-prefix` 到 **order −2000**，于是：

1. 它遮蔽掉全局/部署级的那一段（不会出现两遍）；
2. 它排到 `harness:identity`（−1000）之前，成为整份系统提示词的**第一项**；
3. 其余段完全不受影响，保持标准模式的原顺序。

## 3. 目录内容

| 文件 | 作用 |
| --- | --- |
| `standard-assistant.patch.yml` | **唯一的事实来源**：profile patch 片段，`insert` 一条 `@deepseek-ai/dsh-agent-preset` 行（id `standard-assistant`，显示名「标·准· 模式」，order 6） |
| `persona-prefix-first.mjs` | 本地插件：在 preset scope 里注册 `deployment:persona-prefix`（可配 `prefix` / `order` / `sectionName`） |
| `install.ps1` | 托管块方式装进 profile 的 `cordis.patch.yml`，**并把 `.mjs` 复制到 profile 目录**（幂等、先备份） |
| `uninstall.ps1` | 摘掉托管块 + 删除插件文件 |
| `verify.ps1` | 临时 DSH_HOME 里装一遍 → `--dump-config` → 起临时实例，**同时探测 standard 与 standard-assistant 并动态对照**（工具清单、段顺序、第一/第二项） |
| `tools/gen-patch.mjs` | 从上游 `standard.patch.yml` 生成 `standard-assistant.patch.yml`（保证除 persona 行外逐字一致） |
| `tools/verify-real-profile.ps1` | 复制真实 desktop profile 起临时实例，在完整 bundle 栈下复验（含第三方插件） |
| `tools/probe-preset.mjs` | 探针：`tools.view(scope)` + `systemPrompt.assemble({scope})`，按 preset 落盘 JSON |
| `.gitignore` | 忽略本地产物（`tmp/`、`*.bak-*`、`*.log`） |

> 插件为什么必须复制进 profile：预设声明里的插件行写的是相对路径 `./persona-prefix-first.mjs`，
> Loader 以**插入该行的 patch 文件所在目录**（= profile 目录）为锚点解析。

## 4. 安装 / 校验 / 回滚

```powershell
# 装进当前 GUI 的 profile（缺省取 $env:DSH_PROFILE_DIR）
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-standard-assistant\install.ps1

# 校验（只写 tmp/，不碰真实 profile；端口 3128）
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-standard-assistant\verify.ps1

# 端到端复验：复制真实 desktop profile，在完整 bundle 栈下再跑一遍（端口 3126）
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-standard-assistant\tools\verify-real-profile.ps1

# 回滚
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-standard-assistant\uninstall.ps1
```

装完（或等宿主热加载）后：新建任务 →「Agent 预设 → 自定义」→ **标·准· 模式**。

**本机实装记录（2026-10-29，0.2.1-rc.3）**：

* `C:\Users\Zhang Liang\.dsh\profiles\desktop\cordis.patch.yml`：8935 B → 17275 B，
  原 200 行逐字保留；备份 `cordis.patch.yml.bak-20261029-134215`；
* `…\profiles\desktop\persona-prefix-first.mjs` 已放置；
* 活宿主（`cordis_inspect_query`，host `Config`/`listConfigs`，`name=@deepseek-ai/dsh-agent-preset`）
  安装后 **6 行**：standard / ptc / minimal / cordis / custom / **standard-assistant**
  ⇒ 桌面客户端热加载成功。

**2026-11-08 修复复验（0.2.2-rc.1）**：

* `verify.ps1` PASSED：工具 33 个 = 标准模式；第一项人设段、第二项身份段；
  其余 17 段与标准模式逐项一致；
* `tools/verify-real-profile.ps1` PASSED：真实 desktop profile 副本（含全部第三方 bundle）
  同样 33 工具、段序列一致、无 `agent preset ...:` 挂载告警；
* 真实 profile 已重装托管块（17777 B，备份 `.bak-20261108-091448`），
  并删除历史遗留行 `web-ui-model-capabilities`（备份 `.bak-20261108-092018-pre-stale-clean`）。

## 5. 后续修改要点

* 改人设文案或排序：改 `standard-assistant.patch.yml` 里 `persona-prefix-first.config`
  （`prefix` / `order`），再跑 `install.ps1` 覆盖（幂等）。
* 想加/减标准模式的工具或提示词段：直接改 `standard-assistant.patch.yml` 的 `plugins` 列表
  （整份就是从 `@deepseek-ai/dsh-web-app/presets/standard.patch.yml` 生成的，格式一致），
  **先查新包注册的工具名是否与现有工具重名**（重名会让整个预设挂载失败，`verify.ps1` 能立刻测出来）。
* GUI 的预设编辑器保存时会按行 id `preset-standard-assistant` 往 profile patch 追加
  `config.plugins` 覆盖行；那样改过之后要把覆盖行内容拷回本目录的 `standard-assistant.patch.yml`。

### 5.1 宿主升级后怎么重新生成（每次 DSH 升版都做一遍）

```powershell
# 1. 从 app.asar 取出当前标准模式（路径以实际安装树为准）
node tmp\asar-read.mjs cat /dsh/node_modules/@deepseek-ai/dsh-web-app/presets/standard.patch.yml tmp\standard-<版本>.patch.yml

# 2. 重新生成（换 id/显示名/order + 换 persona 行，其余逐字照抄）
node mods\agent-preset-standard-assistant\tools\gen-patch.mjs tmp\standard-<版本>.patch.yml

# 3. 两段校验（干净模板 + 真实 profile 副本）
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-standard-assistant\verify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-standard-assistant\tools\verify-real-profile.ps1

# 4. 装回真实 profile
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-standard-assistant\install.ps1
```

> 上游升级常见的破坏方式就是**插件行引用消失/改名**（本次 `list-agents`、`modelSelectionSettings`
> 就是例子）。`gen-patch.mjs` 只保证插件行与上游一致，所以「先重新生成，再跑校验」是固定动作。

## 6. 已知边界

* 本模式**不**像极简模式那样压制其他段（没有 `complete: true`），也不抑制运行时上下文
  （与标准模式一致：cwd / sandbox / approval / 委派深度 / checkout / GUI URL 六类都在）。
* AGENTS.md、技能目录、时间行走的是消息通道（`<system-reminder>` 等），与标准模式完全一致。
* 身份段文案是 `dsh-system-prompt` 硬编码的英文句子；本模式只是把它排到人设段之后，没有改写它。

## 7. 相关讨论

* **命令行工具能不能换成 WSL？** 见 [`WSL-VS-POWERSHELL.md`](WSL-VS-POWERSHELL.md)：
  结论是「可以，但换的是工具而不是配置项」；推荐在预设里加一个本地插件注册 WSL `bash`
  工具（`ctx.subprocess.spawn(wsl.exe …)`），代价是 Windows 文件沙箱对该命令失效。
  不推荐直接给官方持久 bash 配 `shellPath: wsl.exe`（沙箱 + 就绪标记双重问题）。

## 8. 变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-10-29 | 建立：由 `standard.patch.yml` 生成（逐字复制 + 换 persona 行）；新增 `persona-prefix-first.mjs` 用同名遮蔽把 `deployment:persona-prefix` 注册到 order −2000；`verify.ps1` 实测 PASSED（第一项人设段、第二项身份段、30 工具、段序列一致）；实装进 desktop profile，活宿主已见 `include:preset-standard-assistant`。 |

| 2026-10-29 | **改名**：显示名「助手标准模式」→「标·准· 模式」（preset id 不变）；托管块标记改为不含显示名的固定写法 # >>> agent-preset-standard-assistant managed block >>>。 |
| 2026-11-08 | **修复 0.2.2-rc.1 下失效**：上游删掉 `tool-subagent-list-agents` 行（子路径已不存在），死引用让整个预设挂不上。用新增的 `tools/gen-patch.mjs` 按新标准模式重新生成；`verify.ps1` 改为与同实例标准模式动态对照；新增 `tools/verify-real-profile.ps1`。两段校验 PASSED（33 工具），已装回 desktop profile。同时清掉 profile 里历史遗留的 `web-ui-model-capabilities` 行。附 `WSL-VS-POWERSHELL.md`（命令行工具换 WSL 的可行性讨论）。 |