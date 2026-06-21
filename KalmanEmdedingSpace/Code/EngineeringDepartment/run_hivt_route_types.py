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
class Scenario:
    scenario_id: str
    title: str
    route_type: str
    main_levels: list[str]
    polylines: list[np.ndarray]  # actor polylines in local xy


def sample_polyline(polyline: np.ndarray, n_points: int) -> np.ndarray:
    if polyline.shape[0] < 2:
        raise ValueError("Polyline must have at least 2 points")

    seg_vec = polyline[1:] - polyline[:-1]
    seg_len = np.linalg.norm(seg_vec, axis=1)
    cumulative = np.concatenate([[0.0], np.cumsum(seg_len)])
    total = float(cumulative[-1])
    if total < 1e-9:
        return np.repeat(polyline[:1], n_points, axis=0)

    targets = np.linspace(0.0, total, n_points)
    out = np.zeros((n_points, 2), dtype=float)

    j = 0
    for i, t in enumerate(targets):
        while j < len(seg_len) - 1 and cumulative[j + 1] < t:
            j += 1
        left = cumulative[j]
        right = cumulative[j + 1]
        alpha = 0.0 if right - left < 1e-9 else (t - left) / (right - left)
        out[i] = polyline[j] * (1.0 - alpha) + polyline[j + 1] * alpha
    return out


def offset_path(path: np.ndarray, offset_m: float) -> np.ndarray:
    grad = np.gradient(path, axis=0)
    tangent = grad / (np.linalg.norm(grad, axis=1, keepdims=True) + 1e-9)
    perp = np.stack([-tangent[:, 1], tangent[:, 0]], axis=1)
    return path + offset_m * perp


def corridor_axis_line(c: CorridorFeature) -> np.ndarray:
    center, major, length = principal_axis(c.xy_m)
    p0 = center - major * (0.45 * length)
    p1 = center + major * (0.45 * length)
    return np.stack([p0, p1], axis=0)


def make_route_tracks(
    scenario_id: str,
    level: str,
    polylines: list[np.ndarray],
    lon0: float,
    lat0: float,
) -> list[RouteTrack]:
    tracks: list[RouteTrack] = []
    for i, polyline in enumerate(polylines):
        pos_xy = sample_polyline(polyline, TOTAL_STEPS)
        pos_ll = local_xy_to_lonlat(pos_xy, lon0, lat0)
        tracks.append(
            RouteTrack(
                route_id=f"{scenario_id}_actor_{i:02d}",
                level=level,
                feature_id=f"{scenario_id}_feature_{i:02d}",
                positions_xy=pos_xy,
                positions_lon_lat=pos_ll,
            )
        )
    return tracks


def build_scenarios(corridors: list[CorridorFeature]) -> list[Scenario]:
    by_level: dict[str, list[CorridorFeature]] = {}
    for c in corridors:
        by_level.setdefault(c.level, []).append(c)

    for level in by_level:
        by_level[level] = sorted(by_level[level], key=lambda x: principal_axis(x.xy_m)[2], reverse=True)

    # 1) ordinary corridor route
    c1 = by_level.get("0", by_level[list(by_level.keys())[0]])[0]
    line1 = corridor_axis_line(c1)
    main1 = line1
    actor1_b = offset_path(sample_polyline(main1, 8), 0.9)
    actor1_c = offset_path(sample_polyline(main1, 8), -0.8)
    scenario1 = Scenario(
        scenario_id="S1",
        title="Normal corridor route",
        route_type="normal_single_corridor",
        main_levels=["0"],
        polylines=[main1, actor1_b, actor1_c],
    )

    # 2) long straight between two corridors
    l0 = by_level.get("0", by_level[list(by_level.keys())[0]])
    c2a = l0[0]
    c2b = l0[min(3, len(l0) - 1)]
    a_line = corridor_axis_line(c2a)
    b_line = corridor_axis_line(c2b)
    main2 = np.stack([a_line[0], b_line[1]], axis=0)
    actor2_b = offset_path(sample_polyline(main2, 6), 1.1)
    actor2_c = offset_path(sample_polyline(main2, 6), -1.0)
    scenario2 = Scenario(
        scenario_id="S2",
        title="Long straight route between corridors",
        route_type="long_straight_between_corridors",
        main_levels=["0"],
        polylines=[main2, actor2_b, actor2_c],
    )

    # 3) long winding route
    l1 = by_level.get("1", l0)
    points3 = []
    for c in l1[:4]:
        center, _, _ = principal_axis(c.xy_m)
        points3.append(center)
    points3 = np.asarray(points3, dtype=float)
    order = np.argsort(points3[:, 0] + 0.45 * points3[:, 1])
    base3 = points3[order]
    mid = (base3[1] + base3[2]) / 2.0 + np.array([2.5, -2.0])
    main3 = np.vstack([base3[0], base3[1], mid, base3[2], base3[3]])
    actor3_b = offset_path(sample_polyline(main3, 12), 0.9)
    actor3_c = offset_path(sample_polyline(main3, 12), -0.9)
    scenario3 = Scenario(
        scenario_id="S3",
        title="Long winding route",
        route_type="long_winding",
        main_levels=["1"],
        polylines=[main3, actor3_b, actor3_c],
    )

    # 4-a) normal multi-floor route
    c4_0 = by_level.get("0", l0)[0]
    c4_1 = by_level.get("1", l1)[0]
    c4_2 = by_level.get("2", by_level.get("2.5", l1))[0]
    p0 = principal_axis(c4_0.xy_m)[0]
    p1 = principal_axis(c4_1.xy_m)[0] + np.array([1.5, -1.0])
    p2 = principal_axis(c4_2.xy_m)[0] + np.array([2.0, -2.0])
    main4n = np.vstack([p0, p1, p2])
    actor4n_b = offset_path(sample_polyline(main4n, 8), 0.6)
    actor4n_c = offset_path(sample_polyline(main4n, 8), -0.6)
    scenario4n = Scenario(
        scenario_id="S4N",
        title="Normal multi-floor route",
        route_type="multi_floor_normal",
        main_levels=["0", "1", "2"],
        polylines=[main4n, actor4n_b, actor4n_c],
    )

    # 4-b) long multi-floor route
    stair_a = (p0 + p1) / 2.0 + np.array([0.6, 0.9])
    stair_b = (p1 + p2) / 2.0 + np.array([-0.8, 1.1])
    main4 = np.vstack([p0, stair_a, p1, stair_b, p2])
    actor4_b = offset_path(sample_polyline(main4, 10), 0.7)
    actor4_c = offset_path(sample_polyline(main4, 10), -0.7)
    scenario4 = Scenario(
        scenario_id="S4L",
        title="Long multi-floor route",
        route_type="multi_floor_long",
        main_levels=["0", "1", "2"],
        polylines=[main4, actor4_b, actor4_c],
    )

    return [scenario1, scenario2, scenario3, scenario4n, scenario4]


def write_master_csv(rows: list[dict[str, Any]], path: Path) -> None:
    if not rows:
        return
    fields = list(rows[0].keys())
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


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


def plot_input_scenario(corridors: list[CorridorFeature], scenario: Scenario, routes: list[RouteTrack], out_path: Path) -> None:
    fig, ax = plt.subplots(figsize=(9.5, 7.5), dpi=180)
    level_set = set(scenario.main_levels)

    for c in corridors:
        if c.level in level_set:
            ax.plot(c.xy_m[:, 0], c.xy_m[:, 1], color="#cbd5e1", linewidth=1.0, alpha=0.9)

    for idx, r in enumerate(routes):
        color = "#0ea5e9" if idx == 0 else "#22c55e"
        ax.plot(r.positions_xy[:, 0], r.positions_xy[:, 1], color=color, linewidth=2.0 if idx == 0 else 1.4)
        ax.scatter([r.positions_xy[0, 0]], [r.positions_xy[0, 1]], color="#ef4444", s=13)

    ax.set_title(f"{scenario.scenario_id}: {scenario.title}")
    ax.set_xlabel("x (m)")
    ax.set_ylabel("y (m)")
    ax.grid(alpha=0.22)
    ax.set_aspect("equal", adjustable="box")
    fig.tight_layout()
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)


def plot_prediction(scene_path: Path, scenario: Scenario, y_hat: np.ndarray, pi: np.ndarray, out_path: Path) -> tuple[int, np.ndarray]:
    arr = np.load(scene_path)
    positions = arr["positions"]
    hist = positions[0, :HIST_STEPS]
    gt = positions[0, HIST_STEPS:]
    best_mode = int(np.argmax(pi[0]))

    fig, ax = plt.subplots(figsize=(9.5, 7.0), dpi=180)
    ax.plot(hist[:, 0], hist[:, 1], color="#0f172a", linewidth=2.3, label="History")
    ax.plot(gt[:, 0], gt[:, 1], color="#f97316", linewidth=2.2, label="GT future")

    for m in range(y_hat.shape[0]):
        pred_abs = y_hat[m, 0, :, :2] + hist[-1]
        if m == best_mode:
            ax.plot(pred_abs[:, 0], pred_abs[:, 1], color="#16a34a", linewidth=2.6, label="Best HiVT mode")
        else:
            ax.plot(pred_abs[:, 0], pred_abs[:, 1], color="#93c5fd", linewidth=1.1, alpha=0.8)

    ax.scatter([hist[-1, 0]], [hist[-1, 1]], marker="*", s=90, color="#dc2626", label="Current")
    ax.set_title(f"HiVT Prediction | {scenario.scenario_id} - {scenario.route_type}")
    ax.set_xlabel("x (m)")
    ax.set_ylabel("y (m)")
    ax.grid(alpha=0.22)
    ax.legend(frameon=False, loc="best")
    ax.set_aspect("equal", adjustable="box")
    fig.tight_layout()
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)

    pred_best = y_hat[best_mode, 0, :, :2] + hist[-1]
    return best_mode, pred_best


def run() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    SCENE_DIR.mkdir(parents=True, exist_ok=True)
    FIG_DIR.mkdir(parents=True, exist_ok=True)
    PRED_DIR.mkdir(parents=True, exist_ok=True)

    all_features = load_geojson_features()
    corridors, lon0, lat0 = collect_corridor_rings(all_features)
    lane_map = corridor_lanes_from_axis(corridors)

    scenarios = build_scenarios(corridors)
    model = load_model(HIVT_ROOT, CKPT_PATH, device="cpu", parallel=False)

    import torch

    all_rows: list[dict[str, Any]] = []
    summary: dict[str, Any] = {
        "title": "HiVT Route-Type Evaluation on EngineeringDepartment Indoor Map",
        "history_steps": HIST_STEPS,
        "future_steps": FUTURE_STEPS,
        "dt_seconds": DT,
        "scenarios": [],
    }

    for scenario in scenarios:
        level_for_track = scenario.main_levels[0]
        routes = make_route_tracks(scenario.scenario_id, level_for_track, scenario.polylines, lon0, lat0)

        lane_segments = []
        for lv in scenario.main_levels:
            if lv in lane_map:
                lane_segments.append(lane_map[lv])
        lane_segments_arr = np.concatenate(lane_segments, axis=0) if lane_segments else np.zeros((0, 2, 2), dtype=float)

        scene_path = SCENE_DIR / f"{scenario.scenario_id}.npz"
        build_scene_npz(routes, lane_segments_arr, scene_path)

        plot_input_scenario(corridors, scenario, routes, FIG_DIR / f"{scenario.scenario_id}_input.png")

        data = build_temporal_data(scene_path)
        data = data.to(torch.device("cpu"))
        with torch.no_grad():
            y_hat, pi = model(data)

        y_hat_np = y_hat.detach().cpu().numpy()
        pi_np = pi.detach().cpu().numpy()
        best_mode, pred_best = plot_prediction(
            scene_path,
            scenario,
            y_hat_np,
            pi_np,
            FIG_DIR / f"{scenario.scenario_id}_prediction.png",
        )

        pred_json_path = PRED_DIR / f"{scenario.scenario_id}_prediction.json"
        with open(pred_json_path, "w", encoding="utf-8") as f:
            json.dump(
                {
                    "scenario_id": scenario.scenario_id,
                    "title": scenario.title,
                    "route_type": scenario.route_type,
                    "levels": scenario.main_levels,
                    "scene_file": str(scene_path),
                    "pi": pi_np[0].tolist(),
                    "best_mode": best_mode,
                    "pred_best_xy": pred_best.tolist(),
                },
                f,
                ensure_ascii=False,
                indent=2,
            )

        for actor_idx, r in enumerate(routes):
            pos = r.positions_xy
            vel = np.zeros_like(pos)
            vel[1:] = (pos[1:] - pos[:-1]) / DT
            speed = np.linalg.norm(vel, axis=1)
            for t in range(TOTAL_STEPS):
                all_rows.append(
                    {
                        "scenario_id": scenario.scenario_id,
                        "scenario_title": scenario.title,
                        "route_type": scenario.route_type,
                        "levels": "|".join(scenario.main_levels),
                        "actor_id": actor_idx,
                        "timestep": t,
                        "is_history": 1 if t < HIST_STEPS else 0,
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
                "scenario_id": scenario.scenario_id,
                "title": scenario.title,
                "route_type": scenario.route_type,
                "levels": scenario.main_levels,
                "scene": str(scene_path),
                "input_figure": str(FIG_DIR / f"{scenario.scenario_id}_input.png"),
                "prediction_figure": str(FIG_DIR / f"{scenario.scenario_id}_prediction.png"),
                "prediction_json": str(pred_json_path),
                "num_actors": len(routes),
            }
        )

    write_master_csv(all_rows, OUTPUT_DIR / "route_types_master.csv")
    with open(OUTPUT_DIR / "route_types_summary.json", "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    report_path = OUTPUT_DIR / "REPORT_HiVT_Route_Types.md"
    with open(report_path, "w", encoding="utf-8") as f:
        f.write("# HiVT Route-Type Evaluation Report\n\n")
        f.write("این گزارش شامل 4 سناریوی مسیر در نقشه داخلی دانشکده و خروجی پیش بینی HiVT است.\n\n")
        f.write("## Scenario List\n\n")
        for item in summary["scenarios"]:
            f.write(f"- {item['scenario_id']} | {item['route_type']} | levels={','.join(item['levels'])}\n")
        f.write("\n## Output Files\n\n")
        f.write("- route_types_master.csv\n")
        f.write("- route_types_summary.json\n")
        f.write("- scenes/*.npz\n")
        f.write("- predictions/*_prediction.json\n")
        f.write("- figures/*_input.png and *_prediction.png\n")

    print("HiVT route-type evaluation completed")
    print(f"output dir: {OUTPUT_DIR}")


if __name__ == "__main__":
    run()
