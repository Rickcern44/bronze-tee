#!/usr/bin/env python3
"""Regenerate the surface-map test fixture (surface_map_fixture.{srf,f32}).

The .srf is baked with tools/course_import's own encoder, so
tests/surface_map_check.gd proves the importer's output round-trips through the
game's reader. tests/test_course_import.py fails if the committed files drift
from this script. Run from the repo root:

    python3 tests/fixtures/make_surface_map_fixture.py

Hole-local frame: tee at the origin, -Z toward the cup at (6, -92). The grids
match surface_map_hole.tres.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.course_import import course_import as ci  # noqa: E402

HERE = Path(__file__).resolve().parent
ORIGIN = (-40.0, 20.0)  # min X, max Z: the first sample of both grids
SURFACE_SIZE = (161, 261)  # columns (X), rows (Z) at 0.5 m: X -40..40, Z 20..-110
ELEVATION_SPACING = 2.0
ELEVATION_SIZE = (41, 66)  # same extent at 2 m
GREEN_SLOPE_X = 0.05  # 5% cross slope; the game caps the green plane at 2%


def grid(size: tuple[int, int], spacing: float) -> tuple[np.ndarray, np.ndarray]:
    """World X and Z of every sample; rows advance toward -Z."""
    cols, rows = size
    return np.meshgrid(ORIGIN[0] + np.arange(cols) * spacing, ORIGIN[1] - np.arange(rows) * spacing)


def surface_ids() -> np.ndarray:
    S = ci.SURFACE
    x, z = grid(SURFACE_SIZE, ci.SURFACE_SPACING)
    ids = np.full(x.shape, S["deep_rough"], dtype=np.uint8)
    fairway = (np.abs(x) <= 10) & (z <= -15) & (z >= -80)
    ids[fairway] = S["fairway"]
    near_fairway = ci.distance_transform_edt(~fairway) * ci.SURFACE_SPACING
    ids[~fairway & (near_fairway <= 3)] = S["first_cut"]
    ids[~fairway & (near_fairway > 3) & (near_fairway <= 9)] = S["second_cut"]
    ids[(np.abs(x) <= 4) & (np.abs(z) <= 4)] = S["tee"]
    green = ((x / 12) ** 2 + ((z + 92) / 9) ** 2) < 1
    near_green = ci.distance_transform_edt(~green) * ci.SURFACE_SPACING
    ids[~green & (near_green <= 1.5)] = S["collar"]
    ids[green] = S["green"]
    ids[(x >= -36) & (x <= -26) & (z <= -30) & (z >= -60)] = S["water"]
    ids[(((x - 16) / 4) ** 2 + ((z + 86) / 3) ** 2) < 1] = S["bunker"]
    ids[(x >= 28) & (x <= 30.5) & (z <= 6) & (z >= -100)] = S["path"]
    return ids


def elevation() -> np.ndarray:
    x, _ = grid(ELEVATION_SIZE, ELEVATION_SPACING)
    return (GREEN_SLOPE_X * x).astype("<f4")


def write(out_dir: Path = HERE) -> None:
    ci._save_surface(surface_ids(), out_dir / "surface_map_fixture.srf")
    (out_dir / "surface_map_fixture.f32").write_bytes(elevation().tobytes(order="C"))


def main() -> int:
    write()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
