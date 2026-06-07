package com.example.wifi_knn_locator

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
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

        // چک مجوزها
        val hasFineLocation = ActivityCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        val hasPhoneState = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ActivityCompat.checkSelfPermission(
                this, Manifest.permission.READ_PHONE_STATE
            ) == PackageManager.PERMISSION_GRANTED
        } else true

        if (!hasFineLocation || !hasPhoneState) {
            Log.w(TAG, "مجوزها ناقص: FINE_LOCATION=$hasFineLocation, PHONE_STATE=$hasPhoneState")
            result.error("PERMISSION_DENIED", "مجوزهای لازم داده نشده", null)
            return
        }

        // Android 11+ : باید requestCellInfoUpdate صدا زده بشه
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                telephonyManager.requestCellInfoUpdate(
                    mainExecutor,
                    object : TelephonyManager.CellInfoCallback() {
                        override fun onCellInfo(list: MutableList<CellInfo>) {
                            result.success(processCellInfoList(list))
                        }

                        override fun onError(errorCode: Int, detail: Throwable?) {
                            Log.e(TAG, "خطا در بروزرسانی CellInfo: $errorCode - $detail")
                            result.success(processCellInfoList(telephonyManager.allCellInfo ?: emptyList()))
                        }
                    }
                )
            } catch (e: Exception) {
                Log.e(TAG, "خطا در requestCellInfoUpdate: ${e.message}")
                result.success(processCellInfoList(telephonyManager.allCellInfo ?: emptyList()))
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
                        servingCell = cellData
                        Log.d(TAG, "دکل متصل پیدا شد: ${cellData["networkType"]}")
                    } else {
                        neighboringCells.add(cellData)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "خطا در پردازش دکل: ${e.message}")
            }
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
                    if (ci == Int.MAX_VALUE || ci <= 0) return null

                    val mcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mccString else id.mcc?.toString()
                    val mnc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mncString else id.mnc?.toString()
                    val tac = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.tac else null
                    val pci = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.pci else null

                    mapOf(
                        "cellId" to ci,
                        "tac" to tac,
                        "mcc" to mcc,
                        "mnc" to mnc,
                        "signalStrength" to cellInfo.cellSignalStrength.dbm,
                        "networkType" to "LTE",
                        "pci" to pci
                    )
                }

                is CellInfoWcdma -> {
                    val id = cellInfo.cellIdentity
                    val cid = id.cid
                    if (cid == Int.MAX_VALUE || cid <= 0) return null

                    val mcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mccString else id.mcc?.toString()
                    val mnc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mncString else id.mnc?.toString()

                    mapOf(
                        "cellId" to cid,
                        "lac" to id.lac,
                        "mcc" to mcc,
                        "mnc" to mnc,
                        "signalStrength" to cellInfo.cellSignalStrength.dbm,
                        "networkType" to "WCDMA",
                        "psc" to id.psc
                    )
                }

                is CellInfoGsm -> {
                    val id = cellInfo.cellIdentity
                    val cid = id.cid
                    if (cid == Int.MAX_VALUE || cid <= 0) return null

                    val mcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mccString else id.mcc?.toString()
                    val mnc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.mncString else id.mnc?.toString()

                    mapOf(
                        "cellId" to cid,
                        "lac" to id.lac,
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
                        if (nci == Long.MAX_VALUE || nci <= 0) return null

                        mapOf(
                            "cellId" to nci,
                            "tac" to id.tac,
                            "mcc" to id.mccString,
                            "mnc" to id.mncString,
                            "signalStrength" to cellInfo.cellSignalStrength.dbm,
                            "networkType" to "NR",
                            "pci" to id.pci
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
