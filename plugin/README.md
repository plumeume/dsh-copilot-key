# dsh-copilot-key (plugin)

DeepSeek Harness 插件：在 App 里管理 [Copilot 键钩子](../hook/)。

- 钩子（`DshCopilotKey.exe` + 登录计划任务）负责按键本身 —— App 没开也能把 DSH 拉起来；
- 本插件负责**管理**它，并把它变成 agent 可用的能力。

## 安装

```
dsh plugin --profile <profile> add dsh-copilot-key
```

桌面端（DeepSeek Harness.exe）的 profile 由 Electron 独占管理，CLI 会拒绝 `--profile desktop`：
请在 **设置 → 插件 → 添加插件** 里填 `dsh-copilot-key`。

## 钩子在哪

解析顺序：

1. profile patch 层里 `- id: copilot-key` 的 `config.directory`；
2. 环境变量 `DSH_COPILOT_KEY_DIR`；
3. `%USERPROFILE%\copilot-key`。

`copilot_key_status` 会显示当前解析到的路径以及可执行文件是否存在。

## 工具

| 工具 | 参数 | 作用 |
|---|---|---|
| `copilot_key_status` | – | 钩子进程/PID、计划任务状态、config.ini、watcher.log 末尾 |
| `copilot_key_start` | – | 未运行时启动钩子（GUI 进程，不闪控制台） |
| `copilot_key_stop` | – | 停止钩子（计划任务可能按崩溃自动重启把它拉回来） |
| `copilot_key_restart` | – | 停掉所有钩子进程并重新起一个 |
| `copilot_key_trigger` | – | 等效按一下这个键 |
| `copilot_key_config` | `trigger` `port` `url` `launcher` `dryrun` | 不传参=读取；传参=修改（校验 + 时间戳备份） |
| `copilot_key_log` | `file`(watcher/launcher/capture) `lines` | 看日志 |

钩子**每次按键都重新读** `config.ini`，所以改完配置下一次按键就生效，不用重启钩子。

## 配置（profile patch 层可选覆盖）

```yaml
- id: copilot-key
  name: dsh-copilot-key
  config:
    directory: D:/tools/copilot-key   # 钩子所在目录
    exeName: DshCopilotKey.exe
    taskName: DshCopilotKey
    logLines: 10
```

## 两种安装方式的区别

| 方式 | 依赖怎么来 | 需要额外操作吗 |
|---|---|---|
| `npm` / 市场安装（推荐） | DSH 会给**装在 profile 里**的插件解析 `@deepseek-ai/*` 共享包（runtime 的 sharedPackages），peer 依赖由平台提供 | 不需要 |
| `link:` 本地源码安装 | 插件真实路径在 profile 之外，Node 从那里往上找不到 `@deepseek-ai/*` | 需要把依赖闭包放进插件自己的 `node_modules`（或让它成为 profile 内的一份拷贝） |

`link:` 装法下钩子目录可以用环境变量 `DSH_COPILOT_KEY_DIR` 指过去；也可以在 profile 的
patch 层里写死：

```yaml
- id: copilot-key
  name: dsh-copilot-key
  config:
    directory: C:/dsh/copilot-key
```

## 兼容性

实测 DSH 内核 **0.1.7-rc.2**；用到 `@deepseek-ai/dsh-tools` 的 `defineTool`、`dsh.bundle.patch` 与 `dsh.profile.bundles`。

## License

MIT
