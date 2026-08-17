# WiFi KNN Locator — Outdoor GPS+BTS Reliability Fix

Contents:

- `replacements/outdoor_gps_bts_service.dart`
  - creates storage before recording
  - saves every completed record immediately
  - final flush on Stop
  - valid LTE RSRP fallback via `signalStrength/getDbm`
- `replacements/outdoor_csv_service.dart`
  - durable CSV session writer
  - real XLSX conversion
  - share/save export with CSV fallback
- `patches/MainActivity_changes.md`
  - requests fresh CellInfo instead of always returning cache first
  - robust LTE RSRP/RSRQ/RSSNR extraction
- `patches/main_dart_changes.md`
  - correct Stop status
  - reliable export
  - metric display
- `patches/pubspec_change.md`
  - adds `excel: ^4.0.6`
- `AGENT_PROMPT_FA.md`
  - exact application and test instructions

Important:
RSRQ and SINR cannot be guaranteed on every Android phone. The application
must show/export them when the modem exposes them, but must never fabricate
research measurements when Android reports them unavailable.
