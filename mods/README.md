# mods —— DSH 客户端定制需求

本目录存放针对 DSH 客户端的各个定制修改，**一个需求一个子目录**。

## 约定

```
mods/
└── <需求名>/
    ├── README.md      # 需求目标、涉及的 DSH 部分、当前状态
    └── ...            # 该需求的源码 / 补丁 / 配置
```

* 需求目录名用简短小写英文 + 连字符，例如 `theme-dark/`、`tool-panel/`。
* 改动只放在自己的需求目录内，避免跨需求互相污染。
* 新增需求后，在 `memory/MEMORY.md` 的目录约定一节按需补充记录。
* 每完成一个阶段，在仓库根目录提交一次 git（并在 `logs/` 写日志）。

## 现有需求

| 需求 | 目录 | 状态 |
| --- | --- | --- |
| 侧栏工作区分活跃/沉默分组 | `active-workspaces/` | 补丁已写回 asar（事故后已恢复），有验收与补丁文档 |
| 极简模式（preset `minimal`）调研 | `agent-preset-minimal/` | 调研完成，结论见 memory §7 |
| 右侧栏编辑器选型 | `sidebar-editor/` | 选型完成（`dsh-better-sidebar@0.24.1`），待安装 |
| WSL 执行可行性 | `wsl-execution/` | 调研完成，四条路线见 memory §8 |
| 桌面端接管 `dsh` 命令 | `dsh-command-desktop/` | 调研 + 只读校验完成，待用户在 GUI 点「管理 dsh 命令…」安装 |
| 定制模式（preset `custom`） | `agent-preset-custom/` | 已实装 desktop profile（memory §10） |
| 标·准· 模式（preset `standard-assistant`） | `agent-preset-standard-assistant/` | 已实装 desktop profile（memory §12） |
| 侧栏面板列表折叠（插件 `@local/dsh-panellist-collapse`） | `sidebar-panellist-collapse/` | 已安装进 desktop profile（memory §13） |
