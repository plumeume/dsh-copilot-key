# Changelog

## 1.0.0 - 2026-09-26

- `hook/`: Copilot 硬件键（LeftWin+LeftShift+F23）低级键盘钩子，吞键 + 补发修饰键以避免开始菜单弹出；
  冷启动或聚焦 DeepSeek Harness；登录自启计划任务；`build/install/uninstall/selftest` 脚本；实测键码采集工具。
- `plugin/`: DSH 插件 `dsh-copilot-key`，7 个 `copilot_key_*` 工具（status / start / stop / restart / trigger / config / log）；
  配置读写带校验与时间戳备份；钩子每次按键重读 `config.ini`，改完下一次按键生效。
