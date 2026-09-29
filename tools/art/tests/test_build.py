"""Tests of tools/art (ART-02): command line, Python selection, the venv, scaling, the order check,
the PNG writer, the fingerprints, keying.

Run: tools/art/.venv/bin/python -m unittest discover -s tools/art/tests
(the command-line and Python-selection tests need only the standard library; the others need the
venv's NumPy and Pillow, and are skipped without them).
"""

import io
import json
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import build  # noqa: E402

try:
    import numpy as np
    from PIL import Image

    from artpipe import clean, fingerprint, png, scale
except ImportError:                                         # outside the venv
    np = None

PINS = build.pins(HERE / "requirements.txt")


class CommandLine(unittest.TestCase):
    def test_modes_and_filter(self):
        o = build.parse_args(["--check", "--resample=nearest"])
        self.assertTrue(o["check"])
        self.assertEqual(o["resample"], "nearest")
        self.assertTrue(build.parse_args(["--pack-heights"])["pack_heights"])
        self.assertTrue(build.parse_args(["--fingerprint"])["fingerprint"])

    def test_unknown_filter_refused_at_once(self):
        with self.assertRaises(SystemExit) as e:
            build.parse_args(["--resample=lanczos"])
        self.assertIn("unknown filter", str(e.exception))

    def test_unknown_argument_refused(self):
        with self.assertRaises(SystemExit) as e:
            build.parse_args(["--chek"])
        self.assertIn("unknown argument '--chek'", str(e.exception))

    def test_output_never_carries_the_forbidden_name(self):
        sink = io.StringIO()
        build.Redacted(sink).write("Enemy Pack/Goblin " + build.WORD.title() + " Pack/x.png\n")
        self.assertNotIn(build.WORD, sink.getvalue().lower())
        self.assertIn("<generated>", sink.getvalue())


class PythonSelection(unittest.TestCase):
    def test_current_python_when_3_12_or_newer(self):
        self.assertIsNone(build.select_python((3, 12, 0), lambda n: None, env={}))
        self.assertIsNone(build.select_python((3, 13, 1), lambda n: None, env={}))

    def test_reexecutes_under_a_probed_python3_12(self):
        asked = []
        found = build.select_python((3, 11, 6), lambda n: asked.append(n) or "/x/python3.12",
                                    probe=lambda p: (3, 12), env={})
        self.assertEqual(found, "/x/python3.12")
        self.assertEqual(asked, ["python3.12"])

    def test_refuses_naming_3_12_when_none_reachable(self):
        with self.assertRaises(SystemExit) as e:
            build.select_python((3, 11, 6), lambda n: None, env={})
        self.assertIn("3.12", str(e.exception))
        self.assertIn("python3.12", str(e.exception))

    def test_refuses_a_python3_12_that_is_not(self):
        for got in ((3, 11), None):
            with self.assertRaises(SystemExit) as e:
                build.select_python((3, 11, 6), lambda n: "/x/python3.12", probe=lambda p: got,
                                    env={})
            self.assertIn("/x/python3.12", str(e.exception))

    def test_never_reexecutes_twice(self):
        with self.assertRaises(SystemExit) as e:
            build.select_python((3, 11, 6), lambda n: "/x/python3.12", probe=lambda p: (3, 12),
                                env={build.MARKER: "1"})
        self.assertIn("once already", str(e.exception))

    def test_reexecution_sets_the_marker(self):
        env, calls = {}, []
        build.bootstrap((3, 11, 6), lambda n: "/x/python3.12", probe=lambda p: (3, 12),
                        execv=lambda *a: calls.append(a), env=env)
        self.assertEqual(calls[0][0], "/x/python3.12")
        self.assertEqual(env.get(build.MARKER), "1")

    def test_refusal_comes_before_any_venv(self):
        with tempfile.TemporaryDirectory() as tmp:
            venv = Path(tmp) / ".venv"
            saved, build.VENV = build.VENV, venv
            try:
                with self.assertRaises(SystemExit):
                    build.bootstrap((3, 11, 6), lambda n: None, env={})
            finally:
                build.VENV = saved
            self.assertFalse(venv.exists())

    def test_venv_version_read_from_pyvenv_cfg(self):
        with tempfile.TemporaryDirectory() as tmp:
            venv = Path(tmp)
            self.assertIsNone(build.venv_version(venv))
            (venv / "pyvenv.cfg").write_text("home = /usr/bin\nversion = 3.11.6\n")
            self.assertEqual(build.venv_version(venv), (3, 11))
            (venv / "pyvenv.cfg").write_text("home = /usr/bin\nversion_info = 3.12.0.final.0\n")
            self.assertEqual(build.venv_version(venv), (3, 12))

    def test_pins_read_from_requirements(self):
        self.assertEqual(PINS, {"numpy": "2.5.3", "pillow": "12.3.0"})


class FakeVenv:
    """Stands in for subprocess.run on a venv: `python -m venv`, `pip install`, and the probe."""

    def __init__(self, venv, python=None, dists=None, cfg=None):
        self.venv, self.python, self.dists = venv, python, dict(dists or {})
        self.created = self.installed = 0
        if python:
            self.make(cfg or python)

    def make(self, cfg):
        (self.venv / "bin").mkdir(parents=True, exist_ok=True)
        (self.venv / "bin" / "python").write_text("")
        (self.venv / "pyvenv.cfg").write_text("version = %d.%d.0\n" % cfg)

    def __call__(self, cmd, **kw):
        cmd = [str(c) for c in cmd]
        if cmd[1:3] == ["-m", "venv"]:
            self.python, self.dists = (3, 12), {}
            self.make((3, 12))
            self.created += 1
            return subprocess.CompletedProcess(cmd, 0, "", "")
        if cmd[1:3] == ["-m", "pip"]:
            self.dists = dict(PINS)
            self.installed += 1
            return subprocess.CompletedProcess(cmd, 0, "", "")
        info = {"python": list(self.python), "dists": {n: self.dists.get(n) for n in cmd[3:]}}
        return subprocess.CompletedProcess(cmd, 0, json.dumps(info), "")


class Venv(unittest.TestCase):
    def boot(self, fake):
        calls = []
        saved, build.VENV = build.VENV, fake.venv
        try:
            build.bootstrap((3, 12, 0), lambda n: None, run=fake,
                            execv=lambda *a: calls.append(a), env={})
        finally:
            build.VENV = saved
        return calls

    def test_missing_venv_is_created_and_checked(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeVenv(Path(tmp) / ".venv")
            calls = self.boot(fake)
            self.assertEqual((fake.created, fake.installed), (1, 1))
            self.assertTrue(calls[0][0].endswith(".venv/bin/python"))

    def test_venv_of_python_3_11_is_rebuilt(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeVenv(Path(tmp) / ".venv", python=(3, 11), dists=PINS)
            self.boot(fake)
            self.assertEqual((fake.created, fake.installed), (1, 1))

    def test_venv_of_python_3_13_is_kept_under_3_12(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeVenv(Path(tmp) / ".venv", python=(3, 13), dists=PINS)
            calls = self.boot(fake)
            self.assertEqual((fake.created, fake.installed), (0, 0))
            self.assertEqual(len(calls), 1)

    def test_wrong_distribution_version_rebuilds(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeVenv(Path(tmp) / ".venv", python=(3, 12), dists=dict(PINS, numpy="2.4.0"))
            self.assertIn("numpy 2.4.0", build.venv_problem(fake.venv, PINS, fake))
            self.boot(fake)
            self.assertEqual((fake.created, fake.installed), (1, 1))

    def test_interpreter_disagreeing_with_pyvenv_cfg_rebuilds(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeVenv(Path(tmp) / ".venv", python=(3, 13), dists=PINS, cfg=(3, 12))
            self.assertIn("pyvenv.cfg says Python 3.12", build.venv_problem(fake.venv, PINS, fake))

    def test_venv_without_pyvenv_cfg_rebuilds(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeVenv(Path(tmp) / ".venv", python=(3, 12), dists=PINS)
            (fake.venv / "pyvenv.cfg").unlink()
            self.assertEqual(build.venv_problem(fake.venv, PINS, fake), "no readable pyvenv.cfg")
            self.boot(fake)
            self.assertEqual((fake.created, fake.installed), (1, 1))

    def test_handoff_happens_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeVenv(Path(tmp) / ".venv", python=(3, 12), dists=PINS)
            env, calls = {}, []
            saved, build.VENV = build.VENV, fake.venv
            try:
                build.bootstrap((3, 12, 0), lambda n: None, run=fake,
                                execv=lambda *a: calls.append(a), env=env)
                self.assertEqual(env.get(build.HANDOFF), "1")
                # the handed-off interpreter does not run inside the venv (sys.prefix elsewhere)
                with self.assertRaises(SystemExit) as e:
                    build.bootstrap((3, 12, 0), lambda n: None, run=fake,
                                    execv=lambda *a: calls.append(a), env=env)
            finally:
                build.VENV = saved
            self.assertIn("refusing to loop", str(e.exception))
            self.assertEqual(len(calls), 1)

    def direct(self, venv, dists, cfg=True):
        """Started directly by the venv's interpreter (sys.prefix is the venv)."""
        env = {build.HANDOFF: "1"}
        saved, build.VENV = build.VENV, venv
        try:
            return build.bootstrap((3, 12, 0), lambda n: None, env=env, prefix=venv,
                                   info=lambda want: {"python": [3, 12], "dists": dists},
                                   execv=lambda *a: self.fail("no exec from inside the venv")), env
        finally:
            build.VENV = saved

    def test_direct_launch_from_a_good_venv(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeVenv(Path(tmp) / ".venv", python=(3, 12), dists=PINS)
            result, env = self.direct(fake.venv, PINS)
            self.assertIsNone(result)
            self.assertNotIn(build.HANDOFF, env)

    def test_direct_launch_from_an_unpinned_venv_refuses(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeVenv(Path(tmp) / ".venv", python=(3, 12), dists=PINS)
            with self.assertRaises(SystemExit) as e:
                self.direct(fake.venv, dict(PINS, pillow="11.0.0"))
            self.assertIn("the running venv: pillow 11.0.0, requirements.txt pins 12.3.0",
                          str(e.exception))
            (fake.venv / "pyvenv.cfg").unlink()
            with self.assertRaises(SystemExit) as e:
                self.direct(fake.venv, PINS)
            self.assertIn("no readable pyvenv.cfg", str(e.exception))

    def test_still_unusable_after_rebuild_refuses(self):
        class Broken(FakeVenv):
            def __call__(self, cmd, **kw):
                done = super().__call__(cmd, **kw)
                self.dists = {}
                return done
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(SystemExit) as e:
                self.boot(Broken(Path(tmp) / ".venv"))
            self.assertIn("still unusable", str(e.exception))


@unittest.skipIf(np is None, "needs the venv (NumPy, Pillow)")
class Scale(unittest.TestCase):
    def body(self, h=40, w=12, colour=(200, 30, 30)):
        cell = np.zeros((h + 20, w + 20, 4), np.uint8)
        cell[10:10 + h, 10:10 + w] = (*colour, 255)
        return cell

    def test_weights_cover_each_output_pixel_once(self):
        for size, anchor, p, q in ((50, 30, 78, 147), (50, 30, 94, 67), (9, 9, 3, 2)):
            w, a_out, out = scale.axis_weights(size, anchor, p, q)
            self.assertTrue((w.sum(axis=0) == p).all())          # every source pixel spread whole
            inner = w.sum(axis=1)[:-1]
            self.assertTrue((inner[1:] == q).all())              # every inner output pixel full
            self.assertEqual((a_out, out), scale.grid(size, anchor, p, q))

    def test_anchor_stays_on_the_baseline(self):
        cell = self.body()
        for method in ("area", "nearest"):
            out, ax, ay = scale.resample(cell, 16, 50, 3, 2, method, [0, 255])
            rows = np.flatnonzero(out[..., 3].any(axis=1))
            self.assertEqual(rows.max() + 1, ay, method)         # feet end on the new baseline
            self.assertEqual(len(rows), 60, method)              # 40 px x 3/2

    def test_visible_height_leaves_out_a_raised_weapon(self):
        cell = self.body()
        cell[0:10, 2:4, 3] = 255                                 # a thin pole beside the head
        self.assertEqual(scale.visible_height(cell), 40)

    def test_area_adds_no_alpha_level(self):
        cell = self.body()
        cell[30:50, 10:22, 3] = 80                               # a translucent part
        out, _, _ = scale.resample(cell, 16, 50, 94, 67, "area", [0, 80, 255])
        self.assertLessEqual(set(np.unique(out[..., 3]).tolist()), {0, 80, 255})

    def test_snap_removes_the_blend_of_two_colours(self):
        cell = self.body(w=14)
        cell[10:50, 17:24, :3] = (20, 20, 160)                   # right half another colour
        pal = scale.palette([cell], 64)
        self.assertEqual(len(pal), 2)
        out, _, _ = scale.resample(cell, 16, 50, 5, 3, "area", [0, 255])   # a non-integer factor
        vis = out[..., 3] > 0
        blended = {tuple(c) for c in out[vis][:, :3].tolist()}
        self.assertGreater(len(blended), 2)                      # area alone blends the seam
        snapped = scale.snap(out, pal)
        kept = {tuple(c) for c in snapped[snapped[..., 3] > 0][:, :3].tolist()}
        self.assertEqual(kept, {(200, 30, 30), (20, 20, 160)})

    def manifest(self, **height):
        sprites = [{"name": n, "role": r} for n, r in (
            ("runt", "caste"), ("skirmisher", "caste"), ("slinger", "caste"), ("hob", "caste"),
            ("cleric", "profession"))]
        heights = dict({"runt": 67, "skirmisher": "native", "slinger": "native", "hob": 119,
                        "cleric": "native"}, **height)
        return {"sprite": sprites, "height": heights, "settings": {"resample": "area"},
                "order": {"basic": ["runt", "skirmisher", "slinger"], "exempt": ["skirmisher"],
                          "tallest": "hob"}}

    def test_validate_manifest(self):
        methods = build.METHODS
        self.assertEqual(scale.validate_manifest(self.manifest(), methods), [])
        m = self.manifest(slinger="big", ghost=70)
        del m["height"]["cleric"]
        m["settings"]["resample"] = "lanczos"
        problems = scale.validate_manifest(m, methods)
        self.assertTrue(any("'ghost', which is not a sprite" in p for p in problems))
        self.assertTrue(any("cleric: no line in [height]" in p for p in problems))
        self.assertTrue(any("slinger = 'big'" in p for p in problems))
        self.assertTrue(any("settings.resample = 'lanczos'" in p for p in problems))
        self.assertTrue(any("height = 0" in p or "runt = 0" in p
                            for p in scale.validate_manifest(self.manifest(runt=0), methods)))

    def test_exemption_must_be_native_and_basic(self):
        problems = scale.validate_manifest(self.manifest(skirmisher=75), build.METHODS)
        self.assertEqual(problems, ["[order] exempt 'skirmisher' is resampled ([height] 75): only "
                                    "a native sprite may be exempt"])
        m = self.manifest()
        m["order"]["exempt"] = ["hob"]
        self.assertIn("[order] exempt 'hob' is not in basic",
                      scale.validate_manifest(m, build.METHODS))

    def test_order_rule(self):
        m = self.manifest()
        role = {sp["name"]: sp["role"] for sp in m["sprite"]}
        good = {"runt": 67, "skirmisher": 70, "slinger": 67, "hob": 119, "cleric": 67}
        self.assertEqual(scale.check_order(good, m["order"], role, m["height"]), [])
        problems = scale.check_order(dict(good, runt=70), m["order"], role, m["height"])
        self.assertEqual(problems, ["runt (70 px) is taller than the shortest profession, "
                                    "cleric (67 px)"])
        slinger80 = dict(m["height"], slinger=80)                  # a resampled basic goblin
        problems = scale.check_order(dict(good, slinger=80), m["order"], role, slinger80)
        self.assertEqual(problems, ["slinger (80 px) is taller than the shortest profession, "
                                    "cleric (67 px)"])
        problems = scale.check_order(dict(good, hob=70), m["order"], role, m["height"])
        self.assertTrue(any("hob (70 px) is not taller than skirmisher" in p for p in problems))

    def test_order_validated(self):
        role = {"runt": "caste", "hob": "caste", "cleric": "profession"}
        self.assertEqual(scale.validate_order({"basic": ["runt"], "tallest": "hob"}, role), [])
        problems = scale.validate_order({"basic": ["grunt"], "tallest": "boss"}, role)
        self.assertEqual(len(problems), 2)
        self.assertIn("'grunt'", problems[0])
        no_hero = {"runt": "caste", "hob": "caste"}
        self.assertIn("no profession",
                      scale.validate_order({"basic": ["runt"], "tallest": "hob"}, no_hero)[0])

    def placed(self, heights):
        poses = [clean.register(self.body(h=h)) for h in heights]
        return clean.place(poses, 4)

    def test_scale_sprite_native_keeps_the_cells(self):
        s = {"palette_max": 64, "cell_margin": 4}
        cw, ch, base, cells = self.placed([40, 41, 40])
        anims = [({"name": "idle"}, [None] * 3)]
        out, w, h, b, info = build.scale_sprite("x", anims, cells, cw, base, "native", "area", s)
        self.assertIs(out, cells)
        self.assertEqual((w, h, b, info["factor"], info["target"]), (cw, ch, base, [1, 1], 40))

    def test_scale_sprite_keeps_the_cells_at_their_height(self):
        s = {"palette_max": 64, "cell_margin": 4}
        cw, ch, base, cells = self.placed([40, 41, 40])
        anims = [({"name": "idle"}, [None] * 3)]
        out, w, h, b, info = build.scale_sprite("x", anims, cells, cw, base, 40, "area", s)
        self.assertIs(out, cells)                                # target = measured: no resampling
        self.assertEqual((info["factor"], info["height"]), ([1, 1], 40))

    def test_scale_sprite_to_a_height(self):
        s = {"palette_max": 64, "cell_margin": 4}
        cw, ch, base, cells = self.placed([40, 41, 40, 39])
        anims = [({"name": "idle"}, [None] * 2), ({"name": "move"}, [None] * 2)]
        out, w, h, b, info = build.scale_sprite("x", anims, cells, cw, base, 27, "area", s)
        self.assertEqual(info["factor"], [27, 40])
        self.assertLessEqual(abs(info["height"] - 27), 2)
        self.assertEqual(len(out), 4)

    def test_check_scale_fails_and_warns(self):
        def entry(role, kind, target, height, idle):
            spec = target if kind == "generated" else "native"
            return {"role": role, "kind": kind,
                    "scale": {"target": target, "height": height, "idle": idle, "spec": spec}}
        order = {"basic": ["runt"], "tallest": "hob"}
        sprites = {"runt": entry("caste", "generated", 67, 67, [66, 67]),
                   "hob": entry("caste", "generated", 119, 119, [110, 119]),
                   "cleric": entry("profession", "strip", 67, 67, [66, 68])}
        warnings = build.check_scale(sprites, order)
        self.assertEqual(len(warnings), 1)
        self.assertIn("hob: idle frames span 9 px", warnings[0])
        sprites["runt"]["scale"]["height"] = 72
        with self.assertRaises(SystemExit) as e:
            build.check_scale(sprites, order)
        self.assertIn("runt: 72 px tall", str(e.exception))


@unittest.skipIf(np is None, "needs the venv (NumPy, Pillow)")
class Keying(unittest.TestCase):
    def test_key_is_removed_and_neutral_kept_in_integers(self):
        s = {"key_tolerance": 48, "fringe_radius": 2, "min_alpha": 0.06}
        rgb = np.zeros((30, 30, 3), np.uint8)
        rgb[:] = (250, 3, 250)
        rgb[10:20, 10:20] = (90, 90, 90)
        out, key = clean.key_sheet(rgb, s)
        self.assertEqual(key.tolist(), [250, 3, 250])
        self.assertEqual(out.dtype, np.uint8)
        self.assertTrue((out[:5, :5, 3] == 0).all())
        self.assertTrue((out[12:18, 12:18] == (90, 90, 90, 255)).all())

    def test_exact_half_fringe_pixel(self):
        # key (250, 4, 250): m_key = 250 + 250 - 8 = 492. A 50 % mix of grey (100, 100, 100) and
        # the key is (175, 52, 175): m = 246 = m_key / 2, so a = 255 / 2 = 127.5, rounded half up
        # to 128; colour (255 p - 127 key) / 128 = (100.58, 99.63, 100.58), rounded to (101, 100).
        s = {"key_tolerance": 48, "fringe_radius": 2, "min_alpha": 0.06}
        rgb = np.zeros((40, 40, 3), np.uint8)
        rgb[:] = (250, 4, 250)
        rgb[16:24, 16:24] = (100, 100, 100)
        rgb[16:24, 15] = (175, 52, 175)
        out, _ = clean.key_sheet(rgb, s)
        self.assertEqual(out[20, 15].tolist(), [101, 100, 101, 128])
        self.assertEqual(out[20, 14].tolist(), [0, 0, 0, 0])

    def test_div_round_half_up_with_negative_numerators(self):
        num = np.array([-3, -5, -1, 0, 1, 3, 5])
        self.assertEqual(clean.div_round(num, 2).tolist(), [-1, -2, 0, 0, 1, 2, 3])
        self.assertEqual(clean.div_round(np.array([-7, 7]), 4).tolist(), [-2, 2])   # -1.75, 1.75


@unittest.skipIf(np is None, "needs the venv (NumPy, Pillow)")
class Png(unittest.TestCase):
    def roundtrip(self, img):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.png"
            png.write(path, img)
            return np.array(Image.open(path).convert("RGBA")), path.read_bytes()

    def test_pixels_read_back_for_any_shape(self):
        rng = np.random.default_rng(7)
        cases = [rng.integers(0, 256, shape + (4,), dtype=np.uint8)
                 for shape in ((1, 1), (1, 9), (9, 1), (37, 53))]
        cases.append(np.full((8, 8, 4), (10, 200, 30, 255), np.uint8))       # flat
        for img in cases:
            back, _ = self.roundtrip(img)
            self.assertTrue((back == img).all(), img.shape)

    def test_chunk_sequence(self):
        _, data = self.roundtrip(np.zeros((3, 5, 4), np.uint8))
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        kinds, i = [], 8
        while i < len(data):
            n = struct.unpack(">I", data[i:i + 4])[0]
            kind, body = data[i + 4:i + 8], data[i + 8:i + 8 + n]
            crc = struct.unpack(">I", data[i + 8 + n:i + 12 + n])[0]
            self.assertEqual(crc, zlib.crc32(kind + body) & 0xFFFFFFFF)
            kinds.append(kind)
            i += 12 + n
        self.assertEqual(kinds, [b"IHDR", b"IDAT", b"IEND"])

    def test_same_array_same_bytes(self):
        img = np.random.default_rng(3).integers(0, 256, (20, 30, 4), dtype=np.uint8)
        self.assertEqual(self.roundtrip(img)[1], self.roundtrip(img)[1])


@unittest.skipIf(np is None, "needs the venv (NumPy, Pillow)")
class Fingerprint(unittest.TestCase):
    def out(self, root, img, writer):
        root.mkdir()
        writer(root / "atlas-0.png", img)
        (root / "atlas-0.json").write_text('{"b": 1, "a": [1, 2]}\n')
        return root

    def test_encoder_moves_files_not_content(self):
        img = np.random.default_rng(5).integers(0, 256, (16, 24, 4), dtype=np.uint8)

        def pillow(path, a):
            Image.fromarray(a, "RGBA").save(path, optimize=False, compress_level=9)
        with tempfile.TemporaryDirectory() as tmp:
            a = self.out(Path(tmp) / "a", img, png.write)
            b = self.out(Path(tmp) / "b", img, pillow)
            self.assertEqual(fingerprint.content(a), fingerprint.content(b))
            self.assertNotEqual(fingerprint.files(a), fingerprint.files(b))

    def test_one_pixel_moves_content(self):
        img = np.zeros((6, 6, 4), np.uint8)
        other = img.copy()
        other[3, 3] = (1, 0, 0, 255)
        with tempfile.TemporaryDirectory() as tmp:
            a = self.out(Path(tmp) / "a", img, png.write)
            b = self.out(Path(tmp) / "b", other, png.write)
            self.assertNotEqual(fingerprint.content(a), fingerprint.content(b))

    def test_only_the_build_outputs_count(self):
        img = np.zeros((6, 6, 4), np.uint8)
        with tempfile.TemporaryDirectory() as tmp:
            a = self.out(Path(tmp) / "a", img, png.write)
            before = (fingerprint.files(a), fingerprint.content(a))
            (a / ".DS_Store").write_bytes(b"junk")
            (a / "notes.json").write_text("{}")
            self.assertEqual((fingerprint.files(a), fingerprint.content(a)), before)
            self.assertEqual([f.name for f in fingerprint.outputs(a)],
                             ["atlas-0.json", "atlas-0.png"])


if __name__ == "__main__":
    unittest.main()
