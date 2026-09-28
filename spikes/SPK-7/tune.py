#!/usr/bin/env python3
"""SPK-7: choose each biome's generation parameters (design/18 *Biomes*, walkable share) on the
Python model of `chunk::generate_chunk`, before writing them in Cairo. The Cairo test
`test_generate_biome_shares` checks the chosen ones on the real generator.

    python3 spikes/SPK-7/tune.py

Share = walkable tiles of the 13 x 13 interior after generation, over the interior (the ring is
the seam, drawn or copied). Random fill from Python's generator: the statistics, not the bits,
matter here.
"""
import random
import statistics

from model import neighbours

INTERIOR = {(x, y) for x in range(1, 14) for y in range(1, 14)}
SPINE = {(x, 7) for x in range(1, 14)} | {(7, y) for y in range(1, 14)}
# Fill densities the generator can draw from three random words a, b, c (in eighths).
DENSITIES = {1: "a&b&c", 2: "a&b", 3: "a&(b|c)", 4: "a", 5: "a|(b&c)", 6: "a|b", 7: "a|b|c"}
TARGETS = {"meadow": (0.80, 0.90), "forest": (0.60, 0.70), "cave": (0.45, 0.55), "ruin": (0.40, 0.50)}


def ring_and_lines(rng):
    ring, lines = set(), set()
    for side in range(4):
        for _ in range(1 + rng.randrange(2)):
            p = 1 + rng.randrange(13)
            if side == 0:
                ring.add((0, p)); lines |= {(x, p) for x in range(1, 8)}
            elif side == 1:
                ring.add((14, p)); lines |= {(x, p) for x in range(7, 14)}
            elif side == 2:
                ring.add((p, 0)); lines |= {(p, y) for y in range(1, 8)}
            else:
                ring.add((p, 14)); lines |= {(p, y) for y in range(7, 14)}
    return ring, lines


def generate(rng, eighths, born, survive, passes, flip):
    fill = {t for t in INTERIOR if rng.random() < eighths / 8}
    ring, lines = ring_and_lines(rng)
    grid = fill | lines | SPINE
    for _ in range(passes):
        nxt = set()
        for t in INTERIOR:
            count = sum(1 for n in neighbours(*t, 15, 15, flip) if n in grid or n in ring)
            if count >= (survive if t in grid else born):
                nxt.add(t)
        grid = nxt
    grid |= lines | SPINE
    # keep the component of the centre
    seen, queue = {(7, 7)}, [(7, 7)]
    for t in queue:
        for n in neighbours(*t, 15, 15, flip):
            if n in grid and n not in seen:
                seen.add(n); queue.append(n)
    return len(seen) / 169


def main():
    rng = random.Random(7)
    results = []
    for eighths in DENSITIES:
        for born in range(1, 7):
            for survive in range(0, 7):
                for passes in (1, 2, 3):
                    shares = [generate(rng, eighths, born, survive, passes, s % 2 == 1) for s in range(60)]
                    results.append((statistics.mean(shares), statistics.pstdev(shares), min(shares), max(shares), eighths, born, survive, passes))
    for biome, (low, high) in TARGETS.items():
        mid = (low + high) / 2
        ok = [r for r in results if low <= r[2] and r[3] <= high]
        ok = ok or [r for r in results if low <= r[0] <= high]
        # prefer: range inside the target, then the fewest passes (cheapest), then centred
        ok.sort(key=lambda r: (not (low <= r[2] and r[3] <= high), r[7], abs(r[0] - mid)))
        print(biome, [f"mean {r[0]:.3f} sd {r[1]:.3f} min {r[2]:.3f} max {r[3]:.3f} fill {r[4]}/8 B{r[5]}/S{r[6]} x{r[7]}" for r in ok[:4]])


if __name__ == "__main__":
    main()
