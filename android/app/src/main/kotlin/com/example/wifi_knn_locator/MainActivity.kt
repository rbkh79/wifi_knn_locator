package com.example.wifi_knn_locator

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.CellInfo
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellInfoWcdma
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "wifi_knn_locator/cell_info"
    private val TAG = "BTS_Service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getCellInfo") {
                    getCellInfoAsync(result)
                } else {
                    result.notImplemented()
                }
            }
    }

    @SuppressLint("MissingPermission")
    private fun getCellInfoAsync(result: MethodChannel.Result) {
        Log.d(TAG, "=== شروع اسکن BTS ===")
        Log.d(TAG, "Android version: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
        Log.d(TAG, "Device manufacturer: ${Build.MANUFACTURER}")
        Log.d(TAG, "Device model: ${Build.MODEL}")

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.JELLY_BEAN_MR1) {
            Log.e(TAG, "Android version too old: API ${Build.VERSION.SDK_INT}")
            result.error("UNSUPPORTED", "Android version too old", null)
            return
        }

        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

        val hasFineLocation = ActivityCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        val hasCoarseLocation = ActivityCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        // Android 13+ نیاز به READ_BASIC_PHONE_STATE داره، نه READ_PHONE_STATE
        val hasPhoneState = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val hasBasic = ActivityCompat.checkSelfPermission(
                this, Manifest.permission.READ_BASIC_PHONE_STATE
            ) == PackageManager.PERMISSION_GRANTED
            val hasNormal = ActivityCompat.checkSelfPermission(
                this, Manifest.permission.READ_PHONE_STATE
            ) == PackageManager.PERMISSION_GRANTED
            val hasPrecise = ActivityCompat.checkSelfPermission(
                this, Manifest.permission.READ_PRECISE_PHONE_STATE
            ) == PackageManager.PERMISSION_GRANTED
            Log.d(TAG, "Android 13+ Permissions: BASIC=$hasBasic, PHONE=$hasNormal, PRECISE=$hasPrecise")
            hasBasic || hasNormal || hasPrecise
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val hasNormal = ActivityCompat.checkSelfPermission(
                this, Manifest.permission.READ_PHONE_STATE
            ) == PackageManager.PERMISSION_GRANTED
            val hasPrecise = ActivityCompat.checkSelfPermission(
                this, Manifest.permission.READ_PRECISE_PHONE_STATE
            ) == PackageManager.PERMISSION_GRANTED
            Log.d(TAG, "Android 6-12 Permissions: PHONE=$hasNormal, PRECISE=$hasPrecise")
            hasNormal || hasPrecise
        } else {
            Log.d(TAG, "Android < 6: Phone permissions not required")
            true
        }

        Log.d(TAG, "Final Permissions: FINE_LOCATION=$hasFineLocation, COARSE_LOCATION=$hasCoarseLocation, PHONE_STATE=$hasPhoneState")

        if (!hasFineLocation && !hasCoarseLocation) {
            Log.e(TAG, "هیچ مجوز Location نداریم")
            result.error("PERMISSION_DENIED", "مجوز Location داده نشده", null)
            return
        }

        // بررسی سیم‌کارت‌های فعال برای پشتیبانی از Dual-SIM
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            try {
                val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
                val activeSubs = subscriptionManager.activeSubscriptionInfoList

                if (activeSubs.isNullOrEmpty()) {
                    Log.w(TAG, "لیست سیم‌کارت‌ها خالی است")
                    // تلاش با TelephonyManager پیش‌فرض
                    fetchCellInfoForManager(telephonyManager, result)
                } else {
                    Log.d(TAG, "تعداد سیم‌کارت‌های فعال: ${activeSubs.size}")
                    for (sub in activeSubs) {
                        Log.d(TAG, "  - SIM ${sub.simSlotIndex}: subId=${sub.subscriptionId}, carrier=${sub.carrierName}")
                    }

                    if (activeSubs.size == 1) {
                        fetchCellInfoForManager(telephonyManager, result)
                    } else {
                        fetchCellInfoForDualSim(activeSubs, telephonyManager, result)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "خطا در SubscriptionManager: ${e.message}")
                // Fallback به روش ساده
                fetchCellInfoForManager(telephonyManager, result)
            }
        } else {
            // Android قدیمی: از روش قبلی استفاده کن
            fetchCellInfoForManager(telephonyManager, result)
        }
    }

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

    @SuppressLint("MissingPermission")
    private fun fetchCellInfoForDualSim(
        activeSubs: List<SubscriptionInfo>,
        baseTelephonyManager: TelephonyManager,
        result: MethodChannel.Result
    ) {
        val allCells = mutableListOf<CellInfo>()
        var pending = activeSubs.size
        val handler = Handler(Looper.getMainLooper())
        var callbackCalled = false

        // Timeout کلی برای Dual-SIM
        val timeoutRunnable = Runnable {
            if (!callbackCalled) {
                callbackCalled = true
                Log.w(TAG, "Dual-SIM timeout رسید")
                result.success(processCellInfoList(allCells))
            }
        }
        handler.postDelayed(timeoutRunnable, 7000) // 7 ثانیه برای Dual-SIM

        for (subInfo in activeSubs) {
            try {
                val tmForSub = baseTelephonyManager.createForSubscriptionId(subInfo.subscriptionId)
                Log.d(TAG, "اسکن سیم‌کارت: subId=${subInfo.subscriptionId}, simSlot=${subInfo.simSlotIndex}")

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    tmForSub.requestCellInfoUpdate(
                        mainExecutor,
                        object : TelephonyManager.CellInfoCallback() {
                            override fun onCellInfo(list: MutableList<CellInfo>) {
                                if (!callbackCalled) {
                                    allCells.addAll(list)
                                    Log.d(TAG, "سیم‌کارت ${subInfo.subscriptionId}: ${list.size} دکل")
                                    pending--
                                    if (pending == 0) {
                                        callbackCalled = true
                                        handler.removeCallbacks(timeoutRunnable)
                                        result.success(processCellInfoList(allCells))
                                    }
                                }
                            }

                            override fun onError(errorCode: Int, detail: Throwable?) {
                                if (!callbackCalled) {
                                    Log.e(TAG, "خطا در سیم‌کارت ${subInfo.subscriptionId}: $errorCode")
                                    // Fallback به allCellInfo
                                    try {
                                        allCells.addAll(tmForSub.allCellInfo ?: emptyList())
                                    } catch (e: Exception) {
                                        Log.e(TAG, "Fallback failed for sub ${subInfo.subscriptionId}")
                                    }

                                    // اگر هنوز خالیه، تلاش برای cellLocation به عنوان fallback
                                    if (allCells.isEmpty()) {
                                        try {
                                            val cellLoc = tmForSub.cellLocation
                                            if (cellLoc != null) {
                                                val cellMap = cellLocationToMap(cellLoc)
                                                if (cellMap != null) {
                                                    // وقتی pending به 0 رسید، مستقیم پاسخ حاوی cellMap می‌فرستیم
                                                    pending--
                                                    if (pending == 0) {
                                                        callbackCalled = true
                                                        handler.removeCallbacks(timeoutRunnable)
                                                        result.success(mapOf("serving_cell" to cellMap, "neighboring_cells" to emptyList<Any>()))
                                                        return
                                                    }
                                                }
                                            }
                                        } catch (e: Exception) {
                                            Log.w(TAG, "cellLocation fallback for sub ${subInfo.subscriptionId} failed: ${e.message}")
                                        }
                                    }

                                    pending--
                                    if (pending == 0) {
                                        callbackCalled = true
                                        handler.removeCallbacks(timeoutRunnable)
                                        result.success(processCellInfoList(allCells))
                                    }
                                }
                            }
                        }
                    )
                } else {
                    // Android قدیمی: از allCellInfo استفاده کن
                    try {
                        allCells.addAll(tmForSub.allCellInfo ?: emptyList())
                    } catch (e: Exception) {
                        Log.e(TAG, "خطا در allCellInfo برای سیم‌کارت ${subInfo.subscriptionId}")
                    }
                    pending--
                    if (pending == 0) {
                        callbackCalled = true
                        handler.removeCallbacks(timeoutRunnable)
                        result.success(processCellInfoList(allCells))
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Exception در اسکن سیم‌کارت ${subInfo.subscriptionId}: ${e.message}")
                pending--
                if (pending == 0) {
                    callbackCalled = true
                    handler.removeCallbacks(timeoutRunnable)
                    result.success(processCellInfoList(allCells))
                }
            }
        }
    }

    private fun processCellInfoList(allCellInfo: List<CellInfo>): Map<String, Any?> {
        if (allCellInfo.isEmpty()) {
            Log.w(TAG, "لیست دکل‌ها خالیه")
            return mapOf("serving_cell" to null, "neighboring_cells" to emptyList<Any>())
        }

        Log.d(TAG, "تعداد ${allCellInfo.size} دکل پیدا شد")

        var servingCell: Map<String, Any?>? = null
        val neighboringCells = mutableListOf<Map<String, Any?>>()

        for (cellInfo in allCellInfo) {
            try {
                val cellData = parseCellInfo(cellInfo)
                if (cellData != null) {
                    if (cellInfo.isRegistered) {
                        if (servingCell == null) servingCell = cellData
                        Log.d(TAG, "دکل متصل: ${cellData["networkType"]} - CellID: ${cellData["cellId"]}")
                    } else {
                        neighboringCells.add(cellData)
                        Log.d(TAG, "دکل مجاور: ${cellData["networkType"]} - CellID: ${cellData["cellId"]}")
                    }
                } else {
                    Log.d(TAG, "دکل null برگشت: ${cellInfo.javaClass.simpleName} registered=${cellInfo.isRegistered}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "خطا در پردازش دکل: ${e.message}")
            }
        }

        // اگر serving cell پیدا نشد، اولین دکل valid رو به عنوان serving cell بذار
        if (servingCell == null && neighboringCells.isNotEmpty()) {
            Log.w(TAG, "serving cell ندیدیم، اولین دکل رو جایگزین می‌کنیم")
            servingCell = neighboringCells.removeAt(0)
        }

        return mapOf(
            "serving_cell" to servingCell,
            "neighboring_cells" to neighboringCells
        )
    }

    // Fallback helper: در صورتی که allCellInfo خالی باشد از cellLocation استفاده می‌کنیم (GSM/CDMA)
    private fun cellLocationToMap(cellLocation: android.telephony.CellLocation): Map<String, Any?>? {
        return try {
            when (cellLocation) {
                is android.telephony.gsm.GsmCellLocation -> {
                    val cid = cellLocation.cid.takeIf { it != -1 }
                    val lac = cellLocation.lac.takeIf { it != -1 }
                    mapOf(
                        "cellId" to cid,
                        "lac" to lac,
                        "networkType" to "GSM",
                        "signalStrength" to null
                    )
                }
                is android.telephony.cdma.CdmaCellLocation -> {
                    val baseId = cellLocation.baseStationId.takeIf { it != -1 }
                    mapOf(
                        "cellId" to baseId,
                        "networkType" to "CDMA",
                        "signalStrength" to null
                    )
                }
                else -> null
            }
        } catch (e: Exception) {
            Log.w(TAG, "cellLocationToMap failed: ${e.message}")
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun parseCellInfo(cellInfo: CellInfo): Map<String, Any?>? {
        return try {
            when (cellInfo) {
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

                is CellInfoWcdma -> {
                    val id = cellInfo.cellIdentity
                    val cid = id.cid
                    if (cid == Int.MAX_VALUE) {
                        Log.d(TAG, "WCDMA cid=MAX_VALUE, skip")
                        return null
                    }

                    val mcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mccString else id.mcc?.toString()
                    val mnc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mncString else id.mnc?.toString()
                    val lac = id.lac.takeIf { it != Int.MAX_VALUE }

                    Log.d(TAG, "WCDMA: cid=$cid, mcc=$mcc, mnc=$mnc, lac=$lac")

                    mapOf(
                        "cellId" to cid,
                        "lac" to lac,
                        "mcc" to mcc,
                        "mnc" to mnc,
                        "signalStrength" to cellInfo.cellSignalStrength.dbm,
                        "networkType" to "WCDMA",
                        "psc" to id.psc.takeIf { it != Int.MAX_VALUE }
                    )
                }

                is CellInfoGsm -> {
                    val id = cellInfo.cellIdentity
                    val cid = id.cid
                    if (cid == Int.MAX_VALUE) {
                        Log.d(TAG, "GSM cid=MAX_VALUE, skip")
                        return null
                    }

                    val mcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mccString else id.mcc?.toString()
                    val mnc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mncString else id.mnc?.toString()
                    val lac = id.lac.takeIf { it != Int.MAX_VALUE }

                    Log.d(TAG, "GSM: cid=$cid, mcc=$mcc, mnc=$mnc, lac=$lac")

                    mapOf(
                        "cellId" to cid,
                        "lac" to lac,
                        "mcc" to mcc,
                        "mnc" to mnc,
                        "signalStrength" to cellInfo.cellSignalStrength.dbm,
                        "networkType" to "GSM"
                    )
                }

                is CellInfoNr -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val id = cellInfo.cellIdentity as android.telephony.CellIdentityNr
                        val nci = id.nci
                        if (nci == Long.MAX_VALUE) {
                            Log.d(TAG, "NR nci=MAX_VALUE, skip")
                            return null
                        }

                        val tac = id.tac.takeIf { it != Int.MAX_VALUE }
                        Log.d(TAG, "NR: nci=$nci, mcc=${id.mccString}, tac=$tac")

                        mapOf(
                            "cellId" to nci,
                            "tac" to tac,
                            "mcc" to id.mccString,
                            "mnc" to id.mncString,
                            "signalStrength" to cellInfo.cellSignalStrength.dbm,
                            "networkType" to "NR",
                            "pci" to id.pci.takeIf { it != Int.MAX_VALUE }
                        )
                    } else null
                }

                else -> {
                    Log.d(TAG, "نوع دکل پشتیبانی نمی‌شه: ${cellInfo.javaClass.simpleName}")
                    null
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "خطا در خواندن اطلاعات دکل: ${e.message}")
            null
        }
    }
}