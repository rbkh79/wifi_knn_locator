@echo off
setlocal
cd /d "%~dp0"
python apply_bts_extended_update.py "%CD%"
if errorlevel 1 (
  echo.
  echo The script must be placed in the ROOT of the wifi_knn_locator repository.
  echo Copy this package's contents into the repository root, then run again.
  pause
  exit /b 1
)
echo.
echo Source files updated. Review changes in GitHub Desktop, then Commit and Push.
pause
