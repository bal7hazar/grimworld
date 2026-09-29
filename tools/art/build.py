#!/usr/bin/env python3
"""Asset pipeline entry point: `tools/art/build.py`.

Reads the private art pack (submodule `assets`), writes atlases, JSON, a report and a preview to
`tools/art/out/` (ignored by git, D-73). Needs Python 3.12 (re-executes under `python3.12` when
started by an older one); sets up its own virtualenv on first run. Deterministic: two runs give
byte-identical outputs, and the pixel-and-metadata fingerprint is meant to match across machines
(README). `--check` also parses the atlases with PixiJS 8 (needs node and pnpm from
.tool-versions, see scripts/setup-toolchain.sh). Other modes: `--fingerprint`, `--pack-heights`,
`--resample=<filter>`.
"""

import json
import os
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
VENV = HERE / ".venv"
OUT = HERE / "out"
ASSETS = REPO / "assets"
PYTHON = (3, 12)            # NumPy 2.5.3 (requirements.txt) needs Python 3.12 or newer


def select_python(version, which):
    """Which interpreter runs the build: None for the current one (`version` is at least 3.12),
    else the path of `python3.12` found by `which` (shutil.which). Refuses, naming 3.12, when
    neither holds. Called before any venv is created or used."""
    if tuple(version[:2]) >= PYTHON:
        return None
    name = "python%d.%d" % PYTHON
    found = which(name)
    if found:
        return found
    raise SystemExit("tools/art/build.py needs Python %d.%d or newer (NumPy 2.5.3), found %d.%d, "
                     "and no `%s` on PATH: install Python %d.%d and run it again."
                     % (*PYTHON, *version[:2], name, *PYTHON))


def venv_version(venv):
    """(major, minor) of the Python a venv was made with, from its pyvenv.cfg; None if unreadable."""
    cfg = venv / "pyvenv.cfg"
    if not cfg.exists():
        return None
    for line in cfg.read_text().splitlines():
        key, _, value = line.partition("=")
        if key.strip() in ("version", "version_info"):
            parts = value.strip().split(".")
            if len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit():
                return int(parts[0]), int(parts[1])
    return None


def bootstrap(version=sys.version_info, which=shutil.which):
    """Re-run under Python 3.12+, then under tools/art/.venv, creating it (or rebuilding it when it
    was made with another Python) and installing the pinned requirements."""
    other = select_python(version, which)
    if other:
        os.execv(other, [other, str(Path(__file__).resolve()), *sys.argv[1:]])
    py = VENV / "bin" / "python"
    if Path(sys.prefix).resolve() == VENV.resolve():
        return
    if VENV.exists() and venv_version(VENV) != tuple(sys.version_info[:2]):
        print(f"tools/art/.venv was made with Python {venv_version(VENV)}, not "
              f"{sys.version_info[0]}.{sys.version_info[1]}: rebuilding it", file=sys.stderr)
        shutil.rmtree(VENV)
    if not py.exists():
        subprocess.run([sys.executable, "-m", "venv", str(VENV)], check=True)
    probe = subprocess.run([str(py), "-c", "import PIL, numpy"], capture_output=True)
    if probe.returncode:
        subprocess.run([str(py), "-m", "pip", "install", "--quiet", "-r",
                        str(HERE / "requirements.txt")], check=True)
    os.execv(str(py), [str(py), str(Path(__file__).resolve()), *sys.argv[1:]])


def generated_dir():
    """The folder of the generated sheets: the one subfolder of `Enemy Pack` holding Animated/Raw."""
    found = sorted(p.parent.parent for p in (ASSETS / "Enemy Pack").glob("*/Animated/Raw"))
    if len(found) != 1:
        raise SystemExit(f"expected exactly one generated-sheet folder, found {len(found)}")
    return found[0] / "Animated" / "Raw"


def forbidden_word_check():
    """The name of the manga must appear nowhere under tools/art nor in CREDITS.md."""
    word = "sla" + "yer"
    bad = []
    files = [REPO / "CREDITS.md"] if (REPO / "CREDITS.md").exists() else []
    for root, dirs, names in os.walk(HERE):
        dirs[:] = [d for d in dirs if d not in (".venv", "node_modules", "__pycache__")]
        files += [Path(root) / n for n in names]
    for f in files:
        if f.suffix in (".png", ".pyc"):
            continue
        if word in f.read_text(errors="ignore").lower() or word in f.name.lower():
            bad.append(str(f.relative_to(REPO)))
    if bad:
        raise SystemExit("forbidden name found in: " + ", ".join(bad))


def main():
    import numpy as np
    from artpipe import atlas, clean, fingerprint, preview

    if "--fingerprint" in sys.argv[1:]:
        if not OUT.is_dir():
            raise SystemExit("tools/art/out/ does not exist: build it first")
        fingerprint.report(OUT)
        return
    if not (ASSETS / "README.md").exists():
        raise SystemExit("The art pack is missing: run `git submodule update --init assets` "
                         "(a private repository, see tools/art/README.md).")
    if "--pack-heights" in sys.argv[1:]:
        pack_heights()
        return
    manifest = tomllib.loads((HERE / "manifest.toml").read_text())
    s = manifest["settings"]
    method = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--resample=")),
                  s["resample"])
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir()

    sprites, origins = [], {}
    report = {"tolerance": s["key_tolerance"], "resample": method, "sprites": {}, "sheets": {}}
    cut_cache = {}
    for sp in manifest["sprite"]:
        name = sp["name"]
        poses, anims, sources = [], [], set()
        if sp["kind"] == "generated":
            path = generated_dir() / sp["file"]
            rows = [a["row"] for a in sp["anim"]]
            if sp["file"] not in cut_cache:
                cut_cache[sp["file"]] = clean.cut_generated(path, sorted(set(rows)), s)
            by_row, stats = cut_cache[sp["file"]]
            report["sheets"][name] = {"key": stats["key"], "dropped_specks": stats["dropped_specks"]}
            for a in sp["anim"]:
                anims.append((a, by_row[a["row"]]))
            sources.add("generated sheet")
        else:
            for a in sp["anim"]:
                anims.append((a, clean.cut_strip(ASSETS / sp["root"] / a["file"])))
            sources.add("original strips")
        every = [p for _, ps in anims for p in ps]
        cell_w, cell_h, baseline, cells = clean.place(every, s["cell_margin"])
        cells, cell_w, cell_h, baseline, scaled = scale_sprite(
            sp, anims, cells, cell_w, baseline, manifest["build"], method, s)
        k, out_anims = 0, []
        for a, ps in anims:
            out_anims.append({"name": a["name"], "fps": a["fps"], "loop": a["loop"],
                              "cells": cells[k:k + len(ps)]})
            k += len(ps)
        sprites.append({"name": name, "role": sp["role"], "cell_w": cell_w, "cell_h": cell_h,
                        "baseline": baseline, "anims": out_anims})
        origins[name] = sp["origin"]

        # Magenta left: any pixel with alpha > 0 within the tolerance of the key (must be zero),
        # and a wider "pinkish" count (R and B high, G low) reported for the eye.
        key = np.array(report["sheets"][name]["key"]) if name in report["sheets"] else \
            np.array([250, 3, 250])
        left = pink = 0
        for a in out_anims:
            for c in a["cells"]:
                vis = c[..., 3] > 0
                rgb = c[..., :3].astype(int)
                left += int((vis & (np.abs(rgb - key).max(axis=2) <= s["key_tolerance"])).sum())
                pink += int((vis & (rgb[..., 0] > 160) & (rgb[..., 2] > 160)
                             & (rgb[..., 1] < 110)).sum())
        report["sprites"][name] = {
            "role": sp["role"], "origin": sp["origin"], "kind": sp["kind"],
            "cell": [cell_w, cell_h], "baseline": baseline,
            "animations": {a["name"]: len(a["cells"]) for a in out_anims},
            "magenta_left": left, "pinkish": pink, "scale": scaled,
        }
        if left:
            raise SystemExit(f"{name}: {left} key-coloured pixels left in the output")

    try:
        check_scale(report["sprites"], manifest["order"])
    except SystemExit:
        print_scale(report)
        raise
    index = atlas.pack(sprites, s, OUT)
    for name, info in index["sprites"].items():
        report["sprites"][name]["page"] = f'atlas-{info["page"]}'
    pages = [json.loads((OUT / p["json"]).read_text()) for p in index["pages"]]
    verify(pages, index, sprites, s)
    (OUT / "sprites.json").write_text(json.dumps(index, indent=1) + "\n")
    report["pages"] = index["pages"]
    (OUT / "report.json").write_text(json.dumps(report, indent=1) + "\n")
    preview.write(OUT / "preview.html", pages, index, origins)
    forbidden_word_check()
    print_report(report)
    if "--check" in sys.argv[1:]:
        sys.stdout.flush()
        pixi_check()


def scale_sprite(sp, anims, cells, cell_w, baseline, builds, method, s):
    """Resample a sprite's placed cells to its build's height (artpipe/scale.py), unless every idle
    frame already stands within 2 px of it. `method`: nearest, area (then the palette snap), or
    area-blend (area without it, for comparison). Returns (cells, cell_w, cell_h, baseline, info)."""
    from artpipe import clean, scale
    k, idle = 0, None
    for a, ps in anims:
        if a["name"] == "idle":
            idle = slice(k, k + len(ps))
        k += len(ps)
    if idle is None:
        raise SystemExit(f'{sp["name"]}: no idle animation, its height cannot be measured')
    target = scale.target_height(sp, builds)
    cells_before = cells
    measured, before = scale.sprite_height(cells[idle])
    info = {"build": sp.get("build"), "target": target, "source": measured,
            "source_idle": [before[0], before[-1]], "factor": [1, 1]}
    if any(abs(h - target) > 2 for h in before):
        levels = scale.alpha_levels(cells)
        colours = scale.palette(cells, s["palette_max"]) if method == "area" else None
        kernel = "area" if method == "area-blend" else method
        out = [scale.resample(c, cell_w // 2, baseline, target, measured, kernel, levels)[0]
               for c in cells]
        if colours is not None:
            out = [scale.snap(c, colours) for c in out]
        info["palette"] = None if colours is None else len(colours)
        cell_w, _, baseline, cells = clean.place([clean.register(c) for c in out],
                                                 s["cell_margin"])
        info["factor"] = [target, measured]
    height, after = scale.sprite_height(cells[idle])
    info.update(height=height, idle=[after[0], after[-1]],
                source_frames=[scale.visible_height(c) for c in cells_before[idle]],
                frames=[scale.visible_height(c) for c in cells[idle]])
    return cells, cell_w, cells[0].shape[0], baseline, info


def pack_heights():
    """The visible height (artpipe/scale.py) of every original unit's idle strip in the pack: the
    blue units and the enemy pack. Prints the median and range over the idle frames."""
    from artpipe import clean, scale
    strips = sorted([*(ASSETS / "Units" / "Blue Units").glob("*/*Idle.png"),
                     *(ASSETS / "Enemy Pack").glob("*/*_Idle.png"),
                     *(ASSETS / "Enemy Pack" / "Extra").glob("*/*_Idle.png")])
    print(f"{'unit (idle strip)':<48}median  range")
    for path in strips:
        _, _, _, cells = clean.place(clean.cut_strip(path), 4)
        h, hs = scale.sprite_height(cells)
        name = str(path.relative_to(ASSETS).parent)
        print(f"{name:<48}{h:<8}{hs[0]}-{hs[-1]}")


def check_scale(sprites, order):
    """AC-1 and AC-2: every sprite's height (the median of its idle frames) within 2 px of its
    target; no basic goblin taller than the shortest profession; `order.tallest` the tallest
    sprite. Fails the build otherwise. The idle frames' own range (breathing, a raised weapon) is
    printed, not checked: a sprite whose idle moves by more than 4 px cannot fit ±2 at one scale."""
    from artpipe import scale
    problems = []
    for name, r in sprites.items():
        h, t = r["scale"]["height"], r["scale"]["target"]
        if abs(h - t) > 2:
            problems.append(f"{name}: {h} px tall (median of the idle frames), target {t} (±2)")
    problems += scale.check_order({n: r["scale"]["height"] for n, r in sprites.items()},
                                  order["basic"], order["tallest"],
                                  {n: r["role"] for n, r in sprites.items()})
    if problems:
        raise SystemExit("scale check failed:\n  " + "\n  ".join(problems))


def pixi_check():
    """AC-4: the atlases parse in PixiJS 8 (tools/art/check, its own package, outside the root
    pnpm workspace, hence --ignore-workspace)."""
    pnpm = ["pnpm", "--dir", str(HERE / "check"), "--ignore-workspace"]
    subprocess.run([*pnpm, "install", "--frozen-lockfile"], check=True)
    subprocess.run([*pnpm, "run", "check"], check=True)


def verify(pages, index, sprites, s):
    """Checks on what was written: pages within limits, frames inside pages, one cell size and
    one baseline per sprite, and every frame's pixels read back from the PNG."""
    from PIL import Image
    import numpy as np
    spec = {sp["name"]: sp for sp in sprites}
    for n, (page, info) in enumerate(zip(pages, index["pages"])):
        img = np.array(Image.open(OUT / info["image"]).convert("RGBA"))
        assert max(info["w"], info["h"]) <= s["atlas_max"], f"page {n} too large"
        assert img.shape[1] == info["w"] and img.shape[0] == info["h"]
        for key, f in page["frames"].items():
            fr, sr, src = f["frame"], f["spriteSourceSize"], f["sourceSize"]
            assert fr["x"] + fr["w"] <= info["w"] and fr["y"] + fr["h"] <= info["h"], key
            name = key.split("/")[0]
            assert src["w"] == spec[name]["cell_w"] and src["h"] == spec[name]["cell_h"], key
            assert sr["x"] + sr["w"] <= src["w"] and sr["y"] + sr["h"] <= src["h"], key
            assert abs(f["anchor"]["y"] - spec[name]["baseline"] / src["h"]) < 1e-5, key
            crop = img[fr["y"]:fr["y"] + fr["h"], fr["x"]:fr["x"] + fr["w"]]
            assert crop[..., 3].any(), key
            # Same baseline, read back from the PNG: the feet row of the frame as placed in its cell.
            solid = crop[..., 3] >= 64
            need = max(4, int(round(0.08 * fr["w"])))
            feet = np.flatnonzero(solid.sum(axis=1) >= need).max() + 1
            assert sr["y"] + feet == spec[name]["baseline"], f"{key}: baseline off"
        for anim, keys in page["animations"].items():
            assert keys and all(k in page["frames"] for k in keys), anim
        # What PixiJS 8's Spritesheet.parse reads: frames, animations, meta.image/size/scale.
        meta = page["meta"]
        assert meta["image"] == info["image"] and meta["scale"] == "1", n
        assert meta["size"] == {"w": info["w"], "h": info["h"]}, n
        # No two frames overlap, and the gutter between them is at least the atlas padding.
        boxes = [f["frame"] for f in page["frames"].values()]
        pad = s["atlas_padding"]
        for i, a in enumerate(boxes):
            for b in boxes[i + 1:]:
                apart = (a["x"] + a["w"] + pad <= b["x"] or b["x"] + b["w"] + pad <= a["x"]
                         or a["y"] + a["h"] + pad <= b["y"] or b["y"] + b["h"] + pad <= a["y"])
                assert apart, f"frames overlap or touch in page {n}"


def print_report(report):
    from artpipe import fingerprint
    print(f"key tolerance: {report['tolerance']} (max channel distance)")
    print(f"{'sprite':<11}{'role':<11}{'cell':<10}{'frames':<8}{'magenta':<8}{'pinkish':<8}page")
    for name, r in report["sprites"].items():
        frames = sum(r["animations"].values())
        print(f"{name:<11}{r['role']:<11}{r['cell'][0]}x{r['cell'][1]:<5}{frames:<8}"
              f"{r['magenta_left']:<8}{r['pinkish']:<8}{r['page']}")
    print_scale(report)
    fingerprint.report(OUT)


def print_scale(report):
    """The table of Scope 4: sprite, build, target, source height, factor, result, cell."""
    print(f"scale: resampling {report['resample']}; heights in px, visible height rule in "
          "artpipe/scale.py (idle frames, median and range)")
    print(f"{'sprite':<11}{'build':<8}{'target':<8}{'source':<14}{'factor':<16}{'result':<14}cell")
    for name, r in report["sprites"].items():
        c = r["scale"]
        p, q = c["factor"]
        factor = "1 (kept)" if p == q else f"{p}/{q}={p / q:.3f}"
        src = f"{c['source']} ({c['source_idle'][0]}-{c['source_idle'][1]})"
        res = f"{c['height']} ({c['idle'][0]}-{c['idle'][1]})"
        print(f"{name:<11}{c['build'] or '-':<8}{c['target']:<8}{src:<14}{factor:<16}{res:<14}"
              f"{r['cell'][0]}x{r['cell'][1]}")


if __name__ == "__main__":
    bootstrap()
    sys.path.insert(0, str(HERE))
    main()
