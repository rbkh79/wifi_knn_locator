from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run HiVT inference on derived EngineeringDepartment scenes.")
    parser.add_argument("--hivt-root", type=Path, default=Path("../HiVT"), help="Path to cloned HiVT repository")
    parser.add_argument(
        "--ckpt-path",
        type=Path,
        default=Path("../HiVT/checkpoints/HiVT-64/checkpoints/epoch=63-step=411903.ckpt"),
        help="Path to HiVT checkpoint",
    )
    parser.add_argument(
        "--scene-path",
        type=Path,
        default=Path("EngineeringDepartment/derived/hivt_ready/scene_001_level_0.npz"),
        help="Path to one derived scene npz (relative to Code folder)",
    )
    parser.add_argument(
        "--output-figure",
        type=Path,
        default=Path("EngineeringDepartment/derived/hivt_prediction_scene.png"),
        help="Output figure path (relative to Code folder)",
    )
    parser.add_argument(
        "--output-json",
        type=Path,
        default=Path("EngineeringDepartment/derived/hivt_prediction_scene.json"),
        help="Output json summary path (relative to Code folder)",
    )
    parser.add_argument("--device", choices=["cpu", "cuda"], default="cpu")
    parser.add_argument("--parallel", action="store_true", help="Pass parallel=True to HiVT checkpoint loader")
    return parser.parse_args()


def resolve_paths(code_dir: Path, path: Path) -> Path:
    return (code_dir / path).resolve() if not path.is_absolute() else path


def load_model(hivt_root: Path, ckpt_path: Path, device: str, parallel: bool):
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
        parallel=parallel,
        map_location=torch.device(device),
    )
    model.eval()
    for p in model.parameters():
        p.requires_grad = False
    return model


def build_temporal_data(scene_npz: Path):
    import torch
    from utils import TemporalData

    arr = np.load(scene_npz)

    x = torch.tensor(arr["x"], dtype=torch.float)
    positions = torch.tensor(arr["positions"], dtype=torch.float)
    y = torch.tensor(arr["y"], dtype=torch.float)
    padding_mask = torch.tensor(arr["padding_mask"], dtype=torch.bool)
    bos_mask = torch.tensor(arr["bos_mask"], dtype=torch.bool)
    rotate_angles = torch.tensor(arr["rotate_angles"], dtype=torch.float)
    lane_vectors = torch.tensor(arr["lane_vectors"], dtype=torch.float)
    lane_actor_index = torch.tensor(arr["lane_actor_index"], dtype=torch.long)
    lane_actor_vectors = torch.tensor(arr["lane_actor_vectors"], dtype=torch.float)

    n = int(arr["num_nodes"][0])

    rows, cols = [], []
    for i in range(n):
        for j in range(n):
            if i != j:
                rows.append(i)
                cols.append(j)
    edge_index = torch.tensor([rows, cols], dtype=torch.long)

    lane_count = int(lane_vectors.shape[0])
    is_intersections = torch.zeros(lane_count, dtype=torch.uint8)
    turn_directions = torch.zeros(lane_count, dtype=torch.uint8)
    traffic_controls = torch.zeros(lane_count, dtype=torch.uint8)

    data = TemporalData(
        x=x,
        positions=positions,
        edge_index=edge_index,
        y=y,
        num_nodes=n,
        padding_mask=padding_mask,
        bos_mask=bos_mask,
        rotate_angles=rotate_angles,
        lane_vectors=lane_vectors,
        is_intersections=is_intersections,
        turn_directions=turn_directions,
        traffic_controls=traffic_controls,
        lane_actor_index=lane_actor_index,
        lane_actor_vectors=lane_actor_vectors,
        seq_id=0,
    )
    data["agent_index"] = torch.tensor([0], dtype=torch.long)
    data["av_index"] = torch.tensor([0], dtype=torch.long)

    return data


def plot_prediction(scene_npz: Path, y_hat: np.ndarray, best_mode: int, output_figure: Path) -> None:
    arr = np.load(scene_npz)
    positions = arr["positions"]  # [N, 50, 2]
    lane_vectors = arr["lane_vectors"]  # [L, 2]
    lane_actor_vectors = arr["lane_actor_vectors"]

    actor = positions[0]
    hist = actor[:20]
    gt_fut_abs = actor[20:]

    pred_rel = y_hat[best_mode, 0, :, :2]
    pred_abs = pred_rel + hist[-1]

    fig, ax = plt.subplots(figsize=(9.5, 7.0), dpi=180)

    if lane_vectors.shape[0] > 0:
        # Rebuild approximate lane anchors by shifting from actor with lane-actor vectors when available.
        if lane_actor_vectors.shape[0] > 0:
            actor0 = hist[-1]
            lane_pos = actor0 + lane_actor_vectors[: min(80, lane_actor_vectors.shape[0])]
            for p in lane_pos:
                ax.scatter([p[0]], [p[1]], s=5, color="#cbd5e1", alpha=0.7)

    ax.plot(hist[:, 0], hist[:, 1], color="#0f172a", linewidth=2.4, label="Observed (history)")
    ax.plot(gt_fut_abs[:, 0], gt_fut_abs[:, 1], color="#f97316", linewidth=2.2, label="GT future")

    num_modes = y_hat.shape[0]
    for m in range(num_modes):
        m_abs = y_hat[m, 0, :, :2] + hist[-1]
        if m == best_mode:
            ax.plot(m_abs[:, 0], m_abs[:, 1], color="#16a34a", linewidth=2.6, label="Best HiVT mode")
        else:
            ax.plot(m_abs[:, 0], m_abs[:, 1], color="#93c5fd", linewidth=1.2, alpha=0.85)

    ax.scatter([hist[-1, 0]], [hist[-1, 1]], marker="*", s=90, color="#dc2626", label="Current agent")
    ax.set_title("HiVT Inference on Derived Indoor Scene")
    ax.set_xlabel("x (m)")
    ax.set_ylabel("y (m)")
    ax.grid(alpha=0.22)
    ax.legend(frameon=False, loc="best")
    ax.set_aspect("equal", adjustable="box")
    fig.tight_layout()
    output_figure.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_figure, bbox_inches="tight")
    plt.close(fig)


def main() -> None:
    args = parse_args()
    code_dir = Path(__file__).resolve().parent.parent

    hivt_root = resolve_paths(code_dir, args.hivt_root)
    ckpt_path = resolve_paths(code_dir, args.ckpt_path)
    scene_path = resolve_paths(code_dir, args.scene_path)
    output_figure = resolve_paths(code_dir, args.output_figure)
    output_json = resolve_paths(code_dir, args.output_json)

    model = load_model(hivt_root, ckpt_path, args.device, args.parallel)

    import torch

    data = build_temporal_data(scene_path)
    data = data.to(torch.device(args.device))

    with torch.no_grad():
        y_hat, pi = model(data)

    y_hat_np = y_hat.detach().cpu().numpy()
    pi_np = pi.detach().cpu().numpy()
    best_mode = int(np.argmax(pi_np[0]))

    plot_prediction(scene_path, y_hat_np, best_mode, output_figure)

    summary = {
        "scene": str(scene_path),
        "output_figure": str(output_figure),
        "output_json": str(output_json),
        "model": {
            "historical_steps": int(model.hparams.historical_steps),
            "future_steps": int(model.hparams.future_steps),
            "num_modes": int(model.hparams.num_modes),
            "embed_dim": int(model.hparams.embed_dim),
        },
        "pred": {
            "pi": pi_np[0].tolist(),
            "best_mode": best_mode,
        },
    }

    output_json.parent.mkdir(parents=True, exist_ok=True)
    with open(output_json, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    print("HiVT inference on derived scene completed")
    print(f"figure: {output_figure}")
    print(f"json: {output_json}")


if __name__ == "__main__":
    main()
