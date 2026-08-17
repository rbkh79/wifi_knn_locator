# Test checklist before field data collection

## Build
- `flutter pub get` succeeds.
- `flutter analyze` has no new error from the modified files.
- Codemagic Android App Bundle build succeeds.

## Persistence test
1. Start Outdoor GPS+BTS.
2. Wait until at least 20 records are shown.
3. Stop normally.
4. Confirm a green message says the actual record count was saved.
5. In Researcher Mode tap `Open Outdoor GPS+BTS Excel (XLSX)`.
6. Confirm a real `.xlsx` appears in `Downloads/WiFiKnnLocator` on Android 10+.
7. Confirm the same export opens in Excel/WPS/Sheets, not Android Share Sheet.
8. Check the sheet contains the recorded rows.

## Crash/restart recovery test
1. Start another recording.
2. Wait for at least 20 completed records and make sure status ends with `saved`.
3. Force-close the app WITHOUT pressing Stop.
4. Re-open the app.
5. Go directly to Researcher Mode and export Outdoor GPS+BTS.
6. The latest interrupted session must still be found and opened as XLSX.
7. Confirm most/all completed rows before force-close exist. The last in-flight sample may legitimately be absent.

## Radio metrics test
- LTE RSRP should show a valid negative dBm value when Android exposes either direct RSRP or valid LTE `dbm`.
- RSRQ/SINR may still show `N/A (device)` on devices/modems that do not expose them.
- Never fabricate RSRQ/SINR.

## Do not start a long field campaign until all tests above pass.
