@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================================
echo WiFi KNN Locator - ساخت APK (با پاک کردن Cache)
echo ========================================
echo.

REM جستجوی Flutter
set FLUTTER_PATH=
set SEARCH_PATHS=C:\flutter\bin\flutter.bat;%USERPROFILE%\flutter\bin\flutter.bat;C:\src\flutter\bin\flutter.bat;%LOCALAPPDATA%\flutter\bin\flutter.bat

echo [جستجو] در حال جستجوی Flutter...
for %%P in (%SEARCH_PATHS%) do (
    if exist "%%P" (
        set FLUTTER_PATH=%%P
        echo [✓] Flutter پیدا شد: %%P
        goto :found
    )
)

:not_found
echo [✗] Flutter در مسیرهای معمول پیدا نشد
set /p FLUTTER_PATH="مسیر flutter.bat را وارد کنید (یا Enter برای خروج): "

if "!FLUTTER_PATH!"=="" (
    echo خروج...
    pause
    exit /b 1
)

if not exist "!FLUTTER_PATH!" (
    echo [خطا] فایل پیدا نشد: !FLUTTER_PATH!
    pause
    exit /b 1
)

:found
echo.
echo [1/6] پاک کردن Flutter build cache...
"!FLUTTER_PATH!" clean
echo.

echo [2/6] پاک کردن build directory...
if exist build (
    rmdir /s /q build
    echo ✓ پوشه build پاک شد
)
echo.

echo [3/6] پاک کردن .dart_tool...
if exist .dart_tool (
    rmdir /s /q .dart_tool
    echo ✓ پوشه .dart_tool پاک شد
)
echo.

echo [4/6] نصب وابستگی‌ها...
"!FLUTTER_PATH!" pub get
if %ERRORLEVEL% NEQ 0 (
    echo [خطا] نصب وابستگی‌ها ناموفق بود
    pause
    exit /b 1
)
echo ✓ وابستگی‌ها نصب شدند
echo.

echo [5/6] بررسی کد...
"!FLUTTER_PATH!" analyze
if %ERRORLEVEL% NEQ 0 (
    echo [هشدار] برخی مشکلات در کد یافت شد، اما ادامه می‌دهیم...
)
echo.

echo [6/6] ساخت APK Release...
"!FLUTTER_PATH!" build apk --release
if %ERRORLEVEL% NEQ 0 (
    echo [خطا] ساخت APK ناموفق بود
    pause
    exit /b 1
)

echo.
echo ========================================
echo ✓ ساخت APK با موفقیت انجام شد!
echo ========================================
echo.
echo 📦 محل فایل APK:
echo    build\app\outputs\flutter-apk\app-release.apk
echo.
pause










