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
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.JELLY_BEAN_MR1) {
            result.error("UNSUPPORTED", "Android version too old", null)
            return
        }

        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

        val hasFineLocation = ActivityCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        // Android 13+ نیاز به READ_BASIC_PHONE_STATE داره، نه READ_PHONE_STATE
        val hasPhoneState = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.checkSelfPermission(
                this, Manifest.permission.READ_BASIC_PHONE_STATE
            ) == PackageManager.PERMISSION_GRANTED ||
            ActivityCompat.checkSelfPermission(
                this, Manifest.permission.READ_PHONE_STATE
            ) == PackageManager.PERMISSION_GRANTED
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ActivityCompat.checkSelfPermission(
                this, Manifest.permission.READ_PHONE_STATE
            ) == PackageManager.PERMISSION_GRANTED
        } else true

        if (!hasFineLocation) {
            Log.w(TAG, "مجوز ACCESS_FINE_LOCATION نداریم")
            result.error("PERMISSION_DENIED", "مجوز ACCESS_FINE_LOCATION داده نشده", null)
            return
        }

        Log.d(TAG, "مجوزها: FINE_LOCATION=$hasFineLocation, PHONE_STATE=$hasPhoneState")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+ : requestCellInfoUpdate با timeout
            val handler = Handler(Looper.getMainLooper())
            var callbackCalled = false

            val timeoutRunnable = Runnable {
                if (!callbackCalled) {
                    callbackCalled = true
                    Log.w(TAG, "timeout رسید، از allCellInfo استفاده می‌کنیم")
                    val fallback = try {
                        telephonyManager.allCellInfo ?: emptyList()
                    } catch (e: Exception) {
                        emptyList()
                    }
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
                                Log.e(TAG, "خطا در CellInfoUpdate: $errorCode - $detail")
                                val fallback = try {
                                    telephonyManager.allCellInfo ?: emptyList()
                                } catch (e: Exception) {
                                    emptyList()
                                }
                                result.success(processCellInfoList(fallback))
                            }
                        }
                    }
                )
                // timeout 3 ثانیه
                handler.postDelayed(timeoutRunnable, 3000)
            } catch (e: Exception) {
                Log.e(TAG, "Exception در requestCellInfoUpdate: ${e.message}")
                val fallback = try {
                    telephonyManager.allCellInfo ?: emptyList()
                } catch (ex: Exception) {
                    emptyList()
                }
                result.success(processCellInfoList(fallback))
            }
        } else {
            val list = try {
                telephonyManager.allCellInfo ?: emptyList()
            } catch (e: Exception) {
                Log.e(TAG, "خطا در allCellInfo: ${e.message}")
                emptyList()
            }
            result.success(processCellInfoList(list))
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

    @Suppress("DEPRECATION")
    private fun parseCellInfo(cellInfo: CellInfo): Map<String, Any?>? {
        return try {
            when (cellInfo) {
                is CellInfoLte -> {
                    val id = cellInfo.cellIdentity
                    val ci = id.ci
                    // فیلتر سخت‌گیرانه رو برداشتیم - فقط MAX_VALUE رو حذف می‌کنیم
                    if (ci == Int.MAX_VALUE) {
                        Log.d(TAG, "LTE ci=MAX_VALUE, skip")
                        return null
                    }

                    val mcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mccString else id.mcc?.toString()
                    val mnc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mncString else id.mnc?.toString()
                    val tac = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.tac.takeIf { it != Int.MAX_VALUE } else null
                    val pci = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.pci.takeIf { it != Int.MAX_VALUE } else null
                    val earfcn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) id.earfcn.takeIf { it != Int.MAX_VALUE } else null

                    Log.d(TAG, "LTE: ci=$ci, mcc=$mcc, mnc=$mnc, tac=$tac, dbm=${cellInfo.cellSignalStrength.dbm}")

                    mapOf(
                        "cellId" to ci,
                        "tac" to tac,
                        "mcc" to mcc,
                        "mnc" to mnc,
                        "signalStrength" to cellInfo.cellSignalStrength.dbm,
                        "networkType" to "LTE",
                        "pci" to pci,
                        "earfcn" to earfcn
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