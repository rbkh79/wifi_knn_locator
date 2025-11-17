@echo off
echo ========================================
echo WiFi KNN Locator - Build AAB Script
echo ========================================
echo.

REM Check if Flutter is installed
where flutter >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Flutter is not installed or not in PATH
    echo Please install Flutter from https://flutter.dev
    echo Or add Flutter to your PATH
    pause
    exit /b 1
)

echo [1/3] Getting Flutter dependencies...
call flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to get dependencies
    pause
    exit /b 1
)

echo.
echo [2/3] Building Release AAB (App Bundle)...
call flutter build appbundle --release
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to build AAB
    pause
    exit /b 1
)

echo.
echo [3/3] Build completed successfully!
echo.
echo AAB location: build\app\outputs\bundle\release\app-release.aab
echo.
echo This AAB file can be uploaded to Google Play Store.
echo.
pause




