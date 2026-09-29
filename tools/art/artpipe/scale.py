"""Scale (ART-02): every sprite at the height of its build, measured by one rule, resampled exactly.

**Visible height.** Of one pose: from the line under the feet (the baseline of `clean.register`) up
to the highest solid pixel (alpha >= 64) inside a band of columns centred on the feet, of half-width
max(4, 10% of the pose's width). The band keeps the body and the head (headwear included) and leaves
out what a hand holds beside or above it: the hobgoblin's club, the shaman's staff, the
skirmisher's spear, the slinger's torch. A sprite's height is the median over its idle frames.

**Resampling.** By the rational factor p/q (p = target height, q = the sprite's measured height),
on a grid anchored at the feet (the anchor column and the baseline of the placed cell land on pixel
boundaries), in integer arithmetic only, so that the result is the same on every machine:
- `nearest`: each output pixel takes the source pixel under its centre.
- `area`: each output pixel looks at the source pixels it covers, weighted by overlap. It is
  visible when visible source pixels cover at least half of it (else transparent: an edge does not
  grow a translucent ring); its alpha is the visible part's average alpha, snapped to the nearest
  value the sprite's source uses (the pack's units use only 0, about 80, and 255); its colour is
  the covered pixels' average in premultiplied alpha. No new transparency level appears, so edges
  stay as hard as the source's; colours blend where source pixels meet.
"""

import numpy as np

from .clean import register

SOLID = 64


def visible_height(rgba):
    """Visible height of one pose (RGBA, any padding), by the rule above."""
    p = register(rgba)
    solid = p.rgba[..., 3] >= SOLID
    band = max(4, int(round(0.10 * solid.shape[1])))
    x0, x1 = max(0, p.feet_x - band), min(solid.shape[1], p.feet_x + band + 1)
    rows = np.flatnonzero(solid[:, x0:x1].any(axis=1))
    return p.baseline - int(rows.min()) if len(rows) else 0


def sprite_height(idle_cells):
    """The sprite's measured height: the median (lower middle) of its idle frames' heights."""
    hs = sorted(visible_height(c) for c in idle_cells)
    return hs[(len(hs) - 1) // 2], hs


def axis_weights(size, anchor, p, q):
    """Integer overlap weights (out x size) of a 1-D resampling by p/q that keeps `anchor` (a pixel
    boundary of the source) on a pixel boundary of the output. In units of 1/q of an output pixel,
    source pixel j spans [(j - anchor) p + A q, (j + 1 - anchor) p + A q) and output pixel i spans
    [i q, (i + 1) q), with A the output anchor. Returns (weights, A, out size)."""
    a_out = -(-anchor * p // q)                                  # ceil: nothing maps below 0
    out = -(-((size - anchor) * p + a_out * q) // q)
    j = np.arange(size, dtype=np.int64)
    s0 = (j - anchor) * p + a_out * q
    i = np.arange(out, dtype=np.int64)
    o0 = i * q
    lo = np.maximum(o0[:, None], s0[None, :])
    hi = np.minimum(o0[:, None] + q, s0[None, :] + p)
    return np.maximum(hi - lo, 0), a_out, out


def axis_nearest(size, anchor, p, q):
    """Index of the source pixel under each output pixel's centre (-1 outside), same grid."""
    a_out = -(-anchor * p // q)
    out = -(-((size - anchor) * p + a_out * q) // q)
    i = np.arange(out, dtype=np.int64)
    # centre (i + 1/2) q  ->  source coordinate ((i + 1/2) q - A q) / p + anchor
    j = ((2 * i + 1) * q - 2 * a_out * q) // (2 * p) + anchor
    j[(j < 0) | (j >= size)] = -1
    return j, a_out, out


def alpha_levels(cells):
    """The alpha values a sprite's source uses (0 included): the levels `area` snaps to."""
    return sorted({0} | {int(v) for c in cells for v in np.unique(c[..., 3])})


def resample(cell, anchor_x, anchor_y, p, q, method, levels=range(256)):
    """Resample an RGBA cell by p/q around (anchor_x, anchor_y). Returns (cell, ax, ay)."""
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


def target_height(sprite, builds):
    """The height a sprite must stand at: its own `height`, else its build's."""
    if "height" in sprite:
        return int(sprite["height"])
    if sprite.get("build") not in builds:
        raise SystemExit(f'{sprite["name"]}: build {sprite.get("build")!r} is not one of '
                         f'{", ".join(builds)} ([build] in manifest.toml)')
    return int(builds[sprite["build"]])


def check_order(heights, basic, tallest, role):
    """AC-2: no basic goblin taller than the shortest profession; `tallest` the tallest sprite.
    `heights` maps a sprite to its measured idle height, `role` to caste or profession. Returns the
    list of problems (empty when the order holds)."""
    problems = []
    heroes = [n for n in heights if role[n] == "profession"]
    if heroes:
        short = min(heroes, key=lambda n: (heights[n], n))
        for n in basic:
            if heights[n] > heights[short]:
                problems.append(f"{n} ({heights[n]} px) is taller than the shortest profession, "
                                f"{short} ({heights[short]} px)")
    for n in heights:
        if n != tallest and heights[n] >= heights[tallest]:
            problems.append(f"{tallest} ({heights[tallest]} px) is not taller than {n} "
                            f"({heights[n]} px)")
    return problems
