# Changelog

## 1.0.1 - 2026-09-26

- 文档补齐：安装章节覆盖全部路径（桌面端 App / 全局 CLI / **npx** / 插件市场），钩子新增 Release 直接下载命令与 SHA256 校验。
- 新增「按一下 Copilot 键实际会发生什么」完整顺序说明，写明启动器的 npx 回退（`npx -y @deepseek-ai/dsh@alpha web`）会联网下载 dsh，以及如何关掉这一步。

## 1.0.0 - 2026-09-26

- `hook/`: Copilot 硬件键（LeftWin+LeftShift+F23）低级键盘钩子，吞键 + 补发修饰键以避免开始菜单弹出；
  冷启动或聚焦 DeepSeek Harness；登录自启计划任务；`build/install/uninstall/selftest` 脚本；实测键码采集工具。
- `plugin/`: DSH 插件 `dsh-copilot-key`，7 个 `copilot_key_*` 工具（status / start / stop / restart / trigger / config / log）；
  配置读写带校验与时间戳备份；钩子每次按键重读 `config.ini`，改完下一次按键生效。
