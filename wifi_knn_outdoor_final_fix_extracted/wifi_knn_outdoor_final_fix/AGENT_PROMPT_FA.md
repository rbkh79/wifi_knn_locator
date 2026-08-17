# دستور Agent — اصلاح نهایی Outdoor GPS+BTS

پروژه کامل فعلی و تمام فایل‌های لازم از قبل در workspace تو موجود است. **به GitHub، وب یا هیچ منبع بیرونی مراجعه نکن.** همین فایل ZIP پیوست را مبنای اصلاح قرار بده: فایل‌های replacement داخل ZIP را دقیقاً جایگزین فایل‌های متناظر پروژه کن و patchهای داخل ZIP را روی فایل‌های متناظر همان پروژه اعمال کن.

هدف: فقط مشکل‌های Outdoor GPS+BTS و Export پژوهشگر را اصلاح کن و هیچ قابلیت دیگری را حذف یا بازطراحی نکن.

## کارهایی که دقیقاً باید انجام دهی

### A) دو فایل را کامل جایگزین کن

فایل داخل ZIP:

`replacements/lib/services/outdoor_gps_bts_service.dart`

را جایگزین این فایل پروژه کن:

`lib/services/outdoor_gps_bts_service.dart`

و فایل:

`replacements/lib/services/outdoor_csv_service.dart`

را جایگزین:

`lib/services/outdoor_csv_service.dart`

کن.

### B) سه patch را روی فایل‌های فعلی پروژه اعمال کن

- `patches/main_dart_changes.md` → `lib/main.dart`
- `patches/MainActivity_changes.md` → `android/app/src/main/kotlin/com/example/wifi_knn_locator/MainActivity.kt`
- `patches/pubspec_change.md` → `pubspec.yaml`

اگر package path واقعی MainActivity در پروژه workspace متفاوت است، همان MainActivity فعلی پروژه را patch کن؛ package/applicationId/namespace/signing را تغییر نده.

## الزامات غیرقابل حذف

1. با Start Recording فایل session قبل از اولین نمونه ساخته شود.
2. هر GPS+BTS record بلافاصله با `flush:true` ذخیره شود؛ ذخیره کل session نباید به Stop وابسته باشد.
3. اگر برنامه بدون Stop بسته یا kill شد، رکوردهای کامل‌شده قبلی باید روی دیسک باقی بمانند.
4. Stop باید final consistency flush/rewrite انجام دهد و UI فقط در صورت موفقیت واقعی پیام سبز بدهد.
5. session ناقص قبلی بعد از restart باید از Researcher Mode قابل Export باشد.
6. Researcher Mode برای Outdoor GPS+BTS باید **XLSX واقعی** بسازد.
7. در Android 10+ یک کپی واقعی از XLSX با MediaStore داخل `Downloads/WiFiKnnLocator` ذخیره شود؛ Share Sheet برای Save استفاده نشود.
8. سپس فایل با `OpenFile.open()` باز شود. اگر Excel نصب است، XLSX با Excel باز شود؛ اگر Android `Open with` برای انتخاب spreadsheet app نشان داد قابل قبول است. Share Sheet قابل قبول نیست.
9. CSV داخلی حذف نشود؛ CSV همان فرمت durable برای write-through recording باشد.
10. RSRP/RSRQ/SINR اصلاحات patch را اعمال کن؛ RSRQ/SINR missing را جعل نکن.
11. Wi-Fi، KNN، Indoor، IMU، localization، database، maps و سایر Researcher exports را حذف یا خراب نکن.
12. تنظیم Codemagic، signing، applicationId، namespace، versioning و keystore را تغییر نده.

## Dependency

`excel: ^4.0.6` را طبق patch به dependencies اضافه کن. `open_file` و `share_plus` فعلی را حذف نکن.

## کنترل سازگاری

بعد از اعمال تغییرات، قبل از پایان کار این موارد را بررسی کن:

```bash
flutter pub get
flutter analyze
```

اگر تست‌های پروژه موجودند و زمان build اجازه می‌دهد:

```bash
flutter test
```

سپس build Android/Codemagic نباید به خاطر این تغییرات compile error داشته باشد.

اگر خطایی ناشی از API دقیق نسخه dependency موجود بود، همان رفتار الزامی بالا را حفظ کن و فقط syntax/API را با نسخه موجود سازگار کن؛ راه‌حل را به Share Sheet برنگردان.

در پایان خلاصه کن چه فایل‌هایی تغییر کردند و تأیید کن که:

- write-through persistence فعال است؛
- interrupted session recoverable است؛
- Stop نتیجه save واقعی را نشان می‌دهد؛
- Researcher Mode از `exportAndOpenGpsBtsXlsx(...)` استفاده می‌کند، XLSX واقعی را در Downloads ذخیره می‌کند، با OpenFile باز می‌کند و Share Sheet را فراخوانی نمی‌کند؛
- RSRP fallback و missing RSRQ/SINR مطابق patch هستند.
