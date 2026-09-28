#!/usr/bin/env python3
"""SPK-2, fix loops 1 and 2: the money of both sides from one node and one account
(devnet-output.txt, written by devnet_measure.py), at fresh prices (prices-fixloop2-output.txt).
Fix loop 2: the tick's flood stops at 15 layers (D-127) on both sides, and the fights of every
scenario are the capped worst case. Supersedes the money of part 2 (native/money-output.txt) and
of fix loop 1 (money-devnet-output-fixloop1-uncapped.txt).

    python3 spikes/SPK-2/money_devnet.py > spikes/SPK-2/money-devnet-output.txt
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
FRI = 1e-18
THRESHOLD = 0.50

rows = {}
for line in open(os.path.join(HERE, "devnet-output.txt")):
    d = json.loads(line)
    if "side" in d:
        assert d["status"] == "SUCCEEDED", d
        rows[(d["side"], d["label"])] = d

mainnet = strk = None
for line in open(os.path.join(HERE, "prices-fixloop2-output.txt")):
    d = json.loads(line)
    if d.get("network") == "mainnet" and "l2_gas_fri" in d and mainnet is None:
        mainnet = d
    if d.get("strk_usd_source") == "coingecko":
        strk = d
P_L2, P_DA = mainnet["l2_gas_fri"], mainnet["l1_data_gas_fri"]
STRK_USD = strk["raw"]["starknet"]["usd"]


def usd(r):
    return (r["l2_gas"] * P_L2 + r["l1_data_gas"] * P_DA) * FRI * STRK_USD


def da_usd(r):
    return r["l1_data_gas"] * P_DA * FRI * STRK_USD


print("Prices")
print(f"  mainnet L2 gas {P_L2:,} fri, L1 data gas {P_DA:,} fri ({mainnet['source']}, block "
      f"{mainnet['block_number']}, {mainnet['block_timestamp']}, read {mainnet['read_at']})")
print(f"  STRK ${STRK_USD} ({strk['url']}, read {strk['read_at']})")
print(f"  => 1M L2 gas = ${1e6 * P_L2 * FRI * STRK_USD:.6f}")
print()

# ---------------------------------------------------------------------------------------------
# Controlled pairs: same node, same account, same storage per goblin (one slot), same checks
# (none: part 1's systems check no owner)

PAIRS = [
    ("Capped worst-case tick, D-127: 15 layers, 8 goblins reached (goblins: one slot each)",
     "capped worst-case tick (15 layers, 8 goblins reached)",
     "capped worst-case tick (15 layers, 8 goblins reached), one felt per goblin, unchecked"),
    ("Capped worst-case tick (goblins packed per instance)",
     "capped worst-case tick (15 layers, 8 goblins reached), packed goblins",
     "capped worst-case tick (15 layers, 8 goblins reached), goblins packed, unchecked"),
    ("Worst-case tick, part 1 fixture (goblins: one slot each)", "worst-case tick",
     "worst-case tick, one felt per goblin, unchecked"),
    ("Worst-case tick, part 1 fixture (goblins packed per instance)", "worst-case tick, packed goblins",
     "worst-case tick, goblins packed, unchecked"),
    ("Queue of 10 moves", "queue of 10 moves", "queue of 10 moves, unchecked"),
    ("Queue of 5 moves", "queue of 5 moves", "queue of 5 moves, unchecked"),
    ("Queue of 1 move", "queue of 1 move", "queue of 1 move, unchecked"),
    ("Queue of 10 moves, no goblin", "queue of 10 moves, no goblin", "queue of 10 moves, no goblin, unchecked"),
    ("Tick, corridor maze (45 layers unlimited; capped at 15)",
     "tick, corridor maze (45 layers unlimited; capped at 15)",
     "tick, corridor maze (45 layers unlimited; capped at 15), unchecked"),
    ("Tick, unreachable target (13 layers)", "tick, unreachable target (13 layers)",
     "tick, unreachable target (13 layers), unchecked"),
    ("Tick, deepest board found (92 layers unlimited; capped at 15)",
     "tick, deepest board found (92 layers unlimited; capped at 15)",
     "tick, deepest board found (92 layers unlimited; capped at 15), unchecked"),
    ("Queue of 10 moves, serpentine (expensive valid queue, capped)", "queue of 10 moves, serpentine (capped)",
     "queue of 10 moves, serpentine (capped), unchecked"),
    ("Brew, signature, new pair", "brew, signature, new pair", "brew, signature, new pair"),
    ("Brew, no signature, new pair", "brew, no signature, new pair", "brew, no signature, new pair"),
    ("Brew, known pair", "brew, known pair", "brew, known pair"),
    ("Accept quest", "accept quest", "accept quest"),
    ("Claim quest", "claim quest", "claim quest"),
    ("Enter", "enter", "enter"),
    ("Leave", "leave", "leave"),
]

print("Controlled pairs: starknet-devnet 0.10.0, the same Cairo 2.19 account, equal goblin storage, "
      "equal checks")
print("| Action | Dojo tx L2 gas | Native tx L2 gas | Difference | Native / Dojo | $ Dojo | $ native |")
print("|---|---:|---:|---:|---:|---:|---:|")
for name, dojo, native in PAIRS:
    d, n = rows[("dojo", dojo)], rows[("native", native)]
    print(f"| {name} | {d['l2_gas']:,} | {n['l2_gas']:,} | {n['l2_gas'] - d['l2_gas']:+,} | "
          f"{n['l2_gas'] / d['l2_gas']:.2f} | {usd(d):.5f} | {usd(n):.5f} |")
print()

def calls(path):
    """(test, call) -> the L2 gas figures of the first table of a snforge summary, in order."""
    out = {}
    for row in open(path).read().split("\n\n")[0].splitlines():
        cells = [c.strip() for c in row.strip("|").split("|")]
        if len(cells) >= 3 and cells[2].replace(",", "").isdigit():
            out.setdefault((cells[0], cells[1]), []).append(int(cells[2].replace(",", "")))
    return out


DOJO_CALLS = calls(os.path.join(HERE, "snforge-summary.md"))
NATIVE_CALLS = calls(os.path.join(HERE, "native", "snforge-summary.md"))
CALL_PAIRS = [
    ("Capped worst-case tick (goblins: one slot each)",
     ("test_tick_capped_worst_case", "tick_worst_case.attack", 0),
     ("test_tick_capped_worst_case", "Instances.attack", 0)),
    ("Capped worst-case tick (goblins packed per instance)",
     ("test_tick_capped_worst_case", "tick_worst_case.attack_packed", 0),
     ("test_tick_capped_worst_case", "Instances.attack", 3)),
    ("Worst-case tick, part 1 fixture (goblins: one slot each)", ("test_tick_worst_case", "tick_worst_case.attack", 0),
     ("test_tick_worst_case", "Instances.attack", 0)),
    ("Worst-case tick, part 1 fixture (goblins packed per instance)",
     ("test_tick_worst_case_packed", "tick_worst_case.attack_packed", 0),
     ("test_tick_worst_case_layouts", "Instances.attack", 3)),
    ("Queue of 10 moves", ("test_queue_moves", "queue_moves.walk", 0), ("test_queue_moves", "Instances.walk", 0)),
    ("Queue of 5 moves", ("test_queue_moves_5", "queue_moves.walk", 0), ("test_queue_moves_5", "Instances.walk", 0)),
    ("Queue of 1 move", ("test_queue_moves_1", "queue_moves.walk", 0), ("test_queue_moves_1", "Instances.walk", 0)),
    ("Queue of 10 moves, no goblin", ("test_queue_moves_no_goblin", "queue_moves.walk", 0),
     ("test_queue_moves_no_goblin", "Instances.walk", 0)),
    ("Tick, corridor maze (capped)", ("test_tick_adversarial_boards", "tick_worst_case.attack", 0),
     ("test_tick_adversarial_boards", "Instances.attack", 0)),
    ("Tick, unreachable target (13 layers)", ("test_tick_adversarial_boards", "tick_worst_case.attack", 1),
     ("test_tick_adversarial_boards", "Instances.attack", 1)),
    ("Tick, deepest board found (capped)", ("test_tick_adversarial_boards", "tick_worst_case.attack", 2),
     ("test_tick_adversarial_boards", "Instances.attack", 2)),
    ("Queue of 10 moves, serpentine (capped)", ("test_queue_serpent", "queue_moves.walk", 0),
     ("test_queue_serpent", "Instances.walk", 0)),
    ("Brew, signature, new pair", ("test_brew_signed_discovers", "brew.brew", 0),
     ("test_brew_signed_discovers", "Hub.brew", 0)),
    ("Brew, known pair", ("test_brew_known_pair", "brew.brew", 1), ("test_brew_known_pair", "Hub.brew", 1)),
    ("Accept quest", ("test_hub_day", "hub.accept_quest", 0), ("test_hub_day", "Hub.accept_quest", 0)),
    ("Claim quest", ("test_hub_day", "hub.claim_quest", 0), ("test_hub_day", "Hub.claim_quest", 0)),
    ("Enter", ("test_hub_day", "hub.enter", 0), ("test_hub_day", "Hub.enter", 0)),
    ("Leave", ("test_hub_day", "hub.leave", 0), ("test_hub_day", "Instances.leave", 0)),
]
print("Controlled pairs, the call alone (snforge, Sierra gas, syscalls excluded)")
print("| Action | Dojo call | Native call | Native / Dojo |")
print("|---|---:|---:|---:|")
for name, (dt, dc, di), (nt, nc, ni) in CALL_PAIRS:
    d, n = DOJO_CALLS[(dt, dc)][di], NATIVE_CALLS[(nt, nc)][ni]
    print(f"| {name} | {d:,} | {n:,} | {n / d:.2f} |")
print()

print("Native only: the owner check (production form) and the layout experiment")
print("| Action | Native tx L2 gas | $ |")
print("|---|---:|---:|")
for label in (
    "capped worst-case tick (15 layers, 8 goblins reached), one felt per goblin, checked",
    "capped worst-case tick (15 layers, 8 goblins reached), goblins packed, checked",
    "worst-case tick, one felt per goblin, checked", "worst-case tick, goblins packed, checked",
    "worst-case tick, 11 slots per goblin, checked", "queue of 10 moves, checked", "queue of 5 moves, checked",
    "queue of 1 move, checked", "queue of 10 moves, no goblin, checked",
    "queue of 10 moves, goblins packed, checked", "queue of 5 moves, goblins packed, checked",
    "queue of 1 move, goblins packed, checked", "queue of 10 moves, 11 slots per goblin, checked",
    "queue of 10 moves, serpentine (capped), checked",
):
    n = rows[("native", label)]
    print(f"| {label} | {n['l2_gas']:,} | {usd(n):.5f} |")
print()

print("Where a native transaction goes (trace; devnet reports invocation gas in steps of 40,000, "
      "so the rest can be slightly negative)")
print("| Action | Receipt | Validate | Account execute | Game calls | Fee transfer | Rest |")
print("|---|---:|---:|---:|---:|---:|---:|")
for label in ("capped worst-case tick (15 layers, 8 goblins reached), one felt per goblin, checked",
              "worst-case tick, one felt per goblin, checked", "queue of 10 moves, checked",
              "queue of 10 moves, no goblin, checked",
              "tick, deepest board found (92 layers unlimited; capped at 15), unchecked",
              "brew, signature, new pair", "accept quest", "enter"):
    n = rows[("native", label)]
    t = n["trace"]
    print(f"| {label} | {n['l2_gas']:,} | {t['validate']:,} | {t['account_execute']:,} | "
          f"{t['game_calls']:,} | {t['fee_transfer']:,} | {t['rest']:,} |")
print()

# ---------------------------------------------------------------------------------------------
# Expeditions (as §3.3) and days (as §3.4), as (L2 gas, L1 data gas) sums so that the break-even
# price scales only the L2 part (C-5): price = (threshold - DA_USD) / (L2_gas x STRK_USD x 1e-18)

MOVES, FIGHTS, OTHERS = 180, 100, 20
RIFTS, QUESTS, BREWS = 5, 3, 5


def gas(side, label):
    if side == "dojo-est":
        # Part 1's packed queues on Dojo are estimated: the queue minus the saving on the tick
        saving = (rows[("dojo", CAPPED_DOJO)]["l2_gas"]
                  - rows[("dojo", CAPPED_DOJO + ", packed goblins")]["l2_gas"])
        r = rows[("dojo", label)]
        return (r["l2_gas"] - saving, r["l1_data_gas"])
    r = rows[(side, label)]
    return (r["l2_gas"], r["l1_data_gas"])


def add(total, count, value):
    return (total[0] + count * value[0], total[1] + count * value[1])


def expedition(side, fight, near_queue, near_len, far_queue, other, near, est=False):
    q = "dojo-est" if est else side
    n_near = -(-round(MOVES * near) // near_len)
    n_far = -(-(MOVES - round(MOVES * near)) // 10)
    total = (0, 0)
    total = add(total, n_near, gas(q, near_queue))
    total = add(total, n_far, gas(side, far_queue))
    total = add(total, FIGHTS, gas(side, fight))
    total = add(total, OTHERS, gas(q, other))
    total = add(total, 1, gas(side, "enter"))
    total = add(total, 1, gas(side, "leave"))
    return total


def dollars(total):
    return (total[0] * P_L2 + total[1] * P_DA) * FRI * STRK_USD


def day(side, total):
    t = (RIFTS * total[0], RIFTS * total[1])
    t = add(t, QUESTS, gas(side, "accept quest"))
    t = add(t, QUESTS, gas(side, "claim quest"))
    t = add(t, BREWS, gas(side, "brew, signature, new pair"))
    return t


N = "native"
CAPPED_DOJO = "capped worst-case tick (15 layers, 8 goblins reached)"
FIGHT = "capped worst-case tick (15 layers, 8 goblins reached), one felt per goblin, checked"
FIGHT_PACKED = "capped worst-case tick (15 layers, 8 goblins reached), goblins packed, checked"
# Every fight is the capped worst case (D-127: the game's worst tick), in production form (checked)
SCENARIOS = [
    ("S1 worst case everywhere",
     ("dojo", CAPPED_DOJO, "queue of 5 moves", 5, "queue of 10 moves, no goblin", "queue of 1 move", 1.0),
     (N, FIGHT, "queue of 5 moves, checked", 5, "queue of 10 moves, no goblin, checked",
      "queue of 1 move, checked", 1.0)),
    ("S2 mixed (2/3 of the moves exploring)",
     ("dojo", CAPPED_DOJO, "queue of 5 moves", 5, "queue of 10 moves, no goblin", "queue of 1 move", 1 / 3),
     (N, FIGHT, "queue of 5 moves, checked", 5, "queue of 10 moves, no goblin, checked",
      "queue of 1 move, checked", 1 / 3)),
    ("S3 mixed, goblins packed per instance",
     ("dojo", CAPPED_DOJO + ", packed goblins", "queue of 5 moves", 5, "queue of 10 moves, no goblin",
      "queue of 1 move", 1 / 3, True),
     (N, FIGHT_PACKED, "queue of 5 moves, goblins packed, checked", 5, "queue of 10 moves, no goblin, checked",
      "queue of 1 move, goblins packed, checked", 1 / 3)),
    ("S4 worst case everywhere, goblins packed per instance",
     ("dojo", CAPPED_DOJO + ", packed goblins", "queue of 5 moves", 5, "queue of 10 moves, no goblin",
      "queue of 1 move", 1.0, True),
     (N, FIGHT_PACKED, "queue of 5 moves, goblins packed, checked", 5, "queue of 10 moves, no goblin, checked",
      "queue of 1 move, goblins packed, checked", 1.0)),
    ("S5 adversarial (every move near goblins in serpentine queues, capped)",
     ("dojo", CAPPED_DOJO, "queue of 10 moves, serpentine (capped)", 10, "queue of 10 moves, no goblin",
      CAPPED_DOJO, 1.0),
     (N, FIGHT, "queue of 10 moves, serpentine (capped), checked", 10, "queue of 10 moves, no goblin, checked",
      FIGHT, 1.0)),
]

print(f"Expedition: {MOVES} moves + {FIGHTS} fight actions + {OTHERS} others, plus enter and leave; "
      f"day: {RIFTS} Rifts, {QUESTS} quests, {BREWS} brews. Native in its production form (owner checked). "
      f"Every fight is the capped worst-case tick (D-127)")
print("| Scenario | $ Dojo | $ native | Native / Dojo | Native × $0.50 | L2 gas price for native to pass | "
      "Native L2 gas per expedition | $ per day, native |")
print("|---|---:|---:|---:|---:|---:|---:|---:|")
for name, d, n in SCENARIOS:
    dt, nt = expedition(*d), expedition(*n)
    du, nu = dollars(dt), dollars(nt)
    da = nt[1] * P_DA * FRI * STRK_USD
    price = (THRESHOLD - da) / (nt[0] * STRK_USD * FRI)
    print(f"| {name} | {du:.3f} | {nu:.3f} | {nu / du:.2f} | {nu / THRESHOLD:.2f} | {price / 1e9:.2f} Gfri | "
          f"{nt[0]:,} | {dollars(day(N, nt)):.2f} |")
print()
print("Dojo's S3 and S4 use part 1's estimated packed queues (measured tick, estimated queues).")

# ---------------------------------------------------------------------------------------------
# What an action would have to cost for ADR-0001's threshold to hold (fix loop 2)

ACTIONS = 300
BUDGET_USD = THRESHOLD / ACTIONS
# DA of an action: the capped fight's L1 data gas, the heaviest DA of the ordinary actions
DA_REF = rows[(N, FIGHT)]["l1_data_gas"]
BUDGET_L2 = (BUDGET_USD - DA_REF * P_DA * FRI * STRK_USD) / (P_L2 * STRK_USD * FRI)
print(f"Per action, for 300 actions ≤ $0.50: ${BUDGET_USD:.6f} per action; with {DA_REF} L1 data gas "
      f"per action at today's price, that is {BUDGET_L2:,.0f} L2 gas per action")
print("| Native action (production form) | Actions per tx | Tx L2 gas | L2 gas per action | $ per action | × budget |")
print("|---|---:|---:|---:|---:|---:|")
PER_ACTION = [
    (FIGHT, 1), (FIGHT_PACKED, 1), ("worst-case tick, one felt per goblin, checked", 1),
    ("queue of 10 moves, checked", 10), ("queue of 5 moves, checked", 5), ("queue of 1 move, checked", 1),
    ("queue of 10 moves, no goblin, checked", 10), ("queue of 10 moves, goblins packed, checked", 10),
    ("queue of 5 moves, goblins packed, checked", 5), ("queue of 1 move, goblins packed, checked", 1),
    ("queue of 10 moves, serpentine (capped), checked", 10), ("enter", 1), ("leave", 1),
    ("brew, signature, new pair", 1), ("accept quest", 1), ("claim quest", 1),
]
for label, n in PER_ACTION:
    r = rows[(N, label)]
    per = usd(r) / n
    print(f"| {label} | {n} | {r['l2_gas']:,} | {r['l2_gas'] / n:,.0f} | {per:.6f} | {per / BUDGET_USD:.2f} |")
print()
print("| Scenario | $ per action, native (expedition / 300) | × budget |")
print("|---|---:|---:|")
for name, d, n in SCENARIOS:
    per = dollars(expedition(*n)) / ACTIONS
    print(f"| {name} | {per:.6f} | {per / BUDGET_USD:.2f} |")
