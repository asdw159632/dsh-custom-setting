# 左侧栏面板列表折叠（plugin `@local/dsh-panellist-collapse`）

需求：**现在这套皮肤（`orca-link`）在左边栏上部有一块动图，动图下面是「全局面板」列表
（插件 / 任务看板 / 技能中心 / 智能体 / Git / SSH / 更多）。列表太长，给一个展开/收起按钮。**

本目录是一个**本地 harness 插件 bundle**：Host 半区为空，Client 半区在侧栏底部加一个折叠按钮。

---

## 1. 结论速览

| 事 | 事实 |
| --- | --- |
| 面板列表是什么 | 左侧栏的 `nav`（`role="navigation"`，无障碍名「全局面板」）。内容是 slot **`sidebar.panellist`** 的 7 个面板项（plugins / schedules / task-board / skill-explorer / agents / git / ssh） |
| 按钮挂在哪 | 官方扩展位 slot **`sidebar.footer.action`**（侧栏底部「设置」旁，`replaceRisk: none`，不替换任何内置 UI）。`order: -10` 排在最左 |
| 折叠做了什么 | 切换 `body[data-dsh-panellist-collapsed]`，CSS 隐藏那份 `nav`；工作区自动上移填满空出来的高度 |
| 状态 | 存 `localStorage['dsh.panellist.collapsed']`，刷新/重启后保持 |
| 文案 | Client locale 服务注册 zh / en 字典；`title`、`aria-label` 为「收起面板列表 / 展开面板列表」 |
| 外观 | 36×36 单元格内 28×28 图标按钮，`color: inherit` + 半透明，跟随主题；hover/active/focus-visible 有反馈 |

## 2. 目录内容

| 文件 | 作用 |
| --- | --- |
| `package.json` | bundle 清单：`dsh.bundle.patch` + `dsh.client`（`platform: web`、`immediately`、`inject: ['@deepseek-ai/dsh-client-ui-sidebar']`）+ locale/icon 导出 |
| `cordis.patch.yml` | 插入一行 `panellist-collapse`（bundle 身份） |
| `index.js` | Host 半区：`export function apply() {}`（本需求无 Host 逻辑） |
| `client.js` | **全部实现**：locale 字典、样式表、`body` 属性同步、按钮组件、slot 注册 |
| `locale/en.json` / `locale/zh.json` | 插件管理界面里的标题/描述（`meta.title` / `meta.description`） |
| `icon.svg` | 原创图标（列表 + 折叠箭头） |

## 3. 安装 / 卸载 / 迭代

```powershell
# 安装（本地目录作为 bundle；不要手写 profile 的 package.json/cordis.patch.yml）
plugin_manager install_bundle target="D:\文档\DSH-plugin\DSH-custom\mods\sidebar-panellist-collapse"

# 卸载
plugin_manager remove_bundle target="@local/dsh-panellist-collapse"
```

* 本地目录安装是 **pnpm link**：改 `client.js` 后**刷新页面**即可生效，不必重装。
* 装完如果桌面窗口没出现按钮：刷新窗口（`Ctrl+R`）或重启客户端；本次实测 web 端 HMR 直接生效。

## 4. 验证记录（2026-10-29，宿主 0.2.1-rc.3，皮肤 `orca-link`）

1. `plugin_manager install_bundle` → `application: applied`、`warnings: []`。
2. Host 组合里出现 `include:panellist-collapse`（`status: absent` = 该插件没有 `Config`，正常）。
3. Client slot 实测：`sidebar.footer.action` occupants 里出现
   `panellist-collapse / order -10 / active: true`（与内置 `update`、`remote-bridge`、`cordis-panel`、`remote-web-ui` 并列）。
4. 浏览器实测（`http://127.0.0.1:1344`）：
   * 按钮出现在侧栏底部图标行（最左），tooltip「收起面板列表」；
   * 点击后面板列表整体消失、工作区上移（会话列表从原来只能露 1 行变成完整可见）；
   * 按钮图标翻转为「展开面板列表」，再点恢复；
   * 刷新页面后折叠状态保持（localStorage 生效）；
   * 控制台无本插件报错。

### 迭代中修掉的两个坑（写下来省得下次再踩）

1. **按钮被宿主 footer 布局拉成整行**：纯 class 样式被宿主对 footer `button` 的更具体规则压掉
   → 改为**内联 style**（`width/height/padding/...`）+ 单元格 `flex: 0 0 auto`，才并进图标行。
2. **折叠选择器命中错目标**：`[data-slot="sidebar.panellist"]` 是**逐面板项**的座位（每个图标一个），
   隐藏它只会掉图标、留下文字 → 折叠要命中列表容器 `nav[role="navigation"]`，
   并加 `[class*="panelList"]` 兜底（宿主类名是 hash 前缀 + 语义名，不能写死 hash）。

## 5. 已知边界

* **折叠后皮肤的动图会浮到工作区上方**：那块动图（皮肤的 status sprite 舞台）是绝对定位的覆盖层，
  原来正好落在「新建会话」与面板列表之间的留白里；列表收起来后工作区上移，动图就叠在工作区顶部了。
  这是皮肤自身的定位行为，不是本插件引入的。如果希望「折叠时连动图一起收起」，需要再加一条
  皮肤相关的选择器（会依赖皮肤内部结构，需与皮肤更新一起维护）——告诉我就加。
* 侧栏收成 56px 窄条（rail）时，列表本来就不显示，按钮仍在但语义重复；不影响使用。
* 皮肤没有设置页（v2 契约），本插件不依赖皮肤：任何皮肤下按钮都在侧栏底部，只是「列表长什么样」
  由皮肤决定。

## 6. 变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-10-29 | 建立：`sidebar.footer.action` 加折叠按钮，折叠 `nav[role=navigation]` 全局面板列表；内联样式对齐 footer 图标、状态持久化、locale 中英；实测折叠/展开/刷新持久均通过。 |
