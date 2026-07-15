# تحلیل دیتاست WiFi Fingerprints (مکان‌یابی داخل‌ساختمان)

این پوشه شامل تحلیل کامل داده‌های RSSI جمع‌آوری‌شده برای پایان‌نامه
**مکان‌یابی مبتنی بر WiFi Fingerprinting و الگوریتم KNN** است.

هدف اصلی: **شناسایی اینکه از میان چند نوع RSSI / Access Point موجود در محیط،
کدام‌ها برای مکان‌یابی مناسب هستند.**

---

## ساختار پوشه

```
excel_analysis/
├── data/
│   └── fingerprints.xlsx            ← داده خام (ورودی)
├── outputs/
│   ├── tables/                      ← ۱۲ جدول خروجی (Excel)
│   └── figures/                     ← ۸ نمودار خروجی (PNG)
├── analyze_fingerprints.py          ← اسکریپت تحلیل (اجرا از خط فرمان)
├── analysis_notebook.ipynb          ← نوت‌بوک Jupyter با توضیحات فارسی (برای ارائه)
├── requirements.txt                 ← وابستگی‌های پایتون
└── README_FA.md                     ← همین فایل
```

---

## نصب پیش‌نیازها

```bash
pip install -r requirements.txt
```

## نحوه اجرا

### روش ۱: اسکریپت (سریع، همه خروجی‌ها را یک‌جا تولید می‌کند)

```bash
cd excel_analysis
python analyze_fingerprints.py
```

### روش ۲: نوت‌بوک (تعاملی، مناسب برای ارائه به استاد)

```bash
cd excel_analysis
jupyter notebook analysis_notebook.ipynb
# یا:
jupyter lab analysis_notebook.ipynb
```

---

## خلاصه یافته‌ها (نتیجه نهایی)

| معیار | مقدار |
|------|------|
| مجموع ردیف‌های داده | ۱٬۷۵۶ |
| تعداد نقطه مرجع (Reference Point) | ۴۵ |
| تعداد نمونه (SampleID) | ۱۲۹ |
| تعداد ساختمان / طبقه | ۵ ساختمان / ۴ طبقه |
| **مجموع Access Point شناسایی‌شده (BSSID یکتا)** | **۷۶** |
| شبکه غالب | WiFi-FUM (۲۶ BSSID) |
| باند فرکانسی | 2.4 GHz (۹۷۷ ردیف) و 5 GHz (۷۷۹ ردیف) |
| محدوده RSSI | ۹۶- تا ۳۱- dBm |
| میانگین RSSI | ۲۲- dBm |

### پاسخ به سؤال استاد: «کدام APها به درد مکان‌یابی می‌خورند؟»

> از **۷۶ اکسس‌پوینت** موجود، تنها **۴۸ مورد** (آنهایی که حداقل ۱۰ بار به‌طور
> پایدار مشاهده شده‌اند) برای Fingerprinting مناسب هستند.
> ۲۸ مورد دیگر شامل هات‌اسپات‌های گوشی‌های عبوری یا شبکه‌های یک‌باره هستند
> که باید فیلتر شوند.

---

## فهرست تحلیل‌ها و خروجی‌ها

| # | تحلیل | جدول | نمودار |
|---|------|------|--------|
| ۱ | آمار کلی دیتاست | `01_overview.xlsx` | — |
| ۲ | تحلیل هر AP (مشاهده/میانگین/std/باند/مناسب) | `02_access_points.xlsx` | — |
| ۳ | خلاصه مناسب/نامناسب | `03_ap_suitable_summary.xlsx` | — |
| ۴ | تحلیل SSIDها | `04_ssids.xlsx` | — |
| ۵ | تعداد AP در هر طبقه | `05_aps_per_floor.xlsx` | `05_aps_per_floor.png` |
| ۶ | AP در هر نقطه مرجع | `06_aps_per_rp.xlsx` | `06_aps_per_rp_distribution.png` |
| ۷ | توزیع RSSI | `07_rssi_distribution.xlsx` | `07_rssi_histogram.png`, `07_rssi_histogram_by_band.png` |
| ۸ | باکس‌پلات پایداری APها | — | `08_rssi_boxplot_top_aps.png` |
| ۹ | پوشش APها (٪ نقاط) | `09_ap_coverage.xlsx` | `09_ap_coverage_distribution.png` |
| ۱۰ | همبستگی RSSI با فاصله | `10_rssi_vs_distance.xlsx` | `10_rssi_vs_distance.png` |
| ۱۱ | ماتریس ساختمان × طبقه | `11_building_floor_aps.xlsx` | `11_building_floor_heatmap.png` |
| ۱۲ | مجموعه پیشنهادی APها | `12_recommended_aps.xlsx` | — |

---

## تنظیمات قابل تغییر

در فایل `analyze_fingerprints.py` دو آستانه مهم وجود دارد که می‌توانید
طبق نیاز پروژه تغییر دهید:

```python
MIN_OBSERVATIONS = 10   # حداقل دفعات مشاهده برای «مناسب بودن» یک AP
COVERAGE_THRESHOLD = 0.80  # آستانه پوشش (۸۰٪) برای APهای همه‌گیر
```

مثلاً اگر سخت‌گیرانه‌تر بخواهید، `MIN_OBSERVATIONS = 20` بگذارید تا فقط APهای
بسیار پایدار باقی بمانند.

---

## نکته درباره فونت فارسی در نمودارها

نمودارها برای جلوگیری از به‌هم‌ریختگی کاراکتر، با **برچسب انگلیسی** تولید
شده‌اند. توضیحات و تحلیل‌ها به‌صورت متن و جدول فارسی هستند. اگر فونت
فارسی (مثل B Nazanin یا Vazirmatn) نصب باشد، اسکریپت خودکار آن را شناسایی
می‌کند.
