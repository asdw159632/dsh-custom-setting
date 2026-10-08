# 2026-10-08 需求 `active-workspaces`：asar 补丁勘查与留档（文档与恢复脚本）

阶段：**文档 + 恢复脚本**（不含实际补丁写入）
负责人角色：文档与留档（`docs-archive`）
关联：[REQUIREMENTS.md](../mods/active-workspaces/REQUIREMENTS.md)、
[COMPARISON.md](../mods/active-workspaces/COMPARISON.md)、
[PATCHING.md](../mods/active-workspaces/PATCHING.md)、
[README.md](../mods/active-workspaces/README.md)

> 本文所有产物路径均为**相对工作区根** `D:\文档\DSH-plugin\DSH-custom` 的路径。

---

## 1. 本次做了什么

| 时间（顺序） | 动作 | 结果 |
| --- | --- | --- |
| 1 | 读 `mods/active-workspaces/REQUIREMENTS.md`、`COMPARISON.md`、`INSTALL-DSH-WEB.md`、`memory/MEMORY.md` | 拿到需求 16 条决策、生态结论、版本口径（客户端宿主 0.2.0-rc.2） |
| 2 | 只读探测桌面客户端 asar 的 header 与目标条目 | 拿到全部实测数值（见 §3） |
| 3 | 用 `tmp/official-ui-workspace-client.020rc2.js` 与 asar 内字节逐字节 + SHA256 比对 | **完全一致** → 该副本可作补丁基线 |
| 4 | 读 `client.js` 中与需求相关的既有实现位置（store / deriveGroups / 行渲染 / 插槽） | 得到坐标表，写入 README §3 |
| 5 | 写 `mods/active-workspaces/PATCHING.md` | asar 结构速查 + 提取/打补丁/回滚/升级重放手册 |
| 6 | 写 `mods/active-workspaces/README.md` | 落地总览（目标、行为清单、文件、验证、风险） |
| 7 | 写 `mods/active-workspaces/scripts/restore-official-ui-workspace.ps1` | 一键回滚脚本，已在真机干跑验证 |
| 8 | 写本日志 | — |

**没有做的事**（按职责边界）：没有写 asar、没有改 `tmp/**`（只读）、没有改
`REQUIREMENTS.md` / `COMPARISON.md` / `INSTALL-DSH-WEB.md` / `memory/MEMORY.md`。

---

## 2. 关键决策与理由

1. **把 asar 补丁手册写成"数值实测 + 可运行片段"**，而不是泛泛的结构说明。
   理由：真正会踩的坑都是数值级的（offset 相对起点、`offset` 是字符串、
   等长约束），写成可复制片段才能在下一次升级后 5 分钟内复核完。
2. **手册里区分"契约"与"实现"**：补丁生成器本身（锚点清单）尚未落档，
   我在 PATCHING.md §10 显式列为「待确认」，只写下它**必须**满足的契约
   （每锚点唯一性断言、补丁前后等长断言、缺失即报错中止）。
   理由：文档不能假装知道它不知道的东西，否则下次维护会照着错的走。
3. **恢复脚本只做一件事**：把备份字节写回 asar 同一位置。
   不做"顺便重新提取官方文件"之类的聪明事（那会用网络/安装包，超出可验证范围）。
4. **恢复脚本自带三道闸**：
   * 备份大小必须等于 asar 条目大小，否则拒绝执行；
   * 写前打印目标条目 `offset` / `size` / 当前 SHA256；
   * 写后重新读取并比对 SHA256，同时断言 offset/size 未变。
   理由：asar 是发行产物，写错一次就可能整包不可用；宁可拒绝执行也不猜。
5. **脚本全 ASCII + UTF-8 with BOM**：中文注释在 PS 5.1 下有 GBK 解析风险
   （`memory/MEMORY.md` 已记录过这个坑），干脆全英文注释并加 BOM，
   两个风险一起消掉。
6. **`README.md` 明确标注状态是"实现进行中"**，验收清单用待勾选框，
   避免把"计划行为"误读成"已实现"。

---

## 3. 实测数值（只读探测的结果）

探测方式：Node 读 `readUInt32LE(4/12)` 取 header 尺寸，遍历 `files` 树取条目，
切出字节后与工作区副本比对。**未写入任何数据。**

| 项 | 值 |
| --- | --- |
| asar | `D:\software\DeepSeek Harness\resources\app.asar` |
| asar 大小 | `121348951` 字节 |
| `headerSize` / `jsonSize` | `3392056` / `3392048` |
| payload base（内容区起点） | `3392064` |
| 条目 | `/dsh/node_modules/@deepseek-ai/dsh-client-ui-workspace/lib/client.js` |
| 条目 `offset`（相对）/ 绝对 | `42803098` / `46195162` |
| 条目 `size` | `200124` |
| 条目 SHA256 | `29c34ce1c2a437cf8a50ba35d1ae44741114439e37a17153dfd4b1aa942aa955` |
| 包版本 | `@deepseek-ai/dsh-client-ui-workspace@0.2.0-rc.2` |
| 与工作区副本比对 | `Buffer.compare === 0`，SHA256 相同 |

`lib/` 目录下同层还有 `index.js`（本次改造不动它）。

### 顺带发现/踩到的坑

* **`entry.offset` 在 header JSON 里是字符串**。第一次探测时写
  `offset + size` 直接得到字符串拼接结果（`"42803098200124"`），
  切出的切片长度为 `0`、md5 是空串的 `d41d8cd9…`。已把这条写进 PATCHING.md §2。
* **条目带 `integrity`（SHA256 单块）字段**。本次改动会使它失配；
  普通 `resources/app.asar` 下 Electron 不使用它做校验，但**未实证**，
  已列入 PATCHING.md §10 待确认。
* header 顶层只有 `files` 一个键，载荷区到文件尾还有约 74.9 MB 的其他内容
  （`payload end 46395286` vs 文件尾 `121348951`），说明 asar 里还有大量其他包。

---

## 4. 恢复脚本的验证（真机干跑）

脚本：`mods/active-workspaces/scripts/restore-official-ui-workspace.ps1`
调用：`powershell -NoProfile -ExecutionPolicy Bypass -File mods\active-workspaces\scripts\restore-official-ui-workspace.ps1 -BackupPath <path> -WhatIfOnly`

| 用例 | 输入 | 期望 | 结果 |
| --- | --- | --- | --- |
| 干跑（备份 = 官方原版） | `tmp` 下同长度副本 | 打印 BEFORE 全字段并提示"已经一致，无需恢复" | ✅ 打印 `offset 42803098` / `size 200124` / 两侧 SHA256 相同，`exit 0` |
| 干跑（备份 = 同长度但已改动） | 翻转 1 字节的副本 | 打印两侧 SHA256 不同、进入 `WhatIfOnly` 分支不写入 | ✅ 两侧 hash 分别为 `29c34ce1…` / `09b61ecb…`，`exit 0` |
| 大小不匹配 | 100 字节文件 | 拒绝执行 | ✅ `REFUSING TO WRITE: backup size (100) != asar entry size (200124)`，`exit 1` |
| 默认备份发现 | `tmp\backup-asar-ui-workspace-*.js` 尚不存在 | 明确报错并提示显式传参 | ✅ 报 `no backup found in … Pass -BackupPath explicitly.`，`exit 1` |
| 语法/编码 | `.ps1` 加 UTF-8 BOM 后 | PS 5.1 解析通过 | ✅ `Parser::ParseFile` 零错误，BOM = `EF BB BF` |

> 干跑全部使用 `-WhatIfOnly` 或触发拒绝分支，**没有发生对 asar 的任何写入**。
> 测试用的临时副本已删除（`tmp/scratch-*` 计数 0）。

---

## 5. 问题与遗留

1. **补丁生成器与锚点清单未落档**。我只能写下它必须满足的契约。
   → 需要 Lead 在实现完成后补：生成器路径、锚点文本清单、每个补丁点的字节区间。
   已列入 `PATCHING.md` §10 第 1、2 条。
2. **`integrity` 是否需要同步更新**未实证。列入 §10 第 3 条。
3. **`persist` 键是否升版**（现为 `dsh.workspace.view.v5`）属于实现决策，未定。
4. **刷新是否足够让 renderer bundle 生效**未实测（推断足够）。
5. **恢复脚本依赖 `tmp/` 备份，而 `tmp/` 被 `.gitignore` 忽略** →
   备份不随仓库同步，跨机恢复需要重新从官方安装包取同版本 `client.js`。
   已在 `README.md` §5 第 7 条写明。
6. 发现一个需求文档里的**过时坐标**：`REQUIREMENTS.md` §6 写的包版本是
   `0.1.0-rc.8`、行号按 2435 行计，而客户端实际的 0.2.0-rc.2 版本是 **4425 行**。
   `INSTALL-DSH-WEB.md` §1 已纠正过版本口径，但 `REQUIREMENTS.md` §6 未同步。
   **我没有改 `REQUIREMENTS.md`**（不属我的写入范围），在此汇报给 Lead。
   正确的坐标表已写入 `README.md` §3。

---

## 6. 下一步

1. Lead：实现 `client.js` 等长补丁 + 补丁生成器，并把生成器与锚点清单落档。
2. Lead：按 `PATCHING.md` §5 写回 asar（需一次性提权），跑写后校验。
3. 之后：按 `README.md` §4.2 / §4.3 走验收与回归，结果补进本日志或新开一篇。
4. 若出现异常：用
   `mods\active-workspaces\scripts\restore-official-ui-workspace.ps1` 回滚。
