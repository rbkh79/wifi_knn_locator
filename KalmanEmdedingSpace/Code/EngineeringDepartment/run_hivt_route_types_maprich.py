from __future__ import annotations

import csv
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
import numpy as np

from build_corridor_routes_and_hivt import (
    DT,
    FUTURE_STEPS,
    HIST_STEPS,
    TOTAL_STEPS,
    CorridorFeature,
    RouteTrack,
    collect_corridor_rings,
    corridor_lanes_from_axis,
    load_geojson_features,
    lonlat_to_local_xy,
    local_xy_to_lonlat,
    principal_axis,
)
from hivt_inference_from_derived import build_temporal_data, load_model


ROOT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = ROOT_DIR / "derived" / "route_type_hivt"
SCENE_DIR = OUTPUT_DIR / "scenes"
FIG_DIR = OUTPUT_DIR / "figures"
PRED_DIR = OUTPUT_DIR / "predictions"

WORKSPACE_ROOT = ROOT_DIR.parent.parent
HIVT_ROOT = (WORKSPACE_ROOT / "HiVT").resolve()
CKPT_PATH = (WORKSPACE_ROOT / "HiVT" / "checkpoints" / "HiVT-64" / "checkpoints" / "epoch=63-step=411903.ckpt").resolve()


@dataclass
class MapPoly:
    level: str
    indoor: str
    xy: np.ndarray


@dataclass
class Scenario:
    scenario_id: str
    title: str
    route_type: str
    levels: list[str]
    main_xy: np.ndarray  # [50,2]
    main_floor: list[str]  # len=50
    actor2_xy: np.ndarray
    actor3_xy: np.ndarray


def unique_ring_vertices(xy_ring: np.ndarray) -> np.ndarray:
    if xy_ring.shape[0] > 1 and np.allclose(xy_ring[0], xy_ring[-1]):
        return xy_ring[:-1].copy()
    return xy_ring.copy()


def walk_ring(vertices: np.ndarray, start: int, step: int, count: int) -> np.ndarray:
    n = vertices.shape[0]
    idx = [(start + i * step) % n for i in range(count)]
    return vertices[idx]


def sample_polyline(polyline: np.ndarray, n_points: int) -> np.ndarray:
    if polyline.shape[0] < 2:
        return np.repeat(polyline[:1], n_points, axis=0)
    seg = polyline[1:] - polyline[:-1]
    seg_len = np.linalg.norm(seg, axis=1)
    cum = np.concatenate([[0.0], np.cumsum(seg_len)])
    total = float(cum[-1])
    if total < 1e-9:
        return np.repeat(polyline[:1], n_points, axis=0)
    t = np.linspace(0.0, total, n_points)
    out = np.zeros((n_points, 2), dtype=float)
    j = 0
    for i, ti in enumerate(t):
        while j < len(seg_len) - 1 and cum[j + 1] < ti:
            j += 1
        left, right = cum[j], cum[j + 1]
        alpha = 0.0 if right - left < 1e-9 else (ti - left) / (right - left)
        out[i] = polyline[j] * (1.0 - alpha) + polyline[j + 1] * alpha
    return out


def nearest_pair(a: np.ndarray, b: np.ndarray) -> tuple[int, int]:
    da = a[:, None, :] - b[None, :, :]
    dist = np.linalg.norm(da, axis=2)
    idx = np.unravel_index(np.argmin(dist), dist.shape)
    return int(idx[0]), int(idx[1])


def make_map_polygons(features: list[dict[str, Any]], lon0: float, lat0: float) -> list[MapPoly]:
    out: list[MapPoly] = []
    for feat in features:
        props = feat.get("properties", {})
        indoor = str(props.get("indoor", "unknown"))
        level = str(props.get("level", "unknown"))
        geom = feat.get("geometry", {})
        g_type = geom.get("type")
        coords = geom.get("coordinates", [])

        rings = []
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
            xy = lonlat_to_local_xy(ring, lon0, lat0)
            out.append(MapPoly(level=level, indoor=indoor, xy=xy))
    return out


def build_scenarios(corridors: list[CorridorFeature]) -> list[Scenario]:
    by_level: dict[str, list[CorridorFeature]] = {}
    for c in corridors:
        by_level.setdefault(c.level, []).append(c)
    for k in by_level:
        by_level[k] = sorted(by_level[k], key=lambda cc: principal_axis(cc.xy_m)[2], reverse=True)

    def ring(c: CorridorFeature) -> np.ndarray:
        return unique_ring_vertices(c.xy_m)

    # Scenario 1: normal in single corridor (history exactly on geojson vertices)
    c0 = by_level.get("0", list(by_level.values())[0])[0]
    v0 = ring(c0)
    h1 = walk_ring(v0, start=3, step=1, count=HIST_STEPS)
    f1 = walk_ring(v0, start=3 + HIST_STEPS, step=1, count=FUTURE_STEPS)
    m1 = np.vstack([h1, f1])
    a1_2 = np.vstack([walk_ring(v0, 18, 1, HIST_STEPS), walk_ring(v0, 38, 1, FUTURE_STEPS)])
    a1_3 = np.vstack([walk_ring(v0, 30, -1, HIST_STEPS), walk_ring(v0, 10, -1, FUTURE_STEPS)])

    s1 = Scenario(
        scenario_id="S1",
        title="Normal corridor route",
        route_type="normal_single_corridor",
        levels=["0"],
        main_xy=m1,
        main_floor=["0"] * TOTAL_STEPS,
        actor2_xy=a1_2,
        actor3_xy=a1_3,
    )

    # Scenario 2: long straight between two corridors
    c2a = by_level["0"][0]
    c2b = by_level["0"][min(3, len(by_level["0"]) - 1)]
    va = ring(c2a)
    vb = ring(c2b)
    ia, ib = nearest_pair(va, vb)
    h2 = walk_ring(va, start=(ia - HIST_STEPS), step=1, count=HIST_STEPS)
    part_a = walk_ring(va, start=ia, step=1, count=10)
    connector = sample_polyline(np.vstack([va[ia], vb[ib]]), 8)
    part_b = walk_ring(vb, start=ib, step=1, count=FUTURE_STEPS - 18)
    f2 = np.vstack([part_a, connector, part_b])
    f2 = sample_polyline(f2, FUTURE_STEPS)
    m2 = np.vstack([h2, f2])
    a2_2 = np.vstack([walk_ring(vb, ib - HIST_STEPS, 1, HIST_STEPS), walk_ring(vb, ib, 1, FUTURE_STEPS)])
    a2_3 = np.vstack([walk_ring(va, ia + 7, 1, HIST_STEPS), walk_ring(va, ia + 27, 1, FUTURE_STEPS)])

    s2 = Scenario(
        scenario_id="S2",
        title="Long straight route between corridors",
        route_type="long_straight_between_corridors",
        levels=["0"],
        main_xy=m2,
        main_floor=["0"] * TOTAL_STEPS,
        actor2_xy=a2_2,
        actor3_xy=a2_3,
    )

    # Scenario 3: long winding route
    c3_1 = by_level.get("1", by_level["0"])[0]
    c3_2 = by_level.get("1", by_level["0"])[min(2, len(by_level.get("1", by_level["0"])) - 1)]
    c3_3 = by_level.get("1", by_level["0"])[min(4, len(by_level.get("1", by_level["0"])) - 1)]
    v31, v32, v33 = ring(c3_1), ring(c3_2), ring(c3_3)
    i12a, i12b = nearest_pair(v31, v32)
    i23a, i23b = nearest_pair(v32, v33)

    h3 = walk_ring(v31, i12a - HIST_STEPS, 1, HIST_STEPS)
    fut3_raw = np.vstack(
        [
            walk_ring(v31, i12a, 1, 8),
            sample_polyline(np.vstack([v31[i12a], v32[i12b]]), 6),
            walk_ring(v32, i12b, 1, 10),
            sample_polyline(np.vstack([v32[i23a], v33[i23b]]), 6),
            walk_ring(v33, i23b, 1, 10),
        ]
    )
    f3 = sample_polyline(fut3_raw, FUTURE_STEPS)
    m3 = np.vstack([h3, f3])
    a3_2 = np.vstack([walk_ring(v32, i12b - HIST_STEPS, 1, HIST_STEPS), walk_ring(v32, i12b, 1, FUTURE_STEPS)])
    a3_3 = np.vstack([walk_ring(v33, i23b - HIST_STEPS, 1, HIST_STEPS), walk_ring(v33, i23b, 1, FUTURE_STEPS)])

    s3 = Scenario(
        scenario_id="S3",
        title="Long winding route",
        route_type="long_winding",
        levels=["1"],
        main_xy=m3,
        main_floor=["1"] * TOTAL_STEPS,
        actor2_xy=a3_2,
        actor3_xy=a3_3,
    )

    # Scenario 4 normal multi-floor
    c40 = by_level["0"][0]
    c41 = by_level.get("1", by_level["0"])[0]
    c42 = by_level.get("2", by_level.get("2.5", by_level["0"]))[0]
    v40, v41, v42 = ring(c40), ring(c41), ring(c42)
    i01a, i01b = nearest_pair(v40, v41)
    i12a, i12b = nearest_pair(v41, v42)

    h4n = walk_ring(v40, i01a - HIST_STEPS, 1, HIST_STEPS)
    f4n_raw = np.vstack(
        [
            sample_polyline(np.vstack([v40[i01a], v41[i01b]]), 8),
            walk_ring(v41, i01b, 1, 10),
            sample_polyline(np.vstack([v41[i12a], v42[i12b]]), 8),
            walk_ring(v42, i12b, 1, 10),
        ]
    )
    f4n = sample_polyline(f4n_raw, FUTURE_STEPS)
    m4n = np.vstack([h4n, f4n])
    floor4n = ["0"] * HIST_STEPS + ["0"] * 5 + ["1"] * 12 + ["2"] * 13
    floor4n = floor4n[:TOTAL_STEPS]
    a4n_2 = np.vstack([walk_ring(v41, i01b - HIST_STEPS, 1, HIST_STEPS), walk_ring(v41, i01b, 1, FUTURE_STEPS)])
    a4n_3 = np.vstack([walk_ring(v42, i12b - HIST_STEPS, 1, HIST_STEPS), walk_ring(v42, i12b, 1, FUTURE_STEPS)])

    s4n = Scenario(
        scenario_id="S4N",
        title="Normal multi-floor route",
        route_type="multi_floor_normal",
        levels=["0", "1", "2"],
        main_xy=m4n,
        main_floor=floor4n,
        actor2_xy=a4n_2,
        actor3_xy=a4n_3,
    )

    # Scenario 4 long multi-floor
    h4l = walk_ring(v40, i01a - HIST_STEPS, 1, HIST_STEPS)
    f4l_raw = np.vstack(
        [
            walk_ring(v40, i01a, 1, 10),
            sample_polyline(np.vstack([v40[i01a], v41[i01b]]), 8),
            walk_ring(v41, i01b, 1, 10),
            sample_polyline(np.vstack([v41[i12a], v42[i12b]]), 8),
            walk_ring(v42, i12b, 1, 16),
        ]
    )
    f4l = sample_polyline(f4l_raw, FUTURE_STEPS)
    m4l = np.vstack([h4l, f4l])
    floor4l = ["0"] * HIST_STEPS + ["0"] * 8 + ["1"] * 10 + ["2"] * 12
    floor4l = floor4l[:TOTAL_STEPS]
    a4l_2 = np.vstack([walk_ring(v41, i01b - HIST_STEPS, 1, HIST_STEPS), walk_ring(v41, i01b + 5, 1, FUTURE_STEPS)])
    a4l_3 = np.vstack([walk_ring(v42, i12b - HIST_STEPS, 1, HIST_STEPS), walk_ring(v42, i12b + 5, 1, FUTURE_STEPS)])

    s4l = Scenario(
        scenario_id="S4L",
        title="Long multi-floor route",
        route_type="multi_floor_long",
        levels=["0", "1", "2"],
        main_xy=m4l,
        main_floor=floor4l,
        actor2_xy=a4l_2,
        actor3_xy=a4l_3,
    )

    return [s1, s2, s3, s4n, s4l]


def build_scene_npz(routes: list[RouteTrack], lane_segments: np.ndarray, out_path: Path) -> None:
    n = len(routes)
    positions = np.stack([r.positions_xy for r in routes], axis=0)

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
        lane_vectors = np.zeros((0, 2), dtype=np.float32)
        lane_positions = np.zeros((0, 2), dtype=np.float32)
    else:
        lane_positions = lane_segments[:, 0, :].astype(np.float32)
        lane_vectors = lane_segments[:, 1, :].astype(np.float32)

    actor_pos_t = positions[:, HIST_STEPS - 1, :]
    pairs = []
    vecs = []
    for lane_idx, lane_pos in enumerate(lane_positions):
        for actor_idx, actor_pos in enumerate(actor_pos_t):
            dvec = lane_pos - actor_pos
            if np.linalg.norm(dvec) <= 40.0:
                pairs.append([lane_idx, actor_idx])
                vecs.append(dvec)

    lane_actor_index = np.asarray(pairs, dtype=np.int64).T if pairs else np.zeros((2, 0), dtype=np.int64)
    lane_actor_vectors = np.asarray(vecs, dtype=np.float32) if vecs else np.zeros((0, 2), dtype=np.float32)

    np.savez(
        out_path,
        x=x_hist.astype(np.float32),
        positions=positions.astype(np.float32),
        y=y_future.astype(np.float32),
        num_nodes=np.asarray([n], dtype=np.int64),
        padding_mask=padding_mask,
        bos_mask=bos_mask,
        rotate_angles=rotate_angles.astype(np.float32),
        lane_vectors=lane_vectors,
        lane_actor_index=lane_actor_index,
        lane_actor_vectors=lane_actor_vectors,
        agent_index=np.asarray([0], dtype=np.int64),
        av_index=np.asarray([0], dtype=np.int64),
    )


def floor_palette() -> dict[str, str]:
    return {
        "-1": "#a78bfa",
        "0": "#38bdf8",
        "1": "#34d399",
        "2": "#f59e0b",
        "2.5": "#fb7185",
        "unknown": "#94a3b8",
    }


def draw_map(ax, map_polys: list[MapPoly], active_levels: list[str]) -> None:
    pal = floor_palette()
    active = set(active_levels)

    for p in map_polys:
        color = pal.get(p.level, pal["unknown"])
        is_active = p.level in active
        alpha = 0.18 if is_active else 0.045
        lw = 0.9 if is_active else 0.4
        ax.fill(p.xy[:, 0], p.xy[:, 1], color=color, alpha=alpha, linewidth=0.0)
        ax.plot(p.xy[:, 0], p.xy[:, 1], color=color, alpha=0.5 if is_active else 0.12, linewidth=lw)


def transition_indices(floor_seq: list[str]) -> list[int]:
    out = []
    for i in range(1, len(floor_seq)):
        if floor_seq[i] != floor_seq[i - 1]:
            out.append(i)
    return out


def plot_map_rich(
    scenario: Scenario,
    routes: list[RouteTrack],
    map_polys: list[MapPoly],
    y_hat: np.ndarray,
    pi: np.ndarray,
    out_path: Path,
) -> tuple[int, np.ndarray]:
    main = routes[0].positions_xy
    hist = main[:HIST_STEPS]
    gt = main[HIST_STEPS:]

    best_mode = int(np.argmax(pi[0]))
    pred_best = y_hat[best_mode, 0, :, :2] + hist[-1]

    fig, ax = plt.subplots(figsize=(12, 9), dpi=180)
    draw_map(ax, map_polys, scenario.levels)

    # Draw other actors softly
    for r in routes[1:]:
        ax.plot(r.positions_xy[:HIST_STEPS, 0], r.positions_xy[:HIST_STEPS, 1], color="#64748b", linewidth=1.0, alpha=0.6)

    # History from GeoJSON points: emphasize points and connectors
    ax.plot(hist[:, 0], hist[:, 1], color="#0f172a", linewidth=2.5, label="History (GeoJSON points)")
    ax.scatter(hist[:, 0], hist[:, 1], color="#111827", s=18, zorder=6)

    # GT future by floor color segments
    pal = floor_palette()
    gt_floor = scenario.main_floor[HIST_STEPS:]
    for i in range(1, len(gt)):
        floor_i = gt_floor[i]
        ax.plot(gt[i - 1 : i + 1, 0], gt[i - 1 : i + 1, 1], color=pal.get(floor_i, "#f97316"), linewidth=2.8, alpha=0.95)
    ax.plot([], [], color="#f97316", linewidth=2.8, label="GT future (floor-colored)")

    # HiVT modes
    for m in range(y_hat.shape[0]):
        pred = y_hat[m, 0, :, :2] + hist[-1]
        if m == best_mode:
            ax.plot(pred[:, 0], pred[:, 1], color="#16a34a", linewidth=2.8, label="Best HiVT mode")
        else:
            ax.plot(pred[:, 0], pred[:, 1], color="#93c5fd", linewidth=1.0, alpha=0.65)

    ax.scatter([hist[-1, 0]], [hist[-1, 1]], marker="*", s=130, color="#dc2626", zorder=8, label="Current")

    # Mark floor transitions on the main route
    for idx in transition_indices(scenario.main_floor):
        x, y = main[idx]
        from_f = scenario.main_floor[idx - 1]
        to_f = scenario.main_floor[idx]
        ax.scatter([x], [y], s=55, facecolor="white", edgecolor="#b91c1c", linewidth=1.5, zorder=9)
        ax.annotate(
            f"L{from_f} -> L{to_f}",
            xy=(x, y),
            xytext=(x + 2.0, y + 2.0),
            color="#991b1b",
            fontsize=9,
            arrowprops={"arrowstyle": "->", "color": "#991b1b", "lw": 1.0},
        )

    # Floor legend helper
    legend_text = "Floor colors: " + ", ".join([f"L{lv}" for lv in scenario.levels])
    ax.text(0.01, 0.01, legend_text, transform=ax.transAxes, fontsize=9, color="#334155")

    ax.set_title(f"{scenario.scenario_id} | {scenario.route_type} | Map + History + GT + HiVT")
    ax.set_xlabel("x (m)")
    ax.set_ylabel("y (m)")
    ax.grid(alpha=0.2)
    ax.set_aspect("equal", adjustable="box")
    ax.legend(frameon=False, loc="upper right")

    fig.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)

    return best_mode, pred_best


def write_master_csv(rows: list[dict[str, Any]], path: Path) -> None:
    if not rows:
        return
    fields = list(rows[0].keys())
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def run() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    SCENE_DIR.mkdir(parents=True, exist_ok=True)
    FIG_DIR.mkdir(parents=True, exist_ok=True)
    PRED_DIR.mkdir(parents=True, exist_ok=True)

    features = load_geojson_features()
    corridors, lon0, lat0 = collect_corridor_rings(features)
    map_polys = make_map_polygons(features, lon0, lat0)
    lane_map = corridor_lanes_from_axis(corridors)

    scenarios = build_scenarios(corridors)
    model = load_model(HIVT_ROOT, CKPT_PATH, device="cpu", parallel=False)

    import torch

    all_rows: list[dict[str, Any]] = []
    summary: dict[str, Any] = {
        "title": "HiVT Indoor Route-Type Evaluation (Map-rich)",
        "history_source": "GeoJSON corridor vertices",
        "history_steps": HIST_STEPS,
        "future_steps": FUTURE_STEPS,
        "dt_seconds": DT,
        "map_input": {
            "geojson_dir": str(ROOT_DIR / "GeoJSON"),
            "lane_features_extracted": "lane_vectors, lane_actor_index, lane_actor_vectors",
        },
        "predictor_input_format": "TemporalData-like npz scene",
        "predictor_output_format": "prediction json + map-rich figure",
        "scenarios": [],
    }

    for s in scenarios:
        main_ll = local_xy_to_lonlat(s.main_xy, lon0, lat0)
        a2_ll = local_xy_to_lonlat(s.actor2_xy, lon0, lat0)
        a3_ll = local_xy_to_lonlat(s.actor3_xy, lon0, lat0)

        routes = [
            RouteTrack(route_id=f"{s.scenario_id}_A0", level="multi", feature_id=f"{s.scenario_id}_main", positions_xy=s.main_xy, positions_lon_lat=main_ll),
            RouteTrack(route_id=f"{s.scenario_id}_A1", level=s.levels[0], feature_id=f"{s.scenario_id}_a2", positions_xy=s.actor2_xy, positions_lon_lat=a2_ll),
            RouteTrack(route_id=f"{s.scenario_id}_A2", level=s.levels[0], feature_id=f"{s.scenario_id}_a3", positions_xy=s.actor3_xy, positions_lon_lat=a3_ll),
        ]

        lanes = [lane_map[lv] for lv in s.levels if lv in lane_map]
        lane_segments = np.concatenate(lanes, axis=0) if lanes else np.zeros((0, 2, 2), dtype=float)

        scene_path = SCENE_DIR / f"{s.scenario_id}.npz"
        build_scene_npz(routes, lane_segments, scene_path)

        data = build_temporal_data(scene_path).to(torch.device("cpu"))
        with torch.no_grad():
            y_hat, pi = model(data)

        y_hat_np = y_hat.detach().cpu().numpy()
        pi_np = pi.detach().cpu().numpy()

        fig_path = FIG_DIR / f"{s.scenario_id}_map_rich_prediction.png"
        best_mode, pred_best = plot_map_rich(s, routes, map_polys, y_hat_np, pi_np, fig_path)

        pred_json_path = PRED_DIR / f"{s.scenario_id}_prediction.json"
        with open(pred_json_path, "w", encoding="utf-8") as f:
            json.dump(
                {
                    "scenario_id": s.scenario_id,
                    "title": s.title,
                    "route_type": s.route_type,
                    "levels": s.levels,
                    "history_source": "GeoJSON vertices",
                    "scene_file": str(scene_path),
                    "prediction_figure": str(fig_path),
                    "pi": pi_np[0].tolist(),
                    "best_mode": best_mode,
                    "history_xy": s.main_xy[:HIST_STEPS].tolist(),
                    "history_floor": s.main_floor[:HIST_STEPS],
                    "gt_future_xy": s.main_xy[HIST_STEPS:].tolist(),
                    "gt_future_floor": s.main_floor[HIST_STEPS:],
                    "pred_best_xy": pred_best.tolist(),
                    "floor_transitions": [
                        {
                            "index": i,
                            "from": s.main_floor[i - 1],
                            "to": s.main_floor[i],
                            "x": float(s.main_xy[i, 0]),
                            "y": float(s.main_xy[i, 1]),
                        }
                        for i in range(1, TOTAL_STEPS)
                        if s.main_floor[i] != s.main_floor[i - 1]
                    ],
                },
                f,
                ensure_ascii=False,
                indent=2,
            )

        for actor_id, r in enumerate(routes):
            pos = r.positions_xy
            vel = np.zeros_like(pos)
            vel[1:] = (pos[1:] - pos[:-1]) / DT
            speed = np.linalg.norm(vel, axis=1)
            floor_seq = s.main_floor if actor_id == 0 else [s.levels[0]] * TOTAL_STEPS
            for t in range(TOTAL_STEPS):
                all_rows.append(
                    {
                        "scenario_id": s.scenario_id,
                        "scenario_title": s.title,
                        "route_type": s.route_type,
                        "actor_id": actor_id,
                        "timestep": t,
                        "is_history": 1 if t < HIST_STEPS else 0,
                        "level": floor_seq[t],
                        "lon": float(r.positions_lon_lat[t, 0]),
                        "lat": float(r.positions_lon_lat[t, 1]),
                        "x_m": float(pos[t, 0]),
                        "y_m": float(pos[t, 1]),
                        "vx_mps": float(vel[t, 0]),
                        "vy_mps": float(vel[t, 1]),
                        "speed_mps": float(speed[t]),
                    }
                )

        summary["scenarios"].append(
            {
                "scenario_id": s.scenario_id,
                "title": s.title,
                "route_type": s.route_type,
                "levels": s.levels,
                "scene": str(scene_path),
                "prediction_figure": str(fig_path),
                "prediction_json": str(pred_json_path),
            }
        )

    write_master_csv(all_rows, OUTPUT_DIR / "route_types_master.csv")

    with open(OUTPUT_DIR / "route_types_summary.json", "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    io_spec = {
        "input_to_predictor": {
            "map": {
                "source": str(ROOT_DIR / "GeoJSON"),
                "derived_lane_features": ["lane_vectors", "lane_actor_index", "lane_actor_vectors"],
            },
            "trajectory_scene": {
                "format": "npz",
                "fields": [
                    "x",
                    "positions",
                    "y",
                    "num_nodes",
                    "padding_mask",
                    "bos_mask",
                    "rotate_angles",
                    "lane_vectors",
                    "lane_actor_index",
                    "lane_actor_vectors",
                    "agent_index",
                    "av_index",
                ],
            },
            "command": "h:/HadiEnv/KalmanEmdedingSpace/Scripts/python.exe Code/EngineeringDepartment/run_hivt_route_types_maprich.py",
        },
        "output_from_predictor": {
            "numeric": [
                str(OUTPUT_DIR / "route_types_master.csv"),
                str(OUTPUT_DIR / "route_types_summary.json"),
                str(PRED_DIR),
            ],
            "visual": str(FIG_DIR),
        },
    }

    with open(OUTPUT_DIR / "inference_io_spec.json", "w", encoding="utf-8") as f:
        json.dump(io_spec, f, ensure_ascii=False, indent=2)

    report = OUTPUT_DIR / "FINAL_REPORT_HiVT_Indoor_Route_Types.md"
    with open(report, "w", encoding="utf-8") as f:
        f.write("# گزارش نهایی: HiVT روی مسیرهای داخلی با نقشه چندطبقه\n\n")
        f.write("## چه چیزی اصلاح شد\n\n")
        f.write("- مسیرها روی نقشه داخلی GeoJSON رسم شدند (نه نمودار خالی).\n")
        f.write("- هر طبقه با رنگ جداگانه نمایش داده شد.\n")
        f.write("- تغییر طبقه با annotation (Lx -> Ly) روی مسیر اصلی مشخص شد.\n")
        f.write("- در هر شکل، History (از نقاط GeoJSON)، GT Future و پیش بینی HiVT همزمان رسم شد.\n\n")

        f.write("## سناریوهای اجراشده\n\n")
        for s in summary["scenarios"]:
            f.write(f"- {s['scenario_id']} | {s['route_type']} | levels={','.join(s['levels'])}\n")

        f.write("\n## ورودی کد پیش بینی\n\n")
        f.write("1. نقشه: GeoJSON های داخلی ساختمان\n")
        f.write("2. مسیر: scene های NPZ شامل x/positions/y و lane features\n")
        f.write("3. اجرای پیش بینی: run_hivt_route_types_maprich.py\n\n")

        f.write("## خروجی کد پیش بینی\n\n")
        f.write("- JSON پیش بینی هر سناریو در predictions\n")
        f.write("- تصویر نقشه-غنی هر سناریو در figures\n")
        f.write("- CSV تجمیعی قابل انتقال: route_types_master.csv\n")
        f.write("- خلاصه سناریوها: route_types_summary.json\n")
        f.write("- قرارداد I/O: inference_io_spec.json\n")

    print("Map-rich HiVT route-type evaluation completed")
    print(f"output: {OUTPUT_DIR}")


if __name__ == "__main__":
    run()
