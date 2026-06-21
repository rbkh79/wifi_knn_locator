# گزارش نهایی: HiVT روی مسیرهای داخلی با نقشه چندطبقه

## چه چیزی اصلاح شد

- مسیرها روی نقشه داخلی GeoJSON رسم شدند (نه نمودار خالی).
- هر طبقه با رنگ جداگانه نمایش داده شد.
- تغییر طبقه با annotation (Lx -> Ly) روی مسیر اصلی مشخص شد.
- در هر شکل، History (از نقاط GeoJSON)، GT Future و پیش بینی HiVT همزمان رسم شد.

## سناریوهای اجراشده

- S1 | normal_single_corridor | levels=0
- S2 | long_straight_between_corridors | levels=0
- S3 | long_winding | levels=1
- S4N | multi_floor_normal | levels=0,1,2
- S4L | multi_floor_long | levels=0,1,2

## ورودی کد پیش بینی

1. نقشه: GeoJSON های داخلی ساختمان
2. مسیر: scene های NPZ شامل x/positions/y و lane features
3. اجرای پیش بینی: run_hivt_route_types_maprich.py

## خروجی کد پیش بینی

- JSON پیش بینی هر سناریو در predictions
- تصویر نقشه-غنی هر سناریو در figures
- CSV تجمیعی قابل انتقال: route_types_master.csv
- خلاصه سناریوها: route_types_summary.json
- قرارداد I/O: inference_io_spec.json
