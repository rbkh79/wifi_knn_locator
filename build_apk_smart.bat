@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================================
echo WiFi KNN Locator - ساخت APK (نسخه هوشمند)
echo ========================================
echo.

REM جستجوی Flutter در مسیرهای معمول
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

REM اگر پیدا نشد، از کاربر بپرس
:not_found
echo [✗] Flutter در مسیرهای معمول پیدا نشد
echo.
echo لطفاً یکی از گزینه‌های زیر را انتخاب کنید:
echo.
echo 1. اگر Flutter نصب دارید، مسیر کامل flutter.bat را وارد کنید
echo    مثال: C:\flutter\bin\flutter.bat
echo.
echo 2. اگر Flutter نصب ندارید:
echo    - دانلود از: https://flutter.dev/docs/get-started/install/windows
echo    - یا از Chocolatey: choco install flutter
echo.
set /p FLUTTER_PATH="مسیر flutter.bat را وارد کنید (یا Enter برای خروج): "

if "!FLUTTER_PATH!"=="" (
    echo.
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
echo [1/4] بررسی Flutter...
"!FLUTTER_PATH!" --version
if %ERRORLEVEL% NEQ 0 (
    echo [خطا] Flutter کار نمی‌کند
    pause
    exit /b 1
)
echo.

echo [2/4] نصب وابستگی‌ها...
"!FLUTTER_PATH!" pub get
if %ERRORLEVEL% NEQ 0 (
    echo [خطا] نصب وابستگی‌ها ناموفق بود
    pause
    exit /b 1
)
echo ✓ وابستگی‌ها نصب شدند
echo.

echo [3/4] پاک کردن build قبلی...
"!FLUTTER_PATH!" clean
echo.

echo [4/4] ساخت APK Release...
"!FLUTTER_PATH!" build apk --release
if %ERRORLEVEL% NEQ 0 (
    echo [خطا] ساخت APK ناموفق بود
    echo.
    echo لطفاً خطاهای بالا را بررسی کنید
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
echo 📱 برای نصب روی دستگاه:
echo    1. فایل APK را به دستگاه منتقل کنید
echo    2. روی فایل کلیک کنید و نصب را تأیید کنید
echo.
echo یا از طریق ADB:
echo    adb install build\app\outputs\flutter-apk\app-release.apk
echo.
pause


















