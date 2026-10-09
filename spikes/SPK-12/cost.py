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
    # S1's ticks alone: 663 M less the transactions that are not batches in the central reading
    # (enter, leave, 10 Fate actions, 2 gates), over 300 ticks (fix loop 1, finding 2).
    s1_tick = (S1_BATCHES - shared(10, 2)) / S1_TICKS
    rows = [
        ("S1's average tick, batched (663 M less enter, leave, 10 Fate actions and 2 gates, over "
         "300 ticks; E)", s1_tick),
        ("the representative tick at the expedition's target (cost-budget §2; E)", TARGET_TICK),
    ]
    for name, (per_call, per_tick, writes) in WORST.items():
        rows.append((f"a worst tick alone, {name} (SPK-15; E)", FLOOR + per_call + per_tick + writes))
    print("| batched cost of a tick | L2 gas | break-even ticks a segment |")
    print("|---|--:|--:|")
    for name, c in rows:
        print(f"| {name} | {c:,.0f} | {ceil(SEGMENT_SETTLE / c)} |")
    phone()


# --- The phone (docs/research/SPK-12-client-proving.md §4), E ------------------------------------
# phone time = T1 / (A2 x A3): T1 the Mac's one-thread time (M, prove-output.txt run8), A2 an A15
# performance core against one Mac core, A3 the A15's six cores against one.
A2 = (0.5, 0.8)
A3 = (1.8, 2.5)
# The Mac's one-thread over six-thread time, measured on the floor (37.4-37.5 / 14.25-14.27) and on
# busy:40 (70.77-78.11 / 24.90-25.08): used to get T1 where only six threads were run.
T1_OVER_T6 = (37.40 / 14.27, 78.11 / 24.90)
WATTS = 5.0  # A5, not measured
BATTERY_J = 12.7 * 3600  # A5: about 12.7 Wh
SEGMENTS = 13  # the central reading


def phone() -> None:
    print("\n## The phone (E): time = T1 / (A2 x A3), A2 = 0.5-0.8, A3 = 1.8-2.5; energy at 5 W "
          "of a 12.7 Wh battery\n")
    print("| segment | T1, Mac one thread | phone time | battery a proof | 13 proofs |")
    print("|---|--:|--:|--:|--:|")
    cases = [
        ("the floor (representative:1), M", (37.40, 37.53)),
        ("busy:40, M", (70.77, 78.11)),
        # No one-thread run: T1 = the Mac's six-thread time (~65 s, D from representative:1000's
        # 76.93-78.05 s at 5.31 M steps, scaled to 4.3 M) x T1_OVER_T6.
        ("23 full worst ticks, ~4.3 M steps (T1 = 65 s x 2.6-3.1, E)",
         (65 * T1_OVER_T6[0], 65 * T1_OVER_T6[1])),
    ]
    for name, (t1_lo, t1_hi) in cases:
        lo, hi = t1_lo / (A2[1] * A3[1]), t1_hi / (A2[0] * A3[0])
        b_lo, b_hi = lo * WATTS / BATTERY_J, hi * WATTS / BATTERY_J
        print(f"| {name} | {t1_lo:.1f}-{t1_hi:.1f} s | {lo:.0f}-{hi:.0f} s | "
              f"{100 * b_lo:.2f}-{100 * b_hi:.2f} % | {100 * SEGMENTS * b_lo:.1f}-"
              f"{100 * SEGMENTS * b_hi:.1f} % |")


# --- ENG-07 (D-233 to D-236): S1 on `play`'s measured batches ------------------------------------
# Every input M: the node's six runs of `lifecycle_probe.py --play on` (the maximum), snforge for the
# fight (`test_tick::test_cost_segment_fight*` less their fixtures, the segment in process: its call,
# 1,409,090 M, added), ENG-05's accepted rises on `enter` and `leave` (PLAN's ENG-05 row).
EXPLORATION_BATCH = 18_992_640  # 10 Moves, every tick on the fast path (node, M)
# One chunk revealed by a Move, end to end (node, M: 14,898,240 - 6,792,640, the max of seven runs).
REVEAL_IN_PLAY = 8_105_600
FIGHT_BATCH_REAL = 189_431_756 + 1_409_090  # 8 goblins attacking a tick, the member at 480: 4 ticks (M)
FIGHT_BATCH_WHOLE = 483_793_084 + 1_409_090  # the same, the member standing 10 ticks (M)
FIGHT_BATCH_CAP4 = 366_384_550 + 1_409_090  # lever 1, at most 4 attacking (M, the cap stood in for)
ENTER_ENG05 = ENTER + 3_520_000  # ENG-05's rise, its worst (M, accepted under D-144)
LEAVE_ENG05 = LEAVE + 6_730_000


def eng07() -> None:
    print("\n## S1 on ENG-07's measured batches (D-158): 30 batches, k of them a fight\n")
    print("| batches | L2 gas | S1 | against 663 M |")
    print("|---|--:|--:|--:|")
    for k, name, fight in (
        (0, "30 exploration batches, 4 reveals", 0),
        (3, "27 exploration + 3 fights at real health (4 ticks each)", FIGHT_BATCH_REAL),
        (3, "27 exploration + 3 whole fights (10 ticks of 8 attackers)", FIGHT_BATCH_WHOLE),
        (3, "27 exploration + 3 whole fights, lever 1 (at most 4 attackers)", FIGHT_BATCH_CAP4),
    ):
        total = (30 - k) * EXPLORATION_BATCH + k * fight + 4 * REVEAL_IN_PLAY + ENTER_ENG05 \
            + LEAVE_ENG05
        print(f"| {name} (E: the mix) | {total:,.0f} | {usd(total)} | {total / S1_BATCHES:.2f}x |")


if __name__ == "__main__":
    main()
    eng07()
