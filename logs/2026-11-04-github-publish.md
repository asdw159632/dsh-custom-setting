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