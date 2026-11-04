# 日志：把 sidebar-panellist-collapse 发布到 GitHub（集合仓库 + 子模块）

日期：2026-11-04
工作区：`D:\文档\DSH-plugin\DSH-custom`
插件源码：`mods/sidebar-panellist-collapse/`
需求：上传插件到 GitHub；新建 `DSH-plugin` 仓库，把插件作为**子仓库**放进去。

## 1. 结果

| 仓库 | URL | 说明 |
| --- | --- | --- |
| 插件独立仓库 | <https://github.com/asdw159632/dsh-panellist-collapse> | public，MIT；首个提交 `d900b61` |
| 集合仓库 | <https://github.com/asdw159632/DSH-plugin> | public；`main` = `0ac2c74`，插件挂在 `plugins/dsh-panellist-collapse`（**git submodule** → 独立仓库 `d900b61`） |

本地工作副本：

```
D:\文档\DSH-plugin\
├── DSH-custom\                                  # 本工作区（开发主仓库，origin=dsh-custom-setting）
├── DSH-plugin\                                  # 集合仓库工作副本（新建）
│   ├── README.md / LICENSE / .gitignore / .gitmodules
│   └── plugins\dsh-panellist-collapse\          # submodule 工作副本（独立仓库的 clone）
└── git-plugin\                                  # 之前就有的另一个插件目录
```

## 2. 做法（无 gh CLI，纯 git + REST API）

* **建仓库**：没有 `gh`，用 Windows 凭据管理器里的 PAT（`git-credential-manager get` 取，40 位 classic）
  调 `POST https://api.github.com/user/repos` 建两个 public 仓库（`private=false`）。
* **push**：沿用 `scripts\push.ps1` 的绕法——`git -c http.sslBackend=openssl`
  `-c "http.extraHeader=Authorization: Basic <base64(user:pat)>" push`（沙箱下 credential.helper 不可用）。
* **子仓库**：父仓库里 `git submodule add https://github.com/asdw159632/dsh-panellist-collapse.git plugins/dsh-panellist-collapse`，
  这样每个插件保持独立历史/独立 clone，父仓库只记 gitlink。
* **插件仓库内容**：从 `mods/sidebar-panellist-collapse/` 复制（9 个文件：package.json / cordis.patch.yml /
  index.js / client.js / locale/{en,zh}.json / icon.svg / README.md），另加 **MIT LICENSE**；
  README 里的本机绝对安装路径改成通用写法，并补「仓库/许可」段。
* 完整脚本（可复用，tmp 不入库）：`tmp/github-publish.ps1`。

## 3. 校验

* `GET /repos/asdw159632/dsh-panellist-collapse` → public、default_branch=main；
  仓库文件树：LICENSE / README.md / client.js / cordis.patch.yml / icon.svg / index.js / locale/*.json / package.json。
* `GET /repos/asdw159632/DSH-plugin/git/trees/main?recursive=1` → 4 个 blob + 1 个 gitlink：
  `plugins/dsh-panellist-collapse` mode `160000` → `d900b619…`（与插件仓库 HEAD 一致）。
* 本地 `git submodule status` → `d900b619… plugins/dsh-panellist-collapse (heads/main)`。

## 4. 注意 / 后续

* **本机已安装的插件仍 pnpm link 到 `DSH-custom/mods/sidebar-panellist-collapse`**，不是新仓库；
  改 GitHub 仓库不会自动影响已装插件。要以后以仓库为准，需要重新 `plugin_manager install_bundle` 指向
  `DSH-plugin\plugins\dsh-panellist-collapse`（或手动同步两份）。
* 以后新增插件：建独立仓库 → push → 在 `D:\文档\DSH-plugin\DSH-plugin` 里
  `git submodule add <repo-url> plugins/<name>` → 更新 README 表格 → commit/push。
* 克隆集合仓库要带子模块：`git clone --recurse-submodules https://github.com/asdw159632/DSH-plugin.git`。
* 两个仓库均为 public；如需私有可在 GitHub 设置里改，或告诉我用 API 改。

## 5. 2026-11-04 修正：仓库 description 中文变 "?????"

现象：两个仓库的 description 在 GitHub 上显示成 `?????`（README 内容正常，因为 git push 是字节流）。

原因：**PowerShell 5.1 的 `Invoke-RestMethod` 用字符串 Body 时不会按 UTF-8 发送**（HttpWebRequest 默认按非 UTF-8 处理），
建仓库时传的中文 description 被转成了 `?`。

修正：
* 用 `-Body ([Text.Encoding]::UTF8.GetBytes($json))` + `ContentType 'application/json; charset=utf-8'` 重新 PATCH；
* 同时按用户要求把两个仓库的 description 改成**英文**：
  * `dsh-panellist-collapse`：DSH UI plugin that collapses the left sidebar panel list: keep only the first N rows (default: just the Plugins entry) while leaving the skin artwork untouched.
  * `DSH-plugin`：My DeepSeek Harness (DSH) plugin collection. Each plugin lives in its own repository and is mounted here as a git submodule.
* `tmp/github-publish.ps1` 已同步改成 UTF-8 字节 Body（以后复用不再踩）。

## 6. 追加发布 dsh-git-plugin（+ 网络故障与 API 兜底）

用户要求把已有的 `dsh-git-plugin` 也挂进集合仓库。

### 6.1 前置：救回残缺的 .git

`D:\文档\DSH-plugin\git-plugin\.git` 只剩 `objects/` 和 `refs/heads/main`（缺 `HEAD`/`config`/`index`，
`git` 直接报 "not a git repository"）。手工补：
* `HEAD` = `ref: refs/heads/main`
* `config` = 最小 `[core]` 段（repositoryformatversion=0 / filemode=false / bare=false / logallrefupdates=true）
* `git -C <dir> reset` 重建 index

复活后：**9 个提交历史完整**（HEAD `8681bb2`），工作树干净（15 个跟踪文件）。

### 6.2 发布 + 挂子模块

* 新建仓库 <https://github.com/asdw159632/dsh-git-plugin>（public，英文 description、topics）；
* 本地直接 `git push -u origin main`（保留原历史），推送成功；
* 集合仓库 `git submodule add https://github.com/asdw159632/dsh-git-plugin.git plugins/dsh-git-plugin`
  → 提交 `18e0506` 并 push（此时 github.com 还通）。
* 校验：`GET /repos/asdw159632/DSH-plugin/git/trees/main?recursive=1` 有两个 mode 160000 的 gitlink：
  `plugins/dsh-git-plugin@8681bb2`、`plugins/dsh-panellist-collapse@d900b61`。

### 6.3 网络故障 + Git Data API 兜底

随后发现 **`github.com:443` 与 `raw.githubusercontent.com` 被阻断**（443 端口连接超时 / Connection reset），
但 `api.github.com` 与 `codeload.github.com` 仍可达 → 所有 `git push` 失败。

而集合仓库 README 还有两处要修：
1. 表格里包名两侧误出现字面反斜杠（`\`dsh-panellist-collapse\``）——原因是生成 Markdown 时反引号写进了
   **双引号 here-string**，`` \` `` 被当成转义；改用单引号 here-string 解决；
2. 补上 `dsh-git-plugin` 行与目录树。

本地提交 `66a7fae` 推不上去，于是用 **GitHub Git Data API** 直接改远端：
`GET /git/ref/heads/main` → `POST /git/blobs`（base64 README）→ `POST /git/trees`（`base_tree` + README）
→ `POST /git/commits` → `PATCH /git/refs/heads/main`。远端变为 `3ae4ed6`，
用 `GET /contents/README.md?ref=main` 解码校验：含 git-plugin 表格行 + 两行 submodule 树 ✓。

**遗留**：本地 `D:\文档\DSH-plugin\DSH-plugin` 的 `HEAD=66a7fae` 未推送（内容与远端 `3ae4ed6` 相同）；
等 github.com 恢复后执行 `git fetch && git reset --hard origin/main` 即可对齐。

### 6.4 安全提醒

这次一次失败的 `git push` 把 `http.extraHeader=Authorization: Basic <base64(user:pat)>` 回显到了命令输出
（脚本只脱敏了 token 原文，没脱敏 base64 组合）。该输出只在本机会话日志里，未进任何仓库；但建议抽空轮换一次 PAT。
后续脚本已改为同时脱敏 token 与 basic 组合。

## 7. 网络恢复后继续 push（走系统代理）

`github.com:443` 直连仍被阻断（TCP 可连、TLS 被 reset/timeout），但发现 **系统 IE 代理是开着的**：
`127.0.0.1:7890`（`HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings`，`ProxyEnable=1`）。
**git/curl 不读 IE 代理**，所以之前所有 push 都直连失败；显式带上代理后立刻恢复：

```
git -c http.sslBackend=openssl -c http.proxy=http://127.0.0.1:7890 ...
```

处理结果：
* `DSH-plugin`：`fetch` 拿到远端 `3ae4ed6`（API 写入的那次 README 修正），备份本地 commit
  `backup/pre-proxy-sync-20261104-1030` 后 `reset --hard origin/main` → 本地=远端=**3ae4ed6**，工作树干净；
* `dsh-custom-setting`：同样操作 → 本地=远端=**c06a32a**，干净；
* 子模块核对：`plugins/dsh-git-plugin@8681bb2`、`plugins/dsh-panellist-collapse@d900b61`，与远端 gitlink 一致；
* `scripts/push.ps1` 已改为**自动读取系统代理**（`DSH_GIT_PROXY` > `HTTPS_PROXY` > IE 代理）并同时脱敏
  token 与 base64 Authorization 头；下次直接 `scripts\push.cmd` 即可。

## 8. PAT 轮换工具（安全收尾）

因一次失败 push 把 base64 Authorization 回显进了本机会话日志，建议轮换 PAT。新增：

* `scripts\rotate-pat.ps1` + `scripts\rotate-pat.cmd`（PS 5.1，BOM）；
* `-CheckOnly`：只校验当前凭据（实测输出：账号 `asdw159632`、scopes `gist, repo, workflow`、代理 `http://127.0.0.1:7890`）；
* 轮换流程（脚本内自动）：隐藏输入新 token → `api.github.com` 校验 → `git-credential-manager store`
  写入 Windows 凭据管理器（stdin 传 token，不走 argv）→ 回读并比对 SHA256 → `git ls-remote` 实测 → 提示删除旧 token；
* 安全约定：不打印 token、不写任何文件；`-TokenFile`（可选）读后即删。
* 凭据存放：Windows 凭据管理器 `git:https://github.com`（用户 asdw159632），系统 `credential.helper=manager`；
  `~/.git-credentials` 是空文件，`GITHUB_TOKEN` 环境变量未设置 —— 轮换只需更新凭据管理器一处。
* 用户在 GitHub 侧的操作：Settings → Developer settings → Personal access tokens (classic) →
  新建（勾 `repo`，按需 `gist`/`workflow`）→ 用脚本写入 → 验证 → **删除旧 token**（<https://github.com/settings/tokens>）。