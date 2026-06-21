from __future__ import annotations

import argparse
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Simple HiVT loader: load checkpoint, freeze model, print model info."
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
        "--device",
        type=str,
        default="cpu",
        choices=["cpu", "cuda"],
        help="Device for checkpoint loading.",
    )
    parser.add_argument(
        "--parallel",
        action="store_true",
        help="Set HiVT parallel=True when loading from checkpoint.",
    )
    return parser.parse_args()


def ensure_paths(hivt_root: Path, ckpt_path: Path) -> tuple[Path, Path]:
    script_dir = Path(__file__).resolve().parent
    resolved_hivt_root = (script_dir / hivt_root).resolve() if not hivt_root.is_absolute() else hivt_root
    resolved_ckpt_path = (script_dir / ckpt_path).resolve() if not ckpt_path.is_absolute() else ckpt_path

    if not resolved_hivt_root.exists():
        raise FileNotFoundError(f"HiVT root not found: {resolved_hivt_root}")
    if not (resolved_hivt_root / "models" / "hivt.py").exists():
        raise FileNotFoundError(
            f"Invalid HiVT root (models/hivt.py missing): {resolved_hivt_root}"
        )
    if not resolved_ckpt_path.exists():
        raise FileNotFoundError(f"Checkpoint not found: {resolved_ckpt_path}")

    return resolved_hivt_root, resolved_ckpt_path


def load_hivt_model(hivt_root: Path, ckpt_path: Path, device: str, parallel: bool):
    # HiVT repository uses absolute imports like 'from models import ...',
    # so we add cloned repo root into sys.path before importing HiVT.
    sys.path.insert(0, str(hivt_root))

    import pytorch_lightning as pl
    import torch
    from models.hivt import HiVT

    pl.seed_everything(2022)

    map_location = torch.device(device)
    model = HiVT.load_from_checkpoint(
        checkpoint_path=str(ckpt_path),
        parallel=parallel,
        map_location=map_location,
    )

    for p in model.parameters():
        p.requires_grad = False
    model.eval()

    return model


def main() -> None:
    args = parse_args()
    hivt_root, ckpt_path = ensure_paths(args.hivt_root, args.ckpt_path)
    model = load_hivt_model(
        hivt_root=hivt_root,
        ckpt_path=ckpt_path,
        device=args.device,
        parallel=args.parallel,
    )

    total_params = sum(p.numel() for p in model.parameters())
    trainable_params = sum(p.numel() for p in model.parameters() if p.requires_grad)

    print("HiVT model loaded successfully")
    print(f"hivt_root: {hivt_root}")
    print(f"checkpoint: {ckpt_path}")
    print(f"class: {model.__class__.__name__}")
    print(f"historical_steps: {model.hparams.historical_steps}")
    print(f"future_steps: {model.hparams.future_steps}")
    print(f"embed_dim: {model.hparams.embed_dim}")
    print(f"num_modes: {model.hparams.num_modes}")
    print(f"total_params: {total_params}")
    print(f"trainable_params_after_freeze: {trainable_params}")


if __name__ == "__main__":
    main()
