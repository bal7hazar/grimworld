"""Clean-up of the sources: keying of the magenta sheets, cutting of poses, registration on the feet.

A pose is a `Pose`: a tight RGBA crop plus the position of its feet (anchor x, baseline y) inside
the crop. Registration later places every pose of a sprite in one cell size on one baseline.
"""

import math
from dataclasses import dataclass

import numpy as np
from PIL import Image

GRID = 256          # nominal cell of the generated sheets
COLS = 6


@dataclass
class Pose:
    rgba: np.ndarray        # H x W x 4, uint8, straight (non-premultiplied) alpha
    feet_x: int             # x of the feet's centre, in crop coordinates
    baseline: int           # y of the line under the feet (= last foot row + 1), crop coordinates


def dilate(mask, r):
    """Square dilation of a boolean mask by r pixels."""
    out = mask.copy()
    h, w = mask.shape
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx == 0 and dy == 0:
                continue
            ys = slice(max(dy, 0), h + min(dy, 0))
            yd = slice(max(-dy, 0), h + min(-dy, 0))
            xs = slice(max(dx, 0), w + min(dx, 0))
            xd = slice(max(-dx, 0), w + min(-dx, 0))
            out[yd, xd] |= mask[ys, xs]
    return out


def sheet_key(rgb):
    """The key colour of a sheet: per-channel median of a 12 px border ring (the upper middle value
    after an integer sort, so an integer: no averaging)."""
    ring = np.concatenate([rgb[:12].reshape(-1, 3), rgb[-12:].reshape(-1, 3),
                           rgb[:, :12].reshape(-1, 3), rgb[:, -12:].reshape(-1, 3)])
    return np.sort(ring, axis=0)[len(ring) // 2].astype(np.int64)


def div_round(num, den):
    """Integer division rounded half up, element-wise (den > 0)."""
    return (2 * num + den) // (2 * den)


def key_sheet(rgb, s):
    """Magenta -> transparency. Returns (RGBA uint8, key colour). Integer arithmetic only.

    Pixels within `key_tolerance` of the key are background. Within `fringe_radius` of the
    background, edge pixels are anti-aliased mixes p = a*fg + (1-a)*key: alpha is estimated from
    how magenta the pixel is (R + B - 2G, zero for a neutral foreground) and the key colour is
    subtracted back out, so no pink halo is left. Elsewhere the pixel is opaque. Alpha is in
    0..255 throughout: a = 255 (1 - m / m_key), fg = (255 p - (255 - a) key) / a, both rounded.
    """
    key = sheet_key(rgb)
    p = rgb.astype(np.int64)
    bg = np.abs(p - key).max(axis=2) <= s["key_tolerance"]
    m = p[..., 0] + p[..., 2] - 2 * p[..., 1]
    m_key = int(key[0] + key[2] - 2 * key[1])
    a_soft = np.clip(div_round(255 * (m_key - m), m_key), 0, 255)
    near = dilate(bg, s["fringe_radius"])
    a = np.where(bg, 0, np.where(near, a_soft, 255))
    a[a < math.ceil(255 * s["min_alpha"])] = 0
    safe = np.maximum(a, 1)[..., None]
    fg = np.clip(div_round(255 * p - (255 - a)[..., None] * key, safe), 0, 255)
    out = np.zeros(rgb.shape[:2] + (4,), np.uint8)
    out[..., :3] = np.where((a > 0)[..., None], fg, 0).astype(np.uint8)
    out[..., 3] = a.astype(np.uint8)
    return out, key


def label(mask):
    """8-connected component labels of a boolean mask (0 = none). Flood fill on set pixels only."""
    h, w = mask.shape
    lab = np.zeros(h * w, np.int32)
    flat = mask.ravel()
    n = 0
    for start in np.flatnonzero(flat):
        if lab[start]:
            continue
        n += 1
        lab[start] = n
        stack = [start]
        while stack:
            i = stack.pop()
            y, x = divmod(i, w)
            for ny in (y - 1, y, y + 1):
                if 0 <= ny < h:
                    for nx in (x - 1, x, x + 1):
                        if 0 <= nx < w:
                            j = ny * w + nx
                            if flat[j] and not lab[j]:
                                lab[j] = n
                                stack.append(j)
    return lab.reshape(h, w), n


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


def cut_generated(sheet_path, rows, s):
    """Key one generated sheet and cut its poses along their silhouettes.

    Returns (poses by row, stats). A silhouette (8-connected, after a 2 px dilation that bridges
    anti-aliasing gaps) belongs to the nominal cell holding its centroid, so a weapon crossing the
    grid line stays with its owner.
    """
    rgb = np.array(Image.open(sheet_path).convert("RGB"))
    rgba, key = key_sheet(rgb, s)
    lab, n = label(dilate(rgba[..., 3] > 0, 2))
    ys, xs = np.mgrid[0:lab.shape[0], 0:lab.shape[1]]
    opaque = rgba[..., 3] > 0
    area = np.bincount(lab[opaque], minlength=n + 1)
    count = np.bincount(lab.ravel(), minlength=n + 1)
    # Centroid sums in int64 (np.add.at: exact whatever the order), not bincount's float weights.
    sum_y = np.zeros(n + 1, np.int64)
    sum_x = np.zeros(n + 1, np.int64)
    np.add.at(sum_y, lab.ravel(), ys.ravel().astype(np.int64))
    np.add.at(sum_x, lab.ravel(), xs.ravel().astype(np.int64))
    idx = np.flatnonzero(lab.ravel() > 0)
    l, y, x = lab.ravel()[idx], idx // lab.shape[1], idx % lab.shape[1]
    box = np.array([np.full(n + 1, 10 ** 6), np.full(n + 1, 10 ** 6),
                    np.full(n + 1, -1), np.full(n + 1, -1)])       # x0, y0, x1, y1 per component
    np.minimum.at(box[0], l, x)
    np.minimum.at(box[1], l, y)
    np.maximum.at(box[2], l, x)
    np.maximum.at(box[3], l, y)
    keep = [c for c in range(1, n + 1) if area[c] >= s["min_component"]]
    dropped = n - len(keep)
    # The largest silhouette whose centroid lies in a cell is that cell's body. Every other kept
    # silhouette (a spark, a projectile, a detached weapon tip) follows the nearest body, by
    # bounding-box gap, within its own row: it may cross the grid line.
    body = {}
    for c in keep:
        cell = (int(sum_y[c] // count[c]) // GRID, int(sum_x[c] // count[c]) // GRID)
        if cell not in body or area[c] > area[body[cell]]:
            body[cell] = c
    cells = {cell: [c] for cell, c in body.items()}
    for c in keep:
        if c in body.values():
            continue
        row = int(sum_y[c] // count[c]) // GRID

        def gap(b):
            dx = max(box[0][b] - box[2][c], box[0][c] - box[2][b], 0)
            dy = max(box[1][b] - box[3][c], box[1][c] - box[3][b], 0)
            return dx * dx + dy * dy
        near = [(gap(b), cell) for cell, b in sorted(body.items()) if cell[0] == row]
        if near:
            cells[min(near)[1]].append(c)
    poses = {}
    for row in rows:
        poses[row] = []
        for col in range(COLS):
            comps = cells.get((row, col), [])
            if not comps:
                raise SystemExit(f"{sheet_path.name}: no silhouette in row {row} column {col}")
            m = np.isin(lab, comps)
            poses[row].append(register(np.where(m[..., None], rgba, 0).astype(np.uint8)))
    return poses, {"key": [int(v) for v in key], "dropped_specks": dropped}


def cut_strip(strip_path):
    """Cut an original strip into square cells (cell = strip height); each cell is one pose."""
    img = np.array(Image.open(strip_path).convert("RGBA"))
    cell = img.shape[0]
    if img.shape[1] % cell:
        raise SystemExit(f"{strip_path.name}: width {img.shape[1]} is not a multiple of {cell}")
    return [register(img[:, i * cell:(i + 1) * cell]) for i in range(img.shape[1] // cell)]


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
