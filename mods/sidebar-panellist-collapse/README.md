# 左侧栏面板列表折叠（plugin `@local/dsh-panellist-collapse`）

需求：**现在这套皮肤（`orca-link`）在左边栏上部有一块动图，动图下面是「全局面板」列表
（插件 / 任务看板 / 技能中心 / 智能体 / Git / SSH / 更多）。列表太长，给一个展开/收起按钮；
按钮要放在「工作区」之上，而且折叠时不要动动图。**

本目录是一个**本地 harness 插件 bundle**：Host 半区为空，Client 半区维护一条很薄的折叠条。

---

## 1. 结论速览

| 事 | 事实 |
| --- | --- |
| 面板列表是什么 | 侧栏的 `nav`（class `*_panelList`，无障碍名「全局面板」），内容是 slot `sidebar.panellist` 的 7 个面板项 |
| 折叠条位置 | 插在**面板列表之后、工作区之前**（面板列表底边下方）。这个位置没有官方槽位，所以用 DOM 插入 + `MutationObserver` 保持（宿主重渲染后自动补回） |
| 折叠做了什么 | 把列表的 `height/min-height/max-height` 收成 0、`overflow:hidden`——**只收高度，保留列表自身的 `margin-top`** |
| 为什么保留 margin（关键） | `orca-link` 皮肤的动图舞台就是靠列表的 `margin-top: calc(var(--orca-stage) - 116px)` 撑出来的；用 `display:none` 会连这条 margin 一起删掉 → 动图舞台塌掉、工作区顶上去盖住动图。所以折叠只收高度，**动图位置完全不变** |
| 状态 | 存 `localStorage['dsh.panellist.collapsed']`，刷新/重启保持 |
| 文案 | Client locale 服务注册 zh / en；tooltip「收起面板列表 / 展开面板列表」 |
| 侧栏窄条（rail） | 列表不可见时折叠条自动隐藏（按列表宽度判断） |

## 2. 目录内容

| 文件 | 作用 |
| --- | --- |
| `package.json` | bundle 清单：`dsh.bundle.patch` + `dsh.client`（`platform: web`、`immediately`） |
| `cordis.patch.yml` | 插入一行 `panellist-collapse`（bundle 身份） |
| `index.js` | Host 半区：`export function apply() {}` |
| `client.js` | **全部实现**：折叠条 DOM、折叠样式、`body` 属性同步、locale 字典、`MutationObserver` 维护位置 |
| `locale/en.json` / `locale/zh.json` | 插件管理界面里的标题/描述（`meta.title` / `meta.description`） |
| `icon.svg` | 原创图标 |

## 3. 安装 / 卸载 / 迭代

```powershell
plugin_manager install_bundle target="D:\文档\DSH-plugin\DSH-custom\mods\sidebar-panellist-collapse"
plugin_manager remove_bundle target="@local/dsh-panellist-collapse"
```

本地目录是 **pnpm link**：改 `client.js` 后**刷新页面**即可生效，不必重装。

## 4. 验证记录（2026-10-29，宿主 0.2.1-rc.3，皮肤 `orca-link`）

1. `plugin_manager install_bundle` → `application: applied`、`warnings: []`（Host 组合出现 `include:panellist-collapse`）。
2. 浏览器实测（`http://127.0.0.1:1344`）：
   * 折叠条在「更多」行下方、工作区标题上方，居中一个小箭头；
   * 点击折叠：面板列表 7 行消失，**动图停在原处不动**，工作区上移到动图下方（不再叠在动图上）；
   * 再点展开：完全恢复原布局；
   * 折叠状态刷新后保持；控制台无本插件报错。

### 迭代记录（三个坑，按发现顺序）

1. 初版按钮放在侧栏底部扩展位 `sidebar.footer.action`——用户反馈位置不对，且离列表太远；
   而且初版用 `display:none` 折叠，把列表的 `margin-top` 一起删了，**动图舞台塌掉**。
   ⇒ 折叠改 `height:0 + overflow:hidden` 保留 margin；按钮改为插在列表与工作区之间。
2. `[data-slot="sidebar.panellist"]` 是**逐面板项**的座位（隐藏它只掉图标、文字还在），
   不是列表容器 → 折叠目标改用 `[class*="panelList"]`。
3. **`nav[role="navigation"]` 匹配不到**：「navigation」是 `<nav>` 的隐式角色，元素上没有该属性
   → 选择器和 `findNav()` 都改用实际存在的 `[class*="panelList"]`（兜底 `[data-dsh-surface="sidebar"] nav`）。
4. 宿主 DOM 重渲染可能移除注入节点 → 用 `MutationObserver` 观察 `document.body`，
   发现折叠条不在列表后面就重新插回（自身插入不会再触发无变化循环）。

## 5. 已知边界

* **依赖宿主 DOM 结构**：选择器用语义片段（`[class*="panelList"]`、`[data-dsh-surface="sidebar"]`、`nav`），
  不用 hash 前缀；但若上游大幅改侧栏结构，需要跟着调一行选择器。换别的皮肤不影响位置（折叠条跟着列表走）。
* 动图本身不归本插件管：折叠/展开都不会改它的样式或位置。
* 侧栏窄条（rail）模式下列表本来隐藏，折叠条也自动隐藏。

## 6. 变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-10-29 | 建立 v1：按钮挂侧栏底部扩展位，`display:none` 折叠列表。 |
| 2026-10-29 | v2（按用户反馈）：折叠条移到「面板列表与工作区之间」；折叠改为只收高度、保留列表 `margin-top`，动图位置不再受影响；修掉 `nav[role=navigation]` 选择器失效、改用 `[class*="panelList"]`；加 `MutationObserver` 维持注入节点。实测折叠/展开/动图不动均通过。 |
