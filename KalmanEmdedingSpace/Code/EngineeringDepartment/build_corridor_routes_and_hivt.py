from __future__ import annotations

import csv
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
import numpy as np


ROOT_DIR = Path(__file__).resolve().parent
GEOJSON_DIR = ROOT_DIR / "GeoJSON"
OUTPUT_DIR = ROOT_DIR / "derived"
HIVT_DIR = OUTPUT_DIR / "hivt_ready"

HIST_STEPS = 20
FUTURE_STEPS = 30
TOTAL_STEPS = HIST_STEPS + FUTURE_STEPS
DT = 1.0
RADIUS_M = 35.0
MAX_ROUTES_PER_LEVEL = 14
RANDOM_SEED = 13


@dataclass
class CorridorFeature:
    level: str
    feature_id: str
    lon_lat: np.ndarray  # [P, 2] -> lon, lat
    xy_m: np.ndarray  # [P, 2] local meters


@dataclass
class RouteTrack:
    route_id: str
    level: str
    feature_id: str
    positions_xy: np.ndarray  # [T, 2]
    positions_lon_lat: np.ndarray  # [T, 2]


def load_geojson_features() -> list[dict[str, Any]]:
    all_features: list[dict[str, Any]] = []
    for path in sorted(GEOJSON_DIR.glob("indoor_level_*.geojson")):
        with open(path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
        all_features.extend(payload.get("features", []))
    return all_features


def collect_corridor_rings(all_features: list[dict[str, Any]]) -> tuple[list[CorridorFeature], float, float]:
    raw_corridors: list[tuple[str, str, np.ndarray]] = []
    lon_all: list[float] = []
    lat_all: list[float] = []

    for idx, feature in enumerate(all_features):
        props = feature.get("properties", {})
        if props.get("indoor") != "corridor":
            continue

        geom = feature.get("geometry", {})
        g_type = geom.get("type")
        coords = geom.get("coordinates", [])
        level = str(props.get("level", "unknown"))
        feature_id = f"corridor_{idx:05d}"

        rings: list[np.ndarray] = []
        if g_type == "Polygon":
            if coords:
                rings.append(np.asarray(coords[0], dtype=float))
        elif g_type == "MultiPolygon":
            for poly in coords:
                if poly:
                    rings.append(np.asarray(poly[0], dtype=float))

        for ring in rings:
            if ring.shape[0] < 4:
                continue
            raw_corridors.append((level, feature_id, ring))
            lon_all.extend(ring[:, 0].tolist())
            lat_all.extend(ring[:, 1].tolist())

    if not raw_corridors:
        raise RuntimeError("No corridor polygons found in GeoJSON files.")

    lon0 = float(np.mean(lon_all))
    lat0 = float(np.mean(lat_all))

    corridors: list[CorridorFeature] = []
    for level, feature_id, ring in raw_corridors:
        xy = lonlat_to_local_xy(ring, lon0, lat0)
        corridors.append(CorridorFeature(level=level, feature_id=feature_id, lon_lat=ring, xy_m=xy))

    return corridors, lon0, lat0


def lonlat_to_local_xy(lon_lat: np.ndarray, lon0: float, lat0: float) -> np.ndarray:
    lon = lon_lat[:, 0]
    lat = lon_lat[:, 1]
    x = (lon - lon0) * 111_320.0 * math.cos(math.radians(lat0))
    y = (lat - lat0) * 110_540.0
    return np.stack([x, y], axis=1)


def local_xy_to_lonlat(xy: np.ndarray, lon0: float, lat0: float) -> np.ndarray:
    lon = xy[:, 0] / (111_320.0 * math.cos(math.radians(lat0))) + lon0
    lat = xy[:, 1] / 110_540.0 + lat0
    return np.stack([lon, lat], axis=1)


def principal_axis(points_xy: np.ndarray) -> tuple[np.ndarray, np.ndarray, float]:
    pts = points_xy[:-1] if np.allclose(points_xy[0], points_xy[-1]) else points_xy
    center = np.mean(pts, axis=0)
    centered = pts - center
    cov = centered.T @ centered / max(1, centered.shape[0] - 1)
    eigvals, eigvecs = np.linalg.eigh(cov)
    major = eigvecs[:, np.argmax(eigvals)]
    major = major / (np.linalg.norm(major) + 1e-9)
    proj = centered @ major
    length = float(np.max(proj) - np.min(proj))
    return center, major, max(length, 0.1)


def create_route_points(center: np.ndarray, major: np.ndarray, length: float, jitter: float, reverse: bool) -> np.ndarray:
    t = np.linspace(0.0, 1.0, TOTAL_STEPS)
    start = center - major * (0.45 * length)
    end = center + major * (0.45 * length)

    pts = (1.0 - t)[:, None] * start + t[:, None] * end

    perp = np.array([-major[1], major[0]])
    phase = 2.0 * math.pi * t
    lateral = jitter * np.sin(phase)
    pts = pts + lateral[:, None] * perp

    if reverse:
        pts = pts[::-1].copy()

    return pts


def corridor_lanes_from_axis(corridors: list[CorridorFeature]) -> dict[str, np.ndarray]:
    by_level: dict[str, list[np.ndarray]] = {}
    for c in corridors:
        center, major, length = principal_axis(c.xy_m)
        p0 = center - major * (0.45 * length)
        p1 = center + major * (0.45 * length)
        line = np.stack([p0, p1], axis=0)
        by_level.setdefault(c.level, []).append(line)

    out: dict[str, np.ndarray] = {}
    for level, lines in by_level.items():
        segments: list[np.ndarray] = []
        for line in lines:
            vec = line[1] - line[0]
            segments.append(np.stack([line[0], vec], axis=0))
        if not segments:
            out[level] = np.zeros((0, 2, 2), dtype=float)
        else:
            out[level] = np.asarray(segments, dtype=float)
    return out


def build_routes(corridors: list[CorridorFeature], lon0: float, lat0: float) -> list[RouteTrack]:
    rng = np.random.default_rng(RANDOM_SEED)
    routes: list[RouteTrack] = []

    by_level: dict[str, list[CorridorFeature]] = {}
    for c in corridors:
        by_level.setdefault(c.level, []).append(c)

    for level, level_corridors in by_level.items():
        sorted_corridors = sorted(level_corridors, key=lambda c: principal_axis(c.xy_m)[2], reverse=True)
        selected = sorted_corridors[:MAX_ROUTES_PER_LEVEL]

        for idx, corridor in enumerate(selected):
            center, major, length = principal_axis(corridor.xy_m)
            jitter = float(rng.uniform(0.05, 0.35))

            for reverse in (False, True):
                route_id = f"L{level}_R{idx:02d}_{'B' if reverse else 'A'}"
                pts_xy = create_route_points(center, major, length, jitter=jitter, reverse=reverse)
                pts_lonlat = local_xy_to_lonlat(pts_xy, lon0, lat0)
                routes.append(
                    RouteTrack(
                        route_id=route_id,
                        level=level,
                        feature_id=corridor.feature_id,
                        positions_xy=pts_xy,
                        positions_lon_lat=pts_lonlat,
                    )
                )

    return routes


def save_routes_csv(routes: list[RouteTrack], path: Path) -> None:
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "route_id",
                "level",
                "feature_id",
                "timestep",
                "is_history",
                "lon",
                "lat",
                "x_m",
                "y_m",
                "vx_mps",
                "vy_mps",
                "speed_mps",
            ]
        )
        for route in routes:
            pos = route.positions_xy
            vel = np.zeros_like(pos)
            vel[1:] = (pos[1:] - pos[:-1]) / DT
            speed = np.linalg.norm(vel, axis=1)
            for t in range(pos.shape[0]):
                writer.writerow(
                    [
                        route.route_id,
                        route.level,
                        route.feature_id,
                        t,
                        1 if t < HIST_STEPS else 0,
                        float(route.positions_lon_lat[t, 0]),
                        float(route.positions_lon_lat[t, 1]),
                        float(pos[t, 0]),
                        float(pos[t, 1]),
                        float(vel[t, 0]),
                        float(vel[t, 1]),
                        float(speed[t]),
                    ]
                )


def save_routes_geojson(routes: list[RouteTrack], path: Path) -> None:
    features = []
    for route in routes:
        coordinates = [[float(x), float(y)] for x, y in route.positions_lon_lat]
        features.append(
            {
                "type": "Feature",
                "properties": {
                    "route_id": route.route_id,
                    "level": route.level,
                    "feature_id": route.feature_id,
                    "hist_steps": HIST_STEPS,
                    "future_steps": FUTURE_STEPS,
                },
                "geometry": {"type": "LineString", "coordinates": coordinates},
            }
        )

    payload = {"type": "FeatureCollection", "features": features}
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False)


def plot_preview(corridors: list[CorridorFeature], routes: list[RouteTrack], out_dir: Path) -> None:
    by_level_corr: dict[str, list[CorridorFeature]] = {}
    by_level_routes: dict[str, list[RouteTrack]] = {}

    for c in corridors:
        by_level_corr.setdefault(c.level, []).append(c)
    for r in routes:
        by_level_routes.setdefault(r.level, []).append(r)

    for level in sorted(by_level_corr.keys()):
        fig, ax = plt.subplots(figsize=(10, 8), dpi=180)
        for c in by_level_corr[level]:
            ring = c.xy_m
            ax.plot(ring[:, 0], ring[:, 1], color="#d1d5db", linewidth=1.0)

        level_routes = by_level_routes.get(level, [])
        for idx, r in enumerate(level_routes):
            color = "#16a34a" if idx % 2 == 0 else "#2563eb"
            pts = r.positions_xy
            ax.plot(pts[:, 0], pts[:, 1], color=color, alpha=0.75, linewidth=1.4)
            ax.scatter([pts[0, 0]], [pts[0, 1]], color="#dc2626", s=10)

        ax.set_title(f"Engineering Dept Routes - Level {level}")
        ax.set_xlabel("x (m)")
        ax.set_ylabel("y (m)")
        ax.grid(alpha=0.25)
        ax.set_aspect("equal", adjustable="box")
        fig.tight_layout()
        fig.savefig(out_dir / f"routes_preview_level_{level}.png", bbox_inches="tight")
        plt.close(fig)


def plot_routes_on_osm_image(routes: list[RouteTrack], osm_image_path: Path, out_path: Path) -> None:
    if not osm_image_path.exists():
        return

    image = plt.imread(osm_image_path)
    h, w = image.shape[0], image.shape[1]

    all_pts = np.concatenate([r.positions_xy for r in routes], axis=0)
    min_x, min_y = np.min(all_pts[:, 0]), np.min(all_pts[:, 1])
    max_x, max_y = np.max(all_pts[:, 0]), np.max(all_pts[:, 1])

    # Use a small margin and linear normalization as a quick alignment proxy.
    margin = 24.0
    span_x = max(max_x - min_x, 1e-6)
    span_y = max(max_y - min_y, 1e-6)

    def to_px(xy: np.ndarray) -> np.ndarray:
        x_n = (xy[:, 0] - min_x) / span_x
        y_n = (xy[:, 1] - min_y) / span_y
        x_px = margin + x_n * (w - 2.0 * margin)
        y_px = h - (margin + y_n * (h - 2.0 * margin))
        return np.stack([x_px, y_px], axis=1)

    fig, ax = plt.subplots(figsize=(w / 120.0, h / 120.0), dpi=120)
    ax.imshow(image)

    for idx, route in enumerate(routes):
        p = to_px(route.positions_xy)
        color = "#2563eb" if idx % 2 == 0 else "#16a34a"
        ax.plot(p[:, 0], p[:, 1], color=color, linewidth=1.6, alpha=0.85)
        ax.scatter([p[0, 0]], [p[0, 1]], color="#ef4444", s=11)

    ax.set_title(f"Synthetic Corridor Routes Overlay | {osm_image_path.name}")
    ax.axis("off")
    fig.tight_layout()
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)


def build_hivt_scene_arrays(routes_for_scene: list[RouteTrack], lane_segments: np.ndarray) -> dict[str, np.ndarray]:
    n = len(routes_for_scene)
    positions = np.stack([r.positions_xy for r in routes_for_scene], axis=0)  # [N, 50, 2]

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

    # Create lane actor edges from synthetic lane centerline segments.
    if lane_segments.size == 0:
        lane_vectors = np.zeros((0, 2), dtype=float)
        lane_positions = np.zeros((0, 2), dtype=float)
    else:
        lane_positions = lane_segments[:, 0, :]
        lane_vectors = lane_segments[:, 1, :]

    actor_pos_t = positions[:, HIST_STEPS - 1, :]

    if lane_vectors.shape[0] == 0:
        lane_actor_index = np.zeros((2, 0), dtype=np.int64)
        lane_actor_vectors = np.zeros((0, 2), dtype=float)
    else:
        pairs = []
        vecs = []
        for lane_idx, lane_pos in enumerate(lane_positions):
            for actor_idx, actor_pos in enumerate(actor_pos_t):
                dvec = lane_pos - actor_pos
                if np.linalg.norm(dvec) <= RADIUS_M:
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


def save_hivt_ready(routes: list[RouteTrack], lane_map: dict[str, np.ndarray], out_dir: Path) -> Path:
    by_level: dict[str, list[RouteTrack]] = {}
    for r in routes:
        by_level.setdefault(r.level, []).append(r)

    manifest: dict[str, Any] = {
        "format": "hivt_like_npz_per_scene",
        "history_steps": HIST_STEPS,
        "future_steps": FUTURE_STEPS,
        "dt_seconds": DT,
        "radius_m": RADIUS_M,
        "scenes": [],
    }

    scene_counter = 0
    scene_size = 8

    for level in sorted(by_level.keys()):
        level_routes = by_level[level]
        lane_segments = lane_map.get(level, np.zeros((0, 2, 2), dtype=float))
        for i in range(0, len(level_routes), scene_size):
            chunk = level_routes[i : i + scene_size]
            arrays = build_hivt_scene_arrays(chunk, lane_segments)
            scene_name = f"scene_{scene_counter:03d}_level_{level}.npz"
            scene_path = out_dir / scene_name
            np.savez(scene_path, **arrays)

            manifest["scenes"].append(
                {
                    "scene_id": scene_counter,
                    "level": level,
                    "file": scene_name,
                    "num_nodes": int(arrays["num_nodes"][0]),
                    "num_lane_vectors": int(arrays["lane_vectors"].shape[0]),
                    "num_lane_actor_edges": int(arrays["lane_actor_index"].shape[1]),
                    "routes": [r.route_id for r in chunk],
                }
            )
            scene_counter += 1

    manifest_path = out_dir / "hivt_manifest.json"
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, ensure_ascii=False)

    return manifest_path


def save_summary(routes: list[RouteTrack], manifest_path: Path, lon0: float, lat0: float) -> None:
    levels = sorted({r.level for r in routes})
    payload = {
        "corridor_route_count": len(routes),
        "levels": levels,
        "history_steps": HIST_STEPS,
        "future_steps": FUTURE_STEPS,
        "local_origin_lon": lon0,
        "local_origin_lat": lat0,
        "outputs": {
            "routes_csv": str(OUTPUT_DIR / "corridor_routes.csv"),
            "routes_geojson": str(OUTPUT_DIR / "corridor_routes.geojson"),
            "hivt_manifest": str(manifest_path),
            "hivt_dir": str(HIVT_DIR),
        },
    }

    with open(OUTPUT_DIR / "summary.json", "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False)


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    HIVT_DIR.mkdir(parents=True, exist_ok=True)

    all_features = load_geojson_features()
    corridors, lon0, lat0 = collect_corridor_rings(all_features)
    routes = build_routes(corridors, lon0, lat0)

    save_routes_csv(routes, OUTPUT_DIR / "corridor_routes.csv")
    save_routes_geojson(routes, OUTPUT_DIR / "corridor_routes.geojson")
    plot_preview(corridors, routes, OUTPUT_DIR)
    plot_routes_on_osm_image(routes, ROOT_DIR / "OSM_EngDep_1.png", OUTPUT_DIR / "routes_overlay_osm_1.png")
    plot_routes_on_osm_image(routes, ROOT_DIR / "OSM_EngDep_2.png", OUTPUT_DIR / "routes_overlay_osm_2.png")

    lane_map = corridor_lanes_from_axis(corridors)
    manifest_path = save_hivt_ready(routes, lane_map, HIVT_DIR)
    save_summary(routes, manifest_path, lon0, lat0)

    print("Route generation and HiVT-ready extraction completed")
    print(f"routes: {OUTPUT_DIR / 'corridor_routes.csv'}")
    print(f"hivt manifest: {manifest_path}")


if __name__ == "__main__":
    main()
