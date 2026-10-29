# 助手标准模式（agent preset `standard-assistant`）

需求：**在标准模式基础上新建一个模式，系统提示词以
`deployment:persona-prefix = "You are a helpful software engineer assistant."` 为第一项开头，
再接上标准模式的其他提示词（去掉标准模式自己的 `deployment:persona-prefix`）。**

本目录既是这个模式的配置源，也是它的安装/校验工具。

---

## 1. 结论速览

| 事 | 事实（本机 0.2.1-rc.3 实测） |
| --- | --- |
| 模式组成 | **标准模式的 `plugins` 列表逐字复制**，唯一改动：把 `@deepseek-ai/dsh-persona` 行换成 `persona-prefix-first.mjs` |
| 系统提示词第一项 | `deployment:persona-prefix` = `You are a helpful software engineer assistant.`（order **−2000**） |
| 第二项 | `harness:identity`（标准模式的身份段，order −1000，原样保留） |
| 其余段 | 与标准模式**顺序与文案都一致**（plan / 13 个 `tool:*` / ui / harness:source / app:web-surface / persona 后缀） |
| 工具 | 与标准模式完全相同的 **30 个** |
| 非空段数 | 17（标准模式也是 17，只是人设段换了文案并挪到最前） |

```
[probe] preset=standard-assistant tools(30): ask_user_question, create_goal, edit, exit_plan_mode, …
[check] 第一项 = deployment:persona-prefix / "You are a helpful software engineer assistant."  OK
[check] 第二项 = harness:identity  OK
[check] 段序列与预期一致  OK
[check] 工具清单 = 标准模式的 30 个  OK
verify: PASSED
```

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
| `standard-assistant.patch.yml` | **唯一的事实来源**：profile patch 片段，`insert` 一条 `@deepseek-ai/dsh-agent-preset` 行（id `standard-assistant`，显示名「助手标准模式」，order 6） |
| `persona-prefix-first.mjs` | 本地插件：在 preset scope 里注册 `deployment:persona-prefix`（可配 `prefix` / `order` / `sectionName`） |
| `install.ps1` | 托管块方式装进 profile 的 `cordis.patch.yml`，**并把 `.mjs` 复制到 profile 目录**（幂等、先备份） |
| `uninstall.ps1` | 摘掉托管块 + 删除插件文件 |
| `verify.ps1` | 临时 DSH_HOME 里装一遍 → `--dump-config` → 起临时实例读探针 → 断言段顺序/文案/工具清单 |
| `tools/probe-preset.mjs` | 探针：`tools.view(scope)` + `systemPrompt.assemble({scope})`，落盘 JSON |
| `.gitignore` | 忽略本地产物（`tmp/`、`*.bak-*`、`*.log`） |

> 插件为什么必须复制进 profile：预设声明里的插件行写的是相对路径 `./persona-prefix-first.mjs`，
> Loader 以**插入该行的 patch 文件所在目录**（= profile 目录）为锚点解析。

## 4. 安装 / 校验 / 回滚

```powershell
# 装进当前 GUI 的 profile（缺省取 $env:DSH_PROFILE_DIR）
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-standard-assistant\install.ps1

# 校验（只写 tmp/，不碰真实 profile；端口 3128）
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-standard-assistant\verify.ps1

# 回滚
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-standard-assistant\uninstall.ps1
```

装完（或等宿主热加载）后：新建任务 →「Agent 预设 → 自定义」→ **助手标准模式**。

**本机实装记录（2026-10-29）**：

* `C:\Users\Zhang Liang\.dsh\profiles\desktop\cordis.patch.yml`：8935 B → 17275 B，
  原 200 行逐字保留；备份 `cordis.patch.yml.bak-20261029-134215`；
* `…\profiles\desktop\persona-prefix-first.mjs` 已放置；
* 活宿主（`cordis_inspect_query`，host `Config`/`listConfigs`，`name=@deepseek-ai/dsh-agent-preset`）
  安装后 **6 行**：standard / ptc / minimal / cordis / custom / **standard-assistant**
  ⇒ 桌面客户端热加载成功。

## 5. 后续修改要点

* 改人设文案或排序：改 `standard-assistant.patch.yml` 里 `persona-prefix-first.config`
  （`prefix` / `order`），再跑 `install.ps1` 覆盖（幂等）。
* 想加/减标准模式的工具或提示词段：直接改 `standard-assistant.patch.yml` 的 `plugins` 列表
  （整份就是从 `@deepseek-ai/dsh-web-app/presets/standard.patch.yml` 生成的，格式一致），
  **先查新包注册的工具名是否与现有工具重名**（重名会让整个预设挂载失败，`verify.ps1` 能立刻测出来）。
* GUI 的预设编辑器保存时会按行 id `preset-standard-assistant` 往 profile patch 追加
  `config.plugins` 覆盖行；那样改过之后要把覆盖行内容拷回本目录的 `standard-assistant.patch.yml`。
* 若上游标准模式升级（新增/删除了行），用 `tmp/gen-standard-assistant-patch.mjs` 思路重新生成：
  复制最新 `standard.patch.yml` → 换 id/name/order → 把 persona 行换成本插件行。

## 6. 已知边界

* 本模式**不**像极简模式那样压制其他段（没有 `complete: true`），也不抑制运行时上下文
  （与标准模式一致：cwd / sandbox / approval / 委派深度 / checkout / GUI URL 六类都在）。
* AGENTS.md、技能目录、时间行走的是消息通道（`<system-reminder>` 等），与标准模式完全一致。
* 身份段文案是 `dsh-system-prompt` 硬编码的英文句子；本模式只是把它排到人设段之后，没有改写它。

## 7. 变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-10-29 | 建立：由 `standard.patch.yml` 生成（逐字复制 + 换 persona 行）；新增 `persona-prefix-first.mjs` 用同名遮蔽把 `deployment:persona-prefix` 注册到 order −2000；`verify.ps1` 实测 PASSED（第一项人设段、第二项身份段、30 工具、段序列一致）；实装进 desktop profile，活宿主已见 `include:preset-standard-assistant`。 |
