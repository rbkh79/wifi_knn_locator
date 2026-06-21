# گزارش کامل کارهای انجام‌شده برای EngineeringDepartment

## 1) خلاصه اجرایی

در این مرحله، بر اساس فایل های GeoJSON ساختمان دانشکده، مسیرهای معقول داخل راهروها تولید شد، خروجی های قابل بررسی ساخته شد، داده های آماده HiVT استخراج شد، و تلاش برای اجرای پیش بینی واقعی HiVT روی داده های استخراج شده انجام شد.

وضعیت فعلی:
- تولید مسیرها و داده های ورودی HiVT انجام شده و خروجی ها موجود هستند.
- اجرای نهایی forward در HiVT به دلیل ناسازگاری نسخه ای در stack فعلی متوقف شده است.

## 2) ورودی های اولیه

منابعی که استفاده شدند:
- GeoJSON طبقات: پوشه GeoJSON در مسیر پروژه
- تصویر OSM: OSM_EngDep_1.png و OSM_EngDep_2.png

## 3) کارهای انجام‌شده

### 3.1) ساخت اسکریپت تولید مسیر و استخراج داده HiVT

اسکریپت اصلی ساخته شد:
- [Code/EngineeringDepartment/build_corridor_routes_and_hivt.py](Code/EngineeringDepartment/build_corridor_routes_and_hivt.py)

کار این اسکریپت:
1. خواندن همه GeoJSON های طبقات
2. استخراج feature های indoor=corridor
3. تبدیل مختصات lon/lat به دستگاه مختصات محلی متری
4. برآورد محور اصلی هر corridor و ساخت مسیرهای رفت/برگشت معقول روی راهرو
5. ذخیره مسیرها در CSV و GeoJSON
6. تولید preview تصویری مسیرها در هر طبقه
7. تولید scene های HiVT-like به فرمت NPZ + manifest
8. تولید overlay تقریبی مسیرها روی تصاویر OSM

### 3.2) اجرای اسکریپت و تولید خروجی

خروجی های اصلی:
- [Code/EngineeringDepartment/derived/corridor_routes.csv](Code/EngineeringDepartment/derived/corridor_routes.csv)
- [Code/EngineeringDepartment/derived/corridor_routes.geojson](Code/EngineeringDepartment/derived/corridor_routes.geojson)
- [Code/EngineeringDepartment/derived/summary.json](Code/EngineeringDepartment/derived/summary.json)
- [Code/EngineeringDepartment/derived/hivt_ready/hivt_manifest.json](Code/EngineeringDepartment/derived/hivt_ready/hivt_manifest.json)
- scene های NPZ در پوشه:
  - [Code/EngineeringDepartment/derived/hivt_ready](Code/EngineeringDepartment/derived/hivt_ready)

### 3.3) تولید خروجی تصویری برای بررسی کیفیت مسیرها

Preview مسیرها روی کریدورهای هر طبقه:
- [Code/EngineeringDepartment/derived/routes_preview_level_-1.png](Code/EngineeringDepartment/derived/routes_preview_level_-1.png)
- [Code/EngineeringDepartment/derived/routes_preview_level_0.png](Code/EngineeringDepartment/derived/routes_preview_level_0.png)
- [Code/EngineeringDepartment/derived/routes_preview_level_1.png](Code/EngineeringDepartment/derived/routes_preview_level_1.png)
- [Code/EngineeringDepartment/derived/routes_preview_level_2.png](Code/EngineeringDepartment/derived/routes_preview_level_2.png)
- [Code/EngineeringDepartment/derived/routes_preview_level_2.5.png](Code/EngineeringDepartment/derived/routes_preview_level_2.5.png)

Overlay تقریبی مسیرها روی تصاویر OSM:
- [Code/EngineeringDepartment/derived/routes_overlay_osm_1.png](Code/EngineeringDepartment/derived/routes_overlay_osm_1.png)
- [Code/EngineeringDepartment/derived/routes_overlay_osm_2.png](Code/EngineeringDepartment/derived/routes_overlay_osm_2.png)

## 4) نتیجه کمی تولید مسیرها

طبق خلاصه تولید:
- تعداد کل مسیرها: 84
- طبقات پوشش داده شده: -1 ، 0 ، 1 ، 2 ، 2.5
- تاریخچه هر مسیر: 20 گام
- آینده هر مسیر: 30 گام
- مجموع طول هر trajectory: 50 گام

مرجع:
- [Code/EngineeringDepartment/derived/summary.json](Code/EngineeringDepartment/derived/summary.json)

## 5) ساختار دقیق داده خروجی

### 5.1) CSV مسیرها

ستون های CSV:
- route_id
- level
- feature_id
- timestep
- is_history
- lon
- lat
- x_m
- y_m
- vx_mps
- vy_mps
- speed_mps

فایل:
- [Code/EngineeringDepartment/derived/corridor_routes.csv](Code/EngineeringDepartment/derived/corridor_routes.csv)

### 5.2) ساختار scene های NPZ برای HiVT

کلیدهای NPZ:
- x: شکل [N, 20, 2]
- positions: شکل [N, 50, 2]
- y: شکل [N, 30, 2]
- padding_mask: شکل [N, 50]
- bos_mask: شکل [N, 20]
- rotate_angles: شکل [N]
- lane_vectors: شکل [L, 2]
- lane_actor_index: شکل [2, E]
- lane_actor_vectors: شکل [E, 2]
- agent_index: شکل [1]
- av_index: شکل [1]

manifest صحنه ها:
- [Code/EngineeringDepartment/derived/hivt_ready/hivt_manifest.json](Code/EngineeringDepartment/derived/hivt_ready/hivt_manifest.json)

## 6) تحلیل کیفیت مسیرهای تولیدی

برداشت فنی از خروجی های تصویری:
1. مسیرها روی محور هندسی کریدورها افتاده اند و با پلان داخلی هم راستا هستند.
2. طول مسیرها متناسب با طول کریدورهای انتخابی است.
3. تنوع رفت/برگشت برای هر corridor در داده دیده می شود.
4. overlay روی OSM برای بازبینی اولیه مناسب است، اما ذاتا یک همترازی تقریبی تصویری است (نه georeference دقیق پیکسلی).

## 7) تلاش برای اجرای پیش بینی واقعی HiVT

### 7.1) اسکریپت inference ساخته شد

- [Code/EngineeringDepartment/hivt_inference_from_derived.py](Code/EngineeringDepartment/hivt_inference_from_derived.py)

هدف این اسکریپت:
1. لود checkpoint مدل HiVT
2. تبدیل scene NPZ به TemporalData
3. اجرای forward و گرفتن y_hat و pi
4. ذخیره تصویر پیش بینی و JSON خروجی

### 7.2) وابستگی های نصب شده در مسیر کار

- pytorch-lightning
- torch-geometric
- سپس پین نسخه های سازگارتر:
  - pytorch-lightning==1.4.6
  - torchmetrics==0.6.0

### 7.3) وضعیت نهایی اجرای inference

Checkpoint لود شد، اما forward مدل در stack فعلی به خطای ناسازگاری API رسید:
- خطای کلیدی: وجود آرگومان is_causal در Transformer جدید که با پیاده سازی TemporalEncoderLayer فعلی HiVT همخوان نیست.

نتیجه:
- مرحله استخراج داده کاملا آماده است.
- برای اجرای end-to-end پیش بینی HiVT، نیاز به محیط نسخه ای کاملا سازگار با کد HiVT موجود است.

## 8) فایل راهنمای تولیدشده

راهنمای خلاصه خروجی ها:
- [Code/EngineeringDepartment/derived/README_generated.md](Code/EngineeringDepartment/derived/README_generated.md)

این فایل FULL_REPORT نسخه کامل تر و یکپارچه همان اطلاعات است.

## 9) جمع بندی نهایی

1. درخواست شما برای تولید مسیرهای معقول در راهروها انجام شد.
2. خروجی های بررسی انسانی (CSV/GeoJSON/تصویر) آماده است.
3. داده های لازم برای HiVT با ساختار scene-based استخراج شد.
4. اجرای نهایی پیش بینی HiVT به دلیل ناسازگاری نسخه ای محیط فعلی کامل نشد.
5. گام بعدی عملی: ساخت یک محیط سازگار دقیق با نسخه های اصلی HiVT برای اجرای موفق forward و تولید خروجی پیش بینی نهایی.
