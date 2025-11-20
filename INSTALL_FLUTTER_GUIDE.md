# راهنمای نصب Flutter برای ساخت APK

## مشکل: Flutter در PATH نیست

اگر پیام "Flutter is not installed or not in PATH" را می‌بینید، یکی از راه‌حل‌های زیر را انجام دهید:

## راه‌حل 1: استفاده از اسکریپت هوشمند (پیشنهادی)

فایل `build_apk_smart.bat` را اجرا کنید. این اسکریپت:
- به صورت خودکار Flutter را در مسیرهای معمول جستجو می‌کند
- اگر پیدا نشد، از شما مسیر Flutter را می‌پرسد

```bash
build_apk_smart.bat
```

## راه‌حل 2: نصب Flutter (اگر نصب ندارید)

### روش A: دانلود مستقیم

1. **دانلود Flutter SDK:**
   - به آدرس https://flutter.dev/docs/get-started/install/windows بروید
   - فایل ZIP را دانلود کنید

2. **استخراج:**
   - فایل را در یک مسیر استخراج کنید (مثلاً `C:\flutter`)
   - **نکته مهم:** مسیر نباید شامل فاصله یا کاراکترهای خاص باشد

3. **اضافه کردن به PATH:**
   - کلید `Win + R` را بزنید
   - `sysdm.cpl` را تایپ کنید و Enter بزنید
   - تب "Advanced" → "Environment Variables"
   - در "System variables"، متغیر "Path" را انتخاب کنید
   - "Edit" → "New"
   - مسیر `C:\flutter\bin` را اضافه کنید
   - OK را بزنید

4. **بررسی نصب:**
   - یک Command Prompt جدید باز کنید
   - دستور زیر را اجرا کنید:
   ```bash
   flutter doctor
   ```

### روش B: استفاده از Chocolatey

اگر Chocolatey نصب دارید:

```bash
choco install flutter
```

### روش C: استفاده از Git

```bash
git clone https://github.com/flutter/flutter.git -b stable
```

سپس مسیر `flutter\bin` را به PATH اضافه کنید.

## راه‌حل 3: استفاده از مسیر کامل (بدون نصب در PATH)

اگر Flutter نصب دارید اما در PATH نیست، می‌توانید از مسیر کامل استفاده کنید:

### ساخت APK با مسیر کامل:

```bash
# مثال (مسیر Flutter خود را جایگزین کنید):
C:\flutter\bin\flutter pub get
C:\flutter\bin\flutter build apk --release
```

### یا از اسکریپت:

فایل `build_apk_smart.bat` را اجرا کنید و وقتی از شما مسیر خواست، مسیر کامل را وارد کنید:
```
C:\flutter\bin\flutter.bat
```

## راه‌حل 4: پیدا کردن مسیر Flutter

اگر Flutter نصب دارید اما نمی‌دانید کجاست:

### در Windows:

1. **جستجو در File Explorer:**
   - کلید `Win + E` را بزنید
   - در نوار آدرس، `C:\` را تایپ کنید
   - در جعبه جستجو، `flutter.bat` را جستجو کنید

2. **استفاده از PowerShell:**
   ```powershell
   Get-ChildItem -Path C:\ -Filter "flutter.bat" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
   ```

3. **بررسی مسیرهای معمول:**
   - `C:\flutter\bin\flutter.bat`
   - `%USERPROFILE%\flutter\bin\flutter.bat` (معمولاً `C:\Users\YourName\flutter\bin\flutter.bat`)
   - `C:\src\flutter\bin\flutter.bat`
   - `%LOCALAPPDATA%\flutter\bin\flutter.bat`

## بررسی نصب Flutter

بعد از نصب یا پیدا کردن Flutter، دستور زیر را اجرا کنید:

```bash
flutter doctor
```

این دستور وضعیت نصب Flutter و وابستگی‌های آن را نشان می‌دهد.

## پیش‌نیازهای اضافی

برای ساخت APK، به موارد زیر نیز نیاز دارید:

1. **Android Studio:**
   - دانلود از: https://developer.android.com/studio
   - Android SDK را نصب کنید

2. **Java JDK:**
   - JDK 17 یا بالاتر
   - دانلود از: https://adoptium.net/

3. **مجوزهای Android:**
   ```bash
   flutter doctor --android-licenses
   ```

## تست سریع

بعد از نصب Flutter، این دستورات را تست کنید:

```bash
flutter --version
flutter doctor
flutter pub get
```

اگر همه چیز درست کار کرد، می‌توانید APK بسازید:

```bash
flutter build apk --release
```

## کمک بیشتر

اگر هنوز مشکل دارید:
1. خروجی `flutter doctor` را بررسی کنید
2. مطمئن شوید Android SDK نصب است
3. مطمئن شوید Java JDK نصب است
4. یک Command Prompt جدید باز کنید (برای اعمال تغییرات PATH)

---

**نکته:** بعد از اضافه کردن Flutter به PATH، باید تمام پنجره‌های Command Prompt را ببندید و دوباره باز کنید تا تغییرات اعمال شود.










