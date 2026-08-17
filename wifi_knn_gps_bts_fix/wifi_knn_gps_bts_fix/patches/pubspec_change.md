# pubspec.yaml change for a real Excel XLSX export

Under `dependencies:` add:

```yaml
  excel: ^4.0.6
```

For example near the existing CSV dependency:

```yaml
  csv: ^6.0.0
  excel: ^4.0.6
```

Then run:

```bash
flutter pub get
```

The replacement `outdoor_csv_service.dart` uses this package to produce an actual `.xlsx` file. The CSV remains the durable write-through recording format because it can be flushed safely row by row while data collection is running.
