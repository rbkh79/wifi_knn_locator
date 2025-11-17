# راهنمای ساخت APK و AAB

این راهنما نحوه ساخت فایل APK و AAB برای نصب روی دستگاه اندروید را توضیح می‌دهد.

## روش 1: استفاده از اسکریپت‌های آماده (ساده‌ترین روش)

### ساخت APK Release (برای نصب مستقیم)
1. فایل `build_apk.bat` را دوبار کلیک کنید
2. منتظر بمانید تا build کامل شود
3. فایل APK در مسیر زیر قرار می‌گیرد:
   ```
   build\app\outputs\flutter-apk\app-release.apk
   ```

### ساخت APK Debug (برای تست)
1. فایل `build_apk_debug.bat` را دوبار کلیک کنید
2. فایل APK در مسیر زیر قرار می‌گیرد:
   ```
   build\app\outputs\flutter-apk\app-debug.apk
   ```

### ساخت AAB (برای Google Play Store)
1. فایل `build_aab.bat` را دوبار کلیک کنید
2. فایل AAB در مسیر زیر قرار می‌گیرد:
   ```
   build\app\outputs\bundle\release\app-release.aab
   ```

## روش 2: استفاده از دستورات Flutter (دستی)

### پیش‌نیازها
- Flutter SDK نصب شده باشد
- Android SDK نصب شده باشد
- Flutter در PATH سیستم باشد

### دستورات

```bash
# نصب وابستگی‌ها
flutter pub get

# ساخت APK Release
flutter build apk --release

# ساخت APK Debug
flutter build apk --debug

# ساخت AAB (App Bundle) برای Google Play
flutter build appbundle --release
```

## روش 3: استفاده از Codemagic (CI/CD)

اگر پروژه را در GitHub push کنید، می‌توانید از Codemagic برای ساخت خودکار استفاده کنید:

1. به [codemagic.io](https://codemagic.io) بروید
2. پروژه را connect کنید
3. یکی از workflow های زیر را انتخاب کنید:
   - `android_debug_apk` - برای ساخت APK Debug
   - `android_release_apk` - برای ساخت APK Release
   - `android_release_aab` - برای ساخت AAB

## نصب APK روی دستگاه

### روش 1: استفاده از ADB
```bash
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

### روش 2: انتقال دستی
1. فایل APK را به گوشی اندروید منتقل کنید (از طریق USB، ایمیل، یا ابر)
2. در گوشی، Settings > Security > Unknown Sources را فعال کنید
3. فایل APK را باز کنید و نصب کنید

## تفاوت APK و AAB

- **APK**: فایل نصب مستقیم برای اندروید. می‌توانید مستقیماً روی دستگاه نصب کنید.
- **AAB**: فرمت جدید Google Play Store. فقط برای آپلود در Play Store استفاده می‌شود.

## نکات مهم

1. **مجوزها**: اطمینان حاصل کنید که مجوزهای Location و WiFi در AndroidManifest.xml تنظیم شده‌اند (قبلاً تنظیم شده است).

2. **اندازه فایل**: 
   - APK Release معمولاً 20-30 مگابایت است
   - AAB معمولاً کوچک‌تر است (15-25 مگابایت)

3. **امضا (Signing)**: برای انتشار در Play Store، باید از keystore استفاده کنید. برای تست، از debug keystore استفاده می‌شود.

4. **حداقل نسخه اندروید**: این اپلیکیشن برای Android 5.0 (API 21) و بالاتر طراحی شده است.

## عیب‌یابی

### خطا: "Flutter is not installed"
- Flutter SDK را نصب کنید: https://flutter.dev/docs/get-started/install
- Flutter را به PATH اضافه کنید

### خطا: "Android SDK not found"
- Android Studio را نصب کنید
- Android SDK را از Android Studio نصب کنید
- متغیر محیطی ANDROID_HOME را تنظیم کنید

### خطا: "Gradle build failed"
- فایل `android/local.properties` را بررسی کنید
- مسیر Flutter SDK را در `local.properties` تنظیم کنید

## پشتیبانی

اگر مشکلی پیش آمد، لطفاً issue در GitHub ایجاد کنید.




