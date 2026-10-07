"""P-1 with bridges on one level and R-37 (`reach.py`; ADR-0008 rules 1, 5, 6): `python3 reach.py`."""
import unittest

from reach import Refused, assert_content, connected, neighbours, p1, plane

W, H = 12, 12


def editor_bridge(deck):
    """CLI-09e's bridge: one deck tile, the southern end South-West of it, the northern end
    North-West of it (`x` grows West, `y` North: SPK-16's neighbours, indices 3 and 5)."""
    n = neighbours(*deck)
    return {"deck": {deck}, "ends": (n[3], n[5])}


def river(rows):
    """A `W × H` map with water (walls) on the rows `rows`."""
    return {(x, y) for y in range(H) for x in range(W) if y not in rows}


class Reach(unittest.TestCase):
    def test_editor_bridge_geometry(self):
        # Both ends in one column (CLI-09e)
        self.assertEqual(editor_bridge((6, 6))["ends"], ((6, 5), (6, 7)))

    def test_only_crossing(self):
        # Row 6 is a river; the bridge is the only crossing
        painted = river({6})
        b = editor_bridge((6, 6))
        # The deck left as water (SPK-16's converter today): the far bank is unreachable
        with self.assertRaises(Refused) as e:
            p1(plane(painted, []), (0, 0))
        self.assertEqual(e.exception.code, "pipeline: unreachable tile")
        # The deck written walkable (D-227): every tile reachable, the deck included
        walk = plane(painted, [b])
        self.assertIn((6, 6), walk)
        p1(walk, (0, 0))

    def test_two_tile_deck_over_a_wide_river(self):
        painted = river({5, 6})
        b = {"deck": {(6, 5), (6, 6)}, "ends": ((6, 4), (6, 7))}
        p1(plane(painted, [b]), (0, 0))

    def test_end_cut_off(self):
        # The northern end (6, 7) has no floor beside it but the deck: its other neighbours are
        # walls, so the far bank is unreachable although the deck and the end are reached
        b = editor_bridge((6, 6))
        north = b["ends"][1]
        painted = river({6}) - (set(neighbours(*north)) - {(6, 6)})
        walk = plane(painted, [b])
        self.assertEqual([n for n in neighbours(*north) if n in walk], [(6, 6)])
        with self.assertRaises(Refused) as e:
            p1(walk, (0, 0))
        self.assertEqual(e.exception.code, "pipeline: unreachable tile")
        # The deck and the end are reached; the far bank is not
        reached = connected(walk, (0, 0))
        self.assertIn((6, 6), reached)
        self.assertIn(north, reached)
        self.assertNotIn((0, 11), reached)

    def test_deck_outside_the_zone(self):
        b = editor_bridge((6, 6))
        zone = {t for t in river(set())} - {(6, 6)}
        with self.assertRaises(Refused) as e:
            plane(river({6}), [b], zone=zone)
        self.assertEqual(e.exception.code, "export: deck outside the zone")

    def test_deck_blocked(self):
        b = editor_bridge((6, 6))
        with self.assertRaises(Refused) as e:
            plane(river({6}), [b], blocked={(6, 6)})
        self.assertEqual(e.exception.code, "export: deck blocked")

    def test_content_off_the_bridge(self):
        b = editor_bridge((6, 6))
        assert_content([b], [(0, 0), (6, 4)])
        for tile in [(6, 6), (6, 5), (6, 7)]:
            with self.assertRaises(Refused) as e:
                assert_content([b], [tile])
            self.assertEqual(e.exception.code, "bridge: tile taken")


if __name__ == "__main__":
    unittest.main()
