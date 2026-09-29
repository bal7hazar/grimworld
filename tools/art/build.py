#!/usr/bin/env python3
"""Asset pipeline entry point: `tools/art/build.py`.

Reads the private art pack (submodule `assets`), writes atlases, JSON, a report and a preview to
`tools/art/out/` (ignored by git, D-73). Needs Python 3.12 (re-executes under `python3.12` when
started by an older one); sets up its own virtualenv on first run. Deterministic: two runs give
byte-identical outputs; the pixel-and-metadata fingerprint is meant to match across machines
(README; a hypothesis until checked on Linux). Modes: see USAGE.
"""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
VENV = HERE / ".venv"
OUT = HERE / "out"
ASSETS = REPO / "assets"
PYTHON = (3, 12)            # NumPy 2.5.3 (requirements.txt) needs Python 3.12 or newer
MARKER = "GRIMWORLD_ART_REEXEC"   # set before re-executing under python3.12: never twice
METHODS = ("area", "area-blend", "nearest")
SPREAD = 6                  # px: an idle whose frames span more than this gets a warning
WORD = "sla" + "yer"        # the manga's name: never written nor printed (D-73, design/10)
USAGE = """usage: tools/art/build.py [--check] [--resample=area|area-blend|nearest]
       tools/art/build.py --fingerprint     fingerprints of the existing out/, no build
       tools/art/build.py --pack-heights    visible heights of the pack's own units
  --check              after the build, parse the atlases with PixiJS 8 (tools/art/check)
  --resample=FILTER    resampling filter of the generated sheets (default: the manifest's)"""

# Run by the venv's interpreter: its version and the installed versions of the named distributions.
PROBE = """import sys, json, importlib.metadata as m
def v(n):
    try:
        return m.version(n)
    except m.PackageNotFoundError:
        return None
print(json.dumps({"python": list(sys.version_info[:2]), "dists": {n: v(n) for n in sys.argv[1:]}}))
"""


def parse_args(argv):
    """The command line, checked before anything runs: unknown arguments and filters refused."""
    opts = {"check": False, "fingerprint": False, "pack_heights": False, "resample": None}
    for a in argv:
        if a in ("--check", "--fingerprint", "--pack-heights"):
            opts[a[2:].replace("-", "_")] = True
        elif a.startswith("--resample="):
            method = a.split("=", 1)[1]
            if method not in METHODS:
                raise SystemExit(f"--resample={method}: unknown filter, one of "
                                 f"{', '.join(METHODS)}\n{USAGE}")
            opts["resample"] = method
        else:
            raise SystemExit(f"unknown argument {a!r}\n{USAGE}")
    return opts


def probe_version(python, run=subprocess.run):
    """(major, minor) that an interpreter reports when run; None if it does not run."""
    r = run([str(python), "-c", "import sys; print('%d %d' % sys.version_info[:2])"],
            capture_output=True, text=True)
    parts = r.stdout.split() if r.returncode == 0 else []
    return (int(parts[0]), int(parts[1])) if len(parts) == 2 and all(
        p.isdigit() for p in parts) else None


def select_python(version, which, probe=probe_version, env=os.environ):
    """Which interpreter runs the build: None for the current one (`version` is at least 3.12),
    else the path of the `python3.12` found by `which`, once its own reported version is checked.
    Refuses, naming 3.12, when there is none, when it reports an older version, or when this
    process was already re-executed once (`MARKER` set). Called before any venv is touched."""
    if tuple(version[:2]) >= PYTHON:
        return None
    need = "tools/art/build.py needs Python %d.%d or newer (NumPy 2.5.3), found %d.%d" % (
        *PYTHON, *version[:2])
    if env.get(MARKER):
        raise SystemExit(f"{need}, after re-executing under python3.12 once already: refusing "
                         "to loop. Install Python 3.12 and run it again.")
    name = "python%d.%d" % PYTHON
    found = which(name)
    if not found:
        raise SystemExit(f"{need}, and no `{name}` on PATH: install Python 3.12 and run it again.")
    got = probe(found)
    if got is None or got < PYTHON:
        raise SystemExit(f"{need}; `{found}` (the `{name}` on PATH) reports "
                         f"{'no version' if got is None else '%d.%d' % got}: install Python "
                         "3.12 and run it again.")
    return found


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


def pins(path):
    """The pinned distributions of requirements.txt: {lower-case name: version}."""
    out = {}
    for line in path.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            name, sep, version = line.partition("==")
            if not sep:
                raise SystemExit(f"{path.name}: {line!r} is not pinned with ==")
            out[name.strip().lower()] = version.strip()
    return out


def venv_problem(venv, want, run=subprocess.run):
    """Why the venv cannot be used as it is: "missing", or what is wrong, or None when it is fine.
    Asks its interpreter itself (not only pyvenv.cfg): its version must be 3.12 or newer and agree
    with pyvenv.cfg, and every pin of requirements.txt must be installed at its version. A venv of
    3.13 is fine under a 3.12 start: no rebuild between two good versions."""
    py = venv / "bin" / "python"
    if not py.exists():
        return "missing"
    r = run([str(py), "-c", PROBE, *sorted(want)], capture_output=True, text=True)
    try:
        info = json.loads(r.stdout) if r.returncode == 0 else None
    except ValueError:
        info = None
    if info is None:
        return "its interpreter does not run"
    got = tuple(info["python"])
    if got < PYTHON:
        return "its interpreter is Python %d.%d, older than 3.12" % got
    cfg = venv_version(venv)
    if cfg is not None and cfg != got:
        return "pyvenv.cfg says Python %d.%d, its interpreter is %d.%d" % (*cfg, *got)
    for name, version in sorted(want.items()):
        have = info["dists"].get(name)
        if have != version:
            return f"{name} {have or 'missing'}, requirements.txt pins {version}"
    return None


def bootstrap(version=None, which=shutil.which, probe=probe_version, run=subprocess.run,
              execv=os.execv, env=os.environ):
    """Re-run under Python 3.12+, then under tools/art/.venv: created when missing, rebuilt when
    `venv_problem` finds it unusable, then checked again before use."""
    version = version or sys.version_info
    script = str(Path(__file__).resolve())
    other = select_python(version, which, probe, env)
    if other:
        print(f"Python {version[0]}.{version[1]}: re-executing under {other}", file=sys.stderr)
        sys.stderr.flush()
        env[MARKER] = "1"
        return execv(other, [other, script, *sys.argv[1:]])
    env.pop(MARKER, None)
    py = VENV / "bin" / "python"
    if Path(sys.prefix).resolve() == VENV.resolve():
        return None
    want = pins(HERE / "requirements.txt")
    problem = venv_problem(VENV, want, run)
    if problem:
        if VENV.exists():
            print(f"tools/art/.venv: {problem}: rebuilding it", file=sys.stderr)
            shutil.rmtree(VENV)
        run([sys.executable, "-m", "venv", str(VENV)], check=True)
        run([str(py), "-m", "pip", "install", "--quiet", "-r", str(HERE / "requirements.txt")],
            check=True)
        problem = venv_problem(VENV, want, run)
        if problem:
            raise SystemExit(f"tools/art/.venv is still unusable after a rebuild: {problem}")
    return execv(str(py), [str(py), script, *sys.argv[1:]])


class Redacted:
    """A text stream that never lets the manga's name through (D-73): every output of the build,
    tracebacks and error messages included, goes through it."""

    def __init__(self, stream):
        self.stream = stream

    def write(self, text):
        return self.stream.write(re.sub(WORD, "<generated>", text, flags=re.IGNORECASE))

    def __getattr__(self, name):
        return getattr(self.stream, name)


def generated_dir():
    """The folder of the generated sheets: the one subfolder of `Enemy Pack` holding Animated/Raw."""
    found = sorted(p.parent.parent for p in (ASSETS / "Enemy Pack").glob("*/Animated/Raw"))
    if len(found) != 1:
        raise SystemExit(f"expected exactly one generated-sheet folder, found {len(found)}")
    return found[0] / "Animated" / "Raw"


def forbidden_word_check():
    """The name of the manga must appear nowhere under tools/art nor in CREDITS.md."""
    bad = []
    files = [REPO / "CREDITS.md"] if (REPO / "CREDITS.md").exists() else []
    for root, dirs, names in os.walk(HERE):
        dirs[:] = [d for d in dirs if d not in (".venv", "node_modules", "__pycache__")]
        files += [Path(root) / n for n in names]
    for f in files:
        if f.suffix in (".png", ".pyc"):
            continue
        if WORD in f.read_text(errors="ignore").lower() or WORD in f.name.lower():
            bad.append(str(f.relative_to(REPO)))
    if bad:
        raise SystemExit("forbidden name found in: " + ", ".join(bad))


def main(opts):
    import tomllib

    import numpy as np
    from artpipe import atlas, clean, fingerprint, preview, scale

    if opts["fingerprint"]:
        if not OUT.is_dir():
            raise SystemExit("tools/art/out/ does not exist: build it first")
        fingerprint.report(OUT)
        return
    if not (ASSETS / "README.md").exists():
        raise SystemExit("The art pack is missing: run `git submodule update --init assets` "
                         "(a private repository, see tools/art/README.md).")
    if opts["pack_heights"]:
        pack_heights()
        return
    manifest = tomllib.loads((HERE / "manifest.toml").read_text())
    s = manifest["settings"]
    method = opts["resample"] or s["resample"]
    if method not in METHODS:
        raise SystemExit(f"manifest.toml: resample = {method!r}, not one of {', '.join(METHODS)}")
    roles = {sp["name"]: sp["role"] for sp in manifest["sprite"]}
    problems = scale.validate_order(manifest["order"], roles)
    problems += [f"[height] names {n!r}, which is not a sprite of the manifest"
                 for n in manifest["height"] if n not in roles]
    if problems:
        raise SystemExit("manifest.toml:\n  " + "\n  ".join(problems))
    specs = {n: scale.height_spec(n, manifest["height"]) for n in roles}
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir()

    sprites, origins = [], {}
    report = {"tolerance": s["key_tolerance"], "resample": method, "sprites": {}, "sheets": {}}
    cut_cache = {}
    for sp in manifest["sprite"]:
        name = sp["name"]
        anims = []
        if sp["kind"] == "generated":
            path = generated_dir() / sp["file"]
            rows = [a["row"] for a in sp["anim"]]
            if sp["file"] not in cut_cache:
                cut_cache[sp["file"]] = clean.cut_generated(path, sorted(set(rows)), s)
            by_row, stats = cut_cache[sp["file"]]
            report["sheets"][name] = {"key": stats["key"], "dropped_specks": stats["dropped_specks"]}
            for a in sp["anim"]:
                anims.append((a, by_row[a["row"]]))
        else:
            for a in sp["anim"]:
                anims.append((a, clean.cut_strip(ASSETS / sp["root"] / a["file"])))
        every = [p for _, ps in anims for p in ps]
        cell_w, cell_h, baseline, cells = clean.place(every, s["cell_margin"])
        cells, cell_w, cell_h, baseline, scaled = scale_sprite(
            name, anims, cells, cell_w, baseline, specs[name], method, s)
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
        for warning in check_scale(report["sprites"], manifest["order"]):
            print(f"warning: {warning}")
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
    if opts["check"]:
        sys.stdout.flush()
        pixi_check()


def scale_sprite(name, anims, cells, cell_w, baseline, spec, method, s):
    """A sprite's placed cells at its height (artpipe/scale.py). `spec` "native": kept as they are
    (factor 1, pixels untouched). A number: resampled by spec / measured height, unless it already
    measures exactly that. `method`: nearest, area (then the palette snap), or area-blend (area
    without it, for comparison). Returns (cells, cell_w, cell_h, baseline, info)."""
    from artpipe import clean, scale
    k, idle = 0, None
    for a, ps in anims:
        if a["name"] == "idle":
            idle = slice(k, k + len(ps))
        k += len(ps)
    if idle is None:
        raise SystemExit(f"{name}: no idle animation, its height cannot be measured")
    cells_before = cells
    measured, before = scale.sprite_height(cells[idle])
    target = measured if spec == scale.NATIVE else spec
    info = {"spec": spec, "target": target, "source": measured,
            "source_idle": [before[0], before[-1]], "factor": [1, 1]}
    if target != measured:
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
    blue units and the enemy pack, never the generated folder (whose name is not printed)."""
    from artpipe import clean, scale
    generated = generated_dir().parent.parent
    strips = sorted(p for p in [*(ASSETS / "Units" / "Blue Units").glob("*/*Idle.png"),
                                *(ASSETS / "Enemy Pack").glob("*/*_Idle.png"),
                                *(ASSETS / "Enemy Pack" / "Extra").glob("*/*_Idle.png")]
                    if generated not in p.parents)
    print(f"{'unit (idle strip)':<48}median  range")
    for path in strips:
        _, _, _, cells = clean.place(clean.cut_strip(path), 4)
        h, hs = scale.sprite_height(cells)
        name = str(path.relative_to(ASSETS).parent)
        print(f"{name:<48}{h:<8}{hs[0]}-{hs[-1]}")


def check_scale(sprites, order):
    """AC-1 and AC-2, on the result. Every resampled sprite's height (the median of its idle
    frames) within 2 px of its target; a native one is its own target. The order rule of
    `scale.check_order`. Fails the build otherwise. Returns warnings: an idle whose frames span
    more than SPREAD px (breathing, a limb crossing the measured band)."""
    from artpipe import scale
    problems, warnings = [], []
    for name, r in sprites.items():
        c = r["scale"]
        if abs(c["height"] - c["target"]) > 2:
            problems.append(f"{name}: {c['height']} px tall (median of the idle frames), "
                            f"target {c['target']} (±2)")
        lo, hi = c["idle"]
        if hi - lo > SPREAD:
            warnings.append(f"{name}: idle frames span {hi - lo} px ({lo}-{hi}), more than "
                            f"{SPREAD}: the height is their median")
    problems += scale.check_order({n: r["scale"]["height"] for n, r in sprites.items()}, order,
                                  {n: r["role"] for n, r in sprites.items()},
                                  {n: r["kind"] for n, r in sprites.items()})
    if problems:
        raise SystemExit("scale check failed:\n  " + "\n  ".join(problems))
    return warnings


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
            need = max(4, (8 * fr["w"] + 50) // 100)            # as clean.register
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
    """The table of Scope 4: sprite, height (native or a number), target, source height, factor,
    result, cell."""
    print(f"scale: resampling {report['resample']}; heights in px, visible height rule in "
          "artpipe/scale.py (idle frames, median and range)")
    print(f"{'sprite':<11}{'height':<8}{'target':<8}{'source':<14}{'factor':<16}{'result':<14}cell")
    for name, r in report["sprites"].items():
        c = r["scale"]
        p, q = c["factor"]
        factor = "1 (native)" if c["spec"] == "native" else (
            "1" if p == q else f"{p}/{q}={p / q:.3f}")
        src = f"{c['source']} ({c['source_idle'][0]}-{c['source_idle'][1]})"
        res = f"{c['height']} ({c['idle'][0]}-{c['idle'][1]})"
        print(f"{name:<11}{str(c['spec']):<8}{c['target']:<8}{src:<14}{factor:<16}{res:<14}"
              f"{r['cell'][0]}x{r['cell'][1]}")


if __name__ == "__main__":
    sys.stdout, sys.stderr = Redacted(sys.stdout), Redacted(sys.stderr)
    options = parse_args(sys.argv[1:])
    bootstrap()
    sys.path.insert(0, str(HERE))
    main(options)
