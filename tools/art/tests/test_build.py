"""Tests of tools/art (ART-02): command line, Python selection, the venv, scaling, the order check,
the PNG writer, the fingerprints, the order rule.

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

    from artpipe import atlas, clean, fingerprint, png, scale
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
        build.Redacted(sink).write("Enemy Pack/" + build.WORD.title() + "/x.png\n")
        self.assertNotIn(build.WORD, sink.getvalue().lower())
        self.assertIn("<redacted>", sink.getvalue())


class PythonSelection(unittest.TestCase):
    def test_current_python_when_3_12_or_3_13(self):
        self.assertEqual(build.PYTHONS, ((3, 12), (3, 13)))
        self.assertIsNone(build.select_python((3, 12, 0), lambda n: None, env={}))
        self.assertIsNone(build.select_python((3, 13, 1), lambda n: None, env={}))

    def test_refuses_python_3_14_naming_the_hashed_versions(self):
        with self.assertRaises(SystemExit) as e:
            build.select_python((3, 14, 0), lambda n: "/x/python3.12", probe=lambda p: (3, 12),
                                env={})
        self.assertEqual(str(e.exception),
                         "tools/art/build.py runs under Python 3.12 or 3.13 (the versions whose "
                         "wheels requirements.txt pins by hash), found 3.14: run it with Python "
                         "3.12 or 3.13.")

    def test_python_3_14_refused_before_any_venv(self):
        with tempfile.TemporaryDirectory() as tmp:
            venv = Path(tmp) / ".venv"
            saved, build.VENV = build.VENV, venv
            try:
                with self.assertRaises(SystemExit):
                    build.bootstrap((3, 14, 0), lambda n: None, run=lambda *a, **k: self.fail(),
                                    execv=lambda *a: self.fail(), env={})
            finally:
                build.VENV = saved
            self.assertFalse(venv.exists())

    def test_own_info_and_probe_share_one_check(self):
        self.assertTrue(build.PROBE.startswith(build.INFO))
        info = build.own_info({"numpy": "x"})
        self.assertEqual(info["python"], list(sys.version_info[:2]))
        self.assertEqual(set(info["dists"]), {"numpy"})

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
            self.pip = cmd
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
            self.assertEqual(fake.pip[1:], ["-m", "pip", "install", "--quiet", "--require-hashes",
                                            "-r", str(build.HERE / "requirements.txt")])

    def test_venv_of_python_3_14_is_rebuilt(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeVenv(Path(tmp) / ".venv", python=(3, 14), dists=PINS)
            self.assertEqual(build.venv_problem(fake.venv, PINS, fake),
                             "its interpreter is Python 3.14, not 3.12 or 3.13")
            self.boot(fake)
            self.assertEqual((fake.created, fake.installed), (1, 1))

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

    def direct(self, venv, dists):
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
            ("runt", "caste"), ("skirmisher", "caste"), ("slinger", "caste"),
            ("hob", "caste"), ("cleric", "profession"))]
        heights = dict({s["name"]: "native" for s in sprites}, **height)
        return {"sprite": sprites, "height": heights, "settings": {"resample": "area"},
                "order": {"basic": ["runt", "skirmisher", "slinger"], "tallest": "hob"}}

    def test_validate_manifest(self):
        methods = build.METHODS
        self.assertEqual(scale.validate_manifest(self.manifest(), methods), [])
        self.assertEqual(scale.validate_manifest(self.manifest(runt=67), methods), [])
        m = self.manifest(slinger="big", ghost=70)
        del m["height"]["cleric"]
        m["settings"]["resample"] = "lanczos"
        self.assertEqual(scale.validate_manifest(m, methods), [
            "[height] names 'ghost', which is not a sprite of the manifest",
            'cleric: no line in [height] ("native" or a height in px)',
            "[height] slinger = 'big': must be \"native\" or a positive height in px",
            "settings.resample = 'lanczos', not one of area, area-blend, nearest"])
        self.assertEqual(scale.validate_manifest(self.manifest(runt=0), methods),
                         ["[height] runt = 0: must be \"native\" or a positive height in px"])

    GOOD = {"runt": 67, "skirmisher": 67, "slinger": 66, "hob": 119, "cleric": 67}

    def order(self, heights, **spec):
        m = self.manifest(**spec)
        role = {sp["name"]: sp["role"] for sp in m["sprite"]}
        return scale.check_order(heights, m["order"], role, m["height"])

    def test_order_rule_holds(self):
        self.assertEqual(self.order(self.GOOD), ([], []))

    def test_order_rule_on_native_drawings_is_a_warning(self):
        # the pack's own Spear Goblin (70) is taller than its Monk (67), and a Thief taller still
        errors, warnings = self.order(dict(self.GOOD, skirmisher=70, runt=73))
        self.assertEqual(errors, [])
        self.assertEqual(warnings, ["runt (73 px) is taller than the shortest profession, "
                                    "cleric (67 px)",
                                    "skirmisher (70 px) is taller than the shortest profession, "
                                    "cleric (67 px)"])
        errors, warnings = self.order(dict(self.GOOD, hob=67))        # a native boss, not the tallest
        self.assertEqual(errors, [])
        self.assertEqual(len(warnings), 3)                        # runt, skirmisher, cleric
        self.assertIn("hob (67 px) is not taller than runt (67 px)", warnings)

    def test_order_rule_on_a_resampled_sprite_is_an_error(self):
        errors, warnings = self.order(dict(self.GOOD, slinger=80), slinger=80)
        self.assertEqual(errors, ["slinger (80 px) is taller than the shortest profession, "
                                  "cleric (67 px)"])
        self.assertEqual(warnings, [])
        errors, warnings = self.order(dict(self.GOOD, hob=60), hob=60)     # a resampled boss
        self.assertEqual(len(errors), 4)                          # not taller than any of the four
        self.assertEqual(warnings, [])
        # a native goblin against a resampled profession: the resampled sprite makes it an error
        errors, warnings = self.order(dict(self.GOOD, runt=70, cleric=60), cleric=60)
        self.assertEqual(errors, ["runt (70 px) is taller than the shortest profession, "
                                  "cleric (60 px)", "skirmisher (67 px) is taller than the "
                                  "shortest profession, cleric (60 px)", "slinger (66 px) is "
                                  "taller than the shortest profession, cleric (60 px)"])

    def test_order_rule_needs_a_sound_manifest(self):
        errors, warnings = scale.check_order(self.GOOD, {"basic": ["grunt"], "tallest": "boss"},
                                             {"runt": "caste", "hob": "caste"}, {})
        self.assertEqual(warnings, [])
        self.assertEqual(len(errors), 3)                          # grunt, boss, no profession

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
        def entry(role, spec, target, height, idle):
            return {"role": role,
                    "scale": {"target": target, "height": height, "idle": idle, "spec": spec}}
        order = {"basic": ["runt"], "tallest": "hob"}
        sprites = {"runt": entry("caste", 67, 67, 67, [66, 67]),
                   "hob": entry("caste", 119, 119, 119, [110, 119]),
                   "cleric": entry("profession", "native", 67, 67, [66, 68])}
        specs = {n: r["scale"]["spec"] for n, r in sprites.items()}
        warnings = build.check_scale(sprites, order, specs)
        self.assertEqual(len(warnings), 1)
        self.assertIn("hob: idle frames span 9 px", warnings[0])
        sprites["runt"]["scale"]["height"] = 72
        with self.assertRaises(SystemExit) as e:
            build.check_scale(sprites, order, specs)
        self.assertIn("runt: 72 px tall", str(e.exception))

    def test_check_scale_native_order_failure_only_warns(self):
        def entry(role, height):
            return {"role": role, "scale": {"target": height, "height": height,
                                            "idle": [height, height], "spec": "native"}}
        order = {"basic": ["runt"], "tallest": "hob"}
        sprites = {"runt": entry("caste", 73), "hob": entry("caste", 209),
                   "cleric": entry("profession", 67)}
        specs = dict.fromkeys(sprites, "native")
        warnings = build.check_scale(sprites, order, specs)
        self.assertEqual(len(warnings), 1)
        self.assertIn("runt (73 px) is taller than the shortest profession", warnings[0])


class RealManifest(unittest.TestCase):
    """The committed manifest.toml itself (stdlib only): the owner's mapping of 2026-09-29."""

    MAPPING = {                 # sprite: (root in the pack, animations it must hold)
        "runt": ("Enemy Pack/Thief", {"idle", "move", "attack"}),
        "skirmisher": ("Enemy Pack/Spear Goblin", {"idle", "move", "attack"}),
        "slinger": ("Enemy Pack/Torch Goblin", {"idle", "move", "attack"}),
        "shaman": ("Enemy Pack/Hex Shaman",
                   {"idle", "move", "attack", "projectile", "explosion"}),
        "hobgoblin": ("Enemy Pack/Troll", {"idle", "move", "attack", "windup", "recover"}),
        "vanguard": ("Units/Blue Units/Warrior", {"idle", "move", "attack", "attack2", "guard"}),
        "warden": ("Units/Blue Units/Archer", {"idle", "move", "attack"}),
        "cleric": ("Units/Blue Units/Monk", {"idle", "move", "heal"}),
    }

    @classmethod
    def setUpClass(cls):
        import tomllib
        cls.manifest = tomllib.loads((HERE / "manifest.toml").read_text())

    def test_exactly_the_eight_sprites_of_the_mapping(self):
        sprites = {sp["name"]: sp for sp in self.manifest["sprite"]}
        self.assertEqual(len(sprites), len(self.manifest["sprite"]))          # no duplicate
        self.assertEqual(set(sprites), set(self.MAPPING))
        for name, (root, anims) in self.MAPPING.items():
            self.assertEqual(sprites[name]["root"], root, name)
            self.assertEqual({a["name"] for a in sprites[name]["anim"]}, anims, name)

    def test_every_sprite_is_a_native_strip_and_none_is_generated(self):
        self.assertEqual(self.manifest["height"], dict.fromkeys(self.MAPPING, "native"))
        for sp in self.manifest["sprite"]:
            self.assertNotIn("kind", sp)                     # there is one kind of source: strips
            for a in sp["anim"]:
                self.assertTrue(a["file"].endswith(".png"), (sp["name"], a["name"]))
                self.assertNotIn("row", a)                   # no sheet rows
            self.assertNotIn("file", sp)                     # no sheet file of a sprite
        self.assertFalse({"key_tolerance", "fringe_radius", "min_alpha", "min_component"}
                         & set(self.manifest["settings"]))      # no keying settings left

    def test_the_troll_telegraph_does_not_loop(self):
        troll = next(sp for sp in self.manifest["sprite"] if sp["name"] == "hobgoblin")
        anims = {a["name"]: a for a in troll["anim"]}
        for name in ("windup", "recover", "attack"):
            self.assertFalse(anims[name]["loop"], name)
        self.assertEqual(anims["windup"]["file"], "Troll_Windup.png")
        self.assertEqual(anims["recover"]["file"], "Troll_Recovery.png")

    @unittest.skipIf(np is None, "needs the venv (NumPy)")
    def test_the_manifest_is_sound(self):
        self.assertEqual(scale.validate_manifest(self.manifest, build.METHODS), [])

    def test_the_town_buildings_are_blue_stills(self):
        stills = {st["name"]: st for st in self.manifest["still"]}
        blue = {n for n, st in stills.items() if st["file"].startswith("Buildings/Blue Buildings/")}
        self.assertEqual(blue, {"castle", "barracks", "archery", "monastery", "tower",
                                "house1", "house2", "house3"})
        for name, st in stills.items():
            folder = st["file"].split("/")[0]
            self.assertEqual(st["role"], "building" if folder == "Buildings" else "prop", name)
            if st["file"].startswith("Buildings/") and name not in blue:
                self.assertTrue(st["file"].startswith("Buildings/Others/"), name)
        self.assertEqual(build.still_problems(self.manifest), [])

    def test_the_props_and_the_ground_tiles(self):
        """CLI-03e: props are cut at one frame from their strips; the ground is the 3 x 3 grass
        autotile of one colour and the water."""
        props = {st["name"]: st for st in self.manifest["still"] if st["role"] == "prop"}
        self.assertTrue(props)
        for name, st in props.items():
            self.assertTrue(st["file"].startswith("Terrain/"), name)
            if "cell" in st:
                self.assertEqual(st["frame"], 0, name)       # one frame: no idle animation in a hub
        tilesets = {ts["name"]: ts for ts in self.manifest["tileset"]}
        self.assertEqual(set(tilesets["grass"]["cells"]),
                         {"nw", "n", "ne", "w", "c", "e", "sw", "s", "se"})
        self.assertEqual(set(tilesets["water"]["cells"]), {"c"})
        self.assertEqual(build.tileset_problems(self.manifest), [])

    def test_the_foam_tile(self):
        """CLI-03g2: the foam is one 192 x 192 cell, the first still of the pack's strip."""
        foam = {ts["name"]: ts for ts in self.manifest["tileset"]}["foam"]
        self.assertEqual((foam["file"], foam["cell"], foam["cells"]),
                         ("Terrain/Tileset/Water Foam.png", 192, {"c": [0, 0]}))


@unittest.skipIf(np is None, "needs the venv (NumPy, Pillow)")
class Stills(unittest.TestCase):
    """A still building (CLI-03c), on synthetic images: no image of the pack."""

    def house(self, path):
        """A 40 x 30 house on a 64 x 48 transparent canvas, a 1 px flag pole under its left wall
        (thinner than the feet rule's 8 %), its walls' last row at y = 39."""
        img = np.zeros((48, 64, 4), np.uint8)
        img[10:40, 12:52] = (90, 120, 200, 255)
        img[40:44, 14:15] = (20, 20, 20, 255)                    # a thin pole below the walls
        Image.fromarray(img, "RGBA").save(path)

    def test_a_still_is_anchored_at_its_base_and_centre(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "House.png"
            self.house(path)
            pose = clean.still(path)
        self.assertEqual(pose.rgba.shape[:2], (34, 40))          # tight crop, pole included
        self.assertEqual(pose.baseline, 30)                      # under the walls, not the pole
        self.assertEqual(pose.feet_x, 20)                        # the horizontal centre

    def test_a_still_packs_as_one_frame_at_native_size(self):
        from artpipe import atlas
        s = {"atlas_max": 2048, "atlas_padding": 2, "cell_margin": 4}
        st = {"name": "house1", "role": "building", "file": "House.png", "origin": "synthetic"}
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "out"
            out.mkdir()
            self.house(Path(tmp) / "House.png")
            sprite = build.still_sprite(st, Path(tmp) / "House.png", s["cell_margin"])
            self.assertEqual((sprite["cell_w"], sprite["cell_h"], sprite["baseline"]),
                             (48, 42, 34))                       # 40 + 2 x 4, 34 + 2 x 4; 4 + 30
            index = atlas.pack([sprite], s, out)
            page = json.loads((out / "atlas-0.json").read_text())
            saved, build.OUT = build.OUT, out
            try:
                build.verify([page], index, [sprite], s)         # baseline read back from the PNG
            finally:
                build.OUT = saved
            back = np.array(Image.open(out / "atlas-0.png").convert("RGBA"))
        entry = index["sprites"]["house1"]
        self.assertEqual(entry["role"], "building")
        self.assertEqual(entry["animations"], {"still": {"frames": 1, "fps": 1, "loop": False}})
        self.assertEqual(page["animations"], {"house1/still": ["house1/still/00"]})
        frame = page["frames"]["house1/still/00"]
        self.assertEqual(frame["anchor"], {"x": 0.5, "y": round(34 / 42, 6)})
        self.assertEqual((frame["frame"]["w"], frame["frame"]["h"]), (40, 34))   # native, trimmed
        f = frame["frame"]
        self.assertTrue((back[f["y"]:f["y"] + 30, f["x"]:f["x"] + 40, 3] == 255).all())

    def test_still_problems(self):
        manifest = {"sprite": [{"name": "runt"}], "still": [
            {"name": "runt", "role": "building", "file": "a.png", "origin": "x"},
            {"name": "tower", "role": "caste", "file": "b.png", "origin": "x"},
            {"name": "tower", "role": "building", "file": "c.gif"},
        ]}
        self.assertEqual(build.still_problems(manifest), [
            "[[still]] 'runt': the name is used twice",
            "[[still]] tower: role 'caste', not one of 'building', 'prop'",
            "[[still]] 'tower': the name is used twice",
            "[[still]] tower: file 'c.gif' is not a PNG",
            "[[still]] tower: no origin"])
        self.assertEqual(build.still_problems({"sprite": []}), [])
        cut = {"sprite": [], "still": [
            {"name": "tree", "role": "prop", "file": "t.png", "origin": "x", "frame": 0,
             "cell": [192, 256]},
            {"name": "bush", "role": "prop", "file": "b.png", "origin": "x", "frame": -1,
             "cell": [128]}]}
        self.assertEqual(build.still_problems(cut), [
            "[[still]] bush: frame -1 is not an index",
            "[[still]] bush: cell [128] is not [width, height]"])

    def strip(self, path):
        """A strip of three 20 x 30 cells (not square): in cell i a block 10 wide and 12 + i tall,
        standing on row 26."""
        img = np.zeros((30, 60, 4), np.uint8)
        for i in range(3):
            img[26 - 12 - i:26, 20 * i + 4:20 * i + 14] = (40 * i + 40, 200, 90, 255)
        Image.fromarray(img, "RGBA").save(path)

    def test_a_prop_from_one_cell_of_a_strip(self):
        """CLI-03e: `frame` and a non-square `cell` cut one cell; it is anchored at its base."""
        s = {"atlas_max": 2048, "atlas_padding": 2, "cell_margin": 4}
        st = {"name": "tree", "role": "prop", "file": "Tree.png", "origin": "synthetic",
              "frame": 1, "cell": [20, 30]}
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "out"
            out.mkdir()
            self.strip(Path(tmp) / "Tree.png")
            pose = clean.still(Path(tmp) / "Tree.png", 1, (20, 30))
            self.assertEqual((pose.rgba.shape[:2], pose.baseline), ((13, 10), 13))
            self.assertEqual(int(pose.rgba[0, 0, 0]), 80)       # cell 1's colour, not cell 0's
            with self.assertRaises(SystemExit):
                clean.still(Path(tmp) / "Tree.png", 3, (20, 30))      # three cells only
            with self.assertRaises(SystemExit):
                clean.still(Path(tmp) / "Tree.png", 0, (25, 30))      # not a strip of 25 px cells
            sprite = build.still_sprite(st, Path(tmp) / "Tree.png", s["cell_margin"])
            index = atlas.pack([sprite], s, out)
            page = json.loads((out / "atlas-0.json").read_text())
            saved, build.OUT = build.OUT, out
            try:
                build.verify([page], index, [sprite], s)         # the baseline read back
            finally:
                build.OUT = saved
        self.assertEqual(index["sprites"]["tree"]["role"], "prop")
        self.assertEqual(index["sprites"]["tree"]["baseline"], 4 + 13)
        frame = page["frames"]["tree/still/00"]
        self.assertEqual((frame["frame"]["w"], frame["frame"]["h"]), (10, 13))


@unittest.skipIf(np is None, "needs the venv (NumPy, Pillow)")
class Tiles(unittest.TestCase):
    """A tileset's cells (CLI-03e), on a synthetic sheet: no image of the pack."""

    S = {"atlas_max": 2048, "atlas_padding": 2, "cell_margin": 4}

    def sheet(self, path):
        """Two 64 px cells side by side: (0, 0) half transparent (an edge), (1, 0) a gradient."""
        img = np.zeros((64, 128, 4), np.uint8)
        img[:, 32:64] = (10, 160, 60, 255)
        img[:, 64:] = (200, 100, 0, 255)
        img[:, 64:, 0] = np.arange(64, dtype=np.uint8)[None, :] * 2
        Image.fromarray(img, "RGBA").save(path)

    def test_tiles_are_untrimmed_anchored_top_left_and_extruded(self):
        ts = {"name": "grass", "role": "tile", "file": "Sheet.png", "origin": "synthetic",
              "cells": {"w": [0, 0], "c": [1, 0]}}
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "out"
            out.mkdir()
            self.sheet(Path(tmp) / "Sheet.png")
            sprites = build.tile_sprites(ts, Path(tmp) / "Sheet.png")
            index = atlas.pack(sprites, self.S, out)
            page = json.loads((out / "atlas-0.json").read_text())
            saved, build.OUT = build.OUT, out
            try:
                build.verify([page], index, sprites, self.S)
            finally:
                build.OUT = saved
            img = np.array(Image.open(out / "atlas-0.png").convert("RGBA"))
        self.assertEqual(set(index["sprites"]), {"grass_w", "grass_c"})
        for name in ("grass_w", "grass_c"):
            entry = index["sprites"][name]
            self.assertEqual((entry["role"], entry["cell"], entry["baseline"]),
                             ("tile", {"w": 64, "h": 64}, 0))
            f = page["frames"][f"{name}/still/00"]
            self.assertEqual((f["frame"]["w"], f["frame"]["h"]), (64, 64))     # untrimmed
            self.assertFalse(f["trimmed"])
            self.assertEqual(f["spriteSourceSize"], {"x": 0, "y": 0, "w": 64, "h": 64})
            self.assertEqual(f["anchor"], {"x": 0, "y": 0})
        # The edge cell keeps its transparent half; the centre cell's edges fill the gutter.
        r = page["frames"]["grass_w/still/00"]["frame"]
        self.assertFalse(img[r["y"]:r["y"] + 64, r["x"]:r["x"] + 32, 3].any())
        r = page["frames"]["grass_c/still/00"]["frame"]
        x, y = r["x"], r["y"]
        cell = img[y:y + 64, x:x + 64]
        self.assertTrue((img[y:y + 64, x - 1] == cell[:, 0]).all())            # left
        self.assertTrue((img[y:y + 64, x + 64] == cell[:, 63]).all())          # right
        self.assertTrue((img[y - 1, x:x + 64] == cell[0]).all())               # top
        self.assertTrue((img[y + 64, x:x + 64] == cell[63]).all())             # bottom
        self.assertTrue((img[y - 1, x - 1] == cell[0, 0]).all())               # a corner
        self.assertFalse(img[y - 2, x:x + 64, 3].any())                        # half the gutter

    def test_tileset_problems(self):
        manifest = {"sprite": [{"name": "runt"}], "still": [{"name": "grass_c"}], "tileset": [
            {"name": "grass", "role": "prop", "file": "a.gif", "cells": {"c": [1, 1]}},
            {"name": "runt", "role": "tile", "file": "b.png", "origin": "x"},
            {"name": "water", "role": "tile", "file": "w.png", "origin": "x",
             "cells": {"c": [0], "d": [0, 0]}},
        ]}
        self.assertEqual(build.tileset_problems(manifest), [
            "[[tileset]] grass: role 'prop', not 'tile'",
            "[[tileset]] grass: file 'a.gif' is not a PNG",
            "[[tileset]] grass: no origin",
            "[[tileset]] grass: 'grass_c', the name is used twice",
            "[[tileset]] runt: no cells",
            "[[tileset]] water: cell c [0] is not [column, row]"])
        self.assertEqual(build.tileset_problems({"sprite": []}), [])

    def test_a_cell_of_another_side(self):
        """CLI-03g2: an entry's `cell` side (the foam's 192): the frame is exactly that cell,
        untrimmed, anchored top-left, its transparent ring kept, its edges extruded."""
        img = np.zeros((192, 384, 4), np.uint8)
        img[40:152, 40:152] = (230, 240, 250, 36)                  # a faint ring's square
        img[80:112, 80:112] = 0                                    # its hole
        img[:, 192:] = (255, 0, 0, 255)                            # the next cell: never cut
        ts = {"name": "foam", "role": "tile", "file": "Foam.png", "origin": "synthetic",
              "cell": 192, "cells": {"c": [0, 0]}}
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "out"
            out.mkdir()
            Image.fromarray(img, "RGBA").save(Path(tmp) / "Foam.png")
            sprites = build.tile_sprites(ts, Path(tmp) / "Foam.png")
            index = atlas.pack(sprites, self.S, out)
            page = json.loads((out / "atlas-0.json").read_text())
            saved, build.OUT = build.OUT, out
            try:
                build.verify([page], index, sprites, self.S)
                # The check holds a tile to its entry's side: a 64 px claim fails on this frame.
                wrong = [dict(sprites[0], cell_w=64, cell_h=64)]
                with self.assertRaises(AssertionError):
                    build.verify([page], index, wrong, self.S)
            finally:
                build.OUT = saved
            packed = np.array(Image.open(out / "atlas-0.png").convert("RGBA"))
        entry = index["sprites"]["foam_c"]
        self.assertEqual((entry["role"], entry["cell"], entry["baseline"]),
                         ("tile", {"w": 192, "h": 192}, 0))
        f = page["frames"]["foam_c/still/00"]
        self.assertEqual((f["frame"]["w"], f["frame"]["h"]), (192, 192))
        self.assertFalse(f["trimmed"])
        self.assertEqual(f["spriteSourceSize"], {"x": 0, "y": 0, "w": 192, "h": 192})
        self.assertEqual(f["anchor"], {"x": 0, "y": 0})
        r = f["frame"]
        self.assertTrue((packed[r["y"]:r["y"] + 192, r["x"]:r["x"] + 192] == img[:, :192]).all())

    def test_a_cell_side_is_checked(self):
        manifest = {"tileset": [
            {"name": "foam", "role": "tile", "file": "f.png", "origin": "x", "cell": 0,
             "cells": {"c": [0, 0]}},
            {"name": "sea", "role": "tile", "file": "s.png", "origin": "x", "cell": "192",
             "cells": {"c": [0, 0]}},
            {"name": "ok", "role": "tile", "file": "o.png", "origin": "x", "cell": 192,
             "cells": {"c": [0, 0]}},
        ]}
        self.assertEqual(build.tileset_problems(manifest), [
            "[[tileset]] foam: cell 0 is not a side in px",
            "[[tileset]] sea: cell '192' is not a side in px"])


@unittest.skipIf(np is None, "needs the venv (NumPy, Pillow)")
class FeetRow(unittest.TestCase):
    def test_the_lowest_wide_row(self):
        alpha = np.zeros((20, 40), np.uint8)
        alpha[2:15, 10:30] = 255                                # a body, 20 wide
        alpha[15:19, 19:21] = 255                               # a thin tip: 2 px, not the feet
        self.assertEqual(build.feet_row(alpha), 15)

    def test_fallback_to_the_last_row_when_no_row_is_wide_enough(self):
        # the Hex Shaman's last explosion frame: 28 x 46, no row of 4 px (8 % of 28, at least 4)
        alpha = np.zeros((46, 28), np.uint8)
        alpha[5:40, 12:14] = 255                                # a 2 px wide spark
        self.assertFalse((alpha.astype(bool).sum(axis=1) >= 4).any())
        self.assertEqual(build.feet_row(alpha), 46)             # the last row, plus one


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


@unittest.skipIf(np is None, "needs the venv's NumPy and Pillow")
class StillsBesideStrips(unittest.TestCase):
    """CLI-03d, note 2 of the CLI-03c review: adding a still to the atlas leaves the strips' frames
    where they were. Synthetic images only (D-73): no byte of the pack, no hash is asserted.

    Pinned: each strip frame's rectangle on its page, its trim offset, and its cell's pixels.
    Not pinned: the page's size and bytes (a still landing on a page can make it taller)."""

    SETTINGS = {"atlas_max": 64, "atlas_padding": 1}

    @staticmethod
    def sprite(name, shades, w, h, role="adventurer"):
        cells = []
        for shade in shades:
            cell = np.zeros((h + 4, w + 4, 4), np.uint8)
            cell[2:2 + h, 2:2 + w] = (shade, 10, 10, 255)
            cells.append(cell)
        return {"name": name, "role": role, "cell_w": w + 4, "cell_h": h + 4, "baseline": h + 2,
                "anims": [{"name": "idle", "fps": 6, "loop": True, "cells": cells}]}

    def packed(self, sprites):
        out = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(out))
        index = atlas.pack(sprites, self.SETTINGS, out)
        pages = []
        for page in index["pages"]:
            data = json.loads((out / page["json"]).read_text())
            pages.append((data, np.array(Image.open(out / page["image"]).convert("RGBA"))))
        return index, pages

    def frames_of(self, index, pages, names):
        """name -> [(frame rectangle, trim offset, cell pixels)] for the given sprites."""
        found = {}
        for name in names:
            data, img = pages[index["sprites"][name]["page"]]
            for key, f in data["frames"].items():
                if key.split("/")[0] != name:
                    continue
                r = f["frame"]
                px = img[r["y"]:r["y"] + r["h"], r["x"]:r["x"] + r["w"]].copy()
                found.setdefault(name, []).append(
                    ((r["x"], r["y"], r["w"], r["h"]),
                     (f["spriteSourceSize"]["x"], f["spriteSourceSize"]["y"]), px.tobytes()))
        return found

    def test_strips_keep_their_frames_with_a_still(self):
        strips = [self.sprite("a", [30, 60, 90], 10, 12), self.sprite("b", [120, 150], 14, 9)]
        still = self.sprite("castle", [200], 20, 30, role="building")
        without = self.packed(strips)
        with_still = self.packed(strips + [still])
        names = ["a", "b"]
        self.assertEqual(self.frames_of(*without, names), self.frames_of(*with_still, names))
        # The still itself is packed, on a page of the same atlas.
        self.assertIn("castle", with_still[0]["sprites"])

    def test_strips_keep_their_frames_with_props_and_tiles(self):
        """CLI-03e: props and untrimmed, extruded tiles leave the strips' frames as they were."""
        strips = [self.sprite("a", [30, 60, 90], 10, 12), self.sprite("b", [120, 150], 14, 9)]
        prop = self.sprite("tree", [210], 12, 20, role="prop")
        tile = {"name": "grass_c", "role": "tile", "cell_w": 16, "cell_h": 16, "baseline": 0,
                "untrimmed": True, "anchor": (0, 0),
                "anims": [{"name": "still", "fps": 1, "loop": False,
                           "cells": [np.full((16, 16, 4), 180, np.uint8)]}]}
        settings, self.SETTINGS = self.SETTINGS, {"atlas_max": 64, "atlas_padding": 2}
        try:
            without = self.packed(strips)
            with_more = self.packed(strips + [prop, tile])
        finally:
            self.SETTINGS = settings
        names = ["a", "b"]
        self.assertEqual(self.frames_of(*without, names), self.frames_of(*with_more, names))
        self.assertEqual(with_more[0]["sprites"]["grass_c"]["role"], "tile")
        self.assertEqual(with_more[0]["sprites"]["tree"]["role"], "prop")

    def test_the_still_is_the_only_thing_the_pages_may_gain(self):
        strips = [self.sprite("a", [30, 60], 10, 12)]
        still = self.sprite("castle", [200], 20, 30, role="building")
        (_, pages) = self.packed(strips)
        (_, pages_with) = self.packed(strips + [still])
        # No assertion on a page's size or bytes: only that every strip frame is still listed.
        self.assertEqual(set(pages[0][0]["frames"]), {
            k for k in pages_with[0][0]["frames"] if not k.startswith("castle/")})


if __name__ == "__main__":
    unittest.main()
