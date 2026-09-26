# dsh-copilot-key

把笔记本上的 **Copilot 硬件键**变成「启动 / 唤起 DeepSeek Harness」，并且能**在 DSH 里直接管理**它。

两部分：

| 目录 | 是什么 |
|---|---|
| [`hook/`](hook/) | 自研按键钩子（9 KB C#，无第三方依赖）：识别 Copilot 组合键、避免开始菜单弹出、启动或聚焦 DSH。带登录自启的计划任务。 |
| [`plugin/`](plugin/) | DeepSeek Harness 插件 `dsh-copilot-key`：在 App 内管理钩子 —— 状态、启停、手动触发、改配置、看日志，并暴露 7 个 agent 工具。 |

## 为什么要在 App 里管它

钩子必须在 App 之外运行 —— 否则 App 关着时按键就没人接。所以分工是：

- **钩子 + 计划任务**：按键本身，冷启动 DSH（App 没开也能按）；
- **插件**：在运行中的 App 里做管理（状态/启停/配置/日志），并让 AI 助手能直接操作它。

## 安装

### 1. 钩子

```powershell
git clone https://github.com/plumeume/dsh-copilot-key
cd dsh-copilot-key\hook
powershell -ExecutionPolicy Bypass -File build.ps1      # 用系统自带 csc.exe 编译
copy config.example.ini config.ini                     # 按需改 trigger / launcher / dryrun
powershell -ExecutionPolicy Bypass -File install.ps1    # 注册登录自启计划任务并立即启动
```

不想自己编译？从 Releases 下载 `DshCopilotKey.exe`（附 SHA256 校验值）。

### 2. 插件

npm 安装（推荐，市场也可一键装）：

```
dsh plugin --profile <你的 profile> add dsh-copilot-key     # 命令行安装（CLI 能管的 profile）
```

桌面端（DeepSeek Harness.exe）的 profile 由 Electron 独占、CLI 会拒绝 `--profile desktop`，
请在 **设置 → 插件 → 添加插件** 里填 `dsh-copilot-key`。

插件默认去 `%USERPROFILE%\copilot-key` 找钩子；钩子装在别处就设环境变量
`DSH_COPILOT_KEY_DIR`，或在 profile 的 patch 层里覆盖 `directory`。

## 插件提供的工具

| 工具 | 作用 |
|---|---|
| `copilot_key_status` | 钩子进程/PID、计划任务状态、当前 config.ini、日志末尾 |
| `copilot_key_start` / `_stop` / `_restart` | 启停重启钩子 |
| `copilot_key_trigger` | 等效按一下这个键 |
| `copilot_key_config` | 读写 `trigger` / `port` / `url` / `launcher` / `dryrun`（带校验与时间戳备份） |
| `copilot_key_log` | 看 watcher / launcher / capture 日志 |

## 兼容性

- Windows 10/11（测试于 Windows 11 build 26200）；钩子用 Win32 低级键盘钩子 + `System.Windows.Forms`，无第三方依赖。
- 插件实测 DSH 内核 **0.1.7-rc.2**；依赖 `defineTool`、`dsh.bundle.patch`、`dsh.profile.bundles`。
- 钩子需要在 **Medium 完整性级别**下运行；若安装目录被打了 Low 标签（`icacls <dir>` 查看），钩子拉起的进程会写不了 `%USERPROFILE%\.dsh`，修复见 [hook/README.md](hook/README.md)。

## License

MIT
