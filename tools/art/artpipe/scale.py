"""Scale (ART-02, D-146 as corrected by the owner): the pack's hand-drawn units keep their native
height; only the generated sheets are resampled, to a height the manifest names.

**Visible height.** Of one pose: from the line under the feet (the baseline of `clean.register`) up
to the highest solid pixel (alpha >= 64) inside a band of columns centred on the feet, of half-width
max(4, 10% of the pose's width, rounded). The band keeps the body and the head (headwear included)
and leaves out what a hand holds beside or above it: the hobgoblin's club, the shaman's staff, the
skirmisher's spear, the slinger's torch. A sprite's height is the median (lower middle) over its
idle frames.

**Resampling.** By the rational factor p/q (p = target height, q = the sprite's measured height),
on a grid anchored at the feet (the anchor column and the baseline of the placed cell land on pixel
boundaries), in integer arithmetic only (int64 sums are exact in any order):
- `nearest`: each output pixel takes the source pixel under its centre.
- `area`: each output pixel looks at the source pixels it covers, weighted by overlap. It is
  visible when visible source pixels cover at least half of it (else transparent: an edge does not
  grow a translucent ring); its alpha is the visible part's average alpha, snapped to the nearest
  value the sprite's source uses; its colour is the covered pixels' average in premultiplied alpha.
  When the sprite's source has a small palette (at most `palette_max` colours), each colour is then
  snapped to the nearest colour of that palette (`snap`), so no new colour appears. The generated
  sheets (tens of thousands of colours) keep the averaged colours.
"""

import numpy as np

from .clean import register

SOLID = 64
NATIVE = "native"


def visible_height(rgba):
    """Visible height of one pose (RGBA, any padding), by the rule above."""
    p = register(rgba)
    solid = p.rgba[..., 3] >= SOLID
    band = max(4, (solid.shape[1] + 5) // 10)                   # 10 % of the width, in integers
    x0, x1 = max(0, p.feet_x - band), min(solid.shape[1], p.feet_x + band + 1)
    rows = np.flatnonzero(solid[:, x0:x1].any(axis=1))
    return p.baseline - int(rows.min()) if len(rows) else 0


def sprite_height(idle_cells):
    """The sprite's measured height: the median (lower middle) of its idle frames' heights."""
    hs = sorted(visible_height(c) for c in idle_cells)
    return hs[(len(hs) - 1) // 2], hs


def grid(size, anchor, p, q):
    """The output grid of a 1-D resampling by p/q that keeps `anchor` (a pixel boundary of the
    source) on a pixel boundary of the output: (output anchor A, output size). In units of 1/q of
    an output pixel, source pixel j spans [(j - anchor) p + A q, (j + 1 - anchor) p + A q) and
    output pixel i spans [i q, (i + 1) q)."""
    a_out = -(-anchor * p // q)                                  # ceil: nothing maps below 0
    return a_out, -(-((size - anchor) * p + a_out * q) // q)


def axis_weights(size, anchor, p, q):
    """Integer overlap weights (out x size) on `grid`'s grid. Returns (weights, A, out size)."""
    a_out, out = grid(size, anchor, p, q)
    s0 = (np.arange(size, dtype=np.int64) - anchor) * p + a_out * q
    o0 = np.arange(out, dtype=np.int64) * q
    lo = np.maximum(o0[:, None], s0[None, :])
    hi = np.minimum(o0[:, None] + q, s0[None, :] + p)
    return np.maximum(hi - lo, 0), a_out, out


def axis_nearest(size, anchor, p, q):
    """Index of the source pixel under each output pixel's centre (-1 outside), on `grid`'s grid."""
    a_out, out = grid(size, anchor, p, q)
    i = np.arange(out, dtype=np.int64)
    # centre (i + 1/2) q  ->  source coordinate ((i + 1/2) q - A q) / p + anchor
    j = ((2 * i + 1) * q - 2 * a_out * q) // (2 * p) + anchor
    j[(j < 0) | (j >= size)] = -1
    return j, a_out, out


def alpha_levels(cells):
    """The alpha values a sprite's source uses (0 included): the levels `area` snaps to."""
    return sorted({0} | {int(v) for c in cells for v in np.unique(c[..., 3])})


def palette(cells, most):
    """The sprite's colours (RGB of its visible pixels), sorted, if at most `most`; else None."""
    seen = np.unique(np.concatenate([c[c[..., 3] > 0][:, :3] for c in cells]), axis=0)
    return seen.astype(np.int64) if len(seen) <= most else None


def snap(cell, colours):
    """Every visible pixel's colour replaced by the nearest of `colours` (squared RGB distance;
    a tie goes to the first in sorted order)."""
    vis = cell[..., 3] > 0
    rgb = cell[vis][:, :3].astype(np.int64)
    d = ((rgb[:, None, :] - colours[None, :, :]) ** 2).sum(axis=2)
    out = cell.copy()
    out[vis, :3] = colours[np.argmin(d, axis=1)].astype(np.uint8)
    return out


def resample(cell, anchor_x, anchor_y, p, q, method, levels=range(256)):
    """Resample an RGBA cell by p/q around (anchor_x, anchor_y). Returns (cell, ax, ay), the new
    anchor. The caller registers the feet again (`clean.register`, `clean.place`): the anchor is
    kept on the grid, but the feet row is re-read from the result, as for any pose."""
    h, w = cell.shape[:2]
    if method == "nearest":
        jy, ay, oh = axis_nearest(h, anchor_y, p, q)
        jx, ax, ow = axis_nearest(w, anchor_x, p, q)
        out = np.zeros((oh, ow, 4), np.uint8)
        ok = (jy[:, None] >= 0) & (jx[None, :] >= 0)
        out[ok] = cell[np.maximum(jy, 0)[:, None], np.maximum(jx, 0)[None, :]][ok]
        return out, ax, ay
    if method != "area":
        raise SystemExit(f"unknown resampling method {method!r} (nearest, area)")
    wy, ay, oh = axis_weights(h, anchor_y, p, q)
    wx, ax, ow = axis_weights(w, anchor_x, p, q)
    a = cell[..., 3].astype(np.int64)
    cover = wy @ a @ wx.T                                        # sum of alpha x weight
    seen = wy @ (a > 0).astype(np.int64) @ wx.T                  # weight of the visible pixels
    total = wy.sum(axis=1)[:, None] * wx.sum(axis=1)[None, :]
    keep = 2 * seen >= total                                     # visible over half, or half
    mean = (2 * cover + np.maximum(seen, 1)) // (2 * np.maximum(seen, 1))   # the visible part's
    lv = np.asarray(levels, np.int64)
    alpha = lv[np.argmin(np.abs(lv[None, None, :] - mean[..., None]), axis=2)]
    alpha = np.where(keep, np.maximum(alpha, lv[lv > 0].min(initial=255)), 0)
    out = np.zeros((oh, ow, 4), np.uint8)
    for c in range(3):
        pm = wy @ (cell[..., c].astype(np.int64) * a) @ wx.T
        col = (2 * pm + np.maximum(cover, 1)) // (2 * np.maximum(cover, 1))   # rounded average
        out[..., c] = np.where(keep, col, 0).astype(np.uint8)
    out[..., 3] = alpha.astype(np.uint8)
    return out, ax, ay


def height_spec(name, heights):
    """A sprite's line of `[height]` in the manifest: "native" or a height in px (int)."""
    if name not in heights:
        raise SystemExit(f"{name}: no line in [height] of manifest.toml "
                         f'("native" or a height in px)')
    spec = heights[name]
    if spec == NATIVE:
        return NATIVE
    if isinstance(spec, bool) or not isinstance(spec, int) or spec <= 0:
        raise SystemExit(f'{name}: [height] must be "native" or a positive height in px, '
                         f"not {spec!r}")
    return spec


def validate_order(order, role):
    """`[order]` of the manifest against the sprites (`role` maps each to caste or profession).
    Returns the list of problems."""
    problems = []
    basic, tallest = order.get("basic", []), order.get("tallest")
    for n in [*basic, tallest]:
        if n is None:
            problems.append("[order] names no `tallest`")
        elif n not in role:
            problems.append(f"[order] names {n!r}, which is not a sprite of the manifest")
    if not any(r == "profession" for r in role.values()):
        problems.append("[order] cannot compare: the manifest has no profession")
    return problems


def check_order(heights, order, role, kind):
    """AC-2. The rule: a basic goblin (`order.basic`) drawn from a generated sheet is never taller
    than the shortest profession; the pack's own hand-drawn goblins keep the pack's proportions
    (its Spear Goblin, 70 px, is taller than its Monk, 67 px) and are not compared. `order.tallest`
    is taller than every other sprite. `heights` maps a sprite to its measured idle height, `role`
    to caste or profession, `kind` to generated or strip. Returns the list of problems."""
    problems = validate_order(order, role)
    if problems:
        return problems
    heroes = [n for n in heights if role[n] == "profession"]
    short = min(heroes, key=lambda n: (heights[n], n))
    for n in order["basic"]:
        if kind[n] == "generated" and heights[n] > heights[short]:
            problems.append(f"{n} ({heights[n]} px) is taller than the shortest profession, "
                            f"{short} ({heights[short]} px)")
    tallest = order["tallest"]
    for n in heights:
        if n != tallest and heights[n] >= heights[tallest]:
            problems.append(f"{tallest} ({heights[tallest]} px) is not taller than {n} "
                            f"({heights[n]} px)")
    return problems
