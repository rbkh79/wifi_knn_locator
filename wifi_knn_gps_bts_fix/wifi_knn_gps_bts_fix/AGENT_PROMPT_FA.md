# دستور دقیق برای Agent — اصلاح Outdoor GPS+BTS

این بسته بر اساس شاخه `main` مخزن `rbkh79/wifi_knn_locator` تهیه شده است.

## هدف نهایی

بخش **Outdoor Recording > GPS+BTS** باید این رفتار را داشته باشد:

1. قبل از شروع ثبت، فایل session ساخته شود.
2. هر رکورد بلافاصله بعد از ثبت به CSV اضافه و با `flush: true` روی حافظه نوشته شود.
3. با زدن Stop، یک final flush/rewrite انجام شود و وضعیت واقعی ذخیره به UI برگردد.
4. بعد از Stop، در Researcher Mode دکمه Export همیشه بتواند آخرین session غیرخالی را پیدا کند.
5. Export اصلی یک فایل واقعی **`.xlsx`** بسازد و Android share/save sheet را باز کند.
6. اگر XLSX شکست خورد، CSV به‌عنوان fallback قابل Share/Save باشد.
7. برای LTE، RSRP مستقیم خوانده شود؛ اگر Android مقدار مستقیم را unavailable برگرداند، از `CellSignalStrengthLte.getDbm()` به‌عنوان RSRP استفاده شود.
8. RSRQ و SINR فقط وقتی Android/modem واقعاً مقدار می‌دهد ذخیره شوند. مقدار ساختگی تولید نشود.
9. در UI به جای `-` برای مقدار unavailable نوشته شود `N/A (device)`.

## فایل‌هایی که باید کامل جایگزین شوند

### A
Source:
`lib/services/outdoor_gps_bts_service.dart`

Replace the entire file with:
`replacements/outdoor_gps_bts_service.dart`

### B
Source:
`lib/services/outdoor_csv_service.dart`

Replace the entire file with:
`replacements/outdoor_csv_service.dart`

## فایل‌هایی که باید patch شوند

### C — Native Android
Target:
`android/app/src/main/kotlin/com/example/wifi_knn_locator/MainActivity.kt`

Apply every change in:
`patches/MainActivity_changes.md`

Do not remove GSM/WCDMA/NR branches or the existing MethodChannel.

### D — UI and controller
Target:
`lib/main.dart`

Apply every change in:
`patches/main_dart_changes.md`

### E — dependency
Target:
`pubspec.yaml`

Apply:
`patches/pubspec_change.md`

Then run:

```bash
flutter pub get
dart format lib/services/outdoor_gps_bts_service.dart
dart format lib/services/outdoor_csv_service.dart lib/main.dart
flutter analyze
flutter build apk --debug
```

## فایل‌هایی که نباید بی‌دلیل تغییر کنند

- `lib/cell_scanner.dart`: در نسخه فعلی کلیدهای `rsrp`, `rsrq`, `sinr` را از native map می‌خواند؛ تغییر لازم نیست.
- `lib/data_model.dart`: در نسخه فعلی فیلدهای `rsrp`, `rsrq`, `sinr` را دارد؛ تغییر لازم نیست.
- ساختار ستون‌های CSV را حذف یا rename نکن.

## Acceptance tests روی گوشی واقعی

### Test 1 — durability
1. Start Recording.
2. صبر کن حداقل 10 رکورد ثبت شود.
3. Stop Recording.
4. باید پیام `Saved 10 records` یا تعداد واقعی دیده شود.
5. Researcher Mode > `Export Outdoor GPS+BTS (Excel XLSX)`.
6. فایل XLSX را با Files/Drive ذخیره کن.
7. تعداد ردیف داده در XLSX باید با شمارنده UI برابر باشد.

### Test 2 — no-loss before Stop
1. Start Recording.
2. 10 تا 20 رکورد بگیر.
3. در حین recording وارد Researcher Mode شو.
4. Export را بزن.
5. فایل باید شامل همه رکوردهای **کامل‌شده تا آن لحظه** باشد.
6. این تست ثابت می‌کند داده فقط در RAM نگه‌داری نمی‌شود.

### Test 3 — LTE metrics
در جایی که LTE متصل است:
- CellID / eNodeB / Local cell / PCI / EARFCN باید مثل قبل نشان داده شوند.
- RSRP باید در دستگاه‌هایی مثل مورد تصویر که `Signal=-113 dBm` ولی `getRsrp()` unavailable است، با fallback معتبر LTE به صورت `RSRP=-113 dBm` ظاهر شود.
- اگر RSRQ یا SINR توسط مودم expose شود، عدد نمایش داده و در XLSX ذخیره شود.
- اگر expose نشود، UI باید `N/A (device)` نشان دهد و فایل مقدار خالی داشته باشد؛ مقدار جعلی نساز.

### Test 4 — restart/export
1. یک session ثبت و Stop کن.
2. اپ را کامل ببند و دوباره باز کن.
3. بدون شروع recording جدید، Researcher Mode > Export را بزن.
4. آخرین CSV غیرخالی باید پیدا و به XLSX تبدیل شود.

## Logcat برای عیب‌یابی

```bash
adb logcat | grep -E "BTS_Service|OutdoorBTS|OutdoorCSV"
```

در LTE به این مقادیر توجه کن:

```text
directRsrp=...
effectiveRsrp=...
rsrq=...
sinr=...
```

اگر `effectiveRsrp` عدد دارد ولی UI هنوز N/A است، مشکل Flutter mapping/UI است.
اگر `rsrq` و `sinr` در native هم null/unavailable هستند، محدودیت device/modem است نه export.

## شرط مهم

Agent نباید برای پر کردن RSRQ یا SINR از فرمول تخمینی یا عدد ثابت استفاده کند. برای داده پژوهشی، unavailable باید unavailable بماند.
