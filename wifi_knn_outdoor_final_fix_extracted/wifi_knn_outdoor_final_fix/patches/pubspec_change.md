# Patch: pubspec.yaml

زیر `dependencies:`، کنار dependency مربوط به CSV این خط را اضافه کن:

```yaml
  csv: ^6.0.0
  excel: ^4.0.6
```

`open_file` و `share_plus` فعلی حذف نشوند. Export پژوهشگر از `open_file` استفاده می‌کند و Share Sheet را صدا نمی‌زند؛ توابع share قدیمی فقط برای سازگاری باقی مانده‌اند.

بعد از اعمال تغییر:

```bash
flutter pub get
```
