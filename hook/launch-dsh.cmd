@echo off
title DeepSeek Harness
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch-dsh.ps1"
if errorlevel 1 (
  echo.
  echo [launch failed] press any key to close
  rem The watcher sets DSH_COPILOT_HIDDEN=1 when it starts us without a console (Copilot key).
  rem Pausing there would leave an invisible process waiting for a key press nobody can give.
  if not defined DSH_COPILOT_HIDDEN pause >nul
)
