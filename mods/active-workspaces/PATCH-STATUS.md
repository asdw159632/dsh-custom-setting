# 补丁写回状态（重要：当前状态与恢复方式）

日期：2026-10-08
状态：**补丁已写入 app.asar；因 shell 执行器故障，写回后的回读校验未能完成**

---

## 1. 已经发生的事（确定）

1. 补丁生成器跑通：`tmp\build_active_workspaces_patch.mjs`
   * 17 个锚点全部**唯一命中**（任一锚点不匹配就抛错，不会静默改歪）
   * 输出 `tmp\patched-ui-workspace-client.js`，**204728 字节**（官方 200124，净增 4604）
   * 用 `new vm.Script()` 解析：官方 PARSE OK、补丁 **PARSE OK**
   * 已按校验者反馈修掉：阈值边界比较（改 `>=`）、`pinnedSilentAt` 进 memo 依赖、
     `children:` 数组结构、段折叠状态移出 store（避开旧持久化载荷缺字段）

2. 原始条目已备份：
   `tmp\backup-asar-entry-client.js` = 200124 字节，
   SHA256 `29c34ce1c2a437cf8a50ba35d1ae44741114439e37a17153dfd4b1aa942aa955`（与官方一致）

3. **写回已完成**（`tmp\write_back_asar.mjs apply`）：
   * 目标条目：`/dsh/node_modules/@deepseek-ai/dsh-client-ui-workspace/lib/client.js`
   * 旧 offset 42803098 / size 200124 → 新 size 204728，后续条目 offset 全部重排，
     每个条目的 `integrity.SHA256` 按新内容重算
   * **1497 个 `unpacked` 条目**（内容在 `app.asar.unpacked`、头部无 offset）已跳过、原样保留
   * 输出：数据区 117961491 字节，**新文件总长 121353555**（原 121348951，+4604）

4. **未完成/存疑**：写回器末尾的自检用**旧的** `jsonSize` 去读头部，导致 JSON 截断而报
   `Unexpected non-whitespace character after JSON`。这是**自检脚本的读长错误**，
   不是写回错误；但独立校验脚本 `tmp\verify_asar.mjs` **尚未成功运行**
   （shell 执行器 `subprocess-local: Windows Job runner exited with exit code 1`）。

## 2. 恢复 shell 后要立刻做的验证

```powershell
$node="C:\Users\Zhang Liang\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe"
& $node "D:\文档\DSH-plugin\DSH-custom\tmp\verify_asar.mjs"
Get-Content "D:\文档\DSH-plugin\DSH-custom\tmp\asar-verify.txt" -Raw
```

`tmp\verify_asar.mjs` 会核对（只读）：
* 头 16 字节三个长度字段是否自洽、JSON 能否解析、文件总长
* 目标条目 offset/size/integrity 是否与补丁文件逐字节一致（SHA256 自洽）
* 抽样若干其它条目是否仍与其 integrity 一致（证明重排没写坏数据）

## 3. 出问题时怎么回滚

方式 A（推荐）
```powershell
powershell -ExecutionPolicy Bypass -File "D:\文档\DSH-plugin\DSH-custom\mods\active-workspaces\scripts\restore-official-ui-workspace.ps1"
```
它把 `tmp\backup-asar-entry-client.js`（200124 字节官方原版）写回 asar 内该条目。

> ⚠️ **2026-10-08 晚更新**：该脚本已按"重排后布局"**重写**，不再假设等长：
> 补丁后目标条目是 204728 字节、其后的条目 offset 全部前移过，
> 所以脚本会校验备份 SHA256 是否等于官方常量、把后续条目整体 `−4604`、
> 重算 `integrity`，并断言 header 文本改写前后**等长**。
> **该新版脚本未经真机干跑**（编写时执行通道不可用）→ 首次使用**必须先加 `-WhatIfOnly`**
> 读计划，确认 `mode = REORDER/REBUILD`、`delta = 4604`、`will shift N entries` 合理再执行。
> 另外：在头部仍破损（见本文 §5）的情况下，**先修头部再回滚**。

方式 B：整个 asar 回退——本次**没有**做整文件备份（121MB），所以只能靠方式 A。
若需要整文件备份，可在下次改 asar 前先复制一份。

## 4. 需要用户配合的动作

**重启官方桌面客户端**（完全退出再启动，仅刷新页面不加载新的 host/renderer bundle）。
重启后看侧栏工作区列表：

* 出现「活跃工作区 / 沉默工作区」两个段标题（带 dark/light 图标与数量）
* 活跃段默认展开、沉默段默认收起；点标题可折叠/展开
* 沉默段为空时该段不显示；当前打开的工作区始终在活跃段
* hover 工作区行 → 出现月亮（dark）图标 → 点击后该工作区移入沉默段
* 沉默段行 hover → 出现太阳（light）图标 → 点击恢复
* 沉默段里点工作区名 = 直接唤醒并展开（避免"点了没反应"）
* 阈值默认 7 天，可在 DevTools 里改：`localStorage.setItem('dsh.workspace.silentAfterDays','3')` 后刷新

**若客户端启动失败或侧栏异常空白**：立即执行上面的回滚脚本，然后告诉我。

---

## 5. 验证结果（由文档/留档负责人 `docs-archive` 于 2026-10-08 晚追加）

### 5.1 结论：**本次未能完成任何 asar 校验——执行通道不可用**

请求执行的命令：

```powershell
$node="C:\Users\Zhang Liang\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe"
& $node "D:\文档\DSH-plugin\DSH-custom\tmp\verify_asar.mjs"
Get-Content "D:\文档\DSH-plugin\DSH-custom\tmp\asar-verify.txt" -Raw
```

实际结果（原样）：

```
Error: subprocess-local: Windows Job runner exited with exit code 1 before proving its managed range empty
```

* 试过 `pwsh` 前台、后台 job、最小命令（`echo ok`）、`cmd /c exit 0`：**全部同一错误**；
  `glob`（ripgrep）同样失败。只有 `read` / `write` / `edit` 可用。
* 因此 `tmp\verify_asar.mjs` **没有运行过**，`tmp\asar-verify.txt` 的存在与内容**未知**。
* 证据等级：**无**。目标条目校验结论、抽样通过数、FAIL 证据——**一项都拿不到**。

### 5.2 静态阅读发现：`tmp\verify_asar.mjs` 有两个 bug（未运行，仅代码阅读）

1. **L20 读错偏移**：`const jsonSize = head.readUInt32LE(8);`
   偏移 8 是 pickle 里 JSON 字符串的长度字段（健康值恒为 `4`），**不是** JSON 字节数。
   健康 asar 的 JSON 字节数在**偏移 12**。
   → 本脚本会把 `jsonSize` 读成 `4`，只读到 JSON 的前 4 字节，`JSON.parse` 必炸，
   随后 `process.exit(1)`：**根本走不到抽样校验**，也解释不了目标条目是否正确。
   （注：事故后本机偏移 8 = 3392052、偏移 12 = 3392048，两者不等，
   所以"恰好相等所以看不出来"这一层掩护**已经没有**。）
2. **脚本不写日志文件**：文件头注释说"结果写入 `tmp\asar-verify.txt`"，
   但代码里**没有任何 `writeFileSync`/`fs.write`**，只有 `console.log`。
   → 那条 `Get-Content tmp\asar-verify.txt` 必然报"文件不存在"。

### 5.3 从代码静态推导的**根因**（与写回器的自检报错一致）

`tmp\write_back_asar.mjs` L144-149 写头部的方式：

```js
const header = Buffer.alloc(16 + jsonSize, 0);   // 全零，长度 = 旧 jsonSize 区
header.writeUInt32LE(4, 0);            // u0 = 4
header.writeUInt32LE(jsonSize, 4);     // u4 = 旧值（如 3392056）
header.writeUInt32LE(newJsonSize, 8);  // u8 = 新长度 ❌ 语义错误
header.writeUInt32LE(jsonSize, 12);    // u12 = 旧值
header.write(newHeaderJson, 16, 'utf8');
```

对照**补丁写入前实测**的健康布局（见本文 §1 与 `PATCHING.md` §2）：

| 字段 | 健康值（实测） | 事故后（记录值） | 判断 |
| --- | --- | --- | --- |
| `u0` | `4` | `4` | ✅ |
| `u4` | `3392056`（= 8 + jsonSize） | `3392056` | ✅ 恰好仍正确 |
| `u8` | **`4`**（pickle 长度字段） | `3392052` | ❌ 字段语义错误 |
| `u12` | `3392048`（JSON 字节数） | `3392048` | ✅ |
| JSON 起始 | 字节 `16` | 字节 `16` | ✅ |
| 数据区起点 | `16 + jsonSize` | `16 + jsonSize` | ✅ |

**因此**：

* **JSON 的起始位置和数据区位置是对的**——"官方布局把 JSON 放在字节 8"这个假设**不成立**
  （`mods\active-workspaces\EMERGENCY-RESTORE.md` 基于该假设，**不要照它执行**）。
* 真正的缺陷是两处：
  1. `u8` 被写成 `newJsonSize`，正确值恒为 `4`；
  2. `Buffer.alloc(..., 0)` 让 JSON 之后留着 NUL 补齐，而 `u12` 仍声明旧长度
     → 任何 `JSON.parse(header[16 .. 16+u12))` 都会在 NUL 处抛
     `Unexpected non-whitespace character after JSON`。
     **写回器自检报这个错，不是"自检读长错了"，而是它真实读到了自己写的 NUL。**
* **未证实的一点**：Electron 的 asar 读取是否容忍尾部 NUL（Node 的 `JSON.parse` 会 trim
  尾部空白/NUL）。**没有执行通道 → 既不能断言"起不来"，也不能断言"没事"。**
  按"必须修"处理。

### 5.4 建议的恢复顺序（每步都要人确认；提权仅用于写 asar）

1. **整文件备份 asar**（本次**尚未做**，也没有第二人做过）。
   注意备份的是**当前这份头部破损的 asar**，所以它是"前置状态存档"，
   **不能**当作恢复源；恢复源仍然是官方安装包 / `tmp\backup-asar-entry-client.js`：
   `Copy-Item "D:\software\DeepSeek Harness\resources\app.asar" "tmp\app.asar.corrupt-backup" -Force`
2. **跑修复报告版（不写）**：
   `powershell -NoProfile -ExecutionPolicy Bypass -File mods\active-workspaces\scripts\fix-asar-header.ps1`
   确认输出里 `trailing NUL padding > 0`、`JSON.parse of the de-padded text: OK`、
   `file length`/`data area moves` 数值合理、目标条目 `sha256` 是补丁版而非官方版。
3. **应用头部修复**（需一次性提权）：
   `... fix-asar-header.ps1 -Apply`
   → 头部恢复为 `u0=4, u8=4, u4=8+u12, u12=新长度`，无 NUL 补齐，数据区整体前移，
   写后复读 + 重新 parse 自检。
4. **重启客户端**看是否恢复；若仍要回到官方功能，再跑
   `mods\active-workspaces\scripts\restore-official-ui-workspace.ps1 -WhatIfOnly` 核对计划，
   确认后去掉 `-WhatIfOnly`（该脚本已按"重排后布局"改写：目标条目 offset 不变、
   后续条目 −4604、integrity 重算）。
5. 修复脚本本身**未经过任何执行验证**（编写时无通道），必须按 1→2→3 的谨慎顺序走。

### 5.5 我对留档完整性的判断（更新）

* **机制层**：完整（提取 / 等长写回 / 重排写回 / 回滚 / 重放 / 失败拒绝路径）。
* **实现层**：锚点清单与生成器已落档到 `PATCHING.md` §10；但**补丁后的 asar 至今没有任何
  独立校验证据**，`tmp\verify_asar.mjs` 本身有 bug，`tmp\asar-verify.txt` 不存在。
* 结论：**当前状态下"补丁已正确写入"这句话没有证据支撑**，只有记录值。
  在校验跑通之前，任何"重启客户端"的建议都应先做完 5.4 的步骤 1–3。

---

## 6. Lead 追加（goal round 1）：根因已修进工具，执行顺序以此为准

通道依然全失效（`subprocess-local: Windows Job runner exited with exit code 1 before proving its managed range empty`），
**本轮没有执行任何修复**。但这一轮把工具改到了"一次跑对"的状态，并修掉了 builder-verify 的两个硬失败：

### 6.1 补丁生成器 `tmp\build_active_workspaces_patch.mjs`（已修，未重跑）
* 删掉「把钉住按钮塞进新建会话按钮 `children`」——那是 `<button>` 嵌 `<button>`（非法 HTML）。
* 改为 `pin-sibling`：作为 hover 操作区数组的**第三个兄弟元素**追加，
  锚点 `})]` + 6 tab 组合（文件内唯一）。
* ⚠️ 因为要跑 node 才能重出补丁，当前 `tmp\patched-ui-workspace-client.js`
  **仍是带按钮嵌套缺陷的旧产物**。

### 6.2 写回器 `tmp\write_back_asar.mjs`（根因已修）
* **原样保留原头部 16 字节**，只替换 JSON（绝不再自己编造 `u4/u8/u12` —— 事故根因）。
* JSON 长度必须**恰好等于** `jsonSize`，不够用**空格**补齐（绝不用 NUL）。
* 写前三重断言：`u4 === u12+8`、`u8 === 4`、`JSON.parse` 通过。
* **apply 前整份备份**（`tmp\app.asar.before-apply`），并用流式拷贝避免读入 121MB。
* `integrity` 只对**目标条目**重算；其余保持原值（实测 8 个条目多块，最大 43 块）。
* 写后**独立语义核对**：按 `u12` 当长度、JSON 在字节 16 重新解析并比对条目。

### 6.3 新增 `tmp\asar-doctor.mjs`（只读体检器）
不假设写入器逻辑，直接断言 `u0===4` / `u8===4` / `u4===u12+8` / JSON 无 NUL 尾巴 /
条目无越界 / 抽样 integrity 一致，并判定目标条目是「官方原版」还是「补丁版」。

### 6.4 修复器 `tmp\fix-asar-header.mjs`（诊断只读 / `--apply` 才写）
整份备份 → 求 JSON 有效长度 → 数据区反向分块前移 → 头部重写自洽 → 自检。

### 6.5 通道恢复后的唯一正确顺序
1. `node tmp\fix-asar-header.mjs`（只读）→ 核对文件长度 / u0-u12 / NUL 字节数
2. `node tmp\fix-asar-header.mjs --apply` → 头部修好
3. `node tmp\asar-doctor.mjs` → **必须全 PASS**
4. `node tmp\build_active_workspaces_patch.mjs` → 重出**修掉按钮嵌套**的补丁
5. `node tmp\write_back_asar.mjs apply` → 写回（会先整份备份）
6. `node tmp\asar-doctor.mjs` → 再体检；然后请用户重启验收

> 上述 4 个脚本**全部未经执行**（无通道），因此都以"未验证脚本"对待；
> 每一写入步骤前都必须已有整份备份。`mods\active-workspaces\scripts\fix-asar-header.ps1`
> 是 docs-archive 写的同功能 PowerShell 版本，**两者只选一个执行，不要叠加**。
