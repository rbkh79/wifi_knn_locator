# Kalman + Frozen Encoder (Embedding Residual Correction)

This folder contains a practical baseline for the pipeline:

1. State history input: `[x, y, vx, vy, ...]`
2. Frozen pre-trained encoder (template for HiVT/AgentFormer/Wayformer/MTR)
3. Embedding space (128-dim default)
4. Kalman filter state update with covariance
5. Predicted trajectory/state output

## Key idea implemented

Embedding is used as **measurement residual correction** during Kalman update:

`z_tilde = z + G @ (embedding - e_pred)`

- `embedding`: output from frozen encoder
- `e_pred = W_embed @ x`: embedding predicted from current Kalman state
- `G @ (embedding - e_pred)`: correction added to measurement before update

Important clarification:

- Kalman filtering is done in physical state space `[x, y, vx, vy]`.
- The code does not track a trajectory directly in raw 64/128-d embedding space.
- Embedding is used only to improve measurement update quality.

## Run

From workspace root:

```powershell
h:/HadiEnv/KalmanEmdedingSpace/Scripts/python.exe Code/kalman_embedding_pipeline.py
```

## Replace with real HiVT

The official HiVT repository is not a Hugging Face style package with
`from_pretrained()`. The repo is used by cloning it and loading a Lightning
checkpoint directly, for example:

```python
model = HiVT.load_from_checkpoint(checkpoint_path=ckpt_path, parallel=True)
```

So if you want the real model, clone the HiVT repository, download the matching
pretrained checkpoint, then adapt `try_build_hivt_encoder()` to the repo's
actual constructor and checkpoint loading code.

The integration points are:

1. build the encoder from the cloned repo
2. load the pretrained checkpoint manually
3. freeze all encoder parameters
4. return the embedding to `update_with_embedding()`
