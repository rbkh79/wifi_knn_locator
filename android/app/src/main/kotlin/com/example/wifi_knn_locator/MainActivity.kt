package com.example.wifi_knn_locator

import android.Manifest
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

class MainActivity: FlutterActivity() {
    private val CHANNEL = "wifi_knn_locator/cell_info"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getCellInfo") {
                val cellInfo = getCellInfo()
                if (cellInfo != null) {
                    result.success(cellInfo)
                } else {
                    result.error("UNAVAILABLE", "Cell info not available", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getCellInfo(): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.JELLY_BEAN_MR1) {
            return null
        }

        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

        // بررسی مجوز
        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_PHONE_STATE
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return null
        }

        val allCellInfo: List<CellInfo>? = try {
            telephonyManager.allCellInfo
        } catch (e: Exception) {
            null
        }

        if (allCellInfo == null || allCellInfo.isEmpty()) {
            return null
        }

        // پیدا کردن دکل متصل (اولین دکل که isRegistered = true)
        var servingCell: Map<String, Any?>? = null
        val neighboringCells = mutableListOf<Map<String, Any?>>()

        for (cellInfo in allCellInfo) {
            val cellData = parseCellInfo(cellInfo)
            if (cellData != null) {
                if (cellInfo.isRegistered) {
                    servingCell = cellData
                } else {
                    neighboringCells.add(cellData)
                }
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
                    val cellIdentity = cellInfo.cellIdentity
                    val cellSignalStrength = cellInfo.cellSignalStrength
                    mapOf(
                        "cellId" to cellIdentity.ci, // استفاده از ci به جای cid (deprecated اما در همه نسخه‌ها موجود)
                        "tac" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            try { cellIdentity.tac } catch (e: Exception) { null }
                        } else { null }),
                        "mcc" to cellIdentity.mcc, // استفاده از mcc به جای mccString
                        "mnc" to cellIdentity.mnc, // استفاده از mnc به جای mncString
                        "signalStrength" to try { cellSignalStrength.dbm } catch (e: Exception) { null },
                        "networkType" to "LTE",
                        "pci" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            try { cellIdentity.pci } catch (e: Exception) { null }
                        } else { null })
                    )
                }
                is CellInfoWcdma -> {
                    val cellIdentity = cellInfo.cellIdentity
                    val cellSignalStrength = cellInfo.cellSignalStrength
                    mapOf(
                        "cellId" to cellIdentity.cid,
                        "lac" to cellIdentity.lac,
                        "mcc" to cellIdentity.mcc,
                        "mnc" to cellIdentity.mnc,
                        "signalStrength" to try { cellSignalStrength.dbm } catch (e: Exception) { null },
                        "networkType" to "WCDMA",
                        "psc" to cellIdentity.psc
                    )
                }
                is CellInfoGsm -> {
                    val cellIdentity = cellInfo.cellIdentity
                    val cellSignalStrength = cellInfo.cellSignalStrength
                    mapOf(
                        "cellId" to cellIdentity.cid,
                        "lac" to cellIdentity.lac,
                        "mcc" to cellIdentity.mcc,
                        "mnc" to cellIdentity.mnc,
                        "signalStrength" to try { cellSignalStrength.dbm } catch (e: Exception) { null },
                        "networkType" to "GSM"
                    )
                }
                is CellInfoNr -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        try {
                            val cellIdentity = cellInfo.cellIdentity
                            val cellSignalStrength = cellInfo.cellSignalStrength
                            mapOf(
                                "cellId" to try { cellIdentity.nci } catch (e: Exception) { null },
                                "tac" to try { cellIdentity.tac } catch (e: Exception) { null },
                                "mcc" to try { 
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                        cellIdentity.mccString?.toIntOrNull() ?: cellIdentity.mcc
                                    } else {
                                        cellIdentity.mcc
                                    }
                                } catch (e: Exception) { null },
                                "mnc" to try { 
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                        cellIdentity.mncString?.toIntOrNull() ?: cellIdentity.mnc
                                    } else {
                                        cellIdentity.mnc
                                    }
                                } catch (e: Exception) { null },
                                "signalStrength" to try { cellSignalStrength.dbm } catch (e: Exception) { null },
                                "networkType" to "NR",
                                "pci" to try { cellIdentity.pci } catch (e: Exception) { null }
                            )
                        } catch (e: Exception) {
                            Log.e("MainActivity", "Error parsing CellInfoNr: ${e.message}")
                            null
                        }
                    } else {
                        null // CellInfoNr فقط در Android Q+ موجود است
                    }
                }
                else -> null
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error parsing cell info: ${e.message}")
            null
        }
    }
}
