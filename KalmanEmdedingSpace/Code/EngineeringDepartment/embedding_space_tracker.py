"""
Embedding Space Tracker — رویکرد صحیح برای پیش‌بینی مسیر indoor

به‌جای استفاده از decoder آموزش‌دیده روی Argoverse، این اسکریپت:
  1. local_encoder از HiVT را برای استخراج embedding هر مسیر استفاده می‌کند.
  2. مسیرهای تاییدشده (G001-G020, C001-C028) به‌عنوان کتابخانه مرجع ذخیره می‌شوند.
  3. برای هر query با مشاهده جزئی، embedding استخراج شده و نزدیک‌ترین مرجع‌ها پیدا می‌شوند.
  4. آینده از مسیرهای مرجع (داده‌های indoor واقعی) بازیابی می‌شود.
  5. آینده بازیابی‌شده به محورهای corridor snap می‌شود.

این رویکرد decoder آموزش‌دیده روی رانندگی شهری را دور می‌زند.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import sqlite3
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
import numpy as np

from route_proposal_workflow import DB_PATH, OUT_DIR, floor_color, load_corridors

ROOT_DIR = Path(__file__).resolve().parent
EMBED_DIR = OUT_DIR / "embedding_space_tracker"
EMBED_IMG_DIR = EMBED_DIR / "images"
EMBED_JSON = EMBED_DIR / "tracker_cases.json"
EMBED_MD = EMBED_DIR / "tracker_summary.md"
EMBED_REPORT_MD = EMBED_DIR / "EMBEDDING_TRACKER_DETAILED_REPORT_FA.md"
EMBED_CSV_DETAIL = EMBED_DIR / "probabilistic_errors_by_route.csv"
EMBED_CSV_SUMMARY = EMBED_DIR / "probabilistic_error_summary.csv"
EMBED_LIB_PATH = EMBED_DIR / "embedding_library.npz"

HIST_STEPS = 20
FUTURE_STEPS = 30
TOTAL_STEPS = HIST_STEPS + FUTURE_STEPS
RADIUS_M = 35.0
TOP_K = 6  # تعداد نزدیک‌ترین مرجع‌ها برای بازیابی
PROB_TAU = 0.05  # دمای softmax برای نگاشت فاصله -> احتمال


@dataclass
class Route:
    route_id: str
    category: str
    level_scope: list[str]
    points_xy: np.ndarray  # [50, 2]


@dataclass
class EmbeddingEntry:
    route_id: str
    embedding: np.ndarray   # [embed_dim]
    future_xy: np.ndarray   # [30, 2] absolute
    hist_last: np.ndarray   # [2] — آخرین نقطه تاریخ (برای مطلق‌سازی)
    level_scope: list[str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Embedding Space Tracker — indoor route prediction via retrieval")
    parser.add_argument("--db-path", type=Path, default=DB_PATH)
    parser.add_argument("--hivt-root", type=Path, default=Path("../HiVT"))
    parser.add_argument(
        "--ckpt-path",
        type=Path,
        default=Path("../HiVT/checkpoints/HiVT-64/checkpoints/epoch=63-step=411903.ckpt"),
    )
    parser.add_argument("--device", choices=["cpu", "cuda"], default="cpu")
    parser.add_argument("--obs-lengths", type=str, default="12,16,20")
    parser.add_argument("--target-pattern", type=str, default="G%,C%")
    parser.add_argument("--top-k", type=int, default=TOP_K)
    parser.add_argument("--prob-tau", type=float, default=PROB_TAU, help="Softmax temperature for probability levels")
    parser.add_argument("--rebuild-lib", action="store_true", help="پاکسازی و بازسازی کتابخانه embedding")
    return parser.parse_args()


def resolve_paths(base: Path, path: Path) -> Path:
    return (base / path).resolve() if not path.is_absolute() else path


def load_model(hivt_root: Path, ckpt_path: Path, device: str):
    if not hivt_root.exists():
        raise FileNotFoundError(f"HiVT root not found: {hivt_root}")
    if not (hivt_root / "models" / "hivt.py").exists():
        raise FileNotFoundError(f"Invalid HiVT root: {hivt_root}")
    if not ckpt_path.exists():
        raise FileNotFoundError(f"Checkpoint not found: {ckpt_path}")

    sys.path.insert(0, str(hivt_root))

    import pytorch_lightning as pl
    import torch
    from models.hivt import HiVT

    orig_torch_load = torch.load

    def torch_load_compat(*args, **kwargs):
        if "weights_only" not in kwargs:
            kwargs["weights_only"] = False
        return orig_torch_load(*args, **kwargs)

    torch.load = torch_load_compat
    pl.seed_everything(2022)

    model = HiVT.load_from_checkpoint(
        checkpoint_path=str(ckpt_path),
        parallel=False,
        map_location=torch.device(device),
    )
    model.eval()
    for p in model.parameters():
        p.requires_grad = False
    return model


def load_routes(db_path: Path, patterns: list[str]) -> list[Route]:
    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    where = " OR ".join(["route_id LIKE ?" for _ in patterns])
    query = f"""
        SELECT route_id, category, level_scope
        FROM route_proposals
        WHERE status = 'approved' AND ({where})
        ORDER BY route_id
    """
    cur.execute(query, patterns)
    rows = cur.fetchall()
    routes: list[Route] = []
    for row in rows:
        rid = str(row["route_id"])
        cur.execute(
            "SELECT point_idx, x_m, y_m FROM route_points WHERE route_id=? ORDER BY point_idx", (rid,)
        )
        pts_rows = cur.fetchall()
        if len(pts_rows) < TOTAL_STEPS:
            continue
        pts = np.array([[float(r["x_m"]), float(r["y_m"])] for r in pts_rows[:TOTAL_STEPS]], dtype=float)
        routes.append(Route(
            route_id=rid,
            category=str(row["category"]),
            level_scope=list(json.loads(row["level_scope"])),
            points_xy=pts,
        ))
    con.close()
    return routes


def build_lane_segments(corridors: list[Any]) -> dict[str, np.ndarray]:
    by_level: dict[str, list[np.ndarray]] = {}
    for c in corridors:
        p0 = c.center - c.axis * max(4.0, 0.45 * c.length_m)
        p1 = c.center + c.axis * max(4.0, 0.45 * c.length_m)
        by_level.setdefault(c.level, []).append(np.stack([p0, p1 - p0], axis=0))
    return {
        lv: np.asarray(segs, dtype=float) if segs else np.zeros((0, 2, 2), dtype=float)
        for lv, segs in by_level.items()
    }


def build_temporal_data(routes: list[Route], obs_len_target: int, lane_segments: np.ndarray, device: str):
    """ساخت TemporalData برای یک bundle از مسیرها."""
    import torch
    from utils import TemporalData

    positions = np.stack([r.points_xy for r in routes], axis=0)  # [N,50,2]
    n = positions.shape[0]

    x_hist = positions[:, :HIST_STEPS, :].copy()
    x_hist[:, 1:, :] = x_hist[:, 1:, :] - x_hist[:, :-1, :]
    x_hist[:, 0, :] = 0.0

    y_future = positions[:, HIST_STEPS:, :] - positions[:, HIST_STEPS - 1: HIST_STEPS, :]

    padding_mask = np.zeros((n, TOTAL_STEPS), dtype=bool)
    bos_mask = np.zeros((n, HIST_STEPS), dtype=bool)
    bos_mask[:, 0] = True

    obs_len_target = int(max(2, min(HIST_STEPS, obs_len_target)))
    cut = HIST_STEPS - obs_len_target
    if cut > 0:
        padding_mask[0, :cut] = True
        x_hist[0, :cut, :] = 0.0
        bos_mask[0, :] = False
        bos_mask[0, cut] = True

    rotate_angles = np.zeros((n,), dtype=float)
    for i in range(n):
        vf = 0 if i > 0 else (cut if cut > 0 else 0)
        a = max(vf + 1, HIST_STEPS - 2)
        b = max(vf + 2, HIST_STEPS - 1)
        dy = positions[i, b, 1] - positions[i, a, 1]
        dx = positions[i, b, 0] - positions[i, a, 0]
        rotate_angles[i] = math.atan2(float(dy), float(dx))

    if lane_segments.size == 0:
        lane_positions = np.zeros((0, 2), dtype=float)
        lane_vectors = np.zeros((0, 2), dtype=float)
    else:
        lane_positions = lane_segments[:, 0, :]
        lane_vectors = lane_segments[:, 1, :]

    actor_pos_t = positions[:, HIST_STEPS - 1, :]
    pairs, vecs = [], []
    for li, lp in enumerate(lane_positions):
        for ai, ap in enumerate(actor_pos_t):
            dvec = lp - ap
            if float(np.linalg.norm(dvec)) <= RADIUS_M:
                pairs.append([li, ai])
                vecs.append(dvec)

    if pairs:
        lane_actor_index = np.asarray(pairs, dtype=np.int64).T
        lane_actor_vectors = np.asarray(vecs, dtype=float)
    else:
        lane_actor_index = np.zeros((2, 0), dtype=np.int64)
        lane_actor_vectors = np.zeros((0, 2), dtype=float)

    rows, cols = [], []
    for i in range(n):
        for j in range(n):
            if i != j:
                rows.append(i)
                cols.append(j)
    edge_index = np.asarray([rows, cols], dtype=np.int64)

    data = TemporalData(
        x=torch.tensor(x_hist, dtype=torch.float),
        positions=torch.tensor(positions, dtype=torch.float),
        edge_index=torch.tensor(edge_index, dtype=torch.long),
        y=torch.tensor(y_future, dtype=torch.float),
        num_nodes=n,
        padding_mask=torch.tensor(padding_mask, dtype=torch.bool),
        bos_mask=torch.tensor(bos_mask, dtype=torch.bool),
        rotate_angles=torch.tensor(rotate_angles, dtype=torch.float),
        lane_vectors=torch.tensor(lane_vectors, dtype=torch.float),
        is_intersections=torch.zeros((lane_vectors.shape[0],), dtype=torch.uint8),
        turn_directions=torch.zeros((lane_vectors.shape[0],), dtype=torch.uint8),
        traffic_controls=torch.zeros((lane_vectors.shape[0],), dtype=torch.uint8),
        lane_actor_index=torch.tensor(lane_actor_index, dtype=torch.long),
        lane_actor_vectors=torch.tensor(lane_actor_vectors, dtype=torch.float),
        seq_id=0,
    )
    data["agent_index"] = torch.tensor([0], dtype=torch.long)
    data["av_index"] = torch.tensor([0], dtype=torch.long)
    return data.to(torch.device(device))


def extract_local_embedding(model, data) -> np.ndarray:
    """Extract local encoder embedding without running the decoder.

    Returns: [N, embed_dim] array — one vector per actor.
    
    Note: global_interactor returns [F, N, D] (modes x actors x dim),
    so we use only local_encoder output which is a clean [N, embed_dim].
    """
    import torch

    with torch.no_grad():
        if model.rotate:
            rotate_mat = torch.empty(data.num_nodes, 2, 2, device=model.device)
            sin_vals = torch.sin(data["rotate_angles"])
            cos_vals = torch.cos(data["rotate_angles"])
            rotate_mat[:, 0, 0] = cos_vals
            rotate_mat[:, 0, 1] = -sin_vals
            rotate_mat[:, 1, 0] = sin_vals
            rotate_mat[:, 1, 1] = cos_vals
            if data.y is not None:
                data.y = torch.bmm(data.y, rotate_mat)
            data["rotate_mat"] = rotate_mat
        else:
            data["rotate_mat"] = None

        local_embed = model.local_encoder(data=data)  # [N, embed_dim]
        # global_interactor returns [F, N, D] (modes x actors x dim)
        # we use local_embed only — shape is a clean [N, embed_dim]

    return local_embed.cpu().numpy()  # [N, embed_dim]


def build_library(
    routes: list[Route],
    model,
    lane_map: dict[str, np.ndarray],
    device: str,
) -> list[EmbeddingEntry]:
    """ساخت کتابخانه embedding برای همه مسیرهای مرجع با obs_len=20 (کامل)."""
    library: list[EmbeddingEntry] = []
    for i, target in enumerate(routes):
        context = [r for j, r in enumerate(routes) if j != i][:7]
        actor_bundle = [target] + context
        anchor_level = target.level_scope[0] if target.level_scope else "0"
        lane_segments = lane_map.get(anchor_level, np.zeros((0, 2, 2), dtype=float))

        data = build_temporal_data(actor_bundle, obs_len_target=HIST_STEPS, lane_segments=lane_segments, device=device)
        embeddings = extract_local_embedding(model, data)  # [N, embed_dim]
        target_embed = embeddings[0]  # embedding برای بازیگر هدف

        hist_last = target.points_xy[HIST_STEPS - 1]
        future_abs = target.points_xy[HIST_STEPS:]  # [30, 2] مطلق — مسیر indoor واقعی

        library.append(EmbeddingEntry(
            route_id=target.route_id,
            embedding=target_embed,
            future_xy=future_abs,
            hist_last=hist_last,
            level_scope=target.level_scope,
        ))
        print(f"  [lib] {target.route_id}  embed_norm={np.linalg.norm(target_embed):.3f}")

    return library


def retrieve_neighbors(
    query_embed: np.ndarray,
    library: list[EmbeddingEntry],
    exclude_id: str,
    top_k: int,
) -> list[tuple[float, EmbeddingEntry]]:
    """یافتن نزدیک‌ترین مرجع‌ها بر اساس فاصله L2 در فضای embedding."""
    results: list[tuple[float, EmbeddingEntry]] = []
    q_norm = query_embed / (np.linalg.norm(query_embed) + 1e-9)
    for entry in library:
        if entry.route_id == exclude_id:
            continue
        e_norm = entry.embedding / (np.linalg.norm(entry.embedding) + 1e-9)
        # فاصله کسینوسی: 1 - cosine_similarity
        cos_dist = float(1.0 - np.dot(q_norm, e_norm))
        results.append((cos_dist, entry))
    results.sort(key=lambda x: x[0])
    return results[:top_k]


def distances_to_probabilities(distances: list[float], tau: float) -> list[float]:
    if not distances:
        return []
    arr = np.asarray(distances, dtype=float)
    tau = max(1e-6, float(tau))
    scores = np.exp(-(arr - np.min(arr)) / tau)
    probs = scores / np.sum(scores)
    return [float(x) for x in probs]


def trajectory_error_metrics(pred_xy: np.ndarray, gt_xy: np.ndarray) -> tuple[float, float]:
    ade = float(np.mean(np.linalg.norm(pred_xy - gt_xy, axis=1)))
    fde = float(np.linalg.norm(pred_xy[-1] - gt_xy[-1]))
    return ade, fde


def write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_detailed_report(
    report_path: Path,
    routes_count: int,
    obs_lengths: list[int],
    top_k: int,
    prob_tau: float,
    cases: list[dict[str, Any]],
    rank_summary_rows: list[dict[str, Any]],
) -> None:
    exp_ade_snap = [float(c["expected_ade_snapped"]) for c in cases]
    exp_fde_snap = [float(c["expected_fde_snapped"]) for c in cases]
    top1_ade = [float(c["top1_ade_snapped"]) for c in cases]
    top1_fde = [float(c["top1_fde_snapped"]) for c in cases]

    best_cases = sorted(cases, key=lambda x: x["expected_fde_snapped"])[:10]
    worst_cases = sorted(cases, key=lambda x: x["expected_fde_snapped"], reverse=True)[:10]

    with open(report_path, "w", encoding="utf-8") as f:
        f.write("# گزارش جامع احتمالاتی Embedding Space Tracker (HiVT Encoder Only)\n\n")
        f.write("## 1) هدف و دامنه\n")
        f.write("این گزارش، نحوه استفاده دقیق از HiVT در حالت انتقال دانش (Transfer Learning) را مستند می‌کند؛\n")
        f.write("به‌صورت خاص فقط از encoder برای استخراج embedding استفاده می‌شود و decoder از چرخه پیش‌بینی حذف است.\n\n")

        f.write("## 2) معماری و جریان داده (Mermaid)\n\n")
        f.write("```mermaid\n")
        f.write("flowchart TD\n")
        f.write("    A[Approved indoor routes G and C] --> B[TemporalData builder]\n")
        f.write("    B --> C[HiVT local_encoder]\n")
        f.write("    C --> D[Embedding library]\n")
        f.write("\n")
        f.write("    Q[Query partial trajectory] --> QB[TemporalData builder]\n")
        f.write("    QB --> QC[HiVT local_encoder]\n")
        f.write("    QC --> E[Cosine distance to library]\n")
        f.write("    E --> F[Top-K neighbors]\n")
        f.write("    F --> G[Softmax on distance = probability levels]\n")
        f.write("    F --> H[Retrieve each neighbor future]\n")
        f.write("    H --> I[Corridor snap per probability level]\n")
        f.write("    G --> J[Weighted expected ADE and FDE]\n")
        f.write("    I --> J\n")
        f.write("    J --> K[CSV + JSON + Images + Full report]\n")
        f.write("```\n\n")

        f.write("## 3) تعریف دقیق متغیرها\n\n")
        f.write("| متغیر | شکل/نوع | توضیح |\n")
        f.write("|---|---|---|\n")
        f.write("| HIST_STEPS | 20 | طول تاریخچه مشاهده |\n")
        f.write("| FUTURE_STEPS | 30 | افق آینده برای ارزیابی |\n")
        f.write("| x | [N,20,2] | تاریخچه نسبی (delta position) بازیگران |\n")
        f.write("| positions | [N,50,2] | موقعیت مطلق کل بازه |\n")
        f.write("| y | [N,30,2] | آینده نسبی نسبت به گام 20 |\n")
        f.write("| padding_mask | [N,50] bool | ماسک گام‌های نامشهود |\n")
        f.write("| bos_mask | [N,20] bool | شروع دنباله معتبر |\n")
        f.write("| rotate_angles | [N] | زاویه چرخش هر بازیگر |\n")
        f.write("| lane_vectors | [L,2] | بردارهای محور corridor |\n")
        f.write("| lane_actor_index | [2,E] | یال lane→actor |\n")
        f.write("| lane_actor_vectors | [E,2] | بردار نسبی lane به actor |\n")
        f.write("| local_embed | [N,D] | خروجی encoder (D=64) |\n")
        f.write("| cos_dist_r | scalar | فاصله کسینوسی Query تا مرجع رتبه r |\n")
        f.write("| p_r | scalar | احتمال سطح r از softmax(-cos_dist/tau) |\n")
        f.write("| ADE_r | scalar (m) | میانگین خطای مکانی برای سطح r |\n")
        f.write("| FDE_r | scalar (m) | خطای نقطه نهایی برای سطح r |\n")
        f.write("| Expected ADE | scalar (m) | مجموع وزنی: Σ p_r * ADE_r |\n")
        f.write("| Expected FDE | scalar (m) | مجموع وزنی: Σ p_r * FDE_r |\n\n")

        f.write("## 4) فرمول‌های احتمال و خطا\n\n")
        f.write("برای رتبه r با فاصله کسینوسی d_r:\n\n")
        f.write("$$p_r = \\frac{\\exp(-d_r/\\tau)}{\\sum_j \\exp(-d_j/\\tau)}$$\n\n")
        f.write("$$ADE_r = \\frac{1}{T} \\sum_{t=1}^{T} ||\\hat{y}_{r,t} - y_t||_2$$\n\n")
        f.write("$$FDE_r = ||\\hat{y}_{r,T} - y_T||_2$$\n\n")
        f.write("$$Expected\\;ADE = \\sum_r p_r \\cdot ADE_r, \\quad Expected\\;FDE = \\sum_r p_r \\cdot FDE_r$$\n\n")

        f.write("## 5) پیکربندی اجرا\n\n")
        f.write(f"- تعداد مسیرهای تاییدشده: {routes_count}\n")
        f.write(f"- طول‌های مشاهده: {obs_lengths}\n")
        f.write(f"- تعداد سطوح احتمال (Top-K): {top_k}\n")
        f.write(f"- دمای Softmax (tau): {prob_tau:.4f}\n")
        f.write(f"- تعداد کل Case ها: {len(cases)}\n\n")

        f.write("## 6) خلاصه نتایج کل\n\n")
        f.write("| معیار | مقدار |\n")
        f.write("|---|---|\n")
        f.write(f"| میانگین Expected ADE (snapped) | {np.mean(exp_ade_snap):.2f} m |\n")
        f.write(f"| میانگین Expected FDE (snapped) | {np.mean(exp_fde_snap):.2f} m |\n")
        f.write(f"| میانگین Top-1 ADE (snapped) | {np.mean(top1_ade):.2f} m |\n")
        f.write(f"| میانگین Top-1 FDE (snapped) | {np.mean(top1_fde):.2f} m |\n\n")

        f.write("## 7) تحلیل خطا به‌ازای سطح احتمال\n\n")
        f.write("| Rank | mean probability | mean ADE raw | mean FDE raw | mean ADE snapped | mean FDE snapped |\n")
        f.write("|---|---|---|---|---|---|\n")
        for row in rank_summary_rows:
            f.write(
                f"| {row['rank']} | {row['mean_probability']:.4f} | {row['mean_ade_raw']:.2f} | "
                f"{row['mean_fde_raw']:.2f} | {row['mean_ade_snapped']:.2f} | {row['mean_fde_snapped']:.2f} |\n"
            )
        f.write("\n")

        f.write("## 8) 10 مورد بهترین Expected FDE\n\n")
        for c in best_cases:
            f.write(
                f"- {c['route_id']} | obs={c['obs_len']} | best_neighbor={c['best_neighbor_id']} | "
                f"Expected FDE snapped={c['expected_fde_snapped']:.2f} m\n"
            )
        f.write("\n")

        f.write("## 9) 10 مورد بدترین Expected FDE\n\n")
        for c in worst_cases:
            f.write(
                f"- {c['route_id']} | obs={c['obs_len']} | best_neighbor={c['best_neighbor_id']} | "
                f"Expected FDE snapped={c['expected_fde_snapped']:.2f} m\n"
            )
        f.write("\n")

        f.write("## 10) بحث و بررسی\n\n")
        f.write("- استفاده از encoder HiVT معتبر است چون نمایش embedding غنی از الگوهای حرکت ایجاد می‌کند.\n")
        f.write("- عدم استفاده از decoder آموخته‌شده روی Argoverse، خطای domain shift را به‌طور مستقیم کاهش می‌دهد.\n")
        f.write("- تعریف probability level بر پایه فاصله embedding، معیار شفاف برای تحلیل uncertainty فراهم می‌کند.\n")
        f.write("- snap به corridor قید هندسی indoor را enforce می‌کند، ولی خطای معنایی مسیر (انتخاب همسایه نامرتبط) را کامل حل نمی‌کند.\n")
        f.write("- برای بهبود بیشتر: metric learning/fine-tune سبک روی embedding با داده indoor پیشنهاد می‌شود.\n\n")

        f.write("## 11) فایل‌های خروجی\n\n")
        f.write(f"- JSON Case-level: {EMBED_JSON.name}\n")
        f.write(f"- CSV خطای هر مسیر و هر سطح احتمال: {EMBED_CSV_DETAIL.name}\n")
        f.write(f"- CSV خلاصه رتبه‌های احتمال: {EMBED_CSV_SUMMARY.name}\n")
        f.write(f"- تصاویر کیس‌ها: {EMBED_IMG_DIR.name}/\n")


def snap_to_corridors(points_xy: np.ndarray, corridors: list[Any]) -> np.ndarray:
    """بستن هر نقطه پیش‌بینی به نزدیک‌ترین محور corridor."""
    if not corridors or points_xy.size == 0:
        return points_xy.copy()

    segs: list[tuple[np.ndarray, np.ndarray]] = []
    for c in corridors:
        half = max(4.0, 0.48 * c.length_m)
        a = c.center - c.axis * half
        b = c.center + c.axis * half
        segs.append((a, b))

    snapped = np.empty_like(points_xy)
    for pi, p in enumerate(points_xy):
        best_proj = p
        best_dist = float("inf")
        for a, b in segs:
            ab = b - a
            denom = float(np.dot(ab, ab))
            if denom < 1e-9:
                proj = a
            else:
                t = float(np.dot(p - a, ab) / denom)
                t = max(0.0, min(1.0, t))
                proj = a + t * ab
            d = float(np.linalg.norm(p - proj))
            if d < best_dist:
                best_dist = d
                best_proj = proj
        snapped[pi] = best_proj
    return snapped


def corridor_distance_metric(points_xy: np.ndarray, corridors: list[Any]) -> float:
    if points_xy.size == 0 or not corridors:
        return 0.0
    segs = []
    for c in corridors:
        half = max(4.0, 0.48 * c.length_m)
        a = c.center - c.axis * half
        b = c.center + c.axis * half
        segs.append((a, b))
    dvals: list[float] = []
    for p in points_xy:
        best = float("inf")
        for a, b in segs:
            ab = b - a
            denom = float(np.dot(ab, ab))
            t = max(0.0, min(1.0, float(np.dot(p - a, ab) / denom) if denom > 1e-9 else 0.0))
            proj = a + t * ab
            best = min(best, float(np.linalg.norm(p - proj)))
        dvals.append(best)
    return float(np.mean(dvals))


def draw_case_image(
    corridors: list[Any],
    target: Route,
    obs_len: int,
    neighbors: list[tuple[float, EmbeddingEntry]],
    probs: list[float],
    snapped_best: np.ndarray,
    out_path: Path,
) -> None:
    fig, ax = plt.subplots(figsize=(11, 8), dpi=170)

    levels = set(target.level_scope)
    for c in corridors:
        color = floor_color(c.level)
        active = c.level in levels
        ax.fill(c.ring_xy[:, 0], c.ring_xy[:, 1], color=color, alpha=0.18 if active else 0.04)
        ax.plot(c.ring_xy[:, 0], c.ring_xy[:, 1], color=color, linewidth=0.8 if active else 0.35,
                alpha=0.6 if active else 0.2)

    hist = target.points_xy[:HIST_STEPS]
    gt_future = target.points_xy[HIST_STEPS:]
    visible = hist[HIST_STEPS - obs_len:]

    ax.plot(visible[:, 0], visible[:, 1], color="#0f172a", linewidth=2.8, zorder=5,
            label=f"Observed ({obs_len} pts)")
    ax.plot(gt_future[:, 0], gt_future[:, 1], color="#f97316", linewidth=2.2, zorder=4,
            label="GT future (indoor)")

    # نمایش آینده‌های بازیابی‌شده از کتابخانه با سطوح احتمال
    palette = ["#16a34a", "#0ea5e9", "#a3e635", "#f59e0b", "#ef4444", "#8b5cf6"]
    for rank, (cos_dist, entry) in enumerate(neighbors):
        retrieved_future = entry.future_xy
        p = probs[rank] if rank < len(probs) else 0.0
        clr = palette[rank % len(palette)]
        if rank == 0:
            ax.plot(
                retrieved_future[:, 0],
                retrieved_future[:, 1],
                color=clr,
                linewidth=2.6,
                zorder=6,
                linestyle="--",
                label=f"Rank1 {entry.route_id} | p={p:.2%} | d={cos_dist:.3f}",
            )
        else:
            ax.plot(
                retrieved_future[:, 0],
                retrieved_future[:, 1],
                color=clr,
                linewidth=max(0.9, 1.8 - rank * 0.15),
                alpha=max(0.35, 0.85 - rank * 0.08),
                zorder=3,
                linestyle="--",
                label=f"Rank{rank+1} {entry.route_id} | p={p:.2%}",
            )

    # آینده snap‌شده به corridor
    ax.plot(snapped_best[:, 0], snapped_best[:, 1], color="#7c3aed", linewidth=2.0,
            zorder=7, label="Best neighbor → corridor-snapped")

    ax.scatter([visible[-1, 0]], [visible[-1, 1]], color="#dc2626", s=50, zorder=8,
               label="Prediction start")

    best_dist = neighbors[0][0] if neighbors else 0.0
    best_id = neighbors[0][1].route_id if neighbors else "?"
    best_p = probs[0] if probs else 0.0
    ax.set_title(
        f"{target.route_id} | obs={obs_len} | best_neighbor={best_id} | p1={best_p:.2%} | cos_d={best_dist:.4f}"
    )
    ax.set_xlabel("x (m)")
    ax.set_ylabel("y (m)")
    ax.grid(alpha=0.2)
    ax.legend(frameon=False, loc="best", fontsize=8)
    ax.set_aspect("equal", adjustable="box")
    fig.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)


def build_contact_sheet(paths: list[Path], out_path: Path) -> None:
    if not paths:
        return
    cols = 4
    rows_count = int(math.ceil(len(paths) / cols))
    fig, axes = plt.subplots(rows_count, cols, figsize=(4.3 * cols, 3.2 * rows_count), dpi=130)
    axes_arr = np.array(axes).reshape(-1)
    for ax, path in zip(axes_arr, paths):
        img = plt.imread(path)
        ax.imshow(img)
        ax.set_title(path.stem[:50], fontsize=7)
        ax.axis("off")
    for ax in axes_arr[len(paths):]:
        ax.axis("off")
    fig.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)


def main() -> None:
    args = parse_args()

    base = ROOT_DIR.parent
    hivt_root = resolve_paths(base, args.hivt_root)
    ckpt_path = resolve_paths(base, args.ckpt_path)
    patterns = [x.strip() for x in args.target_pattern.split(",") if x.strip()]
    obs_lengths = [int(x.strip()) for x in args.obs_lengths.split(",") if x.strip()]

    print("-" * 60)
    print("Embedding Space Tracker")
    print("-" * 60)

    routes = load_routes(args.db_path, patterns)
    if not routes:
        raise RuntimeError("No approved routes found.")
    print(f"بارگذاری {len(routes)} مسیر تاییدشده")

    corridors, _, _ = load_corridors()
    lane_map = build_lane_segments(corridors)

    model = load_model(hivt_root, ckpt_path, args.device)
    print(f"مدل HiVT بارگذاری شد (فقط encoder استفاده می‌شود)")

    EMBED_DIR.mkdir(parents=True, exist_ok=True)
    EMBED_IMG_DIR.mkdir(parents=True, exist_ok=True)

    # ─── ساخت یا بارگذاری کتابخانه embedding ───
    if EMBED_LIB_PATH.exists() and not args.rebuild_lib:
        print(f"بارگذاری کتابخانه embedding از {EMBED_LIB_PATH}")
        lib_data = np.load(EMBED_LIB_PATH, allow_pickle=True)
        library: list[EmbeddingEntry] = []
        for i in range(len(lib_data["route_ids"])):
            library.append(EmbeddingEntry(
                route_id=str(lib_data["route_ids"][i]),
                embedding=lib_data["embeddings"][i],
                future_xy=lib_data["futures"][i],
                hist_last=lib_data["hist_lasts"][i],
                level_scope=list(lib_data["level_scopes"][i]),
            ))
        print(f"  {len(library)} مسیر مرجع بارگذاری شد")
    else:
        print("ساخت کتابخانه embedding (این ممکن است چند دقیقه طول بکشد)...")
        library = build_library(routes, model, lane_map, args.device)
        # ذخیره کتابخانه
        np.savez(
            EMBED_LIB_PATH,
            route_ids=np.array([e.route_id for e in library]),
            embeddings=np.stack([e.embedding for e in library]),
            futures=np.stack([e.future_xy for e in library]),
            hist_lasts=np.stack([e.hist_last for e in library]),
            level_scopes=np.array([e.level_scope for e in library], dtype=object),
        )
        print(f"کتابخانه ذخیره شد: {EMBED_LIB_PATH}")

    # ─── پردازش هر query ───
    import torch

    cases: list[dict[str, Any]] = []
    error_rows: list[dict[str, Any]] = []
    image_paths: list[Path] = []

    for target in routes:
        context = [r for r in routes if r.route_id != target.route_id][:7]
        actor_bundle = [target] + context
        anchor_level = target.level_scope[0] if target.level_scope else "0"
        lane_segments = lane_map.get(anchor_level, np.zeros((0, 2, 2), dtype=float))

        for obs_len in obs_lengths:
            # ─ استخراج embedding برای مشاهده جزئی ─
            data = build_temporal_data(actor_bundle, obs_len_target=obs_len,
                                       lane_segments=lane_segments, device=args.device)
            embeddings = extract_local_embedding(model, data)  # [N, embed_dim]
            query_embed = embeddings[0]  # فقط embedding بازیگر هدف

            # ─ بازیابی نزدیک‌ترین مرجع‌ها ─
            neighbors = retrieve_neighbors(query_embed, library, exclude_id=target.route_id, top_k=args.top_k)

            # ─ محاسبه سطوح احتمال بر اساس فاصله embedding ─
            distances = [float(d) for d, _ in neighbors]
            probs = distances_to_probabilities(distances, args.prob_tau)

            # ─ محاسبه معیارها برای هر سطح احتمال ─
            gt_future = target.points_xy[HIST_STEPS:]
            corr_dist_gt = corridor_distance_metric(gt_future, corridors)

            probability_levels: list[dict[str, Any]] = []
            expected_ade_raw = 0.0
            expected_fde_raw = 0.0
            expected_ade_snapped = 0.0
            expected_fde_snapped = 0.0

            for rank, ((cos_dist, entry), p) in enumerate(zip(neighbors, probs), start=1):
                pred_raw = entry.future_xy
                pred_snapped = snap_to_corridors(pred_raw, corridors)

                ade_raw, fde_raw = trajectory_error_metrics(pred_raw, gt_future)
                ade_snap, fde_snap = trajectory_error_metrics(pred_snapped, gt_future)
                corr_dist_raw = corridor_distance_metric(pred_raw, corridors)
                corr_dist_snap = corridor_distance_metric(pred_snapped, corridors)

                expected_ade_raw += p * ade_raw
                expected_fde_raw += p * fde_raw
                expected_ade_snapped += p * ade_snap
                expected_fde_snapped += p * fde_snap

                probability_levels.append(
                    {
                        "rank": rank,
                        "route_id": entry.route_id,
                        "probability": round(float(p), 6),
                        "cos_dist": round(float(cos_dist), 6),
                        "ade_raw": round(float(ade_raw), 4),
                        "fde_raw": round(float(fde_raw), 4),
                        "ade_snapped": round(float(ade_snap), 4),
                        "fde_snapped": round(float(fde_snap), 4),
                        "corridor_dist_raw": round(float(corr_dist_raw), 4),
                        "corridor_dist_snapped": round(float(corr_dist_snap), 4),
                    }
                )

                error_rows.append(
                    {
                        "route_id": target.route_id,
                        "obs_len": obs_len,
                        "rank": rank,
                        "neighbor_route_id": entry.route_id,
                        "probability": round(float(p), 6),
                        "cos_dist": round(float(cos_dist), 6),
                        "ade_raw_m": round(float(ade_raw), 4),
                        "fde_raw_m": round(float(fde_raw), 4),
                        "ade_snapped_m": round(float(ade_snap), 4),
                        "fde_snapped_m": round(float(fde_snap), 4),
                        "corridor_dist_raw_m": round(float(corr_dist_raw), 4),
                        "corridor_dist_snapped_m": round(float(corr_dist_snap), 4),
                        "is_top1": 1 if rank == 1 else 0,
                    }
                )

            top1 = probability_levels[0]
            best_future_raw = neighbors[0][1].future_xy
            snapped_best = snap_to_corridors(best_future_raw, corridors)

            # ─ رسم تصویر ─
            img_name = f"{target.route_id}__obs{obs_len}__nb{neighbors[0][1].route_id}.png"
            img_path = EMBED_IMG_DIR / img_name
            draw_case_image(
                corridors=corridors,
                target=target,
                obs_len=obs_len,
                neighbors=neighbors,
                probs=probs,
                snapped_best=snapped_best,
                out_path=img_path,
            )
            image_paths.append(img_path)

            case: dict[str, Any] = {
                "route_id": target.route_id,
                "obs_len": obs_len,
                "best_neighbor_id": top1["route_id"],
                "best_probability": top1["probability"],
                "best_cos_distance": top1["cos_dist"],
                "top1_ade_raw": top1["ade_raw"],
                "top1_fde_raw": top1["fde_raw"],
                "top1_ade_snapped": top1["ade_snapped"],
                "top1_fde_snapped": top1["fde_snapped"],
                "expected_ade_raw": round(float(expected_ade_raw), 4),
                "expected_fde_raw": round(float(expected_fde_raw), 4),
                "expected_ade_snapped": round(float(expected_ade_snapped), 4),
                "expected_fde_snapped": round(float(expected_fde_snapped), 4),
                "corridor_dist_gt": round(corr_dist_gt, 4),
                "probability_levels": probability_levels,
            }
            cases.append(case)
            print(
                f"  {target.route_id} obs={obs_len:2d} → nb={neighbors[0][1].route_id}"
                f"  p1={top1['probability']:.3f}"
                f"  E[ADE]_snap={expected_ade_snapped:.2f}m"
                f"  E[FDE]_snap={expected_fde_snapped:.2f}m"
            )

    # ─── ذخیره JSON ───
    EMBED_JSON.write_text(json.dumps(cases, ensure_ascii=False, indent=2), encoding="utf-8")

    # ─── تولید contact sheet به‌ازای هر obs_len ───
    for obs_len in obs_lengths:
        obs_imgs = [p for p in image_paths if f"__obs{obs_len}__" in p.name]
        if obs_imgs:
            build_contact_sheet(obs_imgs, EMBED_DIR / f"contact_obs{obs_len}.png")

    # ─── CSV تفصیلی خطاها (هر مسیر × هر obs × هر rank احتمال) ───
    detail_fields = [
        "route_id",
        "obs_len",
        "rank",
        "neighbor_route_id",
        "probability",
        "cos_dist",
        "ade_raw_m",
        "fde_raw_m",
        "ade_snapped_m",
        "fde_snapped_m",
        "corridor_dist_raw_m",
        "corridor_dist_snapped_m",
        "is_top1",
    ]
    write_csv(EMBED_CSV_DETAIL, error_rows, detail_fields)

    # ─── CSV خلاصه به‌ازای rank احتمال ───
    rank_summary_rows: list[dict[str, Any]] = []
    if error_rows:
        max_rank = int(max(r["rank"] for r in error_rows))
        for rank in range(1, max_rank + 1):
            subset = [r for r in error_rows if int(r["rank"]) == rank]
            if not subset:
                continue
            rank_summary_rows.append(
                {
                    "rank": rank,
                    "count": len(subset),
                    "mean_probability": round(float(np.mean([float(r["probability"]) for r in subset])), 6),
                    "mean_ade_raw": round(float(np.mean([float(r["ade_raw_m"]) for r in subset])), 4),
                    "mean_fde_raw": round(float(np.mean([float(r["fde_raw_m"]) for r in subset])), 4),
                    "mean_ade_snapped": round(float(np.mean([float(r["ade_snapped_m"]) for r in subset])), 4),
                    "mean_fde_snapped": round(float(np.mean([float(r["fde_snapped_m"]) for r in subset])), 4),
                }
            )
    rank_summary_fields = [
        "rank",
        "count",
        "mean_probability",
        "mean_ade_raw",
        "mean_fde_raw",
        "mean_ade_snapped",
        "mean_fde_snapped",
    ]
    write_csv(EMBED_CSV_SUMMARY, rank_summary_rows, rank_summary_fields)

    # ─── تولید Markdown summary ───
    exp_ade_raw = [float(c["expected_ade_raw"]) for c in cases]
    exp_fde_raw = [float(c["expected_fde_raw"]) for c in cases]
    exp_ade_snap = [float(c["expected_ade_snapped"]) for c in cases]
    exp_fde_snap = [float(c["expected_fde_snapped"]) for c in cases]
    top1_ade_snap = [float(c["top1_ade_snapped"]) for c in cases]
    top1_fde_snap = [float(c["top1_fde_snapped"]) for c in cases]

    with open(EMBED_MD, "w", encoding="utf-8") as f:
        f.write("# Embedding Space Tracker — خلاصه نتایج\n\n")
        f.write("## رویکرد\n")
        f.write("به‌جای decoder آموزش‌دیده روی Argoverse، از encoder HiVT برای استخراج embedding استفاده شد.\n")
        f.write("احتمال مسیرها از softmax روی فاصله کسینوسی همسایه‌های Top-K ساخته شد.\n")
        f.write("آینده از مسیرهای مرجع indoor (G+C) بازیابی شد — نه از decoder.\n\n")
        f.write("## معیارها (میانگین کل)\n\n")
        f.write("| معیار | مقدار |\n|---|---|\n")
        f.write(f"| mean Expected ADE (raw) | {np.mean(exp_ade_raw):.2f} m |\n")
        f.write(f"| mean Expected FDE (raw) | {np.mean(exp_fde_raw):.2f} m |\n")
        f.write(f"| mean Expected ADE (snapped) | {np.mean(exp_ade_snap):.2f} m |\n")
        f.write(f"| mean Expected FDE (snapped) | {np.mean(exp_fde_snap):.2f} m |\n")
        f.write(f"| mean Top-1 ADE (snapped) | {np.mean(top1_ade_snap):.2f} m |\n")
        f.write(f"| mean Top-1 FDE (snapped) | {np.mean(top1_fde_snap):.2f} m |\n\n")
        f.write("## مقایسه با روش قبلی (decoder مستقیم)\n\n")
        f.write("| روش | mean ADE | mean FDE |\n|---|---|---|\n")
        f.write(f"| decoder مستقیم HiVT (Argoverse) | 59.57 m | 97.68 m |\n")
        f.write(f"| embedding retrieval احتمالاتی (Expected raw) | {np.mean(exp_ade_raw):.2f} m | {np.mean(exp_fde_raw):.2f} m |\n")
        f.write(f"| embedding retrieval احتمالاتی + snap | {np.mean(exp_ade_snap):.2f} m | {np.mean(exp_fde_snap):.2f} m |\n\n")
        f.write(f"## تعداد موارد\n{len(cases)} مورد ({len(routes)} مسیر × {len(obs_lengths)} طول مشاهده)\n")

    write_detailed_report(
        report_path=EMBED_REPORT_MD,
        routes_count=len(routes),
        obs_lengths=obs_lengths,
        top_k=args.top_k,
        prob_tau=args.prob_tau,
        cases=cases,
        rank_summary_rows=rank_summary_rows,
    )

    print("\n" + "-" * 60)
    print(f"Results:")
    print(f"  JSON: {EMBED_JSON}")
    print(f"  MD:   {EMBED_MD}")
    print(f"  REPORT: {EMBED_REPORT_MD}")
    print(f"  CSV(detail): {EMBED_CSV_DETAIL}")
    print(f"  CSV(summary): {EMBED_CSV_SUMMARY}")
    print(f"  Images: {EMBED_IMG_DIR}")
    print(f"\nmean Expected ADE (raw):     {np.mean(exp_ade_raw):.2f} m")
    print(f"mean Expected ADE (snapped): {np.mean(exp_ade_snap):.2f} m")
    print(f"mean Expected FDE (snapped): {np.mean(exp_fde_snap):.2f} m")
    print("-" * 60)


if __name__ == "__main__":
    main()
