#!/usr/bin/env python3
"""The money computation of the report, from the raw measurements committed next to it:
katana-output.txt (receipts), snforge-summary.md (per-call L2 gas), prices-output.txt (gas and
STRK prices). Every input is printed; every assumption is a named constant below.

    python3 spikes/SPK-2/money.py
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------------------------------------
# Inputs

katana = {}
for line in open(os.path.join(HERE, "katana-output.txt")):
    if line.startswith("{"):
        d = json.loads(line)
        katana[d["label"]] = d

mainnet = sepolia = strk = None
for line in open(os.path.join(HERE, "prices-output.txt")):
    d = json.loads(line)
    if d.get("network") == "mainnet" and "l2_gas_fri" in d and mainnet is None:
        mainnet = d
    if d.get("network") == "sepolia" and "l2_gas_fri" in d and sepolia is None:
        sepolia = d
    if d.get("strk_usd_source") == "coingecko":
        strk = d
STRK_USD = strk["raw"]["starknet"]["usd"]

# snforge per-call L2 gas, first table (Sierra gas) and second (Cairo steps)
tables = open(os.path.join(HERE, "snforge-summary.md")).read().split("\n\n")


def parse(table):
    out = {}
    for row in table.splitlines():
        cells = [c.strip() for c in row.strip("|").split("|")]
        if len(cells) == 6 and cells[2].replace(",", "").isdigit():
            out.setdefault((cells[0], cells[1]), int(cells[2].replace(",", "")))
    return out


sierra = parse(tables[0])
steps = parse(tables[1])

# Action label (Katana) -> snforge (test, call)
SNFORGE = {
    "worst-case tick": ("test_tick_worst_case", "tick_worst_case.attack"),
    "worst-case tick, packed goblins": ("test_tick_worst_case_packed", "tick_worst_case.attack_packed"),
    "queue of 10 moves": ("test_queue_moves", "queue_moves.walk"),
    "queue of 5 moves": ("test_queue_moves_5", "queue_moves.walk"),
    "queue of 1 move": ("test_queue_moves_1", "queue_moves.walk"),
    "queue of 10 moves, no goblin": ("test_queue_moves_no_goblin", "queue_moves.walk"),
    "brew, signature, new pair": ("test_brew_signed_discovers", "brew.brew"),
    "brew, no signature, new pair": ("test_brew_unsigned_discovers", "brew.brew_unsigned"),
    "brew, known pair": ("test_brew_known_pair", "brew.brew"),
    "accept quest": ("test_hub_day", "hub.accept_quest"),
    "claim quest": ("test_hub_day", "hub.claim_quest"),
    "enter": ("test_hub_day", "hub.enter"),
    "leave": ("test_hub_day", "hub.leave"),
}
# The known-pair brew is the second call of its test: its figure is the smaller of the two
KNOWN_SIERRA = 3_312_392
KNOWN_STEPS = 3_048_960

P_L2 = mainnet["l2_gas_fri"]  # fri per L2 gas
P_DA = mainnet["l1_data_gas_fri"]  # fri per L1 data gas (blobs)
FRI = 1e-18  # STRK per fri

# Katana 1.7.1 posts state diffs as calldata (l1_gas, 16 gas per byte, 512 per felt); mainnet
# posts them in blobs (l1_data_gas, 1 per byte, 32 per felt): data gas ~ Katana l1_gas / 16.
DA_RATIO = 16


def usd(l2_gas, l1_gas=0):
    strk_amount = (l2_gas * P_L2 + (l1_gas / DA_RATIO) * P_DA) * FRI
    return strk_amount * STRK_USD, strk_amount


print("Prices")
print(f"  mainnet L2 gas     {P_L2:,} fri  ({mainnet['source']}, block {mainnet['block_number']}, "
      f"{mainnet['block_timestamp']}, read {mainnet['read_at']})")
print(f"  mainnet L1 data gas {P_DA:,} fri")
print(f"  sepolia L2 gas     {sepolia['l2_gas_fri']:,} fri  ({sepolia['source']}, block "
      f"{sepolia['block_number']}, {sepolia['block_timestamp']})")
print(f"  STRK               ${STRK_USD}  ({strk['url']}, read {strk['read_at']})")
print(f"  => 1M L2 gas = {1e6 * P_L2 * FRI:.6f} STRK = ${1e6 * P_L2 * FRI * STRK_USD:.6f}")
print()

# ---------------------------------------------------------------------------------------------
# Per action

cost = {}  # label -> (katana l2, katana l1, sierra estimate l2)
print("| Action | snforge call, Sierra gas | snforge call, Cairo steps | Katana tx L2 gas | "
      "Katana tx overhead | Katana L1 gas (DA) | Sierra estimate of the tx | $ (Katana) | "
      "$ (Sierra estimate) |")
print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
for label, key in SNFORGE.items():
    k = katana[label]
    s = KNOWN_SIERRA if label == "brew, known pair" else sierra[key]
    t = KNOWN_STEPS if label == "brew, known pair" else steps[key]
    overhead = k["l2_gas"] - t  # account, calldata, fee transfer, under Katana's metering
    estimate = s + overhead
    cost[label] = (k["l2_gas"], k["l1_gas"], estimate)
    print(f"| {label} | {s:,} | {t:,} | {k['l2_gas']:,} | {overhead:,} | {k['l1_gas']:,} | "
          f"{estimate:,} | {usd(k['l2_gas'], k['l1_gas'])[0]:.5f} | "
          f"{usd(estimate, k['l1_gas'])[0]:.5f} |")
print()

# ---------------------------------------------------------------------------------------------
# An expedition of 300 actions

ACTIONS = 300
MOVES = 180  # 60 %: walking, in queues
FIGHTS = 100  # 33 %: attacks and skills, one transaction each (the queue stops on damage)
OTHERS = 20  # 7 %: loot, chests, gates, potions: one transaction each, a tick with goblins
assert MOVES + FIGHTS + OTHERS == ACTIONS


def expedition(fight, queue_goblins, queue_goblins_len, queue_empty, queue_empty_len,
               share_near, other, index):
    """L2 and L1 gas of one expedition. `share_near`: share of the moves made with goblins
    awake (queues of `queue_goblins_len`), the rest exploring (queues of `queue_empty_len`)."""
    near = round(MOVES * share_near)
    far = MOVES - near
    n_near = -(-near // queue_goblins_len)
    n_far = -(-far // queue_empty_len)
    l2 = l1 = 0
    for count, action in ((n_near, queue_goblins), (n_far, queue_empty), (FIGHTS, fight),
                          (OTHERS, other), (1, "enter"), (1, "leave")):
        l2 += count * cost[action][index]
        l1 += count * cost[action][1]
    return l2, l1, n_near + n_far + FIGHTS + OTHERS + 2


# The packed lever measured on the tick; for queues it is estimated by the same saving (the same
# 8 goblins read and written once per transaction): not measured.
SAVING = {i: cost["worst-case tick"][i] - cost["worst-case tick, packed goblins"][i] for i in (0, 2)}
for label in ("queue of 5 moves", "queue of 1 move"):
    k2, k1, s2 = cost[label]
    cost[label + ", packed (estimated)"] = (k2 - SAVING[0], k1, s2 - SAVING[2])

SCENARIOS = [
    ("S1 worst case everywhere", "worst-case tick", "queue of 5 moves", 5,
     "queue of 10 moves, no goblin", 10, 1.0, "queue of 1 move"),
    ("S2 mixed: 2/3 of the moves exploring", "worst-case tick", "queue of 5 moves", 5,
     "queue of 10 moves, no goblin", 10, 1 / 3, "queue of 1 move"),
    ("S3 = S2 with the goblins packed in one model", "worst-case tick, packed goblins",
     "queue of 5 moves, packed (estimated)", 5, "queue of 10 moves, no goblin", 10, 1 / 3,
     "queue of 1 move, packed (estimated)"),
]

THRESHOLD = 0.50
print(f"Expedition: {ACTIONS} actions = {MOVES} moves + {FIGHTS} fight actions + {OTHERS} others,"
      f" plus enter and leave")
print("| Scenario | Transactions | L2 gas (Katana) | $ (Katana) | L2 gas (Sierra estimate) | "
      "$ (Sierra estimate) | x threshold | L2 gas price to pass (Sierra est.) |")
print("|---|---:|---:|---:|---:|---:|---:|---:|")
results = {}
for name, fight, qg, qgl, qe, qel, near, other in SCENARIOS:
    k2, k1, n = expedition(fight, qg, qgl, qe, qel, near, other, 0)
    s2, _, _ = expedition(fight, qg, qgl, qe, qel, near, other, 2)
    ku, _ = usd(k2, k1)
    su, _ = usd(s2, k1)
    results[name] = (k2, k1, s2, ku, su)
    # L2 gas price (fri) at which the Sierra estimate costs $0.50, DA kept at today's price
    da = (k1 / DA_RATIO) * P_DA
    price = (THRESHOLD / STRK_USD / FRI - da) / s2
    print(f"| {name} | {n} | {k2:,} | {ku:.3f} | {s2:,} | {su:.3f} | {su / THRESHOLD:.1f} | "
          f"{price / 1e9:.2f} Gfri |")
print()

# ---------------------------------------------------------------------------------------------
# An active player per day (D-101: 5 Rifts a day per account)

RIFTS = 5  # each Rift one expedition of 300 actions (floors not counted apart)
QUESTS = 3  # accepted and claimed
BREWS = 5  # new pairs
day_hub = {
    "accept quest": QUESTS,
    "claim quest": QUESTS,
    "brew, signature, new pair": BREWS,
}
print(f"Active player per day: {RIFTS} Rifts (one expedition each), {QUESTS} quests accepted and "
      f"claimed, {BREWS} brews of a new pair")
print("| Scenario | $ per day (Katana) | $ per day (Sierra estimate) | $ per 30 days (Sierra est.) |")
print("|---|---:|---:|---:|")
for name, (k2, k1, s2, ku, su) in results.items():
    hub_k = sum(n * cost[a][0] for a, n in day_hub.items())
    hub_s = sum(n * cost[a][2] for a, n in day_hub.items())
    hub_l1 = sum(n * cost[a][1] for a, n in day_hub.items())
    day_k = usd(RIFTS * k2 + hub_k, RIFTS * k1 + hub_l1)[0]
    day_s = usd(RIFTS * s2 + hub_s, RIFTS * k1 + hub_l1)[0]
    print(f"| {name} | {day_k:.2f} | {day_s:.2f} | {30 * day_s:.1f} |")
print()

# ---------------------------------------------------------------------------------------------
# D-52

a = sierra[SNFORGE["brew, signature, new pair"]]
b = sierra[SNFORGE["brew, no signature, new pair"]]
print(f"D-52 at system level (snforge, Sierra gas): {a:,} - {b:,} = {a - b:,} L2 gas "
      f"= {100 * (a - b) / b:.1f} % = ${usd(a - b)[0]:.6f} per first brew of a pair")
