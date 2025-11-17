@echo off
echo ========================================
echo WiFi KNN Locator - Build APK Script
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
echo [2/3] Building Release APK...
call flutter build apk --release
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to build APK
    pause
    exit /b 1
)

echo.
echo [3/3] Build completed successfully!
echo.
echo APK location: build\app\outputs\flutter-apk\app-release.apk
echo.
echo You can now install this APK on your Android device.
echo.
pause




