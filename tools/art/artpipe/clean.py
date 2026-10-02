"""Clean-up of the sources: cutting the pack's strips into poses, registration on the feet; a still
image (a building) is one pose.

A pose is a `Pose`: a tight RGBA crop plus the position of its feet (anchor x, baseline y) inside
the crop. Registration later places every pose of a sprite in one cell size on one baseline.
"""

from dataclasses import dataclass

import numpy as np
from PIL import Image


@dataclass
class Pose:
    rgba: np.ndarray        # H x W x 4, uint8, straight (non-premultiplied) alpha
    feet_x: int             # x of the feet's centre, in crop coordinates
    baseline: int           # y of the line under the feet (= last foot row + 1), crop coordinates


def register(rgba):
    """Tight-crop a pose and find its feet: the lowest row at least ~8% of the width wide, so a
    thin trailing effect or a weapon tip is not mistaken for the ground contact."""
    a = rgba[..., 3]
    ys, xs = np.where(a > 0)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    crop = rgba[y0:y1, x0:x1].copy()
    solid = crop[..., 3] >= 64
    width = crop.shape[1]
    need = max(4, (8 * width + 50) // 100)                  # 8 % of the width, in integers
    rows = np.flatnonzero(solid.sum(axis=1) >= need)
    last = int(rows.max()) if len(rows) else crop.shape[0] - 1
    band_top = max(0, last - max(3, (4 * crop.shape[0] + 50) // 100))
    bx = np.flatnonzero(solid[band_top:last + 1].any(axis=0))
    feet_x = int((bx.min() + bx.max() + 1) // 2) if len(bx) else width // 2
    return Pose(crop, feet_x, last + 1)


def cut_strip(strip_path):
    """Cut an original strip into square cells (cell = strip height); each cell is one pose."""
    img = np.array(Image.open(strip_path).convert("RGBA"))
    cell = img.shape[0]
    if img.shape[1] % cell:
        raise SystemExit(f"{strip_path.name}: width {img.shape[1]} is not a multiple of {cell}")
    return [register(img[:, i * cell:(i + 1) * cell]) for i in range(img.shape[1] // cell)]


def still(path):
    """A single still image (a building, CLI-03c), not a strip: one pose at native size, anchored at
    its base (the line under its lowest solid row wide enough: the feet rule of `register`, so a
    thin pole or flag under the walls is not taken for the ground) and at its horizontal centre."""
    p = register(np.array(Image.open(path).convert("RGBA")))
    return Pose(p.rgba, p.rgba.shape[1] // 2, p.baseline)


def place(poses, margin):
    """Register all poses of one sprite in one cell: same size, same baseline, same x anchor.

    Returns (cell_w, cell_h, baseline, frames) where frames maps the pose index to the RGBA cell.
    """
    left = max(p.feet_x for p in poses)
    right = max(p.rgba.shape[1] - p.feet_x for p in poses)
    up = max(p.baseline for p in poses)
    down = max(p.rgba.shape[0] - p.baseline for p in poses)
    half = max(left, right) + margin
    cell_w = 2 * half
    cell_h = up + down + 2 * margin
    baseline = margin + up
    cells = []
    for p in poses:
        cell = np.zeros((cell_h, cell_w, 4), np.uint8)
        y = baseline - p.baseline
        x = half - p.feet_x
        cell[y:y + p.rgba.shape[0], x:x + p.rgba.shape[1]] = p.rgba
        cells.append(cell)
    return cell_w, cell_h, baseline, cells
