from __future__ import annotations

import sqlite3
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.widgets import Button

from route_proposal_workflow import (
    DB_PATH,
    OUT_DIR,
    floor_color,
    load_corridors,
    sample_polyline,
    xy_to_lonlat,
)

MANUAL_DIR = OUT_DIR / "manual_drawn"
MANUAL_IMG_DIR = MANUAL_DIR / "route_images"


def init_manual_db(db_path: Path) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(db_path)
    cur = con.cursor()

    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS manual_routes (
            route_id TEXT PRIMARY KEY,
            note TEXT,
            image_path TEXT,
            checkpoint_count INTEGER NOT NULL,
            sampled_count INTEGER NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
        """
    )

    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS manual_route_checkpoints (
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
        CREATE TABLE IF NOT EXISTS manual_route_points (
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

    con.commit()
    con.close()


def next_manual_route_id(db_path: Path) -> str:
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    cur.execute("SELECT route_id FROM manual_routes WHERE route_id LIKE 'M%' ORDER BY route_id DESC LIMIT 1")
    row = cur.fetchone()
    con.close()

    if not row:
        return "M001"

    rid = str(row[0])
    try:
        num = int(rid[1:])
    except ValueError:
        return "M001"
    return f"M{num + 1:03d}"


def save_manual_route(
    db_path: Path,
    route_id: str,
    checkpoints_xy: np.ndarray,
    sampled_xy: np.ndarray,
    lon0: float,
    lat0: float,
    image_path: Path,
) -> None:
    checkpoints_ll = xy_to_lonlat(checkpoints_xy, lon0, lat0)
    sampled_ll = xy_to_lonlat(sampled_xy, lon0, lat0)

    con = sqlite3.connect(db_path)
    cur = con.cursor()

    cur.execute(
        """
        INSERT OR REPLACE INTO manual_routes (route_id, note, image_path, checkpoint_count, sampled_count)
        VALUES (?, ?, ?, ?, ?)
        """,
        (route_id, "drawn and approved by user", str(image_path), int(len(checkpoints_xy)), int(len(sampled_xy))),
    )

    cur.execute("DELETE FROM manual_route_checkpoints WHERE route_id = ?", (route_id,))
    for i, (xy, ll) in enumerate(zip(checkpoints_xy, checkpoints_ll)):
        cur.execute(
            """
            INSERT INTO manual_route_checkpoints (route_id, point_idx, x_m, y_m, lon, lat)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (route_id, i, float(xy[0]), float(xy[1]), float(ll[0]), float(ll[1])),
        )

    cur.execute("DELETE FROM manual_route_points WHERE route_id = ?", (route_id,))
    for i, (xy, ll) in enumerate(zip(sampled_xy, sampled_ll)):
        cur.execute(
            """
            INSERT INTO manual_route_points (route_id, point_idx, x_m, y_m, lon, lat)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (route_id, i, float(xy[0]), float(xy[1]), float(ll[0]), float(ll[1])),
        )

    con.commit()
    con.close()


def save_manual_image(corridors: list, checkpoints_xy: np.ndarray, sampled_xy: np.ndarray, route_id: str, image_path: Path) -> None:
    fig, ax = plt.subplots(figsize=(10, 7.5), dpi=180)

    for c in corridors:
        color = floor_color(c.level)
        ax.fill(c.ring_xy[:, 0], c.ring_xy[:, 1], color=color, alpha=0.12)
        ax.plot(c.ring_xy[:, 0], c.ring_xy[:, 1], color=color, linewidth=0.7, alpha=0.45)

    ax.plot(sampled_xy[:, 0], sampled_xy[:, 1], color="#111827", linewidth=2.5, label="Sampled route")
    ax.plot(checkpoints_xy[:, 0], checkpoints_xy[:, 1], color="#f97316", linewidth=1.6, marker="o", markersize=4, label="Checkpoints")
    ax.scatter([checkpoints_xy[0, 0]], [checkpoints_xy[0, 1]], color="#16a34a", s=45, label="Start")
    ax.scatter([checkpoints_xy[-1, 0]], [checkpoints_xy[-1, 1]], color="#dc2626", s=45, label="End")

    ax.set_title(f"{route_id} | manual drawn route")
    ax.set_xlabel("x (m)")
    ax.set_ylabel("y (m)")
    ax.grid(alpha=0.2)
    ax.legend(frameon=False, loc="best")
    ax.set_aspect("equal", adjustable="box")
    fig.tight_layout()
    image_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(image_path, bbox_inches="tight")
    plt.close(fig)


class ManualRouteDrawer:
    def __init__(self) -> None:
        init_manual_db(DB_PATH)
        MANUAL_DIR.mkdir(parents=True, exist_ok=True)
        MANUAL_IMG_DIR.mkdir(parents=True, exist_ok=True)

        self.corridors, self.lon0, self.lat0 = load_corridors()
        self.current_points: list[np.ndarray] = []
        self.saved_count = 0

        self.fig, self.ax = plt.subplots(figsize=(12, 9), dpi=140)
        plt.subplots_adjust(bottom=0.16)

        self.route_line, = self.ax.plot([], [], color="#111827", linewidth=2.8)
        self.checkpoint_line, = self.ax.plot([], [], color="#f97316", linewidth=1.5, marker="o", markersize=4)

        self.status_text = self.ax.text(
            0.01,
            0.99,
            "Left click: add checkpoint | Right click: undo last | Approve: save route",
            transform=self.ax.transAxes,
            verticalalignment="top",
            fontsize=10,
            bbox={"facecolor": "white", "alpha": 0.75, "edgecolor": "#d1d5db"},
        )

        self._draw_map_base()
        self._make_buttons()
        self.fig.canvas.mpl_connect("button_press_event", self._on_click)

    def _draw_map_base(self) -> None:
        for c in self.corridors:
            color = floor_color(c.level)
            self.ax.fill(c.ring_xy[:, 0], c.ring_xy[:, 1], color=color, alpha=0.12)
            self.ax.plot(c.ring_xy[:, 0], c.ring_xy[:, 1], color=color, linewidth=0.8, alpha=0.5)

        self.ax.set_title("Manual Route Drawing (Pen/Mouse)")
        self.ax.set_xlabel("x (m)")
        self.ax.set_ylabel("y (m)")
        self.ax.grid(alpha=0.2)
        self.ax.set_aspect("equal", adjustable="box")

    def _make_buttons(self) -> None:
        ax_clear = plt.axes([0.08, 0.03, 0.18, 0.07])
        ax_approve = plt.axes([0.31, 0.03, 0.24, 0.07])
        ax_finish = plt.axes([0.62, 0.03, 0.2, 0.07])

        self.btn_clear = Button(ax_clear, "Clear")
        self.btn_approve = Button(ax_approve, "Approve and Next")
        self.btn_finish = Button(ax_finish, "Finish")

        self.btn_clear.on_clicked(self._clear_route)
        self.btn_approve.on_clicked(self._approve_route)
        self.btn_finish.on_clicked(self._finish)

    def _set_status(self, message: str) -> None:
        self.status_text.set_text(message)
        self.fig.canvas.draw_idle()

    def _refresh_current_route(self) -> None:
        if not self.current_points:
            self.route_line.set_data([], [])
            self.checkpoint_line.set_data([], [])
            self.fig.canvas.draw_idle()
            return

        pts = np.vstack(self.current_points)
        self.checkpoint_line.set_data(pts[:, 0], pts[:, 1])

        if len(pts) >= 2:
            sampled = sample_polyline(pts, 80)
            self.route_line.set_data(sampled[:, 0], sampled[:, 1])
        else:
            self.route_line.set_data(pts[:, 0], pts[:, 1])

        self.fig.canvas.draw_idle()

    def _on_click(self, event) -> None:
        if event.inaxes != self.ax or event.xdata is None or event.ydata is None:
            return

        if event.button == 1:
            self.current_points.append(np.array([float(event.xdata), float(event.ydata)], dtype=float))
            self._set_status(f"checkpoint added | checkpoints={len(self.current_points)}")
            self._refresh_current_route()
        elif event.button == 3:
            if self.current_points:
                self.current_points.pop()
                self._set_status(f"last checkpoint removed | checkpoints={len(self.current_points)}")
                self._refresh_current_route()

    def _clear_route(self, _event) -> None:
        self.current_points = []
        self._set_status("current route cleared")
        self._refresh_current_route()

    def _approve_route(self, _event) -> None:
        if len(self.current_points) < 2:
            self._set_status("need at least 2 checkpoints")
            return

        checkpoints_xy = np.vstack(self.current_points)
        sampled_xy = sample_polyline(checkpoints_xy, 50)

        route_id = next_manual_route_id(DB_PATH)
        image_path = MANUAL_IMG_DIR / f"{route_id}__manual_drawn.png"

        save_manual_route(DB_PATH, route_id, checkpoints_xy, sampled_xy, self.lon0, self.lat0, image_path)
        save_manual_image(self.corridors, checkpoints_xy, sampled_xy, route_id, image_path)

        self.saved_count += 1
        self.current_points = []
        self._refresh_current_route()
        self._set_status(f"saved {route_id} | now draw next route | total_saved={self.saved_count}")

    def _finish(self, _event) -> None:
        self._set_status(f"finished | total_saved={self.saved_count}")
        plt.close(self.fig)

    def run(self) -> None:
        plt.show()


def main() -> None:
    app = ManualRouteDrawer()
    app.run()


if __name__ == "__main__":
    main()
