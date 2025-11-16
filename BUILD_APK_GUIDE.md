# راهنمای ساخت APK

## روش 1: استفاده از اسکریپت (ساده‌ترین روش)

### برای ساخت APK Release:
```bash
build_apk.bat
```

### برای ساخت APK Debug:
```bash
build_apk_debug.bat
```

## روش 2: استفاده از دستورات Flutter

### 1. نصب وابستگی‌ها
```bash
flutter pub get
```

### 2. ساخت APK Release (برای انتشار)
```bash
flutter build apk --release
```

### 3. ساخت APK Debug (برای تست)
```bash
flutter build apk --debug
```

### 4. ساخت APK Split (برای کاهش حجم - اختیاری)
```bash
flutter build apk --split-per-abi
```

## محل فایل APK

بعد از ساخت موفق، فایل APK در مسیر زیر قرار می‌گیرد:

- **Release APK**: `build\app\outputs\flutter-apk\app-release.apk`
- **Debug APK**: `build\app\outputs\flutter-apk\app-debug.apk`
- **Split APK**: `build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk` (و سایر معماری‌ها)

## نکات مهم

### 1. پیش‌نیازها
- Flutter SDK نصب شده باشد
- Flutter در PATH سیستم باشد
- Android SDK نصب شده باشد
- Java JDK نصب شده باشد

### 2. بررسی نصب Flutter
```bash
flutter doctor
```

### 3. اگر Flutter در PATH نیست:
- Windows: مسیر Flutter را به متغیر محیطی PATH اضافه کنید
- یا از مسیر کامل استفاده کنید:
```bash
C:\path\to\flutter\bin\flutter build apk --release
```

### 4. امضای APK (برای انتشار در Google Play)
برای انتشار در Google Play Store، باید APK را با کلید خود امضا کنید. 
فایل `android/app/build.gradle.kts` را ویرایش کنید و signing config خود را اضافه کنید.

### 5. کاهش حجم APK
برای کاهش حجم APK، از split-per-abi استفاده کنید:
```bash
flutter build apk --split-per-abi --release
```

این دستور سه APK جداگانه برای معماری‌های مختلف می‌سازد:
- armeabi-v7a (32-bit ARM)
- arm64-v8a (64-bit ARM)
- x86_64 (64-bit x86)

## نصب APK روی دستگاه

### روش 1: از طریق ADB
```bash
adb install build\app\outputs\flutter-apk\app-release.apk
```

### روش 2: انتقال دستی
1. فایل APK را به دستگاه Android خود منتقل کنید
2. روی فایل APK کلیک کنید
3. اگر پیام "Install from unknown sources" ظاهر شد، تنظیمات را فعال کنید
4. نصب را تأیید کنید

## عیب‌یابی

### خطا: "Flutter not found"
- مطمئن شوید Flutter نصب است
- Flutter را به PATH اضافه کنید
- یا از مسیر کامل استفاده کنید

### خطا: "Gradle build failed"
- Android SDK را بررسی کنید
- Java JDK را بررسی کنید
- دستور `flutter clean` را اجرا کنید و دوباره امتحان کنید

### خطا: "Permission denied"
- مجوزهای AndroidManifest.xml را بررسی کنید
- مطمئن شوید تمام مجوزهای لازم وجود دارند

## ساخت AAB (برای Google Play)

برای انتشار در Google Play Store، بهتر است از AAB استفاده کنید:

```bash
flutter build appbundle --release
```

فایل AAB در مسیر زیر قرار می‌گیرد:
`build\app\outputs\bundle\release\app-release.aab`


