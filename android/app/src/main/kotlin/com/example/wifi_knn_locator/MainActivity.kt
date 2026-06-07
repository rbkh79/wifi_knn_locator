package com.example.wifi_knn_locator

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.CellInfo
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoWcdma
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "wifi_knn_locator/cell_info"
    private val TAG = "BTS_Service"

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

    @SuppressLint("MissingPermission")
    private fun getCellInfo(): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.JELLY_BEAN_MR1) {
            Log.w(TAG, "Android version too old: ${Build.VERSION.SDK_INT}")
            return null
        }

        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

        // در Android 12+، برای دسترسی به اطلاعات سلولی نیاز به ACCESS_FINE_LOCATION است
        val hasLocationPermission = ActivityCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasLocationPermission) {
            Log.w(TAG, "ACCESS_FINE_LOCATION permission not granted")
            return null
        }

        // دریافت اطلاعات دکل‌ها
        val allCellInfo: List<CellInfo>? = try {
            telephonyManager.allCellInfo
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception getting cell info: ${e.message}")
            null
        } catch (e: Exception) {
            Log.e(TAG, "Error getting cell info: ${e.message}", e)
            null
        }

        if (allCellInfo == null || allCellInfo.isEmpty()) {
            Log.w(TAG, "No cell info available")
            return null
        }

        Log.d(TAG, "Found ${allCellInfo.size} cell info entries")

        // پیدا کردن دکل متصل (اولین دکل که isRegistered = true)
        var servingCell: Map<String, Any?>? = null
        val neighboringCells = mutableListOf<Map<String, Any?>>()

        for (cellInfo in allCellInfo) {
            try {
                val cellData = parseCellInfo(cellInfo)
                if (cellData != null) {
                    if (cellInfo.isRegistered) {
                        servingCell = cellData
                        Log.d(TAG, "Serving cell found: ${cellData["networkType"]}")
                    } else {
                        neighboringCells.add(cellData)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error processing cell info: ${e.message}")
            }
        }

        Log.d(TAG, "Returning serving cell: ${servingCell != null}, neighbors: ${neighboringCells.size}")

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
                        "cellId" to cellIdentity.ci,
                        "tac" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) cellIdentity.tac else null),
                        "mcc" to cellIdentity.mccString,
                        "mnc" to cellIdentity.mncString,
                        "signalStrength" to cellSignalStrength.dbm,
                        "networkType" to "LTE",
                        "pci" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) cellIdentity.pci else null)
                    )
                }
                is CellInfoWcdma -> {
                    val cellIdentity = cellInfo.cellIdentity
                    val cellSignalStrength = cellInfo.cellSignalStrength
                    mapOf(
                        "cellId" to cellIdentity.cid,
                        "lac" to cellIdentity.lac,
                        "mcc" to cellIdentity.mccString,
                        "mnc" to cellIdentity.mncString,
                        "signalStrength" to try { 
                            cellSignalStrength.dbm 
                        } catch (e: Exception) { 
                            null 
                        },
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
                        "mcc" to cellIdentity.mccString,
                        "mnc" to cellIdentity.mncString,
                        "signalStrength" to try { 
                            cellSignalStrength.dbm 
                        } catch (e: Exception) { 
                            null 
                        },
                        "networkType" to "GSM"
                    )
                }
                else -> {
                    Log.d(TAG, "Unsupported cell info type: ${cellInfo.javaClass.simpleName}")
                    null
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing cell info: ${e.message}", e)
            null
        }
    }
}
