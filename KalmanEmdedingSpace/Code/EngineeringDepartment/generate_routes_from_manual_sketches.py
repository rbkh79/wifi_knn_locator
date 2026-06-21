from __future__ import annotations

import argparse
import csv
import json
import sqlite3
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
import numpy as np

from route_proposal_workflow import (
    DB_PATH,
    OUT_DIR,
    draw_route_image,
    init_db,
    load_corridors,
    persist_proposals,
    sample_polyline,
    write_summary_md,
    xy_to_lonlat,
)

SKETCH_DIR = OUT_DIR / "sketch_generated"
SKETCH_JSON = SKETCH_DIR / "sketch_generated_routes.json"
SKETCH_CSV = SKETCH_DIR / "sketch_generated_routes.csv"
SKETCH_SUMMARY = SKETCH_DIR / "sketch_generated_routes_summary.md"
SKETCH_IMG_DIR = SKETCH_DIR / "route_images"
SKETCH_CONTACT_SHEET = SKETCH_DIR / "sketch_generated_contact_sheet.png"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate GeoJSON-guided routes from manual sketches")
    parser.add_argument("--db-path", type=Path, default=DB_PATH)
    parser.add_argument("--import-to-proposals", action="store_true", help="Insert generated routes into route_proposals")
    return parser.parse_args()


def load_manual_routes(db_path: Path) -> list[dict[str, Any]]:
    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    cur = con.cursor()

    cur.execute("SELECT route_id FROM manual_routes ORDER BY route_id")
    route_ids = [row[0] for row in cur.fetchall()]

    out: list[dict[str, Any]] = []
    for rid in route_ids:
        cur.execute(
            """
            SELECT point_idx, x_m, y_m
            FROM manual_route_points
            WHERE route_id = ?
            ORDER BY point_idx
            """,
            (rid,),
        )
        rows = cur.fetchall()
        if not rows:
            continue
        pts = np.array([[float(r["x_m"]), float(r["y_m"])] for r in rows], dtype=float)
        out.append({"manual_route_id": rid, "points_xy": pts})

    con.close()
    return out


def segment_projection_and_distance(point: np.ndarray, a: np.ndarray, b: np.ndarray) -> tuple[np.ndarray, float]:
    ab = b - a
    denom = float(np.dot(ab, ab))
    if denom < 1e-9:
        proj = a.copy()
        return proj, float(np.linalg.norm(point - proj))
    t = float(np.dot(point - a, ab) / denom)
    t = max(0.0, min(1.0, t))
    proj = a + t * ab
    dist = float(np.linalg.norm(point - proj))
    return proj, dist


def corridor_axis_segment(corridor) -> tuple[np.ndarray, np.ndarray]:
    half = max(4.0, 0.48 * corridor.length_m)
    a = corridor.center - corridor.axis * half
    b = corridor.center + corridor.axis * half
    return a, b


def snap_points_to_geojson(points_xy: np.ndarray, corridors: list[Any]) -> tuple[np.ndarray, list[str], list[str]]:
    snapped: list[np.ndarray] = []
    corridor_seq: list[str] = []
    level_seq: list[str] = []

    axis_cache = [(c, *corridor_axis_segment(c)) for c in corridors]

    for p in points_xy:
        best_proj = p
        best_corridor = axis_cache[0][0]
        best_dist = float("inf")

        for c, a, b in axis_cache:
            proj, d = segment_projection_and_distance(p, a, b)
            if d < best_dist:
                best_dist = d
                best_proj = proj
                best_corridor = c

        snapped.append(best_proj)
        corridor_seq.append(best_corridor.corridor_id)
        level_seq.append(best_corridor.level)

    return np.vstack(snapped), corridor_seq, level_seq


def unique_preserve_order(items: list[str]) -> list[str]:
    seen = set()
    out: list[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        out.append(item)
    return out


def compress_consecutive(items: list[str]) -> list[str]:
    if not items:
        return []
    out = [items[0]]
    for x in items[1:]:
        if x != out[-1]:
            out.append(x)
    return out


def next_generated_id(existing_ids: set[str], idx: int) -> str:
    while True:
        rid = f"G{idx:03d}"
        if rid not in existing_ids:
            return rid
        idx += 1


def export_csv(proposals: list[dict[str, Any]], csv_path: Path) -> None:
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "route_id",
        "source_manual_route",
        "category",
        "level_scope",
        "corridor_ids",
        "requires_manual_transition",
        "description",
    ]
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for p in proposals:
            writer.writerow(
                {
                    "route_id": p["route_id"],
                    "source_manual_route": p.get("source_manual_route", ""),
                    "category": p["category"],
                    "level_scope": "|".join(p["level_scope"]),
                    "corridor_ids": "|".join(p["corridor_ids"]),
                    "requires_manual_transition": int(p["requires_manual_transition"]),
                    "description": p["description"],
                }
            )


def build_contact_sheet(image_paths: list[Path], out_path: Path) -> None:
    if not image_paths:
        return

    cols = 3
    rows = int(np.ceil(len(image_paths) / cols))
    fig, axes = plt.subplots(rows, cols, figsize=(15, 4 * rows), dpi=160)
    axes_arr = np.array(axes).reshape(-1)

    for ax, img_path in zip(axes_arr, image_paths):
        img = plt.imread(img_path)
        ax.imshow(img)
        ax.set_title(img_path.stem, fontsize=9)
        ax.axis("off")

    for ax in axes_arr[len(image_paths) :]:
        ax.axis("off")

    fig.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)


def main() -> None:
    args = parse_args()

    corridors, lon0, lat0 = load_corridors()
    manual_routes = load_manual_routes(args.db_path)
    if not manual_routes:
        raise RuntimeError("No manual routes found. Draw and approve routes first.")

    SKETCH_DIR.mkdir(parents=True, exist_ok=True)
    SKETCH_IMG_DIR.mkdir(parents=True, exist_ok=True)

    existing_ids: set[str] = set()
    if args.import_to_proposals:
        init_db(args.db_path)
        con = sqlite3.connect(args.db_path)
        cur = con.cursor()
        cur.execute("SELECT route_id FROM route_proposals")
        existing_ids = {row[0] for row in cur.fetchall()}
        con.close()

    proposals: list[dict[str, Any]] = []
    new_idx = 1

    for mr in manual_routes:
        raw = mr["points_xy"]
        snapped_xy, corridor_seq_raw, level_seq_raw = snap_points_to_geojson(raw, corridors)
        sampled_xy = sample_polyline(snapped_xy, 50)
        sampled_ll = xy_to_lonlat(sampled_xy, lon0, lat0)

        corridor_seq = compress_consecutive(corridor_seq_raw)
        level_scope = unique_preserve_order(compress_consecutive(level_seq_raw))

        rid = next_generated_id(existing_ids, new_idx)
        existing_ids.add(rid)
        new_idx += 1

        proposal = {
            "route_id": rid,
            "source_manual_route": mr["manual_route_id"],
            "category": "manual_sketch_geojson_guided",
            "level_scope": level_scope,
            "corridor_ids": corridor_seq,
            "validation": "manual_sketch_snapped_to_geojson",
            "requires_manual_transition": len(set(level_scope)) > 1,
            "description": f"generated from manual sketch {mr['manual_route_id']} and snapped to nearest GeoJSON corridors",
            "points_xy": sampled_xy.tolist(),
            "points_lonlat": sampled_ll.tolist(),
        }
        proposals.append(proposal)

    for p in proposals:
        image_path = SKETCH_IMG_DIR / f"{p['route_id']}__from_{p['source_manual_route']}.png"
        draw_route_image(corridors, p, image_path)

    with open(SKETCH_JSON, "w", encoding="utf-8") as f:
        json.dump(
            {
                "note": "Routes generated from approved manual sketches and GeoJSON corridor guidance",
                "count": len(proposals),
                "proposals": proposals,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )

    export_csv(proposals, SKETCH_CSV)
    write_summary_md(proposals, SKETCH_SUMMARY)

    image_paths = sorted(SKETCH_IMG_DIR.glob("*.png"))
    build_contact_sheet(image_paths, SKETCH_CONTACT_SHEET)

    if args.import_to_proposals:
        persist_proposals(args.db_path, proposals)

    print("Generated routes from manual sketches")
    print(f"manual input count: {len(manual_routes)}")
    print(f"generated routes: {len(proposals)}")
    print(f"json: {SKETCH_JSON}")
    print(f"csv: {SKETCH_CSV}")
    print(f"summary: {SKETCH_SUMMARY}")
    print(f"images: {SKETCH_IMG_DIR}")
    print(f"contact_sheet: {SKETCH_CONTACT_SHEET}")
    if args.import_to_proposals:
        print("Imported into route_proposals table with pending status")


if __name__ == "__main__":
    main()
