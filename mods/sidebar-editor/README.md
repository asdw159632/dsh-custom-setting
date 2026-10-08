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

### 2.4 无冲突

* `dsh-web-all@0.4.5`（desktop profile 已装的那套：任务看板 / SSH / 用量 …）的
  `cordis.patch.yml` **没有** `better-sidebar` 行，dependencies 里也没有它 ——
  不会触发 better-sidebar 的「聚合包双挂载」退让逻辑，无需处理挂载顺序。
* desktop profile 的 `cordis.patch.yml` 里**没有**任何 `better-sidebar` 手工挂载行
  （已读全文确认）→ 不会双挂载出两个侧栏。

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
