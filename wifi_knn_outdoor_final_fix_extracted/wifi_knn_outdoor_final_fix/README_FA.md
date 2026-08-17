# اصلاح نهایی Outdoor GPS+BTS

این بسته برای چهار مشکل ساخته شده است:

1. از دست رفتن داده در صورت بسته شدن/Crash قبل از Stop.
2. پیام سبز Stop بدون تضمین اینکه فایل واقعاً ذخیره شده است.
3. Export پژوهشگر که Share Sheet باز می‌کرد یا CSV می‌داد.
4. خالی ماندن RSRP در LTE در حالی که `signalStrength/dbm` معتبر وجود دارد.

## معماری جدید ذخیره

- با Start، فایل CSV session قبل از اولین نمونه ساخته می‌شود.
- هر نمونه کامل‌شده همان لحظه `append + flush:true` می‌شود.
- اگر append شکست بخورد، سرویس همان لحظه full rewrite را به عنوان recovery امتحان می‌کند.
- Stop یک final consistency rewrite انجام می‌دهد.
- اگر اپ ناگهانی بسته شود، رکوردهایی که قبلاً کامل و flush شده‌اند در session CSV باقی می‌مانند.
- بعد از باز کردن دوباره اپ، Researcher Mode می‌تواند جدیدترین session غیرخالی قبلی را پیدا کند.

## Export جدید

- CSV فرمت durable داخلی برای ثبت امن است.
- هنگام Export یک XLSX واقعی ساخته می‌شود.
- در Android 10+ یک کپی از XLSX با MediaStore در `Downloads/WiFiKnnLocator` ذخیره می‌شود.
- سپس Export از `OpenFile.open(...xlsx...)` استفاده می‌کند تا فایل در Excel/WPS/Sheets باز شود.
- مسیر Export به `Share.shareXFiles` وصل نیست؛ بنابراین Share Sheet نباید باز شود.
- اگر Microsoft Excel نصب باشد، Android فایل XLSX را با Excel باز می‌کند. اگر چند spreadsheet app نصب باشد ممکن است Android فقط پنجره Open with نشان دهد؛ این Share Sheet نیست.

## فایل‌های بسته

- `replacements/lib/services/outdoor_gps_bts_service.dart` — جایگزینی کامل
- `replacements/lib/services/outdoor_csv_service.dart` — جایگزینی کامل
- `patches/main_dart_changes.md` — patch UI/Stop/Export
- `patches/MainActivity_changes.md` — patch RSRP/RSRQ/SINR
- `patches/pubspec_change.md` — اضافه کردن excel dependency
- `AGENT_PROMPT_FA.md` — دستور کامل برای Agent
- `TEST_CHECKLIST.md` — تست قبل از داده‌برداری واقعی


## بازیابی پس از بسته‌شدن ناگهانی
هر ردیف کامل بلافاصله روی CSV نوشته و flush می‌شود. اگر process دقیقاً وسط نوشتن آخرین ردیف قطع شود، Export فقط tail بدون newline را کنار می‌گذارد و تمام ردیف‌های کامل قبلی را بازیابی می‌کند؛ بنابراین خرابی احتمالی آخرین append باعث غیرقابل‌خواندن شدن کل session نمی‌شود.
