from __future__ import annotations

import argparse
import json
import math
import sqlite3
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
import numpy as np

from route_proposal_workflow import DB_PATH, OUT_DIR, floor_color, load_corridors, numeric_level

ROOT_DIR = Path(__file__).resolve().parent
PRED_DIR = OUT_DIR / "predictive_embedding_demo"
PRED_IMG_DIR = PRED_DIR / "images"
PRED_JSON = PRED_DIR / "predictive_cases.json"
PRED_MD = PRED_DIR / "predictive_summary.md"
PRED_CONTACT = PRED_DIR / "predictive_contact_sheet.png"

HIST_STEPS = 20
FUTURE_STEPS = 30
TOTAL_STEPS = HIST_STEPS + FUTURE_STEPS
RADIUS_M = 35.0


@dataclass
class Route:
    route_id: str
    category: str
    level_scope: list[str]
    points_xy: np.ndarray


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="HiVT predictive embedding demo on approved Engineering routes")
    parser.add_argument("--db-path", type=Path, default=DB_PATH)
    parser.add_argument("--hivt-root", type=Path, default=Path("../HiVT"))
    parser.add_argument(
        "--ckpt-path",
        type=Path,
        default=Path("../HiVT/checkpoints/HiVT-64/checkpoints/epoch=63-step=411903.ckpt"),
    )
    parser.add_argument("--device", choices=["cpu", "cuda"], default="cpu")
    parser.add_argument("--max-context", type=int, default=7, help="Max additional actors besides target")
    parser.add_argument("--obs-lengths", type=str, default="12,16,20", help="Comma-separated observed history lengths")
    parser.add_argument("--target-pattern", type=str, default="G%,C%", help="SQL LIKE patterns for target route ids")
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
            """
            SELECT point_idx, x_m, y_m
            FROM route_points
            WHERE route_id = ?
            ORDER BY point_idx
            """,
            (rid,),
        )
        points = cur.fetchall()
        if len(points) < TOTAL_STEPS:
            continue
        pts = np.array([[float(r["x_m"]), float(r["y_m"])] for r in points[:TOTAL_STEPS]], dtype=float)
        routes.append(
            Route(
                route_id=rid,
                category=str(row["category"]),
                level_scope=list(json.loads(row["level_scope"])),
                points_xy=pts,
            )
        )

    con.close()
    return routes


def build_lane_segments(corridors: list[Any]) -> dict[str, np.ndarray]:
    out: dict[str, np.ndarray] = {}
    by_level: dict[str, list[np.ndarray]] = {}

    for c in corridors:
        p0 = c.center - c.axis * max(4.0, 0.45 * c.length_m)
        p1 = c.center + c.axis * max(4.0, 0.45 * c.length_m)
        by_level.setdefault(c.level, []).append(np.stack([p0, p1 - p0], axis=0))

    for level, segs in by_level.items():
        out[level] = np.asarray(segs, dtype=float) if segs else np.zeros((0, 2, 2), dtype=float)

    return out


def choose_context(target: Route, pool: list[Route], max_context: int) -> list[Route]:
    candidates = [r for r in pool if r.route_id != target.route_id]

    # Prefer routes sharing first level, then nearest in anchor point.
    shared = [r for r in candidates if r.level_scope and target.level_scope and r.level_scope[0] == target.level_scope[0]]
    others = [r for r in candidates if r not in shared]

    t_anchor = target.points_xy[HIST_STEPS - 1]

    def sort_key(r: Route) -> float:
        return float(np.linalg.norm(r.points_xy[HIST_STEPS - 1] - t_anchor))

    shared = sorted(shared, key=sort_key)
    others = sorted(others, key=sort_key)

    selected = shared[:max_context]
    if len(selected) < max_context:
        selected.extend(others[: max_context - len(selected)])

    return selected


def build_temporal_data(
    routes: list[Route],
    obs_len_target: int,
    lane_segments: np.ndarray,
    device: str,
):
    import torch
    from utils import TemporalData

    positions = np.stack([r.points_xy for r in routes], axis=0)  # [N,50,2]
    n = positions.shape[0]

    x_hist = positions[:, :HIST_STEPS, :].copy()
    x_hist[:, 1:, :] = x_hist[:, 1:, :] - x_hist[:, :-1, :]
    x_hist[:, 0, :] = 0.0

    y_future = positions[:, HIST_STEPS:, :] - positions[:, HIST_STEPS - 1 : HIST_STEPS, :]

    padding_mask = np.zeros((n, TOTAL_STEPS), dtype=bool)
    bos_mask = np.zeros((n, HIST_STEPS), dtype=bool)
    bos_mask[:, 0] = True

    # Simulate partial input for target actor only.
    obs_len_target = int(max(2, min(HIST_STEPS, obs_len_target)))
    cut = HIST_STEPS - obs_len_target
    if cut > 0:
        padding_mask[0, :cut] = True
        x_hist[0, :cut, :] = 0.0
        bos_mask[0, :] = False
        bos_mask[0, cut] = True

    rotate_angles = np.zeros((n,), dtype=float)
    for i in range(n):
        valid_from = 0
        if i == 0 and cut > 0:
            valid_from = cut
        a = max(valid_from + 1, HIST_STEPS - 2)
        b = max(valid_from + 2, HIST_STEPS - 1)
        dy = positions[i, b, 1] - positions[i, a, 1]
        dx = positions[i, b, 0] - positions[i, a, 0]
        rotate_angles[i] = math.atan2(float(dy), float(dx))

    if lane_segments.size == 0:
        lane_vectors = np.zeros((0, 2), dtype=float)
        lane_positions = np.zeros((0, 2), dtype=float)
    else:
        lane_positions = lane_segments[:, 0, :]
        lane_vectors = lane_segments[:, 1, :]

    actor_pos_t = positions[:, HIST_STEPS - 1, :]
    pairs = []
    vecs = []
    for lane_idx, lane_pos in enumerate(lane_positions):
        for actor_idx, actor_pos in enumerate(actor_pos_t):
            dvec = lane_pos - actor_pos
            if float(np.linalg.norm(dvec)) <= RADIUS_M:
                pairs.append([lane_idx, actor_idx])
                vecs.append(dvec)

    if pairs:
        lane_actor_index = np.asarray(pairs, dtype=np.int64).T
        lane_actor_vectors = np.asarray(vecs, dtype=float)
    else:
        lane_actor_index = np.zeros((2, 0), dtype=np.int64)
        lane_actor_vectors = np.zeros((0, 2), dtype=float)

    rows = []
    cols = []
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
    data = data.to(torch.device(device))
    return data


def draw_case_image(
    corridors: list[Any],
    level_scope: list[str],
    target: Route,
    obs_len: int,
    pred_modes_abs: np.ndarray,
    best_mode: int,
    pi: np.ndarray,
    out_path: Path,
) -> None:
    fig, ax = plt.subplots(figsize=(10.5, 7.5), dpi=170)

    levels = set(level_scope)
    for c in corridors:
        color = floor_color(c.level)
        active = c.level in levels
        ax.fill(c.ring_xy[:, 0], c.ring_xy[:, 1], color=color, alpha=0.18 if active else 0.04)
        ax.plot(c.ring_xy[:, 0], c.ring_xy[:, 1], color=color, linewidth=0.8 if active else 0.35, alpha=0.6 if active else 0.2)

    hist = target.points_xy[:HIST_STEPS]
    gt_future = target.points_xy[HIST_STEPS:]
    visible = hist[HIST_STEPS - obs_len :]

    ax.plot(visible[:, 0], visible[:, 1], color="#0f172a", linewidth=2.8, label=f"Observed ({obs_len} points)")
    ax.plot(gt_future[:, 0], gt_future[:, 1], color="#f97316", linewidth=2.1, label="GT future")

    other_labeled = False
    for m in range(pred_modes_abs.shape[0]):
        line = pred_modes_abs[m]
        if m == best_mode:
            ax.plot(line[:, 0], line[:, 1], color="#16a34a", linewidth=2.8, label="Best HiVT mode")
        else:
            label = "Other HiVT modes" if not other_labeled else None
            ax.plot(line[:, 0], line[:, 1], color="#93c5fd", linewidth=1.1, alpha=0.8, label=label)
            other_labeled = True

    ax.scatter([visible[-1, 0]], [visible[-1, 1]], color="#dc2626", s=45, label="Prediction start")

    ax.set_title(f"{target.route_id} | obs={obs_len} | best={best_mode} | pi={pi[best_mode]:.3f}")
    ax.set_xlabel("x (m)")
    ax.set_ylabel("y (m)")
    ax.grid(alpha=0.2)
    ax.legend(frameon=False, loc="best")
    ax.set_aspect("equal", adjustable="box")
    fig.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)


def build_contact_sheet(paths: list[Path], out_path: Path) -> None:
    if not paths:
        return
    cols = 4
    rows = int(math.ceil(len(paths) / cols))
    fig, axes = plt.subplots(rows, cols, figsize=(4.3 * cols, 3.2 * rows), dpi=150)
    axes_arr = np.array(axes).reshape(-1)

    for ax, path in zip(axes_arr, paths):
        img = plt.imread(path)
        ax.imshow(img)
        ax.set_title(path.stem[:50], fontsize=8)
        ax.axis("off")

    for ax in axes_arr[len(paths) :]:
        ax.axis("off")

    fig.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)


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
            if denom < 1e-9:
                proj = a
            else:
                t = float(np.dot(p - a, ab) / denom)
                t = max(0.0, min(1.0, t))
                proj = a + t * ab
            d = float(np.linalg.norm(p - proj))
            if d < best:
                best = d
        dvals.append(best)
    return float(np.mean(dvals))


def main() -> None:
    args = parse_args()

    base = ROOT_DIR.parent
    hivt_root = resolve_paths(base, args.hivt_root)
    ckpt_path = resolve_paths(base, args.ckpt_path)

    patterns = [x.strip() for x in args.target_pattern.split(",") if x.strip()]
    obs_lengths = [int(x.strip()) for x in args.obs_lengths.split(",") if x.strip()]

    routes = load_routes(args.db_path, patterns)
    if not routes:
        raise RuntimeError("No approved target routes found for provided patterns.")

    corridors, _, _ = load_corridors()
    lane_map = build_lane_segments(corridors)

    model = load_model(hivt_root, ckpt_path, args.device)

    import torch

    PRED_DIR.mkdir(parents=True, exist_ok=True)
    PRED_IMG_DIR.mkdir(parents=True, exist_ok=True)

    cases: list[dict[str, Any]] = []
    image_paths: list[Path] = []

    for target in routes:
        context = choose_context(target, routes, args.max_context)
        actor_bundle = [target] + context
        anchor_level = target.level_scope[0] if target.level_scope else "0"
        lane_segments = lane_map.get(anchor_level, np.zeros((0, 2, 2), dtype=float))

        for obs_len in obs_lengths:
            data = build_temporal_data(actor_bundle, obs_len, lane_segments, args.device)
            with torch.no_grad():
                y_hat, pi = model(data)

            y_hat_np = y_hat.detach().cpu().numpy()  # [M, N, 30, D]
            pi_np = pi.detach().cpu().numpy()  # [N, M]

            target_pi = pi_np[0]
            best_mode = int(np.argmax(target_pi))
            hist_last = target.points_xy[HIST_STEPS - 1]

            pred_modes_abs = y_hat_np[:, 0, :, :2] + hist_last[None, None, :]
            gt_future = target.points_xy[HIST_STEPS:]

            best_abs = pred_modes_abs[best_mode]
            ade = float(np.mean(np.linalg.norm(best_abs - gt_future, axis=1)))
            fde = float(np.linalg.norm(best_abs[-1] - gt_future[-1]))
            best_corridor_mean_dist = corridor_distance_metric(best_abs, corridors)
            gt_corridor_mean_dist = corridor_distance_metric(gt_future, corridors)

            img_name = f"{target.route_id}__obs{obs_len}__best{best_mode}.png"
            img_path = PRED_IMG_DIR / img_name
            draw_case_image(corridors, target.level_scope, target, obs_len, pred_modes_abs, best_mode, target_pi, img_path)
            image_paths.append(img_path)

            cases.append(
                {
                    "route_id": target.route_id,
                    "category": target.category,
                    "level_scope": target.level_scope,
                    "obs_length": obs_len,
                    "best_mode": best_mode,
                    "pi": target_pi.tolist(),
                    "ade": ade,
                    "fde": fde,
                    "best_corridor_mean_dist": best_corridor_mean_dist,
                    "gt_corridor_mean_dist": gt_corridor_mean_dist,
                    "image": str(img_path),
                    "context_routes": [r.route_id for r in context],
                    "gt_end": gt_future[-1].tolist(),
                    "pred_end": best_abs[-1].tolist(),
                }
            )

    with open(PRED_JSON, "w", encoding="utf-8") as f:
        json.dump(
            {
                "note": "Predictive embedding demo using HiVT on approved EngineeringDepartment routes",
                "target_patterns": patterns,
                "obs_lengths": obs_lengths,
                "route_count": len(routes),
                "case_count": len(cases),
                "cases": cases,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )

    with open(PRED_MD, "w", encoding="utf-8") as f:
        f.write("# HiVT Predictive Embedding Demo\n\n")
        f.write("## Setup\n\n")
        f.write(f"- route_count: {len(routes)}\n")
        f.write(f"- obs_lengths: {obs_lengths}\n")
        f.write(f"- case_count: {len(cases)}\n\n")

        f.write("## Aggregate Metrics\n\n")
        if cases:
            ade_mean = float(np.mean([c["ade"] for c in cases]))
            fde_mean = float(np.mean([c["fde"] for c in cases]))
            pred_corr_mean = float(np.mean([c["best_corridor_mean_dist"] for c in cases]))
            gt_corr_mean = float(np.mean([c["gt_corridor_mean_dist"] for c in cases]))
            f.write(f"- mean_ADE: {ade_mean:.4f}\n")
            f.write(f"- mean_FDE: {fde_mean:.4f}\n")
            f.write(f"- mean_best_corridor_distance_m: {pred_corr_mean:.4f}\n")
            f.write(f"- mean_gt_corridor_distance_m: {gt_corr_mean:.4f}\n")
        f.write("\n## Cases\n\n")
        for c in cases:
            f.write(
                f"- {c['route_id']} | obs={c['obs_length']} | best={c['best_mode']} | "
                f"ADE={c['ade']:.3f} | FDE={c['fde']:.3f} | "
                f"predCorrDist={c['best_corridor_mean_dist']:.2f}m | image={Path(c['image']).name}\n"
            )

    build_contact_sheet(sorted(image_paths), PRED_CONTACT)

    print("HiVT predictive embedding demo completed")
    print(f"images_dir: {PRED_IMG_DIR}")
    print(f"contact_sheet: {PRED_CONTACT}")
    print(f"json: {PRED_JSON}")
    print(f"md: {PRED_MD}")


if __name__ == "__main__":
    main()
