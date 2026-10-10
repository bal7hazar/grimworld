"""The converter (ENG-08 AC-3, AC-7): the samples convert, the committed outputs are what it writes,
and it refuses each case of `checks.json` with its code. A registry case is the same mutation as
`tests/test_checks.cairo`'s `test_refuse_<case>`, which snforge runs; `test_cairo_twins` holds that
each one exists there with the same code.

    python3 -m unittest discover -s map-format/tests -p 'test_*.py'
"""
import contextlib
import copy
import io
import json
import os
import re
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FORMAT = os.path.dirname(HERE)
SPIKE = os.path.dirname(FORMAT)
SAMPLES = os.path.join(SPIKE, "samples")
sys.path.insert(0, FORMAT)

import convert  # noqa: E402
import records as R  # noqa: E402
from schema_check import validate  # noqa: E402


def load(name):
    with open(os.path.join(SAMPLES, name), encoding="utf-8") as f:
        return json.load(f)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


TABLE = json.loads(read(os.path.join(FORMAT, "checks.json")))
MANIFEST = load("manifest.json")


def zone():
    """The sample zone's records, before the checks."""
    return convert.build_zone(load("zone.json"), MANIFEST)


def first_wall(record):
    return next(t for t in range(225) if R.has(record["walls"], t))


def first_floor(record):
    return next(t for t in range(225) if not R.has(record["walls"], t))


def gate(z, gid):
    return z["gates"][gid]


# Each registry case: the mutation of `tests/test_checks.cairo`'s test of the same name.
def m_set_outside(z):
    z["chunk_set"] |= 1 << 3


def m_count_above_members(z):
    z["quotas"][0] = (R.COLLECTOR_Q, 1, 6)


def m_count_above_candidates(z):
    z["quotas"][0] = (R.COLLECTOR_Q, 1, 3)


def m_spawn_on_wall(z):
    rec = z["chunks"][1]
    rec["spawns"][0]["tile"] = first_wall(rec)


def m_object_kind(z):
    rec = z["chunks"][0]
    assert rec["objects"][0]["kind"] == R.OBJECTS["landmark"]
    rec["objects"][0]["kind"] = R.OBJECTS["vein"]


def m_empty_with_value(z):
    z["chunks"][0]["tiles"][1] = 5


def m_tile_taken(z):
    rec = z["chunks"][2]
    assert rec["objects"][0]["kind"] == R.OBJECTS["chest"]
    rec["objects"][0]["tile"] = rec["spawns"][0]["tile"]


def m_over_caps(z):
    rec = z["chunks"][2]
    taken = {s["tile"] for s in rec["spawns"]} | {o["tile"] for o in rec["objects"]}
    taken |= {rec["tiles"][i] for i in range(len(z["candidates"])) if R.has(z["candidates"][i], 2)}
    free = [t for t in range(225) if not R.has(rec["walls"], t) and t not in taken]
    rec["objects"] += [{"tile": free[0], "kind": 1, "state": 0, "param": 0},
                       {"tile": free[1], "kind": 1, "state": 0, "param": 0}]


def m_gate_anchor_not_floor(z):
    gate(z, 3)["anchor_tile"] = first_wall(z["chunks"][16])


def m_mask_disagrees(z):
    rec = z["chunks"][2]
    assert R.has(rec["walls"], 14)
    rec["walls"] &= ~(1 << 14)


def m_chunk_not_in_set(z):
    z["chunk_set"] &= ~1


def m_gate_not_indexed(z):
    z["chunks"][16]["gates"] = [0, 0]


def m_entry_not_floor(z):
    z["location"]["entry_tile"] = first_wall(z["chunks"][0])


def m_heart_template(z):
    z["hearts"][2] = (0, 2)


def m_floor_rectangle(z):
    z["location"]["kind"] = R.LOCATION_KINDS["dungeon"]
    z["location"]["target"] = 6


def m_quota_kind(z):
    kind, param, n = z["quotas"][1]
    z["quotas"][1] = (R.EXIT, param, n)


def m_quota_draws(z):
    every = R.rectangle(15, 15)
    z["location"]["width"] = z["location"]["height"] = 15
    z["chunk_set"] = every
    z["quotas"] = [(R.COLLECTOR_Q, 1, 112), (R.VEIN_Q, 0, 112), (R.LANDMARK_Q, 1, 112),
                   (R.HEART, 1, 112), (R.HEART, 1, 112), (R.LANDMARK_Q, 2, 112)]
    z["candidates"] = [every] * 6
    z["hearts"] = {3: (2, 5), 4: (2, 5)}


def m_candidates_outside(z):
    z["candidates"][0] |= 1 << 3


def bridge(z):
    return z["bridges"][15][0]


def m_bridge_deck(z):
    bridge(z)["deck"] = 0


def m_bridge_end(z):
    a, _ = bridge(z)["ends"]
    bridge(z)["ends"] = (a, a)


def m_bridge_floor(z):
    _, e = bridge(z)["ends"]
    bridge(z)["ends"] = (first_wall(z["chunks"][15]), e)


def m_bridge_apart(z):
    _, e = bridge(z)["ends"]
    bridge(z)["ends"] = (first_floor(z["chunks"][15]), e)


def m_bridge_index(z):
    z["chunks"][15]["bridges"] = 0  # index 0 of a chunk holding 0 (Cairo: index 1 of 1)


def m_candidates_rewrite_count(z):
    z["quotas"][0] = (R.COLLECTOR_Q, 1, 2)
    z["candidates"][0] = 1 << 16


def m_candidates_rewrite_tile(z):
    assert R.has(z["candidates"][0], 1)
    z["candidates"][0] &= ~(1 << 1)


def m_pack_rewrite_heart(z):
    z["hearts"][2] = (0, 5)


MUTATIONS = {name[2:]: f for name, f in globals().items() if name.startswith("m_")}


class Registry(unittest.TestCase):
    def test_sample_passes(self):
        z = zone()
        R.check_zone(z)
        convert.pipeline(z)

    def test_each_case_refused_with_its_code(self):
        for case in TABLE["registry"]:
            with self.subTest(case=case["case"]):
                z = zone()
                MUTATIONS[case["case"]](z)
                with self.assertRaises(R.Refused) as caught:
                    R.check_zone(z)
                self.assertEqual(caught.exception.code, case["code"])

    def test_every_case_has_a_mutation(self):
        self.assertEqual(sorted(MUTATIONS), sorted(c["case"] for c in TABLE["registry"]))

    def test_cairo_twins(self):
        """Each registry case is `test_refuse_<case>` in tests/test_checks.cairo, with its code."""
        source = read(os.path.join(SPIKE, "tests", "test_checks.cairo"))
        for case in TABLE["registry"]:
            pattern = (r"#\[should_panic\(expected: '" + re.escape(case["code"]) + r"'\)\]\s*"
                       r"fn test_refuse_" + case["case"] + r"\(\)")
            self.assertRegex(source, pattern, case["case"])

    def test_codes_fit_a_short_string(self):
        for case in TABLE["registry"]:
            self.assertLessEqual(len(case["code"]), 31, case["code"])


def converted(export):
    return convert.convert(export, MANIFEST)


class Pipeline(unittest.TestCase):
    def refused(self, export, code):
        with self.assertRaises(R.Refused) as caught:
            converted(export)
        self.assertEqual(caught.exception.code, code)

    def test_unreachable(self):
        export = load("zone.json")
        plane = convert.Plane(export)
        target = (3, 3)  # chunk 0's interior: walled in by its six neighbours
        walls = set(R.neighbours(*target))
        for span in export["rows"]:
            row = list(span["terrain"])
            for i in range(len(row)):
                if plane.glob(span["x"] + i, span["y"]) in walls:
                    row[i] = "#"
            span["terrain"] = "".join(row)
        self.refused(export, "pipeline: unreachable tile")

    def test_seam(self):
        z = zone()
        # Chunk 1's tile at row 7, column 0, on its seam with chunk 0, made a wall in the records
        rec = z["chunks"][1]
        self.assertFalse(R.has(rec["walls"], 105))
        rec["walls"] |= 1 << 105
        with self.assertRaises(R.Refused) as caught:
            convert.pipeline(z)
        self.assertEqual(caught.exception.code, "pipeline: seam")

    def test_deck_disconnected(self):
        export = load("zone.json")
        b = export["bridges"][0]
        x, y = b["deck"][0]
        b["deck"].append([x, y + 4])
        self.refused(export, "pipeline: deck not connected")


class Export(unittest.TestCase):
    def refused(self, export, code):
        with self.assertRaises(R.Refused) as caught:
            converted(export)
        self.assertEqual(caught.exception.code, code)

    def test_origin_odd(self):
        export = load("zone.json")
        export["origin"]["y"] += 1
        self.refused(export, "export: origin row odd")

    def test_door_off_border(self):
        export = load("zone.json")
        b = export["buildings"][0]
        x, y = b["door"]
        b["footprint"] = [[x + dx, y + dy] for dx in (-1, 0, 1) for dy in (-1, 0, 1)]
        self.refused(export, "export: door not on the border")

    def test_unknown_kind(self):
        export = load("zone.json")
        export["props"][0]["kind"] = "statue"
        self.refused(export, "export: unknown kind")

    def test_two_candidates(self):
        export = load("zone.json")
        c = dict(export["candidates"][0])
        c["x"] += 1
        export["candidates"].append(c)
        self.refused(export, "export: two candidates in a chunk")

    def test_three_gates(self):
        export = load("zone.json")
        g = dict(export["gates"][0])
        export["gates"] += [dict(g, gate="to_floor", x=g["x"] + 2), dict(g, x=g["x"] + 3)]
        self.refused(export, "export: three gates in a chunk")

    def test_bridge_across(self):
        export = load("zone.json")
        export["bridges"][0]["ends"][0] = [export["origin"]["x"] + 20, export["origin"]["y"] + 20]
        self.refused(export, "export: bridge across chunks")

    def test_schema(self):
        export = load("zone.json")
        export["biome"] = "lava"
        self.refused(export, "export: schema")

    def test_format(self):
        export = load("zone.json")
        export["format"] = "grimworld-map"
        self.refused(export, "export: format")

    def test_version(self):
        export = load("zone.json")
        export["version"] = 2
        self.refused(export, "export: version")

    def test_hex_outside_size(self):
        export = load("zone.json")
        export["size"]["width"] = 2
        self.refused(export, "export: hex outside the size")

    def test_row_lengths(self):
        export = load("zone.json")
        export["rows"][0]["outline"] = export["rows"][0]["outline"][:-1]
        self.refused(export, "export: row lengths differ")

    def test_row_lengths_through_main(self):
        # The review's case: a short outline gives a refusal line and exit 1, no IndexError
        export = load("zone.json")
        export["rows"][0] = {"y": export["rows"][0]["y"], "x": export["rows"][0]["x"],
                             "terrain": "...", "outline": "11"}
        with tempfile.TemporaryDirectory() as out:
            path = os.path.join(out, "zone.json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(export, f)
            self.assertEqual(convert.main([path, "--manifest", os.path.join(SAMPLES, "manifest.json"),
                                           "--out", os.path.join(out, "r.json")]), 1)

    def test_field_missing(self):
        export = load("zone.json")
        del export["entry"]
        self.refused(export, "export: field missing")

    def test_unknown_name(self):
        export = load("zone.json")
        export["spawns"][0]["template"] = "dragons"
        self.refused(export, "export: unknown name")

    def test_candidate_of_no_quota(self):
        export = load("zone.json")
        export["candidates"][0]["quota"] = 5
        self.refused(export, "export: candidate of no quota")

    def test_object_outside_set(self):
        # A chest on chunk 17 (cx 2, cy 1), outside the chunk set
        export = load("zone.json")
        export["features"][1]["x"] = export["origin"]["x"] + 33
        export["features"][1]["y"] = export["origin"]["y"] + 20
        self.refused(export, "zone: chunk not in the set")

    def test_set_piece_size(self):
        export = load("set_piece.json")
        export["size"]["width"] = 2
        self.refused(export, "export: set piece size")

    def test_set_piece_corner(self):
        export = load("set_piece.json")
        export["rows"][0]["terrain"] = "." + export["rows"][0]["terrain"][1:]
        self.refused(export, "set piece: corner not wall")

    def test_set_piece_tile(self):
        export = load("set_piece.json")
        export["spawns"][0]["x"], export["spawns"][0]["y"] = 5, 5  # a wall of the arena
        self.refused(export, "set piece: tile not floor")

    def test_set_piece_caps(self):
        export = load("set_piece.json")
        export["features"] += [{"feature": "chest", "param": None, "x": 3, "y": 3},
                               {"feature": "chest", "param": None, "x": 4, "y": 3}]
        self.refused(export, "set piece: over its caps")

    def test_malformed(self):
        """A failure no check names (here forced inside the zone's build) is still one refusal line
        and exit 1, never a traceback."""
        original = convert.build_zone

        def broken(*_):
            raise IndexError("forced")

        out = io.StringIO()
        convert.build_zone = broken
        try:
            with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(out):
                code = convert.main([os.path.join(SAMPLES, "zone.json"), "--manifest",
                                     os.path.join(SAMPLES, "manifest.json"), "--out",
                                     os.path.join(tmp, "r.json")])
        finally:
            convert.build_zone = original
        self.assertEqual(code, 1)
        self.assertTrue(out.getvalue().startswith("refused: export: malformed"), out.getvalue())

    def test_every_export_case_tested(self):
        names = {n[len("test_"):] for n in dir(self) if n.startswith("test_")}
        for case in TABLE["export"]:
            self.assertIn(case["case"], names)

class Samples(unittest.TestCase):
    def test_samples_match_the_schema(self):
        schema = json.loads(read(os.path.join(FORMAT, "schema.json")))
        for name in ("zone.json", "town.json", "set_piece.json"):
            validate(load(name), schema)

    def test_committed_outputs_are_the_converters(self):
        with tempfile.TemporaryDirectory() as out:
            for name, extra in (("zone", True), ("town", False), ("set_piece", False)):
                args = [os.path.join(SAMPLES, f"{name}.json"), "--manifest",
                        os.path.join(SAMPLES, "manifest.json"), "--out",
                        os.path.join(out, f"{name}.records.json")]
                if extra:
                    args += ["--golden", os.path.join(out, "zone.golden.json"),
                             "--seed", os.path.join(out, "zone.seed.json")]
                self.assertEqual(convert.main(args), 0)
            for name in ("zone.records.json", "town.records.json", "set_piece.records.json",
                         "zone.golden.json", "zone.seed.json"):
                with open(os.path.join(out, name), encoding="utf-8") as f:
                    self.assertEqual(json.load(f), load(name), name)

    def test_footprint_unwalkable_but_its_door(self):
        export = load("zone.json")
        z = convert.build_zone(export, MANIFEST)
        plane = z["plane"]
        hut = export["buildings"][0]
        door = plane.glob(*hut["door"])
        self.assertIn(door, z["walk"], "the door walkable")
        for h in hut["footprint"]:
            g = plane.glob(*h)
            if g != door:
                self.assertNotIn(g, z["walk"], f"footprint hex {g} unwalkable")
                self.assertTrue(plane.cells[g]["walk"], "painted floor under it")

    def test_blocking_prop_unwalkable(self):
        export = load("zone.json")
        z = convert.build_zone(export, MANIFEST)
        plane = z["plane"]
        tree, bush = export["props"]
        self.assertTrue(json.loads(read(os.path.join(FORMAT, "kinds.json")))["props"]["tree"]["blocks"])
        self.assertNotIn(plane.glob(tree["x"], tree["y"]), z["walk"], "a tree blocks")
        self.assertTrue(plane.cells[plane.glob(tree["x"], tree["y"])]["walk"], "on painted floor")
        self.assertIn(plane.glob(bush["x"], bush["y"]), z["walk"], "a bush does not")

    def test_town_writes_only_its_location(self):
        writes, z = converted(load("town.json"))
        self.assertIsNone(z)
        self.assertEqual([w[0] for w in writes], [R.LOCATION])
        self.assertEqual((writes[0][2][0] >> 56) & 0xffff, 0, "no map: 0 x 0")

    def test_set_piece_keeps_d134(self):
        writes, _ = converted(load("set_piece.json"))
        self.assertEqual([w[0] for w in writes], [R.SET_PIECE])
        export = load("set_piece.json")
        export["rows"][0]["terrain"] = "." + export["rows"][0]["terrain"][1:]
        with self.assertRaises(R.Refused) as caught:
            converted(export)
        self.assertEqual(caught.exception.code, "set piece: corner not wall")

    def test_zone_record_order(self):
        writes, _ = converted(load("zone.json"))
        kinds = [w[0] for w in writes]
        self.assertEqual(kinds[:2], [R.LOCATION, R.OUTLINE])
        self.assertLess(kinds.index(R.QUOTAS), kinds.index(R.ZONE_CHUNK))
        self.assertLess(kinds.index(R.CANDIDATES), kinds.index(R.QUOTAS))
        self.assertEqual(kinds[-2:], [R.GATE, R.GATE])

    def test_marker_and_layout(self):
        writes, z = converted(load("zone.json"))
        loc = writes[0][2][0]
        self.assertEqual((loc >> 144) & 0xff, R.AUTHORED)
        for kind, rid, felts, _ in writes:
            for part in felts:
                self.assertTrue(R.has(part, 250), "LIVE in every part")
                self.assertLess(part, 1 << 251)
            if kind == R.ZONE_CHUNK:
                self.assertEqual(R.unpack_zone_chunk(felts)["walls"], z["chunks"][rid % 256]["walls"])

    def test_copy_does_not_alias_the_sample(self):
        a, b = zone(), zone()
        a["chunks"][0]["walls"] = 0
        self.assertNotEqual(b["chunks"][0]["walls"], 0)
        self.assertIsNot(copy.deepcopy(a), a)


if __name__ == "__main__":
    unittest.main()
