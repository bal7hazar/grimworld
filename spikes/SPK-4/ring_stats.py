#!/usr/bin/env python3
"""What the vectors say about the ring of ADR-0006 §4 and the empty case (SPK-4 fix loop 1):
goblins starting on the ring (none may move), moves onto the ring (none may land there), and the
panic data of the empty cases. Exits 1 if a vector breaks the ring rule.

  python3 spikes/SPK-4/ring_stats.py [vectors.jsonl]
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "vectors", "vectors.jsonl")
ring = {t for t in range(240) if t % 15 in (0, 14) or t // 15 in (0, 15)}
on_ring = moved_from_ring = onto_ring = interior_moves = 0
empty = []
for line in open(path, encoding="utf-8"):
    v = json.loads(line)
    if not v["case"]:
        empty.append(bytes.fromhex(v["panic"][0][2:]).decode() if "panic" in v else "returned")
        continue
    if v["case"][0] != "0x1" or "ok" not in v:
        continue
    goblin, tile = int(v["case"][3], 16), int(v["ok"][0], 16)
    if goblin in ring:
        on_ring += 1
        moved_from_ring += tile != goblin
    elif tile != goblin:
        interior_moves += 1
        onto_ring += tile in ring
print(json.dumps({
    "goblin_steps_starting_on_the_ring": on_ring,
    "of_which_moved": moved_from_ring,
    "moves_from_the_interior": interior_moves,
    "of_which_onto_the_ring": onto_ring,
    "empty_cases": len(empty),
    "empty_case_panic_data": sorted(set(empty)),
}, indent=1))
sys.exit(1 if moved_from_ring or onto_ring else 0)
