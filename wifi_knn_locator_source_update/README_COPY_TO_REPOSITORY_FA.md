# بسته سورس Outdoor GPS + BTS + Wi-Fi

این ZIP فقط **فایل‌های سورس و تنظیمات تغییرکرده** را دارد. فایل APK، AAB، build، keystore یا فایل خروجی در آن نیست.

## روش استفاده

1. مخزن `wifi_knn_locator` را در GitHub Desktop باز کنید.
2. از مخزن یک نسخه پشتیبان یا Branch جدید بسازید.
3. محتوای این ZIP را Extract کنید.
4. پوشه‌های `lib` و `android` را روی ریشه مخزن کپی کنید و Replace را بزنید.
5. پوشه مخفی `.git` را حذف نکنید.
6. تغییرات را در GitHub Desktop بررسی، Commit و Push کنید.
7. Build را در Codemagic اجرا کنید.

## قابلیت‌های اضافه‌شده

- هر نمونه شامل GPS، BTS سروینگ، سلول‌های همسایه و همه Wi-Fiهای قابل مشاهده است.
- هر لحظه فقط یک ردیف CSV تولید می‌شود؛ BTS به تعداد Wi-Fiها تکرار نمی‌شود.
- فایل از ابتدای Session ساخته می‌شود و هر رکورد فوراً روی دیسک نوشته می‌شود.
- در صورت رد مجوز Wi-Fi، برنامه بدون Crash ثبت GPS+BTS را ادامه می‌دهد.
- در صورت رد مجوز GPS یا Phone، پیام وضعیت برگردانده می‌شود و برنامه Crash نمی‌کند.
- Export قدیمی `exportAndOpenGpsBtsCsv()` به خروجی جدید GPS+BTS+WiFi هدایت می‌شود؛ بنابراین `main.dart` فعلی همچنان سازگار است.

## مجوزها

Manifest شامل Location، Phone، Wi-Fi و Nearby Wi-Fi است. ثبت در این نسخه فقط هنگام بازبودن برنامه انجام می‌شود؛ بنابراین Background Location و Foreground Service اضافه نشده‌اند.

## آزمون روی گوشی

پیش از برداشت یک‌ساعته:

1. یک Session دو دقیقه‌ای ثبت کنید.
2. Location، Phone و Nearby devices را Allow کنید.
3. فایل CSV را Export کنید.
4. بررسی کنید ستون‌های `Latitude`، `Longitude`، `GpsAccuracyM`، `CellID`، `WifiAPCount` و `WifiReadingsJSON` مقدار دارند.

برخی گوشی‌ها اطلاعات سلول همسایه، PCI یا EARFCN را محدود می‌کنند؛ خالی‌بودن این موارد همیشه خطای برنامه نیست.
