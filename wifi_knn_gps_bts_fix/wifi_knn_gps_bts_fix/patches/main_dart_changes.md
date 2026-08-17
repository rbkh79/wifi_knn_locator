# lib/main.dart changes

Target: `lib/main.dart`

## 1) Replace `_toggleGpsBtsRecording()`

```dart
Future<void> _toggleGpsBtsRecording() async {
  debugPrint('[DEBUG] GPS+BTS record toggle');

  if (_isRecordingGpsBts) {
    final savedPath = await OutdoorGpsBtsService.instance.stopRecording();

    if (!mounted) return;

    setState(() {
      _isRecordingGpsBts = false;
      _gpsBtsRecordingStatus = savedPath != null
          ? 'Saved $_gpsBtsRecordCount records'
          : 'Recording stopped, but final save failed';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          savedPath != null
              ? 'GPS+BTS saved successfully. You can export XLSX now.'
              : 'GPS+BTS stopped, but final save failed. Try Export immediately.',
        ),
        backgroundColor: savedPath != null ? Colors.green : Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );

    return;
  }

  final success = await OutdoorGpsBtsService.instance.startRecording(
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
    setState(() {
      _isRecordingGpsBts = true;
      _gpsBtsRecordingStatus =
          'Recording... each completed sample is saved immediately';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('GPS+BTS recording started; write-through save is active'),
        backgroundColor: Colors.green,
      ),
    );
  } else {
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

Why this matters: the old UI overwrote the service's final save status with the generic text `Recording stopped`, hiding whether the file was actually saved.

## 2) Replace `_exportOutdoorGpsBts()`

```dart
Future<void> _exportOutdoorGpsBts() async {
  final service = OutdoorGpsBtsService.instance;

  // While recording, each finished row is already flushed to the current CSV.
  // After Stop, do one final consistency flush before XLSX conversion.
  String? preferredCsvPath;
  if (service.isRecording) {
    preferredCsvPath = service.currentSessionPath;
  } else if (service.recordCount > 0) {
    preferredCsvPath =
        await service.flushCurrentSession() ?? service.latestSavedPath;
  } else {
    preferredCsvPath = service.latestSavedPath;
  }

  var ok = await OutdoorCsvService.shareGpsBtsXlsx(
    csvPath: preferredCsvPath,
  );

  // CSV is the emergency fallback if XLSX generation ever fails.
  if (!ok) {
    ok = await OutdoorCsvService.shareGpsBtsCsv(
      filePath: preferredCsvPath,
    );
  }

  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        ok
            ? 'Outdoor GPS+BTS export is ready. Choose Save/Files/Drive in the share sheet.'
            : 'No saved Outdoor GPS+BTS records were found.',
      ),
      backgroundColor: ok ? Colors.green : Colors.orange,
      duration: const Duration(seconds: 5),
    ),
  );
}
```

## 3) Replace the four signal metric chips

Current code:

```dart
Chip(label: Text('Signal: ${_latestGpsBtsRecord!.signalStrength ?? '-'} dBm')),
Chip(label: Text('RSRP: ${_latestGpsBtsRecord!.rsrp ?? '-'} dBm')),
Chip(label: Text('RSRQ: ${_latestGpsBtsRecord!.rsrq ?? '-'} dB')),
Chip(label: Text('SINR: ${_latestGpsBtsRecord!.sinr ?? '-'} dB')),
```

Replace with:

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

This makes the difference between a true unavailable modem field and a display bug explicit.

## 4) Change the Researcher Mode export button label

Replace:

```dart
label: const Text('Export Outdoor GPS+BTS Dataset'),
```

with:

```dart
label: const Text('Export Outdoor GPS+BTS (Excel XLSX)'),
```

Keep:

```dart
onPressed: _exportOutdoorGpsBts,
```

## 5) `dispose()` does not need to be made async

Keep the existing call to `stopRecording()` in `dispose()`. With the replacement service every completed record was already appended with `flush: true`, so an app close no longer depends on one final end-of-session write for data survival.
