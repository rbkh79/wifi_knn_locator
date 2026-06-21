# Engineering Department - Generated Routes and HiVT-ready Data

This folder was generated from indoor GeoJSON files in `Code/EngineeringDepartment/GeoJSON`.

## What was generated

- `corridor_routes.csv`: time-indexed indoor trajectories on corridor axes.
- `corridor_routes.geojson`: routes as LineString features for GIS review.
- `routes_preview_level_*.png`: level-wise route preview over corridor polygons.
- `routes_overlay_osm_1.png`, `routes_overlay_osm_2.png`: approximate visual overlays over provided OSM images.
- `hivt_ready/scene_*.npz`: scene-wise arrays compatible with HiVT-style TemporalData inputs.
- `hivt_ready/hivt_manifest.json`: manifest describing scenes and dimensions.
- `summary.json`: generation summary.

## CSV schema

`route_id, level, feature_id, timestep, is_history, lon, lat, x_m, y_m, vx_mps, vy_mps, speed_mps`

- `is_history=1` for timesteps 0..19
- `is_history=0` for timesteps 20..49
- One trajectory has 50 timesteps (20 history + 30 future)

## HiVT scene arrays in NPZ

- `x`: [N, 20, 2] historical displacement input
- `positions`: [N, 50, 2] absolute local positions
- `y`: [N, 30, 2] future displacement target
- `padding_mask`: [N, 50]
- `bos_mask`: [N, 20]
- `rotate_angles`: [N]
- `lane_vectors`: [L, 2]
- `lane_actor_index`: [2, E]
- `lane_actor_vectors`: [E, 2]
- `agent_index`: [1]
- `av_index`: [1]

## Inference compatibility note

`hivt_inference_from_derived.py` is included to run checkpoint inference on generated scenes, but this repository's HiVT code is sensitive to exact PyTorch/PyG/Lightning versions. In the current environment, checkpoint loading is solved, but model forward fails due a torch API mismatch (`is_causal` argument) and needs a compatible torch stack (typically older than current 2.8 behavior).
