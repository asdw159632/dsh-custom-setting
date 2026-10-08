# 需求：侧栏「活跃工作区 / 沉默工作区」分组

状态：**需求已确认；asar 补丁实现进行中**（2026-10-08）
涉及目录：`mods/active-workspaces/`
实现层：就地改桌面客户端 app.asar 内的官方插件 `@deepseek-ai/dsh-client-ui-workspace@0.2.0-rc.2`

---

## 1. 一句话目标

把 DSH 左侧栏「按工作区分组」的工作区列表拆成 **活跃工作区** 与 **沉默工作区** 两段，
两段各自可展开/收起，并允许用行内按钮手动把某个工作区钉进/移出沉默段 ——
让侧栏只突出当前在推进的需求。

需求原文与逐条决策见 [REQUIREMENTS.md](REQUIREMENTS.md)；
与社区插件生态的对比（结论：生态空白，必须自研）见 [COMPARISON.md](COMPARISON.md)；
asar 补丁怎么打、怎么回滚、升级后怎么重放见 [PATCHING.md](PATCHING.md)。

---

## 2. 最终行为清单

### 2.1 判定规则

对每个工作区 `W`：

```
silent(W) =
       W 被手动钉为沉默（pinnedSilentAt(W) 存在）
   且 W 的活动时间 <= pinnedSilentAt(W)      // 钉住之后没有新活动
   且 W 不是当前打开的工作区

silent(W) 为假 → 活跃段
```

* `W 的活动时间` = 该工作区下所有可见会话 `updatedAt` 的最大值；
  **一条会话都没有时取工作区创建时间**（`group.createdAt`）。
* **当前所在工作区始终进活跃段**（`containsCurrent`），优先级高于钉住与时间判定。
* 阈值默认 **7 天、可配置**，键名实现时定（候选 `silentAfterDays`），
  写在 profile 的 `cordis.patch.yml` 插件 config 里；**不做设置页面**。
* 「恢复」（点太阳）= 删除 `pinnedSilentAt(W)`，回到纯自动判定。
  若该工作区本来已超阈值，它会**落回沉默段** —— 这是预期行为，不是 bug。
* 有比 `pinnedSilentAt(W)` 更新的会话活动 → 钉住自动失效，回到自动判定。

### 2.2 分段渲染

* 两个段各有可点击标题行，点击切换展开/收起。
* **默认：活跃段展开、沉默段收起。**
* **空分组整段隐藏**（不留空标题）。
* 段级展开状态**沿用侧栏既有的持久化机制**（与工作区条目展开状态同一 store）。
* 沉默段内的工作区展开后，会话列表行为与今天**完全一致**
  （会话行、拖拽、溢出「展开更多」、归档筛选全部保留）。

### 2.3 手动钉住入口

* 位置：工作区行**已有的 hover 操作区**里，追加一个图标按钮。
* 语义：**单按钮切换**。
  * 活跃段 → 月亮图标「标记沉默」，点击后该工作区立即移入沉默段；
  * 沉默段 → 太阳图标「恢复」，点击后按 §2.1 重新判定。
* 按钮带 `aria-label` 与 tooltip，文案走插件既有 i18n，**中英文都要**。

### 2.4 作用范围（明确不动的东西）

* 只改侧栏「按工作区分组」的列表。
* **搜索结果、扁平列表、工作区选择弹窗（`WorkspacePicker`）保持原样。**
* 不改工作区重命名 / 删除 / 拖拽排序等既有能力。
* 不做灰化、降透明度等视觉弱化（两段样式一致）。
* 不新增 DSH 设置页面。
* 不碰右侧面板（better-sidebar / aionui-panel）相关文件。

---

## 3. 涉及文件

| 文件 | 角色 | 谁维护 |
| --- | --- | --- |
| `D:\software\DeepSeek Harness\resources\app.asar` | **被改的发行产物**（工作区外，需一次性提权） | Lead |
| `/dsh/node_modules/@deepseek-ai/dsh-client-ui-workspace/lib/client.js` | asar 内的实际改动对象，**200124 字节**，必须等长替换 | Lead |
| `mods/active-workspaces/REQUIREMENTS.md` | 需求与逐条决策 | Lead |
| `mods/active-workspaces/COMPARISON.md` | 生态对比 | Lead |
| `mods/active-workspaces/INSTALL-DSH-WEB.md` | dsh-web 全家桶安装记录（前置、与本需求解耦） | Lead |
| `mods/active-workspaces/PATCHING.md` | asar 补丁 / 回滚 / 重放手册 | 本文档作者 |
| `mods/active-workspaces/README.md` | 本文件：落地总览 | 本文档作者 |
| `mods/active-workspaces/scripts/restore-official-ui-workspace.ps1` | 一键回滚到官方 `client.js` | 本文档作者 |
| `logs/2026-10-08-active-workspaces-sidebar.md` | 工作日志 | 本文档作者 |
| `tmp/official-ui-workspace-client.020rc2.js` | 官方原版基线副本（工作区副本，仅供比对） | Lead |
| `tmp/backup-asar-ui-workspace-*.js` | 打补丁前的 asar 内原始字节备份（回滚用） | Lead |

`client.js` 里与需求直接相关的既有位置（版本 `0.2.0-rc.2`，共 4425 行）：

| 位置 | 作用 |
| --- | --- |
| `createWorkspaceViewStore()`（~L658） | 侧栏视图 store，已持久化 `groupExpansion`，`persist: "dsh.workspace.view.v5"` |
| `deriveGroups()`（~L484） | 工作区分组派生，产出 `groups[]`（含 `containsCurrent`、`createdAt`） |
| `SessionTree`（~L2316） | 树渲染与展开状态处理 |
| `renderGroup`（~L2440 起） | 逐个工作区段的渲染（`groupSection`） |
| `ProjectRowItem`（~L1270） | 工作区行 + hover 操作区（重命名 / 删除 / 新建会话）→ 月亮/太阳按钮加在这里 |
| `WorkspaceBrowser`（~L2793） | 浏览器主组件 |
| `ctx.slots.inject("sidebar.workspaces", …)`（~L4299） | single 插槽注册，正是"外部插件无法扩展"的原因 |

> 行号是 `0.2.0-rc.2` 的坐标，**升级后会漂移**；补丁以文本锚点为准，不以行号为准。

---

## 4. 如何验证

### 4.1 前置

1. 补丁已按 [PATCHING.md](PATCHING.md) §5 写入并通过写后校验；
2. 客户端**刷新页面**（无效再彻底重启）。

### 4.2 验收清单

- [ ] 侧栏出现两段标题，**活跃段默认展开、沉默段默认收起**。
- [ ] 沉默段为空时，**看不到**沉默段标题（活跃段为空同理）。
- [ ] 当前所在的工作区**永远在活跃段**，即使它已超阈值或被钉为沉默。
- [ ] hover 活跃段的工作区 → 出现月亮按钮；点击后该工作区**立即移入沉默段**。
- [ ] hover 沉默段的工作区 → 出现太阳按钮；点击后按规则重新判定。
- [ ] 被钉为沉默的工作区产生**比钉住时间更新的会话活动**后，自动回到活跃段。
- [ ] 超过 7 天无活动的工作区自动落到沉默段。
- [ ] 改配置阈值（如改成 1 天 / 30 天）后，分组行为随之变化。
- [ ] **重启 / 刷新页面后，段级展开状态保留。**
- [ ] 沉默段内工作区展开后：会话行、拖拽排序、溢出「展开更多」、归档筛选**均无变化**。
- [ ] **搜索结果、扁平列表、工作区选择弹窗行为无变化。**
- [ ] 月亮/太阳按钮的 tooltip 与 `aria-label` 中英文都正确。
- [ ] 无会话的工作区按**工作区创建时间**参与判定。

### 4.3 回归面（改了官方包，必须一并看）

- [ ] 工作区重命名 / 删除仍可用。
- [ ] 会话新建、拖拽排序、归档仍可用。
- [ ] 侧栏「按会话分组 / 扁平列表 / 搜索」视图切换正常。
- [ ] 浏览器控制台无新增报错（补丁是文本级替换，语法错误会直接白屏）。

---

## 5. 已知限制与风险

1. **asar 补丁不跨客户端升级**：客户端升级会替换 `app.asar`，补丁全部丢失。
   → 必须按 [PATCHING.md](PATCHING.md) §9 用锚点补丁重放；锚点缺失必须**报错中止**，不能静默改歪。
2. **紧耦合官方内部实现**：`deriveGroups` / store / 行渲染都是非公开内部结构，
   补丁与其文本形态绑定（不是 API 绑定）。官方重构即锚点失效。
3. **仅影响桌面客户端**：`dsh web`（profile `web`）加载的是另一套 `0.1.0-rc.8`，
   行为不变；`~/.dsh/profiles/node_modules` 的 junction 也指向那套，**不要顺手改它**。
4. **等长约束**：任何改动若改变文件长度，会让 asar 内后续条目的 `offset` 全部错位。
   补丁生成器必须断言补丁前后长度相等。
5. **条目 `integrity` 字段会失配**：补丁后 header 里记录的 SHA256 不再匹配。
   普通 `resources/app.asar` 布局下 Electron 不据此校验，但本机未实证；
   若出现包校验类报错，先怀疑这里。
6. **持久化键版本**：store 现为 `dsh.workspace.view.v5`。
   新增段级展开状态与沉默钉表的落盘方式（沿用 v5 补默认值 / 升 v6）是实现决策，未定。
7. **回滚手段单一**：依赖 `tmp/backup-asar-ui-workspace-*.js` 备份 + 恢复脚本。
   `tmp/` 被 `.gitignore` 忽略 → **备份不进 git**，只在本机存在。
   若需要跨机恢复，得重新从官方安装包提取同版本 `client.js`。
8. **客户端升级通道**：本机是 nightly 通道（见 [COMPARISON.md](COMPARISON.md) §2.3），
   升级频率可能较高 → 补丁被覆盖的概率不低，重放脚本是必需品而非可选项。
9. **未验证项**：刷新是否足以让 renderer bundle 生效、asar 在客户端运行中是否被文件锁占用 ——
   见 [PATCHING.md](PATCHING.md) §10。

---

## 6. 待办

- [ ] Lead 完成 `client.js` 等长补丁并写回 asar（含补丁生成器与锚点清单落档）。
- [ ] 跑完 §4.2 / §4.3 全部验收项，结果记入日志。
- [ ] 把 §10 的待确认项（尤其补丁生成器与锚点清单）补进 [PATCHING.md](PATCHING.md)。
