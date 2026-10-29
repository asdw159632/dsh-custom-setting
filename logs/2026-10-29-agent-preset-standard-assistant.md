# 日志：新建「助手标准模式」（agent preset `standard-assistant`）

日期：2026-10-29
工作区：`D:\文档\DSH-plugin\DSH-custom`
需求目录：`mods/agent-preset-standard-assistant/`
宿主：桌面客户端 **dsh 0.2.1-rc.3**（`D:\software\DeepseekHarness\desktop\resources\app.asar`）
GUI profile：`desktop`（`~/.dsh/profiles/desktop`）

## 1. 需求

> 「在标准模式基础上新建一个模式，系统提示词以
> `"name": "deployment:persona-prefix", "text": "You are a helpful software engineer assistant."`
> 为第一项开头，再接上标准模式其他提示词（除了标准模式的 deployment:persona-prefix）。」

## 2. 设计（先解决「凭什么能排第一」）

上一轮实测已钉死两个事实（`memory/MEMORY.md` §11）：

* 段顺序由段自己的 `order` 决定：`harness:identity` = **−1000**、内置 persona（`deployment:persona-prefix`）= **0**、
  plan = 500、tool 段 1000+；
* `ctx.systemPrompt.section()` 支持**同名遮蔽**：scoped 段覆盖同名 global 段，并带上自己的 `order`。

所以「直接给内置 persona 换个 prefix」做不到第一项——身份段永远在它前面。方案：

* 预设的 `plugins` **逐字复制**标准模式（`@deepseek-ai/dsh-web-app/presets/standard.patch.yml`）；
* 去掉 `@deepseek-ai/dsh-persona` 行，换成本地插件 `persona-prefix-first.mjs`：
  在 preset scope 里用同名 `deployment:persona-prefix` 重新注册，order = **−2000**；
* 结果：人设段第一、身份段（−1000）第二、其余段原顺序不变；标准模式的人设段被遮蔽（不会出现两遍）。

## 3. 交付物

```
mods/agent-preset-standard-assistant/
├── README.md                       # 事实速览 / 机制 / 安装校验 / 后续修改
├── standard-assistant.patch.yml    # 唯一事实来源（由 standard.patch.yml 生成，8053 B）
├── persona-prefix-first.mjs        # 本地插件：注册 order −2000 的 deployment:persona-prefix 段
├── install.ps1 / uninstall.ps1     # 托管块方式装/摘 profile，并复制/删除本地插件
├── verify.ps1                      # 临时 DSH_HOME 端到端：工具清单 + 段顺序/文案断言
├── tools/probe-preset.mjs          # 探针：tools.view(scope) + systemPrompt.assemble({scope})
└── .gitignore
```

生成脚本（临时，不入库）：`tmp/gen-standard-assistant-patch.mjs`。

## 4. 实测（`verify.ps1`，退出码 0）

```
verify: CLI = …\desktop\resources\runtime\cli\bin\dsh.cmd（0.2.1-rc.3）
[3/4] OK: 组合里出现 preset-standard-assistant
--- 预设挂载诊断（应为空）---
（无告警）
--- 工具清单（30 个）---
  ask_user_question, create_goal, edit, exit_plan_mode, get_goal, glob, grep, interrupt_agent,
  job_kill, job_list, job_output, list_agents, present, pwsh, read, read_image, schedule_create,
  schedule_delete, schedule_list, schedule_update, send_message, skill, subagent_fork, todo_write,
  update_goal, web_fetch, web_search, workflow, working_directory, write
--- 系统提示词非空段顺序 ---
   1. deployment:persona-prefix        ← 「You are a helpful software engineer assistant.」
   2. harness:identity
   3. tool:pwsh      4. tool:read      5. tool:write     6. tool:edit
   7. tool:glob      8. tool:grep      9. tool:jobs      10. tool:web_search
  11. tool:web_fetch 12. tool:goal     13. tool:workflow 14. tool:subagent_fork
  15. ui:deliverable-file-references   16. harness:source   17. app:web-surface
[check] 第一项 = deployment:persona-prefix / "You are a helpful software engineer assistant."  OK
[check] 第二项 = harness:identity  OK
[check] 段序列与预期一致  OK
[check] 工具清单 = 标准模式的 30 个  OK
verify: PASSED
```

## 5. 实装（真实 desktop profile）

* `~\.dsh\profiles\desktop\cordis.patch.yml`：8935 B `668B4D5B…` → 17275 B `52B4B5A0…`，
  原 **200 行逐字保留**；备份 `cordis.patch.yml.bak-20261029-134215`；
* `~\.dsh\profiles\desktop\persona-prefix-first.mjs` 已放置（本地插件行按 profile 目录解析）；
* **活宿主已加载**：`cordis_inspect_query`（host `Config`/`listConfigs`，
  `name=@deepseek-ai/dsh-agent-preset`）安装前 5 行 → 安装后 **6 行**（多出 `include:preset-standard-assistant`）
  ⇒ 桌面客户端热加载成功，新建任务 →「Agent 预设 → 自定义」应能看到「助手标准模式」。

## 6. 两个坑（已修进 install.ps1）

1. **相对插件锚点**：preset 里的插件行 `./persona-prefix-first.mjs` 以「插入该预设行的 patch 文件
   所在目录」（= profile 目录）为锚点，所以插件必须随 profile 放置，不能留在 mods 目录里。
2. **热加载顺序**：桌面端会热加载 `cordis.patch.yml`；若先写 patch 再复制插件，热加载那一瞬间
   会解析不到插件 → 该预设挂载失败。install.ps1 已改为**先复制插件、后写 patch**。

## 7. 后续

* 改人设文案/排序：改 `standard-assistant.patch.yml` 里 `persona-prefix-first.config` 的 `prefix`/`order`，
  重跑 `install.ps1`（幂等）→ `verify.ps1` 复核。
* 上游标准模式升级后：按 `tmp/gen-standard-assistant-patch.mjs` 的思路重新生成（复制最新
  `standard.patch.yml` → 换 id/name/order → persona 行换成本插件行）。
* 「同名遮蔽 + 自定 order」这套办法可复用到任何「想在某个模式里把某段提示词挪位置」的需求。
