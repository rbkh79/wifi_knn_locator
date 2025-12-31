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

    private fun parseCellInfo(cellInfo: CellInfo): Map<String, Any?>? {
        return when (cellInfo) {
            is CellInfoLte -> {
                val cellIdentity = cellInfo.cellIdentity
                val cellSignalStrength = cellInfo.cellSignalStrength
                mapOf(
                    "cellId" to cellIdentity.cid,
                    "tac" to cellIdentity.tac,
                    "mcc" to cellIdentity.mccString?.toIntOrNull(),
                    "mnc" to cellIdentity.mncString?.toIntOrNull(),
                    "signalStrength" to cellSignalStrength.dbm,
                    "networkType" to "LTE",
                    "pci" to cellIdentity.pci
                )
            }
            is CellInfoWcdma -> {
                val cellIdentity = cellInfo.cellIdentity
                val cellSignalStrength = cellInfo.cellSignalStrength
                mapOf(
                    "cellId" to cellIdentity.cid,
                    "lac" to cellIdentity.lac,
                    "mcc" to cellIdentity.mccString?.toIntOrNull(),
                    "mnc" to cellIdentity.mncString?.toIntOrNull(),
                    "signalStrength" to cellSignalStrength.dbm,
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
                    "mcc" to cellIdentity.mccString?.toIntOrNull(),
                    "mnc" to cellIdentity.mncString?.toIntOrNull(),
                    "signalStrength" to cellSignalStrength.dbm,
                    "networkType" to "GSM"
                )
            }
            is CellInfoNr -> {
                val cellIdentity = cellInfo.cellIdentity
                val cellSignalStrength = cellInfo.cellSignalStrength
                mapOf(
                    "cellId" to cellIdentity.nci,
                    "tac" to cellIdentity.tac,
                    "mcc" to cellIdentity.mccString?.toIntOrNull(),
                    "mnc" to cellIdentity.mncString?.toIntOrNull(),
                    "signalStrength" to cellSignalStrength.dbm,
                    "networkType" to "NR",
                    "pci" to cellIdentity.pci
                )
            }
            else -> null
        }
    }
}
