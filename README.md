# dsh-copilot-key

把笔记本上的 **Copilot 硬件键**变成「启动 / 唤起 DeepSeek Harness」，并且能**在 DSH 里直接管理**它。

两部分：

| 目录 | 是什么 |
|---|---|
| [`hook/`](hook/) | 自研按键钩子（9 KB C#，无第三方依赖）：识别 Copilot 组合键、避免开始菜单弹出、启动或聚焦 DSH。带登录自启的计划任务。 |

按下这个键**不会弹出任何窗口**：启动链（`cmd → powershell`）以 `CREATE_NO_WINDOW` 运行，从创建起就没有控制台；
唯一会出现的窗口就是 DeepSeek Harness 自己的窗口。
| [`plugin/`](plugin/) | DeepSeek Harness 插件 `dsh-copilot-key`：在 App 内管理钩子 —— 状态、启停、手动触发、改配置、看日志，并暴露 7 个 agent 工具。 |

## 为什么要在 App 里管它

钩子必须在 App 之外运行 —— 否则 App 关着时按键就没人接。所以分工是：

- **钩子 + 计划任务**：按键本身，冷启动 DSH（App 没开也能按）；
- **插件**：在运行中的 App 里做管理（状态/启停/配置/日志），并让 AI 助手能直接操作它。

## 安装

### 1. 钩子（按键本身）

**方式 A：直接下载 Release 里的 exe（推荐，不用装编译环境）**

```powershell
$dir = "$env:USERPROFILE\copilot-key"
New-Item -ItemType Directory $dir -Force | Out-Null
$base = "https://github.com/plumeume/dsh-copilot-key"
$raw  = "https://raw.githubusercontent.com/plumeume/dsh-copilot-key/master/hook"

Invoke-WebRequest "$base/releases/download/v1.0.2/DshCopilotKey.exe"        -OutFile "$dir\DshCopilotKey.exe"
Invoke-WebRequest "$base/releases/download/v1.0.2/DshCopilotKey.exe.sha256" -OutFile "$dir\DshCopilotKey.exe.sha256"
Invoke-WebRequest "$raw/config.example.ini" -OutFile "$dir\config.ini"
Invoke-WebRequest "$raw/install.ps1"        -OutFile "$dir\install.ps1"
Invoke-WebRequest "$raw/uninstall.ps1"      -OutFile "$dir\uninstall.ps1"

# 校验：exe 由 CI 现场编译，哈希随构建变化，所以 .sha256 随 Release 一起发布
$want = (Get-Content "$dir\DshCopilotKey.exe.sha256" -Raw).Split()[0]
$have = (Get-FileHash "$dir\DshCopilotKey.exe" -Algorithm SHA256).Hash
if ($want -ne $have) { throw "SHA256 mismatch: $have" } else { "SHA256 OK: $have" }

# 注册登录自启的计划任务并立即启动
powershell -ExecutionPolicy Bypass -File "$dir\install.ps1"
```

> 脚本都用 `$PSScriptRoot`，目录放哪都行；但 `config.ini` 必须和 `DshCopilotKey.exe` 同目录。
> GitHub 直连不稳时，把上面两个域名换成镜像/代理地址即可。

**方式 B：克隆仓库自己编译**（用系统自带 `csc.exe`，不需要 .NET SDK）

```powershell
git clone https://github.com/plumeume/dsh-copilot-key
cd dsh-copilot-key\hook
powershell -ExecutionPolicy Bypass -File build.ps1      # 编译 DshCopilotKey.exe
copy config.example.ini config.ini                      # 按需改 trigger / launcher / dryrun
powershell -ExecutionPolicy Bypass -File install.ps1    # 注册登录自启并立即启动
```

**卸载**：`powershell -ExecutionPolicy Bypass -File uninstall.ps1`（删除计划任务 + 结束进程）

### 2. 插件（在 App 里管理钩子）

| 你的 DSH 是怎么装的 | 怎么装插件 |
|---|---|
| **桌面端**（DeepSeek Harness.exe） | **设置 → 插件 → 添加插件**，填 `dsh-copilot-key`（桌面端 profile 由 Electron 独占，CLI 会拒绝 `--profile desktop`） |
| 全局 CLI（`npm i -g @deepseek-ai/dsh`） | `dsh plugin --profile <profile> add dsh-copilot-key` |
| **没有全局 CLI、用 npx 跑 dsh** | `npx -y @deepseek-ai/dsh@alpha plugin --profile <profile> add dsh-copilot-key` |
| 插件市场 | 搜 `dsh-copilot-key` 一键安装 |

> npx 方式不会全局安装任何东西：npx 把 dsh 下到 `%LOCALAPPDATA%\npm-cache\_npx` 后复用。
> 也可以 `npm i -g dsh-copilot-key`，但插件要生效仍需把它加进 profile 的 `dsh.profile.bundles`
> —— 用上面的命令或 App 界面做这一步即可。

插件默认去 `%USERPROFILE%\copilot-key` 找钩子；钩子装在别处就设环境变量
`DSH_COPILOT_KEY_DIR`，或在 profile 的 patch 层里覆盖 `directory`。

## 按一下 Copilot 键，实际会发生什么

钩子按这个顺序尝试（每一步都会写进 `watcher.log`）：

1. **桌面端在运行** → 聚焦它的窗口（`AppActivate`，不新建窗口）；
2. 桌面端**已安装但没运行** → 启动 `%LOCALAPPDATA%\Programs\DeepSeek Harness\DeepSeek Harness.exe`；
3. 否则退回 **Web 版**：`config.ini` 的 `port` 已在监听 → 用默认浏览器打开 `url`；
4. 否则执行 `config.ini` 的 `launcher`（默认 `launch-dsh.cmd` → `launch-dsh.ps1`），它依次尝试：
   - PATH 上的 `dsh` → `dsh web`
   - `%LOCALAPPDATA%\npm-cache\_npx` 里**版本最高**的缓存构建 → `node <bin.js> web`
   - 都没有 → **`npx -y @deepseek-ai/dsh@alpha web`**（⚠️ 这一步会**联网下载**一个新的 dsh 到 npx 缓存）
5. `dsh web` 就绪后由它自己打开浏览器；启动器只在第 3 步（端口已在监听）时开浏览器，避免开出两个标签页。

> **第 4 步全程不可见（1.0.2 起）**：钩子用 `CreateProcess` + `CREATE_NO_WINDOW` 而非 ShellExecute 启动启动器，
> `cmd` 与 `powershell` 从创建起就没有控制台窗口，按键不会再闪出 cmd / 终端窗口。
> 若你自己写 `launcher`，同样不必担心弹窗；但失败时的 `pause` 之类要留意 —— 隐藏运行的子进程会拿到
> `DSH_COPILOT_HIDDEN=1`，可以用 `if not defined DSH_COPILOT_HIDDEN` 跳过。

> 只用桌面端、不希望第 4 步去下 Web 版？把 `config.ini` 的 `launcher` 指向你自己的脚本
> （例如只做 `Start-Process "$env:LOCALAPPDATA\Programs\DeepSeek Harness\DeepSeek Harness.exe"`）。
> 想只记录不启动，把 `dryrun` 改成 `1`（下一次按键即生效）。

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
