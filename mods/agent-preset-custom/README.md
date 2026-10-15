# 定制模式（agent preset `custom`）— Windows 桌面客户端版

需求：**新建一个 DSH 模式，在「极简模式」基础上添加文件工具与 `ask_user_question`，
命名为「定制模式」**。

> 本目录是 WSL 版 `~/dsh-custom/mods/agent-preset-custom/` 的 **Windows 复刻**：
> 模式组成（`custom.patch.yml`）与探针脚本**逐字节一致**，安装/校验脚本按平台重写成
> PowerShell（bash 版在 Windows 沙箱下不可用，MSYS 信号管道会被拒）。
> 本目录既是这个模式的配置源，也是它的安装/校验工具。

---

## 1. 结论速览（先看这段，避免重复踩坑）

| 事 | 事实（本机实测） |
| --- | --- |
| **定制模式 =** | 极简模式（逐字复制）+ `@deepseek-ai/dsh-tool-fs` + `@deepseek-ai/dsh-tool-ask-user` |
| 极简模式在 **Windows** 上的模型可见工具 | `pwsh`（`dsh-tool-pwsh-persistent`，持久式；bash 那两行被 `process.platform === 'win32'` 门禁用） |
| 极简模式在 Linux 上的模型可见工具 | `bash`（同一份 patch 在 WSL 侧就是这个结果） |
| 单独新增 `@deepseek-ai/dsh-tool-bash` | **不行**：与极简自带的持久 `bash` 同名 → 整个预设挂载失败 `tool "bash" is already registered in this scope` |
| `read_image` 能不能单独加 | **不能**：0.2.0-rc.2 里只存在于 `@deepseek-ai/dsh-tool-fs`，该包无条件注册 `read`/`read_image`/`write`/`edit`，没有开关 |
| 最终取舍 | 保留极简自带的持久 shell；新增 `tool-fs`（连带 read/write/edit）与 `tool-ask-user` |

实测工具清单（探针读 preset standing scope 的工具视图，等价于模型看到的目录）：

```
① 临时 web 模板 profile（verify.ps1）
   [probe] preset=minimal tools(1): pwsh
   [probe] preset=custom  tools(6): ask_user_question, edit, pwsh, read, read_image, write

② 真实 desktop profile 副本（tools/verify-real-profile.ps1，含第三方 bundle）
   [probe] preset=minimal tools(18): pwsh, task_board_* ×17
   [probe] preset=custom  tools(23): ask_user_question, edit, pwsh, read, read_image, write, task_board_* ×17
```

> ②里多出的 17 个 `task_board_*` 来自 profile 里的第三方插件（`@linxin666/dsh-client-ui-task-board`），
> 它注册在 **profile 层**而不是 preset 层，所以会出现在**所有**模式的工具视图里（极简模式也有）。
> 这不是本模式引入的，也不影响「定制模式 = 极简 + 5 个工具」的结论。

## 2. 目录内容

| 文件 | 作用 |
| --- | --- |
| `custom.patch.yml` | **唯一的事实来源**：dsh profile patch 片段，`insert` 一条 `@deepseek-ai/dsh-agent-preset` 行（id `custom`，显示名「定制模式」，order 5）。与 WSL 版 `sha256 E81590C3…AEFB` 逐字节一致 |
| `install.ps1` | 把上面的片段以托管块形式写进某个 profile 的 `cordis.patch.yml`（幂等、先备份、保留 BOM/换行风格） |
| `uninstall.ps1` | 摘掉托管块（摘空则写回 `[]` 模板） |
| `verify.ps1` | 临时 `DSH_HOME`（web 模板 profile）+ `--dump-config` + 起临时实例读工具清单 |
| `tools/verify-real-profile.ps1` | **Windows 特有**：复制真实 profile（含第三方 bundle 与 node_modules junction）起临时实例，端到端复核 |
| `tools/probe-preset-tools.mjs` | 校验探针：打印指定 preset 对模型可见的工具名（与 WSL 版逐字节一致） |
| `.gitignore` | 忽略本地产物（`tmp/`、`*.bak-*`、`*.log`） |

## 3. 安装

```powershell
# 装进当前 GUI 用的 profile（缺省取 $env:DSH_PROFILE_DIR，即 desktop）
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-custom\install.ps1

# 或指定 profile 目录
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-custom\install.ps1 `
  -ProfileDir "$env:USERPROFILE\.dsh\profiles\desktop"
```

* profile 目录在工作区之外，**workspace-write 沙箱下写它会失败**，需要一次
  `danger-full-access`（会向用户申请）。
* 安装做的事：整份备份 `cordis.patch.yml` → 去掉旧的托管块 → 追加新托管块。
  目标文件还是空模板 `[]` 时整体重写（`- insert:` 不能直接跟在 `[]` 后面）。
* **本机实装记录（2026-10-15）**：
  * 目标 `C:\Users\Zhang Liang\.dsh\profiles\desktop\cordis.patch.yml`；
  * 3267 B `710E84A5…321E` → 8406 B `F898226A…D11B`，原 92 行**逐字保留**（行级比对通过）；
  * 备份 `cordis.patch.yml.bak-20261015-152454`；profile 目录内其余文件（`package.json` /
    `pnpm-lock.yaml` / `cordis.yml`）哈希未变。
* 装完后**运行中的宿主已加载**（见 §7），新建任务 →「Agent 预设」→ **自定义** 分组里
  应能看到「定制模式」；若看不到就重启一次客户端（Desktop profile 的补丁层在启动时合成）。

## 4. 校验

```powershell
# ① 模板 profile 快速校验（不需要提权，产物全在 tmp/）
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-custom\verify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-custom\verify.ps1 -Port 3199

# ② 真实 desktop profile 端到端（读真实 profile，只写 tmp/）
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-custom\tools\verify-real-profile.ps1
```

两次实测都是退出码 0：`6/6 PRESENT`、`--- 预设挂载诊断 ---（无告警）`。
产物留在 `tmp/agent-preset-custom-verify/`、`tmp/real-verify/`（已 gitignore），全程不碰真实 `DSH_HOME`。

为什么必须有「起临时实例」这一步：预设行是**运行时挂载**的，`--dump-config` 只能证明
patch 组合正确，证明不了 `read_image` 之类「要等 attachments 服务」的行真的注册成功。
探针插件读 preset standing scope 的工具视图，才是模型实际看到的目录。

## 5. 回滚

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File mods\agent-preset-custom\uninstall.ps1
# 或直接恢复 profile 目录里的 cordis.patch.yml.bak-<时间戳>
```

## 6. 后续修改要点

* 改配置一律改 `custom.patch.yml`，再跑 `install.ps1` 覆盖（幂等），不要手改 profile
  里的托管块——下次安装会被覆盖。
* 想加别的工具：在 `plugins:` 末尾按同样格式追加行（包名 `@deepseek-ai/dsh-tool-*`）；
  **先查该包注册的工具名是否与现有工具重名**（重名会让整个预设挂载失败，`verify.ps1` 能立刻测出来）。
  查工具名：`grep -n 'name: "' <asar 内包>/lib/index.js`。
* GUI 的预设编辑器改这个模式时，会按行 id `preset-custom` 往 profile patch 里追加
  `config.plugins` 覆盖行；那样改过之后要把覆盖行的内容拷回本目录的 `custom.patch.yml`。
* `description` 显示在模式悬停说明里；`name` 决定 UI 显示名（有 `name` 即进「自定义」分组）。

## 7. 相关事实（Windows 侧，写死在这里省得下次重查）

* **宿主**：桌面客户端自带 **0.2.0-rc.2**（在 `D:\software\DSH\resources\app.asar` 内）。
  可直接跑的 CLI：`D:\software\DSH\resources\runtime\cli\bin\dsh.cmd`
  （= `set ELECTRON_RUN_AS_NODE=1` + `DeepSeek Harness.exe --expose-internals
  <asar>\dsh\node_modules\@deepseek-ai\dsh-desktop-host\lib\cli.js`）。
  `dsh.cmd --version` → `0.2.0-rc.2`。两个 verify 脚本都自动探测它。
* **桌面客户端的 profile 不允许 CLI 组合**：
  `dsh.cmd --profile desktop --dump-config` →
  `error: profile "desktop" is managed exclusively by the Electron application`。
  ⇒ 真实 profile 的端到端校验只能走「复制 + junction + 改名 profile」这条路
  （`tools/verify-real-profile.ps1`），profile 名改用 `realverify` 即不再被拦。
* **环境锚点**（DSH 会话里自带）：`DSH_HOME=C:\Users\Zhang Liang\.dsh`、
  `DSH_PROFILE=desktop`、`DSH_PROFILE_DIR=…\.dsh\profiles\desktop`。
  `install.ps1` / `uninstall.ps1` 的缺省 profile 目录就取自 `DSH_PROFILE_DIR`。
* **当前 GUI 已加载本模式**（`cordis_inspect_query`，host `Config`/`listConfigs`，
  `name=@deepseek-ai/dsh-agent-preset`）→ 5 行：standard / ptc / minimal / cordis / **custom**
  （`include:preset-custom`，`packageDir` = asar 内 `@deepseek-ai/dsh-agent-preset`）。
  即桌面客户端**热加载了** patch，不必以「重启后才有」为前提；这只是验收信号，
  真正点开要看 GUI 的预设选择器。
* **预设声明位置**：asar 内 `@deepseek-ai/dsh-web-app/presets/{standard,ptc,minimal,cordis}.patch.yml`，
  由该包 `dsh.bundle.patch` 注册（order 1/2/3/4）；本地新增行 order 取 5。
* web 面把 agent plane 整体搬进 preset：`@deepseek-ai/dsh-web-app/cordis.patch.yml` 把
  `dsh-base` 里的 `tool-bash` / `tool-fs` 等 host 行按 id `disabled: true` 关掉，改由预设挂载。
* profile patch 层顺序：`dsh.profile.bundles` 各自层 → profile 的 `cordis.patch.yml` →
  `$DSH_HOME/cordis.patch.yml` → `--patch` 覆盖。
* 预设由 `@deepseek-ai/dsh-agent-preset-registry` 急切挂载；挂载失败只影响该预设
  （日志 `agent preset <id>: <原因>`，UI 显示「加载失败」），不挡宿主启动。
* 本工作区（Windows）本身是 git 仓库，直接提交/推送到 origin；WSL 那套是独立工作区
  （`/home/zhangliang/dsh-custom`），有它自己的裸仓库。

## 8. 变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-10-15 | 建立：从 WSL 版复刻（`custom.patch.yml` / 探针逐字节一致），安装/校验重写为 PowerShell；实装进 desktop profile 并两次实测通过（模板 profile 6 工具、真实 profile 副本 23 工具含第三方 bundle）；活宿主 inspect 已见 `include:preset-custom`。 |
