#!/usr/bin/env python3
"""SPK-18: the converter's reachability (P-1) with bridges, and the layout rule R-37 (ADR-0008 rules
2 and 7). A prototype for ENG-09's converter (`tools/map-format/`, SPK-16's `convert.py`
`pipeline`), on global tiles `(x, y)`, odd-r with `x` growing West (SPK-16's `records.neighbours`).

The graph has two levels: `(t, 0)` for every walkable tile `t`, `(d, 1)` for every deck tile `d`.
- Ground edges: two adjacent walkable tiles, **but** an end and its own bridge's deck tile (the
  cut: that edge is the climb's, rule 2);
- the climb: an end `(e, 0)` and an adjacent tile of its bridge's deck `(d, 1)`;
- the deck: two adjacent tiles of one bridge's deck, `(d, 1)` and `(d', 1)`.
P-1: every node reachable from the entry `(entry, 0)`: every walkable tile on the ground and every
deck tile aloft. With no bridge it is SPK-16's P-1 unchanged.

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


def assert_layout(bridges):
    """R-37 (the converter's `export:` code, and ENG-09's `ZoneAssert` across a chunk's bridges):
    two bridges' decks neither share nor touch a tile; an end is on no deck and touches no other
    bridge's deck. With it, a deck tile next to an end is that end's bridge's (the window's masks
    are exact, `src/movement.cairo`)."""
    for i, b in enumerate(bridges):
        near = set(b["deck"]) | {n for d in b["deck"] for n in neighbours(*d)}
        for j, other in enumerate(bridges):
            if any(e in other["deck"] for e in b["ends"]):
                raise Refused("export: bridge end on a deck", f"bridge {i}")
            if j == i:
                continue
            if near & set(other["deck"]):
                raise Refused("export: decks touch", f"bridges {i} and {j}")
            if any(e in near for e in other["ends"]):
                raise Refused("export: end by another deck", f"bridges {j} and {i}")


def reach(walk, bridges, entry):
    """The nodes reachable from `(entry, 0)`."""
    deck_of, end_of = {}, {}
    for i, b in enumerate(bridges):
        for d in b["deck"]:
            deck_of[d] = i
        for e in b["ends"]:
            end_of.setdefault(e, set()).add(i)

    def edges(node):
        t, level = node
        for n in neighbours(*t):
            if level == 0:
                if t in end_of and deck_of.get(n) in end_of[t]:
                    yield (n, 1)  # the climb
                    continue
                if n in end_of and deck_of.get(t) in end_of[n]:
                    continue  # the cut
                if n in walk:
                    yield (n, 0)
            else:
                if deck_of.get(n) == deck_of[t]:
                    yield (n, 1)  # along the deck
                elif deck_of[t] in end_of.get(n, ()):
                    yield (n, 0)  # the descent

    start = (entry, 0)
    seen, todo = {start}, [start]
    while todo:
        for n in edges(todo.pop()):
            if n not in seen:
                seen.add(n)
                todo.append(n)
    return seen


def p1(walk, bridges, entry):
    """P-1 with bridges: refuses a walkable tile or a deck tile the entry cannot reach."""
    assert_layout(bridges)
    nodes = {(t, 0) for t in walk} | {(d, 1) for b in bridges for d in b["deck"]}
    missing = nodes - reach(walk, bridges, entry)
    if missing:
        raise Refused("pipeline: unreachable tile", f"{sorted(missing)[:3]}")


if __name__ == "__main__":
    import unittest
    unittest.main(module="test_reach")
