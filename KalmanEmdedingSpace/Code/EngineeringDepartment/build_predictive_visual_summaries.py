from __future__ import annotations

import json
import math
from pathlib import Path

import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent
PRED_DIR = ROOT / "derived" / "route_workflow" / "predictive_embedding_demo"
JSON_PATH = PRED_DIR / "predictive_cases.json"
OUT_DIR = PRED_DIR / "summaries"


def render_sheet(cases: list[dict], out_path: Path, title: str, cols: int = 4) -> None:
    if not cases:
        return

    paths = [Path(c["image"]) for c in cases if Path(c["image"]).exists()]
    if not paths:
        return

    rows = int(math.ceil(len(paths) / cols))
    fig, axes = plt.subplots(rows, cols, figsize=(4.2 * cols, 3.2 * rows), dpi=150)
    axes_arr = axes.ravel() if hasattr(axes, "ravel") else [axes]

    for ax, case, p in zip(axes_arr, cases, paths):
        img = plt.imread(p)
        ax.imshow(img)
        ax.set_title(f"{case['route_id']} | FDE={case['fde']:.1f}", fontsize=8)
        ax.axis("off")

    for ax in axes_arr[len(paths) :]:
        ax.axis("off")

    fig.suptitle(title, fontsize=12)
    fig.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)


def main() -> None:
    payload = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    cases = payload["cases"]

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for obs in [12, 16, 20]:
        sub = [c for c in cases if int(c["obs_length"]) == obs]
        sub_sorted = sorted(sub, key=lambda c: (c["route_id"], c["fde"]))
        render_sheet(sub_sorted, OUT_DIR / f"obs{obs}_all.png", f"All Cases | obs={obs}")

    by_fde = sorted(cases, key=lambda c: float(c["fde"]))
    render_sheet(by_fde[:24], OUT_DIR / "best24_by_fde.png", "Best 24 Cases by FDE", cols=6)
    render_sheet(by_fde[-24:], OUT_DIR / "worst24_by_fde.png", "Worst 24 Cases by FDE", cols=6)

    with open(OUT_DIR / "summary_stats.md", "w", encoding="utf-8") as f:
        f.write("# Predictive Visual Summary\n\n")
        f.write(f"- total_cases: {len(cases)}\n")
        f.write(f"- mean_ADE: {sum(c['ade'] for c in cases)/len(cases):.4f}\n")
        f.write(f"- mean_FDE: {sum(c['fde'] for c in cases)/len(cases):.4f}\n")
        for obs in [12, 16, 20]:
            sub = [c for c in cases if int(c['obs_length']) == obs]
            if not sub:
                continue
            f.write(f"- obs={obs}: mean_ADE={sum(c['ade'] for c in sub)/len(sub):.4f}, mean_FDE={sum(c['fde'] for c in sub)/len(sub):.4f}\n")

    print("visual summaries generated")
    print(f"out_dir: {OUT_DIR}")


if __name__ == "__main__":
    main()
