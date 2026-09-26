# Changelog

## 1.0.2 - 2026-09-26

- **修复：按 Copilot 键会弹出一个 cmd / 终端窗口。** 钩子过去用 ShellExecute（`UseShellExecute = true`）启动
  `launch-dsh.cmd`，ShellExecute 必然给 `cmd.exe` 新建控制台，Windows 11 又把这个控制台交给默认终端应用托管，
  于是每次按键都在屏幕最前面弹一个终端窗口。现在改用 `CreateProcess` + `CREATE_NO_WINDOW`
  （`UseShellExecute = false` / `CreateNoWindow = true`）：`cmd → powershell` 整条链照旧，只是从创建起就没有窗口。
  GUI 程序不受影响 —— 隐藏链里 `Start-Process` 启动的桌面端窗口照常出现。
- `launch-dsh.cmd` 失败时的 `pause`（等人按键）加了 `DSH_COPILOT_HIDDEN` 守卫：watcher 会给隐藏运行的子进程设这个
  环境变量，否则失败会留下一个**看不见、却一直等人按键**的进程。手动双击运行时行为不变。
- `config.ini` 的 `launcher` / `log` 现在支持相对路径（相对配置文件所在目录），与 `config.example.ini` 里的说明一致 ——
  以前相对值被原样使用，只是因为计划任务的工作目录恰好是钩子目录才没出问题。
- 新增两个回归测试：`hook/test/windowwatch.ps1`（触发一次按键，检查期间是否冒出任何窗口）、
  `hook/test/hidden-gui-test.ps1`（隐藏链里启动的 GUI 窗口仍然可见）。
  `hook/test/cold-start-test.ps1` 增加 `DSH_LAUNCH_FORCE_WEB=1` 以跳过"桌面端优先"分支，否则它够不到 Web 路径。
- CI：标签推送时自动把新编译的 exe 作为 Release 资产上传（连同 `DshCopilotKey.exe.sha256`），
  下载链接不会再指向旧二进制。
- 插件（npm `dsh-copilot-key`）本次无改动，仍为 1.0.1。

## 1.0.1 - 2026-09-26

- 文档补齐：安装章节覆盖全部路径（桌面端 App / 全局 CLI / **npx** / 插件市场），钩子新增 Release 直接下载命令与 SHA256 校验。
- 新增「按一下 Copilot 键实际会发生什么」完整顺序说明，写明启动器的 npx 回退（`npx -y @deepseek-ai/dsh@alpha web`）会联网下载 dsh，以及如何关掉这一步。

## 1.0.0 - 2026-09-26

- `hook/`: Copilot 硬件键（LeftWin+LeftShift+F23）低级键盘钩子，吞键 + 补发修饰键以避免开始菜单弹出；
  冷启动或聚焦 DeepSeek Harness；登录自启计划任务；`build/install/uninstall/selftest` 脚本；实测键码采集工具。
- `plugin/`: DSH 插件 `dsh-copilot-key`，7 个 `copilot_key_*` 工具（status / start / stop / restart / trigger / config / log）；
  配置读写带校验与时间戳备份；钩子每次按键重读 `config.ini`，改完下一次按键生效。
