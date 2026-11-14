@echo off
chcp 65001 >nul
cd /d "%~dp0"
where python >nul 2>nul
if errorlevel 1 (
  echo Python غير مثبت على هذا الجهاز.
  echo حمّله من https://www.python.org/downloads/ ثم أعد المحاولة.
  pause
  exit /b 1
)
python "%~dp0bridge.py" --port 8756
pause
