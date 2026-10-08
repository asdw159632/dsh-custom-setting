# 需求：右侧栏**可编辑**编辑器（编辑打开的文件）

状态：**选型完成，等待在客户端「插件」页安装**（2026-10-08）
涉及目录：`mods/sidebar-editor/`
实现层：**不自己写代码**，安装现成外部插件 `dsh-better-sidebar@0.24.1` 到 desktop profile

---

## 1. 一句话目标

让右侧栏里打开的文件**能改**：现在点文件只能看（官方文档预览是只读的），
目标是拿到带保存能力的编辑器（CodeMirror + `Ctrl+S` + 脏标记）。

---

## 2. 事实核查（2026-10-08 实测）

### 2.1 当前 GUI（desktop profile）用的是官方右栏

宿主 = 应用内 `app.asar` 里的 **DSH 0.2.0-rc.2**（`runtime.json` 亦记
`desktopVersion: 0.2.0-rc.2`，自带 pnpm **11.7.0** / node 24.21.0）。
它**自带整套官方右侧栏**，不是没装：

| 官方包（均为 `0.2.0-rc.2`） | 作用 |
| --- | --- |
| `@deepseek-ai/dsh-client-ui-sidebar-right` | 右侧栏容器（tab / 分栏 / 浮窗 / 资源地址解析） |
| `@deepseek-ai/dsh-client-ui-sidebar-files` | 内置「文件」页：工作区文件树，点文件开进侧栏 |
| `@deepseek-ai/dsh-client-ui-sidebar-documentpreview` | 文档预览（Office→PDF / PDF / 图片 / 表格 / 文本） |
| `@deepseek-ai/dsh-client-ui-sidebar-terminal` | 侧栏终端 |
| `@deepseek-ai/dsh-client-ui-sidebar-browser` | 内嵌浏览器（README 注明只在 desktop profile 挂载） |
| `@deepseek-ai/dsh-client-ui-sidebar` | 左侧栏面板列表 / 席位基座 |

清单来源（只读工具）：`tmp\list-host-official-packages.mjs` → 输出 `tmp\host-official-packages.txt`
（宿主内官方 `@deepseek-ai/*` 包共 289 个）。

### 2.2 官方预览**只读**，且宿主 API 没有写方法 —— 这是设计，不是缺装

* `dsh-client-ui-sidebar-documentpreview` 文档原文：**「预览而非编辑。」查看器不提供文件编辑**
  （`tmp\asar-dump\...\sidebar-documentpreview\README.zh.md`）。
* 宿主 `@deepseek-ai/dsh-api-workspace-files` 只有
  `read` / `readBytes` / `stat` / `list` / `changes` —— **没有任何写方法**
  （`tmp\asar-dump\...\dsh-api-workspace-files\README.zh.md` §方法表）。
  写入只由 host 侧的 `ctx.fs`（写/编辑工具）承担，浏览器侧拿不到。

**推论：官方路线拿不到编辑器，必须引入外部插件。**

### 2.3 插件版本必须按宿主线选（易踩坑）

| 包 | 版本 | peer / engines | 能否用于本机 desktop（0.2.0-rc.2） |
| --- | --- | --- | --- |
| `dsh-better-sidebar` | **0.24.1**（npm `latest`） | `@deepseek-ai/*` `^0.2.0-rc.1` | ✅ 适用（0.2.0-rc.1+） |
| `dsh-better-sidebar` | 0.22.1 | `^0.1.7-rc.1` | ❌ caret 跨 minor 不成立，会被启动预检整行禁用 |
| `dsh-better-sidebar` | 0.18.0（**web profile 现存**） | `^0.1.2-rc.1` | ❌ 同上 |
| `@linxin666/dsh-client-ui-aionui-panel` | 0.3.6（web profile 现存） | engines `>=0.1.1-rc.1`，dev deps 0.1.1-rc.2 | ❌ 0.1.x 线，inject 依赖 `dsh-client-runtime`（0.2 宿主无此包） |

peer 逐条核对结论（对着 `tmp\host-official-packages.txt`）：
0.24.1 的 14 条 peer 在宿主**全部存在** —— `dsh-llm` / `dsh-agent` / `dsh-tools` /
`dsh-session` / `dsh-settings` / `dsh-subagent` / `dsh-invariants` / `dsh-client-locale` /
`dsh-host-webserver` / `dsh-client-ui-slots` / `dsh-client-ui-settings` /
`dsh-client-ui-primitives` / `dsh-client-ui-conversation` / `cordis@4.0.4`；
可选 peer `dsh-client-ui-sidebar-right` 也在（`0.2.0-rc.2`）。
唯一残留未满足的是可选集成 `@huanlin/dsh-plugin-better-locale`（上游未适配 0.2，非本品依赖面）。

### 2.4 与已装的 `dsh-web-all@0.4.5` 是否冲突（2026-10-08 实测：不冲突）

用户明确问过这一条，逐项核对如下（全部只读查证，未改任何文件）：

| 冲突面 | 实测结果 | 依据 |
| --- | --- | --- |
| **双挂载**（同一包挂两次 → `duplicate prefix route "/sidebar/api"`） | ❌ 不会发生：`dsh-web-all@0.4.5` 的 `cordis.patch.yml` **没有** `better-sidebar` 行，`dependencies` 里也没有该包；全家族搜 `better-sidebar` 只命中"商店条目描述 / 插件管理器注释 / remote-web-ui 注释"，**没有任何挂载行** | 整树 grep |
| **右侧栏 tab kind 抢占** | ❌ 不会：全家族对右栏只做**只读探测** —— `ctx.get('sidebarRightTabs').get('browser')` 判断官方 browser tab 是否存在，再 `ctx.sidebarRight.openTab('browser', {url})`（创意工坊外链）。**没有任何 `sidebarRightTabs.register`** | grep `sidebarRightTabs.register|openTab(` |
| **host 路由前缀** | ❌ 不会：better-sidebar 占 `/sidebar/*`；家族占 `/api/dsh-*` / `/api/plugin-manager` / `/api/dsh-ssh` / `/git` / `/pet` / `/remote`。remote-web-ui 反而**主动把 `/sidebar/*` 列入转发白名单**（成对设备通道） | `remote-channel-rules.ts` §REMOTE_CHANNEL_RULES |
| **UI 区域** | ❌ 不重叠：家族占**左侧栏**面板行（任务看板 / SSH / 技能中心 / 皮肤中心）+ 底部席位（更新 / 远程 / 用量卡）；better-sidebar 占**右侧栏** tab + 自绘底部工作台 | 各自 README + 注入面 |
| **设置分区** | ❌ 不冲突：家族一个一级分区（web-ui-settings），better-sidebar 自己的「侧边卡片」分区与挂载行 config 并存 | 各自 README |

**两条需要知情的细节（不是冲突）：**

1. **家族插件管理器里的 `bundle-guard` 是冲着另一套聚合包写的。**
   `@linxin666/dsh-client-ui-plugin-manager@0.4.5` 里有一段守卫，注释原文就是
   「the family aggregate mounts dsh-better-sidebar as the insert row
   `{ id: 'better-sidebar', name: 'dsh-better-sidebar' }` … → duplicate prefix route `/sidebar/api`」。
   它处理的是 **`@linxin666/dsh-web-ui-all`（web profile 那套，0.3.x）**：
   那一套确实把 better-sidebar 当行挂载，同时官方 CLI 又把它追加进 `dsh.profile.bundles`，
   于是重复挂载。**desktop 的 `dsh-web-all@0.4.5` 不挂它**，所以这段守卫在本机不会触发，
   也不存在挂载顺序问题。
2. **远程访问通道的白名单漏了新 ws 路径。** `dsh-remote-web-ui` 的
   `wsPaths` 只列 `/api/remote.mux`、`/sidebar/ws/terminal`、`/sidebar/ws/agent-terminals`、
   `/sidebar/ws/agent-opens`、`/api/dsh-ssh/terminal` —— **没有 better-sidebar 0.24.1 的
   `/sidebar/ws/fs-watch`**。影响面仅限**手机扫码远程访问**时文件树的目录实时刷新
   （fetch 类 `/sidebar/*` 由 `sidebarPrefix` 整体覆盖，不受影响；**本地桌面零影响**）。

**唯一真会"冲突"的操作**：把同一插件装两遍（例如官方插件页装过、又从创意工坊再装一次）
→ 同一 loader entry id → `duplicate loader entry id` 或 `duplicate prefix route "/sidebar/api"`。
**只走一个通道装一次**即可；真出现了就在插件页停用其中一个。

* desktop profile 的 `cordis.patch.yml` 里**没有**任何 `better-sidebar` 手工挂载行
  （已读全文确认）→ 不会双挂载出两个侧栏。

### 2.5 市场（dshmarket）为什么弹「这是终端插件」——文案启发式，对 0.24.1 不成立

用户装之前收到提醒：「它是终端插件，可能让 web 版和客户端跑不起来」。**已定位到确切出处与判定逻辑。**

**出处**：`dshmarket`（创意工坊）的**安装确认弹窗** —— `MarketSection.tsx:7138`
在 `looksTerminal(confirming, lang)` 为真时渲染该警告块，文案在
`dshmarket/src/client/locales.ts:135-138`（打包后在 `client/client.js:333-336`）：

| 键 | 文案 |
| --- | --- |
| `terminalCautionTitle` | 可能不适用于网页版 |
| `terminalCautionBody` | 这是终端插件，网页版里可能用不了。 |
| `terminalCautionStartup` | 也可能让 DeepSeek Harness 起不来。 |
| `terminalCautionLink` | 先看使用说明 ↗ |

**判定逻辑**：`market-data.ts:382` 的 `looksTerminal()` 是**纯文案正则**，
把「插件名 + 市场描述」里出现 `tui|cli|tty|terminal|终端|命令行` 当作"终端插件"证据，
只在匹配前剔除「无需/不需要 … terminal」这类否定从句。它**不读依赖、不看原生模块**。

**为什么命中**：市场数据源（`awesome-dsh-plugin.com/plugins.json`，dshmarket 的目录源）
给它的描述是：

> Full sidebar workbench with file rendering and editing, **terminal**, Git, and subagents;
> third-party plugins can register new tabs.

那个 terminal 指的是**它侧栏里的终端 tab —— 而该 tab 自 v0.19 起由 DSH 官方
`dsh-client-ui-sidebar-terminal` 提供**（插件自己不再实现终端）。

**对 0.24.1 是否为真：否。**

* **无原生依赖**：0.24.1 的依赖清单里**没有 `node-pty`**（只有 CodeMirror 系、mermaid、
  dompurify、ws、yaml、clsx、rxjs、react-icons、`@deepseek-ai/schemastery`）。
  对比：老版 `0.18.0`（web profile 现存）的依赖里**有 `node-pty: ^1.1.0`** —— 提醒描述的是**那个年代**。
* 上游 README 两处明写：安装「depends on no package that needs a build script
  (the terminal and `node-pty` went back to DSH wholesale)」、「carries no native dependencies」。
  → 没有原生编译、没有构建脚本，**"装完起不来"的因果链不存在**。
* **市场自己的兼容性数据也没拦它**：`~/.dsh/profiles/desktop/.dsh-market/discovery-compatibility-v1.json`
  里 `dsh-better-sidebar` 的缓存事实是 version **0.24.1**、`enginesDsh: null`（无宿主版本门），
  peers 全为 `^0.2.0-rc.1` —— 与本机 0.2.0-rc.2 相符（§2.3 已逐条核对宿主里都在）。
  即**只有文案启发式命中，兼容性判定通过**。

**那条提醒何时是真的**：自带 xterm + `node-pty` 的终端类插件需要 pnpm 跑构建脚本，
Windows 上还常撞"文件被运行中的宿主占用"；而 DSH 启动是**全有全无**——一个插件加载失败
整个进程退出（dshmarket 因此配了脱离终端的恢复界面与「调整插件」）。0.24.1 不属于这一类。

**顺带一条实用提醒**：`~/.dsh/profiles/desktop/.dsh-market/log.ndjson` 里有
`install-blocked: refused while agents are running`（2026-10-08）——**有会话在跑时市场会拒绝安装**。
若你在市场里被这条挡下：改用官方「**插件**」页安装（不受该限制），或先结束会话再装。

**真正需要防的仍然只有两件事**（与提醒无关）：装完**完全重启客户端**（host 半区）；
以及 v0.23.0 起其 fs 路由取消工作区包含检查的安全取舍。

---

## 3. 方案：装 `dsh-better-sidebar@0.24.1`

它做的事正好是缺口：v0.19.0 起接 DSH 原生右侧栏（不再自绘面板），
把 tab 类型注册为原生 tab，并**接管内置「文件」页**；自带的
**可编辑 CodeMirror 编辑器**（保存 `Ctrl+S`、语法高亮、预览切换、脏标记、
mtime 冲突检测）就是官方没有的那一半。图片 / PDF / 表格 / Office 仍由官方
`ui-sidebar-documentpreview` 只读渲染。

* 上游：<https://github.com/omdsh-dev/DSH-better-sidebar>
* npm：<https://www.npmjs.com/package/dsh-better-sidebar>
* 无原生依赖（终端与 `node-pty` 已交还 DSH）→ 安装一步到位，不触发 build scripts 门禁。

### 3.1 安装通道（决定：走客户端插件页）

**通道：侧栏「插件」页 → 添加插件**（= 官方 `dsh-client-ui-plugin-manager` 的安装对话框），
它用 Host 自带 pnpm，并负责 `pluginManager.inspect` 预检、失败还原 profile、启用新组合包。

> ⚠️ 不要去 **设置 → 内置插件**：那是只读清单分区（`ui-settings-plugin-inventory`），
> 装不了东西。安装入口在**侧栏的「插件」页**。

步骤：

1. 侧栏点「**插件**」→ 找到「**添加插件**」输入框；
2. 填 **`dsh-better-sidebar@0.24.1`**（写精确版本；`@latest` 目前也是 0.24.1，但不要依赖它）；
3. 点「**安装**」：Host 先 inspect（读注册表确认 spec），通过后跑 pnpm，输出折叠在「查看安装详情」里；
4. 安装完成点「**立即启用**」（= 启用新组合包、写入 `dsh.profile.bundles`）；
5. **重启客户端**（本插件有 host 半区 `/sidebar/api/*` 路由，只刷页面不够）；
6. 重启后打开某个文本文件验证（见 §4）。

### 3.2 常见报错对照

| 现象 | 处理 |
| --- | --- |
| `Ignored build scripts` | 本包已无原生依赖，理论上不会出现；出现就用对话框的「允许这些脚本并重试」 |
| `minimum release age` / 版本不足 24h | 重跑一次（pnpm 会补 `minimumReleaseAgeExclude`）或等 24h |
| 页面出现**两个侧边栏** | 双挂载；本机已确认无手工挂载行，若发生先查 profile 的 `cordis.patch.yml` 是否被加了 `better-sidebar` 行 |
| 装完「文件」页没变 | 检查插件页里该组合包是否**已启用**、行是否有异常标签；确认已重启客户端 |
| 提示无法访问 GitHub / 连接超时 | 对话框提供「改用国内镜像」；本包走 npm 注册表，镜像即可 |

---

## 4. 验收清单（装完由 agent 协同验证）

- [ ] 侧栏「插件」页出现 `dsh-better-sidebar` 组合包，状态**已启用**，无异常标签。
- [ ] 右侧栏「文件」页仍是文件树（被插件接管，外观/交互更丰富）。
- [ ] 点一个文本/代码文件 → 打开的是**可编辑**编辑器（CodeMirror），不是只读预览。
- [ ] 改一行 → 出现脏标记；`Ctrl+S` 保存 → **磁盘内容同步变化**（用 `read` / `Get-Item LastWriteTime` 复核）。
- [ ] `Esc`/切走再切回，tab 内容与滚动位置保留。
- [ ] 图片 / PDF / Office 仍是官方只读预览（未被插件抢走）。
- [ ] 未保存就关闭 tab / 刷新时，有丢弃确认（Markdown 预览的刷新按钮）。
- [ ] 无控制台报错、无第二个侧栏。

## 5. 回滚

* 插件页里对该组合包**停用**（或卸载）→ 重启客户端即回到官方只读预览。
* 兜底：恢复安装前的 `C:\Users\Zhang Liang\.dsh\profiles\desktop\` 下
  `package.json` / `pnpm-lock.yaml` / `pnpm-workspace.yaml`（安装前建议先复制一份到 `tmp/`）。

## 6. 待办

- [ ] 用户在客户端「插件」页完成安装 + 启用 + 重启。
- [ ] agent 按 §4 复核（尤其保存是否真正落盘）。
- [ ] 结论回写 `memory/MEMORY.md`。

---

## 附：本目录相关证据（均在 `tmp/`，不进 git）

| 文件 | 内容 |
| --- | --- |
| `tmp\list-host-official-packages.mjs` | 只读脚本：列 asar 内官方包名与版本 |
| `tmp\host-official-packages.txt` | 上面脚本的输出（289 个官方包） |
| `tmp\dump-asar.mjs` | 只读脚本：把 asar 内指定路径前缀导出到 `tmp\asar-dump\` |
| `tmp\asar-dump\dsh\node_modules\@deepseek-ai\dsh-client-ui-sidebar-documentpreview\README.zh.md` | 「预览而非编辑」原文出处 |
| `tmp\asar-dump\dsh\node_modules\@deepseek-ai\dsh-api-workspace-files\README.zh.md` | 宿主文件 API 方法表（无写方法） |
| `tmp\asar-dump\dsh\node_modules\@deepseek-ai\dsh-client-ui-plugin-manager\README.zh.md` | 插件页安装对话框行为（本需求走的就是它） |
