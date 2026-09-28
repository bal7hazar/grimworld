#!/usr/bin/env python3
"""Adversarial boards for the tick's flood (fix loop 1, C-3): how many layers the shared flood
needs on a valid 15 × 16 window, beyond the 12 of the part-1 fixture.

    python3 spikes/SPK-2/adversarial.py

Prints, for each board, the terrain felt, the goblins' local tiles and the number of flood layers
(the loop of `board::flood`: one layer per distance until every goblin is touched or the frontier
runs out). The same rules as `src/board.cairo`: pointy-top odd-r, bit 15 y + x, `+1` West, the
ring is wall, goblins block the flood (occupancy frozen at the start of the tick, rule (a)).

Boards:
- `maze`: the auditor's board (start 112, goblins 111, 16, 211, 213, 215, 217, 219, 221);
- `sealed`: the same, goblin 221 walled in: the flood runs until the frontier is exhausted;
- `deep`: a hill climb from `maze` for the deepest valid board found (seeded, deterministic): the
  8 goblins on the farthest reachable tiles.
"""
import random
from collections import deque

W, H = 15, 16
START = 112  # local (7, 7)
INTERIOR = [y * W + x for y in range(1, H - 1) for x in range(1, W - 1)]


def neighbours(i):
    x, y = i % W, i // W
    out = []
    if x > 0:
        out.append(i - 1)
    if x < W - 1:
        out.append(i + 1)
    cols = (x - 1, x) if y % 2 == 0 else (x, x + 1)
    for dy in (-1, 1):
        ny = y + dy
        if 0 <= ny < H:
            for nx in cols:
                if 0 <= nx < W:
                    out.append(ny * W + nx)
    return out


def tiles(felt):
    return {i for i in INTERIOR if (felt >> i) & 1}


def felt(ts):
    return sum(1 << i for i in ts)


def distances(open_tiles, start):
    dist = {start: 0}
    queue = deque([start])
    while queue:
        t = queue.popleft()
        for n in neighbours(t):
            if n in open_tiles and n not in dist:
                dist[n] = dist[t] + 1
                queue.append(n)
    return dist


def layers(terrain, goblins, start=START):
    """Length of the layer array `board::flood` returns (layer 0 is the start): goblins block;
    the loop stops when every goblin is touched (the last layer is the farthest goblin's
    distance) or when the frontier is empty (one last, empty, layer). Returns (length,
    per-goblin distances, 0 = unreachable)."""
    free = terrain - set(goblins) - {start}
    dist = distances(free | {start}, start)
    depth = {}
    for g in goblins:
        ds = [dist[n] + 1 for n in neighbours(g) if n in dist]
        depth[g] = min(ds) if ds else 0
    if all(depth.values()):
        return max(depth.values()) + 1, depth
    return max(dist.values()) + 2, depth


def show(name, terrain, goblins):
    n, depth = layers(terrain, goblins)
    print(f"{name}: layers {n}, goblins {goblins}, distances {[depth[g] for g in goblins]}")
    print(f"  terrain {hex(felt(terrain))}")
    return n


MAZE = tiles(0xfff9fff00027ffc8001fff00027ffc8001fff00027ffc8001fff0000)
MAZE_GOBLINS = [111, 16, 211, 213, 215, 217, 219, 221]
assert START in MAZE and all(g in MAZE for g in MAZE_GOBLINS)
show("maze", MAZE, MAZE_GOBLINS)

# An unreachable target: part 1's worst-case fixture board (the comb, `fixtures::window(COMB, 13,
# 14)`) with goblin 8 (local 151) walled in: the flood runs until the frontier is exhausted.
def comb_walkable(x, y):
    return y % 4 != 2 or x % 6 == 3


COMB = {i for i in INTERIOR if comb_walkable(13 + i % W, 14 + i // W)}
WORST_GOBLINS = [111, 97, 16, 28, 211, 223, 103, 151]
show("comb (part 1 fixture)", COMB, WORST_GOBLINS)
SEALED = COMB - {n for n in neighbours(151) if n in COMB}
show("sealed", SEALED, WORST_GOBLINS)


def eccentricity(open_tiles):
    return max(distances(open_tiles, START).values())


def farthest(open_tiles, count):
    """`count` goblins on the farthest tiles: first those that stay reachable once the others
    block (they step), then the farthest remaining tiles (a goblin blocked by another is
    unreachable, and the flood then runs until the frontier is exhausted: the costliest case)."""
    dist = distances(open_tiles, START)
    order = [t for t in sorted(dist, key=lambda t: (-dist[t], t)) if t != START]
    chosen = []
    for t in order:
        trial = chosen + [t]
        _, depth = layers(open_tiles, trial)
        if all(depth.values()):
            chosen = trial
        if len(chosen) == count:
            return chosen
    for t in order:
        if len(chosen) == count:
            break
        if t not in chosen:
            chosen.append(t)
    return sorted(chosen)


# Goblin 1 stands next to the adventurer (the measured action is an attack on it): its tile is
# kept open and counted as an obstacle throughout the climb, which maximises the eccentricity of
# the start around it.
ADJACENT = 113  # local (8, 7), West of the start
rng = random.Random(2026)
best = set(MAZE) | {ADJACENT}
best_score = eccentricity(best - {ADJACENT})
for _ in range(60000):
    t = rng.choice(INTERIOR)
    if t in (START, ADJACENT):
        continue
    trial = best ^ {t}
    score = eccentricity(trial - {ADJACENT})
    if score >= best_score:
        best, best_score = trial, score
# Drop tiles the flood cannot reach from the start: they change nothing
best = set(distances(best - {ADJACENT}, START)) | {ADJACENT}
deep_goblins = [ADJACENT] + farthest(best - {ADJACENT}, 7)
print(f"deep: eccentricity {best_score}")
show("deep", best, deep_goblins)
