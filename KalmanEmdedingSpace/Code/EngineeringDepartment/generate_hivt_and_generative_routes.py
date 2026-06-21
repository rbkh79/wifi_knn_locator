from __future__ import annotations

import argparse
import csv
import json
import math
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
import numpy as np

from route_proposal_workflow import (
    DB_PATH,
    OUT_DIR,
    corridor_family,
    draw_route_image,
    load_corridors,
    log_review,
    numeric_level,
    persist_proposals,
    sample_polyline,
    xy_to_lonlat,
)

HIST_STEPS = 20
FUTURE_STEPS = 30
TOTAL_STEPS = HIST_STEPS + FUTURE_STEPS
RADIUS_M = 35.0

GEN_DIR = OUT_DIR / "generative_from_sketch"
GEN_JSON = GEN_DIR / "generative_routes.json"
GEN_CSV = GEN_DIR / "generative_routes.csv"
GEN_SUMMARY_MD = GEN_DIR / "generative_summary.md"
GEN_IMG_DIR = GEN_DIR / "route_images"
GEN_CONTACT_SHEET = GEN_DIR / "generative_contact_sheet.png"

HIVT_DIR = OUT_DIR / "hivt_from_sketch"
HIVT_SCENES_DIR = HIVT_DIR / "scenes"
HIVT_MANIFEST = HIVT_DIR / "hivt_manifest.json"
HIVT_CHECKPOINTS_CSV = HIVT_DIR / "route_checkpoints.csv"
HIVT_STRUCTURE_MD = HIVT_DIR / "HIVT_INPUT_STRUCTURE.md"


@dataclass
class RouteRecord:
    route_id: str
    category: str
    level_scope: list[str]
    corridor_ids: list[str]
    points_xy: np.ndarray
    source_manual_route: str | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate compositional/inter-floor routes and HiVT-ready scenes")
    parser.add_argument("--db-path", type=Path, default=DB_PATH)
    parser.add_argument("--max-composed", type=int, default=28)
    parser.add_argument("--scene-size", type=int, default=8)
    parser.add_argument("--skip-import", action="store_true", help="Do not import generated routes into route_proposals")
    parser.add_argument("--skip-approve-g", action="store_true", help="Do not auto-approve G001..G020")
    return parser.parse_args()


def parse_level(level: str) -> float | None:
    try:
        return float(level)
    except ValueError:
        return None


def level_to_str(v: float) -> str:
    if abs(v - round(v)) < 1e-9:
        return str(int(round(v)))
    txt = f"{v:.3f}".rstrip("0").rstrip(".")
    return txt


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


def next_id(existing: set[str], prefix: str, start: int) -> tuple[str, int]:
    idx = start
    while True:
        rid = f"{prefix}{idx:03d}"
        if rid not in existing:
            existing.add(rid)
            return rid, idx + 1
        idx += 1


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


def snap_points_to_corridors(points_xy: np.ndarray, corridors: list[Any]) -> tuple[np.ndarray, list[str], list[str]]:
    snapped: list[np.ndarray] = []
    corridor_ids: list[str] = []
    levels: list[str] = []

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
        corridor_ids.append(best_corridor.corridor_id)
        levels.append(best_corridor.level)

    return np.vstack(snapped), compress_consecutive(corridor_ids), unique_preserve_order(compress_consecutive(levels))


def load_route_points(cur: sqlite3.Cursor, route_id: str) -> np.ndarray:
    cur.execute(
        """
        SELECT point_idx, x_m, y_m
        FROM route_points
        WHERE route_id = ?
        ORDER BY point_idx
        """,
        (route_id,),
    )
    rows = cur.fetchall()
    if not rows:
        return np.zeros((0, 2), dtype=float)
    return np.array([[float(r[1]), float(r[2])] for r in rows], dtype=float)


def source_manual_from_description(desc: str) -> str | None:
    marker = "manual sketch "
    i = desc.find(marker)
    if i < 0:
        return None
    tail = desc[i + len(marker) :]
    token = tail.split(" ", 1)[0].strip()
    if token.startswith("M"):
        return token
    return None


def load_approved_g_routes(db_path: Path) -> list[RouteRecord]:
    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    cur = con.cursor()

    cur.execute(
        """
        SELECT route_id, category, level_scope, corridor_ids, description
        FROM route_proposals
        WHERE route_id LIKE 'G%' AND status = 'approved'
        ORDER BY route_id
        """
    )

    out: list[RouteRecord] = []
    for row in cur.fetchall():
        rid = str(row["route_id"])
        pts = load_route_points(cur, rid)
        if pts.shape[0] == 0:
            continue
        out.append(
            RouteRecord(
                route_id=rid,
                category=str(row["category"]),
                level_scope=list(json.loads(row["level_scope"])),
                corridor_ids=list(json.loads(row["corridor_ids"])),
                points_xy=pts,
                source_manual_route=source_manual_from_description(str(row["description"])),
            )
        )

    con.close()
    return out


def approve_all_g_routes(db_path: Path) -> None:
    for i in range(1, 21):
        rid = f"G{i:03d}"
        log_review(db_path, rid, "approve", "user-confirmed good")


def generate_piece_composed_routes(
    approved_routes: list[RouteRecord],
    corridors: list[Any],
    existing_ids: set[str],
    max_composed: int,
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    idx = 1
    signatures: set[tuple[int, ...]] = set()

    for i, ra in enumerate(approved_routes):
        for j, rb in enumerate(approved_routes):
            if i == j:
                continue
            pa = ra.points_xy
            pb = rb.points_xy
            if pa.shape[0] < 40 or pb.shape[0] < 40:
                continue

            a_mid = pa[29]
            b_mid = pb[20]
            if float(np.linalg.norm(a_mid - b_mid)) > 16.0:
                continue

            bridge = np.vstack([a_mid, (a_mid + b_mid) * 0.5, b_mid])
            raw = np.vstack([pa[:30], bridge[1:], pb[21:]])
            sampled = sample_polyline(raw, 50)
            snapped, corridor_ids, level_scope = snap_points_to_corridors(sampled, corridors)
            sampled = sample_polyline(snapped, 50)

            signature = tuple(hash(x) % 1_000_003 for x in corridor_ids[:12])
            if signature in signatures:
                continue
            signatures.add(signature)

            rid, idx = next_id(existing_ids, "C", idx)
            proposal = {
                "route_id": rid,
                "category": "manual_sketch_piece_composed",
                "level_scope": level_scope,
                "corridor_ids": corridor_ids,
                "validation": "composed_from_approved_sketch_segments",
                "requires_manual_transition": len(set(level_scope)) > 1,
                "description": f"composed from {ra.route_id} front segment and {rb.route_id} tail segment",
                "points_xy": sampled.tolist(),
            }
            out.append(proposal)

            if len(out) >= max_composed:
                return out

    return out


def generate_level_shift_routes(
    approved_routes: list[RouteRecord],
    corridors: list[Any],
    existing_ids: set[str],
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    idx = 1

    corridor_by_id = {c.corridor_id: c for c in corridors}
    by_level: dict[str, list[Any]] = {}
    by_level_family: dict[str, dict[str, list[Any]]] = {}
    for c in corridors:
        by_level.setdefault(c.level, []).append(c)
        fam = corridor_family(c.name)
        if fam:
            by_level_family.setdefault(c.level, {}).setdefault(fam, []).append(c)

    for level in by_level:
        by_level[level] = sorted(by_level[level], key=lambda x: x.length_m, reverse=True)
    for level in by_level_family:
        for fam in by_level_family[level]:
            by_level_family[level][fam] = sorted(by_level_family[level][fam], key=lambda x: x.length_m, reverse=True)

    available = {parse_level(level): level for level in by_level.keys()}

    for route in approved_routes:
        if not route.corridor_ids:
            continue

        for delta in (-1.0, 1.0):
            target_corridors: list[Any] = []
            prev_center: np.ndarray | None = None
            ok = True

            for cid in route.corridor_ids:
                orig = corridor_by_id.get(cid)
                if orig is None:
                    ok = False
                    break
                lv = parse_level(orig.level)
                if lv is None:
                    ok = False
                    break
                target_lv_num = lv + delta
                if target_lv_num not in available:
                    ok = False
                    break
                target_level = available[target_lv_num]

                fam = corridor_family(orig.name)
                candidates = by_level_family.get(target_level, {}).get(fam, []) if fam else []
                if not candidates:
                    candidates = by_level[target_level]
                if not candidates:
                    ok = False
                    break

                if prev_center is None:
                    pick = candidates[0]
                else:
                    pick = min(candidates, key=lambda c: float(np.linalg.norm(c.center - prev_center)))

                target_corridors.append(pick)
                prev_center = pick.center

            if not ok or len(target_corridors) < 2:
                continue

            waypoints: list[np.ndarray] = []
            first = target_corridors[0]
            last = target_corridors[-1]
            waypoints.append(first.center - first.axis * min(14.0, 0.32 * first.length_m))
            for c in target_corridors:
                waypoints.append(c.center)
            waypoints.append(last.center + last.axis * min(14.0, 0.32 * last.length_m))

            raw = np.vstack(waypoints)
            sampled = sample_polyline(raw, 50)
            _, corridor_ids, level_scope = snap_points_to_corridors(sampled, corridors)

            rid, idx = next_id(existing_ids, "T", idx)
            proposal = {
                "route_id": rid,
                "category": "manual_sketch_inter_floor_transfer",
                "level_scope": level_scope,
                "corridor_ids": corridor_ids,
                "validation": "shifted_from_approved_sketch_level_pattern",
                "requires_manual_transition": len(set(level_scope)) > 1,
                "description": f"inter-floor transfer from {route.route_id} with level shift {delta:+.0f}",
                "points_xy": sampled.tolist(),
            }
            out.append(proposal)

    return out


def finalize_proposals(proposals_xy: list[dict[str, Any]], lon0: float, lat0: float) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for p in proposals_xy:
        pts_xy = np.asarray(p["points_xy"], dtype=float)
        pts_xy = sample_polyline(pts_xy, 50)
        pts_ll = xy_to_lonlat(pts_xy, lon0, lat0)
        q = dict(p)
        q["points_xy"] = pts_xy.tolist()
        q["points_lonlat"] = pts_ll.tolist()
        out.append(q)
    return out


def export_generative_outputs(proposals: list[dict[str, Any]]) -> None:
    GEN_DIR.mkdir(parents=True, exist_ok=True)

    with open(GEN_JSON, "w", encoding="utf-8") as f:
        json.dump(
            {
                "note": "Generative routes from approved manual sketches",
                "count": len(proposals),
                "routes": proposals,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )

    with open(GEN_CSV, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["route_id", "category", "level_scope", "corridor_ids", "requires_manual_transition", "description"])
        for p in proposals:
            w.writerow(
                [
                    p["route_id"],
                    p["category"],
                    "|".join(p["level_scope"]),
                    "|".join(p["corridor_ids"]),
                    int(p["requires_manual_transition"]),
                    p["description"],
                ]
            )

    with open(GEN_SUMMARY_MD, "w", encoding="utf-8") as f:
        f.write("# Generative Routes from Approved Sketches\n\n")
        categories = sorted({p["category"] for p in proposals})
        f.write("## Categories\n\n")
        for c in categories:
            f.write(f"- {c}\n")
        f.write("\n## Routes\n\n")
        for p in proposals:
            f.write(
                f"- {p['route_id']} | {p['category']} | levels={','.join(p['level_scope'])} | "
                f"manual_transition={p['requires_manual_transition']}\n"
            )


def export_generative_images(corridors: list[Any], proposals: list[dict[str, Any]]) -> None:
    GEN_IMG_DIR.mkdir(parents=True, exist_ok=True)

    img_paths: list[Path] = []
    for p in proposals:
        img_path = GEN_IMG_DIR / f"{p['route_id']}__{p['category']}__L{'-'.join(p['level_scope'])}.png"
        draw_route_image(corridors, p, img_path)
        img_paths.append(img_path)

    if not img_paths:
        return

    cols = 4
    rows = int(math.ceil(len(img_paths) / cols))
    fig, axes = plt.subplots(rows, cols, figsize=(4.4 * cols, 3.2 * rows), dpi=150)
    axes_arr = np.array(axes).reshape(-1)

    for ax, path in zip(axes_arr, img_paths):
        img = plt.imread(path)
        ax.imshow(img)
        ax.set_title(path.stem[:52], fontsize=8)
        ax.axis("off")

    for ax in axes_arr[len(img_paths):]:
        ax.axis("off")

    fig.tight_layout()
    fig.savefig(GEN_CONTACT_SHEET, bbox_inches="tight")
    plt.close(fig)


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


def build_hivt_scene_arrays(positions: np.ndarray, lane_segments: np.ndarray) -> dict[str, np.ndarray]:
    n = int(positions.shape[0])

    x_hist = positions[:, :HIST_STEPS, :].copy()
    x_hist[:, 1:, :] = x_hist[:, 1:, :] - x_hist[:, :-1, :]
    x_hist[:, 0, :] = 0.0

    y_future = positions[:, HIST_STEPS:, :] - positions[:, HIST_STEPS - 1 : HIST_STEPS, :]

    padding_mask = np.zeros((n, TOTAL_STEPS), dtype=bool)
    bos_mask = np.zeros((n, HIST_STEPS), dtype=bool)
    bos_mask[:, 0] = True

    rotate_angles = np.arctan2(
        positions[:, HIST_STEPS - 1, 1] - positions[:, HIST_STEPS - 2, 1],
        positions[:, HIST_STEPS - 1, 0] - positions[:, HIST_STEPS - 2, 0],
    )

    if lane_segments.size == 0:
        lane_vectors = np.zeros((0, 2), dtype=float)
        lane_positions = np.zeros((0, 2), dtype=float)
    else:
        lane_positions = lane_segments[:, 0, :]
        lane_vectors = lane_segments[:, 1, :]

    actor_pos_t = positions[:, HIST_STEPS - 1, :]

    pairs: list[list[int]] = []
    vecs: list[np.ndarray] = []
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

    return {
        "x": x_hist.astype(np.float32),
        "positions": positions.astype(np.float32),
        "y": y_future.astype(np.float32),
        "num_nodes": np.asarray([n], dtype=np.int64),
        "padding_mask": padding_mask,
        "bos_mask": bos_mask,
        "rotate_angles": rotate_angles.astype(np.float32),
        "lane_vectors": lane_vectors.astype(np.float32),
        "lane_actor_index": lane_actor_index,
        "lane_actor_vectors": lane_actor_vectors.astype(np.float32),
        "agent_index": np.asarray([0], dtype=np.int64),
        "av_index": np.asarray([0], dtype=np.int64),
    }


def export_hivt_inputs(all_routes: list[dict[str, Any]], corridors: list[Any], scene_size: int) -> None:
    HIVT_SCENES_DIR.mkdir(parents=True, exist_ok=True)

    lane_map = build_lane_segments(corridors)

    by_level: dict[str, list[dict[str, Any]]] = {}
    for p in all_routes:
        lv = p["level_scope"][0] if p["level_scope"] else "unknown"
        by_level.setdefault(lv, []).append(p)

    manifest: dict[str, Any] = {
        "format": "hivt_like_npz_per_scene",
        "history_steps": HIST_STEPS,
        "future_steps": FUTURE_STEPS,
        "total_steps": TOTAL_STEPS,
        "radius_m": RADIUS_M,
        "required_tensors": {
            "x": "[N,20,2] history offsets",
            "positions": "[N,50,2] absolute xy",
            "y": "[N,30,2] future offsets from t=19",
            "padding_mask": "[N,50] bool",
            "bos_mask": "[N,20] bool",
            "rotate_angles": "[N] rad",
            "lane_vectors": "[L,2]",
            "lane_actor_index": "[2,E] long",
            "lane_actor_vectors": "[E,2]",
            "agent_index": "[1]",
            "av_index": "[1]",
        },
        "scenes": [],
    }

    checkpoints_rows: list[list[Any]] = []
    scene_idx = 0

    for level in sorted(by_level.keys(), key=numeric_level):
        routes = by_level[level]
        lane_segments = lane_map.get(level, np.zeros((0, 2, 2), dtype=float))

        for i in range(0, len(routes), scene_size):
            chunk = routes[i : i + scene_size]
            positions = np.stack([np.asarray(r["points_xy"], dtype=float) for r in chunk], axis=0)
            arrays = build_hivt_scene_arrays(positions, lane_segments)

            scene_name = f"scene_{scene_idx:03d}_level_{level}.npz"
            scene_path = HIVT_SCENES_DIR / scene_name
            np.savez(scene_path, **arrays)

            manifest["scenes"].append(
                {
                    "scene_id": scene_idx,
                    "level_anchor": level,
                    "file": scene_name,
                    "num_nodes": int(arrays["num_nodes"][0]),
                    "num_lane_vectors": int(arrays["lane_vectors"].shape[0]),
                    "num_lane_actor_edges": int(arrays["lane_actor_index"].shape[1]),
                    "routes": [r["route_id"] for r in chunk],
                }
            )

            checkpoint_idx = [0, 10, 20, 30, 40, 49]
            for r in chunk:
                pts = np.asarray(r["points_xy"], dtype=float)
                for k in checkpoint_idx:
                    checkpoints_rows.append([
                        r["route_id"],
                        k,
                        float(pts[k, 0]),
                        float(pts[k, 1]),
                        ",".join(r["level_scope"]),
                        r["category"],
                    ])

            scene_idx += 1

    with open(HIVT_MANIFEST, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    with open(HIVT_CHECKPOINTS_CSV, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["route_id", "checkpoint_idx", "x_m", "y_m", "level_scope", "category"])
        w.writerows(checkpoints_rows)

    with open(HIVT_STRUCTURE_MD, "w", encoding="utf-8") as f:
        f.write("# HiVT Input Structure (From Approved Sketch + GeoJSON)\n\n")
        f.write("این خروجی دقیقا داده‌های لازم برای `TemporalData` در HiVT را تولید می‌کند.\n\n")
        f.write("## Required Tensors\n\n")
        for key, desc in manifest["required_tensors"].items():
            f.write(f"- {key}: {desc}\n")
        f.write("\n## Checkpoints\n\n")
        f.write("- checkpointها در `route_checkpoints.csv` ذخیره می‌شوند (اندیس‌های 0,10,20,30,40,49).\n")
        f.write("- این checkpointها برای گزارش مقاله، مقایسه مسیرها و کنترل کیفیت قابل استفاده هستند.\n")
        f.write("\n## Scene Files\n\n")
        f.write(f"- scene npz directory: {HIVT_SCENES_DIR}\n")
        f.write(f"- manifest: {HIVT_MANIFEST}\n")


def main() -> None:
    args = parse_args()

    if not args.skip_approve_g:
        approve_all_g_routes(args.db_path)

    corridors, lon0, lat0 = load_corridors()
    approved = load_approved_g_routes(args.db_path)
    if not approved:
        raise RuntimeError("No approved G routes found in route_proposals.")

    existing_ids = {r.route_id for r in approved}

    composed = generate_piece_composed_routes(approved, corridors, existing_ids, args.max_composed)
    transferred = generate_level_shift_routes(approved, corridors, existing_ids)

    proposals_xy = composed + transferred
    proposals = finalize_proposals(proposals_xy, lon0, lat0)

    if not args.skip_import and proposals:
        persist_proposals(args.db_path, proposals)

    export_generative_outputs(proposals)
    export_generative_images(corridors, proposals)

    approved_as_dict: list[dict[str, Any]] = []
    for r in approved:
        approved_as_dict.append(
            {
                "route_id": r.route_id,
                "category": r.category,
                "level_scope": r.level_scope,
                "corridor_ids": r.corridor_ids,
                "points_xy": r.points_xy.tolist(),
            }
        )

    export_hivt_inputs(approved_as_dict + proposals, corridors, args.scene_size)

    print("Approved G routes are kept in DB")
    print(f"approved_G_count: {len(approved)}")
    print(f"generated_piece_composed: {len(composed)}")
    print(f"generated_inter_floor_transfer: {len(transferred)}")
    print(f"generated_total: {len(proposals)}")
    print(f"generative_json: {GEN_JSON}")
    print(f"generative_images: {GEN_IMG_DIR}")
    print(f"generative_contact_sheet: {GEN_CONTACT_SHEET}")
    print(f"hivt_manifest: {HIVT_MANIFEST}")
    print(f"hivt_structure_doc: {HIVT_STRUCTURE_MD}")


if __name__ == "__main__":
    main()
