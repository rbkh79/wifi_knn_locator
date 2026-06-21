from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Protocol
import json
import logging
import math

import numpy as np

try:
    import matplotlib.pyplot as plt
except Exception as exc:  # pragma: no cover
    raise RuntimeError(
        "matplotlib is required for figure generation. Install it in the venv first."
    ) from exc


ROOT_DIR = Path(__file__).resolve().parent
FIGURE_DIR = ROOT_DIR / "figure_Out"
LOG_DIR = ROOT_DIR / "logs"


class EncoderProtocol(Protocol):
    def encode(self, trajectory_history: np.ndarray) -> np.ndarray:
        """Encode history into a fixed-size embedding."""

    def freeze(self) -> None:
        """Freeze encoder weights (no training updates)."""


class FrozenLinearEncoder:
    """
    Minimal stand-in for a pre-trained trajectory encoder.

    In production, replace this class with HiVT/AgentFormer/Wayformer/MTR
    and keep `.freeze()` behavior.
    """

    def __init__(self, input_dim: int, embedding_dim: int = 128, seed: int = 7) -> None:
        rng = np.random.default_rng(seed)
        self.weight = rng.normal(0.0, 0.05, size=(embedding_dim, input_dim))
        self.bias = rng.normal(0.0, 0.01, size=(embedding_dim,))
        self._frozen = False

    def freeze(self) -> None:
        self._frozen = True

    def encode(self, trajectory_history: np.ndarray) -> np.ndarray:
        flat = trajectory_history.reshape(-1)
        emb = self.weight @ flat + self.bias
        return np.tanh(emb)


@dataclass
class KalmanConfig:
    dt: float = 0.1
    process_noise: float = 0.15
    measurement_noise: float = 0.35
    embed_noise: float = 0.20


@dataclass
class ExperimentConfig:
    history_len: int = 12
    steps: int = 180
    snr_db: float = 5.0
    embedding_dim: int = 128
    random_seed: int = 42


class ConstantVelocityKalmanFilter:
    """Standard Kalman filter in input/state space."""

    def __init__(self, config: KalmanConfig) -> None:
        dt = config.dt
        self.x = np.zeros(4, dtype=float)
        self.P = np.eye(4, dtype=float) * 10.0
        self.F = np.array(
            [
                [1.0, 0.0, dt, 0.0],
                [0.0, 1.0, 0.0, dt],
                [0.0, 0.0, 1.0, 0.0],
                [0.0, 0.0, 0.0, 1.0],
            ],
            dtype=float,
        )
        self.H = np.array(
            [
                [1.0, 0.0, 0.0, 0.0],
                [0.0, 1.0, 0.0, 0.0],
            ],
            dtype=float,
        )
        self.Q = np.eye(4, dtype=float) * config.process_noise
        self.R = np.eye(2, dtype=float) * config.measurement_noise

    def initialize_from_state(self, state: np.ndarray) -> None:
        self.x = np.asarray(state, dtype=float).copy()
        self.P = np.eye(4, dtype=float) * 5.0

    def predict(self) -> np.ndarray:
        self.x = self.F @ self.x
        self.P = self.F @ self.P @ self.F.T + self.Q
        return self.x.copy()

    def update(self, z_pos: np.ndarray) -> np.ndarray:
        z = np.asarray(z_pos, dtype=float)
        y = z - self.H @ self.x
        s_mat = self.H @ self.P @ self.H.T + self.R
        k_gain = self.P @ self.H.T @ np.linalg.inv(s_mat)
        self.x = self.x + k_gain @ y
        self.P = (np.eye(4) - k_gain @ self.H) @ self.P
        return self.x.copy()


class EmbeddingCorrectedKalmanFilter(ConstantVelocityKalmanFilter):
    """Kalman filter with embedding residual correction."""

    def __init__(self, embedding_dim: int, config: KalmanConfig) -> None:
        super().__init__(config)
        rng = np.random.default_rng(23)
        self.W_embed = rng.normal(0.0, 0.1, size=(embedding_dim, 4))
        self.G = rng.normal(0.0, 0.03, size=(2, embedding_dim))
        self.embed_noise = config.embed_noise

    def update_with_embedding(self, z_pos: np.ndarray, embedding: np.ndarray) -> np.ndarray:
        e_pred = self.W_embed @ self.x
        embed_residual = np.asarray(embedding, dtype=float) - e_pred
        correction = self.G @ embed_residual
        z_tilde = np.asarray(z_pos, dtype=float) + correction

        y = z_tilde - self.H @ self.x
        s_mat = self.H @ self.P @ self.H.T + self.R + np.eye(2) * self.embed_noise
        k_gain = self.P @ self.H.T @ np.linalg.inv(s_mat)
        self.x = self.x + k_gain @ y
        self.P = (np.eye(4) - k_gain @ self.H) @ self.P
        return self.x.copy()


class TrajectoryPipeline:
    def __init__(self, history_len: int = 12, embedding_dim: int = 128) -> None:
        self.history_len = history_len
        self.state_dim = 4
        self.embedding_dim = embedding_dim
        self.encoder = FrozenLinearEncoder(
            input_dim=history_len * self.state_dim,
            embedding_dim=embedding_dim,
        )
        self.encoder.freeze()

    def encode(self, trajectory_history: np.ndarray) -> np.ndarray:
        return self.encoder.encode(trajectory_history)


def try_build_hivt_encoder() -> EncoderProtocol | None:
    """Optional integration point for a real frozen HiVT encoder.

    The official HiVT repository is evaluated with:

        model = HiVT.load_from_checkpoint(checkpoint_path=ckpt_path, parallel=True)

    If you want a real encoder here, clone the repository, load the checkpoint
    manually with the repo's LightningModule class, and expose the internal
    embedding path you need.
    """

    # The actual HiVT constructor and checkpoint loading are repo-specific and
    # depend on the cloned source tree. Return None here so the synthetic
    # fallback stays correct until a concrete adapter is wired in.
    return None


def make_directories() -> None:
    FIGURE_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)


def configure_logger() -> logging.Logger:
    logger = logging.getLogger("kalman_embedding_experiment")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()

    formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")

    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(formatter)
    logger.addHandler(stream_handler)

    file_handler = logging.FileHandler(LOG_DIR / "run.log", encoding="utf-8")
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    return logger


def build_sinusoidal_trajectory(config: ExperimentConfig) -> dict[str, np.ndarray]:
    dt = 0.1
    time = np.arange(config.steps, dtype=float) * dt
    x_true = 8.0 * np.sin(0.35 * time) + 0.12 * time
    y_true = 4.0 * np.cos(0.22 * time) + 0.08 * time
    vx_true = np.gradient(x_true, dt)
    vy_true = np.gradient(y_true, dt)

    rng = np.random.default_rng(config.random_seed)
    signal_power = float(np.mean(x_true**2 + y_true**2) / 2.0)
    snr_linear = 10 ** (config.snr_db / 10.0)
    noise_power = signal_power / snr_linear
    noise_std = math.sqrt(noise_power)

    x_meas = x_true + rng.normal(0.0, noise_std, size=time.shape)
    y_meas = y_true + rng.normal(0.0, noise_std, size=time.shape)
    vx_meas = np.gradient(x_meas, dt)
    vy_meas = np.gradient(y_meas, dt)

    state_meas = np.stack([x_meas, y_meas, vx_meas, vy_meas], axis=1)
    state_true = np.stack([x_true, y_true, vx_true, vy_true], axis=1)
    position_meas = np.stack([x_meas, y_meas], axis=1)

    return {
        "time": time,
        "state_true": state_true,
        "state_meas": state_meas,
        "position_meas": position_meas,
        "noise_std": np.array([noise_std], dtype=float),
        "signal_power": np.array([signal_power], dtype=float),
        "snr_db": np.array([config.snr_db], dtype=float),
    }


def sliding_history(state_sequence: np.ndarray, index: int, history_len: int) -> np.ndarray:
    start = max(0, index - history_len + 1)
    history = state_sequence[start : index + 1]
    if len(history) < history_len:
        pad = np.repeat(history[:1], history_len - len(history), axis=0)
        history = np.concatenate([pad, history], axis=0)
    return history[-history_len:]


def run_experiment(config: ExperimentConfig) -> dict[str, np.ndarray | dict[str, float] | list[str]]:
    logger = configure_logger()
    logger.info("Starting experiment with config: %s", asdict(config))

    synth = build_sinusoidal_trajectory(config)
    time = synth["time"]
    state_true = synth["state_true"]
    state_meas = synth["state_meas"]
    position_meas = synth["position_meas"]
    noise_std = float(synth["noise_std"][0])

    pipeline = TrajectoryPipeline(history_len=config.history_len, embedding_dim=config.embedding_dim)
    hivt_encoder = try_build_hivt_encoder()

    input_kf = ConstantVelocityKalmanFilter(KalmanConfig())
    embedding_corrected_kf = EmbeddingCorrectedKalmanFilter(config.embedding_dim, KalmanConfig())

    input_kf.initialize_from_state(state_meas[0])
    embedding_corrected_kf.initialize_from_state(state_meas[0])

    input_estimates = [input_kf.x.copy()]
    embedding_corrected_estimates = [embedding_corrected_kf.x.copy()]
    embeddings = []
    residual_norms = []
    encoder_name = "HiVT" if hivt_encoder is not None else "FrozenLinearEncoder"

    if hivt_encoder is not None:
        encoder = hivt_encoder
        logger.info("HiVT encoder detected and frozen adapter is active.")
    else:
        encoder = pipeline.encoder
        logger.info("HiVT not available; using frozen synthetic encoder as drop-in baseline.")

    for idx in range(1, len(time)):
        history = sliding_history(state_meas, idx, config.history_len)
        embedding = encoder.encode(history)
        embeddings.append(embedding)

        input_kf.predict()
        input_state = input_kf.update(position_meas[idx])
        input_estimates.append(input_state)

        embedding_corrected_kf.predict()
        e_pred = embedding_corrected_kf.W_embed @ embedding_corrected_kf.x
        residual_norms.append(float(np.linalg.norm(embedding - e_pred)))
        corrected_state = embedding_corrected_kf.update_with_embedding(position_meas[idx], embedding)
        embedding_corrected_estimates.append(corrected_state)

    input_estimates_arr = np.asarray(input_estimates)
    embedding_corrected_estimates_arr = np.asarray(embedding_corrected_estimates)
    embeddings_arr = np.asarray(embeddings)
    residual_norms_arr = np.asarray(residual_norms)

    rmse_input = float(np.sqrt(np.mean((input_estimates_arr[:, :2] - state_true[: len(input_estimates_arr), :2]) ** 2)))
    rmse_embedding_corrected = float(
        np.sqrt(
            np.mean(
                (embedding_corrected_estimates_arr[:, :2] - state_true[: len(embedding_corrected_estimates_arr), :2]) ** 2
            )
        )
    )
    meas_rmse = float(np.sqrt(np.mean((position_meas[:, :2] - state_true[:, :2]) ** 2)))

    metrics = {
        "snr_db": config.snr_db,
        "noise_std": noise_std,
        "measurement_rmse": meas_rmse,
        "input_kf_rmse": rmse_input,
        "embedding_corrected_kf_rmse": rmse_embedding_corrected,
        # Backward-compatible alias for older logs/scripts.
        "embedding_kf_rmse": rmse_embedding_corrected,
        "history_len": config.history_len,
        "steps": config.steps,
    }

    logger.info("Metrics: %s", metrics)

    payload = {
        "config": asdict(config),
        "metrics": metrics,
        "encoder": encoder_name,
        "time": time,
        "state_true": state_true,
        "state_meas": state_meas,
        "position_meas": position_meas,
        "input_estimates": input_estimates_arr,
        "embedding_corrected_estimates": embedding_corrected_estimates_arr,
        # Backward-compatible alias for older logs/scripts.
        "embedding_estimates": embedding_corrected_estimates_arr,
        "embeddings": embeddings_arr,
        "residual_norms": residual_norms_arr,
    }

    save_outputs(payload, logger)
    return payload


def save_outputs(payload: dict[str, np.ndarray | dict[str, float] | list[str]], logger: logging.Logger) -> None:
    time = payload["time"]
    state_true = payload["state_true"]
    state_meas = payload["state_meas"]
    input_estimates = payload["input_estimates"]
    embedding_corrected_estimates = payload["embedding_corrected_estimates"]
    residual_norms = payload["residual_norms"]
    metrics = payload["metrics"]

    np.savez(
        LOG_DIR / "experiment_data.npz",
        time=time,
        state_true=state_true,
        state_meas=state_meas,
        input_estimates=input_estimates,
        embedding_corrected_estimates=embedding_corrected_estimates,
        # Backward-compatible alias for older readers.
        embedding_estimates=embedding_corrected_estimates,
        residual_norms=residual_norms,
    )

    with open(LOG_DIR / "experiment_summary.json", "w", encoding="utf-8") as handle:
        json.dump(
            {
                "metrics": metrics,
                "notes": [
                    "Synthetic sinusoidal trajectory with SNR=5 dB",
                    "Input-space KF uses raw noisy positions",
                    "A second state-space KF uses embedding residual only for measurement correction",
                    "No direct trajectory tracking is performed in raw 64/128-d embedding space",
                    "HiVT is used if importable; otherwise frozen linear encoder is the fallback",
                ],
            },
            handle,
            indent=2,
            ensure_ascii=False,
        )

    with open(LOG_DIR / "experiment_report.md", "w", encoding="utf-8") as handle:
        handle.write("# Experiment Report\n\n")
        handle.write("## Configuration\n\n")
        handle.write(f"- SNR dB: {metrics['snr_db']}\n")
        handle.write(f"- Noise std: {metrics['noise_std']:.4f}\n")
        handle.write(f"- History length: {metrics['history_len']}\n")
        handle.write(f"- Steps: {metrics['steps']}\n\n")
        handle.write("## Metrics\n\n")
        handle.write(f"- Measurement RMSE: {metrics['measurement_rmse']:.4f}\n")
        handle.write(f"- Input KF RMSE: {metrics['input_kf_rmse']:.4f}\n")
        handle.write(f"- Embedding-corrected KF RMSE: {metrics['embedding_corrected_kf_rmse']:.4f}\n\n")
        handle.write("## Interpretation\n\n")
        handle.write(
            "Both filters estimate the same physical state [x, y, vx, vy]. "
            "The second filter adds embedding residual as a measurement correction term, "
            "rather than tracking dynamics directly in latent embedding space.\n"
        )

    plot_trajectory(time, state_true, state_meas, input_estimates, embedding_corrected_estimates)
    plot_error_curves(time, state_true, state_meas, input_estimates, embedding_corrected_estimates)
    plot_embedding_diagnostics(time, residual_norms)

    logger.info("Saved figures to %s", FIGURE_DIR)
    logger.info("Saved logs to %s", LOG_DIR)


def plot_trajectory(
    time: np.ndarray,
    state_true: np.ndarray,
    state_meas: np.ndarray,
    input_estimates: np.ndarray,
    embedding_corrected_estimates: np.ndarray,
) -> None:
    fig, axes = plt.subplots(1, 3, figsize=(18, 5.5), dpi=160)

    axes[0].plot(state_true[:, 0], state_true[:, 1], color="#111827", linewidth=2.5, label="Ground truth")
    axes[0].scatter(state_meas[:, 0], state_meas[:, 1], s=10, color="#d97706", alpha=0.45, label="Noisy input")
    axes[0].plot(input_estimates[:, 0], input_estimates[:, 1], color="#2563eb", linewidth=2.0, label="Input-space KF")
    axes[0].plot(
        embedding_corrected_estimates[:, 0],
        embedding_corrected_estimates[:, 1],
        color="#16a34a",
        linewidth=2.0,
        label="State KF + embedding correction",
    )
    axes[0].set_title("Trajectory in XY Space")
    axes[0].set_xlabel("x")
    axes[0].set_ylabel("y")
    axes[0].grid(alpha=0.25)
    axes[0].legend(frameon=False)

    axes[1].plot(time, state_true[:, 0], color="#111827", linewidth=2.0, label="x true")
    axes[1].scatter(time, state_meas[:, 0], s=10, color="#d97706", alpha=0.55, label="x noisy (points)")
    axes[1].plot(time, input_estimates[:, 0], color="#2563eb", linewidth=2.0, label="x KF input")
    axes[1].plot(
        time,
        embedding_corrected_estimates[:, 0],
        color="#16a34a",
        linewidth=2.0,
        label="x KF + embedding correction",
    )
    axes[1].set_title("X over Time")
    axes[1].set_xlabel("time")
    axes[1].set_ylabel("x")
    axes[1].grid(alpha=0.25)
    axes[1].legend(frameon=False)

    axes[2].plot(time, state_true[:, 1], color="#111827", linewidth=2.0, label="y true")
    axes[2].scatter(time, state_meas[:, 1], s=10, color="#d97706", alpha=0.55, label="y noisy (points)")
    axes[2].plot(time, input_estimates[:, 1], color="#2563eb", linewidth=2.0, label="y KF input")
    axes[2].plot(
        time,
        embedding_corrected_estimates[:, 1],
        color="#16a34a",
        linewidth=2.0,
        label="y KF + embedding correction",
    )
    axes[2].set_title("Y over Time")
    axes[2].set_xlabel("time")
    axes[2].set_ylabel("y")
    axes[2].grid(alpha=0.25)
    axes[2].legend(frameon=False)

    fig.tight_layout()
    fig.savefig(FIGURE_DIR / "trajectory_comparison.png", bbox_inches="tight")
    plt.close(fig)


def plot_error_curves(
    time: np.ndarray,
    state_true: np.ndarray,
    state_meas: np.ndarray,
    input_estimates: np.ndarray,
    embedding_corrected_estimates: np.ndarray,
) -> None:
    position_error_meas = np.linalg.norm(state_meas[:, :2] - state_true[:, :2], axis=1)
    position_error_input = np.linalg.norm(input_estimates[:, :2] - state_true[:, :2], axis=1)
    position_error_embed = np.linalg.norm(embedding_corrected_estimates[:, :2] - state_true[:, :2], axis=1)

    fig, ax = plt.subplots(figsize=(12, 5), dpi=160)
    ax.plot(time, position_error_meas, color="#d97706", linewidth=1.5, label="Noisy input error")
    ax.plot(time[: len(position_error_input)], position_error_input, color="#2563eb", linewidth=2.0, label="Input-space KF error")
    ax.plot(
        time[: len(position_error_embed)],
        position_error_embed,
        color="#16a34a",
        linewidth=2.0,
        label="State KF + embedding correction error",
    )
    ax.set_title("Position Error Comparison")
    ax.set_xlabel("time")
    ax.set_ylabel("L2 error")
    ax.grid(alpha=0.25)
    ax.legend(frameon=False)

    fig.tight_layout()
    fig.savefig(FIGURE_DIR / "error_comparison.png", bbox_inches="tight")
    plt.close(fig)


def plot_embedding_diagnostics(time: np.ndarray, residual_norms: np.ndarray) -> None:
    fig, ax = plt.subplots(figsize=(12, 4.5), dpi=160)
    ax.plot(time[1 : 1 + len(residual_norms)], residual_norms, color="#7c3aed", linewidth=2.0)
    ax.set_title("Embedding Residual Norm")
    ax.set_xlabel("time")
    ax.set_ylabel("||e - e_pred||")
    ax.grid(alpha=0.25)
    fig.tight_layout()
    fig.savefig(FIGURE_DIR / "embedding_residuals.png", bbox_inches="tight")
    plt.close(fig)


def main() -> None:
    make_directories()
    np.set_printoptions(precision=3, suppress=True)
    config = ExperimentConfig()
    payload = run_experiment(config)

    metrics = payload["metrics"]
    print("Experiment completed")
    print(json.dumps(metrics, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
