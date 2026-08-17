# Patch: lib/main.dart

این patch فقط بخش Outdoor GPS+BTS را تغییر می‌دهد. سایر قابلیت‌های برنامه دست نخورند.

## 1) کل تابع `_toggleGpsBtsRecording()` را با این نسخه جایگزین کن

```dart
Future<void> _toggleGpsBtsRecording() async {
  debugPrint('[DEBUG] Start/Stop GPS+BTS clicked');
  final service = OutdoorGpsBtsService.instance;

  if (_isRecordingGpsBts) {
    debugPrint('[DEBUG] Stop Recording clicked');

    final savedPath = await service.stopRecording();
    if (!mounted) return;

    final count = service.recordCount;
    setState(() {
      _isRecordingGpsBts = false;
    });

    late final String message;
    late final Color color;

    if (count == 0) {
      message = 'Recording stopped, but no GPS+BTS records were captured.';
      color = Colors.orange;
    } else if (savedPath != null) {
      message = 'Saved $count GPS+BTS records successfully.';
      color = Colors.green;
    } else {
      message =
          'SAVE ERROR: $count records were captured but final verification failed.';
      color = Colors.red;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 5),
      ),
    );
    return;
  }

  debugPrint('[DEBUG] Starting GPS+BTS recording service...');

  final success = await service.startRecording(
    onRecordCountChanged: (count) {
      if (!mounted) return;
      setState(() {
        _gpsBtsRecordCount = count;
      });
    },
    onLatestRecordChanged: (record) {
      if (!mounted) return;
      setState(() {
        _latestGpsBtsRecord = record;
      });
    },
    onStatusChanged: (status) {
      if (!mounted) return;
      setState(() {
        _gpsBtsRecordingStatus = status;
      });
    },
  );

  if (!mounted) return;

  if (success) {
    debugPrint('[DEBUG] GPS+BTS recording service started successfully');
    setState(() {
      _isRecordingGpsBts = true;
      _gpsBtsRecordingStatus =
          'Recording... completed samples are saved immediately.';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('GPS+BTS recording started; write-through save is active.'),
        backgroundColor: Colors.green,
      ),
    );
  } else {
    debugPrint('[DEBUG] GPS+BTS recording service failed to start');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Failed to start GPS+BTS recording: $_gpsBtsRecordingStatus',
        ),
        backgroundColor: Colors.red,
      ),
    );
  }
}
```

نکته: بعد از Stop دیگر `_gpsBtsRecordingStatus` را مصنوعی روی `Recording stopped` بازنویسی نکن. Status واقعی از سرویس می‌آید.

---

## 2) کل تابع `_exportOutdoorGpsBts()` را با این نسخه جایگزین کن

```dart
Future<void> _exportOutdoorGpsBts() async {
  final service = OutdoorGpsBtsService.instance;

  if (service.isRecording) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Stop GPS+BTS recording before opening the Excel export.',
        ),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  String? preferredCsvPath;
  if (service.recordCount > 0) {
    preferredCsvPath =
        await service.flushCurrentSession() ?? service.latestSavedPath;
  } else {
    // After an app restart this may be null. The service will then find the
    // newest non-empty recoverable GPS+BTS session on disk automatically.
    preferredCsvPath = service.latestSavedPath;
  }

  final exportResult = await OutdoorCsvService.exportAndOpenGpsBtsXlsx(
    csvPath: preferredCsvPath,
  );

  if (!mounted) return;

  if (exportResult == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No saved Outdoor GPS+BTS data was found to export.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 5),
      ),
    );
    return;
  }

  final savedPublicly = exportResult.savedToDownloads;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        savedPublicly
            ? 'Excel XLSX saved in Downloads/WiFiKnnLocator and opened.'
            : 'Excel XLSX created and opened, but public Downloads copy failed.',
      ),
      backgroundColor: savedPublicly ? Colors.green : Colors.orange,
      duration: const Duration(seconds: 6),
    ),
  );
}
```

این مسیر برای Export پژوهشگر `Share.shareXFiles` را صدا نمی‌زند. XLSX واقعی ساخته می‌شود، روی Android 10+ تلاش می‌شود یک کپی در Downloads عمومی ذخیره شود، سپس فایل با `OpenFile.open()` باز می‌شود.

---

## 3) نمایش RSRP/RSRQ/SINR

این چهار Chip فعلی:

```dart
Chip(label: Text('Signal: ${_latestGpsBtsRecord!.signalStrength ?? '-'} dBm')),
Chip(label: Text('RSRP: ${_latestGpsBtsRecord!.rsrp ?? '-'} dBm')),
Chip(label: Text('RSRQ: ${_latestGpsBtsRecord!.rsrq ?? '-'} dB')),
Chip(label: Text('SINR: ${_latestGpsBtsRecord!.sinr ?? '-'} dB')),
```

با این جایگزین شوند:

```dart
Chip(
  label: Text(
    'Signal: ${_latestGpsBtsRecord!.signalStrength ?? 'N/A'} dBm',
  ),
),
Chip(
  label: Text(
    _latestGpsBtsRecord!.effectiveRsrp != null
        ? 'RSRP: ${_latestGpsBtsRecord!.effectiveRsrp} dBm'
        : 'RSRP: N/A (device)',
  ),
),
Chip(
  label: Text(
    _latestGpsBtsRecord!.rsrq != null
        ? 'RSRQ: ${_latestGpsBtsRecord!.rsrq} dB'
        : 'RSRQ: N/A (device)',
  ),
),
Chip(
  label: Text(
    _latestGpsBtsRecord!.sinr != null
        ? 'SINR: ${_latestGpsBtsRecord!.sinr} dB'
        : 'SINR: N/A (device)',
  ),
),
```

---

## 4) عنوان دکمه Researcher Mode

این:

```dart
label: const Text('Export Outdoor GPS+BTS Dataset'),
```

به این تغییر کند:

```dart
label: const Text('Open Outdoor GPS+BTS Excel (XLSX)'),
```

`onPressed: _exportOutdoorGpsBts` باقی بماند.

---

## 5) `dispose()`

`dispose()` را async نکن. سرویس جدید هر رکورد کامل‌شده را همان لحظه با `flush: true` ذخیره می‌کند؛ بنابراین ایمنی رکوردهای کامل‌شده وابسته به final save در `dispose()` نیست.
