"""The interface's elements (CLI-03i): nine-slices, three-slices and stills of the pack's `UI
Elements`, packed on their own page(s) for the client's chrome.

A sheet of the pack places its pieces on a lattice with empty cells between them; the manifest
describes the lattice (`pieces.columns`, `pieces.rows`: source bounds in px) and the build composes
the pieces contiguous, the pack's pixels untouched. The transparent outer margin is then trimmed and
recorded as the element's `outset`. An element with states (`states = { pressed = "<file>" }`) is
trimmed by the margins common to every state, so all its images have one size and a pressed face
keeps its place: lower by `drop` px. The client cuts each frame from the page at the device's scale
and lays it out with CSS `border-image` (`slice`, `content` and `fill` below).
"""

import numpy as np

ROLE = "ui"
KINDS = ("nine", "three", "still")
FILLS = ("stretch", "round")
REGULAR = "regular"         # the animation (frame) of an element's normal state
SIDES = 4                   # insets are [top, right, bottom, left], in art px


def _inset(value):
    return (isinstance(value, list) and len(value) == SIDES
            and all(isinstance(v, int) and not isinstance(v, bool) and v >= 0 for v in value))


def _bounds(value):
    return (isinstance(value, list) and value and all(
        isinstance(b, list) and len(b) == 2 and all(isinstance(v, int) for v in b)
        and 0 <= b[0] < b[1] for b in value))


def problems(manifest, taken):
    """The `[[ui]]` entries: a name used once in the whole manifest (`taken`: the other names), role
    `ui`, a kind and a fill, a PNG of the pack, its lattice for a nine- or three-slice (3 columns;
    3 rows or 1), the slice and content insets, `states` naming PNGs, and `drop` only beside a
    pressed state. Returns the list of problems."""
    out, seen = [], set(taken)
    for e in manifest.get("ui", []):
        name = e.get("name")
        if not name:
            out.append(f"a [[ui]] has no name: {e!r}")
            continue
        if name in seen:
            out.append(f"[[ui]] {name}: the name is used twice")
        seen.add(name)
        if e.get("role") != ROLE:
            out.append(f"[[ui]] {name}: role {e.get('role')!r}, not {ROLE!r}")
        kind = e.get("kind")
        if kind not in KINDS:
            out.append(f"[[ui]] {name}: kind {kind!r}, not one of {', '.join(KINDS)}")
        if e.get("fill", "stretch") not in FILLS:
            out.append(f"[[ui]] {name}: fill {e.get('fill')!r}, not one of {', '.join(FILLS)}")
        if not e.get("origin"):
            out.append(f"[[ui]] {name}: no origin")
        files = [e.get("file"), *(e.get("states") or {}).values()]
        for f in files:
            if not str(f or "").endswith(".png"):
                out.append(f"[[ui]] {name}: file {f!r} is not a PNG")
        if e.get("states") is not None and (not isinstance(e["states"], dict) or set(
                e["states"]) - {"pressed"}):
            out.append(f"[[ui]] {name}: states {e['states']!r}, only `pressed` is known")
        if ("drop" in e) != ("pressed" in (e.get("states") or {})):
            out.append(f"[[ui]] {name}: `drop` goes with a pressed state, and only with one")
        elif "drop" in e and not (isinstance(e["drop"], int) and e["drop"] >= 0):
            out.append(f"[[ui]] {name}: drop {e['drop']!r} is not a length in px")
        for key in ("slice", "content"):
            if kind != "still" and not _inset(e.get(key)):
                out.append(f"[[ui]] {name}: {key} {e.get(key)!r} is not [top, right, bottom, left]")
        if kind == "three" and _inset(e.get("slice")) and (e["slice"][0] or e["slice"][2]):
            out.append(f"[[ui]] {name}: a three-slice has left and right insets only")
        if kind in ("nine", "three"):
            p = e.get("pieces")
            cols, rows = (p or {}).get("columns"), (p or {}).get("rows")
            if not (_bounds(cols) and len(cols) == 3):
                out.append(f"[[ui]] {name}: pieces.columns {cols!r} is not 3 [x0, x1] bounds")
            if not (_bounds(rows) and len(rows) == (3 if kind == "nine" else 1)):
                out.append(f"[[ui]] {name}: pieces.rows {rows!r} is not "
                           f"{3 if kind == 'nine' else 1} [y0, y1] bounds")
    return out


def compose(rgba, columns, rows):
    """The pieces at the lattice's bounds, side by side with nothing between them."""
    return np.concatenate([np.concatenate([rgba[y0:y1, x0:x1] for x0, x1 in columns], axis=1)
                           for y0, y1 in rows], axis=0)


def outside_pieces(rgba, columns, rows):
    """True when an opaque pixel of the sheet lies outside the described pieces: the sheet does not
    have this layout."""
    keep = np.zeros(rgba.shape[:2], bool)
    for y0, y1 in rows:
        for x0, x1 in columns:
            keep[y0:y1, x0:x1] = True
    return bool((rgba[..., 3] > 0)[~keep].any())


def margins(img):
    """The fully transparent rows and columns at each edge: [top, right, bottom, left]."""
    solid = img[..., 3] > 0
    ys, xs = np.flatnonzero(solid.any(axis=1)), np.flatnonzero(solid.any(axis=0))
    if not len(ys):
        raise ValueError("no opaque pixel")
    h, w = solid.shape
    return [int(ys[0]), int(w - 1 - xs[-1]), int(h - 1 - ys[-1]), int(xs[0])]


def face_top(img):
    """The first opaque row of the image's middle column: where a button's face starts."""
    rows = np.flatnonzero(img[:, img.shape[1] // 2, 3] > 0)
    return int(rows[0]) if len(rows) else None


def worst_band(img, slice_, kind):
    """How far the stretched bands are from uniform: the largest share of pixels of a row (between
    the top and bottom insets) differing from that band's middle row, and the same for columns
    between the left and right insets. 0 is a perfectly uniform edge."""
    t, r, b, l = slice_
    h, w = img.shape[:2]
    worst = 0.0
    if kind == "nine" and h - b > t:
        band = img[t:h - b]
        ref = band[len(band) // 2]
        worst = max(worst, float((band != ref).any(axis=2).mean(axis=1).max()))
    if w - r > l:
        band = img[:, l:w - r]
        ref = band[:, band.shape[1] // 2]
        worst = max(worst, float((band != ref[:, None]).any(axis=2).mean(axis=0).max()))
    return worst


def centre_colour(img, slice_):
    """The most common opaque colour between the slices, as #rrggbb: what text on the element sits
    on (the client's contrast test reads it, copied as numbers)."""
    t, r, b, l = slice_
    h, w = img.shape[:2]
    inner = img[t:h - b, l:w - r].reshape(-1, 4)
    inner = inner[inner[:, 3] == 255][:, :3]
    if not len(inner):
        inner = img.reshape(-1, 4)
        inner = inner[inner[:, 3] == 255][:, :3]
    colours, counts = np.unique(inner, axis=0, return_counts=True)
    top = colours[int(np.argmax(counts))]
    return "#%02x%02x%02x" % tuple(int(v) for v in top)


def element(e, read, tolerance):
    """One `[[ui]]` entry, checked, as `atlas.pack` takes it (untrimmed frames anchored top-left,
    no gutter extrusion: the client cuts exact rectangles) plus its `ui` metadata, and its report
    line. `read(file)` gives a sheet as an RGBA array. Refuses (SystemExit) a sheet with another
    layout than described, a pressed sheet of another layout than the regular one, a `drop` that
    is not the faces' difference, an inset outside the image and a non-uniform stretched edge."""
    name, kind = e["name"], e["kind"]
    fill = e.get("fill", "stretch")
    files = {REGULAR: e["file"], **(e.get("states") or {})}
    sheets = {state: read(f) for state, f in files.items()}
    shape = sheets[REGULAR].shape
    images = {}
    for state, rgba in sheets.items():
        if rgba.shape != shape:
            raise SystemExit(f"[[ui]] {name}: {files[state]} is {rgba.shape[1]} x "
                             f"{rgba.shape[0]}, not the regular sheet's {shape[1]} x {shape[0]}")
        if kind == "still":
            images[state] = rgba
            continue
        cols, rows = e["pieces"]["columns"], e["pieces"]["rows"]
        if max(x1 for _, x1 in cols) > shape[1] or max(y1 for _, y1 in rows) > shape[0]:
            raise SystemExit(f"[[ui]] {name}: pieces outside the {shape[1]} x {shape[0]} sheet")
        if kind == "nine" and outside_pieces(rgba, cols, rows):
            raise SystemExit(f"[[ui]] {name}: {files[state]} has pixels outside the described "
                             "pieces: not this layout")
        images[state] = compose(rgba, cols, rows)
    if "pressed" in images:
        got = (face_top(images["pressed"]) or 0) - (face_top(images[REGULAR]) or 0)
        if got != e["drop"]:
            raise SystemExit(f"[[ui]] {name}: drop {e['drop']}, the pressed face starts {got} px "
                             "lower than the regular one")
    # One trim for every state: the margins they have in common.
    common = [min(m) for m in zip(*(margins(img) for img in images.values()))]
    t, r, b, l = common
    for state, img in images.items():
        h, w = img.shape[:2]
        images[state] = img[t:h - b, l:w - r]
    h, w = images[REGULAR].shape[:2]
    slice_ = e.get("slice", [0] * SIDES)
    content = e.get("content", [0] * SIDES)
    for key, inset in (("slice", slice_), ("content", content)):
        if inset[0] + inset[2] > h or inset[1] + inset[3] > w:
            raise SystemExit(f"[[ui]] {name}: {key} {inset} lies outside the {w} x {h} image")
    worst = 0.0
    if kind != "still" and fill == "stretch":
        for state, img in images.items():
            worst = max(worst, worst_band(img, slice_, kind))
        if worst > tolerance:
            raise SystemExit(f"[[ui]] {name}: a stretched edge is not uniform ({worst:.0%} of a "
                             f"row or column differs, at most {tolerance:.0%}): widen the slice "
                             "or use fill = \"round\"")
    meta = {"kind": kind, "fill": fill, "slice": slice_, "content": content, "outset": common}
    if "pressed" in images:
        meta["drop"] = e["drop"]
        meta["states"] = ["pressed"]
    sprite = {"name": name, "role": ROLE, "cell_w": w, "cell_h": h, "baseline": 0,
              "untrimmed": True, "extrude": False, "anchor": (0, 0), "ui": meta,
              "anims": [{"name": state, "fps": 1, "loop": False, "cells": [img]}
                        for state, img in images.items()]}
    report = {"role": ROLE, "origin": e["origin"], "kind": kind, "fill": fill, "cell": [w, h],
              "outset": common, "edge": round(worst, 3),
              "centre": {state: centre_colour(img, slice_) for state, img in images.items()}}
    return sprite, report
