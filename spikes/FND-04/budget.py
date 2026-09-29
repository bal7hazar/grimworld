#!/usr/bin/env python3
"""FND-04: the arithmetic of docs/architecture/cost-budget.md. No network.

Every input is a measured figure with its source, or a coefficient fitted by analyse.py on the
Sepolia traces. Every output says whether it is measured (M), derived from measurements by
arithmetic only (D), or an estimate that rests on an assumption (E).

    python3 spikes/FND-04/budget.py > spikes/FND-04/budget-output.txt
"""
import json
import os

import analyse

HERE = os.path.dirname(os.path.abspath(__file__))

# --- Prices: SPK-1 §5's, so that every dollar here compares with SPK-1 and D-137 -----------------
P_L2 = 21_345_234_918          # fri per L2 gas, mainnet, block 15,594,144 (SPK-1 prices-output.txt)
P_DA = 980_202_556_584         # fri per L1 data gas, same block
STRK_USD = 0.04125403          # CoinGecko, 2026-09-28T20:50:07Z
THRESHOLD, ACTIONS = 0.50, 300  # D-129


def usd(l2, da=0):
    return (l2 * P_L2 + da * P_DA) * 1e-18 * STRK_USD


# --- Measured on Sepolia ---------------------------------------------------------------------------
BURNER_FIXED = 717_435         # SPK-1b §1: validate + account execution + fee transfer + res2, burner sending directly
OWNER_FIXED = 1_087_585        # SPK-1b §3, the owner's account, same definition
BURNER_SAVING = OWNER_FIXED - BURNER_FIXED  # 370,150: the same transaction sent by the burner (SPK-1b, measured on enter and leave)

rows = analyse.load()


def sepolia(label):
    """One measured Sepolia transaction of that label (the repeats are identical, analyse.py §1)."""
    return next(r for r in rows if r["label"] == label)


TICK_LABEL = "capped worst-case tick (15 layers, 8 goblins reached), one felt per goblin, checked"
M = {k: sepolia(v) for k, v in {
    "tick": TICK_LABEL,
    "q10": "queue of 10 moves, checked",
    "q5": "queue of 5 moves, checked",
    "q1": "queue of 1 move, checked",
    "explore10": "queue of 10 moves, no goblin, checked",
    "enter": "enter",
    "leave": "leave",
    "b_enter": "B burner direct: enter",
    "b_leave": "B burner direct: leave",
}.items()}

# --- Fitted on the same traces (analyse.py §2, §4) -------------------------------------------------
shapes = []
seen = set()
for r in rows:
    if r["type"] == "DECLARE" or r["label"].startswith("D burner"):
        continue
    if analyse.signature(r) not in seen:
        seen.add(analyse.signature(r))
        shapes.append(r)
s11 = sum(r["new"] ** 2 for r in shapes)
s12 = sum(r["new"] * (r["over"] + r["zeroed"]) for r in shapes)
s22 = sum((r["over"] + r["zeroed"]) ** 2 for r in shapes)
t1 = sum(r["new"] * r["state"] for r in shapes)
t2 = sum((r["over"] + r["zeroed"]) * r["state"] for r in shapes)
det = s11 * s22 - s12 * s12
NEW_SLOT = round((t1 * s22 - t2 * s12) / det)
OTHER_SLOT = round((s11 * t2 - s12 * t1) / det)
PER_FELT, BASE = analyse.PER_FELT, analyse.BASE
SIG_FELTS, HEADER_FELTS = 2, 4  # a Stark signature; a multicall of one call: count, to, selector, length
EXTRA_CALL_FELTS = 3            # each further call of a multicall: to, selector, length

# The floor of a burner transaction before its game call and its game slots:
FEE_SLOTS = 2  # the fee token's balances of the sender and of the sequencer (every trace)
FLOOR = BURNER_FIXED + BASE + PER_FELT * (SIG_FELTS + HEADER_FELTS) + FEE_SLOTS * OTHER_SLOT


def out(s=""):
    print(s)


def fmt(n):
    return f"{round(n):,}"


out("# FND-04 budget arithmetic\n")
out("Kinds: M measured; D derived from measurements by arithmetic only; E estimate resting on a stated assumption.\n")
out("## Inputs\n")
out("| Input | Value | Kind | Source |")
out("|---|---:|---|---|")
out(f"| Burner's fixed part, sending directly | {fmt(BURNER_FIXED)} | M | SPK-1b §1 (validate 87,805, execution 141,670, fee transfer 455,360, res2 32,600) |")
out(f"| Same transaction, burner against the owner's account | −{fmt(BURNER_SAVING)} | M | SPK-1b §4 (enter and leave, identical game call) |")
out(f"| res1 constant + the 2 signature felts, together (the aggregate) | {fmt(BASE + SIG_FELTS * PER_FELT)} | chosen normalisation, not measured | analyse.py §2, §4.1: any aggregate congruent to 880 modulo 2,000, from 880 to 74,880, keeps the observed divisibility |")
out(f"| — split as a constant {fmt(BASE)} + 2 × {fmt(PER_FELT)} | — | assumed normalisation | a free signature and a constant of 14,880 fit the same receipts |")
out(f"| Per felt of calldata | {fmt(PER_FELT)} | M | analyse.py §3, controlled pairs |")
out(f"| A multicall's header: the first call {HEADER_FELTS} felts (count, to, selector, length), each further call "
    f"{EXTRA_CALL_FELTS} (to, selector, length) | {fmt(PER_FELT * HEADER_FELTS)}, then {fmt(PER_FELT * EXTRA_CALL_FELTS)} a call | D | the account's `__execute__` calldata layout × the per-felt price |")
out(f"| A new slot (value was 0) | {fmt(NEW_SLOT)} | M (fit under the 14,880 convention) | analyse.py §4; pairs 426,000 to 482,000; 452,808 to 453,691 over the admissible aggregates (§4.1) |")
out(f"| An overwritten or zeroed slot | {fmt(OTHER_SLOT)} | M (fit under the 14,880 convention) | analyse.py §4; pairs 20,000 to 80,000; 24,878 to 33,751 over the admissible aggregates (§4.1) |")
out(f"| **Floor of a burner transaction** (fixed part + constant + 6 felts + the fee token's 2 slots) | **{fmt(FLOOR)}** | D under the 14,880 convention | the lines above; 806,297 to 862,551 over the admissible aggregates, 815,419 to 818,459 within ±2,000 (analyse.py §4.1) |")
out(f"| Prices | L2 {P_L2:,} fri, DA {P_DA:,} fri, STRK ${STRK_USD} | M | SPK-1 §5 (mainnet, 2026-09-28) |")
out(f"| 1M L2 gas | ${usd(1e6):.6f} | D | |")
out(f"| The target in L2 gas: $0.50 for 300 actions, no DA | {fmt(THRESHOLD / usd(1))} per expedition, {fmt(THRESHOLD / usd(1) / ACTIONS)} per action | D | D-129 |")
out()

# Check: the floor model against the burner's measured receipts.
out("## Check: the model against the burner's receipts (SPK-1b case B)\n")
out("| Action | Receipt (M) | Floor + game call + args + game slots (model) | Error |")
out("|---|---:|---:|---:|")
for k in ("b_enter", "b_leave"):
    r = M[k]
    args = r["felts"] - SIG_FELTS - HEADER_FELTS
    game_slots = r["new"] * NEW_SLOT + (r["over"] + r["zeroed"] - FEE_SLOTS) * OTHER_SLOT
    model = FLOOR + r["game"] + PER_FELT * args + game_slots + r["res2"] - 32_600  # res2 is inside BURNER_FIXED at leave's 32,600
    out(f"| {r['label']} | {fmt(r['receipt'])} | {fmt(model)} | {fmt(model - r['receipt'])} ({100 * (model - r['receipt']) / r['receipt']:+.1f} %) |")
out()

# --- Per transaction, with the burner ------------------------------------------------------------
out("## Every measured action, sent by the burner (D: SPK-1's receipt − 370,150; enter and leave M: SPK-1b)\n")
out("| Action | L2 gas | L1 data gas | Game call | Game slots new/other | $ |")
out("|---|---:|---:|---:|---|---:|")
burner = {}
for k, r in M.items():
    if k.startswith("b_"):
        continue
    l2 = M["b_" + k]["receipt"] if k in ("enter", "leave") else r["receipt"] - BURNER_SAVING
    burner[k] = (l2, r["da"])
    gs = f"{r['new']}/{r['over'] + r['zeroed'] - FEE_SLOTS}"
    out(f"| {r['label']} | {fmt(l2)} | {r['da']} | {fmt(r['game'])} | {gs} | {usd(l2, r['da']):.5f} |")
out()

# --- A batch of 10 worst ticks -------------------------------------------------------------------
tick = M["tick"]
tick_remainder_burner = tick["receipt"] - tick["game"] - BURNER_SAVING  # M − M: 1,194,875
batch_as_measured = 10 * tick["game"] + tick_remainder_burner + PER_FELT * 9 * 3  # 9 more attack actions, ~3 felts each (E)
# The queue shares its reads and writes: a move alone against a move in a queue (M, SPK-1 §3)
per_move_in_queue = (M["q10"]["game"] - M["q5"]["game"]) / 5
shared_in_walk = M["q1"]["game"] - per_move_in_queue
out("## A played batch of weight 10\n")
out("| Figure | L2 gas | Kind | How |")
out("|---|---:|---|---|")
out(f"| Worst tick, game call | {fmt(tick['game'])} | M | SPK-1 §4 |")
out(f"| Worst tick, non-game remainder with the burner | {fmt(tick_remainder_burner)} | D | {fmt(tick['receipt'] - tick['game'])} − {fmt(BURNER_SAVING)} |")
out(f"| Batch of 10 worst ticks, each tick's call as measured | {fmt(batch_as_measured)} | E | 10 × call + remainder once + 27 felts of the 9 more actions (3 felts each: assumption) |")
out(f"| A move in a queue, 8 goblins following: marginal | {fmt(per_move_in_queue)} | D | (queue of 10 − queue of 5) / 5, game calls |")
out(f"| The part of a queue's call it pays once | {fmt(shared_in_walk)} | D | queue of 1 − the marginal move |")
tick_marginal_if_shared = tick["game"] - shared_in_walk
batch_shared = 10 * tick_marginal_if_shared + shared_in_walk + tick_remainder_burner + PER_FELT * 27
out(f"| Batch of 10 worst ticks, if a batch reads and writes the instance once as the queue does | {fmt(batch_shared)} | E | assumes the tick shares the same {fmt(shared_in_walk)} as the walk: not measured |")
spk7_window = 720_000
out(f"| The chunked map's net overhead on a one-tick transaction with goblins awake | +{fmt(spk7_window)} | M (local node) | SPK-7: a whole-transaction difference (A − S), storage effects included, the local node's meter |")
out(f"| — of which the window's assembly in memory | 65,224 | M (snforge) | SPK-7 §2.1; the window follows the adventurer and is assembled at every tick (D-120) |")
out(f"| + that overhead at each of the 10 ticks, the batch paying it as 10 transactions would | +{fmt(10 * spk7_window)} per batch | E | an upper reading: inside one transaction, cached chunk reads and slots changed once may cost less; not measured |")
out(f"| design/02's target of a batch | 40,000,000 | — | design/02 § Size |")
out(f"| Batch as measured + that overhead at each tick | {fmt(batch_as_measured + 10 * spk7_window)} | E | above 40M |")
out(f"| Batch sharing + that overhead at each tick | {fmt(batch_shared + 10 * spk7_window)} | E | |")
out(f"| Batch as measured + the assembly alone at each tick (reads and writes cached, no other effect) | "
    f"{fmt(batch_as_measured + 10 * 65_224)} | E | the lower reading |")
per_tick_budget = (40_000_000 - FLOOR - 16 * OTHER_SLOT - PER_FELT * 30) / 10
out(f"| **Per-tick budget inside 40M** (40M − floor − 16 game slots once − 30 felts) / 10 | **{fmt(per_tick_budget)}** | D | the game's computation and storage syscalls of one tick, window included |")
ret = sepolia("return the burner's STRK")
out(f"| Funding a new burner: the burner's STRK transfer measured, its recipient's balance new instead of overwritten | "
    f"{fmt(ret['receipt'] + NEW_SLOT - OTHER_SLOT)} | E | {fmt(ret['receipt'])} (M) + {fmt(NEW_SLOT - OTHER_SLOT)} |")
fate = FLOOR + 1_000_000 + 2 * NEW_SLOT + 4 * OTHER_SLOT
out(f"| A Fate action other than the entry draw (enter has its own budget): floor + a call of 1.0M + 2 new + 4 other slots | {fmt(fate)} | E | the call's 1.0M is an assumption |")
out()

out("## Enter, the movement benchmark, reveals\n")
out("| Figure | L2 gas | Kind | How |")
out("|---|---:|---|---|")
b_enter = M["b_enter"]
out(f"| Enter, burner: 4 new instance slots under a new instance id | {fmt(b_enter['receipt'])} | M | SPK-1b; the 25 enters of SPK-1 wrote 100 distinct new keys |")
reuse = b_enter["receipt"] - 4 * (NEW_SLOT - OTHER_SLOT)
out(f"| Enter, if its 4 slots are **reused keys** holding a value (instance slots reused, a generation in the record) | {fmt(reuse)} | E (extrapolation) | − 4 × {fmt(NEW_SLOT - OTHER_SLOT)}; no zero-then-rewrite was observed, and no instance key was recycled between enters |")
out(f"| The spike's `walk` of 10 moves, 8 goblins following, burner (movement benchmark) | {fmt(burner['q10'][0])} | D | SPK-1's receipt − 370,150 |")
walk_args = M["q10"]["felts"] - SIG_FELTS - HEADER_FELTS
play10 = burner["q10"][0] - PER_FELT * walk_args + PER_FELT * 30
out(f"| A move-only `play` batch of 10 moves near goblins (design/02: planned moves join play) | {fmt(play10)} | E | the benchmark with its {walk_args} argument felts replaced by 30 (3 a move); assumes play's moves cost what walk's do |")
for n, first_reveal in ((1, True), (1, False), (3, False)):
    slots = n * NEW_SLOT + (NEW_SLOT if first_reveal else OTHER_SLOT)
    out(f"| Slots of a reveal of {n} chunk{'s' if n > 1 else ''}, SPK-7's layout ({n} terrain slot{'s' if n > 1 else ''} new; the revealed bitmap "
        f"{'new: the instance' + chr(39) + 's first reveal' if first_reveal else 'overwritten'}) | {fmt(slots)} | D | SPK-7 `reveal`: terrain per chunk, the bitmap once per transaction, no occupancy |")
out(f"| + an occupancy slot per chunk, new, if a future layout writes one at reveal | +{fmt(NEW_SLOT)} a chunk | E (assumption) | SPK-7 writes occupancy only when goblins move |")
out()

# --- Expedition -------------------------------------------------------------------------------------
out("## The expedition: 300 actions (SPK-1 §5's composition), burner sending directly\n")
out("S1: 36 queues of 5 moves near goblins, 100 fights, 20 other actions (a move alone near goblins), enter, leave.")
out("S2: 12 queues of 5 near goblins, 12 exploring queues of 10, the rest as S1.\n")


def expedition(near_q5, explore_q10, fights, fight_batch, near_q10=0):
    l2 = da = 0
    for count, key in ((near_q5, "q5"), (near_q10, "q10"), (explore_q10, "explore10"), (20, "q1"), (1, "enter"),
                       (1, "leave")):
        l2 += count * burner[key][0]
        da += count * burner[key][1]
    l2 += fights * fight_batch
    da += fights * tick["da"]
    return l2, da


out("Every batched row assumes a batch keeps **one** tick's state remainder and one tick's DA footprint "
    "(832 L1 data gas): the tick's 12 slots changed once per transaction. Each batch carries the 27 argument felts "
    f"of its 9 further actions (3 felts each, an assumption): {fmt(PER_FELT * 27)} a batch, "
    f"{fmt(PER_FELT * 270)} per expedition.\n")
cases = [
    ("One action per transaction, owner's account (SPK-1 §5: a projection of receipts)", None),
    ("One per transaction, burner", ("single", tick["receipt"] - BURNER_SAVING)),
    ("Fights in batches of 10, each tick as measured, without the 27 felts (D-137's estimate)", ("batch", 10 * tick["game"] + tick_remainder_burner)),
    ("Fights in batches of 10, each tick as measured, with the 27 felts", ("batch", batch_as_measured)),
    ("Fights in batches of 10, reads and writes shared", ("batch", batch_shared)),
    ("Also moves near goblins in 10s (priced as the queue of 10)", ("batch10", batch_shared)),
]
out("| Case | Kind | S1 L2 gas | S1 $ | S1 × $0.50 | S2 L2 gas | S2 $ | S2 × $0.50 |")
out("|---|---|---:|---:|---:|---:|---:|---:|")
for name, c in cases:
    res = []
    for near, far in ((36, 0), (12, 12)):
        if c is None:
            l2 = da = 0
            for count, key in ((near, "q5"), (far, "explore10"), (20, "q1"), (100, "tick"), (1, "enter"), (1, "leave")):
                l2 += count * M[key]["receipt"]
                da += count * M[key]["da"]
        elif c[0] == "single":
            l2, da = expedition(near, far, 100, c[1])
        elif c[0] == "batch10":
            l2, da = expedition(0, far, 10, c[1], near_q10=near * 5 // 10)
        else:
            l2, da = expedition(near, far, 10, c[1])
        res.append((l2, da))
    kind = "D" if c is None or c[0] == "single" else "E"
    (l1, d1), (l2_, d2) = res
    out(f"| {name} | {kind} | {fmt(l1)} | {usd(l1, d1):.3f} | {usd(l1, d1) / THRESHOLD:.2f} | {fmt(l2_)} | "
        f"{usd(l2_, d2):.3f} | {usd(l2_, d2) / THRESHOLD:.2f} |")
out()

# What the expedition must fit in, and where the rest would have to come from.
target_l2 = THRESHOLD / usd(1)
l1, d1 = expedition(36, 0, 10, batch_shared)
l2_, d2 = expedition(12, 12, 10, batch_shared)
out("## What $0.50 leaves, at these prices\n")
out(f"- The target: {fmt(target_l2)} L2 gas per expedition with no DA (D).")
for name, (l, d) in (("S1", (l1, d1)), ("S2", (l2_, d2))):
    over = (usd(l, d) - THRESHOLD) / usd(1)
    out(f"- {name}, fights batched and shared (E): {fmt(l)} L2 gas and {d:,} L1 data gas, ${usd(l, d):.3f}; "
        f"{'over' if over > 0 else 'under'} the target by {fmt(abs(over))} L2 gas.")
moves_s1 = 36 * burner["q5"][0]
l1_unshared, _ = expedition(36, 0, 10, batch_as_measured)
out(f"- S1's 36 queues of 5 near goblins cost {fmt(moves_s1)} (D): {100 * moves_s1 / l1_unshared:.3f} % of S1 with "
    f"fights batched, each tick as measured, with the 27 felts (E), and {100 * moves_s1 / l1:.3f} % with fights "
    "batched and shared (E).")
# S1 with moves near goblins in tens: what must a fight's tick cost, inside a batch, for S1 to meet $0.50?
rest_l2, rest_da = expedition(0, 0, 0, 0, near_q10=18)
fight_da = 10 * tick["da"]
per_batch = (THRESHOLD / usd(1) - rest_l2 - (rest_da + fight_da) * P_DA / P_L2) / 10
per_tick_needed = (per_batch - tick_remainder_burner - PER_FELT * 27) / 10
out(f"- For S1 to meet $0.50 with its moves near goblins in tens (E): a batch of 10 fight ticks at "
    f"{fmt(per_batch)} L2 gas, **{fmt(per_tick_needed)} per tick** (game call, inside the batch), against "
    f"{fmt(tick['game'])} measured alone and {fmt(tick_marginal_if_shared)} if shared as the queue shares.")
out(f"- Break-even L2 gas price, S1 and S2 with fights batched and shared (E): "
    f"{THRESHOLD / (l1 * 1e-18 * STRK_USD) / 1e9 - d1 * P_DA / l1 / 1e9:.1f} and "
    f"{THRESHOLD / (l2_ * 1e-18 * STRK_USD) / 1e9 - d2 * P_DA / l2_ / 1e9:.1f} Gfri (today {P_L2 / 1e9:.1f}).")
out()

# --- Hub actions: estimated from SPK-2's native entrypoints -----------------------------------------
LIGHT_RATIO = 1.157
out("## Hub actions not measured on Sepolia (E)\n")
out(f"Estimate = floor + game call (snforge's Sierra gas × {LIGHT_RATIO}, the median Sepolia/snforge ratio of SPK-1 §3's "
    "light actions: exploring queue 1.115, enter 1.157, leave 1.182; the heavy ones are 1.02 to 1.09) + 3 felts of "
    "arguments + its game slots from the local node's traces (devnet_trace.py).\n")
snforge = {"brew, signature, new pair": 755_698, "brew, known pair": 493_050, "accept quest": 248_930,
           "claim quest": 403_150}
devslots = {}
for line in open(os.path.join(HERE, "devnet-output.txt")):
    d = json.loads(line)
    if d.get("side") == "native" and d["label"] in snforge:
        game = [c for c in d["state_diff"]["storage"] if not c["contract"].startswith("0x4718")]
        devslots[d["label"]] = (sum(c["new"] for c in game), sum(c["overwritten"] + c["zeroed"] for c in game),
                                d["l2_gas"])
out("| Action | snforge call (M) | Game slots new/other (M, devnet) | Estimate on Sepolia, burner | $ | Devnet receipt (M, other meter) |")
out("|---|---:|---|---:|---:|---:|")
for label, sn in snforge.items():
    n, o, dv = devslots[label]
    est = FLOOR + sn * LIGHT_RATIO + PER_FELT * 3 + n * NEW_SLOT + o * OTHER_SLOT
    out(f"| {label} | {fmt(sn)} | {n}/{o} | {fmt(est)} | {usd(est):.5f} | {fmt(dv)} |")
