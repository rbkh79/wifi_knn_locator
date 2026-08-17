# MainActivity.kt changes

Target:
`android/app/src/main/kotlin/com/example/wifi_knn_locator/MainActivity.kt`

## 1) Replace the entire `fetchCellInfoForManager(...)` function

Replace the current function beginning with:

```kotlin
@SuppressLint("MissingPermission")
private fun fetchCellInfoForManager(
```

and ending immediately before `fetchCellInfoForDualSim(...)` with:

```kotlin
@SuppressLint("MissingPermission")
private fun fetchCellInfoForManager(
    telephonyManager: TelephonyManager,
    result: MethodChannel.Result
) {
    Log.d(TAG, "fetchCellInfoForManager: requesting fresh cell info")

    // Keep a cached copy only as a fallback. The old code returned this cache
    // immediately, so fresh RSRP/RSRQ/RSSNR values were often never requested.
    val cached = try {
        telephonyManager.allCellInfo ?: emptyList()
    } catch (e: Exception) {
        Log.w(TAG, "Initial allCellInfo failed: ${e.message}")
        emptyList()
    }

    // requestCellInfoUpdate was added in API 29 (Android 10 / Q).
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        val handler = Handler(Looper.getMainLooper())
        var callbackCalled = false

        val timeoutRunnable = Runnable {
            if (!callbackCalled) {
                callbackCalled = true
                Log.w(TAG, "Fresh cell-info request timed out; using cached cells")
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

## 2) Replace only the `is CellInfoLte -> { ... }` branch inside `parseCellInfo`

Use this exact LTE branch:

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
        value.takeIf {
            it != Int.MAX_VALUE && it in min..max
        }

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

    // For LTE Android documents getDbm() as the measured-cell RSRP.
    // Therefore it is a legitimate fallback when getRsrp() reports UNAVAILABLE.
    val dbmAsRsrp = validRange(signal.dbm, -140, -43)

    val directRsrp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        validRange(signal.rsrp, -140, -43)
    } else {
        null
    }

    val rsrp = directRsrp ?: dbmAsRsrp

    // Do not invent RSRQ/SINR. Keep null if the modem/firmware does not expose it.
    val rsrq = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        valid(signal.rsrq)
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

## 3) Small Dual-SIM compatibility improvement

Inside `fetchCellInfoForDualSim(...)`, change:

```kotlin
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
```

to:

```kotlin
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
```

This lets Android 10 use the fresh asynchronous cell-info API too.

## Important research behavior

- `RSRP`: if direct `getRsrp()` is unavailable on LTE, `getDbm()` is used because Android defines LTE `getDbm()` as measured-cell RSRP.
- `RSRQ`: recorded only when Android/modem exposes it.
- `SINR`: uses LTE `getRssnr()` only when exposed.
- Never replace missing RSRQ/SINR with made-up values. A missing value must remain missing.
