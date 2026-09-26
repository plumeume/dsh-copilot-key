@echo off
title DeepSeek Harness
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch-dsh.ps1"
if errorlevel 1 (
  echo.
  echo [launch failed] press any key to close
  pause >nul
)
