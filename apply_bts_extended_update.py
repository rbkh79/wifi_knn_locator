#!/usr/bin/env python3
"""Apply the extended Outdoor GPS+BTS research update.

Usage:
    python apply_bts_extended_update.py /path/to/wifi_knn_locator

No APK/AAB/build files are created. Only source files are changed.
Git already provides rollback, so no backup files are written into the repo.
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def patch_data_model(repo: Path) -> None:
    path = repo / "lib/data_model.dart"
    text = path.read_text(encoding="utf-8")
    if "final int? rsrp;" in text and "final int? timingAdvance;" in text:
        print("[skip] lib/data_model.dart already contains extended radio fields")
        return

    pattern = re.compile(
        r"/// اطلاعات یک دکل مخابراتی \(Cell Tower\)\s*"
        r"class CellTowerInfo \{.*?\n\}\s*\n\s*/// اسکن کامل دکل‌های مخابراتی",
        re.S,
    )
    replacement = r'''/// اطلاعات یک دکل مخابراتی (Cell Tower)
class CellTowerInfo {
  final int? cellId;
  final int? lac;
  final int? tac;
  final int? mcc;
  final int? mnc;
  final int? signalStrength;
  final String? networkType;
  final int? psc;
  final int? pci;
  final int? earfcn;

  // Extended LTE/NR research metrics. They may be null on some phones.
  final int? rsrp;
  final int? rsrq;
  final int? sinr;
  final int? cqi;
  final int? timingAdvance;
  final int? asuLevel;
  final int? level;
  final int? bandwidth;
  final int? band;
  final bool? registered;

  CellTowerInfo({
    this.cellId,
    this.lac,
    this.tac,
    this.mcc,
    this.mnc,
    this.signalStrength,
    this.networkType,
    this.psc,
    this.pci,
    this.earfcn,
    this.rsrp,
    this.rsrq,
    this.sinr,
    this.cqi,
    this.timingAdvance,
    this.asuLevel,
    this.level,
    this.bandwidth,
    this.band,
    this.registered,
  });

  Map<String, dynamic> toMap() {
    return {
      'cell_id': cellId,
      'lac': lac,
      'tac': tac,
      'mcc': mcc,
      'mnc': mnc,
      'signal_strength': signalStrength,
      'network_type': networkType,
      'psc': psc,
      'pci': pci,
      'earfcn': earfcn,
      'rsrp': rsrp,
      'rsrq': rsrq,
      'sinr': sinr,
      'cqi': cqi,
      'timing_advance': timingAdvance,
      'asu_level': asuLevel,
      'level': level,
      'bandwidth': bandwidth,
      'band': band,
      'registered': registered,
    };
  }

  factory CellTowerInfo.fromMap(Map<String, dynamic> map) {
    int? asInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    return CellTowerInfo(
      cellId: asInt(map['cell_id'] ?? map['cellId']),
      lac: asInt(map['lac']),
      tac: asInt(map['tac']),
      mcc: asInt(map['mcc']),
      mnc: asInt(map['mnc']),
      signalStrength: asInt(map['signal_strength'] ?? map['signalStrength']),
      networkType: (map['network_type'] ?? map['networkType']) as String?,
      psc: asInt(map['psc']),
      pci: asInt(map['pci']),
      earfcn: asInt(map['earfcn']),
      rsrp: asInt(map['rsrp']),
      rsrq: asInt(map['rsrq']),
      sinr: asInt(map['sinr']),
      cqi: asInt(map['cqi']),
      timingAdvance: asInt(map['timing_advance'] ?? map['timingAdvance']),
      asuLevel: asInt(map['asu_level'] ?? map['asuLevel']),
      level: asInt(map['level']),
      bandwidth: asInt(map['bandwidth']),
      band: asInt(map['band']),
      registered: map['registered'] as bool?,
    );
  }

  String get uniqueId {
    final parts = <String>[];
    if (mcc != null) parts.add('MCC:$mcc');
    if (mnc != null) parts.add('MNC:$mnc');
    if (lac != null) parts.add('LAC:$lac');
    if (tac != null) parts.add('TAC:$tac');
    if (cellId != null) parts.add('CID:$cellId');
    if (psc != null) parts.add('PSC:$psc');
    if (pci != null) parts.add('PCI:$pci');
    return parts.join('|');
  }

  @override
  String toString() => 'CellTowerInfo($uniqueId, signal: $signalStrength)';
}

/// اسکن کامل دکل‌های مخابراتی'''
    new_text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise RuntimeError(f"data_model.dart: CellTowerInfo match count={count}")
    path.write_text(new_text, encoding="utf-8")
    print("[patch] lib/data_model.dart")


def patch_cell_scanner(repo: Path) -> None:
    path = repo / "lib/cell_scanner.dart"
    text = path.read_text(encoding="utf-8")
    if "timingAdvance: _parseInt(map['timingAdvance'])" in text:
        print("[skip] lib/cell_scanner.dart already parses extended fields")
        return

    old = """        earfcn: _parseInt(map['earfcn']),
      );"""
    new = """        earfcn: _parseInt(map['earfcn']),
        rsrp: _parseInt(map['rsrp']),
        rsrq: _parseInt(map['rsrq']),
        sinr: _parseInt(map['sinr']),
        cqi: _parseInt(map['cqi']),
        timingAdvance: _parseInt(map['timingAdvance']),
        asuLevel: _parseInt(map['asuLevel']),
        level: _parseInt(map['level']),
        bandwidth: _parseInt(map['bandwidth']),
        band: _parseInt(map['band']),
        registered: map['registered'] as bool?,
      );"""
    text = replace_once(text, old, new, "cell_scanner extended fields")
    path.write_text(text, encoding="utf-8")
    print("[patch] lib/cell_scanner.dart")


def locate_main_activity(repo: Path) -> Path:
    candidates = list((repo / "android/app/src/main/kotlin").rglob("MainActivity.kt"))
    if len(candidates) != 1:
        raise FileNotFoundError(
            f"Could not uniquely locate MainActivity.kt; found {len(candidates)} files"
        )
    return candidates[0]


def patch_kotlin(repo: Path) -> None:
    path = locate_main_activity(repo)
    text = path.read_text(encoding="utf-8")
    if '"timingAdvance" to timingAdvance' in text and '"rsrp" to rsrp' in text:
        print(f"[skip] {path.relative_to(repo)} already emits extended LTE fields")
        return

    pattern = re.compile(
        r"\s*is CellInfoLte -> \{.*?\n\s*\}\n\s*is CellInfoWcdma -> \{",
        re.S,
    )
    replacement = r'''
                is CellInfoLte -> {
                    val id = cellInfo.cellIdentity
                    val signal = cellInfo.cellSignalStrength
                    val ci = id.ci
                    if (ci == Int.MAX_VALUE) {
                        Log.d(TAG, "LTE ci=MAX_VALUE, skip")
                        return null
                    }

                    fun valid(value: Int): Int? = value.takeIf { it != Int.MAX_VALUE }
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
                    } else null

                    val rsrp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        valid(signal.rsrp)
                    } else null
                    val rsrq = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        valid(signal.rsrq)
                    } else null
                    val sinr = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        valid(signal.rssnr)
                    } else null
                    val cqi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        valid(signal.cqi)
                    } else null
                    val timingAdvance = valid(signal.timingAdvance)
                    val bandwidth = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        valid(id.bandwidth)
                    } else null
                    val band = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        id.bands.firstOrNull()
                    } else null

                    Log.d(
                        TAG,
                        "LTE ci=$ci pci=$pci earfcn=$earfcn dbm=${signal.dbm} " +
                            "rsrp=$rsrp rsrq=$rsrq sinr=$sinr ta=$timingAdvance"
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
                is CellInfoWcdma -> {'''
    new_text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise RuntimeError(f"MainActivity.kt: LTE block match count={count}")
    path.write_text(new_text, encoding="utf-8")
    print(f"[patch] {path.relative_to(repo)}")


def patch_main(repo: Path) -> None:
    path = repo / "lib/main.dart"
    text = path.read_text(encoding="utf-8")

    if "OutdoorGpsBtsRecord? _latestGpsBtsRecord;" not in text:
        old = """  String _gpsBtsRecordingStatus = '';
  String _imuRecordingStatus = '';"""
        new = """  String _gpsBtsRecordingStatus = '';
  OutdoorGpsBtsRecord? _latestGpsBtsRecord;
  String _imuRecordingStatus = '';"""
        text = replace_once(text, old, new, "main latest BTS state")

    if "onLatestRecordChanged:" not in text:
        old = """        onRecordCountChanged: (count) {
          setState(() {
            _gpsBtsRecordCount = count;
          });
        },
        onStatusChanged: (status) {"""
        new = """        onRecordCountChanged: (count) {
          if (!mounted) return;
          setState(() {
            _gpsBtsRecordCount = count;
          });
        },
        onLatestRecordChanged: (record) {
          if (!mounted) return;
          setState(() {
            _latestGpsBtsRecord = record;
          });
        },
        onStatusChanged: (status) {"""
        text = replace_once(text, old, new, "main latest BTS callback")

    text = text.replace(
        "GPS + BTS Recording",
        "GPS + BTS Recording (Extended Radio Metrics)",
        1,
    )

    if "Neighbor cells: ${_latestGpsBtsRecord!.neighboringCells.length}" not in text:
        marker = """                      if (_gpsBtsRecordingStatus.isNotEmpty && !_isRecordingGpsBts) ...[
                        const SizedBox(height: 8),"""
        metrics = """                      if (_latestGpsBtsRecord != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Latest GPS + BTS sample',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            Chip(label: Text('GPS ±${_latestGpsBtsRecord!.accuracy?.toStringAsFixed(0) ?? '-'} m')),
                            Chip(label: Text('CellID: ${_latestGpsBtsRecord!.cellId ?? '-'}')),
                            Chip(label: Text('eNodeB: ${_latestGpsBtsRecord!.eNodeBId ?? '-'}')),
                            Chip(label: Text('Local cell: ${_latestGpsBtsRecord!.localCellId ?? '-'}')),
                            Chip(label: Text('PCI: ${_latestGpsBtsRecord!.pci ?? '-'}')),
                            Chip(label: Text('EARFCN: ${_latestGpsBtsRecord!.earfcn ?? '-'}')),
                            Chip(label: Text('Signal: ${_latestGpsBtsRecord!.signalStrength ?? '-'} dBm')),
                            Chip(label: Text('RSRP: ${_latestGpsBtsRecord!.rsrp ?? '-'} dBm')),
                            Chip(label: Text('RSRQ: ${_latestGpsBtsRecord!.rsrq ?? '-'} dB')),
                            Chip(label: Text('SINR: ${_latestGpsBtsRecord!.sinr ?? '-'} dB')),
                            Chip(label: Text('Timing advance: ${_latestGpsBtsRecord!.timingAdvance ?? '-'}')),
                            Chip(label: Text('Neighbor cells: ${_latestGpsBtsRecord!.neighboringCells.length}')),
                          ],
                        ),
                      ],
                      if (_gpsBtsRecordingStatus.isNotEmpty && !_isRecordingGpsBts) ...[
                        const SizedBox(height: 8),"""
        text = replace_once(text, marker, metrics, "main BTS metrics panel")

    text = text.replace(
        "Export GPS+BTS and IMU data collected during outdoor recording",
        "Export GPS+BTS data with PCI, EARFCN, RSRP, RSRQ, SINR, Timing Advance and neighbor cells; IMU export remains separate",
        1,
    )
    text = text.replace(
        "Export Outdoor GPS+BTS Dataset",
        "Export Outdoor GPS+BTS Extended Dataset",
        1,
    )

    path.write_text(text, encoding="utf-8")
    print("[patch] lib/main.dart")


def overwrite_service(repo: Path, package_root: Path) -> None:
    source = package_root / "replacements/lib/services/outdoor_gps_bts_service.dart"
    target = repo / "lib/services/outdoor_gps_bts_service.dart"
    if not target.exists():
        raise FileNotFoundError(target)
    shutil.copy2(source, target)
    print("[write] lib/services/outdoor_gps_bts_service.dart")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "repo",
        nargs="?",
        default=".",
        type=Path,
        help="Path to the wifi_knn_locator repository (default: current folder)",
    )
    args = parser.parse_args()
    repo = args.repo.resolve()

    if not (repo / "pubspec.yaml").exists():
        print(
            f"ERROR: {repo} is not the wifi_knn_locator Flutter repository root.",
            file=sys.stderr,
        )
        return 2

    package_root = Path(__file__).resolve().parent
    overwrite_service(repo, package_root)
    patch_data_model(repo)
    patch_cell_scanner(repo)
    patch_kotlin(repo)
    patch_main(repo)

    print("\nSource update completed.")
    print("GitHub Desktop should now show the modified source files.")
    print("No APK, AAB, build folder, or signing file was created.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
