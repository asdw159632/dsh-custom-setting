# 安装记录：dsh-web 全家桶（桌面客户端 desktop profile）

日期：2026-10-08
状态：**前置配置已完成，等待在客户端 UI 内执行安装**

---

## 1. 版本口径（先纠正一个容易看错的坑）

这台机器上有**两套** DSH 安装树，混淆会导致完全错误的兼容性结论：

| 安装树 | 路径 | DSH SDK 版本 | 用途 |
| --- | --- | --- | --- |
| **桌面客户端自带** | `D:\software\DeepSeek Harness\resources\app.asar` → `/dsh/node_modules/` | **0.2.0-rc.2** | 当前正在用的 GUI 就是它 |
| 独立 CLI / dsh web | `D:\software\DeepseekHarness\node_modules\` | 0.1.0-rc.8 | 另一个 `dsh web` 实例 |
| profile 软链层 | `C:\Users\Zhang Liang\.dsh\profiles\node_modules\@deepseek-ai\` | 0.1.0-rc.8（junction 指向上面那套） | 被第二套使用 |

* 全局 `dsh` CLI（`C:\Users\Zhang Liang\AppData\Roaming\npm`）版本 = **0.1.0-rc.8**，与客户端自带宿主 **不一致**。
* **结论：客户端本体已是 0.2.0-rc.2，满足 dsh-web 全家桶门槛（`dsh.engines.dsh: >=0.2.0-rc.2`），不需要升级客户端。**

校验方法（可复用）：

```powershell
$node = "C:\Users\Zhang Liang\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe"
# 读 app.asar header，遍历 files 树，取出 /dsh/node_modules/@deepseek-ai/dsh/package.json
```

另注：`dsh-better-sidebar` / `@linxin666/dsh-client-ui-aionui-panel` 那批插件装在
**web profile**（`~/.dsh/profiles/web`），与 desktop profile 无关，当前 GUI 未启用。

## 2. 目标包

* npm 包：`@linxin666/dsh-web-all`
* 最新版本：**0.4.5**（`registry.npmjs.org` 实测）
* 仓库：<https://github.com/zhu1090093659/dsh-web>
* 要求：`@deepseek-ai/dsh >= 0.2.0-rc.2`（客户端满足）

## 3. 本次已完成的改动

文件：`C:\Users\Zhang Liang\.dsh\profiles\desktop\pnpm-workspace.yaml`

追加两个配置块（原因来自 dsh-web 官方 README 的安装排障章节）：

```yaml
minimumReleaseAgeExclude:
  - '@linxin666/*'          # 防 pnpm 11 发布年龄门禁静默装回旧版本（官方记录过因此启动崩溃）

allowBuilds:
  cloudflared: true         # 原生命令行工具
  cpu-features: true        # ssh2 的原生依赖
  node-pty: true            # 终端 PTY
  ssh2: true                # SSH 传输
```

校验：用 `js-yaml` 解析通过，五个键齐全、类型正确。

备份：本次改动前的 desktop profile 配置已存到
`tmp\backup-desktop-profile-20261008\`（`package.json` / `pnpm-lock.yaml` /
`pnpm-workspace.yaml` / `cordis.patch.yml` / `cordis.yml`）。

## 4. 待执行：在客户端 UI 内安装

**必须走客户端自己的插件管理**，不要用全局 `dsh plugin`：

| 通道 | pnpm 版本 | 判断 |
| --- | --- | --- |
| 客户端「设置 → 插件」 | 应用自带 **11.7.0** | ✅ 用这个（也是当初装 dshmarket 的通道） |
| 全局 `dsh plugin`（`dsh` 0.1.0-rc.8） | CLI 自带 11.22.0 | ❌ 与 profile 的 pnpm 11.7.0 跨版本，会改写 `pnpm-lock.yaml`（lockfileVersion 9.0） |

步骤：

1. 打开客户端 → **设置 → 插件**（或左侧导航栏的插件入口）
2. 安装输入框填入包名：

   ```
   @linxin666/dsh-web-all@0.4.5
   ```

3. 若首次报 `ERR_PNPM_IGNORED_BUILDS`：这是 pnpm 拦原生构建脚本，按提示重跑一次即可
   （本次已预先放开四类构建脚本，预计不会再报）
4. **彻底重启客户端**（仅刷新页面不会加载新的 host 半区）
5. 重启后验证：侧边栏应出现任务看板 / 会话归档 / Git 图谱 / SSH / 用量统计等入口；
   也可在客户端内执行 `dsh --profile desktop --dump-config` 检查配置层是否挂载

## 5. 已知影响与后续

* dsh-web 全家桶会**新增一批侧栏入口与设置分区**（任务看板、会话归档、Git 图谱、
  SSH、用量统计、模型能力、皮肤中心、插件管理器、Skill 中心、创意工坊），
  侧栏会比现在更拥挤——这与"简化侧栏"的诉求方向相反，装完后再决定要不要按需卸载部分子包。
* dsh-web **不含**工作区活跃/沉默分组（生态空白），该改造仍按
  [REQUIREMENTS.md](REQUIREMENTS.md) 单独做，属于下一次的工作。
* 安装后若客户端内启用了皮肤中心，界面观感会变化。

## 6. 风险与回滚

* 回滚 profile 配置：把 `tmp\backup-desktop-profile-20261008\` 下的文件复制回
  `C:\Users\Zhang Liang\.dsh\profiles\desktop\`。
* 卸载插件：在同一个插件管理界面卸载 `@linxin666/dsh-web-all`，或恢复备份的
  `package.json` + `pnpm-lock.yaml` 后重装依赖。
