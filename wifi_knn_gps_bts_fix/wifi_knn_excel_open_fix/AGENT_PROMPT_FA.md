# دستور برای Agent — اصلاح Export پژوهشگر به Excel واقعی

مخزن هدف:
`https://github.com/rbkh79/wifi_knn_locator`

هدف این Patch فقط اصلاح رفتار Export در Researcher Mode است، بدون خراب کردن ذخیره CSV داخلی یا تنظیمات Codemagic.

## تغییرات اجباری

1. فایل زیر را با نسخه داخل این بسته **کامل جایگزین کن**:
   `lib/services/outdoor_csv_service.dart`

2. در `pubspec.yaml` dependency زیر را اضافه کن و سایر dependencyها را حفظ کن:
   `excel: ^4.0.6`

3. در `lib/main.dart` منطق این دو تابع را تغییر نده؛ نسخه فعلی درست به Service وصل است:

```dart
Future<void> _exportOutdoorGpsBts() async {
  await OutdoorCsvService.exportAndOpenGpsBtsCsv();
}

Future<void> _exportOutdoorImu() async {
  await OutdoorCsvService.exportAndOpenImuCsv();
}
```

4. فقط label دکمه‌ها را برای شفافیت به این صورت تغییر بده:
   - `Open Outdoor GPS+BTS in Excel`
   - `Open Outdoor IMU+GPS in Excel`

5. دکمه‌های Outdoor Researcher Mode نباید `Share.shareXFiles` را صدا بزنند.
   مسیر اصلی Export باید:
   CSV موجود -> XLSX واقعی -> `OpenFile.open(..., type: XLSX MIME)` باشد.

6. CSV داخلی را حذف نکن؛ CSV همچنان آرشیو خام داده است و XLSX فقط هنگام Export ساخته شود.

7. فایل XLSX باید واقعی باشد؛ فقط تغییر پسوند `.csv` به `.xlsx` ممنوع است.

8. همه Cell ID / eNodeB ID / PCI / EARFCN و سایر شناسه‌ها در XLSX به صورت text نوشته شوند تا Excel ارقام را به scientific notation تبدیل نکند یا دقت عددی از بین نرود.

9. هیچ fallback به Share Sheet برای این دو دکمه اضافه نکن. اگر برنامه‌ای برای XLSX نصب نیست، نتیجه OpenFile را log کن.

10. Codemagic، signing، package name، applicationId و build_aab را تغییر نده.

## تست قبل از commit

- `flutter pub get`
- `flutter analyze`
- در صورت امکان `flutter build appbundle --release`
- بررسی کن `outdoor_gps_bts_export.xlsx` واقعاً ایجاد شود.
- اگر Microsoft Excel روی گوشی نصب است، با فشار دکمه GPS+BTS فایل باید در Excel/برنامه spreadsheet باز شود، نه Share Sheet.

نکته Android: اگر چند برنامه برای XLSX نصب باشند، Android ممکن است یک بار پنجره "Open with" نشان دهد. این با Share Sheet فرق دارد. بعد از انتخاب Excel به عنوان default، فایل مستقیم در Excel باز می‌شود.
