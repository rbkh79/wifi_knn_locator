# Patch: android/app/src/main/kotlin/.../MainActivity.kt

این patch دو کار انجام می‌دهد:

1. XLSX ساخته‌شده را بدون Share Sheet در Downloads عمومی Android ذخیره می‌کند.
2. Cell info تازه‌تر و RSRP/RSRQ/SINR صحیح‌تر را می‌گیرد.

**package / namespace / applicationId موجود پروژه را تغییر نده.**

---

# A) Export XLSX به Downloads عمومی بدون Share Sheet

## A-1) importها

اگر وجود ندارند، این importها را بالای فایل اضافه کن:

```kotlin
import android.content.ContentValues
import android.os.Environment
import android.provider.MediaStore
import java.io.File
```

## A-2) channel دوم

داخل `MainActivity` کنار channel فعلی BTS این constant را اضافه کن:

```kotlin
private val FILE_EXPORT_CHANNEL = "wifi_knn_locator/file_export"
```

## A-3) داخل `configureFlutterEngine(...)`

MethodChannel فعلی `wifi_knn_locator/cell_info` را دست نزن. **بعد از همان handler** این channel دوم را اضافه کن:

```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_EXPORT_CHANNEL)
    .setMethodCallHandler { call, result ->
        when (call.method) {
            "saveFileToDownloads" -> {
                val sourcePath = call.argument<String>("sourcePath")
                val displayName = call.argument<String>("displayName")
                val mimeType = call.argument<String>("mimeType")
                    ?: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

                if (sourcePath.isNullOrBlank() || displayName.isNullOrBlank()) {
                    result.error("BAD_ARGS", "sourcePath/displayName missing", null)
                } else {
                    saveFileToDownloads(
                        sourcePath = sourcePath,
                        displayName = displayName,
                        mimeType = mimeType,
                        result = result
                    )
                }
            }
            else -> result.notImplemented()
        }
    }
```

## A-4) این تابع را داخل کلاس `MainActivity` اضافه کن

```kotlin
@Suppress("DEPRECATION")
private fun saveFileToDownloads(
    sourcePath: String,
    displayName: String,
    mimeType: String,
    result: MethodChannel.Result
) {
    Thread {
        try {
            val source = File(sourcePath)
            if (!source.exists() || source.length() <= 0L) {
                runOnUiThread {
                    result.error("SOURCE_MISSING", "XLSX source file is missing/empty", null)
                }
                return@Thread
            }

            val savedLocation: String

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = contentResolver
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, displayName)
                    put(MediaStore.Downloads.MIME_TYPE, mimeType)
                    put(
                        MediaStore.Downloads.RELATIVE_PATH,
                        Environment.DIRECTORY_DOWNLOADS + "/WiFiKnnLocator"
                    )
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }

                val uri = resolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    values
                ) ?: throw IllegalStateException("Cannot create Downloads item")

                try {
                    resolver.openOutputStream(uri)?.use { output ->
                        source.inputStream().use { input ->
                            input.copyTo(output)
                        }
                    } ?: throw IllegalStateException("Cannot open Downloads output stream")

                    val finishValues = ContentValues().apply {
                        put(MediaStore.Downloads.IS_PENDING, 0)
                    }
                    resolver.update(uri, finishValues, null, null)
                    savedLocation = uri.toString()
                } catch (e: Exception) {
                    try {
                        resolver.delete(uri, null, null)
                    } catch (_: Exception) {
                    }
                    throw e
                }
            } else {
                val downloadsDir = Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS
                )
                if (!downloadsDir.exists() && !downloadsDir.mkdirs()) {
                    throw IllegalStateException("Cannot create Downloads directory")
                }

                val appDir = File(downloadsDir, "WiFiKnnLocator")
                if (!appDir.exists() && !appDir.mkdirs()) {
                    throw IllegalStateException("Cannot create WiFiKnnLocator directory")
                }

                val target = File(appDir, displayName)
                source.copyTo(target, overwrite = true)
                savedLocation = target.absolutePath
            }

            Log.d(TAG, "XLSX copied to public Downloads: $savedLocation")
            runOnUiThread {
                result.success(savedLocation)
            }
        } catch (e: Exception) {
            Log.e(TAG, "saveFileToDownloads failed", e)
            runOnUiThread {
                result.error("SAVE_DOWNLOADS_FAILED", e.message, null)
            }
        }
    }.start()
}
```

در Android 10+ این روش از `MediaStore.Downloads` استفاده می‌کند؛ بنابراین XLSX یک کپی واقعی در Downloads کاربر دارد و هیچ Share Sheet لازم نیست.

---

# B) Fresh BTS metrics

## B-1) کل تابع `fetchCellInfoForManager(...)` را جایگزین کن

```kotlin
@SuppressLint("MissingPermission")
private fun fetchCellInfoForManager(
    telephonyManager: TelephonyManager,
    result: MethodChannel.Result
) {
    Log.d(TAG, "fetchCellInfoForManager: requesting fresh cell info")

    val cached = try {
        telephonyManager.allCellInfo ?: emptyList()
    } catch (e: Exception) {
        Log.w(TAG, "Initial allCellInfo failed: ${e.message}")
        emptyList()
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        val handler = Handler(Looper.getMainLooper())
        var callbackCalled = false

        val timeoutRunnable = Runnable {
            if (!callbackCalled) {
                callbackCalled = true
                Log.w(TAG, "Fresh cell-info request timed out; using cache")
                result.success(processCellInfoList(cached))
            }
        }

        try {
            telephonyManager.requestCellInfoUpdate(
                mainExecutor,
                object : TelephonyManager.CellInfoCallback() {
                    override fun onCellInfo(list: MutableList<CellInfo>) {
                        if (callbackCalled) return
                        callbackCalled = true
                        handler.removeCallbacks(timeoutRunnable)

                        val selected = if (list.isNotEmpty()) list else cached
                        Log.d(
                            TAG,
                            "Fresh cell info: ${list.size}; cached fallback: ${cached.size}"
                        )
                        result.success(processCellInfoList(selected))
                    }

                    override fun onError(errorCode: Int, detail: Throwable?) {
                        if (callbackCalled) return
                        callbackCalled = true
                        handler.removeCallbacks(timeoutRunnable)
                        Log.w(
                            TAG,
                            "Fresh cell-info error=$errorCode detail=$detail; using cache"
                        )
                        result.success(processCellInfoList(cached))
                    }
                }
            )

            handler.postDelayed(timeoutRunnable, 3500)
        } catch (e: Exception) {
            handler.removeCallbacks(timeoutRunnable)
            Log.w(TAG, "requestCellInfoUpdate failed: ${e.message}")
            result.success(processCellInfoList(cached))
        }
    } else {
        Log.d(TAG, "Android < 10: using cached allCellInfo")
        result.success(processCellInfoList(cached))
    }
}
```

## B-2) داخل `fetchCellInfoForDualSim(...)`

فقط شرط مربوط به استفاده از `requestCellInfoUpdate` را از:

```kotlin
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
```

به:

```kotlin
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
```

تغییر بده.

## B-3) کل branch مربوط به `is CellInfoLte -> { ... }` داخل `parseCellInfo` را جایگزین کن

```kotlin
is CellInfoLte -> {
    val id = cellInfo.cellIdentity
    val signal = cellInfo.cellSignalStrength
    val ci = id.ci

    if (ci == Int.MAX_VALUE) {
        Log.d(TAG, "LTE ci=MAX_VALUE, skip")
        return null
    }

    fun valid(value: Int): Int? =
        value.takeIf { it != Int.MAX_VALUE }

    fun validRange(value: Int, min: Int, max: Int): Int? =
        value.takeIf { it != Int.MAX_VALUE && it in min..max }

    val mcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        id.mccString
    } else {
        valid(id.mcc)?.toString()
    }

    val mnc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        id.mncString
    } else {
        valid(id.mnc)?.toString()
    }

    val tac = valid(id.tac)
    val pci = valid(id.pci)

    val earfcn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        valid(id.earfcn)
    } else {
        null
    }

    val dbmAsRsrp = validRange(signal.dbm, -140, -43)

    val directRsrp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        validRange(signal.rsrp, -140, -43)
    } else {
        null
    }

    val rsrp = directRsrp ?: dbmAsRsrp

    // Missing means unavailable from modem/device; do not fabricate it.
    val rsrq = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        validRange(signal.rsrq, -34, 3)
    } else {
        null
    }

    val sinr = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        validRange(signal.rssnr, -20, 30)
    } else {
        null
    }

    val cqi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        validRange(signal.cqi, 0, 15)
    } else {
        null
    }

    val timingAdvance = validRange(signal.timingAdvance, 0, 1282)

    val bandwidth = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        valid(id.bandwidth)
    } else {
        null
    }

    val band = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        id.bands.firstOrNull()
    } else {
        null
    }

    Log.d(
        TAG,
        "LTE ci=$ci pci=$pci earfcn=$earfcn dbm=${signal.dbm} " +
            "directRsrp=$directRsrp effectiveRsrp=$rsrp " +
            "rsrq=$rsrq sinr=$sinr cqi=$cqi ta=$timingAdvance"
    )

    mapOf(
        "cellId" to ci,
        "tac" to tac,
        "mcc" to mcc,
        "mnc" to mnc,
        "signalStrength" to signal.dbm,
        "networkType" to "LTE",
        "pci" to pci,
        "earfcn" to earfcn,
        "rsrp" to rsrp,
        "rsrq" to rsrq,
        "sinr" to sinr,
        "cqi" to cqi,
        "timingAdvance" to timingAdvance,
        "asuLevel" to signal.asuLevel,
        "level" to signal.level,
        "bandwidth" to bandwidth,
        "band" to band,
        "registered" to cellInfo.isRegistered
    )
}
```

## رفتار پژوهشی الزامی

- RSRP در LTE در صورت نبود direct RSRP از LTE `dbm` معتبر fallback می‌گیرد.
- RSRQ و SINR فقط وقتی Android/modem ارائه کند ثبت می‌شوند.
- برای missing metric عدد `0` یا مقدار تخمینی/ساختگی ننویس.
