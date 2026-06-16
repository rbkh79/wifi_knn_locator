package com.example.wifi_knn_locator_new

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
        Log.d(TAG, "Device: ${Build.MANUFACTURER} ${Build.MODEL}")

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.JELLY_BEAN_MR1) {
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
            true
        }

        Log.d(TAG, "Permissions: FINE=$hasFineLocation, COARSE=$hasCoarseLocation, PHONE=$hasPhoneState")

        if (!hasFineLocation && !hasCoarseLocation) {
            Log.e(TAG, "هیچ مجوز Location نداریم")
            result.error("PERMISSION_DENIED", "مجوز Location داده نشده", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            try {
                val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
                val activeSubs = subscriptionManager.activeSubscriptionInfoList

                if (activeSubs.isNullOrEmpty()) {
                    Log.w(TAG, "لیست سیم‌کارت‌ها خالی است")
                    fetchCellInfoForManager(telephonyManager, result)
                } else {
                    Log.d(TAG, "تعداد سیم‌کارت‌های فعال: ${activeSubs.size}")
                    if (activeSubs.size == 1) {
                        fetchCellInfoForManager(telephonyManager, result)
                    } else {
                        fetchCellInfoForDualSim(activeSubs, telephonyManager, result)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "خطا در SubscriptionManager: ${e.message}")
                fetchCellInfoForManager(telephonyManager, result)
            }
        } else {
            fetchCellInfoForManager(telephonyManager, result)
        }
    }

    @SuppressLint("MissingPermission")
    private fun fetchCellInfoForManager(telephonyManager: TelephonyManager, result: MethodChannel.Result) {
        Log.d(TAG, "fetchCellInfoForManager: شروع اسکن")

        try {
            val allCellInfo = telephonyManager.allCellInfo
            if (allCellInfo != null && allCellInfo.isNotEmpty()) {
                Log.d(TAG, "allCellInfo موفق: ${allCellInfo.size} دکل")
                result.success(processCellInfoList(allCellInfo))
                return
            } else {
                Log.w(TAG, "allCellInfo خالی یا null، تلاش با requestCellInfoUpdate")
            }
        } catch (e: Exception) {
            Log.e(TAG, "خطا در allCellInfo: ${e.message}")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Log.d(TAG, "تلاش با requestCellInfoUpdate (Android 11+)")
            val handler = Handler(Looper.getMainLooper())
            var callbackCalled = false

            val timeoutRunnable = Runnable {
                if (!callbackCalled) {
                    callbackCalled = true
                    Log.w(TAG, "requestCellInfoUpdate timeout")
                    val fallback = try { telephonyManager.allCellInfo ?: emptyList() } catch (e: Exception) { emptyList() }
                    result.success(processCellInfoList(fallback))
                }
            }

            try {
                telephonyManager.requestCellInfoUpdate(
                    mainExecutor,
                    object : TelephonyManager.CellInfoCallback() {
                        override fun onCellInfo(list: MutableList<CellInfo>) {
                            if (!callbackCalled) {
                                callbackCalled = true
                                handler.removeCallbacks(timeoutRunnable)
                                Log.d(TAG, "requestCellInfoUpdate موفق: ${list.size} دکل")
                                result.success(processCellInfoList(list))
                            }
                        }

                        override fun onError(errorCode: Int, detail: Throwable?) {
                            if (!callbackCalled) {
                                callbackCalled = true
                                handler.removeCallbacks(timeoutRunnable)
                                Log.e(TAG, "requestCellInfoUpdate خطا: code=$errorCode")
                                val fallback = try { telephonyManager.allCellInfo ?: emptyList() } catch (e: Exception) { emptyList() }
                                result.success(processCellInfoList(fallback))
                            }
                        }
                    }
                )
                handler.postDelayed(timeoutRunnable, 5000)
            } catch (e: Exception) {
                Log.e(TAG, "Exception در requestCellInfoUpdate: ${e.message}")
                val fallback = try { telephonyManager.allCellInfo ?: emptyList() } catch (ex: Exception) { emptyList() }

                if (fallback.isEmpty()) {
                    try {
                        val cellLoc = telephonyManager.cellLocation
                        if (cellLoc != null) {
                            val cellMap = cellLocationToMap(cellLoc)
                            if (cellMap != null) {
                                result.success(mapOf("serving_cell" to cellMap, "neighboring_cells" to emptyList<Any>()))
                                return
                            }
                        }
                    } catch (e2: Exception) {
                        Log.w(TAG, "cellLocation fallback failed: ${e2.message}")
                    }
                }

                result.success(processCellInfoList(fallback))
            }
        } else {
            Log.d(TAG, "Android < 11: استفاده از allCellInfo")
            val list = try { telephonyManager.allCellInfo ?: emptyList() } catch (e: Exception) { emptyList() }
            result.success(processCellInfoList(list))
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

        val timeoutRunnable = Runnable {
            if (!callbackCalled) {
                callbackCalled = true
                Log.w(TAG, "Dual-SIM timeout")
                result.success(processCellInfoList(allCells))
            }
        }
        handler.postDelayed(timeoutRunnable, 7000)

        for (subInfo in activeSubs) {
            try {
                val tmForSub = baseTelephonyManager.createForSubscriptionId(subInfo.subscriptionId)
                Log.d(TAG, "اسکن سیم‌کارت: subId=${subInfo.subscriptionId}, slot=${subInfo.simSlotIndex}")

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    tmForSub.requestCellInfoUpdate(
                        mainExecutor,
                        object : TelephonyManager.CellInfoCallback() {
                            override fun onCellInfo(list: MutableList<CellInfo>) {
                                if (!callbackCalled) {
                                    allCells.addAll(list)
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
                                    try { allCells.addAll(tmForSub.allCellInfo ?: emptyList()) } catch (e: Exception) {}
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
                    try { allCells.addAll(tmForSub.allCellInfo ?: emptyList()) } catch (e: Exception) {}
                    pending--
                    if (pending == 0) {
                        callbackCalled = true
                        handler.removeCallbacks(timeoutRunnable)
                        result.success(processCellInfoList(allCells))
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Exception در سیم‌کارت ${subInfo.subscriptionId}: ${e.message}")
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
                        Log.d(TAG, "دکل متصل: ${cellData["networkType"]} CellID=${cellData["cellId"]}")
                    } else {
                        neighboringCells.add(cellData)
                        Log.d(TAG, "دکل مجاور: ${cellData["networkType"]} CellID=${cellData["cellId"]}")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "خطا در پردازش دکل: ${e.message}")
            }
        }

        if (servingCell == null && neighboringCells.isNotEmpty()) {
            Log.w(TAG, "serving cell ندیدیم، اولین دکل رو جایگزین می‌کنیم")
            servingCell = neighboringCells.removeAt(0)
        }

        return mapOf("serving_cell" to servingCell, "neighboring_cells" to neighboringCells)
    }

    private fun cellLocationToMap(cellLocation: android.telephony.CellLocation): Map<String, Any?>? {
        return try {
            when (cellLocation) {
                is android.telephony.gsm.GsmCellLocation -> mapOf(
                    "cellId" to cellLocation.cid.takeIf { it != -1 },
                    "lac" to cellLocation.lac.takeIf { it != -1 },
                    "networkType" to "GSM",
                    "signalStrength" to null
                )
                is android.telephony.cdma.CdmaCellLocation -> mapOf(
                    "cellId" to cellLocation.baseStationId.takeIf { it != -1 },
                    "networkType" to "CDMA",
                    "signalStrength" to null
                )
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
                    val ci = id.ci
                    if (ci == Int.MAX_VALUE) return null
                    val mcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mccString else id.mcc?.toString()
                    val mnc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mncString else id.mnc?.toString()
                    val tac = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.tac.takeIf { it != Int.MAX_VALUE } else null
                    val pci = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.pci.takeIf { it != Int.MAX_VALUE } else null
                    val earfcn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) id.earfcn.takeIf { it != Int.MAX_VALUE } else null
                    Log.d(TAG, "LTE: ci=$ci, mcc=$mcc, mnc=$mnc, tac=$tac, dbm=${cellInfo.cellSignalStrength.dbm}")
                    mapOf("cellId" to ci, "tac" to tac, "mcc" to mcc, "mnc" to mnc,
                        "signalStrength" to cellInfo.cellSignalStrength.dbm, "networkType" to "LTE",
                        "pci" to pci, "earfcn" to earfcn)
                }
                is CellInfoWcdma -> {
                    val id = cellInfo.cellIdentity
                    val cid = id.cid
                    if (cid == Int.MAX_VALUE) return null
                    val mcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mccString else id.mcc?.toString()
                    val mnc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mncString else id.mnc?.toString()
                    val lac = id.lac.takeIf { it != Int.MAX_VALUE }
                    Log.d(TAG, "WCDMA: cid=$cid, mcc=$mcc, mnc=$mnc, lac=$lac")
                    mapOf("cellId" to cid, "lac" to lac, "mcc" to mcc, "mnc" to mnc,
                        "signalStrength" to cellInfo.cellSignalStrength.dbm, "networkType" to "WCDMA",
                        "psc" to id.psc.takeIf { it != Int.MAX_VALUE })
                }
                is CellInfoGsm -> {
                    val id = cellInfo.cellIdentity
                    val cid = id.cid
                    if (cid == Int.MAX_VALUE) return null
                    val mcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mccString else id.mcc?.toString()
                    val mnc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mncString else id.mnc?.toString()
                    val lac = id.lac.takeIf { it != Int.MAX_VALUE }
                    Log.d(TAG, "GSM: cid=$cid, mcc=$mcc, mnc=$mnc, lac=$lac")
                    mapOf("cellId" to cid, "lac" to lac, "mcc" to mcc, "mnc" to mnc,
                        "signalStrength" to cellInfo.cellSignalStrength.dbm, "networkType" to "GSM")
                }
                is CellInfoNr -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val id = cellInfo.cellIdentity as android.telephony.CellIdentityNr
                        val nci = id.nci
                        if (nci == Long.MAX_VALUE) return null
                        val tac = id.tac.takeIf { it != Int.MAX_VALUE }
                        Log.d(TAG, "NR: nci=$nci, mcc=${id.mccString}, tac=$tac")
                        mapOf("cellId" to nci, "tac" to tac, "mcc" to id.mccString, "mnc" to id.mncString,
                            "signalStrength" to cellInfo.cellSignalStrength.dbm, "networkType" to "NR",
                            "pci" to id.pci.takeIf { it != Int.MAX_VALUE })
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
