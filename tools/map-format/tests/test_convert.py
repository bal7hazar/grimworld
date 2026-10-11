"""The converter (ENG-08 AC-3, AC-7; ENG-09): the samples convert, the committed outputs are what it
writes, and it refuses each case of `checks.json` with its code. A registry case is refused by the
Registry itself in `contracts/persistent/tests/test_zone.cairo`'s `test_refuse_<case>` (a write of
the sample, or a rewrite, that breaks the same rule), which snforge runs; `test_cairo_twins` holds
that each one exists there with the same code.

    python3 -m unittest discover -s tools/map-format/tests -p 'test_*.py'
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
ROOT = os.path.dirname(os.path.dirname(FORMAT))
SAMPLES = os.path.join(FORMAT, "samples")
TWINS = os.path.join(ROOT, "contracts", "persistent", "tests", "test_zone.cairo")
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


# Each registry case: the mutation the Cairo twin of the same name writes (`TWINS`).
def m_set_outside(z):
    z["chunk_set"] |= 1 << 3


def m_count_above_members(z):
    z["quotas"][0] = (R.COLLECTOR_Q, 1, 6)


def m_count_above_candidates(z):
    z["quotas"][0] = (R.COLLECTOR_Q, 1, 3)


def m_spawn_on_wall(z):
    rec = z["chunks"][1]
    rec["spawns"][0]["tile"] = first_wall(rec)


def m_spawn_on_ring(z):
    rec = z["chunks"][1]
    rec["spawns"][0]["tile"] = next(t for t in range(225) if not R.has(rec["walls"], t)
                                    and (t // 15 in (0, 14) or t % 15 in (0, 14)))


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
    free = [t for t in range(225) if not R.has(rec["walls"], t) and t not in taken
            and 0 < t // 15 < 14 and 0 < t % 15 < 14]
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


def m_level_band(z):
    z["location"]["level_min"], z["location"]["level_max"] = 0, 255


def m_heart_template(z):
    z["hearts"][2] = (0, 2)


def m_floor_rectangle(z):
    z["location"]["kind"] = R.LOCATION_KINDS["dungeon"]
    z["location"]["target"] = 6


def m_floor_few(z):
    z["location"]["kind"] = R.LOCATION_KINDS["dungeon"]
    z["location"]["target"] = 5


def m_gate_entry_outside(z):
    assert gate(z, 3)["destination"] == 3 and gate(z, 3)["entry_chunk"] == 112
    z["destinations"][3] = (7, 7)


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


def m_bridge_deck_floor(z):
    z["chunks"][15]["walls"] |= bridge(z)["deck"]


def m_bridge_tile_taken(z):
    a, _ = bridge(z)["ends"]
    z["chunks"][15]["objects"].append({"tile": a, "kind": R.OBJECTS["chest"], "state": 0,
                                       "param": 0})


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
# The registry cases with a converter twin; the others name why the converter cannot write them
TWINNED = [c for c in TABLE["registry"] if "converter" not in c]


class Registry(unittest.TestCase):
    def test_sample_passes(self):
        z = zone()
        R.check_zone(z)
        convert.pipeline(z)

    def test_each_case_refused_with_its_code(self):
        for case in TWINNED:
            with self.subTest(case=case["case"]):
                z = zone()
                MUTATIONS[case["case"]](z)
                with self.assertRaises(R.Refused) as caught:
                    R.check_zone(z)
                self.assertEqual(caught.exception.code, case["code"])

    def test_every_case_has_a_mutation(self):
        self.assertEqual(sorted(MUTATIONS), sorted(c["case"] for c in TWINNED))

    def test_a_case_without_a_twin_gives_its_reason(self):
        """ENG-R1c-1: the rules on records the converter never writes (a generated zone's, a
        dungeon floor's quotas) are the Registry's alone, each with its reason."""
        alone = [c for c in TABLE["registry"] if "converter" in c]
        self.assertTrue(alone)
        for case in alone:
            self.assertIn("authored zones only", case["converter"], case["case"])

    def test_floor_bounds(self):
        """R-40 and R-28 at their boundaries, the 4 x 3 sweep of `test_set_record_floor_bounds`:
        `N` 1 to 5 refused, 6 to 11 accepted, 12 refused; `N` 0 no floor, whatever the size."""
        R.assert_floor({"target": 0, "width": 0, "height": 0})
        for n in range(1, 13):
            location = {"target": n, "width": 4, "height": 3}
            with self.subTest(n=n):
                if 6 <= n < 12:
                    R.assert_floor(location)
                    continue
                with self.assertRaises(R.Refused) as caught:
                    R.assert_floor(location)
                code = "location: floor under 6 chunks" if n < 6 else "location: floor rectangle"
                self.assertEqual(caught.exception.code, code)

    def test_gate_entry_bounds(self):
        """R-41 at its boundary, as `test_gate_entry_bounds`: into an 8 x 8 floor, chunk 112
        (7, 7) accepted, 113 (8, 7) and 127 (7, 8) refused; no size known, nothing checked."""
        for entry, refused in ((112, False), (113, True), (127, True)):
            with self.subTest(entry=entry):
                if not refused:
                    R.assert_gate_entry(3, {"entry_chunk": entry}, (8, 8))
                    continue
                with self.assertRaises(R.Refused) as caught:
                    R.assert_gate_entry(3, {"entry_chunk": entry}, (8, 8))
                self.assertEqual(caught.exception.code, "gate: entry outside rectangle")
        R.assert_gate_entry(3, {"entry_chunk": 224}, None)

    def test_gate_destinations_from_the_manifest(self):
        """The sample's floor (15 x 15 in the manifest) is a destination with a size; the town, a
        hub, is none, even given one; a manifest without sizes checks nothing."""
        self.assertEqual(zone()["destinations"], {3: (15, 15)})
        manifest = copy.deepcopy(MANIFEST)
        manifest["location_sizes"]["test_town"] = [1, 1]
        self.assertEqual(convert.build_zone(load("zone.json"), manifest)["destinations"],
                         {3: (15, 15)})
        del manifest["location_sizes"]
        z = convert.build_zone(load("zone.json"), manifest)
        self.assertEqual(z["destinations"], {})
        R.check_zone(z)

    def test_cairo_twins(self):
        """Each registry case is `test_refuse_<case>` in the Registry's tests, with its code."""
        source = read(TWINS)
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

    def test_bridge_the_only_crossing(self):
        """D-227 (ADR-0008 rule 6): with the ford painted as water, the bridge is the stream's only
        crossing; its deck is written walkable, so P-1 accepts the map; with the deck left out of
        the plane the far bank would be unreachable."""
        export = load("zone.json")
        plane = convert.Plane(export)
        deck = {plane.glob(*h) for h in export["bridges"][0]["deck"]}
        z = convert.build_zone(export, MANIFEST)
        for g in deck:
            self.assertIn(g, z["walk"], "the deck walkable")
            self.assertFalse(plane.cells[g]["walk"], "painted as water")
        converted(export)

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
        # Both into the dungeon, so that E-5 (a gate elsewhere on the outline) does not apply
        export["gates"] += [dict(g, gate="to_floor", to="floor_1", x=g["x"] + 2),
                            dict(g, to="floor_1", x=g["x"] + 3)]
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

    def test_deck_outside(self):
        export = load("zone.json")
        export["bridges"][0]["deck"] = [[export["origin"]["x"] + 33, export["origin"]["y"] + 20]]
        self.refused(export, "export: deck outside the zone")

    def test_deck_blocked(self):
        export = load("zone.json")
        tree = export["props"][0]
        export["bridges"][0]["deck"] = [[tree["x"], tree["y"]]]
        self.refused(export, "export: deck blocked")

    def test_footprint_outside(self):
        export = load("zone.json")
        b = export["buildings"][0]
        b["footprint"].append([export["origin"]["x"] + 33, export["origin"]["y"] + 20])
        self.refused(export, "export: footprint outside the set")

    def test_footprint_disconnected(self):
        export = load("zone.json")
        b = export["buildings"][0]
        x, y = b["door"]
        b["footprint"].append([x + 4, y + 4])
        self.refused(export, "export: footprint not connected")

    def test_door_not_walkable(self):
        export = load("zone.json")
        plane = convert.Plane(export)
        b = export["buildings"][0]
        door = plane.glob(*b["door"])
        for span in export["rows"]:
            row = list(span["terrain"])
            for i in range(len(row)):
                if plane.glob(span["x"] + i, span["y"]) == door:
                    row[i] = "#"
            span["terrain"] = "".join(row)
        self.refused(export, "export: door not walkable")

    def test_gate_inside(self):
        # The gate to the town moved to the zone's inside (all six neighbours in the zone)
        export = load("zone.json")
        g, inside = export["gates"]
        g["x"], g["y"] = inside["x"], inside["y"]
        self.refused(export, "export: gate not on the outline")

    def test_dungeon_entrance_inside(self):
        # A gate into a dungeon (`floor_1`) may stand inside the chunk set: the sample's does
        export = load("zone.json")
        z = convert.build_zone(export, MANIFEST)
        g = export["gates"][1]
        self.assertEqual(MANIFEST["location_kinds"][g["to"]], "dungeon")
        here = z["plane"].glob(g["x"], g["y"])
        self.assertTrue(all(n in z["zone"] for n in R.neighbours(*here)), "inside")

    # The ids of the manifest, each packed into a fixed field (`convert.ID_BITS`): the largest that
    # fits converts, one more is refused, and so is a negative one, before any record is packed.
    # (table, a name of the sample's export in it): the region, the zone and the gates' locations,
    # the gate, the pack (spawn template, heart), the collector, the landmark, the spawn table.
    SAMPLE_IDS = (("regions", "test_region"), ("locations", "meadow_edge"),
                  ("locations", "floor_1"), ("gates", "to_town"), ("packs", "raiders"),
                  ("collectors", "camp"), ("landmarks", "old_oak"), ("spawn_tables", "meadow"))
    ID_TABLES = ("regions", "locations", "gates", "packs", "collectors", "landmarks", "skills",
                 "spawn_tables", "set_pieces")

    def with_id(self, table, name, value):
        manifest = copy.deepcopy(MANIFEST)
        manifest[table][name] = value
        return manifest

    def refused_id(self, export, manifest, needle):
        with self.assertRaises(R.Refused) as caught:
            convert.convert(export, manifest)
        self.assertEqual(caught.exception.code, "export: id does not fit")
        self.assertIn(needle, caught.exception.detail)

    def test_id_negative(self):
        for table, name in self.SAMPLE_IDS:
            with self.subTest(table=table):
                self.refused_id(load("zone.json"), self.with_id(table, name, -1), f"{name!r}: id -1")
        self.refused_id(load("set_piece.json"), self.with_id("set_pieces", "boss_arena", -1),
                        "'boss_arena': id -1")
        export = load("zone.json")
        export["gates"][0]["quest"] = -1  # the schema refuses it too: the converter's own check
        with self.assertRaises(R.Refused) as caught:
            convert.build_zone(export, MANIFEST)
        self.assertEqual(caught.exception.code, "export: id does not fit")

    def test_id_above_16_bits(self):
        top, over = (1 << 16) - 1, 1 << 16
        for table, name in self.SAMPLE_IDS:
            with self.subTest(table=table):
                convert.convert(load("zone.json"), self.with_id(table, name, top))
                self.refused_id(load("zone.json"), self.with_id(table, name, over),
                                f"{name!r}: id {over} does not fit 16 bits")
        # A set piece's id is a u16 for the game (`Location.set_pieces` is `Lanes16`)
        writes, _ = convert.convert(load("set_piece.json"),
                                    self.with_id("set_pieces", "boss_arena", top))
        self.assertEqual(writes[0][1], top)
        self.refused_id(load("set_piece.json"), self.with_id("set_pieces", "boss_arena", over),
                        f"'boss_arena': id {over} does not fit 16 bits")
        for table in self.ID_TABLES:
            with self.subTest(table=table, at="resolve"):
                self.assertEqual(convert.resolve({table: {"n": top}}, table, "n", "x"), top)
                with self.assertRaises(R.Refused) as caught:
                    convert.resolve({table: {"n": over}}, table, "n", "x")
                self.assertEqual(caught.exception.code, "export: id does not fit")

    def test_id_above_32_bits(self):
        top, over = (1 << 32) - 1, 1 << 32
        # A gate's quest is the u32 of `Gate`: the only field of 32 bits
        export = load("zone.json")
        export["gates"][0]["quest"] = top
        z = convert.build_zone(export, MANIFEST)
        self.assertEqual(max(g["quest"] for g in z["gates"].values()), top)
        export["gates"][0]["quest"] = over
        with self.assertRaises(R.Refused) as caught:
            convert.build_zone(export, MANIFEST)
        self.assertEqual(caught.exception.code, "export: id does not fit")
        self.assertIn("quest", caught.exception.detail)

    def test_id_refused_through_main(self):
        """Exit 1 and one `refused:` line, no output file written."""
        with tempfile.TemporaryDirectory() as tmp:
            manifest, out = os.path.join(tmp, "m.json"), os.path.join(tmp, "r.json")
            with open(manifest, "w", encoding="utf-8") as f:
                json.dump(self.with_id("regions", "test_region", 1 << 16), f)
            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                code = convert.main([os.path.join(SAMPLES, "zone.json"), "--manifest", manifest,
                                     "--out", out])
            self.assertEqual(code, 1)
            self.assertTrue(buffer.getvalue().startswith("refused: export: id does not fit"),
                            buffer.getvalue())
            self.assertFalse(os.path.exists(out))

    def test_location_size(self):
        """E-51: a manifest location's size is two whole numbers from 1 to 15; anything else is
        refused before any record is built, used by a gate of the export or not."""
        for good in ([1, 1], [15, 15], [3, 2]):
            manifest = copy.deepcopy(MANIFEST)
            manifest["location_sizes"]["floor_1"] = good
            self.assertEqual(convert.build_zone(load("zone.json"), manifest)["destinations"],
                             {3: tuple(good)})
        bad = ([0, 15], [15, 0], [16, 15], [15, 16], [-1, 3], [3], [3, 2, 1], [], [3.0, 2],
               [3, 2.5], ["3", 2], [True, 2], [3, False], [None, 2], "15x15", 15, None,
               {"w": 3, "h": 2}, (3, 2)[0])
        for entry in bad:
            for name in ("floor_1", "meadow_edge", "test_town"):
                with self.subTest(entry=entry, name=name):
                    manifest = copy.deepcopy(MANIFEST)
                    manifest["location_sizes"][name] = entry
                    with self.assertRaises(R.Refused) as caught:
                        convert.convert(load("zone.json"), manifest)
                    self.assertEqual(caught.exception.code, "export: location size")
                    self.assertIn(name, caught.exception.detail)
        for table in ([[3, 2]], "x", 5, None):
            manifest = copy.deepcopy(MANIFEST)
            manifest["location_sizes"] = table
            with self.assertRaises(R.Refused) as caught:
                convert.convert(load("zone.json"), manifest)
            self.assertEqual(caught.exception.code, "export: location size")

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
