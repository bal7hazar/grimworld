"""Tests of tools/art (ART-02): Python selection, scaling, the order check, the PNG writer.

Run: tools/art/.venv/bin/python -m unittest discover -s tools/art/tests
(the Python-selection tests need only the standard library; the others need the venv's NumPy
and Pillow, and are skipped without them).
"""

import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import build  # noqa: E402

try:
    import numpy as np
    from PIL import Image

    from artpipe import png, scale
except ImportError:                                         # outside the venv
    np = None


class PythonSelection(unittest.TestCase):
    def test_current_python_when_3_12_or_newer(self):
        self.assertIsNone(build.select_python((3, 12, 0), lambda name: None))
        self.assertIsNone(build.select_python((3, 13, 1), lambda name: None))

    def test_reexecutes_under_python3_12_when_on_path(self):
        asked = []
        found = build.select_python((3, 11, 6), lambda name: asked.append(name) or "/x/python3.12")
        self.assertEqual(found, "/x/python3.12")
        self.assertEqual(asked, ["python3.12"])

    def test_refuses_naming_3_12_when_none_reachable(self):
        with self.assertRaises(SystemExit) as e:
            build.select_python((3, 11, 6), lambda name: None)
        self.assertIn("3.12", str(e.exception))
        self.assertIn("python3.12", str(e.exception))

    def test_refusal_comes_before_any_venv(self):
        with tempfile.TemporaryDirectory() as tmp:
            venv = Path(tmp) / ".venv"
            saved = build.VENV
            build.VENV = venv
            try:
                with self.assertRaises(SystemExit):
                    build.bootstrap((3, 11, 6), lambda name: None)
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


@unittest.skipIf(np is None, "needs the venv (NumPy, Pillow)")
class Scale(unittest.TestCase):
    def body(self, h=40, w=12):
        cell = np.zeros((h + 20, w + 20, 4), np.uint8)
        cell[10:10 + h, 10:10 + w] = (200, 30, 30, 255)
        return cell

    def test_weights_cover_each_output_pixel_once(self):
        for size, anchor, p, q in ((50, 30, 78, 147), (50, 30, 94, 67), (9, 9, 3, 2)):
            w, a_out, out = scale.axis_weights(size, anchor, p, q)
            self.assertTrue((w.sum(axis=0) == p).all())          # every source pixel spread whole
            inner = w.sum(axis=1)[:-1]
            self.assertTrue((inner[1:] == q).all())              # every inner output pixel full
            self.assertEqual(a_out, -(-anchor * p // q))

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

    def test_area_adds_no_alpha_level_and_snap_no_colour(self):
        cell = self.body()
        cell[30:50, 10:22, 3] = 80                               # a translucent part
        out, _, _ = scale.resample(cell, 16, 50, 94, 67, "area", [0, 80, 255])
        self.assertLessEqual(set(np.unique(out[..., 3]).tolist()), {0, 80, 255})
        pal = scale.palette([cell], 64)
        snapped = scale.snap(out, pal)
        vis = snapped[..., 3] > 0
        self.assertEqual({tuple(c) for c in snapped[vis][:, :3].tolist()}, {(200, 30, 30)})

    def test_order_check_passes_and_fails(self):
        role = {"runt": "caste", "hob": "caste", "cleric": "profession", "vanguard": "profession"}
        good = {"runt": 78, "hob": 128, "cleric": 94, "vanguard": 94}
        self.assertEqual(scale.check_order(good, ["runt"], "hob", role), [])
        tall_runt = dict(good, runt=100)
        problems = scale.check_order(tall_runt, ["runt"], "hob", role)
        self.assertEqual(len(problems), 1)
        self.assertIn("runt (100 px) is taller than the shortest profession", problems[0])
        short_boss = dict(good, hob=94)
        problems = scale.check_order(short_boss, ["runt"], "hob", role)
        self.assertTrue(any("hob (94 px) is not taller than cleric" in p for p in problems))

    def test_target_height_from_build_or_override(self):
        builds = {"small": 78, "medium": 94}
        self.assertEqual(scale.target_height({"name": "a", "build": "small"}, builds), 78)
        self.assertEqual(scale.target_height({"name": "a", "build": "small", "height": 70},
                                             builds), 70)
        with self.assertRaises(SystemExit):
            scale.target_height({"name": "a", "build": "huge"}, builds)


@unittest.skipIf(np is None, "needs the venv (NumPy, Pillow)")
class Png(unittest.TestCase):
    def test_pixels_read_back(self):
        rng = np.random.default_rng(7)
        img = rng.integers(0, 256, (37, 53, 4), dtype=np.uint8)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.png"
            png.write(path, img)
            back = np.array(Image.open(path).convert("RGBA"))
        self.assertTrue((back == img).all())


if __name__ == "__main__":
    unittest.main()
