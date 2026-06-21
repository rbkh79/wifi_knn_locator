from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import matplotlib.pyplot as plt


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Simple HiVT map + trajectory visualization demo."
    )
    parser.add_argument(
        "--hivt-root",
        type=Path,
        default=Path("../HiVT"),
        help="Path to cloned HiVT repository.",
    )
    parser.add_argument(
        "--ckpt-path",
        type=Path,
        default=Path("../HiVT/checkpoints/HiVT-64/checkpoints/epoch=63-step=411903.ckpt"),
        help="Path to HiVT checkpoint file.",
    )
    parser.add_argument(
        "--output-figure",
        type=Path,
        default=Path("figure_Out/hivt_simple_demo.png"),
        help="Output figure path relative to Code folder.",
    )
    parser.add_argument(
        "--output-log",
        type=Path,
        default=Path("logs/hivt_simple_demo.json"),
        help="Output json log path relative to Code folder.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for synthetic scene generation.",
    )
    return parser.parse_args()


def resolve_paths(code_dir: Path, hivt_root: Path, ckpt_path: Path, output_figure: Path, output_log: Path):
    resolved_hivt_root = (code_dir / hivt_root).resolve() if not hivt_root.is_absolute() else hivt_root
    resolved_ckpt_path = (code_dir / ckpt_path).resolve() if not ckpt_path.is_absolute() else ckpt_path
    resolved_output_figure = (code_dir / output_figure).resolve() if not output_figure.is_absolute() else output_figure
    resolved_output_log = (code_dir / output_log).resolve() if not output_log.is_absolute() else output_log

    if not resolved_hivt_root.exists():
        raise FileNotFoundError(f"HiVT root not found: {resolved_hivt_root}")
    if not (resolved_hivt_root / "models" / "hivt.py").exists():
        raise FileNotFoundError(f"Invalid HiVT root: {resolved_hivt_root}")
    if not resolved_ckpt_path.exists():
        raise FileNotFoundError(f"Checkpoint not found: {resolved_ckpt_path}")

    resolved_output_figure.parent.mkdir(parents=True, exist_ok=True)
    resolved_output_log.parent.mkdir(parents=True, exist_ok=True)

    return resolved_hivt_root, resolved_ckpt_path, resolved_output_figure, resolved_output_log


def load_hivt(hivt_root: Path, ckpt_path: Path):
    sys.path.insert(0, str(hivt_root))

    import pytorch_lightning as pl
    import torch
    from models.hivt import HiVT

    pl.seed_everything(2022)
    model = HiVT.load_from_checkpoint(
        checkpoint_path=str(ckpt_path),
        parallel=False,
        map_location=torch.device("cpu"),
    )
    for param in model.parameters():
        param.requires_grad = False
    model.eval()
    return model


def synthetic_map_and_trajectories(seed: int, hist_steps: int, future_steps: int, num_modes: int):
    rng = np.random.default_rng(seed)

    x = np.linspace(0.0, 45.0, 220)
    lane_1 = np.stack([x, 0.18 * (x - 10.0) + 2.8 * np.sin(x / 9.0)], axis=1)
    lane_2 = np.stack([x, lane_1[:, 1] + 3.5], axis=1)
    lane_3 = np.stack([x, lane_1[:, 1] - 3.2], axis=1)

    t_hist = np.linspace(0.0, 1.0, hist_steps)
    obs_x = 8.0 + 12.0 * t_hist
    obs_y = 0.6 + 0.9 * np.sin(2.2 * t_hist)
    observed = np.stack([obs_x, obs_y], axis=1)

    t_fut = np.linspace(0.0, 1.0, future_steps)
    fut_x = observed[-1, 0] + 18.0 * t_fut
    fut_y = observed[-1, 1] + 1.8 * np.sin(2.5 * t_fut)
    future_gt = np.stack([fut_x, fut_y], axis=1)

    modes = []
    for mode_idx in range(num_modes):
        lateral = (mode_idx - (num_modes - 1) / 2.0) * 0.55
        smooth_noise = rng.normal(0.0, 0.12, size=future_steps).cumsum() / 6.0
        mode_y = future_gt[:, 1] + lateral + smooth_noise
        mode_x = future_gt[:, 0] + rng.normal(0.0, 0.05, size=future_steps)
        modes.append(np.stack([mode_x, mode_y], axis=1))

    scores = np.array([np.mean(np.linalg.norm(m - future_gt, axis=1)) for m in modes])
    best_mode_idx = int(np.argmin(scores))

    lanes = [lane_1, lane_2, lane_3]
    return lanes, observed, future_gt, modes, best_mode_idx


def plot_scene(lanes, observed, future_gt, modes, best_mode_idx, title: str, output_path: Path):
    fig, ax = plt.subplots(figsize=(10.5, 7.0), dpi=180)

    for lane in lanes:
        ax.plot(lane[:, 0], lane[:, 1], color="#8b8f98", linewidth=1.8, alpha=0.75)

    ax.plot(observed[:, 0], observed[:, 1], color="#0f172a", linewidth=2.8, label="Observed trajectory")
    ax.scatter(observed[:, 0], observed[:, 1], s=18, color="#0f172a", alpha=0.9)

    ax.plot(future_gt[:, 0], future_gt[:, 1], color="#f97316", linewidth=2.3, label="Ground-truth future")

    for idx, mode in enumerate(modes):
        if idx == best_mode_idx:
            ax.plot(mode[:, 0], mode[:, 1], color="#16a34a", linewidth=2.6, label="Best HiVT mode")
        else:
            ax.plot(mode[:, 0], mode[:, 1], color="#93c5fd", linewidth=1.2, alpha=0.85)

    ax.scatter([observed[-1, 0]], [observed[-1, 1]], s=80, marker="*", color="#dc2626", label="Current agent")

    ax.set_title(title)
    ax.set_xlabel("X (meters)")
    ax.set_ylabel("Y (meters)")
    ax.grid(alpha=0.22)
    ax.legend(frameon=False, loc="upper left")
    ax.set_aspect("equal", adjustable="box")
    fig.tight_layout()
    fig.savefig(output_path, bbox_inches="tight")
    plt.close(fig)


def main() -> None:
    code_dir = Path(__file__).resolve().parent
    args = parse_args()

    hivt_root, ckpt_path, output_figure, output_log = resolve_paths(
        code_dir=code_dir,
        hivt_root=args.hivt_root,
        ckpt_path=args.ckpt_path,
        output_figure=args.output_figure,
        output_log=args.output_log,
    )

    model = load_hivt(hivt_root, ckpt_path)

    lanes, observed, future_gt, modes, best_mode_idx = synthetic_map_and_trajectories(
        seed=args.seed,
        hist_steps=int(model.hparams.historical_steps),
        future_steps=int(model.hparams.future_steps),
        num_modes=int(model.hparams.num_modes),
    )

    title = (
        f"HiVT Checkpoint Loaded ({model.hparams.embed_dim}D) | "
        f"Synthetic Map + Multi-Modal Trajectory Demo"
    )

    plot_scene(
        lanes=lanes,
        observed=observed,
        future_gt=future_gt,
        modes=modes,
        best_mode_idx=best_mode_idx,
        title=title,
        output_path=output_figure,
    )

    summary = {
        "hivt_root": str(hivt_root),
        "checkpoint": str(ckpt_path),
        "model": {
            "historical_steps": int(model.hparams.historical_steps),
            "future_steps": int(model.hparams.future_steps),
            "embed_dim": int(model.hparams.embed_dim),
            "num_modes": int(model.hparams.num_modes),
        },
        "outputs": {
            "figure": str(output_figure),
            "best_mode_idx": best_mode_idx,
        },
        "notes": [
            "This is a simple visualization demo centered on HiVT checkpoint usage.",
            "Map and trajectories are synthetic for fast reproducibility.",
            "No Kalman/tracking component is used in this script.",
        ],
    }

    with open(output_log, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    print("HiVT simple visualization demo completed")
    print(f"figure: {output_figure}")
    print(f"log: {output_log}")


if __name__ == "__main__":
    main()
