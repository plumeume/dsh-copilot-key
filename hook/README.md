# Copilot 键 → 启动 DeepSeek Harness（钩子）

把笔记本上的 **Copilot 硬件键**重新映射为「启动 / 唤起 DeepSeek Harness」。
不依赖 PowerToys / AutoHotkey，全部由本目录内一个 ~9 KB 的自研 C# 小工具完成。

## 这个键实际发出什么

用 `DshCopilotKey.exe capture` 实测（Windows 11 build 26200），Copilot 键发出的正是微软规范定义的组合键：

```
LWin down (vk=0x5B, ext=1)
LShift down (vk=0xA0, scan=0x2A)
F23 down  (vk=0x86, scan=0x6E)
... 抬起顺序相反
```

因为 Windows 把 `Win` 视为"单独按下"，**直接按这个键会弹出开始菜单**。本工具在识别到组合键时会：

1. 吞掉 F23 的按下/抬起事件（不让系统 Copilot 处理器看到）；
2. 立刻补发 `LShift↑` `LWin↑`（避免开始菜单弹出）；
3. 吞掉随后到达的物理 `LShift↑` `LWin↑`，保证修饰键状态平衡；
4. 执行启动动作。

## 安装（两种方式）

**A. 直接用 Release 的 exe**（不用装编译环境）

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

# exe 由 CI 现场编译，哈希随构建变化，所以 .sha256 随 Release 一起发布
$want = (Get-Content "$dir\DshCopilotKey.exe.sha256" -Raw).Split()[0]
$have = (Get-FileHash "$dir\DshCopilotKey.exe" -Algorithm SHA256).Hash
if ($want -ne $have) { throw "SHA256 mismatch: $have" } else { "SHA256 OK: $have" }

powershell -ExecutionPolicy Bypass -File "$dir\install.ps1"
```

**B. 克隆后自己编译**：`git clone … && cd hook && powershell -File build.ps1`（见下"常用命令"）。

> `install.ps1` / `uninstall.ps1` 都用 `$PSScriptRoot`，放哪都行；`config.ini` 必须与 exe 同目录。

## 按键后的行为（完整顺序）

每次按键都会把判定结果写进 `watcher.log`。顺序是：

1. **桌面端在运行** → 聚焦它的窗口（`AppActivate`），结束；
2. 桌面端**已安装未运行** → 启动 `%LOCALAPPDATA%\Programs\DeepSeek Harness\DeepSeek Harness.exe`，结束；
3. 否则退回 **Web 版**：`config.ini` 的 `port`（默认 3080）已在监听 → 用默认浏览器打开 `url`，结束；
4. 否则执行 `config.ini` 的 `launcher`（默认 `launch-dsh.cmd` → `launch-dsh.ps1`），按顺序尝试：
   1. PATH 上的 `dsh` → `dsh web`
   2. `%LOCALAPPDATA%\npm-cache\_npx` 中**版本最高**的缓存构建 → `node <bin.js> web`
   3. 都没有 → **`npx -y @deepseek-ai/dsh@alpha web`**：这一步会**联网下载**一个 dsh 到 npx 缓存（首次较慢，之后复用）
5. `dsh web` 就绪后自己打开浏览器；启动器只在第 3 步（端口已在监听）开浏览器 —— 两条路径都只开一次，不会出现两个标签页。

> **全程不弹窗（1.0.2 起）**：第 4 步的 `cmd` 与 `powershell` 是控制台程序，钩子过去用 ShellExecute 启动它们，
> ShellExecute 必然新建控制台，Windows 11 又把它交给默认终端托管 —— 于是每次按键都闪一个终端窗口。
> 现在改为 `CreateProcess` + `CREATE_NO_WINDOW`（`UseShellExecute=false` / `CreateNoWindow=true`），
> 控制台从创建起就没有窗口；用 `Start-Process` 起的 GUI 程序不受影响。

> **只想用桌面端**：把 `config.ini` 的 `launcher` 指向自己的脚本即可，例如
> `Start-Process "$env:LOCALAPPDATA\Programs\DeepSeek Harness\DeepSeek Harness.exe"`，
> 这样第 4 步永远不会去下 Web 版。想只记录不启动：`dryrun = 1`。
> 自定义 `launcher` 也同样是隐藏运行的；失败时需要交互（`pause`）就要先判断 `DSH_COPILOT_HIDDEN`。

> **只想用桌面端**：把 `config.ini` 的 `launcher` 指向自己的脚本即可，例如
> `Start-Process "$env:LOCALAPPDATA\Programs\DeepSeek Harness\DeepSeek Harness.exe"`，
> 这样第 4 步永远不会去下 Web 版。想只记录不启动：`dryrun = 1`。

## 文件

| 文件 | 作用 |
|---|---|
| `DshCopilotKey.cs` | 源码（Win32 低级键盘钩子 + SendInput） |
| `build.ps1` | 用系统自带 `csc.exe` 编译 |
| `config.example.ini` | 配置模板：触发方式 / 端口 / URL / 启动脚本 / 日志 / dryrun（`launcher` / `log` 可写相对路径，相对本文件所在目录） |
| `launch-dsh.ps1` `.cmd` | 冷启动脚本：优先聚焦/启动桌面端，否则起 Web 服务并等端口通了再开浏览器。由钩子**隐藏**运行（`DSH_COPILOT_HIDDEN=1`），屏幕上不弹窗 |
| `install.ps1` | 注册登录自启的计划任务并立即启动 |
| `uninstall.ps1` | 卸载：删除计划任务并结束进程 |
| `selftest.ps1` | 自检：模拟按键，校验钩子命中 + 开始菜单未弹出 + 启动链路执行 |
| `test/cold-start-test.ps1` | 冷启动自检：用桩服务验证"起服务 → 开浏览器"整条链路（设 `DSH_LAUNCH_FORCE_WEB=1` 跳过桌面端分支） |
| `test/windowwatch.ps1` | 静默回归：触发一次按键，记录期间出现的每个可见窗口 —— 期望 **0** 个命令行窗口 |
| `test/hidden-gui-test.ps1` | 静默回归：隐藏链里 `Start-Process` 起的 GUI 窗口仍然可见（默认拿记事本模拟桌面端） |

## 常用命令

```powershell
# 编译（系统自带 .NET Framework 的 csc.exe，无需 SDK）
powershell -ExecutionPolicy Bypass -File build.ps1

# 安装（注册计划任务，登录自启、崩溃自动重启）并立即启动
powershell -ExecutionPolicy Bypass -File install.ps1

# 自检
powershell -ExecutionPolicy Bypass -File selftest.ps1

# 静默回归（触发一次按键，检查有没有闪出窗口）
powershell -ExecutionPolicy Bypass -File test\windowwatch.ps1
powershell -ExecutionPolicy Bypass -File test\hidden-gui-test.ps1

# 手动触发一次（等价于按一下这个键）
& .\DshCopilotKey.exe trigger

# 只记录不启动：config.ini 里 dryrun = 1（下一次按键即生效，无需重启）

# 重新采集按键码（换键盘/换机型时排查）
& .\DshCopilotKey.exe capture capture.log 60

# 卸载，恢复原状
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

## 故障排查

### 按 Copilot 键会弹出 cmd / 终端窗口（1.0.2 已修）

1.0.1 及更早版本里，钩子用 `ProcessStartInfo` + `UseShellExecute = true` 启动 `launch-dsh.cmd`。
ShellExecute 必然给 `cmd.exe` 新建控制台，Windows 11 又把这个控制台交给默认终端应用托管，
于是每次按键都在最前面弹一个终端窗口（实测两个窗口事件：先是空的 `Terminal`，再是带标题的 `管理员: DeepSeek Harness`）。

修法见源码里 `Program.StartHidden`：`UseShellExecute = false` + `CreateNoWindow = true`，
也就是 `CreateProcess` 带 `CREATE_NO_WINDOW`。子进程照样有控制台，只是没有窗口。

回归验证：

```powershell
powershell -ExecutionPolicy Bypass -File test\windowwatch.ps1
# 修复前: 1,966ms  + NEW WINDOW  14556|WindowsTerminal|管理员:  DeepSeek Harness
# 修复后: console/terminal windows opened: 0 / RESULT: PASS

powershell -ExecutionPolicy Bypass -File test\hidden-gui-test.ps1
# PASS  GUI window appeared from the hidden chain (notepad pid 1234, title '记事本')
```

### 按键后 DSH 起不来，报 `EPERM ... .dsh\profiles\<p>\cordis.yml`

根因通常不在 DSH：**安装目录被打了 Low 完整性标签并向下继承**，计划任务从该目录拉起进程时，
整条链（DshCopilotKey → cmd → powershell → node）都以 Low IL 运行；Low 进程受 no-write-up 限制，
写不了 Medium 的 `%USERPROFILE%\.dsh`，内核返回 ACCESS_DENIED，Node 报成 `EPERM`。

判断（S-1-16-4096 = Low，S-1-16-8192 = Medium）：

```powershell
whoami /groups | Select-String 'S-1-16-'
icacls <钩子所在目录> | Select-String 'Mandatory'
```

修复：

```powershell
icacls <钩子所在目录> /setintegritylevel "(OI)(CI)Medium"
```

然后重启钩子（注销/登录，或 `Stop-Process DshCopilotKey` 后再 `Start-ScheduledTask DshCopilotKey`），再按键。

### 按键没反应

```powershell
Get-Process DshCopilotKey                       # 钩子在跑吗
Get-Content .\watcher.log -Tail 20              # 每次按键都有记录
Get-ScheduledTask -TaskName DshCopilotKey       # 计划任务状态
```

`watcher.log` 里每条记录都带判定结果（是否命中组合键、是否 dryrun、走了哪条启动路径）。
