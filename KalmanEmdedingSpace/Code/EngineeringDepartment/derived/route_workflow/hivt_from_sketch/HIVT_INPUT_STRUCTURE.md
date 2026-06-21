# HiVT Input Structure (From Approved Sketch + GeoJSON)

این خروجی دقیقا داده‌های لازم برای `TemporalData` در HiVT را تولید می‌کند.

## Required Tensors

- x: [N,20,2] history offsets
- positions: [N,50,2] absolute xy
- y: [N,30,2] future offsets from t=19
- padding_mask: [N,50] bool
- bos_mask: [N,20] bool
- rotate_angles: [N] rad
- lane_vectors: [L,2]
- lane_actor_index: [2,E] long
- lane_actor_vectors: [E,2]
- agent_index: [1]
- av_index: [1]

## Checkpoints

- checkpointها در `route_checkpoints.csv` ذخیره می‌شوند (اندیس‌های 0,10,20,30,40,49).
- این checkpointها برای گزارش مقاله، مقایسه مسیرها و کنترل کیفیت قابل استفاده هستند.

## Scene Files

- scene npz directory: H:\HadiEnv\KalmanEmdedingSpace\Code\EngineeringDepartment\derived\route_workflow\hivt_from_sketch\scenes
- manifest: H:\HadiEnv\KalmanEmdedingSpace\Code\EngineeringDepartment\derived\route_workflow\hivt_from_sketch\hivt_manifest.json
