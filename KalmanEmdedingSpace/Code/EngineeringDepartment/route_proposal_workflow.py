from __future__ import annotations

import argparse
import csv
import json
import math
import sqlite3
import shutil
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
import numpy as np


ROOT_DIR = Path(__file__).resolve().parent
GEOJSON_DIR = ROOT_DIR / "GeoJSON"
OUT_DIR = ROOT_DIR / "derived" / "route_workflow"
DB_PATH = OUT_DIR / "routes_workflow.db"
PROPOSALS_JSON = OUT_DIR / "route_proposals_stage1.json"
PROPOSALS_CSV = OUT_DIR / "route_proposals_stage1.csv"
PREVIEW_PNG = OUT_DIR / "route_proposals_stage1_preview.png"
SUMMARY_MD = OUT_DIR / "route_proposals_stage1_summary.md"
ROUTE_IMG_DIR = OUT_DIR / "route_images"


@dataclass
class Corridor:
    corridor_id: str
    level: str
    name: str | None
    ring_lonlat: np.ndarray
    ring_xy: np.ndarray
    center: np.ndarray
    axis: np.ndarray
    length_m: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Modular route proposal + review workflow")
    parser.add_argument(
        "--action",
        choices=["propose", "review", "decide", "list-approved", "status", "purge-wrong", "purge-routes"],
        default="propose",
    )
    parser.add_argument("--route-id", type=str, help="Route ID for decide action")
    parser.add_argument("--route-ids", type=str, default="", help="Comma-separated route ids for purge-routes action")
    parser.add_argument("--decision", choices=["approve", "reject", "comment", "skip"], help="Decision for decide action")
    parser.add_argument("--comment", type=str, default="", help="Comment for decide action")
    parser.add_argument("--delete-images", action="store_true", help="Delete per-route images when purging routes")
    parser.add_argument("--include-non-pending", action="store_true", help="Review all routes, not only pending")
    return parser.parse_args()


def lonlat_to_xy(lonlat: np.ndarray, lon0: float, lat0: float) -> np.ndarray:
    lon = lonlat[:, 0]
    lat = lonlat[:, 1]
    x = (lon - lon0) * 111_320.0 * math.cos(math.radians(lat0))
    y = (lat - lat0) * 110_540.0
    return np.stack([x, y], axis=1)


def xy_to_lonlat(xy: np.ndarray, lon0: float, lat0: float) -> np.ndarray:
    lon = xy[:, 0] / (111_320.0 * math.cos(math.radians(lat0))) + lon0
    lat = xy[:, 1] / 110_540.0 + lat0
    return np.stack([lon, lat], axis=1)


def principal_axis(points_xy: np.ndarray) -> tuple[np.ndarray, np.ndarray, float]:
    pts = points_xy[:-1] if np.allclose(points_xy[0], points_xy[-1]) else points_xy
    center = np.mean(pts, axis=0)
    centered = pts - center
    cov = centered.T @ centered / max(1, len(centered) - 1)
    eigvals, eigvecs = np.linalg.eigh(cov)
    major = eigvecs[:, np.argmax(eigvals)]
    major = major / (np.linalg.norm(major) + 1e-9)
    proj = centered @ major
    length = float(np.max(proj) - np.min(proj))
    return center, major, max(length, 1.0)


def corridor_family(name: str | None) -> str | None:
    if not name:
        return None
    parts = name.rsplit(" ", 1)
    if len(parts) == 2 and parts[1].isdigit():
        return parts[0]
    return name


def load_corridors() -> tuple[list[Corridor], float, float]:
    features: list[tuple[str, str | None, np.ndarray]] = []
    lon_all: list[float] = []
    lat_all: list[float] = []

    for path in sorted(GEOJSON_DIR.glob("indoor_level_*.geojson")):
        with open(path, "r", encoding="utf-8") as f:
            payload = json.load(f)
        for feat in payload.get("features", []):
            props = feat.get("properties", {})
            if props.get("indoor") != "corridor":
                continue
            geom = feat.get("geometry", {})
            g_type = geom.get("type")
            coords = geom.get("coordinates", [])
            level = str(props.get("level", "unknown"))
            name = props.get("name")

            rings: list[np.ndarray] = []
            if g_type == "Polygon" and coords:
                rings.append(np.asarray(coords[0], dtype=float))
            elif g_type == "MultiPolygon":
                for poly in coords:
                    if poly:
                        rings.append(np.asarray(poly[0], dtype=float))

            for ring in rings:
                if ring.shape[0] < 4:
                    continue
                features.append((level, name, ring))
                lon_all.extend(ring[:, 0].tolist())
                lat_all.extend(ring[:, 1].tolist())

    if not features:
        raise RuntimeError("No indoor=corridor polygons found in GeoJSON")

    lon0 = float(np.mean(lon_all))
    lat0 = float(np.mean(lat_all))

    corridors: list[Corridor] = []
    for i, (level, name, ring_ll) in enumerate(features):
        ring_xy = lonlat_to_xy(ring_ll, lon0, lat0)
        center, axis, length = principal_axis(ring_xy)
        corridors.append(
            Corridor(
                corridor_id=f"C{i:04d}",
                level=level,
                name=name,
                ring_lonlat=ring_ll,
                ring_xy=ring_xy,
                center=center,
                axis=axis,
                length_m=length,
            )
        )

    return corridors, lon0, lat0


def line_from_axis(center: np.ndarray, axis: np.ndarray, length: float, fraction: float) -> np.ndarray:
    half = 0.5 * length * fraction
    p0 = center - axis * half
    p1 = center + axis * half
    return np.stack([p0, p1], axis=0)


def sample_polyline(polyline: np.ndarray, n_points: int = 50) -> np.ndarray:
    if polyline.shape[0] < 2:
        return np.repeat(polyline[:1], n_points, axis=0)
    seg = polyline[1:] - polyline[:-1]
    seg_len = np.linalg.norm(seg, axis=1)
    cum = np.concatenate([[0.0], np.cumsum(seg_len)])
    total = float(cum[-1])
    if total < 1e-9:
        return np.repeat(polyline[:1], n_points, axis=0)
    tvals = np.linspace(0.0, total, n_points)
    out = np.zeros((n_points, 2), dtype=float)
    j = 0
    for i, t in enumerate(tvals):
        while j < len(seg_len) - 1 and cum[j + 1] < t:
            j += 1
        left, right = cum[j], cum[j + 1]
        alpha = 0.0 if right - left < 1e-9 else (t - left) / (right - left)
        out[i] = polyline[j] * (1 - alpha) + polyline[j + 1] * alpha
    return out


def numeric_level(level: str) -> float:
    try:
        return float(level)
    except ValueError:
        return 9999.0


def nearest_pair(a: list[Corridor], b: list[Corridor]) -> tuple[Corridor, Corridor]:
    best = (a[0], b[0])
    best_d = float("inf")
    for ca in a:
        for cb in b:
            d = float(np.linalg.norm(ca.center - cb.center))
            if d < best_d:
                best_d = d
                best = (ca, cb)
    return best


def build_multi_floor_chain_proposals(
    by_level: dict[str, list[Corridor]],
    lon0: float,
    lat0: float,
    start_idx: int,
    family_scores: Counter[str],
) -> tuple[list[dict[str, Any]], int]:
    proposals: list[dict[str, Any]] = []
    idx = start_idx

    candidate_chains = [
        ["0", "1", "2"],
    ]

    variant_offsets = [0, 1, 2]

    for chain in candidate_chains:
        if any(level not in by_level or len(by_level[level]) < 2 for level in chain):
            continue

        for variant_idx, offset in enumerate(variant_offsets):
            corridor_pairs = []
            for level in chain:
                ranked = sorted(
                    by_level[level],
                    key=lambda corridor: (
                        family_scores.get(corridor_family(corridor.name) or "", 0),
                        corridor.name is not None,
                        corridor.length_m,
                    ),
                    reverse=True,
                )
                if len(ranked) < 2:
                    break
                start = min(offset, max(0, len(ranked) - 2))
                pair = ranked[start : start + 2]
                if len(pair) < 2:
                    pair = ranked[:2]
                corridor_pairs.append((pair[0], pair[1]))
            if len(corridor_pairs) != len(chain):
                continue

            waypoints_xy: list[np.ndarray] = []
            for pair_idx, (c_a, c_b) in enumerate(corridor_pairs):
                lead = c_a.center - c_a.axis * min(18.0, 0.35 * c_a.length_m)
                trail = c_b.center + c_b.axis * min(18.0, 0.35 * c_b.length_m)
                if pair_idx == 0:
                    waypoints_xy.append(lead)
                waypoints_xy.append(c_a.center)
                waypoints_xy.append(c_b.center)
                if pair_idx == len(corridor_pairs) - 1:
                    waypoints_xy.append(trail)

            raw = np.vstack(waypoints_xy)
            pts_xy = sample_polyline(raw, 50)
            pts_ll = xy_to_lonlat(pts_xy, lon0, lat0)

            rid = f"R{idx:03d}"
            idx += 1
            proposals.append(
                {
                    "route_id": rid,
                    "category": f"multi_floor_multi_corridor_long_{'-'.join(chain)}_v{variant_idx + 1}",
                    "level_scope": chain,
                    "corridor_ids": [pair[0].corridor_id for pair in corridor_pairs] + [pair[1].corridor_id for pair in corridor_pairs],
                    "validation": "multi_floor_multi_corridor_chain",
                    "requires_manual_transition": True,
                    "description": f"long multi-floor route across repeated corridor families and levels: {' -> '.join(chain)} (variant {variant_idx + 1})",
                    "points_xy": pts_xy.tolist(),
                    "points_lonlat": pts_ll.tolist(),
                }
            )

    return proposals, idx


def build_proposals(corridors: list[Corridor], lon0: float, lat0: float) -> list[dict[str, Any]]:
    by_level: dict[str, list[Corridor]] = {}
    family_scores: Counter[str] = Counter()
    for c in corridors:
        by_level.setdefault(c.level, []).append(c)
        family = corridor_family(c.name)
        if family:
            family_scores[family] += 1
    for lv in by_level:
        by_level[lv] = sorted(by_level[lv], key=lambda x: x.length_m, reverse=True)

    proposals: list[dict[str, Any]] = []
    idx = 1

    for level in sorted(by_level.keys(), key=numeric_level):
        c = by_level[level][0]
        for label, frac in [("short", 0.22), ("medium", 0.48), ("long", 0.82)]:
            line = line_from_axis(c.center, c.axis, c.length_m, frac)
            pts_xy = sample_polyline(line, 50)
            pts_ll = xy_to_lonlat(pts_xy, lon0, lat0)
            rid = f"R{idx:03d}"
            idx += 1
            proposals.append(
                {
                    "route_id": rid,
                    "category": f"single_corridor_{label}",
                    "level_scope": [level],
                    "corridor_ids": [c.corridor_id],
                    "validation": "corridor_axis_based",
                    "requires_manual_transition": False,
                    "description": f"{label} route inside one corridor on level {level}",
                    "points_xy": pts_xy.tolist(),
                    "points_lonlat": pts_ll.tolist(),
                }
            )

    for level in sorted(by_level.keys(), key=numeric_level):
        if len(by_level[level]) < 2:
            continue
        c1 = by_level[level][0]
        c2 = by_level[level][1]
        connector = np.vstack([c1.center, c2.center])
        for label, pad in [("short", 8.0), ("medium", 16.0), ("long", 24.0)]:
            p1 = c1.center - c1.axis * pad
            p2 = c2.center + c2.axis * pad
            raw = np.vstack([p1, c1.center, connector[1], p2])
            pts_xy = sample_polyline(raw, 50)
            pts_ll = xy_to_lonlat(pts_xy, lon0, lat0)
            rid = f"R{idx:03d}"
            idx += 1
            proposals.append(
                {
                    "route_id": rid,
                    "category": f"two_corridor_same_floor_{label}",
                    "level_scope": [level],
                    "corridor_ids": [c1.corridor_id, c2.corridor_id],
                    "validation": "corridor_centers_connector",
                    "requires_manual_transition": True,
                    "description": f"{label} route across two corridors on level {level}; connector needs your validation",
                    "points_xy": pts_xy.tolist(),
                    "points_lonlat": pts_ll.tolist(),
                }
            )

    levels_sorted = sorted(by_level.keys(), key=numeric_level)
    if len(levels_sorted) >= 2:
        for i in range(len(levels_sorted) - 1):
            la = levels_sorted[i]
            lb = levels_sorted[i + 1]
            ca, cb = nearest_pair(by_level[la][: min(4, len(by_level[la]))], by_level[lb][: min(4, len(by_level[lb]))])
            mid = (ca.center + cb.center) / 2.0
            for label, pad in [("medium", 12.0), ("long", 22.0)]:
                raw = np.vstack(
                    [
                        ca.center - ca.axis * pad,
                        ca.center,
                        mid,
                        cb.center,
                        cb.center + cb.axis * pad,
                    ]
                )
                pts_xy = sample_polyline(raw, 50)
                pts_ll = xy_to_lonlat(pts_xy, lon0, lat0)
                rid = f"R{idx:03d}"
                idx += 1
                proposals.append(
                    {
                        "route_id": rid,
                        "category": f"multi_floor_{label}",
                        "level_scope": [la, lb],
                        "corridor_ids": [ca.corridor_id, cb.corridor_id],
                        "validation": "inter_floor_center_connector",
                        "requires_manual_transition": True,
                        "description": f"{label} multi-floor route from level {la} to {lb}; stair/elevator segment needs your approval",
                        "points_xy": pts_xy.tolist(),
                        "points_lonlat": pts_ll.tolist(),
                    }
                )

    long_chain_proposals, idx = build_multi_floor_chain_proposals(by_level, lon0, lat0, idx, family_scores)
    proposals.extend(long_chain_proposals)

    return proposals


def floor_color(level: str) -> str:
    palette = {
        "-1": "#8b5cf6",
        "0": "#0ea5e9",
        "1": "#10b981",
        "2": "#f59e0b",
        "2.5": "#ef4444",
    }
    return palette.get(level, "#64748b")


def draw_preview(corridors: list[Corridor], proposals: list[dict[str, Any]], out_png: Path) -> None:
    fig, ax = plt.subplots(figsize=(13, 10), dpi=180)

    for c in corridors:
        color = floor_color(c.level)
        ax.fill(c.ring_xy[:, 0], c.ring_xy[:, 1], color=color, alpha=0.10)
        ax.plot(c.ring_xy[:, 0], c.ring_xy[:, 1], color=color, linewidth=0.8, alpha=0.45)

    shown = proposals[:20]
    cmap = plt.get_cmap("tab20")
    for i, p in enumerate(shown):
        pts = np.asarray(p["points_xy"], dtype=float)
        color = cmap(i % 20)
        ax.plot(pts[:, 0], pts[:, 1], color=color, linewidth=2.0, alpha=0.95)
        ax.scatter([pts[0, 0]], [pts[0, 1]], s=22, color=color)
        ax.text(pts[0, 0], pts[0, 1], p["route_id"], fontsize=8, color="#111827")

    ax.set_title("Stage-1 Route Proposals on Indoor Map (first 20 shown)")
    ax.set_xlabel("x (m)")
    ax.set_ylabel("y (m)")
    ax.grid(alpha=0.2)
    ax.set_aspect("equal", adjustable="box")
    fig.tight_layout()
    out_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_png, bbox_inches="tight")
    plt.close(fig)


def draw_route_image(corridors: list[Corridor], proposal: dict[str, Any], out_path: Path) -> None:
    fig, ax = plt.subplots(figsize=(10, 7.5), dpi=180)
    levels = set(proposal["level_scope"])

    for c in corridors:
        color = floor_color(c.level)
        active = c.level in levels
        ax.fill(c.ring_xy[:, 0], c.ring_xy[:, 1], color=color, alpha=0.20 if active else 0.05)
        ax.plot(c.ring_xy[:, 0], c.ring_xy[:, 1], color=color, linewidth=1.0 if active else 0.4, alpha=0.7 if active else 0.2)

    pts = np.asarray(proposal["points_xy"], dtype=float)
    ax.plot(pts[:, 0], pts[:, 1], color="#111827", linewidth=2.8, label="Proposed route")
    ax.scatter([pts[0, 0]], [pts[0, 1]], color="#16a34a", s=45, label="Start")
    ax.scatter([pts[-1, 0]], [pts[-1, 1]], color="#dc2626", s=45, label="End")

    info = (
        f"{proposal['route_id']} | {proposal['category']}\n"
        f"levels={','.join(proposal['level_scope'])} | manual_transition={proposal['requires_manual_transition']}"
    )
    ax.set_title(info)
    ax.set_xlabel("x (m)")
    ax.set_ylabel("y (m)")
    ax.grid(alpha=0.2)
    ax.legend(frameon=False, loc="best")
    ax.set_aspect("equal", adjustable="box")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)


def route_image_path(route_id: str, category: str, levels: list[str]) -> Path:
    lv = "-".join(levels)
    name = f"{route_id}__{category}__L{lv}.png"
    return ROUTE_IMG_DIR / name


def init_db(db_path: Path) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(db_path)
    cur = con.cursor()

    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS route_proposals (
            route_id TEXT PRIMARY KEY,
            category TEXT NOT NULL,
            level_scope TEXT NOT NULL,
            corridor_ids TEXT NOT NULL,
            validation TEXT NOT NULL,
            requires_manual_transition INTEGER NOT NULL,
            description TEXT NOT NULL,
            status TEXT NOT NULL,
            image_path TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
        """
    )

    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS route_points (
            route_id TEXT NOT NULL,
            point_idx INTEGER NOT NULL,
            x_m REAL NOT NULL,
            y_m REAL NOT NULL,
            lon REAL NOT NULL,
            lat REAL NOT NULL,
            PRIMARY KEY (route_id, point_idx)
        )
        """
    )

    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS approved_routes (
            route_id TEXT PRIMARY KEY,
            approved_at TEXT DEFAULT CURRENT_TIMESTAMP,
            reviewer_note TEXT
        )
        """
    )

    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS rejected_routes (
            route_id TEXT PRIMARY KEY,
            rejected_at TEXT DEFAULT CURRENT_TIMESTAMP,
            reviewer_note TEXT
        )
        """
    )

    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS route_reviews (
            review_id INTEGER PRIMARY KEY AUTOINCREMENT,
            route_id TEXT NOT NULL,
            decision TEXT NOT NULL,
            comment TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
        """
    )

    # Keep older databases compatible without dropping any saved review history.
    cur.execute("PRAGMA table_info(route_proposals)")
    proposal_columns = {row[1] for row in cur.fetchall()}
    if "image_path" not in proposal_columns:
        cur.execute("ALTER TABLE route_proposals ADD COLUMN image_path TEXT")

    cur.execute("PRAGMA table_info(route_reviews)")
    review_columns = {row[1] for row in cur.fetchall()}
    if "comment" not in review_columns:
        cur.execute("ALTER TABLE route_reviews ADD COLUMN comment TEXT")

    con.commit()
    con.close()


def persist_proposals(db_path: Path, proposals: list[dict[str, Any]]) -> None:
    con = sqlite3.connect(db_path)
    cur = con.cursor()

    for p in proposals:
        img = str(route_image_path(p["route_id"], p["category"], p["level_scope"]))
        cur.execute("SELECT status FROM route_proposals WHERE route_id = ?", (p["route_id"],))
        row = cur.fetchone()
        status = row[0] if row else "pending"

        cur.execute(
            """
            INSERT OR REPLACE INTO route_proposals (
                route_id, category, level_scope, corridor_ids,
                validation, requires_manual_transition, description, status, image_path
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                p["route_id"],
                p["category"],
                json.dumps(p["level_scope"], ensure_ascii=False),
                json.dumps(p["corridor_ids"], ensure_ascii=False),
                p["validation"],
                1 if p["requires_manual_transition"] else 0,
                p["description"],
                status,
                img,
            ),
        )

        cur.execute("DELETE FROM route_points WHERE route_id = ?", (p["route_id"],))
        for i, (xy, ll) in enumerate(zip(p["points_xy"], p["points_lonlat"])):
            cur.execute(
                """
                INSERT INTO route_points (route_id, point_idx, x_m, y_m, lon, lat)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (p["route_id"], i, float(xy[0]), float(xy[1]), float(ll[0]), float(ll[1])),
            )

    con.commit()
    con.close()


def log_review(db_path: Path, route_id: str, decision: str, comment: str) -> bool:
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    cur.execute("SELECT route_id FROM route_proposals WHERE route_id = ?", (route_id,))
    found = cur.fetchone()
    if found is None:
        con.close()
        return False

    cur.execute(
        "INSERT INTO route_reviews (route_id, decision, comment) VALUES (?, ?, ?)",
        (route_id, decision, comment),
    )

    if decision == "approve":
        cur.execute("UPDATE route_proposals SET status = 'approved' WHERE route_id = ?", (route_id,))
        cur.execute(
            "INSERT OR REPLACE INTO approved_routes (route_id, reviewer_note) VALUES (?, ?)",
            (route_id, comment),
        )
        cur.execute("DELETE FROM rejected_routes WHERE route_id = ?", (route_id,))
    elif decision == "reject":
        cur.execute("UPDATE route_proposals SET status = 'rejected' WHERE route_id = ?", (route_id,))
        cur.execute(
            "INSERT OR REPLACE INTO rejected_routes (route_id, reviewer_note) VALUES (?, ?)",
            (route_id, comment),
        )
        cur.execute("DELETE FROM approved_routes WHERE route_id = ?", (route_id,))
    elif decision in {"comment", "skip"}:
        pass

    con.commit()
    con.close()
    return True


def export_csv(proposals: list[dict[str, Any]], csv_path: Path) -> None:
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "route_id",
        "category",
        "level_scope",
        "corridor_ids",
        "validation",
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
                    "category": p["category"],
                    "level_scope": "|".join(p["level_scope"]),
                    "corridor_ids": "|".join(p["corridor_ids"]),
                    "validation": p["validation"],
                    "requires_manual_transition": int(p["requires_manual_transition"]),
                    "description": p["description"],
                }
            )


def write_summary_md(proposals: list[dict[str, Any]], md_path: Path) -> None:
    md_path.parent.mkdir(parents=True, exist_ok=True)
    with open(md_path, "w", encoding="utf-8") as f:
        f.write("# Stage-1 Route Proposals\n\n")
        f.write("در این مرحله مسیرها یکی یکی قابل بررسی و تایید/رد هستند.\n\n")
        f.write("## Categories\n\n")
        for c in sorted({p["category"] for p in proposals}):
            f.write(f"- {c}\n")

        f.write("\n## Proposed Routes\n\n")
        for p in proposals:
            img = route_image_path(p["route_id"], p["category"], p["level_scope"]) 
            f.write(
                f"- {p['route_id']} | {p['category']} | levels={','.join(p['level_scope'])} | "
                f"manual_transition={p['requires_manual_transition']} | image={img.name}\n"
            )


def build_article_gallery(db_path: Path) -> None:
    gallery_dir = OUT_DIR / "article_gallery"
    gallery_dir.mkdir(parents=True, exist_ok=True)
    rejected_dir = gallery_dir / "rejected"
    clean_dir = gallery_dir / "clean"
    long_dir = gallery_dir / "long_routes"
    rejected_dir.mkdir(parents=True, exist_ok=True)
    clean_dir.mkdir(parents=True, exist_ok=True)
    long_dir.mkdir(parents=True, exist_ok=True)

    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    cur.execute("SELECT route_id, category, level_scope, status, image_path FROM route_proposals ORDER BY route_id")
    rows = [dict(r) for r in cur.fetchall()]
    con.close()

    selected_paths: list[tuple[str, Path]] = []
    long_paths: list[tuple[str, Path]] = []
    gallery_md = gallery_dir / "gallery_index.md"
    with open(gallery_md, "w", encoding="utf-8") as f:
        f.write("# Route Gallery for Article Use\n\n")
        f.write("## Legend\n\n")
        f.write("- clean: non-rejected routes\n")
        f.write("- rejected: routes marked wrong\n")
        f.write("- long_routes: only long multi-floor / multi-corridor candidates\n\n")

        for row in rows:
            image_path = Path(row["image_path"])
            if not image_path.exists():
                continue
            category = row["category"]
            status = row["status"]
            target = clean_dir / image_path.name
            if status == "rejected":
                target = rejected_dir / image_path.name
            else:
                selected_paths.append((row["route_id"], target))
            shutil.copy2(image_path, target)
            if "long" in category and "multi_floor" in category:
                long_target = long_dir / image_path.name
                shutil.copy2(image_path, long_target)
                long_paths.append((row["route_id"], long_target))

        f.write("## Routes\n\n")
        for row in rows:
            f.write(f"- {row['route_id']} | {row['category']} | {row['status']} | {row['image_path']}\n")

    if long_paths:
        fig, axes = plt.subplots(math.ceil(len(long_paths) / 2), 2, figsize=(14, 4 * math.ceil(len(long_paths) / 2)), dpi=180)
        axes_arr = np.array(axes).reshape(-1)
        for ax, (rid, img_path) in zip(axes_arr, long_paths):
            img = plt.imread(img_path)
            ax.imshow(img)
            ax.set_title(rid, fontsize=10)
            ax.axis("off")
        for ax in axes_arr[len(long_paths):]:
            ax.axis("off")
        fig.tight_layout()
        fig.savefig(gallery_dir / "long_routes_contact_sheet.png", bbox_inches="tight")
        plt.close(fig)

    with open(gallery_dir / "gallery_summary.txt", "w", encoding="utf-8") as f:
        f.write(f"clean_images={len(selected_paths)}\n")
        f.write(f"long_images={len(long_paths)}\n")
        f.write(f"rejected_images={len([r for r in rows if r['status'] == 'rejected'])}\n")


def purge_routes(db_path: Path, route_ids: list[str], delete_images: bool) -> int:
    if not route_ids:
        return 0

    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    cur = con.cursor()

    placeholders = ",".join(["?"] * len(route_ids))
    cur.execute(
        f"SELECT route_id, image_path FROM route_proposals WHERE route_id IN ({placeholders})",
        route_ids,
    )
    rows = cur.fetchall()
    existing_ids = [str(r["route_id"]) for r in rows]

    if not existing_ids:
        con.close()
        return 0

    existing_placeholders = ",".join(["?"] * len(existing_ids))
    cur.execute(f"DELETE FROM route_points WHERE route_id IN ({existing_placeholders})", existing_ids)
    cur.execute(f"DELETE FROM route_reviews WHERE route_id IN ({existing_placeholders})", existing_ids)
    cur.execute(f"DELETE FROM approved_routes WHERE route_id IN ({existing_placeholders})", existing_ids)
    cur.execute(f"DELETE FROM rejected_routes WHERE route_id IN ({existing_placeholders})", existing_ids)
    cur.execute(f"DELETE FROM route_proposals WHERE route_id IN ({existing_placeholders})", existing_ids)
    con.commit()
    con.close()

    if delete_images:
        for row in rows:
            image_path = row["image_path"]
            if not image_path:
                continue
            p = Path(str(image_path))
            if p.exists():
                p.unlink()

    return len(existing_ids)


def purge_wrong_routes(db_path: Path, delete_images: bool) -> int:
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    cur.execute("SELECT route_id FROM route_proposals WHERE status = 'rejected' ORDER BY route_id")
    route_ids = [r[0] for r in cur.fetchall()]
    con.close()
    return purge_routes(db_path, route_ids, delete_images)


def list_approved(db_path: Path) -> list[str]:
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    cur.execute("SELECT route_id FROM approved_routes ORDER BY route_id")
    rows = cur.fetchall()
    con.close()
    return [r[0] for r in rows]


def load_db_routes(db_path: Path, include_non_pending: bool) -> list[dict[str, Any]]:
    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    if include_non_pending:
        cur.execute("SELECT * FROM route_proposals ORDER BY route_id")
    else:
        cur.execute("SELECT * FROM route_proposals WHERE status = 'pending' ORDER BY route_id")
    rows = [dict(r) for r in cur.fetchall()]
    con.close()
    return rows


def review_menu(db_path: Path, include_non_pending: bool) -> None:
    routes = load_db_routes(db_path, include_non_pending)
    if not routes:
        print("No routes to review.")
        return

    print("Interactive review menu")
    print("Options: [A]pprove, [R]eject, [C]omment, [S]kip, [Q]Cancel")

    for r in routes:
        levels = json.loads(r["level_scope"]) if isinstance(r["level_scope"], str) else r["level_scope"]
        print("\n" + "=" * 72)
        print(f"Route: {r['route_id']}")
        print(f"Type: {r['category']}")
        print(f"Levels: {','.join(levels)}")
        print(f"Status: {r['status']}")
        print(f"Manual transition: {bool(r['requires_manual_transition'])}")
        print(f"Description: {r['description']}")
        print(f"Image: {r['image_path']}")

        choice = input("Decision [A/R/C/S/Q]: ").strip().lower()
        if choice == "q":
            print("Review canceled by user.")
            return
        if choice == "s":
            log_review(db_path, r["route_id"], "skip", "skip in interactive review")
            continue
        if choice == "c":
            txt = input("Comment text: ").strip()
            log_review(db_path, r["route_id"], "comment", txt)
            continue
        if choice == "a":
            note = input("Approve note (optional): ").strip()
            log_review(db_path, r["route_id"], "approve", note)
            print(f"Approved: {r['route_id']}")
            continue
        if choice == "r":
            note = input("Reject reason (optional): ").strip()
            log_review(db_path, r["route_id"], "reject", note)
            print(f"Rejected: {r['route_id']}")
            continue

        print("Unknown choice, route skipped.")
        log_review(db_path, r["route_id"], "skip", "unknown input")


def print_status(db_path: Path) -> None:
    con = sqlite3.connect(db_path)
    cur = con.cursor()

    cur.execute("SELECT status, COUNT(*) FROM route_proposals GROUP BY status")
    rows = cur.fetchall()
    print("Route status counts:")
    for s, c in rows:
        print(f"  {s}: {c}")

    cur.execute("SELECT COUNT(*) FROM route_reviews")
    total_reviews = cur.fetchone()[0]
    print(f"Total review events (history preserved): {total_reviews}")

    cur.execute(
        """
        SELECT route_id, decision, comment, created_at
        FROM route_reviews
        ORDER BY review_id DESC
        LIMIT 12
        """
    )
    recent = cur.fetchall()
    print("Recent reviews:")
    for rid, d, comment, ts in recent:
        print(f"  {ts} | {rid} | {d} | {comment}")

    con.close()


def main() -> None:
    args = parse_args()
    init_db(DB_PATH)

    if args.action == "propose":
        corridors, lon0, lat0 = load_corridors()
        proposals = build_proposals(corridors, lon0, lat0)

        OUT_DIR.mkdir(parents=True, exist_ok=True)
        ROUTE_IMG_DIR.mkdir(parents=True, exist_ok=True)

        for p in proposals:
            img = route_image_path(p["route_id"], p["category"], p["level_scope"])
            draw_route_image(corridors, p, img)

        with open(PROPOSALS_JSON, "w", encoding="utf-8") as f:
            json.dump(
                {
                    "note": "Stage-1 proposals from GeoJSON corridors",
                    "proposal_count": len(proposals),
                    "proposals": proposals,
                },
                f,
                ensure_ascii=False,
                indent=2,
            )

        export_csv(proposals, PROPOSALS_CSV)
        draw_preview(corridors, proposals, PREVIEW_PNG)
        write_summary_md(proposals, SUMMARY_MD)
        persist_proposals(DB_PATH, proposals)

        print("Stage-1 route proposals generated")
        print(f"json: {PROPOSALS_JSON}")
        print(f"csv: {PROPOSALS_CSV}")
        print(f"preview(all-in-one): {PREVIEW_PNG}")
        print(f"per-route images: {ROUTE_IMG_DIR}")
        print(f"db: {DB_PATH}")
        return

    if args.action == "review":
        review_menu(DB_PATH, args.include_non_pending)
        return

    if args.action == "decide":
        if not args.route_id or not args.decision:
            raise ValueError("--route-id and --decision are required for decide action")
        ok = log_review(DB_PATH, args.route_id, args.decision, args.comment)
        if not ok:
            print(f"Route ID not found: {args.route_id}")
        else:
            print(f"Saved decision: {args.route_id} -> {args.decision}")
        return

    if args.action == "list-approved":
        ids = list_approved(DB_PATH)
        print("Approved routes:")
        for rid in ids:
            print(rid)
        return

    if args.action == "status":
        print_status(DB_PATH)
        return

    if args.action == "purge-wrong":
        removed = purge_wrong_routes(DB_PATH, args.delete_images)
        build_article_gallery(DB_PATH)
        print(f"Purged wrong routes: {removed}")
        return

    if args.action == "purge-routes":
        route_ids = [x.strip() for x in args.route_ids.split(",") if x.strip()]
        if not route_ids:
            raise ValueError("--route-ids is required for purge-routes action")
        removed = purge_routes(DB_PATH, route_ids, args.delete_images)
        build_article_gallery(DB_PATH)
        print(f"Purged listed routes: {removed}")
        return


if __name__ == "__main__":
    main()
