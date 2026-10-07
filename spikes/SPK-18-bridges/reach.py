#!/usr/bin/env python3
"""SPK-18: the converter's reachability (P-1) with bridges on one level (D-227; ADR-0008 rules 1, 5
and 6). A prototype for ENG-09's converter (`tools/map-format/`, SPK-16's `convert.py`), on global
tiles `(x, y)`, odd-r with `x` growing West (SPK-16's `records.neighbours`).

A deck is walkable ground drawn over water: the converter writes every deck tile walkable in the
plane (`plane`), then P-1 runs on that plane as SPK-16's does. R-37 keeps authored content off a
bridge's deck and ends.

    python3 reach.py            # the unit tests (test_reach.py)
"""


class Refused(Exception):
    def __init__(self, code, detail=""):
        super().__init__(f"{code}: {detail}" if detail else code)
        self.code = code


def neighbours(x, y):
    """SPK-16's `records.neighbours`: an even row's North and South neighbours are `x - 1` and `x`,
    an odd row's `x` and `x + 1`."""
    d = 0 if y % 2 == 1 else -1
    return [(x - 1, y), (x + 1, y), (x + d, y - 1), (x + d + 1, y - 1), (x + d, y + 1),
            (x + d + 1, y + 1)]


def plane(painted, bridges, zone=None, blocked=()):
    """The walkable plane the converter writes: the painted floor and every deck tile (rule 1). A
    deck tile outside the zone (`zone`, its tiles; `None`: every tile) or on a blocked hex (a
    building's footprint, a blocking prop: `convert.py`'s `blocked`) is refused first."""
    decks = {d for b in bridges for d in b["deck"]}
    if zone is not None and decks - set(zone):
        raise Refused("export: deck outside the zone", f"{sorted(decks - set(zone))[:3]}")
    if decks & set(blocked):
        raise Refused("export: deck blocked", f"{sorted(decks & set(blocked))[:3]}")
    return set(painted) | decks


def assert_content(bridges, taken):
    """R-37 (`bridge: tile taken`): no spawn point, object, candidate tile, gate anchor or entry
    (`taken`, their tiles) on a bridge's deck or ends."""
    for i, b in enumerate(bridges):
        hit = (set(b["deck"]) | set(b["ends"])) & set(taken)
        if hit:
            raise Refused("bridge: tile taken", f"bridge {i} at {sorted(hit)[:3]}")


def connected(tiles, start):
    seen, todo = {start}, [start]
    while todo:
        for n in neighbours(*todo.pop()):
            if n in tiles and n not in seen:
                seen.add(n)
                todo.append(n)
    return seen


def p1(walk, entry):
    """P-1 (SPK-16's `pipeline`): every walkable tile reachable from the entry."""
    missing = walk - connected(walk, entry)
    if missing:
        raise Refused("pipeline: unreachable tile", f"{sorted(missing)[:3]}")


if __name__ == "__main__":
    import unittest
    unittest.main(module="test_reach")
