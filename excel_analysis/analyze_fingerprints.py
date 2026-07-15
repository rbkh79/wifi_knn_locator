# -*- coding: utf-8 -*-
"""
تحلیل کامل دیتاست fingerprints.xlsx برای مکان‌یابی WiFi Fingerprinting
=====================================================================

این اسکریپت تمام تحلیل‌های لازم برای پایان‌نامه را روی داده‌های RSSI انجام می‌دهد:
  1. آمار کلی دیتاست
  2. تعداد Access Pointهای یکتا (BSSID)
  3. تعداد SSIDهای یکتا
  4. تعداد دفعات مشاهده هر BSSID
  5. میانگین / انحراف معیار / کمینه / بیشینه RSSI هر BSSID
  6. باند فرکانسی هر AP (2.4GHz یا 5GHz)
  7. حذف APهای کم‌مشاهده (آستانه قابل تنظیم)
  8. تعداد AP در هر طبقه
  9. تعداد AP قابل مشاهده در هر Reference Point
 10. هیستوگرام و توزیع RSSI
 11. همبستگی RSSI با فاصله از Reference Point
 12. درصد APهایی که در بیش از ۸۰٪ نقاط دیده شده‌اند

خروجی‌ها:
  - excel_analysis/outputs/tables/*.xlsx   (جدول‌ها)
  - excel_analysis/outputs/figures/*.png   (نمودارها)

نحوه اجرا (از داخل پوشه excel_analysis):
    python analyze_fingerprints.py
"""

from __future__ import annotations

import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # backend بدون پنجره (مناسب برای اسکریپت‌های خودکار)
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns

# ---------------------------------------------------------------------------
# تنظیمات اولیه
# ---------------------------------------------------------------------------
sns.set_theme(style="whitegrid", font_scale=1.1)

# تلاش برای فعال‌سازی فونت فارسی (در صورت نصب بودن). اگر نباشد، نمودارها
# همچنان با فونت لاتین تولید می‌شوند ولی متن‌ها انگلیسی خواهند بود.
try:
    import matplotlib.font_manager as fm

    for candidate in ("B Nazanin", "Vazirmatn", "Tahoma", "B Mitra"):
        if any(candidate.lower() in f.name.lower() for f in fm.fontManager.ttflist):
            plt.rcParams["font.family"] = candidate
            PERSIAN_OK = True
            break
    else:
        PERSIAN_OK = False
except Exception:
    PERSIAN_OK = False

# چون ممکن است فونت فارسی در دسترس نباشد، برچسب‌های نمودارها را انگلیسی
# می‌نویسیم تا خروجی همیشه تمیز و قابل‌خواندن باشد.

# مسیرها
BASE_DIR = Path(__file__).resolve().parent
DATA_PATH = BASE_DIR / "data" / "fingerprints.xlsx"
TABLES_DIR = BASE_DIR / "outputs" / "tables"
FIGURES_DIR = BASE_DIR / "outputs" / "figures"
TABLES_DIR.mkdir(parents=True, exist_ok=True)
FIGURES_DIR.mkdir(parents=True, exist_ok=True)

# آستانه‌های قابل تنظیم
MIN_OBSERVATIONS = 10          # حداقل دفعات مشاهده برای "مناسب بودن" یک AP
COVERAGE_THRESHOLD = 0.80      # آستانه پوشش برای APهای همه‌گیر (۸۰٪)


# ---------------------------------------------------------------------------
# توابع کمکی
# ---------------------------------------------------------------------------
def freq_to_band(freq: int) -> str:
    """تبدیل فرکانس (MHz) به نام باند."""
    if freq < 4000:
        return "2.4 GHz"
    return "5 GHz"


def haversine_m(lat1, lon1, lat2, lon2):
    """فاصله دو نقطه جغرافیایی به متر (حدودی)."""
    R = 6371000.0
    p1 = np.radians(lat1)
    p2 = np.radians(lat2)
    dp = np.radians(lat2 - lat1)
    dl = np.radians(lon2 - lon1)
    a = np.sin(dp / 2) ** 2 + np.cos(p1) * np.cos(p2) * np.sin(dl / 2) ** 2
    return 2 * R * np.arcsin(np.sqrt(a))


def save_table(df: pd.DataFrame, name: str) -> Path:
    """ذخیره یک DataFrame در فایل اکسل (با Sheet جداگانه برای هر جدول)."""
    path = TABLES_DIR / f"{name}.xlsx"
    df.to_excel(path, index=False)
    return path


def save_fig(name: str, dpi: int = 150) -> Path:
    """ذخیره شکل فعلی matplotlib و بستن آن."""
    path = FIGURES_DIR / f"{name}.png"
    plt.tight_layout()
    plt.savefig(path, dpi=dpi, bbox_inches="tight")
    plt.close()
    return path


def print_section(title: str) -> None:
    line = "=" * 70
    print(f"\n{line}\n{title}\n{line}")


# ---------------------------------------------------------------------------
# بارگذاری و پاک‌سازی داده
# ---------------------------------------------------------------------------
def load_data() -> pd.DataFrame:
    print_section("0) بارگذاری و پاک‌سازی داده‌ها")
    df = pd.read_excel(DATA_PATH, sheet_name="in")
    print(f"تعداد ردیف خام: {len(df):,}")
    print(f"تعداد ستون‌ها: {df.shape[1]}")

    # نرمال‌سازی نوع Building (یک مقدار '1' ناقص وجود داشت)
    df["Building"] = df["Building"].astype(str).str.strip()
    # فقط ردیف‌هایی که داده WiFi معتبر دارند نگه می‌داریم
    df = df.dropna(subset=["WifiBSSID", "WifiRSSI"]).copy()
    df["WifiBSSID"] = df["WifiBSSID"].str.lower().str.strip()
    df["WifiRSSI"] = pd.to_numeric(df["WifiRSSI"], errors="coerce")
    df["WifiFrequency"] = pd.to_numeric(df["WifiFrequency"], errors="coerce")
    df = df.dropna(subset=["WifiRSSI", "WifiFrequency"])

    # ساخت ستون باند
    df["Band"] = df["WifiFrequency"].apply(freq_to_band)

    print(f"تعداد ردیف پس از پاک‌سازی: {len(df):,}")
    return df


# ---------------------------------------------------------------------------
# تحلیل‌ها
# ---------------------------------------------------------------------------
def overview(df: pd.DataFrame) -> None:
    print_section("1) آمار کلی دیتاست")
    summary = {
        "Total rows": len(df),
        "Unique Reference Points (RP)": df["ReferencePointID"].nunique(),
        "Unique Samples (SampleID)": df["SampleID"].nunique(),
        "Unique Buildings": df["Building"].nunique(),
        "Floors": ", ".join(map(str, sorted(df["Floor"].unique()))),
        "Unique BSSIDs (APs)": df["WifiBSSID"].nunique(),
        "Unique SSIDs": df["WifiSSID"].nunique(),
        "RSSI min (dBm)": int(df["WifiRSSI"].min()),
        "RSSI max (dBm)": int(df["WifiRSSI"].max()),
        "RSSI mean (dBm)": round(float(df["WifiRSSI"].mean()), 2),
        "RSSI std (dBm)": round(float(df["WifiRSSI"].std()), 2),
        "2.4 GHz rows": int((df["Band"] == "2.4 GHz").sum()),
        "5 GHz rows": int((df["Band"] == "5 GHz").sum()),
    }
    summary_df = pd.DataFrame(list(summary.items()), columns=["Metric", "Value"])
    save_table(summary_df, "01_overview")
    for k, v in summary.items():
        print(f"  {k:35s}: {v}")


def ap_analysis(df: pd.DataFrame) -> pd.DataFrame:
    print_section("2) تحلیل هر Access Point (BSSID)")
    agg = (
        df.groupby("WifiBSSID")
        .agg(
            SSID=("WifiSSID", lambda s: s.dropna().mode().iloc[0] if not s.dropna().mode().empty else None),
            Observations=("WifiRSSI", "count"),
            Mean_RSSI_dBm=("WifiRSSI", "mean"),
            Std_RSSI=("WifiRSSI", "std"),
            Min_RSSI_dBm=("WifiRSSI", "min"),
            Max_RSSI_dBm=("WifiRSSI", "max"),
            Frequency_MHz=("WifiFrequency", lambda s: int(s.mode().iloc[0])),
            Seen_in_RPs=("ReferencePointID", "nunique"),
        )
        .reset_index()
    )
    agg["Band"] = agg["Frequency_MHz"].apply(freq_to_band)
    agg["Std_RSSI"] = agg["Std_RSSI"].round(2)
    agg["Mean_RSSI_dBm"] = agg["Mean_RSSI_dBm"].round(2)
    # تعداد کل RP برای محاسبه پوشش
    total_rp = df["ReferencePointID"].nunique()
    agg["Coverage_pct"] = (agg["Seen_in_RPs"] / total_rp * 100).round(1)
    # ستون مناسب بودن
    agg["Suitable"] = np.where(agg["Observations"] >= MIN_OBSERVATIONS, "YES", "NO")
    agg = agg.sort_values("Observations", ascending=False).reset_index(drop=True)
    save_table(agg, "02_access_points")
    print(agg.to_string(index=False))
    print(f"\n→ فایل: outputs/tables/02_access_points.xlsx")
    print(f"تعداد AP مناسب (>= {MIN_OBSERVATIONS} مشاهده): {(agg['Suitable'] == 'YES').sum()}")
    print(f"تعداد AP نامناسب: {(agg['Suitable'] == 'NO').sum()}")
    return agg


def ap_summary_by_suitable(agg: pd.DataFrame) -> None:
    print_section("3) خلاصه مناسب/نامناسب بودن APها")
    summary = agg.groupby("Suitable").agg(
        Count=("WifiBSSID", "count"),
        Total_Observations=("Observations", "sum"),
        Mean_RSSI=("Mean_RSSI_dBm", "mean"),
    ).reset_index()
    save_table(summary, "03_ap_suitable_summary")
    print(summary.to_string(index=False))


def ssid_analysis(df: pd.DataFrame) -> None:
    print_section("4) تحلیل SSIDها")
    ssid = (
        df.groupby("WifiSSID")
        .agg(
            Observations=("WifiRSSI", "count"),
            Unique_BSSIDs=("WifiBSSID", "nunique"),
            Mean_RSSI_dBm=("WifiRSSI", "mean"),
            Seen_in_RPs=("ReferencePointID", "nunique"),
        )
        .reset_index()
        .sort_values("Observations", ascending=False)
    )
    ssid["Mean_RSSI_dBm"] = ssid["Mean_RSSI_dBm"].round(2)
    save_table(ssid, "04_ssids")
    print(ssid.to_string(index=False))


def aps_per_floor(df: pd.DataFrame) -> None:
    print_section("5) تعداد Access Point در هر طبقه")
    per_floor = (
        df.groupby("Floor")
        .agg(
            Unique_BSSIDs=("WifiBSSID", "nunique"),
            Unique_SSIDs=("WifiSSID", "nunique"),
            Observations=("WifiRSSI", "count"),
            Unique_RPs=("ReferencePointID", "nunique"),
        )
        .reset_index()
    )
    save_table(per_floor, "05_aps_per_floor")
    print(per_floor.to_string(index=False))

    # نمودار
    plt.figure(figsize=(8, 5))
    sns.barplot(data=per_floor, x="Floor", y="Unique_BSSIDs", color="#4C72B0")
    plt.title("Number of unique APs (BSSIDs) per floor")
    plt.xlabel("Floor")
    plt.ylabel("Unique BSSIDs")
    save_fig("05_aps_per_floor")


def aps_per_rp(df: pd.DataFrame) -> None:
    print_section("6) تعداد AP قابل مشاهده در هر Reference Point")
    per_rp = (
        df.groupby("ReferencePointID")
        .agg(
            Unique_BSSIDs=("WifiBSSID", "nunique"),
            Observations=("WifiRSSI", "count"),
            Mean_RSSI_dBm=("WifiRSSI", "mean"),
        )
        .reset_index()
        .sort_values("Unique_BSSIDs", ascending=False)
    )
    per_rp["Mean_RSSI_dBm"] = per_rp["Mean_RSSI_dBm"].round(2)
    save_table(per_rp, "06_aps_per_rp")
    print(per_rp.head(20).to_string(index=False))
    print(f"... (مجموع {len(per_rp)} RP)")

    # نمودار توزیع
    plt.figure(figsize=(9, 5))
    sns.histplot(per_rp["Unique_BSSIDs"], bins=15, color="#55A868")
    plt.title("Distribution of unique APs visible per Reference Point")
    plt.xlabel("Unique BSSIDs per RP")
    plt.ylabel("Number of RPs")
    save_fig("06_aps_per_rp_distribution")


def rssi_distribution(df: pd.DataFrame) -> None:
    print_section("7) توزیع و هیستوگرام RSSI")
    desc = df["WifiRSSI"].describe().round(2).to_frame().reset_index()
    desc.columns = ["Statistic", "Value"]
    save_table(desc, "07_rssi_distribution")
    print(desc.to_string(index=False))

    # هیستوگرام کلی
    plt.figure(figsize=(9, 5))
    sns.histplot(df["WifiRSSI"], bins=30, kde=True, color="#C44E52")
    plt.title("Overall RSSI distribution")
    plt.xlabel("RSSI (dBm)")
    plt.ylabel("Count")
    save_fig("07_rssi_histogram")

    # هیستوگرام به تفکیک باند
    plt.figure(figsize=(9, 5))
    sns.histplot(data=df, x="WifiRSSI", hue="Band", bins=30, kde=True, multiple="stack")
    plt.title("RSSI distribution by frequency band")
    plt.xlabel("RSSI (dBm)")
    plt.ylabel("Count")
    save_fig("07_rssi_histogram_by_band")


def rssi_per_ap_boxplot(agg: pd.DataFrame, df: pd.DataFrame) -> None:
    print_section("8) باکس‌پلات RSSI برای پایدارترین APها")
    # ۱۲ AP برتر از نظر تعداد مشاهده
    top = agg.head(12)["WifiBSSID"].tolist()
    sub = df[df["WifiBSSID"].isin(top)].copy()
    order = agg.head(12)["WifiBSSID"].tolist()
    plt.figure(figsize=(12, 6))
    sns.boxplot(data=sub, x="WifiBSSID", y="WifiRSSI", order=order, color="#8172B3")
    plt.title("RSSI box-plot for the 12 most observed APs (higher = more stable)")
    plt.xlabel("BSSID (AP)")
    plt.ylabel("RSSI (dBm)")
    plt.xticks(rotation=45, ha="right")
    save_fig("08_rssi_boxplot_top_aps")


def coverage_analysis(df: pd.DataFrame) -> None:
    print_section("9) پوشش APها (در چند درصد RPها دیده شده‌اند)")
    total_rp = df["ReferencePointID"].nunique()
    cov = (
        df.groupby("WifiBSSID")["ReferencePointID"]
        .nunique()
        .sort_values(ascending=False)
    )
    coverage_pct = (cov / total_rp * 100).round(1)
    print(f"تعداد کل RPها: {total_rp}")
    print(f"APهایی که در بیش از {int(COVERAGE_THRESHOLD*100)}٪ RPها دیده شده‌اند:")
    widespread = coverage_pct[coverage_pct >= COVERAGE_THRESHOLD * 100]
    print(f"  → {len(widespread)} AP از {len(coverage_pct)} AP")
    cov_df = coverage_pct.reset_index()
    cov_df.columns = ["WifiBSSID", "Coverage_pct"]
    cov_df["Widespread(>=80%)"] = np.where(cov_df["Coverage_pct"] >= COVERAGE_THRESHOLD * 100, "YES", "NO")
    save_table(cov_df, "09_ap_coverage")

    # نمودار
    plt.figure(figsize=(10, 5))
    sns.histplot(coverage_pct, bins=20, color="#937860")
    plt.axvline(COVERAGE_THRESHOLD * 100, color="red", linestyle="--", label=f"{int(COVERAGE_THRESHOLD*100)}% threshold")
    plt.title("AP coverage distribution (% of Reference Points where AP is visible)")
    plt.xlabel("Coverage (% of RPs)")
    plt.ylabel("Number of APs")
    plt.legend()
    save_fig("09_ap_coverage_distribution")


def distance_correlation(df: pd.DataFrame) -> None:
    print_section("10) همبستگی RSSI با فاصله از Reference Point")
    # برای هر BSSID، فاصله هر مشاهده تا مرکز (میانگین GPS) همان RP را حساب می‌کنیم
    rp_center = df.groupby("ReferencePointID")[["GPS_Latitude", "GPS_Longitude"]].mean()
    rows = []
    for rp, grp in df.groupby("ReferencePointID"):
        if rp not in rp_center.index:
            continue
        clat, clon = rp_center.loc[rp]
        d = haversine_m(grp["GPS_Latitude"].values, grp["GPS_Longitude"].values, clat, clon)
        tmp = grp[["WifiRSSI"]].copy()
        tmp["Distance_m"] = d
        rows.append(tmp)
    if rows:
        dist_df = pd.concat(rows)
        corr = dist_df["WifiRSSI"].corr(dist_df["Distance_m"])
        print(f"همبستگی پیرسون بین RSSI و فاصله تا مرکز RP: {corr:.3f}")
        save_table(dist_df.reset_index(drop=True), "10_rssi_vs_distance")

        plt.figure(figsize=(8, 6))
        # برای جلوگیری از اورفلو، نمونه‌گیری اگر زیاد بود
        sample = dist_df.sample(min(len(dist_df), 1500), random_state=42)
        sns.scatterplot(data=sample, x="Distance_m", y="WifiRSSI", alpha=0.4, color="#DD8452")
        plt.title(f"RSSI vs distance to RP center (Pearson r = {corr:.3f})")
        plt.xlabel("Distance to RP center (m)")
        plt.ylabel("RSSI (dBm)")
        save_fig("10_rssi_vs_distance")
    else:
        print("داده GPS کافی برای این تحلیل وجود ندارد.")


def building_floor_heatmap(df: pd.DataFrame) -> None:
    print_section("11) تعداد AP یکتا به ازای ساختمان × طبقه")
    pivot = df.pivot_table(
        index="Building",
        columns="Floor",
        values="WifiBSSID",
        aggfunc="nunique",
        fill_value=0,
    )
    save_table(pivot.reset_index(), "11_building_floor_aps")
    print(pivot.to_string())

    plt.figure(figsize=(8, 5))
    sns.heatmap(pivot, annot=True, fmt="d", cmap="YlGnBu")
    plt.title("Unique APs per Building x Floor")
    plt.xlabel("Floor")
    plt.ylabel("Building")
    save_fig("11_building_floor_heatmap")


def recommended_subset(agg: pd.DataFrame) -> None:
    print_section("12) مجموعه پیشنهادی APها برای Fingerprinting")
    # معیارها: حداقل مشاهده + پوشش قابل‌قبول + پایداری (Std بالا = ناپایدار)
    rec = agg[
        (agg["Observations"] >= MIN_OBSERVATIONS)
    ].copy()
    rec["Stability_note"] = np.where(rec["Std_RSSI"] <= 6, "stable", "noisy")
    rec = rec.sort_values(["Coverage_pct", "Observations"], ascending=[False, False])
    save_table(rec, "12_recommended_aps")
    print(f"تعداد AP پیشنهادی: {len(rec)} از {len(agg)} AP")
    print(rec[["WifiBSSID", "SSID", "Observations", "Mean_RSSI_dBm", "Std_RSSI", "Band", "Coverage_pct", "Stability_note"]].head(20).to_string(index=False))


# ---------------------------------------------------------------------------
# اجرای اصلی
# ---------------------------------------------------------------------------
def main() -> None:
    print(f"فونت فارسی فعال: {PERSIAN_OK}")
    df = load_data()
    overview(df)
    agg = ap_analysis(df)
    ap_summary_by_suitable(agg)
    ssid_analysis(df)
    aps_per_floor(df)
    aps_per_rp(df)
    rssi_distribution(df)
    rssi_per_ap_boxplot(agg, df)
    coverage_analysis(df)
    distance_correlation(df)
    building_floor_heatmap(df)
    recommended_subset(agg)

    print_section("پایان - خروجی‌ها")
    print(f"جداول  : {TABLES_DIR}")
    print(f"نمودارها: {FIGURES_DIR}")


if __name__ == "__main__":
    main()
