#!/usr/bin/env python3
"""SPK-2 part 2: the money of the native contracts, side by side with the Dojo baseline of part 1,
from the committed raw outputs and at the same fresh prices:
  ../katana-output.txt, ../snforge-summary.md   part 1 (Dojo): Katana receipts, snforge calls
  devnet-output.txt, snforge-summary.md         part 2 (native): devnet receipts, snforge calls
  prices-output.txt                             prices read for part 2

    python3 spikes/SPK-2/native/money.py > spikes/SPK-2/native/money-output.txt
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PART1 = os.path.dirname(HERE)


def receipts(path):
    out = {}
    for line in open(path):
        if line.startswith("{"):
            d = json.loads(line)
            out[d["label"]] = d
    return out


def summary(path):
    """(test, call) -> first L2 gas figure of the first table."""
    out = {}
    table = open(path).read().split("\n\n")[0]
    for row in table.splitlines():
        cells = [c.strip() for c in row.strip("|").split("|")]
        if len(cells) >= 3 and cells[2].replace(",", "").isdigit():
            out.setdefault((cells[0], cells[1]), []).append(int(cells[2].replace(",", "")))
    return out


katana = receipts(os.path.join(PART1, "katana-output.txt"))
devnet = receipts(os.path.join(HERE, "devnet-output.txt"))
dojo_calls = summary(os.path.join(PART1, "snforge-summary.md"))
native_calls = summary(os.path.join(HERE, "snforge-summary.md"))

mainnet = strk = None
for line in open(os.path.join(HERE, "prices-output.txt")):
    d = json.loads(line)
    if d.get("network") == "mainnet" and "l2_gas_fri" in d and mainnet is None:
        mainnet = d
    if d.get("strk_usd_source") == "coingecko":
        strk = d
P_L2 = mainnet["l2_gas_fri"]
P_DA = mainnet["l1_data_gas_fri"]
STRK_USD = strk["raw"]["starknet"]["usd"]
FRI = 1e-18
THRESHOLD = 0.50


def usd_katana(r):
    # Katana posts state diffs as calldata (l1_gas, 512 per felt); mainnet in blobs (32 per felt)
    return (r["l2_gas"] * P_L2 + r["l1_gas"] / 16 * P_DA) * FRI * STRK_USD


def usd_devnet(r):
    return (r["l2_gas"] * P_L2 + r["l1_data_gas"] * P_DA) * FRI * STRK_USD


print("Prices")
print(f"  mainnet L2 gas {P_L2:,} fri, L1 data gas {P_DA:,} fri ({mainnet['source']}, block "
      f"{mainnet['block_number']}, {mainnet['block_timestamp']}, read {mainnet['read_at']})")
print(f"  STRK ${STRK_USD} ({strk['url']}, read {strk['read_at']})")
print(f"  => 1M L2 gas = ${1e6 * P_L2 * FRI * STRK_USD:.6f}")
print()

# label, Dojo Katana label, Dojo snforge (test, call, index), native snforge (test, call, index)
ROWS = [
    ("Worst-case tick, a model / storage struct per goblin", "worst-case tick",
     ("test_tick_worst_case", "tick_worst_case.attack", 0),
     ("test_tick_worst_case", "Instances.attack", 0)),
    ("Worst-case tick, goblins packed per instance", "worst-case tick, packed goblins",
     ("test_tick_worst_case_packed", "tick_worst_case.attack_packed", 0),
     ("test_tick_worst_case_layouts", "Instances.attack_packed", 0)),
    ("Worst-case tick, one felt per goblin (native only)", None, None,
     ("test_tick_worst_case_layouts", "Instances.attack_felt", 0)),
    ("Queue of 10 moves", "queue of 10 moves", ("test_queue_moves", "queue_moves.walk", 0),
     ("test_queue_moves", "Instances.walk", 0)),
    ("Queue of 5 moves", "queue of 5 moves", ("test_queue_moves_5", "queue_moves.walk", 0),
     ("test_queue_moves_5", "Instances.walk", 0)),
    ("Queue of 1 move", "queue of 1 move", ("test_queue_moves_1", "queue_moves.walk", 0),
     ("test_queue_moves_1", "Instances.walk", 0)),
    ("Queue of 10 moves, no goblin", "queue of 10 moves, no goblin",
     ("test_queue_moves_no_goblin", "queue_moves.walk", 0),
     ("test_queue_moves_no_goblin", "Instances.walk", 0)),
    ("Queue of 10 moves, goblins packed (native only)", None, None,
     ("test_queue_moves_packed", "Instances.walk_packed", 0)),
    ("Queue of 5 moves, goblins packed (native only)", None, None,
     ("test_queue_moves_packed_short", "Instances.walk_packed", 0)),
    ("Queue of 1 move, goblins packed (native only)", None, None,
     ("test_queue_moves_packed_short", "Instances.walk_packed", 1)),
    ("Brew, signature, new pair", "brew, signature, new pair",
     ("test_brew_signed_discovers", "brew.brew", 0), ("test_brew_signed_discovers", "Hub.brew", 0)),
    ("Brew, no signature, new pair", "brew, no signature, new pair",
     ("test_brew_unsigned_discovers", "brew.brew_unsigned", 0),
     ("test_brew_unsigned_discovers", "Hub.brew_unsigned", 0)),
    ("Brew, known pair", "brew, known pair", ("test_brew_known_pair", "brew.brew", 1),
     ("test_brew_known_pair", "Hub.brew", 1)),
    ("Accept quest", "accept quest", ("test_hub_day", "hub.accept_quest", 0),
     ("test_hub_day", "Hub.accept_quest", 0)),
    ("Claim quest", "claim quest", ("test_hub_day", "hub.claim_quest", 0),
     ("test_hub_day", "Hub.claim_quest", 0)),
    ("Enter", "enter", ("test_hub_day", "hub.enter", 0), ("test_hub_day", "Hub.enter", 0)),
    ("Leave", "leave", ("test_hub_day", "hub.leave", 0), ("test_hub_day", "Instances.leave", 0)),
]
NATIVE_LABEL = {
    "Worst-case tick, a model / storage struct per goblin": "worst-case tick",
    "Worst-case tick, goblins packed per instance": "worst-case tick, packed goblins",
    "Worst-case tick, one felt per goblin (native only)": "worst-case tick, one felt per goblin",
    "Queue of 10 moves, goblins packed (native only)": "queue of 10 moves, packed goblins",
    "Queue of 5 moves, goblins packed (native only)": "queue of 5 moves, packed goblins",
    "Queue of 1 move, goblins packed (native only)": "queue of 1 move, packed goblins",
}


def call(calls, key):
    if key is None:
        return None
    test, name, index = key
    return calls[(test, name)][index]


def fmt(v):
    return "—" if v is None else f"{v:,}"


print("Full transactions: Dojo on Katana 1.7.1 (Cairo-steps metering), native on starknet-devnet "
      "0.10.0; and the call alone in snforge (Sierra gas, syscalls excluded)")
print("| Action | Dojo tx L2 gas | Native tx L2 gas | Difference | Native / Dojo | $ Dojo | $ native "
      "| Dojo call | Native call | Native / Dojo (call) |")
print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
native_tx = {}
for label, dojo_label, dojo_key, native_key in ROWS:
    n = devnet[NATIVE_LABEL.get(label, dojo_label.lower() if dojo_label else None)]
    native_tx[label] = n
    nc = call(native_calls, native_key)
    if dojo_label:
        k = katana[dojo_label]
        dc = call(dojo_calls, dojo_key)
        print(f"| {label} | {k['l2_gas']:,} | {n['l2_gas']:,} | {n['l2_gas'] - k['l2_gas']:+,} | "
              f"{n['l2_gas'] / k['l2_gas']:.2f} | {usd_katana(k):.5f} | {usd_devnet(n):.5f} | "
              f"{dc:,} | {nc:,} | {nc / dc:.2f} |")
    else:
        print(f"| {label} | — | {n['l2_gas']:,} | — | — | — | {usd_devnet(n):.5f} | — | {nc:,} | — |")
print()

# ---------------------------------------------------------------------------------------------
# Expeditions, as part 1: 180 moves in queues, 100 fight actions, 20 others, enter and leave

MOVES, FIGHTS, OTHERS = 180, 100, 20


def expedition(cost, fight, near_queue, near_len, far_queue, far_len, share_near, other):
    near = round(MOVES * share_near)
    far = MOVES - near
    n_near = -(-near // near_len)
    n_far = -(-far // far_len)
    total = (n_near * cost[near_queue] + n_far * cost[far_queue] + FIGHTS * cost[fight]
             + OTHERS * cost[other] + cost["enter"] + cost["leave"])
    return total, n_near + n_far + FIGHTS + OTHERS + 2


dojo_cost = {label: usd_katana(r) for label, r in katana.items()}
native_cost = {label: usd_devnet(r) for label, r in devnet.items()}
# Part 1's packed queues were estimated (not measured): the queue minus the saving on the tick
saving = dojo_cost["worst-case tick"] - dojo_cost["worst-case tick, packed goblins"]
dojo_cost["queue of 5 moves, packed (estimated)"] = dojo_cost["queue of 5 moves"] - saving
dojo_cost["queue of 1 move, packed (estimated)"] = dojo_cost["queue of 1 move"] - saving

SCENARIOS = [
    ("S1 worst case everywhere, a model / struct per goblin",
     ("worst-case tick", "queue of 5 moves", 5, "queue of 10 moves, no goblin", 10, 1.0,
      "queue of 1 move"),
     ("worst-case tick", "queue of 5 moves", 5, "queue of 10 moves, no goblin", 10, 1.0,
      "queue of 1 move")),
    ("S2 mixed (2/3 of the moves exploring), a model / struct per goblin",
     ("worst-case tick", "queue of 5 moves", 5, "queue of 10 moves, no goblin", 10, 1 / 3,
      "queue of 1 move"),
     ("worst-case tick", "queue of 5 moves", 5, "queue of 10 moves, no goblin", 10, 1 / 3,
      "queue of 1 move")),
    ("S3 mixed, goblins packed per instance",
     ("worst-case tick, packed goblins", "queue of 5 moves, packed (estimated)", 5,
      "queue of 10 moves, no goblin", 10, 1 / 3, "queue of 1 move, packed (estimated)"),
     ("worst-case tick, packed goblins", "queue of 5 moves, packed goblins", 5,
      "queue of 10 moves, no goblin", 10, 1 / 3, "queue of 1 move, packed goblins")),
    ("S4 worst case everywhere, goblins packed per instance",
     ("worst-case tick, packed goblins", "queue of 5 moves, packed (estimated)", 5,
      "queue of 10 moves, no goblin", 10, 1.0, "queue of 1 move, packed (estimated)"),
     ("worst-case tick, packed goblins", "queue of 5 moves, packed goblins", 5,
      "queue of 10 moves, no goblin", 10, 1.0, "queue of 1 move, packed goblins")),
]

RIFTS, QUESTS, BREWS = 5, 3, 5


def day(cost, expedition_usd):
    return (RIFTS * expedition_usd + QUESTS * (cost["accept quest"] + cost["claim quest"])
            + BREWS * cost["brew, signature, new pair"])


print(f"Expedition: {MOVES} moves + {FIGHTS} fight actions + {OTHERS} others, plus enter and "
      f"leave. Day: {RIFTS} Rifts, {QUESTS} quests, {BREWS} brews")
print("| Scenario | $ Dojo (Katana) | $ native (devnet) | Native / Dojo | Native × $0.50 | "
      "L2 gas price for native to pass | $ per day, native |")
print("|---|---:|---:|---:|---:|---:|---:|")
for name, d, n in SCENARIOS:
    du, _ = expedition(dojo_cost, *d)
    nu, _ = expedition(native_cost, *n)
    # The L2 part scales with the L2 gas price; DA is small and kept at today's price
    price = P_L2 * THRESHOLD / nu
    print(f"| {name} | {du:.3f} | {nu:.3f} | {nu / du:.2f} | {nu / THRESHOLD:.2f} | "
          f"{price / 1e9:.1f} Gfri | {day(native_cost, nu):.2f} |")
print()
print("S3 and S4 on Dojo use part 1's estimated packed queues; on native every figure is measured.")
