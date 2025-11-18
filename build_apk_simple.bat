@echo off
chcp 65001 >nul
echo ========================================
echo WiFi KNN Locator - ساخت APK
echo ========================================
echo.

REM بررسی وجود Flutter
where flutter >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [خطا] Flutter یافت نشد!
    echo.
    echo لطفاً یکی از کارهای زیر را انجام دهید:
    echo 1. Flutter را نصب کنید: https://flutter.dev
    echo 2. Flutter را به PATH اضافه کنید
    echo 3. یا از مسیر کامل Flutter استفاده کنید
    echo.
    echo مثال: C:\flutter\bin\flutter build apk --release
    echo.
    pause
    exit /b 1
)

echo [1/4] بررسی Flutter...
call flutter doctor --android-licenses >nul 2>nul
call flutter --version
echo.

echo [2/4] نصب وابستگی‌ها...
call flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo [خطا] نصب وابستگی‌ها ناموفق بود
    pause
    exit /b 1
)
echo ✓ وابستگی‌ها نصب شدند
echo.

echo [3/4] پاک کردن build قبلی...
call flutter clean
echo.

echo [4/4] ساخت APK Release...
call flutter build apk --release
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




