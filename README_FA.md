# Wi‑Fi KNN Locator

یک برنامهٔ Flutter برای تخمین موقعیت جغرافیایی (lat/lon) از شناسه‌های MAC وای‑فای با استفاده از الگوریتم ساده KNN (k-Nearest Neighbors).

## ویژگی‌ها

- اسکن شبکه‌های وای‑فای و دریافت RSSI (قدرت سیگنال)
- استفاده از fingerprint dataset (BSSID → lat/lon) برای محاسبهٔ مکان
- الگوریتم KNN ساده برای وزن‌دهی و میانگین‌گیری مختصات
- رابط کاربری با نقشه و اطلاعات پیش‌بینی‌شده
- بدون نیاز به سرویس GPS یا اینترنت

## نیازمندی‌ها

- **موبایل**: اندروید 21+ یا iOS 11+
- **توسعه**: Flutter 3.0+ و Dart 3.0+

## نصب سریع

### برای کاربران نهایی (دانلود APK)

1. دانلود `app-debug.apk` از [Releases](../../releases)
2. نصب روی گوشی اندروید: `adb install -r app-debug.apk`
3. اجرای برنامه و اعطای مجوزهای لوکیشن و وای‑فای

### برای توسعه‌دهندگان

```bash
# کلون کردن
git clone https://github.com/YOUR_USERNAME/wifi_knn_locator.git
cd wifi_knn_locator

# نصب وابستگی‌ها
flutter pub get

# اجرای روی دستگاه
flutter run

# ساخت APK (نیاز به Android SDK)
flutter build apk --debug
```

## ساختار پروژه

```
wifi_knn_locator/
├── lib/
│   └── main.dart          # کد اصلی UI و KNN
├── assets/
│   ├── wifi_db.csv        # Database BSSID → lat/lon
│   └── wifi_fingerprints.csv  # Fingerprint dataset
├── android/               # پیکربندی اندروید
├── ios/                   # پیکربندی iOS
├── codemagic.yaml         # CI/CD برای ساخت APK
└── pubspec.yaml           # وابستگی‌های Dart/Flutter
```

## الگوریتم KNN

الگوریتم ساده‌شدهٔ KNN:

1. **دریافت fingerprints**: هر fingerprint یک مکان (lat, lon) و مجموعهٔ BSSIDs با RSSI است.
2. **اسکن وای‑فای**: دریافت BSSID و RSSI شبکه‌های نزدیک.
3. **محاسبهٔ فاصله**: فاصلهٔ اقلیدسی بین scan و هر fingerprint:
   ```
   distance = √(Σ(observed_rssi - fingerprint_rssi)²)
   ```
4. **انتخاب k نزدیک‌ترین**: مثلاً k=3
5. **میانگین وزنی**: 
   ```
   weight = 1 / (distance + 1)
   predicted_location = Σ(weight × fingerprint_location) / Σ(weight)
   ```

## جمع‌آوری داده‌های training

برای دقت بالا:

1. چند نقطه در محیط خود انتخاب کنید (مثلاً هر 5 متر).
2. در هر نقطه، اپ را اجرا کنید و نتیجهٔ اسکن را ذخیره کنید.
3. داده‌ها را به فرمت CSV وارد کنید:
   ```csv
   lat,lon,bssid1:rssi,bssid2:rssi,...
   37.4220,-122.0841,aa:bb:cc:dd:ee:01:-40,aa:bb:cc:dd:ee:02:-60
   ```
4. فایل را در `assets/wifi_fingerprints.csv` قرار دهید.

## استقرار (Deployment)

### روش 1: Codemagic (خودکار)
- پروژه به GitHub push کنید.
- Codemagic را connect کنید: https://codemagic.io
- هر push، APK جدید می‌سازد و در Releases قرار می‌دهد.

### روش 2: ساخت دستی
```bash
flutter build apk --release
# خروجی: build/app/outputs/flutter-apk/app-release.apk
```

## مشکلات و حل

**مشکل**: "Build failed due to use of deleted Android v1 embedding"
- **حل**: Flutter v2 نیاز دارد. `flutter upgrade` را اجرا کنید.

**مشکل**: اسکن وای‑فای کار نمی‌کند
- **حل**: مجوزهای لوکیشن و وای‑فای را فعال کنید (در تنظیمات گوشی).

**مشکل**: دقت پیش‌بینی کم است
- **حل**: dataset بزرگ‌تر جمع‌آوری کنید (همه BSSIDهای نزدیک).

## لایسنس

MIT

## نویسنده

توسعه‌یافته برای پروژهٔ Wi‑Fi-based indoor localization با KNN.

---

**نکات**:
- این کد برای **آموزشی** است. برای استفادهٔ تجاری، دقت و پرایوسی را بررسی کنید.
- اسکن وای‑فای فقط روی **اندروید** کار می‌کند (iOS محدودیت دارد).
