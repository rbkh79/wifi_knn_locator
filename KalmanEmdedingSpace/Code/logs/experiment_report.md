# Experiment Report

## Configuration

- SNR dB: 5.0
- Noise std: 2.3310
- History length: 12
- Steps: 180

## Metrics

- Measurement RMSE: 2.1988
- Input KF RMSE: 1.3987
- Embedding-corrected KF RMSE: 1.2816

## Interpretation

Both filters estimate the same physical state [x, y, vx, vy]. The second filter adds embedding residual as a measurement correction term, rather than tracking dynamics directly in latent embedding space.
