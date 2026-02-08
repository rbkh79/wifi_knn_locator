# اسکریپت‌های ارزیابی آزمایش

## پیش‌نیاز
- Python 3.7+
- اختیاری: `scipy` برای محاسبه دقیق p-value آزمون t (`pip install scipy`)
- اختیاری: `matplotlib` برای رسم نمودار (`pip install matplotlib`)

## نحوه استفاده

1. نتایج آزمایش را در یک فایل CSV با ستون‌های زیر ذخیره کنید:
   - `lat_true`, `lon_true`: موقعیت واقعی (Ground Truth)
   - `lat_est`, `lon_est`: موقعیت تخمین‌زده‌شده توسط اپ
   - `method`: `wifi_only` یا `hybrid`
   - `point_id`, `sample_id`: شناسه نقطه و نمونه (برای جفت‌گیری)

2. اجرای اسکریپت:
   ```bash
   python evaluate_experiment.py path/to/results.csv
   python evaluate_experiment.py path/to/results.csv --output-dir report/
   ```

3. خروجی: چاپ در ترمینال + در صورت تعیین `--output-dir` ذخیره در `evaluation_report.txt` و در صورت نصب matplotlib رسم `error_boxplot.png`.

## نمونه CSV
فایل `sample_experiment_results.csv` یک نمونه کوچک برای تست اسکریپت است.
