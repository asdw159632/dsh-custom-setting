# 需求对比：自研「活跃/沉默工作区分组」 vs 社区插件生态

记录日期：2026-10-08
对比对象：
- 本需求方案：[REQUIREMENTS.md](REQUIREMENTS.md)
- 社区仓 A：`zhu1090093659/dsh-web`（npm scope `@linxin666/*`，即 README 自称的 dsh-web 插件全家桶；
  URL `github.com/zhu1090093659/dsh-web-ui` 会重定向到它）
- 社区仓 B：`DamonKoy/dsh-web-ui`（npm scope 同为 `@linxin666/*`，右侧面板 `dsh-aionui-panel` 的来源；
  与仓 A 的 `darwin` fork 关系：仓 A README 的署名节把 aionui-panel 列为"本仓库原创"，但仓 A 的
  `packages/AGENTS.md` 已把 aionui-panel 标记为**彻底移除**）
- 第三个相关项目：`omdsh-dev/DSH-better-sidebar`（npm 包 `dsh-better-sidebar`，**本机已安装**）

---

## 1. 结论速览

| 用户关注点 | 社区插件是否齐全 | 结论 |
| --- | --- | --- |
| ① 工作区进一步分组（活跃/沉默） | **没有** | 三个仓库都没有这个能力，必须自研。但可以参考 `dsh-session-archive` 的阈值与自动策略设计。 |
| ② 右侧预览可以编辑 | **有，而且本机已装** | `dsh-better-sidebar`（v0.15.2，经 `@linxin666/dsh-web-ui-all` 装入本机 web profile）已提供 CodeMirror 编辑器 + 预览/编辑切换 + `Ctrl+S` 保存；另一个实现 `@linxin666/dsh-client-ui-aionui-panel`（v0.3.6）也装在本机。**这块需求不用自己写。** |
| ③ DSH 客户端兼容性 | **存在真实的版本错层** | 本机 DSH 是 **0.1.0-rc.8**；`dsh-better-sidebar@0.18.0` 明确声明只支持 **0.1.2-rc.1+**；aionui-panel v0.3.6 声明 `>=0.1.1-rc.1`。本机顶层装的是 0.18.0，聚合包内嵌套装的是 0.15.2（兼容 rc.8 的那条线）。 |

**一句话**：右侧可编辑预览这块生态已经覆盖且本机已在用，所以你的方案可以砍掉这部分的改造设想；而**活跃/沉默工作区分组确实是生态空白**，只能自研——这也让"就地改官方工作区插件"的选择更站得住。

---

## 2. 逐条对比

### 2.1 工作区进一步分组

社区包清单（仓 A，`packages/`）里与"工作区/会话组织"沾边的只有：

| 包 | 提供什么 | 是否覆盖本需求 |
| --- | --- | --- |
| `dsh-session-archive` | 全量会话集中视图：按状态（全部/未归档/已归档）、工作区、标题/ID 搜索、最后活动/归档时间排序；批量归档/恢复/物理删除；可选的"按最后活动时间自动归档"与"按归档保留期自动清理"（默认关闭） | **否**。它是**会话级**（session）管理面板，不改变侧栏工作区树的渲染结构，也没有"活跃/沉默"工作区分段与段级折叠。 |
| `dsh-better-sidebar` | 右侧工作台：资源管理器 / 编辑器 / 终端 / Git / 浏览器，按会话隔离；不接管左侧栏工作区列表 | **否**。README 全文没有工作区级分组/折叠能力。 |
| `dsh-remote-web-ui` | 移动端有独立的"工作区列表"页，但只是平铺列表 | **否**。 |

**可借鉴的设计**（不是现成功能）：
- `dsh-session-archive` 的 `autoArchiveDays` 默认 **7 天**，按**最后活动时间**（不是创建时间）判定——与本需求"7 天阈值 + 最新会话活动时间"的口径完全一致，说明默认值选择是同生态的共识。
- 它把阈值做成 `settings.section` 表单（1–3650，越界不保存 + 校验提示）。本需求按用户决定**不做设置页面**，只在 profile 配置里给键，属于有意简化。

### 2.2 右侧预览可以编辑

两个已安装实现（本机 `~/.dsh/profiles/web/node_modules/`）：

| 实现 | 版本 | 编辑能力（来自其 README） |
| --- | --- | --- |
| `dsh-better-sidebar` | 顶层 0.18.0 / 聚合包内嵌套 0.15.2 | CodeMirror 编辑器、预览↔编辑切换、`Ctrl/Cmd+S` 保存、dirty 标记、mtime 冲突检测、28+ 语言高亮、图片/Markdown(含 Mermaid)/HTML/PDF 预览、Git 真 diff + 暂存/提交/还原 |
| `@linxin666/dsh-client-ui-aionui-panel` | 0.3.6（随 `@linxin666/dsh-web-ui-all@0.3.6` 装入） | Explorer（文件树 + 文件名搜索 + Git 变更 stage/unstage/discard）+ Preview（10+ 格式多 tab）+ 分屏编辑与保存（mtime 冲突检测） |

**重要事实**：仓 A 的 `packages/AGENTS.md` 已声明 `dsh-aionui-panel` 被**彻底移除**（包、聚合行、内嵌设置卡与文档引用均已清理），右侧面板改由 `dsh-better-sidebar` 提供。所以：
- 仓 A 的**当前形态**里，右侧面板 = better-sidebar（第三方，非本仓）；
- 本机之所以还有 aionui-panel，是因为装的是较早的 `@linxin666/dsh-web-ui-all@0.3.6`；
- 两者有**互斥机制**：better-sidebar 读取 aionui-panel 设置命名空间里的"提供方选择"，选 aionui 时整个 better-sidebar 不挂载。

**对本需求的影响**：本需求只动左侧栏的工作区列表渲染，与右侧面板（无论是 better-sidebar 还是 aionui-panel）**没有插槽或 DOM 冲突**。不需要为它们做适配，但也不应该去碰右侧面板相关文件。

### 2.3 DSH 客户端兼容性

本机实测版本：

| 项目 | 版本 | 备注 |
| --- | --- | --- |
| 桌面客户端外壳 | `44.0.0`（nightly 通道） | `resources/app-update.yml` 指向 `dsh-desk/win-x64` nightly |
| DSH SDK / 宿主 | `@deepseek-ai/dsh` **0.1.0-rc.8** | 与 `dsh-client-ui-workspace` 等包同版本 |
| 本需求要改的包 | `@deepseek-ai/dsh-client-ui-workspace` **0.1.0-rc.8** | 打包文件 `lib/client.js`（2435 行） |

生态声明的兼容门槛：

| 插件 | 声明 | 与本机 rc.8 的关系 |
| --- | --- | --- |
| `dsh-better-sidebar@0.18.0` | 只支持 DSH **0.1.2-rc.1+**，明确"不再支持 0.1.0-rc.8 ~ 0.1.1-rc.2" | **不兼容**。rc.8 用户被指引固定装 `0.17.1` |
| `dsh-better-sidebar@0.15.2`（聚合包内嵌套的实际版本） | 0.1.0-rc.x 线 | 与 rc.8 相配 |
| `@linxin666/dsh-client-ui-aionui-panel@0.3.6` | `dsh.engines.dsh: >=0.1.1-rc.1` | 声明下限高于 rc.8，但本机在跑 |
| `@linxin666/dsh-web-ui-all@0.3.6` | `dsh.engines.dsh: >=0.1.1-rc.1` | 同上 |

**两条对本需求有实际影响的结论**：

1. **一旦 DSH 升到 0.1.2-rc.1+，`dsh-client-ui-workspace` 会被整体替换**，我打在 `lib/client.js` 里的补丁会**全部丢失**。
   → `mods/active-workspaces/` 里的**重放脚本不是可选项，是必需项**；且要在补丁里留版本号锚点，升级后先比对再重放。
2. **升级还有连带风险**：官方包升级后 `lib/client.js` 的内部结构（`deriveGroups` / store / `SessionRow` 的代码形态）可能变化，纯文本锚点补丁会失效。所以补丁脚本应当**先校验锚点存在**，锚点缺失时明确报错而不是静默打歪。
3. 本机 `@deepseek-ai/dsh-client-ui-primitives` 的 junction 指向 `D:\software\DeepseekHarness\node_modules\@deepseek-ai\dsh-client-ui-primitives`，而该目录**不存在**（断链）。不影响本需求（`client.js` 里对 primitives 的引用由宿主模块系统解析），但如果将来要做"另写插件"路线，需要先把这个链路理清。

---

## 3. 对原方案的影响

| 原方案条目 | 是否调整 |
| --- | --- |
| 侧栏活跃/沉默分组 + 段级展开收起 | **保留**，生态无现成能力 |
| 月亮/太阳 hover 钉住 + 自动解除 | **保留**，生态无对应概念 |
| 7 天阈值可配 | **保留**；默认值与 `dsh-session-archive` 的 `autoArchiveDays=7` 巧合一致，作为默认值的旁证 |
| 就地改官方 `dsh-client-ui-workspace` | **保留**；这正好绕开"新插件要重写整个工作区树+行渲染"的成本，也避免与 better-sidebar 的服务契约纠缠 |
| 右侧可编辑预览 | **不在本需求范围**（原方案也没打算做）；本机已由 better-sidebar / aionui-panel 覆盖 |
| 重放脚本 | **升级为必需交付物**，且必须带锚点校验 |
| 与右侧面板的关系 | **明确不做适配**，只保证不碰相关文件 |

## 4. 参考链接

- [zhu1090093659/dsh-web](https://github.com/zhu1090093659/dsh-web)
- [DamonKoy/dsh-web-ui](https://github.com/DamonKoy/dsh-web-ui)
- [omdsh-dev/DSH-better-sidebar](https://github.com/omdsh-dev/DSH-better-sidebar)
- [dsh-session-archive 说明](https://github.com/zhu1090093659/dsh-web/tree/dev/packages/dsh-session-archive)
