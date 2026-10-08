# PATCHING.md — 客户端 app.asar 就地补丁手册

面向对象：未来维护本工作区的自己 / 接手的人。
适用需求：`mods/active-workspaces/`（侧栏「活跃工作区 / 沉默工作区」分组）。
记录日期：2026-10-08。

> **重大状态变更（2026-10-08 晚）：写回方式已从「等长覆盖」改为「带头重排的追加式」。**
> 补丁净增 4604 字节（200124 → 204728），硬压回原长度不可行。
> → **§5 的等长覆盖流程已作废**，现行流程见 **§5b**；现行写回器是 `tmp/write_back_asar.mjs`。
> → §2 里的「等长约束」已不再是硬约束，但仍然是**风险源**（见 §5b 的 offset 重排规则）。
>
> 本手册里标「实测」的数值是在本机真机取到的；标「记录值」的来自 Lead 的生成器/写回器
> 记录，尚未由第二人独立复算。**本手册不把"没跑过"的东西写成"已验证"**。

---

## 1. 为什么必须走 asar 补丁（而不是写一个外部插件）

结论：**外部插件做不到，只能整体替换官方插件的 `lib/client.js`；而"另写一个插件"的成本高到不可接受。**

理由链条：

1. 侧栏的工作区/会话区是一个**名为 `sidebar.workspaces` 的 single 插槽**。
   官方包自己就是用 `ctx.slots.inject("sidebar.workspaces", …)` 把它占掉的，
   `WorkspaceBrowser` 是**该包内部的局部函数，没有 export**（包 `exports` 只暴露
   `lib/index.js` 与 `lib/client.js` 两个入口）。外部插件拿不到这个组件，
   也无法在 single 插槽里与它并存。
2. 官方包对外只开了这些**子插槽**，全部是"往里塞一个动作/一小块 UI"的粒度：
   `sidebar.workspaces.directoryFlow`、`sidebar.workspaces.session.menu.item`、
   `sidebar.workspaces.session.row.action`、`sidebar.session.row.leading`、
   `sidebar.session.row.hover`。
   它们**都不能改变工作区列表的分组结构**。
3. 因此想做「按活跃/沉默两段」的分组，只有两条路：
   * **A. 就地改官方 `lib/client.js`**（本工作区选的路线）；
   * **B. 自己重写整棵工作区树**：工作区行、会话行、拖拽排序、溢出"展开更多"、
     归档筛选、搜索、右键菜单……全部重做，并在 single 插槽里顶掉官方实现。
4. 选 A 的理由：改动面小（分组判定 + 渲染分段 + 一个按钮 + i18n），
   并且**天然保留**拖拽 / 溢出 / 归档筛选 / 搜索等既有行为（需求 §4 要求保留）。
   B 路线的重写量是 A 的十几倍，且要长期跟随官方内部结构变化——不划算。
5. 代价（必须接受）：补丁打在**发行产物**上，客户端一升级就没了 →
   所以「可重放」是硬需求，见 §9。

---

## 2. asar 结构速查

asar（Electron 归档）布局：

```
偏移 0            uint32 LE  = 4            （pickle 的前置长度字段）
偏移 4            uint32 LE  = headerSize    （header 区总长，含下面 8 字节）
偏移 8            uint32 LE  = 4            （json 字符串的 pickle 长度字段）
偏移 12           uint32 LE  = jsonSize      （header JSON 的字节长度）
偏移 16 .. 16+jsonSize-1   header JSON（UTF-8）
偏移 16+jsonSize  内容区起点（payload base）
条目 bytes      = 文件[payloadBase + entry.offset , + entry.size)
```

* **`entry.offset` 是相对内容区起点（payload base）的偏移，不是文件绝对偏移。**
  绝对偏移 = `16 + jsonSize + entry.offset`。
* header JSON 只有两个顶层键：`{"files": { … 目录树 … }}`。
* 目录节点形态：`{ "files": { …子节点… } }`；文件节点形态：
  `{ "size": <字节数>, "offset": "<十进制字符串>", "integrity": {…} }`。
  **注意 `offset` 在 JSON 里是字符串**，做算术前必须 `Number()`，
  否则 `offset + size` 会变成字符串拼接（本手册编写时就踩过：得到 `0` 长度切片）。
* **长度变化 = 必须重排**：所有条目的 `offset` 是**绝对数值**，一旦某个条目的字节长度变化，
  排在它后面的每个条目都要重算偏移、重写 header。
  * 能做到等长替换时，等长替换**仍然是最省事的做法**（见已作废的 §5，思路仍可复用）；
  * 做不到等长时（本需求就是这种情况），必须走 §5b 的"带头重排"：逐个条目搬位置、
    重算 `offset`、重算 `integrity.hash`，并在整文件层面重写。
  → 无论走哪条路，都要**断言目标条目最终长度与你的意图一致**（等长断言 / 新长度断言）。

### 本机实测数值（客户端 `0.2.0-rc.2`，补丁写入**前**，2026-10-08）

| 项 | 值 |
| --- | --- |
| asar 路径 | `D:\software\DeepSeek Harness\resources\app.asar` |
| asar 文件大小 | `121348951` 字节（≈115.7 MiB） |
| `headerSize` / `jsonSize` | `3392056` / `3392048` |
| payload base | `3392064`（= 16 + 3392048） |
| 目标条目路径 | `/dsh/node_modules/@deepseek-ai/dsh-client-ui-workspace/lib/client.js` |
| 目标 `offset`（相对） | `42803098` → 绝对 `46195162`（= 3392064 + 42803098） |
| 目标 `size` | `200124` 字节 |
| 目标 SHA256 | `29c34ce1c2a437cf8a50ba35d1ae44741114439e37a17153dfd4b1aa942aa955` |
| 包版本 | `@deepseek-ai/dsh-client-ui-workspace@0.2.0-rc.2` |
| 同目录兄弟条目 | `client.js`、`index.js` |
| `unpacked` 条目数 | `1497`（内容在 `app.asar.unpacked`，header 里**没有** `offset`） |

> **实测确认**：目标文件的工作区副本与 asar 内字节逐字节相同、SHA256 与 header 记录一致
> （`Buffer.compare === 0`）→ 拿 `tmp/` 里的官方副本当补丁基线是可信的。

### 补丁写入**后**的状态（补丁已生效，`tmp/write_back_asar.mjs` 记录值）

| 项 | 值 |
| --- | --- |
| 目标条目 `size` | `204728` 字节（官方 200124，**净增 4604**） |
| 目标条目 `offset` | 相对值未变：`42803098`（原本就是数据区第一个条目） |
| asar 文件大小 | `121353555` 字节（原 121348951，**+4604**） |
| 数据区长度 | `117961491` 字节（原 117965795，**−3394304**） |
| header `jsonSize` | `3392048`（**未变**，重排后的 JSON 更短，写入器用 NUL 补齐到原长度） |
| `integrity` | 全部数据区条目按新内容**重算**（见 §5b 与 §10） |

> 数据区从 117965795 缩到 117961491，说明**原文件的数据区里有 3394304 字节的间隙**，
> 而重排后是**紧凑排布**。这个差额是记录值、**未由第二人独立复算**（见 §11 待复核）。

---

## 3. 从 asar 提取目标文件（可运行片段）

本机 Node：`C:\Users\Zhang Liang\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe`
（也可用 PATH 上的 `node`）。把下面片段存成 `tmp/extract-asar-client.mjs` 后运行：

```js
import fs from 'node:fs';
import crypto from 'node:crypto';

const ASAR = String.raw`D:\software\DeepSeek Harness\resources\app.asar`;
const ENTRY = ['dsh', 'node_modules', '@deepseek-ai', 'dsh-client-ui-workspace', 'lib', 'client.js'];
const OUT = String.raw`D:\文档\DSH-plugin\DSH-custom\tmp\extracted-client.js`;

const buf = fs.readFileSync(ASAR);

// 1) 读 header 定位
const headerSize = buf.readUInt32LE(4);
const jsonSize = buf.readUInt32LE(12);
const base = 16 + jsonSize;                       // payload base
const header = JSON.parse(buf.subarray(16, 16 + jsonSize).toString('utf8'));

// 2) 沿 files 树往下走
let node = header;
for (const part of ENTRY) {
  node = node.files?.[part];
  if (node === undefined) throw new Error(`entry not found at segment: ${part}`);
}

// 3) offset 是字符串，必须转数字
const offset = Number(node.offset);
const size = Number(node.size);
if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(size)) {
  throw new Error(`bad entry numbers: offset=${node.offset} size=${node.size}`);
}

// 4) 切出内容并落盘
const bytes = buf.subarray(base + offset, base + offset + size);
fs.writeFileSync(OUT, bytes);
console.log('asar size     :', buf.length);
console.log('headerSize    :', headerSize, ' jsonSize:', jsonSize, ' payloadBase:', base);
console.log('abs range     :', base + offset, '..', base + offset + size, ` (${size} bytes)`);
console.log('entry sha256  :', crypto.createHash('sha256').update(bytes).digest('hex'));
console.log('header integ  :', node.integrity?.hash);
```

只做核对（不落盘）时，把片段用 `node -` 从 stdin 灌进去也可（本手册数值就是这么取的）：

```powershell
$node = 'C:\Users\Zhang Liang\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe'
$code | & $node -              # $code 为上面的片段（去掉写盘那行）
```

**判读要点**：`entry sha256` 必须等于 `header integ`；
不等说明 asar 或提取过程有问题，**先停下别打补丁**。

---

## 4. 沙箱提权注意事项（本机必读）

* 本工作区的写范围只有 `D:\文档\DSH-plugin\DSH-custom`（DSH 沙箱 `workspace-write`）。
* `D:\software\DeepSeek Harness\resources\app.asar` **在工作区外**，
  默认沙箱会直接拒绝写入（报 `[sandbox: file access denied …]`）。
  → 需要对**具体那一条写命令**做一次性提权（`danger-full-access`）。
  提权审批由 Lead 发起；子代理自己的权限在启动时就固定了，**无法自我提权**。
* 提权前的自检（只读，不需要审批）：
  1. asar 未被进程占用 → 试着以 `ReadWrite` 打开一次再关掉即可（本机 2026-10-08 实测可打开）；
  2. 目标 `offset`/`size` 与你手上的补丁基线一致 → 直接跑恢复脚本的干跑模式最省事：
     `powershell -NoProfile -ExecutionPolicy Bypass -File mods\active-workspaces\scripts\restore-official-ui-workspace.ps1 -WhatIfOnly`
     （只读，会打印 header / 条目 / offset / size / SHA256 / 模式判定）；
  3. 明确你走的是哪条路：能等长就等长（§5，已作废但思路可用），
     不能等长就走重排（§5b），**不要**把"能等长"硬套到"长度已变化"的 asar 上。
* 提权只用在**写 asar 那一步**；提取、比对、校验、写日志都留在工作区内完成。
* 不要用 `Set-Content` / 文本管道往 asar 写：那会重新编码并可能改动长度。
  必须按字节写入（`FileStream` + 原始 `byte[]`）。

---

## 5. 【已作废】打补丁 → 校验 → 写回（等长覆盖版）

> ⚠️ **本节仅作历史参考 / 等长场景复用。本需求实际走的是 §5b 的带头重排写回。**
> 作废原因：补丁净增 4604 字节，`patched-client.js` 是 204728 字节，
> 「写回后长度仍为 200124 / 总长仍为 121348951」这两个断言现在**都不成立**。
> 若未来的补丁能做成等长，本节流程可以照用。

约定：`$root = D:\文档\DSH-plugin\DSH-custom`。

### 步骤 0 — 备份（先备份，后动手）

```powershell
$root  = 'D:\文档\DSH-plugin\DSH-custom'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
# 备份的必须是「当前 asar 里的官方字节」，即本次补丁的基线文件
Copy-Item "$root\tmp\extracted-client.js" "$root\tmp\backup-asar-ui-workspace-$stamp.js"
```

备份文件就是**官方原始 200124 字节**，回滚靠它（§6）。
补丁生成器每次运行都应滚动生成一份新的带时间戳备份，不要覆盖旧的。

### 步骤 1 — 生成补丁后的内容（等长）

补丁生成器（Lead 维护）的契约：

1. 读基线 `tmp\extracted-client.js`（或直接从 asar 提取，更稳）；
2. **逐锚点校验**：每个锚点字符串都必须**恰好出现一次**，否则报错退出（见 §9）；
3. 做等长替换，产出 `tmp\patched-client.js`；
4. **断言长度相等**：`(Get-Item patched).Length -eq (Get-Item baseline).Length`，不等即失败；
5. 打印每个补丁点的字节区间与替换前后片段，便于人工复核。

### 步骤 2 — 写入前校验

```powershell
$root = 'D:\文档\DSH-plugin\DSH-custom'
$baseline = Get-Item "$root\tmp\extracted-client.js"   # 基线（官方原版）
$patched  = Get-Item "$root\tmp\patched-client.js"
"baseline bytes : $($baseline.Length)  (应为 200124)"
"patched  bytes : $($patched.Length)"
if ($baseline.Length -ne $patched.Length) { throw '长度不等，拒绝写入 asar' }
```

再用 §3 的片段读一次 asar 里的**当前** `offset`/`size`，确认与本手册表格一致
（若客户端已升级，这里就会不一致 → 走 §9 重放流程，不要硬写）。
最省事的做法是跑恢复脚本的干跑模式（只读、不写字节）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File mods\active-workspaces\scripts\restore-official-ui-workspace.ps1 -BackupPath "$root\tmp\extracted-client.js" -WhatIfOnly
```

### 步骤 3 — 写回（提权；按字节、等长、原地覆盖）

写入只做一件事：把 `patched-client.js` 的字节覆盖到
`payloadBase + offset` 起始的 `size` 字节上。**不新增、不删除任何字节**，
header 与所有其他条目偏移全部不动。

```powershell
# 需一次性提权（danger-full-access）
$asar = 'D:\software\DeepSeek Harness\resources\app.asar'
$root = 'D:\文档\DSH-plugin\DSH-custom'
$patched = [System.IO.File]::ReadAllBytes("$root\tmp\patched-client.js")

$fs = [System.IO.File]::Open($asar, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
try {
    $h = New-Object byte[] 16
    [void]$fs.Read($h, 0, 16)
    $jsonSize = [BitConverter]::ToUInt32($h, 12)
    $base = 16 + $jsonSize
    $off  = 42803098          # ← 必须来自步骤 2 的实测，不要照抄
    $fs.Seek($base + $off, [System.IO.SeekOrigin]::Begin) | Out-Null
    $fs.Write($patched, 0, $patched.Length)
    $fs.Flush()
} finally { $fs.Dispose() }
```

### 步骤 4 — 写后校验（必做）

按 §3 片段再提取一次，断言：

* 提取长度 == `200124`；
* **提取内容与 `patched-client.js` 逐字节相同**（`fc /b` 或 Node `Buffer.compare`）；
* 文件总长度仍为 `121348951`；
* SHA256 == 补丁后文件的 SHA256（**不要再等于表里那个官方 SHA256**）。

### 步骤 5 — 生效与验收

* 客户端内**刷新页面**（改的是 renderer 侧 bundle，不必重启进程）；
  若刷新无效再彻底重启客户端。
* 按 `README.md` §验证 的清单逐条走。
* 结论写进 `logs/` 当日工作日志。

---

## 5b. 【现行】带头重排的追加式写回

适用场景：补丁后的 `client.js` **长度变了**（本需求：200124 → 204728，+4604）。
执行者：`tmp/write_back_asar.mjs`（Lead 维护）。用法：

```powershell
$node = 'C:\Users\Zhang Liang\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe'
& $node tmp\write_back_asar.mjs dry-run   # 只算净增，不写
& $node tmp\write_back_asar.mjs apply     # 真正写回（asar 在工作区外 → 需一次性提权）
& $node tmp\write_back_asar.mjs verify    # 只读回读校验
```

### 它做什么（7 步）

1. 打开 asar，`readUInt32LE(12)` 取 `jsonSize`（**不是偏移 8**，偏移 8 是 pickle 的
   JSON 长度字段），读 `16 .. 16+jsonSize` 解析 header JSON；
2. 沿 `files` 树找到目标条目；写回前先核对 asar 内条目 SHA256 == header 的 `integrity.hash`，
   不等就抛错（防止在已改动的 asar 上二次打补丁）；
3. **备份原始条目**到 `tmp\backup-asar-entry-client.js`（200124 字节，SHA256 与官方一致）；
4. **按原顺序重排数据区**：逐条目读取 → 长度变化的条目（只有目标）换成 `patched-client.js`
   → 其余条目**内容字节原样搬运**；
5. 逐条目重算 `offset`（`cursor` 累加）与 `integrity`（`algorithm/hash/blockSize/blocks` 全部重写）；
6. 把新 JSON 字符串写进头部，**整文件重写**（先写 16 字节前缀 + 头部，再顺序写数据区），
   最后 `ftruncate` 到 `16 + jsonSize + cursor`；
7. 回读自检。

### 必须记住的三个坑

1. **`unpacked` 条目要跳过**（本次 1497 个）：它们的内容在 `app.asar.unpacked\` 下，
   header 里**没有 `offset`**。若不跳过，`Number(undefined)` → `NaN`，
   会以 `RangeError: position NaN` 崩掉（`fs.readSync` 的 position 是 `NaN`）。
   跳过条件是 `child.unpacked || child.offset === undefined`。
2. **头部长度字段的位置**：`writeUInt32LE(4)` = headerSize、**`(12)` = jsonSize（真正的 JSON 字节数）**、
   `(8)` = pickle 里 JSON 字符串的长度字段。三者**必须一致地维护**：
   本写回器保持 `jsonSize` 不变、把新 JSON 用 NUL 补齐到原长度，所以 `(4)/(8)/(12)` 都不用动。
   若有脚本把新长度写进 `(12)` 而没用 NUL 补齐，`JSON.parse` 会在 NUL 处报
   `Unexpected non-whitespace character after JSON`。
3. **要保留数据区尾部到原文件尾的差距**：重排后是紧凑排布，
   文件尾一定会缩短（本次 −3394304 + 4604）。若重排结果是"条目 end == 文件尾"，
   那只是巧合，**不要**把"数据区必须紧贴文件尾"当成不变量写进校验（否则将来会误报）。

### 写后必须核对

用只读脚本核对（**注意**：`tmp\verify_asar.mjs` 当前有 bug，见 §11）：

* 文件总长 == `121353555`（记录值）；
* `JSON.parse` 成功，且条目数与重排前一致（unpacked 条目不算在内）；
* 目标条目 `size == 204728`、SHA256 与 `patched-ui-workspace-client.js` 逐字节相同、
  且等于 header 里重算后的 `integrity.hash`；
* **抽样 + 最大条目**核对其它条目的 SHA256 仍与其 `integrity.hash` 一致
  （证明"搬运"没写坏内容）；
* 数据区各条目 `[offset, offset+size)` 区间**无重叠**、`max end` 与数据区长度自洽。

---

## 6. 回滚（把官方 `client.js` 放回去）

**脚本：`mods\active-workspaces\scripts\restore-official-ui-workspace.ps1`**

```powershell
# 只打印计划，不写字节（只读，可在无提权时先跑）
powershell -NoProfile -ExecutionPolicy Bypass -File mods\active-workspaces\scripts\restore-official-ui-workspace.ps1 -WhatIfOnly
# 真正回滚（asar 在工作区外 → 需一次性提权）
powershell -NoProfile -ExecutionPolicy Bypass -File mods\active-workspaces\scripts\restore-official-ui-workspace.ps1
```

### 它为什么不能只是"等长写回"

补丁已把 asar **重排过**：目标条目 `size` 从 200124 变成 204728，
**它后面的每个条目 offset 都前移了**。所以恢复官方文件必须把整个布局还原：

1. 在目标条目的**当前** offset 处写入官方字节（200124）；
2. 把它后面的**每一个**条目**向前搬 4604 字节**（`delta = 旧 size − 新 size`）；
3. 改写目标条目的 `size`；
4. 把后面每个条目的 `"offset":"N"` 减去 `delta`；
5. 重算目标条目的 `integrity.hash`；
6. 把文件截断到新的数据区末尾。

脚本对 header 的修改是**文本级定点替换**，并断言替换前后**字节长度不变**
（所以 16 字节前缀里的 `headerSize/jsonSize` 都不用动），
同时断言每个替换 token 在 header 里**恰好出现一次**（`"offset":"N"` 这种 token 可能在多条目里重复 → 直接拒绝）。

**脚本自带的安全闸**：

| 闸 | 行为 |
| --- | --- |
| 备份 SHA256 ≠ 已知官方常量 `29c34ce1…` | 拒绝执行（`-Force` 可绕过，仅当客户端版本确实变了） |
| 条目内容已经等于备份 | 直接退出，不写 |
| `delta` 计算不出整数 / offset 变负 | 拒绝执行 |
| 目标条目**不是**数据区最后一内容 | 拒绝执行（说明布局不是本写回器产出的，此时应整文件回退） |
| header 文本 token 命中数 ≠ 1 | 在写 header 前拒绝 |
| 改写后 JSON 长度 ≠ 原长度 | 在写 header 前拒绝 |
| 写后复读：hash/size/offset/文件长度任一不符 | 报 `VERIFY FAILED` |

### 关键差异 vs 补丁前版本

| | 旧版脚本（已作废） | 现行脚本 |
| --- | --- | --- |
| 前提 | 条目不改变长度 | **不要求**等长 |
| 备份大小检查 | **要求等于**当前条目大小，否则拒绝 | 不再要求；改为**要求等于已知官方 SHA256** |
| offset 处理 | 不动 | 后面所有条目 −delta |
| integrity | 不动 | 目标条目重算 |
| 默认备份 | `tmp\backup-asar-ui-workspace-*.js` | 优先 `tmp\backup-asar-entry-client*.js`，兼容旧名与官方副本名 |

> ⚠️ **诚实标注**：现行脚本是在**无法执行 shell 的环境下**改写的——
> 作者只能做静态语法自检（人工核对），**没有真机干跑过**。
> 因此第一次使用前**必须先跑 `-WhatIfOnly`**，确认打印出的
> `mode = REORDER/REBUILD`、`delta`、`new file length`、`will shift N entries` 与预期一致，
> 再执行真正的回滚。若 `-WhatIfOnly` 报错，**不要**去掉开关硬跑。

### 手工等价流程（脚本不可用时）

1. 用 §3 片段取出目标条目的当前 `offset`/`size` 与 header `integrity.hash`；
2. 以 `-WhatIfOnly` 的输出为蓝本，按上面 6 步自己写一次性脚本；
3. 回滚后复算 SHA256，应等于 `29c34ce1c2a437cf8a50ba35d1ae44741114439e37a17153dfd4b1aa942aa955`。

回滚后客户端行为应与改造前完全一致（段标题消失、月亮/太阳按钮消失）。
如果回滚后行为没变，先确认**彻底重启过客户端**（host 侧代码不是刷新就能换的），
再确认 asar 的 mtime 确实变了。要重新打补丁，就重跑 §5b 那两条命令。

---

## 7. 沙箱外/其他注意

* **不要动 `C:\Users\Zhang Liang\.dsh\profiles\node_modules\@deepseek-ai\*`**：
  那是 junction，指向另一套 `0.1.0-rc.8`，改它不会影响当前客户端（见 `memory/MEMORY.md` §4）。
* 本改造**只影响桌面客户端**；`dsh web`（profile `web`）加载的是另一套 0.1.0-rc.8 的包，行为不变。
* 客户端「设置 → 插件」安装/卸载**其他插件不会**重写 app.asar 内的这个包；
  但**客户端自身升级会整包替换 app.asar** → 见 §9。

---

## 8. 本手册数值的实测方法（复核用）

1. `Get-Item 'D:\software\DeepSeek Harness\resources\app.asar'` 取文件大小；
2. Node 读 `readUInt32LE(4)` / `readUInt32LE(12)` 取 `headerSize` / `jsonSize`
   （**偏移 12 才是 JSON 字节数**，偏移 8 是 pickle 里 JSON 字符串的长度字段；
   这两个值在本机相等，所以写错位置一时看不出来——`tmp\verify_asar.mjs` 就栽在这里）；
3. 沿 `files` 树取条目，打印 `offset`(Number) / `size` / `integrity.hash`；
4. 切出字节与 `tmp/official-ui-workspace-client.020rc2.js` 逐字节比对 + SHA256 比对。
   2026-10-08 结果：**完全相同**（`Buffer.compare === 0`，SHA256 一致）。

**补丁写入后的复核对（只读）**，建议用这个最小片段，别用有 bug 的 `tmp\verify_asar.mjs`：

```js
// node --input-type=module 或存成 tmp\check-after.mjs
import fs from 'node:fs';
import crypto from 'node:crypto';
const ASAR = String.raw`D:\software\DeepSeek Harness\resources\app.asar`;
const fd = fs.openSync(ASAR, 'r');
const st = fs.fstatSync(fd);
const head = Buffer.alloc(16); fs.readSync(fd, head, 0, 16, 0);
const jsonSize = head.readUInt32LE(12);            // ← 12，不是 8
const base = 16 + jsonSize;
const hdrBuf = Buffer.alloc(jsonSize); fs.readSync(fd, hdrBuf, 0, jsonSize, 16);
const hdrText = hdrBuf.toString('utf8');
const json = JSON.parse(hdrText);                   // 必须成功
console.log('file size   :', st.size, '(记录值 121353555)');
console.log('jsonSize    :', jsonSize, ' payload base:', base);
let e = json;
for (const seg of ['dsh','node_modules','@deepseek-ai','dsh-client-ui-workspace','lib','client.js']) e = e.files[seg];
const size = Number(e.size), offset = Number(e.offset);
const buf = Buffer.alloc(size); fs.readSync(fd, buf, 0, size, base + offset);
const hash = crypto.createHash('sha256').update(buf).digest('hex');
const patched = fs.readFileSync(String.raw`D:\文档\DSH-plugin\DSH-custom\tmp\patched-ui-workspace-client.js`);
console.log('entry size  :', size, '(记录值 204728)');
console.log('entry sha256:', hash);
console.log('header hash :', e.integrity.hash, ' self-consistent:', hash === e.integrity.hash);
console.log('== patched  :', buf.equals(patched));
// 抽样：最大条目 + 均匀取样，核对每条的 SHA256 与其 integrity 一致
```

---

## 9. 客户端升级后如何重放

前置事实：客户端升级 = 换掉 `resources/app.asar`（可能整包或整条 `/dsh` 子树），
**打在里面的补丁一定丢失**。所以补丁必须以"**可重放的锚点补丁**"形式留档。

重放流程：

1. **先判断是否真的需要重放**：用 §3 片段提取目标条目，
   若 SHA256 已等于表里的官方值 → 说明是干净的原版，可以重放；
   若不等且不是我们打的补丁 hash → 官方自己改过这个文件，**必须重新比对锚点**。
2. **取新版本的坐标**：重放前先确认包版本（asar 内
   `/dsh/node_modules/@deepseek-ai/dsh-client-ui-workspace/package.json` 的 `version`）。
   版本号变了就意味着内部实现大概率有变。
3. **锚点必须全部命中**：Lead 的补丁生成器对**每一个锚点**都做
   `count(anchor) === 1` 断言，任一缺失/重复即**报错退出**。
   这是硬要求 —— 锚点漂移时静默"改歪"会产出能编译但行为错误的 bundle，
   比直接失败危险得多。
4. **长度断言**：等长补丁断言"补丁前后长度一致"；非等长补丁（本需求）断言的是
   **"补丁后长度 == 生成器预期的 204728"**，并把新长度写进留档。
   两种断言都必须存在，绝不能"不检查长度就往 asar 里写"。
5. 锚点缺失时的正确做法：
   * 停下，把"新版本中该锚点附近的代码"与 `REQUIREMENTS.md` §3 的判定规则对照；
   * 在 `PATCHING.md` 里追加一节记录**锚点迁移**（旧锚点 → 新锚点 → 版本号）；
   * 重新生成补丁、重新走 §5b 全套校验；
   * **不要**用"模糊匹配/正则扫一遍"代替精确锚点。
6. 客户端自动更新通常在启动时发生；打完补丁后如果又升级了，
   `tmp/` 里的备份仍在，可反复重放（重放 = 生成器 + 写回器两条命令）。
7. 若官方在新版里**已经**实现了活跃/沉默分组 → 停止打补丁，
   改用官方能力并归档本需求（删掉 `mods/active-workspaces/` 的补丁部分，保留日志）。
8. **升级后的重放起点变了**：现行 asar 已被重排（总长 121353555），
   若客户端又升级，asar 会被换回官方形态（总长可能是 121348951 或别的值）。
   → 每次都重新按 §3 取 `jsonSize`/`offset`/`size`，**不要**沿用本文里的旧数值。

---

## 10. 已确认（原先的「待确认」，Lead 于 2026-10-08 晚逐条答复）

1. **补丁生成器与锚点清单**：`tmp\build_active_workspaces_patch.mjs`（Lead 维护）。
   **17 个锚点**，每个都要求**唯一命中**，命中数 ≠ 1 立即抛错：

   | # | 锚点 id | # | 锚点 id |
   | --- | --- | --- | --- |
   | 1 | `store-init` | 10 | `row-toggle` |
   | 2 | `store-actions` | 11 | `pin-button` |
   | 3 | `threshold` | 12 | `pin-flag` |
   | 4 | `classify` | 13 | `browser-store` |
   | 5 | `group-fields` | 14 | `derive-view` |
   | 6 | `tree-props` | 15 | `tree-call-props` |
   | 7 | `tree-sections` | 16 | `dict-zh` |
   | 8 | `tree-render` | 17 | `dict-en` |
   | 9 | `row-actions` | | |

   产出 `tmp\patched-ui-workspace-client.js` = **204728 字节**（官方 200124，净增 4604）。
   官方与补丁版都通过 `new vm.Script()` 解析（PARSE OK）。
2. **逐点改动内容**：以生成器源码为准——每个 `add(id, find, replace)` 就是一段可读的 diff 说明。
   **锚点文本本身仍未落档**（见 §11 待复核）。
3. **`integrity` 字段**：条目确实带
   `integrity: { algorithm: "SHA256", hash, blockSize: 4194304, blocks: [hash] }`；
   写回器**按新内容重算**（本次 `blocks` 只有一块，因为文件远小于 4 MiB 分块）。
   **Electron 的 `EnableEmbeddedAsarIntegrityValidation` fuse = false（Lead 实测）** →
   运行时不校验；仍然重算，是为了将来被校验时不出事。
4. **`lib/index.js`**：**不含**同源逻辑。它是 host 半区入口，
   工作区列表渲染只在 `lib/client.js` → 只改 `client.js` 是对的。
5. **持久化键：决定不升版**，保持 `dsh.workspace.view.v5`。理由：
   * 段折叠状态**已从 store 移到独立的 localStorage key** `dsh.workspace.sectionExpansion`；
   * 沉默钉表 `pinnedSilentAt` 在 store 里，但**读取处已加 `?? {}` 兜底**
     （与官方 `archivedFilter ?? "default"` 同一套路）。
   → 旧持久化载荷缺字段不会出问题；升版反而会作废用户已有的 UI 偏好。
6. **生效条件**：host 半区改动需**重启整个客户端**；本次改的是 **client bundle**。
   Lead 的说法是"理论上重启后加载"，**仍未实测** → 列入 §11 待验证。
   实际操作按"先刷新页面，不行就彻底重启"走。
7. **asar 在运行中是否被锁**：Lead 实测**没有被锁**（可以 `r+` 打开）。
   沙箱默认拒绝写工作区外文件，需一次性提权；提权后写入成功。

---

## 11. 仍未验证 / 待复核（不要当成已知事实）

1. **补丁写入后的 asar 尚未通过独立回读校验**。Lead 的写回器自检用旧 `jsonSize`
   去读头部，导致 JSON 截断并报 `Unexpected non-whitespace character after JSON`；
   独立校验脚本 `tmp\verify_asar.mjs` 也**未成功运行**（shell 执行器故障）。
   → 当前状态见 `mods/active-workspaces/PATCH-STATUS.md`。
2. **`tmp\verify_asar.mjs` 自身有两个 bug**（静态阅读所得，未运行）：
   * L20 `head.readUInt32LE(8)` 取的是 pickle 的 JSON 长度字段，不是 JSON 字节数
     → 应改为 `readUInt32LE(12)`；否则 `hdr` 只读到前 4 字节，`JSON.parse` 必炸，
     随后脚本 `exit(1)`，**根本走不到抽样校验**；
   * 脚本头注释说"结果写入 `tmp\asar-verify.txt`"，但代码里**没有任何写文件调用**，
     只有 `console.log` → 读 `asar-verify.txt` 只会得到"文件不存在"。
3. **数据区为何缩短 3394304 字节**（117965795 → 117961491）：记录值显示原 asar 的
   数据区存在间隙，重排后变成紧凑排布。这个差额**未经第二人独立复算**，
   而它恰好落在"重排是否抄错了内容"的高风险区 → 必须用 §5b 的抽样 + 最大条目校验来证伪。
4. **刷新是否足以加载新的 client bundle**（§10 第 6 条）——未实测。
5. **回滚脚本的新版未真机干跑**（编写时 shell 不可用）→ 首次使用必须先 `-WhatIfOnly`。
