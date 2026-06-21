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

import matplotlib.pyplot as plt
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from route_proposal_workflow import DB_PATH, OUT_DIR, floor_color, load_corridors

ROOT_DIR = Path(__file__).resolve().parent
OUT_BASE = OUT_DIR / "contrastive_decoder"
IMG_DIR = OUT_BASE / "images"
CSV_PATH = OUT_BASE / "contrastive_decoder_cases.csv"
MD_PATH = OUT_BASE / "contrastive_decoder_summary.md"
ADAPTER_PT = OUT_BASE / "contrastive_adapter.pt"
DECODER_PT = OUT_BASE / "contrastive_decoder.pt"
CONTACT_PATH = OUT_BASE / "predictions_contact_sheet.png"

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


@dataclass
class Sample:
    route_id: str
    obs_len: int
    embedding: np.ndarray  # [D]
    hist_last: np.ndarray  # [2]
    observed_xy: np.ndarray  # [obs_len,2]
    gt_future_abs: np.ndarray  # [30,2]
    gt_future_rel: np.ndarray  # [30,2]


class EmbeddingAdapter(nn.Module):
    def __init__(self, dim: int, hidden: int = 128) -> None:
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(dim, hidden),
            nn.ReLU(inplace=True),
            nn.Linear(hidden, dim),
        )

    def forward(self, z: torch.Tensor) -> torch.Tensor:
        return z + self.net(z)


class FutureDecoder(nn.Module):
    def __init__(self, dim: int, hidden: int = 256, future_steps: int = FUTURE_STEPS) -> None:
        super().__init__()
        self.future_steps = future_steps
        self.net = nn.Sequential(
            nn.Linear(dim + 1, hidden),  # +1 for normalized obs length
            nn.ReLU(inplace=True),
            nn.Linear(hidden, hidden),
            nn.ReLU(inplace=True),
            nn.Linear(hidden, future_steps * 2),
        )

    def forward(self, z: torch.Tensor, obs_len_norm: torch.Tensor) -> torch.Tensor:
        x = torch.cat([z, obs_len_norm], dim=-1)
        out = self.net(x)
        return out.view(-1, self.future_steps, 2)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="HiVT contrastive adapter + decoder predictor (new file, non-destructive)")
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
    parser.add_argument("--train-ratio", type=float, default=0.8)

    parser.add_argument("--adapter-epochs", type=int, default=25)
    parser.add_argument("--decoder-epochs", type=int, default=50)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--adapter-lr", type=float, default=1e-3)
    parser.add_argument("--decoder-lr", type=float, default=1e-3)
    parser.add_argument("--margin", type=float, default=0.2)
    parser.add_argument("--reg-lambda", type=float, default=0.05)
    parser.add_argument("--pos-k", type=int, default=4)
    parser.add_argument("--neg-k", type=int, default=8)
    parser.add_argument("--triplets-per-anchor", type=int, default=12)
    parser.add_argument("--retrieval-top-k", type=int, default=6)
    parser.add_argument("--retrieval-tau", type=float, default=0.05)
    parser.add_argument("--hybrid-alpha", type=float, default=0.35, help="Weight for decoder in hybrid")
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


def ade_fde(pred_abs: np.ndarray, gt_abs: np.ndarray) -> tuple[float, float]:
    ade = float(np.mean(np.linalg.norm(pred_abs - gt_abs, axis=1)))
    fde = float(np.linalg.norm(pred_abs[-1] - gt_abs[-1]))
    return ade, fde


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
    future_dist: np.ndarray,
    pos_k: int,
    neg_k: int,
    triplets_per_anchor: int,
    seed: int,
) -> list[tuple[int, int, int]]:
    rng = random.Random(seed)
    n = future_dist.shape[0]
    triplets: list[tuple[int, int, int]] = []

    for i in range(n):
        idx = [j for j in range(n) if j != i]
        idx_sorted = sorted(idx, key=lambda j: future_dist[i, j])
        pos_pool = idx_sorted[: max(1, min(pos_k, len(idx_sorted)))]
        neg_pool = idx_sorted[-max(1, min(neg_k, len(idx_sorted))):]

        for _ in range(triplets_per_anchor):
            p = rng.choice(pos_pool)
            n_idx = rng.choice(neg_pool)
            triplets.append((i, p, n_idx))

    rng.shuffle(triplets)
    return triplets


def write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def distances_to_probabilities(distances: np.ndarray, tau: float) -> np.ndarray:
    tau = max(1e-6, float(tau))
    d = np.asarray(distances, dtype=float)
    d = d - np.min(d)
    s = np.exp(-d / tau)
    s_sum = np.sum(s)
    if s_sum < 1e-12:
        return np.ones_like(s) / max(1, len(s))
    return s / s_sum


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
        np.random.shuffle(idx_triplets)

        total = 0.0
        count = 0
        for s in range(0, len(idx_triplets), batch_size):
            batch = idx_triplets[s : s + batch_size]
            if len(batch) == 0:
                continue

            a = torch.tensor(batch[:, 0], dtype=torch.long, device=device)
            p = torch.tensor(batch[:, 1], dtype=torch.long, device=device)
            n = torch.tensor(batch[:, 2], dtype=torch.long, device=device)

            za = adapter(z_base[a])
            zp = adapter(z_base[p])
            zn = adapter(z_base[n])

            triplet_loss = criterion(za, zp, zn)
            reg_loss = (
                F.mse_loss(za, z_base[a]) + F.mse_loss(zp, z_base[p]) + F.mse_loss(zn, z_base[n])
            ) / 3.0

            loss = triplet_loss + reg_lambda * reg_loss

            optimizer.zero_grad()
            loss.backward()
            optimizer.step()

            total += float(loss.item()) * len(batch)
            count += len(batch)

        mean_loss = total / max(1, count)
        if epoch == 1 or epoch % 5 == 0 or epoch == epochs:
            print(f"  [adapter] epoch {epoch:03d}/{epochs} loss={mean_loss:.5f}")

    return adapter


def train_decoder(
    decoder: FutureDecoder,
    adapter: EmbeddingAdapter,
    samples_train: list[Sample],
    device: str,
    epochs: int,
    batch_size: int,
    lr: float,
) -> FutureDecoder:
    optimizer = torch.optim.Adam(decoder.parameters(), lr=lr)

    # Freeze adapter during decoder fitting.
    adapter.eval()
    for p in adapter.parameters():
        p.requires_grad = False

    z = np.stack([s.embedding for s in samples_train], axis=0)
    obs = np.array([s.obs_len / HIST_STEPS for s in samples_train], dtype=float)[:, None]
    y = np.stack([s.gt_future_rel for s in samples_train], axis=0)

    z_t = torch.tensor(z, dtype=torch.float, device=device)
    obs_t = torch.tensor(obs, dtype=torch.float, device=device)
    y_t = torch.tensor(y, dtype=torch.float, device=device)

    n = z.shape[0]
    idx = np.arange(n)

    for epoch in range(1, epochs + 1):
        np.random.shuffle(idx)

        total = 0.0
        count = 0

        for s in range(0, n, batch_size):
            b = idx[s : s + batch_size]
            zb = z_t[b]
            ob = obs_t[b]
            yb = y_t[b]

            with torch.no_grad():
                za = adapter(zb)

            pred = decoder(za, ob)

            loss_mse = F.smooth_l1_loss(pred, yb)
            loss_fde = F.smooth_l1_loss(pred[:, -1, :], yb[:, -1, :])
            loss = loss_mse + 0.5 * loss_fde

            optimizer.zero_grad()
            loss.backward()
            optimizer.step()

            total += float(loss.item()) * len(b)
            count += len(b)

        mean_loss = total / max(1, count)
        if epoch == 1 or epoch % 5 == 0 or epoch == epochs:
            print(f"  [decoder] epoch {epoch:03d}/{epochs} loss={mean_loss:.5f}")

    return decoder


def draw_case_image(
    corridors: list[Any],
    route: Route,
    obs_len: int,
    observed: np.ndarray,
    gt_future: np.ndarray,
    pred_raw: np.ndarray,
    pred_snap: np.ndarray,
    pred_hybrid_snap: np.ndarray,
    ade_raw: float,
    fde_raw: float,
    ade_snap: float,
    fde_snap: float,
    ade_hybrid: float,
    fde_hybrid: float,
    out_path: Path,
) -> None:
    fig, ax = plt.subplots(figsize=(10.8, 7.8), dpi=170)

    levels = set(route.level_scope)
    for c in corridors:
        color = floor_color(c.level)
        active = c.level in levels
        ax.fill(c.ring_xy[:, 0], c.ring_xy[:, 1], color=color, alpha=0.18 if active else 0.04)
        ax.plot(
            c.ring_xy[:, 0],
            c.ring_xy[:, 1],
            color=color,
            linewidth=0.8 if active else 0.35,
            alpha=0.6 if active else 0.2,
        )

    ax.plot(observed[:, 0], observed[:, 1], color="#0f172a", linewidth=2.8, label=f"Observed ({obs_len})")
    ax.plot(gt_future[:, 0], gt_future[:, 1], color="#f97316", linewidth=2.2, label="GT future")
    ax.plot(pred_raw[:, 0], pred_raw[:, 1], color="#16a34a", linewidth=2.2, linestyle="--", label="Pred raw")
    ax.plot(pred_snap[:, 0], pred_snap[:, 1], color="#7c3aed", linewidth=2.2, label="Pred snapped")
    ax.plot(
        pred_hybrid_snap[:, 0],
        pred_hybrid_snap[:, 1],
        color="#0ea5e9",
        linewidth=2.4,
        label="Hybrid snapped",
    )

    ax.scatter([observed[-1, 0]], [observed[-1, 1]], color="#dc2626", s=45, label="Prediction start")

    ax.set_title(
        f"{route.route_id} | obs={obs_len} | dec-snap ADE/FDE={ade_snap:.1f}/{fde_snap:.1f} | "
        f"hyb ADE/FDE={ade_hybrid:.1f}/{fde_hybrid:.1f}"
    )
    ax.set_xlabel("x (m)")
    ax.set_ylabel("y (m)")
    ax.grid(alpha=0.2)
    ax.legend(frameon=False, loc="best")
    ax.set_aspect("equal", adjustable="box")
    fig.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)


def build_contact_sheet(paths: list[Path], out_path: Path, max_items: int = 36) -> None:
    if not paths:
        return

    use = paths[:max_items]
    cols = 4
    rows = int(math.ceil(len(use) / cols))

    fig, axes = plt.subplots(rows, cols, figsize=(4.3 * cols, 3.2 * rows), dpi=130)
    axes_arr = np.array(axes).reshape(-1)

    for ax, path in zip(axes_arr, use):
        img = plt.imread(path)
        ax.imshow(img)
        ax.set_title(path.stem[:52], fontsize=7)
        ax.axis("off")

    for ax in axes_arr[len(use) :]:
        ax.axis("off")

    fig.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)


def main() -> None:
    args = parse_args()
    set_seed(args.seed)

    base = ROOT_DIR.parent
    hivt_root = resolve_paths(base, args.hivt_root)
    ckpt_path = resolve_paths(base, args.ckpt_path)

    patterns = [x.strip() for x in args.target_pattern.split(",") if x.strip()]
    obs_lengths = [int(x.strip()) for x in args.obs_lengths.split(",") if x.strip()]

    routes = load_routes(args.db_path, patterns)
    if len(routes) < 12:
        raise RuntimeError("Not enough routes for contrastive+decoder training.")

    corridors, _, _ = load_corridors()
    lane_map = build_lane_segments(corridors)

    model = load_model(hivt_root, ckpt_path, args.device)

    # Route-level train/test split.
    route_ids = [r.route_id for r in routes]
    rnd = random.Random(args.seed)
    rnd.shuffle(route_ids)
    split = int(max(1, min(len(route_ids) - 1, round(len(route_ids) * args.train_ratio))))
    train_ids = set(route_ids[:split])
    test_ids = set(route_ids[split:])

    train_routes = [r for r in routes if r.route_id in train_ids]
    test_routes = [r for r in routes if r.route_id in test_ids]

    print("-" * 60)
    print(f"routes total={len(routes)} train={len(train_routes)} test={len(test_routes)}")
    print("Building samples...")

    samples_train: list[Sample] = []
    samples_test: list[Sample] = []

    for target in routes:
        pool = train_routes if target.route_id in train_ids else routes
        context = choose_context(target, pool, args.max_context)
        actor_bundle = [target] + context

        anchor_level = target.level_scope[0] if target.level_scope else "0"
        lane_segments = lane_map.get(anchor_level, np.zeros((0, 2, 2), dtype=float))

        for obs_len in obs_lengths:
            data = build_temporal_data(actor_bundle, obs_len, lane_segments, args.device)
            z = extract_local_embedding(model, data)[0]

            hist = target.points_xy[:HIST_STEPS]
            observed = hist[HIST_STEPS - obs_len :]
            hist_last = hist[-1]
            gt_abs = target.points_xy[HIST_STEPS:]
            gt_rel = gt_abs - hist_last[None, :]

            s = Sample(
                route_id=target.route_id,
                obs_len=obs_len,
                embedding=z,
                hist_last=hist_last,
                observed_xy=observed,
                gt_future_abs=gt_abs,
                gt_future_rel=gt_rel,
            )

            if target.route_id in train_ids:
                samples_train.append(s)
            else:
                samples_test.append(s)

    if len(samples_test) == 0:
        raise RuntimeError("No test samples; adjust train-ratio.")

    print(f"samples train={len(samples_train)} test={len(samples_test)}")

    # Train adapter using future-similarity triplets on train set.
    z_train = np.stack([s.embedding for s in samples_train], axis=0)
    y_train_abs = np.stack([s.gt_future_abs for s in samples_train], axis=0)

    future_dist = compute_dist_matrix(y_train_abs)
    triplets = build_triplets(
        future_dist=future_dist,
        pos_k=args.pos_k,
        neg_k=args.neg_k,
        triplets_per_anchor=args.triplets_per_anchor,
        seed=args.seed,
    )

    print(f"Training adapter with {len(triplets)} triplets...")
    adapter = train_adapter(
        z_train=z_train,
        triplets=triplets,
        device=args.device,
        epochs=args.adapter_epochs,
        batch_size=args.batch_size,
        lr=args.adapter_lr,
        margin=args.margin,
        reg_lambda=args.reg_lambda,
    )

    dim = z_train.shape[1]
    decoder = FutureDecoder(dim=dim).to(args.device)

    print("Training decoder on adapted embeddings...")
    decoder = train_decoder(
        decoder=decoder,
        adapter=adapter,
        samples_train=samples_train,
        device=args.device,
        epochs=args.decoder_epochs,
        batch_size=args.batch_size,
        lr=args.decoder_lr,
    )

    OUT_BASE.mkdir(parents=True, exist_ok=True)
    IMG_DIR.mkdir(parents=True, exist_ok=True)

    torch.save({"state_dict": adapter.state_dict()}, ADAPTER_PT)
    torch.save({"state_dict": decoder.state_dict()}, DECODER_PT)

    # Evaluate on held-out route IDs and produce images.
    adapter.eval()
    decoder.eval()

    rows: list[dict[str, Any]] = []
    img_paths: list[Path] = []

    # Build retrieval library from train samples in adapted space.
    with torch.no_grad():
        z_train_t = torch.tensor(np.stack([s.embedding for s in samples_train], axis=0), dtype=torch.float, device=args.device)
        z_train_adapt = adapter(z_train_t).detach().cpu().numpy()
    y_train_rel = np.stack([s.gt_future_rel for s in samples_train], axis=0)
    train_route_ids = [s.route_id for s in samples_train]

    with torch.no_grad():
        for s in samples_test:
            z = torch.tensor(s.embedding[None, :], dtype=torch.float, device=args.device)
            obs_norm = torch.tensor([[s.obs_len / HIST_STEPS]], dtype=torch.float, device=args.device)

            z_adapt = adapter(z)
            pred_rel = decoder(z_adapt, obs_norm).detach().cpu().numpy()[0]  # [30,2]
            pred_abs = pred_rel + s.hist_last[None, :]
            pred_snap = snap_to_corridors(pred_abs, corridors)

            # Retrieval on adapted embedding + hybrid fusion.
            zq = z_adapt.detach().cpu().numpy()[0]
            q_norm = zq / (np.linalg.norm(zq) + 1e-9)
            lib_norm = z_train_adapt / (np.linalg.norm(z_train_adapt, axis=1, keepdims=True) + 1e-9)
            d = 1.0 - (lib_norm @ q_norm)

            # Exclude same route id if present in library.
            for i, rid in enumerate(train_route_ids):
                if rid == s.route_id:
                    d[i] = np.inf

            k = int(max(1, min(args.retrieval_top_k, np.sum(np.isfinite(d)))))
            top_idx = np.argsort(d)[:k]
            top_d = d[top_idx]
            p = distances_to_probabilities(top_d, args.retrieval_tau)

            ret_rel = np.zeros((FUTURE_STEPS, 2), dtype=float)
            for w, idx in zip(p, top_idx):
                ret_rel += float(w) * y_train_rel[idx]

            alpha = float(max(0.0, min(1.0, args.hybrid_alpha)))
            hyb_rel = alpha * pred_rel + (1.0 - alpha) * ret_rel
            hyb_abs = hyb_rel + s.hist_last[None, :]
            hyb_snap = snap_to_corridors(hyb_abs, corridors)

            ade_raw, fde_raw = ade_fde(pred_abs, s.gt_future_abs)
            ade_snap, fde_snap = ade_fde(pred_snap, s.gt_future_abs)
            ade_hyb, fde_hyb = ade_fde(hyb_snap, s.gt_future_abs)

            row = {
                "route_id": s.route_id,
                "obs_len": s.obs_len,
                "ade_raw_m": round(ade_raw, 4),
                "fde_raw_m": round(fde_raw, 4),
                "ade_snapped_m": round(ade_snap, 4),
                "fde_snapped_m": round(fde_snap, 4),
                "ade_hybrid_snapped_m": round(ade_hyb, 4),
                "fde_hybrid_snapped_m": round(fde_hyb, 4),
                "hybrid_topk": k,
                "hybrid_alpha": alpha,
            }
            rows.append(row)

            img_name = f"{s.route_id}__obs{s.obs_len}.png"
            img_path = IMG_DIR / img_name
            draw_case_image(
                corridors=corridors,
                route=next(r for r in routes if r.route_id == s.route_id),
                obs_len=s.obs_len,
                observed=s.observed_xy,
                gt_future=s.gt_future_abs,
                pred_raw=pred_abs,
                pred_snap=pred_snap,
                pred_hybrid_snap=hyb_snap,
                ade_raw=ade_raw,
                fde_raw=fde_raw,
                ade_snap=ade_snap,
                fde_snap=fde_snap,
                ade_hybrid=ade_hyb,
                fde_hybrid=fde_hyb,
                out_path=img_path,
            )
            img_paths.append(img_path)

    fields = [
        "route_id",
        "obs_len",
        "ade_raw_m",
        "fde_raw_m",
        "ade_snapped_m",
        "fde_snapped_m",
        "ade_hybrid_snapped_m",
        "fde_hybrid_snapped_m",
        "hybrid_topk",
        "hybrid_alpha",
    ]
    write_csv(CSV_PATH, rows, fields)

    build_contact_sheet(img_paths, CONTACT_PATH)

    mean_ade_raw = float(np.mean([r["ade_raw_m"] for r in rows]))
    mean_fde_raw = float(np.mean([r["fde_raw_m"] for r in rows]))
    mean_ade_snap = float(np.mean([r["ade_snapped_m"] for r in rows]))
    mean_fde_snap = float(np.mean([r["fde_snapped_m"] for r in rows]))
    mean_ade_hyb = float(np.mean([r["ade_hybrid_snapped_m"] for r in rows]))
    mean_fde_hyb = float(np.mean([r["fde_hybrid_snapped_m"] for r in rows]))

    best_rows = sorted(rows, key=lambda x: x["fde_hybrid_snapped_m"])[:10]
    worst_rows = sorted(rows, key=lambda x: x["fde_hybrid_snapped_m"], reverse=True)[:10]

    with open(MD_PATH, "w", encoding="utf-8") as f:
        f.write("# Contrastive + Decoder Prediction Summary\n\n")
        f.write("این خروجی با یک روش جدید مستقل تولید شده و فایل های قبلی را تغییر نمی دهد.\n\n")
        f.write("## Training setup\n")
        f.write(f"- train routes: {len(train_routes)}\n")
        f.write(f"- test routes: {len(test_routes)}\n")
        f.write(f"- train samples: {len(samples_train)}\n")
        f.write(f"- test samples: {len(samples_test)}\n")
        f.write(f"- adapter epochs: {args.adapter_epochs}\n")
        f.write(f"- decoder epochs: {args.decoder_epochs}\n\n")
        f.write(f"- hybrid alpha: {args.hybrid_alpha}\n")
        f.write(f"- retrieval top-k: {args.retrieval_top_k}\n")
        f.write(f"- retrieval tau: {args.retrieval_tau}\n\n")

        f.write("## Mean metrics on held-out test routes\n\n")
        f.write("| Metric | Value (m) |\n")
        f.write("|---|---:|\n")
        f.write(f"| mean ADE raw | {mean_ade_raw:.3f} |\n")
        f.write(f"| mean FDE raw | {mean_fde_raw:.3f} |\n")
        f.write(f"| mean ADE decoder-snapped | {mean_ade_snap:.3f} |\n")
        f.write(f"| mean FDE decoder-snapped | {mean_fde_snap:.3f} |\n")
        f.write(f"| mean ADE hybrid-snapped | {mean_ade_hyb:.3f} |\n")
        f.write(f"| mean FDE hybrid-snapped | {mean_fde_hyb:.3f} |\n\n")

        f.write("## Best 10 by hybrid snapped FDE\n\n")
        for r in best_rows:
            f.write(
                f"- {r['route_id']} obs={r['obs_len']} | ADE_hyb={r['ade_hybrid_snapped_m']:.2f} | "
                f"FDE_hyb={r['fde_hybrid_snapped_m']:.2f}\n"
            )
        f.write("\n")

        f.write("## Worst 10 by hybrid snapped FDE\n\n")
        for r in worst_rows:
            f.write(
                f"- {r['route_id']} obs={r['obs_len']} | ADE_hyb={r['ade_hybrid_snapped_m']:.2f} | "
                f"FDE_hyb={r['fde_hybrid_snapped_m']:.2f}\n"
            )
        f.write("\n")

        f.write("## Output files\n\n")
        f.write(f"- CSV: {CSV_PATH.name}\n")
        f.write(f"- Summary: {MD_PATH.name}\n")
        f.write(f"- Images: {IMG_DIR.name}/\n")
        f.write(f"- Contact sheet: {CONTACT_PATH.name}\n")
        f.write(f"- Adapter weights: {ADAPTER_PT.name}\n")
        f.write(f"- Decoder weights: {DECODER_PT.name}\n")

    print("-" * 60)
    print("Contrastive + decoder run finished")
    print(f"CSV: {CSV_PATH}")
    print(f"MD:  {MD_PATH}")
    print(f"IMG: {IMG_DIR}")
    print(f"CONTACT: {CONTACT_PATH}")
    print(f"mean decoder snapped ADE/FDE: {mean_ade_snap:.3f} / {mean_fde_snap:.3f}")
    print(f"mean hybrid  snapped ADE/FDE: {mean_ade_hyb:.3f} / {mean_fde_hyb:.3f}")
    print("-" * 60)


if __name__ == "__main__":
    main()
