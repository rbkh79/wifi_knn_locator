package com.example.wifi_knn_locator

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.CellInfo
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoWcdma
import android.telephony.CellInfoNr
import android.telephony.CellIdentityNr
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

        // بررسی مجوز Location (برای Android 10+ الزامی است)
        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED &&
            ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.w("MainActivity", "Location permission not granted for cell info")
            return null
        }

        val allCellInfo: List<CellInfo>? = try {
            telephonyManager.allCellInfo
        } catch (e: Exception) {
            Log.e("MainActivity", "Error getting cell info: ${e.message}")
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
                        "cellId" to cellIdentity.ci, // استفاده از ci (deprecated اما در همه نسخه‌ها موجود)
                        "tac" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            try { 
                                @Suppress("DEPRECATION")
                                cellIdentity.tac 
                            } catch (e: Exception) { 
                                null 
                            }
                        } else { 
                            null 
                        }),
                        "mcc" to cellIdentity.mcc, // استفاده از mcc (deprecated اما در همه نسخه‌ها موجود)
                        "mnc" to cellIdentity.mnc, // استفاده از mnc (deprecated اما در همه نسخه‌ها موجود)
                        "signalStrength" to try { 
                            cellSignalStrength.dbm 
                        } catch (e: Exception) { 
                            null 
                        },
                        "networkType" to "LTE",
                        "pci" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            try { 
                                @Suppress("DEPRECATION")
                                cellIdentity.pci 
                            } catch (e: Exception) { 
                                null 
                            }
                        } else { 
                            null 
                        })
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
                        "mcc" to cellIdentity.mcc,
                        "mnc" to cellIdentity.mnc,
                        "signalStrength" to try { 
                            cellSignalStrength.dbm 
                        } catch (e: Exception) { 
                            null 
                        },
                        "networkType" to "GSM"
                    )
                }
                is CellInfoNr -> {
                    // 5G NR support
                    val cellIdentity = try { cellInfo.cellIdentity as CellIdentityNr } catch (ex: Exception) { null }
                    val cellSignalStrength = cellInfo.cellSignalStrength
                    if (cellIdentity == null) return null
                    mapOf(
                        "cellId" to try { cellIdentity.nci } catch (e: Exception) { null },
                        "tac" to try { cellIdentity.tac } catch (e: Exception) { null },
                        // CellIdentityNr exposes MCC/MNC as strings (mccString/mncString)
                        "mcc" to try { cellIdentity.mccString?.toInt() } catch (e: Exception) { null },
                        "mnc" to try { cellIdentity.mncString?.toInt() } catch (e: Exception) { null },
                        "signalStrength" to try { cellSignalStrength.dbm } catch (e: Exception) { null },
                        "networkType" to "NR",
                        "pci" to try { cellIdentity.pci } catch (e: Exception) { null }
                    )
                }
                else -> {
                    null
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error parsing cell info: ${e.message}")
            null
        }
    }
}
