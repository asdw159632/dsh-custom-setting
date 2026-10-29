# 日志：左侧栏面板列表折叠按钮（皮肤需求）

日期：2026-10-29
工作区：`D:\文档\DSH-plugin\DSH-custom`
需求目录：`mods/sidebar-panellist-collapse/`
宿主：桌面客户端 dsh **0.2.1-rc.3**；GUI `http://127.0.0.1:1344`
当前皮肤：`orca-link`（`~\.dsh\skins\orca-link`，skin-center 的 v2 资产目录）
profile：`desktop`

## 1. 需求

> 「现在的皮肤实际上在左边栏上部有一个动图，动图之下是插件列表。当前插件列表太长，
> 是否可以有一个展开收起按钮来控制」

## 2. 调研（先把 UI 结构钉死）

* 皮肤是**纯资产目录**（`skin.json` + `skin.css` + `patches.css` + `hooks.mjs` + assets），
  由 profile 里的 `dsh-client-ui-skin-center` 插件加载；动图是皮肤 hooks 注入的绝对定位覆盖层
  （`v78Lda_float` / status sprite），不是布局流里的元素。
* 「插件列表」= 侧栏的 `nav`（`role="navigation"`，名「全局面板」），内容是 slot
  **`sidebar.panellist`** 的 occupant：plugins / schedules / task-board / skill-explorer /
  agents / git / ssh（`cordis_inspect_query` client `Slots.listSubTree root=sidebar.panellist` 实测）。
* 侧栏底部的官方扩展位是 slot **`sidebar.footer.action`**（`replaceRisk: none`，
  `ownerProps: { wide: boolean }`），内置 occupant：update / remote-bridge / cordis-panel / remote-web-ui。

## 3. 实现（按 cordis-plugin-development skill 的 bundle 流程）

需求是「给现有列表加一个控制」，属于视觉交互 → 做成一个**本地 bundle 插件**（可安装、可卸载、
跨会话生效），而不是改皮肤资产（皮肤更新会覆盖，且许可证是 CC BY-NC-SA）。

* 目录 `mods/sidebar-panellist-collapse/`：`package.json`（`dsh.bundle.patch` + `dsh.client`）、
  `cordis.patch.yml`、`index.js`（Host 空实现）、`client.js`（全部逻辑）、`locale/{en,zh}.json`、`icon.svg`。
* Client 逻辑：注册 `sidebar.footer.action` 一个 36×36 单元格 → 点击切
  `body[data-dsh-panellist-collapsed]` → CSS 隐藏 `nav[role="navigation"]`；
  localStorage 持久化；locale 字典（zh/en）；所有资源用 `ctx.effect` 注册，卸载自动清理。
* 安装：`plugin_manager install_bundle target=<绝对目录>` → `application: applied`、`warnings: []`。

## 4. 实测（浏览器 `http://127.0.0.1:1344`）

| 步骤 | 结果 |
| --- | --- |
| 安装 bundle | applied，无 warning；host 组合出现 `include:panellist-collapse` |
| client slot | `sidebar.footer.action` occupant：`panellist-collapse` order -10 active |
| 初始渲染 | 按钮出现在侧栏底部图标行最左，tooltip「收起面板列表」 |
| 点击折叠 | 面板列表整体消失，工作区/C 会话列表上移铺满；按钮变「展开面板列表」 |
| 再次点击 | 恢复原样 |
| 刷新页面 | 折叠状态保持（localStorage `dsh.panellist.collapsed`） |
| 控制台 | 本插件无报错（仅其余插件既有 warning） |

截图证据（浏览器截图，未入库）：
`D:\...\attachments\...` 的 browser-view 截图；折叠态与展开态各一张，见对话记录。

## 5. 两个坑（迭代两次修掉）

1. **尺寸被宿主规则覆盖**：初版用 class 写 `width:28px/height:28px`，被宿主 footer button 的
   更具体规则压掉 → 按钮被拉成整行、换行到图标行之上。改为**内联 style** + 单元格
   `flex: 0 0 auto` 后并进图标行。
2. **折叠选择器命中错层**：`[data-slot="sidebar.panellist"]` 是逐面板项的座位（隐藏它只掉图标、
   留下文字），不是列表容器。改为命中 `nav[role="navigation"]`，并用 `[class*="panelList"]` 兜底
   （宿主类名 hash 前缀不可依赖）。

## 6. 已知边界 / 后续

* 折叠后皮肤动图（绝对定位覆盖层）会叠在工作区顶部——皮肤自身定位行为；若要"折叠时连动图一起
  收起"，需加皮肤相关选择器，按需再做。
* 侧栏窄条（rail）模式下列表本来隐藏，按钮语义重复但无副作用。
* 皮肤更新不影响本插件（不依赖皮肤内部类名；折叠目标用的是角色的语义选择器）。
* 若以后面板列表的 `nav` 结构变化（例如改成别的标签），fallback 选择器是
  `[class*="panelList"]`，届时按新结构再调一行 CSS 即可。
