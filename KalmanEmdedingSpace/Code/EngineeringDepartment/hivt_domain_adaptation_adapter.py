from __future__ import annotations

import argparse
import csv
import json
import math
import random
import sqlite3
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from route_proposal_workflow import DB_PATH, OUT_DIR, load_corridors

ROOT_DIR = Path(__file__).resolve().parent
ADAPT_DIR = OUT_DIR / "domain_adaptation_adapter"
ADAPT_CSV = ADAPT_DIR / "adapter_comparison_cases.csv"
ADAPT_MD = ADAPT_DIR / "adapter_summary.md"
ADAPT_MODEL = ADAPT_DIR / "adapter_weights.pt"

HIST_STEPS = 20
FUTURE_STEPS = 30
TOTAL_STEPS = HIST_STEPS + FUTURE_STEPS
RADIUS_M = 35.0


@dataclass
class Route:
    route_id: str
    category: str
    level_scope: list[str]
    points_xy: np.ndarray  # [50,2]


class EmbeddingAdapter(nn.Module):
    """Lightweight residual adapter on top of frozen HiVT embeddings."""

    def __init__(self, dim: int, hidden: int = 128) -> None:
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(dim, hidden),
            nn.ReLU(inplace=True),
            nn.Linear(hidden, dim),
        )

    def forward(self, z: torch.Tensor) -> torch.Tensor:
        return z + self.net(z)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Simple transfer-learning style domain adaptation on HiVT embeddings")
    parser.add_argument("--db-path", type=Path, default=DB_PATH)
    parser.add_argument("--hivt-root", type=Path, default=Path("../HiVT"))
    parser.add_argument(
        "--ckpt-path",
        type=Path,
        default=Path("../HiVT/checkpoints/HiVT-64/checkpoints/epoch=63-step=411903.ckpt"),
    )
    parser.add_argument("--device", choices=["cpu", "cuda"], default="cpu")
    parser.add_argument("--target-pattern", type=str, default="G%,C%")
    parser.add_argument("--obs-lengths", type=str, default="12,16,20")
    parser.add_argument("--max-context", type=int, default=7)
    parser.add_argument("--seed", type=int, default=2026)

    parser.add_argument("--epochs", type=int, default=40)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--margin", type=float, default=0.25)
    parser.add_argument("--reg-lambda", type=float, default=0.05, help="Keep adapted embedding close to source")
    parser.add_argument("--pos-k", type=int, default=4, help="Number of future-nearest routes as positives")
    parser.add_argument("--neg-k", type=int, default=8, help="Number of future-farthest routes as negatives")
    parser.add_argument("--triplets-per-anchor", type=int, default=12)
    return parser.parse_args()


def resolve_paths(base: Path, path: Path) -> Path:
    return (base / path).resolve() if not path.is_absolute() else path


def set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def load_model(hivt_root: Path, ckpt_path: Path, device: str):
    if not hivt_root.exists():
        raise FileNotFoundError(f"HiVT root not found: {hivt_root}")
    if not (hivt_root / "models" / "hivt.py").exists():
        raise FileNotFoundError(f"Invalid HiVT root: {hivt_root}")
    if not ckpt_path.exists():
        raise FileNotFoundError(f"Checkpoint not found: {ckpt_path}")

    sys.path.insert(0, str(hivt_root))

    import pytorch_lightning as pl
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
            "SELECT point_idx, x_m, y_m FROM route_points WHERE route_id=? ORDER BY point_idx",
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
    by_level: dict[str, list[np.ndarray]] = {}
    for c in corridors:
        p0 = c.center - c.axis * max(4.0, 0.45 * c.length_m)
        p1 = c.center + c.axis * max(4.0, 0.45 * c.length_m)
        by_level.setdefault(c.level, []).append(np.stack([p0, p1 - p0], axis=0))

    out: dict[str, np.ndarray] = {}
    for level, segs in by_level.items():
        out[level] = np.asarray(segs, dtype=float) if segs else np.zeros((0, 2, 2), dtype=float)
    return out


def choose_context(target: Route, pool: list[Route], max_context: int) -> list[Route]:
    candidates = [r for r in pool if r.route_id != target.route_id]

    shared = [
        r
        for r in candidates
        if r.level_scope and target.level_scope and r.level_scope[0] == target.level_scope[0]
    ]
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


def extract_local_embedding(model, data) -> np.ndarray:
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

        local_embed = model.local_encoder(data=data)  # [N, D]

    return local_embed.detach().cpu().numpy()


def snap_to_corridors(points_xy: np.ndarray, corridors: list[Any]) -> np.ndarray:
    if not corridors or points_xy.size == 0:
        return points_xy.copy()

    segs: list[tuple[np.ndarray, np.ndarray]] = []
    for c in corridors:
        half = max(4.0, 0.48 * c.length_m)
        a = c.center - c.axis * half
        b = c.center + c.axis * half
        segs.append((a, b))

    snapped = np.empty_like(points_xy)
    for i, p in enumerate(points_xy):
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
        snapped[i] = best_proj
    return snapped


def future_ade(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.mean(np.linalg.norm(a - b, axis=1)))


def compute_dist_matrix(futures: np.ndarray) -> np.ndarray:
    n = futures.shape[0]
    d = np.zeros((n, n), dtype=float)
    for i in range(n):
        for j in range(i + 1, n):
            val = future_ade(futures[i], futures[j])
            d[i, j] = val
            d[j, i] = val
    return d


def build_triplets(
    dist_mat: np.ndarray,
    pos_k: int,
    neg_k: int,
    triplets_per_anchor: int,
    seed: int,
) -> list[tuple[int, int, int]]:
    rng = random.Random(seed)
    n = dist_mat.shape[0]
    triplets: list[tuple[int, int, int]] = []

    for i in range(n):
        idx = [j for j in range(n) if j != i]
        idx_sorted = sorted(idx, key=lambda j: dist_mat[i, j])
        pos_pool = idx_sorted[: max(1, min(pos_k, len(idx_sorted)))]
        neg_pool = idx_sorted[-max(1, min(neg_k, len(idx_sorted))):]

        for _ in range(triplets_per_anchor):
            p = rng.choice(pos_pool)
            n_idx = rng.choice(neg_pool)
            triplets.append((i, p, n_idx))

    rng.shuffle(triplets)
    return triplets


def cosine_distance_matrix(query: np.ndarray, refs: np.ndarray) -> np.ndarray:
    q = query / (np.linalg.norm(query, axis=1, keepdims=True) + 1e-9)
    r = refs / (np.linalg.norm(refs, axis=1, keepdims=True) + 1e-9)
    sim = q @ r.T
    return 1.0 - sim


def write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def train_adapter(
    z_train: np.ndarray,
    triplets: list[tuple[int, int, int]],
    device: str,
    epochs: int,
    batch_size: int,
    lr: float,
    margin: float,
    reg_lambda: float,
) -> EmbeddingAdapter:
    dim = int(z_train.shape[1])
    adapter = EmbeddingAdapter(dim=dim).to(device)

    optimizer = torch.optim.Adam(adapter.parameters(), lr=lr)
    criterion = nn.TripletMarginWithDistanceLoss(
        distance_function=lambda x, y: 1.0 - F.cosine_similarity(x, y),
        margin=margin,
    )

    z_base = torch.tensor(z_train, dtype=torch.float, device=device)
    idx_triplets = np.asarray(triplets, dtype=np.int64)

    for epoch in range(1, epochs + 1):
        perm = np.random.permutation(len(idx_triplets))
        idx_triplets = idx_triplets[perm]

        running = 0.0
        count = 0

        for start in range(0, len(idx_triplets), batch_size):
            batch = idx_triplets[start : start + batch_size]
            if len(batch) == 0:
                continue

            a = torch.tensor(batch[:, 0], dtype=torch.long, device=device)
            p = torch.tensor(batch[:, 1], dtype=torch.long, device=device)
            n = torch.tensor(batch[:, 2], dtype=torch.long, device=device)

            za = adapter(z_base[a])
            zp = adapter(z_base[p])
            zn = adapter(z_base[n])

            triplet_loss = criterion(za, zp, zn)

            # Keep adaptation close to source embedding to preserve source knowledge.
            reg_loss = (
                F.mse_loss(adapter(z_base[a]), z_base[a])
                + F.mse_loss(adapter(z_base[p]), z_base[p])
                + F.mse_loss(adapter(z_base[n]), z_base[n])
            ) / 3.0

            loss = triplet_loss + reg_lambda * reg_loss

            optimizer.zero_grad()
            loss.backward()
            optimizer.step()

            running += float(loss.item()) * len(batch)
            count += len(batch)

        mean_loss = running / max(1, count)
        if epoch == 1 or epoch % 5 == 0 or epoch == epochs:
            print(f"  epoch {epoch:03d}/{epochs}  loss={mean_loss:.5f}")

    return adapter


def main() -> None:
    args = parse_args()
    set_seed(args.seed)

    base = ROOT_DIR.parent
    hivt_root = resolve_paths(base, args.hivt_root)
    ckpt_path = resolve_paths(base, args.ckpt_path)

    patterns = [x.strip() for x in args.target_pattern.split(",") if x.strip()]
    obs_lengths = [int(x.strip()) for x in args.obs_lengths.split(",") if x.strip()]

    routes = load_routes(args.db_path, patterns)
    if len(routes) < 10:
        raise RuntimeError("Not enough approved routes for adaptation.")

    corridors, _, _ = load_corridors()
    lane_map = build_lane_segments(corridors)

    model = load_model(hivt_root, ckpt_path, args.device)
    print(f"Loaded {len(routes)} routes. Starting adapter training...")

    # Build one base embedding per route (obs=20), plus future target per route.
    base_embeddings: list[np.ndarray] = []
    base_futures: list[np.ndarray] = []
    route_ids: list[str] = []

    for target in routes:
        context = choose_context(target, routes, args.max_context)
        actor_bundle = [target] + context
        anchor_level = target.level_scope[0] if target.level_scope else "0"
        lane_segments = lane_map.get(anchor_level, np.zeros((0, 2, 2), dtype=float))

        data = build_temporal_data(actor_bundle, HIST_STEPS, lane_segments, args.device)
        z = extract_local_embedding(model, data)[0]  # target actor embedding

        base_embeddings.append(z)
        base_futures.append(target.points_xy[HIST_STEPS:])
        route_ids.append(target.route_id)

    z_train = np.stack(base_embeddings, axis=0)
    future_arr = np.stack(base_futures, axis=0)

    dist_mat = compute_dist_matrix(future_arr)
    triplets = build_triplets(
        dist_mat=dist_mat,
        pos_k=args.pos_k,
        neg_k=args.neg_k,
        triplets_per_anchor=args.triplets_per_anchor,
        seed=args.seed,
    )

    adapter = train_adapter(
        z_train=z_train,
        triplets=triplets,
        device=args.device,
        epochs=args.epochs,
        batch_size=args.batch_size,
        lr=args.lr,
        margin=args.margin,
        reg_lambda=args.reg_lambda,
    )

    ADAPT_DIR.mkdir(parents=True, exist_ok=True)
    torch.save({"state_dict": adapter.state_dict()}, ADAPT_MODEL)

    # Build adapted library embeddings.
    adapter.eval()
    with torch.no_grad():
        z_base_t = torch.tensor(z_train, dtype=torch.float, device=args.device)
        z_adapt_t = adapter(z_base_t)
        z_adapt = z_adapt_t.detach().cpu().numpy()

    rows: list[dict[str, Any]] = []

    for target in routes:
        context = choose_context(target, routes, args.max_context)
        actor_bundle = [target] + context
        anchor_level = target.level_scope[0] if target.level_scope else "0"
        lane_segments = lane_map.get(anchor_level, np.zeros((0, 2, 2), dtype=float))

        gt_future = target.points_xy[HIST_STEPS:]
        target_idx = route_ids.index(target.route_id)

        for obs_len in obs_lengths:
            data = build_temporal_data(actor_bundle, obs_len, lane_segments, args.device)
            zq = extract_local_embedding(model, data)[0]

            # Baseline retrieval with source embedding.
            d_base = cosine_distance_matrix(zq[None, :], z_train)[0]
            d_base[target_idx] = np.inf
            nb_base = int(np.argmin(d_base))
            pred_base = future_arr[nb_base]
            pred_base_snap = snap_to_corridors(pred_base, corridors)

            ade_base = float(np.mean(np.linalg.norm(pred_base - gt_future, axis=1)))
            fde_base = float(np.linalg.norm(pred_base[-1] - gt_future[-1]))
            ade_base_snap = float(np.mean(np.linalg.norm(pred_base_snap - gt_future, axis=1)))
            fde_base_snap = float(np.linalg.norm(pred_base_snap[-1] - gt_future[-1]))

            # Adapted retrieval.
            with torch.no_grad():
                zq_t = torch.tensor(zq[None, :], dtype=torch.float, device=args.device)
                zq_adapt = adapter(zq_t).detach().cpu().numpy()[0]

            d_adapt = cosine_distance_matrix(zq_adapt[None, :], z_adapt)[0]
            d_adapt[target_idx] = np.inf
            nb_adapt = int(np.argmin(d_adapt))
            pred_adapt = future_arr[nb_adapt]
            pred_adapt_snap = snap_to_corridors(pred_adapt, corridors)

            ade_adapt = float(np.mean(np.linalg.norm(pred_adapt - gt_future, axis=1)))
            fde_adapt = float(np.linalg.norm(pred_adapt[-1] - gt_future[-1]))
            ade_adapt_snap = float(np.mean(np.linalg.norm(pred_adapt_snap - gt_future, axis=1)))
            fde_adapt_snap = float(np.linalg.norm(pred_adapt_snap[-1] - gt_future[-1]))

            rows.append(
                {
                    "route_id": target.route_id,
                    "obs_len": obs_len,
                    "baseline_neighbor": route_ids[nb_base],
                    "adapt_neighbor": route_ids[nb_adapt],
                    "baseline_cos_dist": round(float(d_base[nb_base]), 6),
                    "adapt_cos_dist": round(float(d_adapt[nb_adapt]), 6),
                    "baseline_ade_raw_m": round(ade_base, 4),
                    "baseline_fde_raw_m": round(fde_base, 4),
                    "baseline_ade_snapped_m": round(ade_base_snap, 4),
                    "baseline_fde_snapped_m": round(fde_base_snap, 4),
                    "adapt_ade_raw_m": round(ade_adapt, 4),
                    "adapt_fde_raw_m": round(fde_adapt, 4),
                    "adapt_ade_snapped_m": round(ade_adapt_snap, 4),
                    "adapt_fde_snapped_m": round(fde_adapt_snap, 4),
                    "delta_ade_snapped_m": round(ade_adapt_snap - ade_base_snap, 4),
                    "delta_fde_snapped_m": round(fde_adapt_snap - fde_base_snap, 4),
                }
            )

    fields = [
        "route_id",
        "obs_len",
        "baseline_neighbor",
        "adapt_neighbor",
        "baseline_cos_dist",
        "adapt_cos_dist",
        "baseline_ade_raw_m",
        "baseline_fde_raw_m",
        "baseline_ade_snapped_m",
        "baseline_fde_snapped_m",
        "adapt_ade_raw_m",
        "adapt_fde_raw_m",
        "adapt_ade_snapped_m",
        "adapt_fde_snapped_m",
        "delta_ade_snapped_m",
        "delta_fde_snapped_m",
    ]
    write_csv(ADAPT_CSV, rows, fields)

    base_ade = np.mean([float(r["baseline_ade_snapped_m"]) for r in rows])
    base_fde = np.mean([float(r["baseline_fde_snapped_m"]) for r in rows])
    adapt_ade = np.mean([float(r["adapt_ade_snapped_m"]) for r in rows])
    adapt_fde = np.mean([float(r["adapt_fde_snapped_m"]) for r in rows])

    improved_ade = sum(1 for r in rows if float(r["delta_ade_snapped_m"]) < 0)
    improved_fde = sum(1 for r in rows if float(r["delta_fde_snapped_m"]) < 0)

    with open(ADAPT_MD, "w", encoding="utf-8") as f:
        f.write("# HiVT Domain Adaptation (Simple Adapter)\n\n")
        f.write("این خروجی با افزودن یک adapter سبک روی embedding های frozen HiVT تولید شده است.\n\n")
        f.write("## Setup\n")
        f.write(f"- Routes: {len(routes)}\n")
        f.write(f"- Obs lengths: {obs_lengths}\n")
        f.write(f"- Epochs: {args.epochs}\n")
        f.write(f"- Margin: {args.margin}\n")
        f.write(f"- Reg lambda: {args.reg_lambda}\n\n")

        f.write("## Mean Metrics (Snapped)\n\n")
        f.write("| Metric | Baseline | Adapted | Delta (Adapted-Baseline) |\n")
        f.write("|---|---:|---:|---:|\n")
        f.write(f"| ADE (m) | {base_ade:.3f} | {adapt_ade:.3f} | {adapt_ade - base_ade:.3f} |\n")
        f.write(f"| FDE (m) | {base_fde:.3f} | {adapt_fde:.3f} | {adapt_fde - base_fde:.3f} |\n\n")

        f.write("## Case-level Improvement Count\n\n")
        f.write(f"- ADE improved in {improved_ade}/{len(rows)} cases\n")
        f.write(f"- FDE improved in {improved_fde}/{len(rows)} cases\n\n")

        f.write("## Output Files\n\n")
        f.write(f"- CSV: {ADAPT_CSV.name}\n")
        f.write(f"- Report: {ADAPT_MD.name}\n")
        f.write(f"- Adapter weights: {ADAPT_MODEL.name}\n")

    print("-" * 60)
    print("Simple domain adaptation finished")
    print(f"CSV: {ADAPT_CSV}")
    print(f"MD:  {ADAPT_MD}")
    print(f"PT:  {ADAPT_MODEL}")
    print(f"mean baseline snapped ADE/FDE: {base_ade:.3f} / {base_fde:.3f}")
    print(f"mean adapted  snapped ADE/FDE: {adapt_ade:.3f} / {adapt_fde:.3f}")
    print("-" * 60)


if __name__ == "__main__":
    main()
