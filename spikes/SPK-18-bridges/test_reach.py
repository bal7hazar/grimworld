"""P-1 with bridges and R-37 (`reach.py`; ADR-0008 rules 2 and 7): `python3 reach.py`."""
import unittest

from reach import Refused, neighbours, p1, reach

W, H = 12, 12


def step(t, d):
    """The neighbour of `t` in direction `d`, ENG-02's order (East, North-East, North-West, West,
    South-West, South-East), `x` growing West."""
    x, y = t
    n = neighbours(x, y)  # x-1 (East), x+1 (West), two South, two North
    return {0: n[0], 1: n[4], 2: n[5], 3: n[1], 4: n[3], 5: n[2]}[d]


def editor_bridge(deck):
    """CLI-09e's bridge: one deck tile, the southern end South-West of it, the northern end
    North-West of it."""
    return {"deck": {deck}, "ends": (step(deck, 4), step(deck, 2))}


def board(river_x=None, road_y=None):
    """A `W × H` board, a river down column `river_x` (walls), a road across it on row `road_y`."""
    walk = set()
    for y in range(H):
        for x in range(W):
            if x != river_x or y == road_y:
                walk.add((x, y))
    return walk


class Reach(unittest.TestCase):
    def test_direction_helper(self):
        # The editor's bridge: both ends in one column (CLI-09e)
        b = editor_bridge((6, 6))
        self.assertEqual(b["ends"], ((6, 5), (6, 7)))

    def test_river_crossed_only_by_a_bridge(self):
        # The river is two columns wide where the bridge stands: 5 and 6 walls, the deck on (6, 6)
        walk = {t for t in board() if t[0] not in (5, 6)}
        bridge = {"deck": {(5, 6), (6, 6)}, "ends": ((4, 6), (7, 6))}
        # Today's P-1 (no bridge read): the far bank is unreachable
        with self.assertRaises(Refused) as e:
            p1(walk, [], (0, 0))
        self.assertEqual(e.exception.code, "pipeline: unreachable tile")
        # With the bridge: every tile, and both deck tiles aloft
        p1(walk, [bridge], (0, 0))
        nodes = reach(walk, [bridge], (0, 0))
        self.assertIn(((5, 6), 1), nodes)
        self.assertNotIn(((5, 6), 0), nodes)

    def test_editor_bridge_over_a_road(self):
        # Row 6 is wall but the deck's tile, the only gap, passed under (from (5, 5) to (5, 7));
        # the ends sit on rows 5 and 7
        deck = (6, 6)
        b = editor_bridge(deck)
        walk = {t for t in board() if t[1] != 6 or t == deck}
        p1(walk, [b], (0, 0))
        nodes = reach(walk, [b], (0, 0))
        self.assertIn((deck, 0), nodes)  # under
        self.assertIn((deck, 1), nodes)  # on

    def test_editor_bridge_over_a_river(self):
        # The wall row 6 has no gap: the only crossing is the deck
        deck = (6, 6)
        b = editor_bridge(deck)
        walk = {t for t in board() if t[1] != 6}
        with self.assertRaises(Refused):
            p1(walk, [], (0, 0))
        p1(walk, [b], (0, 0))

    def test_the_cut(self):
        # Under the deck, a pocket reached only from the ends is unreachable: the end-to-under edge
        # is the climb's. The deck's ground tile walkable, every other neighbour of it a wall but
        # the two ends
        deck = (6, 6)
        b = editor_bridge(deck)
        others = [n for n in neighbours(*deck) if n not in b["ends"]]
        walk = (board() - set(others)) | {deck}
        walk -= {t for t in board() if t[1] == 6 and t != deck}
        with self.assertRaises(Refused) as e:
            p1(walk, [b], (0, 0))
        self.assertIn("(6, 6), 0", str(e.exception))

    def test_decks_touch(self):
        a = editor_bridge((4, 6))
        b = editor_bridge((5, 6))
        with self.assertRaises(Refused) as e:
            p1(board(), [a, b], (0, 0))
        self.assertEqual(e.exception.code, "export: decks touch")

    def test_end_by_another_deck(self):
        # b's end (4, 5) is next to a's deck (4, 6)
        a = editor_bridge((4, 6))
        b = {"deck": {(5, 4)}, "ends": ((4, 5), (5, 3))}
        with self.assertRaises(Refused) as e:
            p1(board(), [a, b], (0, 0))
        self.assertEqual(e.exception.code, "export: end by another deck")

    def test_end_on_a_deck(self):
        a = {"deck": {(4, 6)}, "ends": ((4, 6), (4, 7))}
        with self.assertRaises(Refused) as e:
            p1(board(), [a], (0, 0))
        self.assertEqual(e.exception.code, "export: bridge end on a deck")


if __name__ == "__main__":
    unittest.main()
