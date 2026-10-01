#!/usr/bin/env python3
"""SPK-12: L2 batches as designed against one SNIP-36 proof a segment, for S1 and for a
fight-heavy expedition (docs/research/SPK-12-client-proving.md §2). Arithmetic only: every input
below names its source and its kind (M measured, D derived, E estimated); every output is D when
all its inputs are M or D, E otherwise.

  python3 spikes/SPK-12/cost.py > spikes/SPK-12/cost-output.txt
"""
from math import ceil

USD_PER_GAS = 0.000881 / 1e6  # cost-budget.md §1: 1M L2 gas = $0.000881 (D, mainnet 2026-09-28)

# --- Batches as designed -------------------------------------------------------------------------
S1_BATCHES = 663e6  # STATUS.md, S1's running estimate (E): 300 actions, ~30 batches of weight 10
S1_TICKS = 300  # ENG-01 §10.2: about 30 batches of weight 10 (E)
FLOOR = 816_939  # cost-budget.md §1, the burner's floor (D)
# SPK-15 (spikes/SPK-15/README.md at 0f4b571, *A worst batch against 40 M*): per-call part paid once
# an invocation, a worst tick without it, the batch's own writes (ENG-01 §10.1's 64 keys, initialised).
WORST = {  # (per-call, per-tick, batch writes): E (the executor is E; the rest C/D)
    "as it stands": (19_675_090, 20_873_867, 4_436_950),
    "with L1-L4": (15_882_120, 14_807_647, 4_436_950),
}
# The representative tick inside a batch at the expedition's target (cost-budget §2), E.
TARGET_TICK = 1_469_435

# --- Shared by both designs: the actions that stay L2 transactions -------------------------------
ENTER = 4_513_259  # ENG-01 §10, CBT-02f, `enter` a later entry, belt worst case (M on the node, net)
LEAVE = 2_350_000  # ENG-01 §10, ENG-06's `leave` to a hub (M + 10 %, D-148)
FATE = 2_900_000  # cost-budget §2, a Fate action sent alone (E: not measured)
GATE = 3_667_902  # ENG-01 §10, `leave` through a gate to a location, initialised (E)

# --- Proofs (SNIP-36), slingfall at f8810c5 ------------------------------------------------------
# docs/proving.md, *Cost sheet on alpha.8 (lot B6)*: an Invoke carrying one proof and one
# `submit_chunk` message, 75,000,000 of it the protocol's flat charge (M on starknet-devnet 0.10.0).
PROOF_INVOKE = 77_321_760
VIRTUAL_CAP = 1.0e9  # slingfall's planner budget under the protocol's 1.1e9 cap (D)
# What grimworld adds per segment (E): the segment's resulting words published as calldata, so that
# a Fate action, another device and the indexer can rebuild the state the proof only hashes
# (design/02, *The client's copy*): about 420 felts for CBT-02's 100-goblin state (`fixture`'s
# words, 8 + 100 x 4 + members), at 5,120 a felt (cost-budget §1, M).
STATE_FELTS = 420
PUBLISH = STATE_FELTS * 5_120
SEGMENT_SETTLE = PROOF_INVOKE + PUBLISH


def usd(gas: float) -> str:
    return f"${gas * USD_PER_GAS:.3f}"


def m(gas: float) -> str:
    return f"{gas / 1e6:,.1f} M"


def proofs_for(ticks: float, per_call: float, per_tick: float, writes: float) -> int:
    """Proofs a segment of `ticks` ticks needs: its virtual transaction's L2 gas under the cap."""
    return max(1, ceil((per_call + ticks * per_tick + writes) / VIRTUAL_CAP))


def shared(fate: int, gates: int) -> float:
    return ENTER + LEAVE + fate * FATE + gates * GATE


def main() -> None:
    print("SPK-12 cost model (cost.py). M measured, D derived, E estimated; sources in the script.\n")
    print(f"Per segment, proved (E): one proof Invoke {PROOF_INVOKE:,} (M, slingfall B6) + the state "
          f"published, {STATE_FELTS} felts x 5,120 = {PUBLISH:,} (E) -> {SEGMENT_SETTLE:,} L2 gas "
          f"({usd(SEGMENT_SETTLE)}).\n")

    print("## S1 (300 actions, ~300 ticks), segments bounded by F Fate actions and G gates\n")
    print("| F | G | segments | ticks a segment | batches (STATUS, E) | proofs: segments | proofs: "
          "shared L2 txs | proofs total | ratio proofs / batches |")
    print("|--:|--:|--:|--:|--:|--:|--:|--:|--:|")
    rep = WORST["as it stands"]
    for fate, gates in [(5, 0), (10, 2), (20, 4)]:
        segments = fate + gates + 1
        per = S1_TICKS / segments
        # S1's representative ticks are far under the cap: one proof a segment.
        p = proofs_for(per, 0, TARGET_TICK, 0)
        proved = segments * p * SEGMENT_SETTLE
        total = proved + shared(fate, gates)
        print(f"| {fate} | {gates} | {segments} | {per:.0f} | {m(S1_BATCHES)} {usd(S1_BATCHES)} | "
              f"{m(proved)} | {m(shared(fate, gates))} | **{m(total)} {usd(total)}** | "
              f"{total / S1_BATCHES:.2f}x |")

    print("\n## A fight-heavy expedition: every one of 300 ticks SPK-15's worst tick\n")
    print("Batches: D-172 stops a batch before a tick that would pass the limit, so each worst tick "
          "is an invocation alone: floor + per-call + the tick + the batch's writes (E).\n")
    print("| worst tick | batches: a tick alone | batches total | segments (F=10, G=2) | proofs a "
          "segment | proofs total | ratio proofs / batches |")
    print("|---|--:|--:|--:|--:|--:|--:|")
    for name, (per_call, per_tick, writes) in WORST.items():
        alone = FLOOR + per_call + per_tick + writes
        batches = S1_TICKS * alone + shared(10, 2)
        segments = 13
        p = proofs_for(S1_TICKS / segments, per_call, per_tick, writes)
        proofs = segments * p * SEGMENT_SETTLE + shared(10, 2)
        print(f"| {name} | {m(alone)} | {m(batches)} {usd(batches)} | {segments} | {p} | "
              f"{m(proofs)} {usd(proofs)} | {proofs / batches:.3f}x |")

    print("\n## Ticks a proof holds (virtual transaction under 1.0e9 L2 gas, E)\n")
    print("| tick | per-call | per tick | ticks a proof |")
    print("|---|--:|--:|--:|")
    for name, (per_call, per_tick, writes) in WORST.items():
        n = int((VIRTUAL_CAP - per_call - writes) // per_tick)
        print(f"| worst, {name} | {per_call:,} | {per_tick:,} | {n} |")
    print(f"| representative at the target | 0 | {TARGET_TICK:,} | {int(VIRTUAL_CAP // TARGET_TICK)} |")

    print("\n## Break-even: ticks a segment above which one proof costs less than the same ticks "
          "batched\n")
    s1_tick = (S1_BATCHES - ENTER - LEAVE) / S1_TICKS
    rows = [
        ("S1's average tick, batched (663 M less enter and leave, over 300 ticks; E)", s1_tick),
        ("the representative tick at the expedition's target (cost-budget §2; E)", TARGET_TICK),
    ]
    for name, (per_call, per_tick, writes) in WORST.items():
        rows.append((f"a worst tick alone, {name} (SPK-15; E)", FLOOR + per_call + per_tick + writes))
    print("| batched cost of a tick | L2 gas | break-even ticks a segment |")
    print("|---|--:|--:|")
    for name, c in rows:
        print(f"| {name} | {c:,.0f} | {ceil(SEGMENT_SETTLE / c)} |")


if __name__ == "__main__":
    main()
