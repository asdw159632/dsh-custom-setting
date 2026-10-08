# 工作日志：右侧栏编辑器（编辑打开的文件）

日期：2026-10-08
需求目录：[`mods/sidebar-editor/`](../mods/sidebar-editor/README.md)
状态：选型完成，等待用户在客户端「插件」页安装

---

## 1. 起因

用户问：「当前安装的 dsh-web 插件里是不是没有侧边栏的编辑功能？」
追问确认为：**要能编辑在侧栏打开的文件**（不是编辑侧栏本身）。

## 2. 做了什么

### 2.1 先回答「有没有」——结论：官方侧栏是只读，且是设计如此

1. 定位当前 GUI 的 profile：**desktop**（`~/.dsh/profiles/desktop`），
   装的是 `@linxin666/dsh-web-all@0.4.5` 那套（19 个子包：任务看板 / SSH / 技能中心 /
   用量 / 更新 / 远程访问 / 皮肤中心 …）。
2. 扫这套插件对侧栏的介入面：只做「加行（`sidebar.panellist`）+ 加席位
   （`sidebar.footer.action`）+ 给官方工作区列表套皮肤（`[data-slot="sidebar.workspaces"]`）」，
   **没有任何编辑能力**；家族里的「编辑」都在各自面板/设置里（任务标签、SKILL.md、
   主题配色、推理档位）。
3. 可编辑侧栏（编辑器）来自另外两个包：`dsh-better-sidebar` 与
   `@linxin666/dsh-client-ui-aionui-panel` —— 两者**只装在 web profile**，
   desktop profile 的 node_modules 里搜 `better-sidebar|aionui|codemirror|monaco` **零命中**。

### 2.2 顺手挖出一个反直觉事实：官方宿主自带右侧栏

写 `tmp\list-host-official-packages.mjs`（只读解析 `app.asar` 头部，列出
`/dsh/node_modules/@deepseek-ai/*/package.json` 的名称与版本），拿到宿主
**289 个官方包**，其中就有：

`dsh-client-ui-sidebar-right` / `-sidebar-files` / `-sidebar-documentpreview` /
`-sidebar-terminal` / `-sidebar-browser`，全部 `0.2.0-rc.2`。

也就是说：**文件树 + 打开文件 + 预览已经在官方侧栏里了，缺的只有「编辑」。**

### 2.3 确认「缺编辑」是设计而非漏装

* `tmp\dump-asar.mjs`（只读导出 asar 内指定前缀）导出上述包的 README，
  `sidebar-documentpreview` 原文：**「预览而非编辑。」查看器不提供文件编辑**。
* 宿主 `dsh-api-workspace-files` 方法表只有 `read` / `readBytes` / `stat` / `list` / `changes`
  ——**浏览器侧拿不到写通道**，写只由 host 的 `ctx.fs` 承担。

### 2.4 选型（不自己写）

对照 npm 与 peer 声明：

* `dsh-better-sidebar@0.24.1`：peer `^0.2.0-rc.1` → **正好覆盖 0.2.0-rc.2**；
  14 条 peer 逐条对着宿主清单核过，**全部存在**；可选 peer
  `dsh-client-ui-sidebar-right` 也在。它接管内置「文件」页并提供**可编辑 CodeMirror**
  （`Ctrl+S` 保存 / 脏标记 / mtime 冲突检测）。
* 排除：`dsh-better-sidebar@0.22.1`、web profile 现有的 `0.18.0`（均为 0.1.x 线，
  caret 跨 minor 会被启动预检整行禁用）、`aionui-panel@0.3.6`（0.1.x 线，依赖 0.2 宿主没有的
  `dsh-client-runtime`）。

### 2.5 安装通道

用户在两条通道里选了**自己在客户端「插件」页安装**（官方
`dsh-client-ui-plugin-manager` 的安装对话框：inspect 预检 → pnpm 安装 → 立即启用 →
重启客户端）。这与 `memory/MEMORY.md` §4「装插件一律走客户端内插件管理界面」一致。
精确 spec：`dsh-better-sidebar@0.24.1`。

## 3. 交付物

* `mods/sidebar-editor/README.md`：事实核查、版本对照、安装步骤、报错对照、
  验收清单、回滚。
* `tmp\list-host-official-packages.mjs`、`tmp\dump-asar.mjs`：两个只读 asar 工具
  （以后查宿主官方包/文档可复用；`tmp/` 不进 git）。

## 4. 下一步

1. 用户在侧栏「插件」→「添加插件」填 `dsh-better-sidebar@0.24.1` → 安装 → 立即启用 → **重启客户端**。
2. agent 按验收清单复核，重点验证「`Ctrl+S` 后磁盘内容真的变了」。
3. 结论回写 `memory/MEMORY.md`。

## 5. 未决 / 风险

* 安装会改动 desktop profile 的 `package.json` / `pnpm-lock.yaml`（插件页会重排），
  失败时该页面自行还原；建议安装前另存一份 profile 配置到 `tmp/`。
* 本插件 v0.23.0 起其 fs 路由**取消了工作区包含检查**（宿主用户可访问的任意路径都能读写）
  —— 这是它的已知安全取舍，装与不装需要知情。
* 重启客户端会中断当前会话（会话与任务持久化，重开后可继续）。
