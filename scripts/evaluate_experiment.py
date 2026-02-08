#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ارزیابی آزمایش مکان‌یابی: خطای میانگین، خطای ۹۰٪، و آزمون t جفتی.

ورودی: فایل CSV با ستون‌ها:
  lat_true, lon_true, lat_est, lon_est, method, point_id, sample_id
  method = 'wifi_only' | 'hybrid'

استفاده:
  python evaluate_experiment.py data/experiment_results.csv
  python evaluate_experiment.py data/experiment_results.csv --output-dir report/
"""

import argparse
import csv
import math
import sys
from pathlib import Path

# شعاع زمین تقریبی (متر)
EARTH_RADIUS_M = 6371000


def haversine_m(lat1_deg: float, lon1_deg: float, lat2_deg: float, lon2_deg: float) -> float:
    """فاصله بین دو نقطه به متر (Haversine)."""
    a = math.radians(lat1_deg)
    b = math.radians(lat2_deg)
    dlat = math.radians(lat2_deg - lat1_deg)
    dlon = math.radians(lon2_deg - lon1_deg)
    x = math.sin(dlat / 2) ** 2 + math.cos(a) * math.cos(b) * math.sin(dlon / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(min(1.0, x)))


def load_csv(path: str):
    """بارگذاری CSV و محاسبه خطا برای هر سطر."""
    rows = []  # type: list
    with open(path, newline="", encoding="utf-8") as f:
        r = csv.DictReader(f)
        for row in r:
            try:
                lat_t = float(row["lat_true"])
                lon_t = float(row["lon_true"])
                lat_e = float(row["lat_est"])
                lon_e = float(row["lon_est"])
                method = (row.get("method") or "").strip().lower()
                point_id = row.get("point_id", "")
                sample_id = row.get("sample_id", "")
                err = haversine_m(lat_t, lon_t, lat_e, lon_e)
                rows.append({
                    "error_m": err,
                    "method": method if method in ("wifi_only", "hybrid") else "unknown",
                    "point_id": point_id,
                    "sample_id": sample_id,
                })
            except (KeyError, ValueError):
                continue
    return rows


def stats(errors):
    """میانگین، انحراف معیار، و صدک ۹۰."""
    if not errors:
        return None
    n = len(errors)
    mean = sum(errors) / n
    var = sum((x - mean) ** 2 for x in errors) / n
    std = math.sqrt(var)
    sorted_e = sorted(errors)
    idx90 = max(0, int(0.9 * n) - 1) if n else 0
    p90 = sorted_e[idx90] if sorted_e else 0.0
    return {"n": n, "MAE": mean, "std": std, "P90": p90}


def paired_ttest(control_errors, treatment_errors):
    """
    t-test جفتی: تفاوت = control - treatment (مثبت یعنی hybrid بهتر است).
    فرض H1: میانگین تفاوت > 0 (خطای hybrid کمتر).
    """
    n = min(len(control_errors), len(treatment_errors))
    if n < 2:
        return None
    diffs = [control_errors[i] - treatment_errors[i] for i in range(n)]
    mean_d = sum(diffs) / n
    var_d = sum((x - mean_d) ** 2 for x in diffs) / (n - 1)
    std_d = math.sqrt(var_d)
    if std_d < 1e-10:
        return {"t": 0.0, "df": n - 1, "p_value": 0.5, "mean_diff": mean_d, "std_diff": 0.0}
    t_stat = mean_d / (std_d / math.sqrt(n))
    try:
        import scipy.stats as st
        p_val = 1 - st.t.cdf(t_stat, df=n - 1)
    except ImportError:
        # تقریب نرمال برای df >= 30
        p_val = 1 - 0.5 * (1 + math.erf(t_stat / math.sqrt(2)))
    p_val = max(0, min(1, p_val))
    return {"t": t_stat, "df": n - 1, "p_value": p_val, "mean_diff": mean_d, "std_diff": std_d}


def main():
    parser = argparse.ArgumentParser(description="ارزیابی آزمایش مکان‌یابی")
    parser.add_argument("csv_path", help="مسیر فایل CSV نتایج")
    parser.add_argument("--output-dir", "-o", default="", help="پوشه خروجی برای گزارش متنی")
    args = parser.parse_args()

    data = load_csv(args.csv_path)
    if not data:
        print("هیچ رکورد معتبری در CSV یافت نشد.")
        sys.exit(1)

    control = [r["error_m"] for r in data if r["method"] == "wifi_only"]
    hybrid = [r["error_m"] for r in data if r["method"] == "hybrid"]

    s_control = stats(control)
    s_hybrid = stats(hybrid)

    lines = []
    lines.append("=" * 60)
    lines.append("گزارش ارزیابی آزمایش مکان‌یابی (کنترل: فقط وای‌فای، آزمایش: تلفیقی)")
    lines.append("=" * 60)
    lines.append("")

    if s_control:
        lines.append("گروه کنترل (فقط وای‌فای):")
        lines.append(f"  تعداد نمونه: {s_control['n']}")
        lines.append(f"  خطای میانگین (MAE): {s_control['MAE']:.2f} m")
        lines.append(f"  انحراف معیار: {s_control['std']:.2f} m")
        lines.append(f"  خطای ۹۰٪ (P90): {s_control['P90']:.2f} m")
        lines.append("")
    if s_hybrid:
        lines.append("گروه آزمایش (تلفیق وای‌فای + BTS):")
        lines.append(f"  تعداد نمونه: {s_hybrid['n']}")
        lines.append(f"  خطای میانگین (MAE): {s_hybrid['MAE']:.2f} m")
        lines.append(f"  انحراف معیار: {s_hybrid['std']:.2f} m")
        lines.append(f"  خطای ۹۰٪ (P90): {s_hybrid['P90']:.2f} m")
        lines.append("")

    n_pair = min(len(control), len(hybrid))
    if n_pair >= 2:
        # برای t جفتی به جفت‌های هم‌تراز نیاز داریم (همان point_id و sample_id)
        # اگر در CSV جفت‌گیری نشده، به ترتیب جفت می‌کنیم
        c_sorted = sorted(control)[:n_pair]
        h_sorted = sorted(hybrid)[:n_pair]
        tt = paired_ttest(control[:n_pair], hybrid[:n_pair])
        if tt:
            lines.append("آزمون t جفتی (یک‌طرفه، H1: خطای تلفیقی کمتر):")
            lines.append(f"  میانگین تفاوت (کنترل - تلفیقی): {tt['mean_diff']:.2f} m")
            lines.append(f"  آماره t: {tt['t']:.3f}, درجه آزادی: {tt['df']}")
            lines.append(f"  p-value: {tt['p_value']:.4f}")
            if tt["p_value"] < 0.05:
                lines.append("  نتیجه: بهبود تلفیق از نظر آماری معنادار است (p < 0.05).")
            else:
                lines.append("  نتیجه: در این نمونه تفاوت معنادار نیست (p >= 0.05).")
    else:
        lines.append("برای آزمون t جفتی حداقل ۲ جفت نمونه لازم است.")

    text = "\n".join(lines)
    print(text)

    if args.output_dir:
        out_dir = Path(args.output_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        out_file = out_dir / "evaluation_report.txt"
        out_file.write_text(text, encoding="utf-8")
        print(f"\nگزارش در {out_file} ذخیره شد.")

    # پیشنهاد برای نمودار
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, ax = plt.subplots()
        if control:
            ax.boxplot([control, hybrid], labels=["فقط وای‌فای", "تلفیقی (وای‌فای+BTS)"])
        ax.set_ylabel("خطا (متر)")
        ax.set_title("توزیع خطای مکان‌یابی")
        plot_path = Path(args.output_dir or ".") / "error_boxplot.png"
        fig.savefig(plot_path, bbox_inches="tight")
        print(f"نمودار جعبه‌ای در {plot_path} ذخیره شد.")
    except Exception as e:
        print(f"برای رسم نمودار matplotlib نصب کنید: {e}")


if __name__ == "__main__":
    main()
