#!/usr/bin/env python3
"""SPK-1: the money of the Sepolia receipts, with SPK-2's method (spikes/SPK-2/money_devnet.py:
same expedition, same scenarios S1 and S2, same break-even and fight-budget formulas), side by side
with the local node's receipts (spikes/SPK-2/devnet-output.txt), both at the same mainnet prices
(prices-output.txt, read by spikes/SPK-2/prices.py). Also the transactions sent and their cost, and
the fixed part of a transaction from the traces.

    python3 spikes/SPK-1/money.py > spikes/SPK-1/money-output.txt
"""
import json
import os
import statistics

HERE = os.path.dirname(os.path.abspath(__file__))
SPK2 = os.path.join(HERE, "..", "SPK-2")
FRI = 1e-18
THRESHOLD = 0.50
TICK = "capped worst-case tick (15 layers, 8 goblins reached), one felt per goblin, checked"

# ---------------------------------------------------------------------------------------------
# Receipts

sepolia_all = [json.loads(line) for line in open(os.path.join(HERE, "measure-output.txt"))]
sepolia_txs = [r for r in sepolia_all if "latency_ms" in r]
deploy_all = [json.loads(line) for line in open(os.path.join(HERE, "deploy-output.txt"))]
deploy_txs = [r for r in deploy_all if "fee" in r]

sepolia = {}
for r in sepolia_txs:
    assert r["status"] == "SUCCEEDED", r["label"]
    sepolia.setdefault(r["label"], []).append(r)

devnet = {}
for line in open(os.path.join(SPK2, "devnet-output.txt")):
    d = json.loads(line)
    if d.get("side") == "native":
        devnet[d["label"]] = d

mainnet = strk = None
for line in open(os.path.join(HERE, "prices-output.txt")):
    d = json.loads(line)
    if d.get("network") == "mainnet" and "l2_gas_fri" in d and mainnet is None:
        mainnet = d
    if d.get("strk_usd_source") == "coingecko":
        strk = d
P_L2, P_DA = mainnet["l2_gas_fri"], mainnet["l1_data_gas_fri"]
STRK_USD = strk["raw"]["starknet"]["usd"]


def one(label):
    """The Sepolia receipt of an action: every repeat must agree (they are identical transactions)."""
    rows = sepolia[label]
    l2 = {r["l2_gas"] for r in rows}
    da = {r["l1_data_gas"] for r in rows}
    assert len(l2) == 1 and len(da) == 1, (label, l2, da)
    return rows[0]


def usd(l2, da):
    return (l2 * P_L2 + da * P_DA) * FRI * STRK_USD


print("Prices (mainnet)")
print(f"  L2 gas {P_L2:,} fri, L1 data gas {P_DA:,} fri ({mainnet['source']}, block {mainnet['block_number']}, "
      f"{mainnet['block_timestamp']}, read {mainnet['read_at']})")
print(f"  STRK ${STRK_USD} ({strk['url']}, read {strk['read_at']})")
print(f"  => 1M L2 gas = ${1e6 * P_L2 * FRI * STRK_USD:.6f}; 1,000 L1 data gas = ${1e3 * P_DA * FRI * STRK_USD:.6f}")
print()

# ---------------------------------------------------------------------------------------------
# Transactions sent and their cost

deploy_fee = sum(int(r["fee"]) for r in deploy_txs)
measure_fee = sum(int(r["fee"]) for r in sepolia_txs)
measured = [r for r in sepolia_txs if r["measured"]]
print("Transactions sent on Sepolia, and their cost (test STRK, the owner's)")
print("| Step | Transactions | Fee (STRK) |")
print("|---|---:|---:|")
print(f"| Declare and deploy (2 declares, 2 deploys) | 4 | "
      f"{sum(int(r['fee']) for r in deploy_txs if r.get('step', '').startswith(('declare', 'deploy'))) * FRI:.4f} |")
print(f"| Link and hub setup | 3 | {sum(int(r['fee']) for r in deploy_txs if r.get('label')) * FRI:.4f} |")
print(f"| Setups (4 queues, 20 board resets) | {len(sepolia_txs) - len(measured)} | "
      f"{sum(int(r['fee']) for r in sepolia_txs if not r['measured']) * FRI:.4f} |")
print(f"| Measured (4 queues, 20 ticks, 25 enter, 25 leave) | {len(measured)} | "
      f"{sum(int(r['fee']) for r in measured) * FRI:.4f} |")
print(f"| **Total** | **{len(deploy_txs) + len(sepolia_txs)}** | **{(deploy_fee + measure_fee) * FRI:.4f}** |")
print()

# ---------------------------------------------------------------------------------------------
# Per action: Sepolia against the local node

ROWS = [
    ("Worst tick under D-127 (capped winding board, owner checked)", TICK),
    ("Queue of 10 moves, 8 goblins following", "queue of 10 moves, checked"),
    ("Queue of 5 moves, 8 goblins following", "queue of 5 moves, checked"),
    ("Queue of 1 move, 8 goblins following", "queue of 1 move, checked"),
    ("Exploring queue: 10 moves, no goblin", "queue of 10 moves, no goblin, checked"),
    ("Enter", "enter"),
    ("Leave", "leave"),
]
print("Per action: receipts on Sepolia (Starknet 0.14.4) and on the local node (starknet-devnet 0.10.0, "
      "SPK-2), native contracts in production form, both at the mainnet prices above")
print("| Action | Sepolia n | Sepolia L2 gas | Devnet L2 gas | Sepolia / devnet | Sepolia L1 data gas | "
      "Devnet L1 data gas | Sepolia fee paid (STRK) | $ Sepolia | $ devnet |")
print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
for name, label in ROWS:
    s, d = one(label), devnet[label]
    fees = [int(r["fee"]) for r in sepolia[label]]
    print(f"| {name} | {len(sepolia[label])} | {s['l2_gas']:,} | {d['l2_gas']:,} | {s['l2_gas'] / d['l2_gas']:.3f} | "
          f"{s['l1_data_gas']} | {d['l1_data_gas']} | {statistics.median(fees) * FRI:.5f} | "
          f"{usd(s['l2_gas'], s['l1_data_gas']):.5f} | {usd(d['l2_gas'], d['l1_data_gas']):.5f} |")
print()

# ---------------------------------------------------------------------------------------------
# The meter: invocation figures of the traces, Sepolia against devnet and snforge


def calls(path):
    out = {}
    for row in open(path).read().split("\n\n")[0].splitlines():
        cells = [c.strip() for c in row.strip("|").split("|")]
        if len(cells) >= 3 and cells[2].replace(",", "").isdigit():
            out.setdefault((cells[0], cells[1]), []).append(int(cells[2].replace(",", "")))
    return out


SNFORGE = calls(os.path.join(SPK2, "native", "snforge-summary.md"))
SNFORGE_KEY = {
    TICK: ("test_tick_capped_worst_case", "Instances.attack", 1),
    "queue of 10 moves, checked": ("test_queue_moves", "Instances.walk", 0),
    "queue of 5 moves, checked": ("test_queue_moves_5", "Instances.walk", 0),
    "queue of 1 move, checked": ("test_queue_moves_1", "Instances.walk", 0),
    "queue of 10 moves, no goblin, checked": ("test_queue_moves_no_goblin", "Instances.walk", 0),
    "enter": ("test_hub_day", "Hub.enter", 0),
    "leave": ("test_hub_day", "Instances.leave", 0),
}
print("The meter: the game's call as metered on Sepolia, on devnet (VM resources) and by snforge in "
      "Sierra gas (the call alone)")
print("| Action | Sepolia game call | Devnet game call (VM resources) | snforge call (Sierra gas) | "
      "Sepolia / devnet | Sepolia / snforge |")
print("|---|---:|---:|---:|---:|---:|")
for name, label in ROWS:
    s = next(r for r in sepolia[label] if "trace" in r)
    game = sum(c["l2_gas"] for c in s["trace"]["game_calls"])
    dv = devnet[label]["trace"]["game_calls"]
    t, c, i = SNFORGE_KEY[label]
    sn = SNFORGE[(t, c)][i]
    print(f"| {name} | {game:,} | {dv:,} | {sn:,} | {game / dv:.3f} | {game / sn:.3f} |")
print()

# ---------------------------------------------------------------------------------------------
# The fixed part of a transaction

print("The non-game remainder of a transaction (Sepolia traces; L2 gas): the receipt minus the game's call, "
      "for these actions and this account (class Sierra 1.7.0, Cairo 2.11.2). The receipt is split into "
      "the invocations the trace attributes (validate, the account's __execute__ without the game call, the "
      "game call, the fee transfer) and two UNATTRIBUTED residuals: trace total minus the invocations, and "
      "receipt minus trace total (expected to be calldata, signature and events: not verified). An observed "
      "remainder, not a universal floor: another account class, calldata or state diff gives another one")
print("| Action | Receipt | Validate | Account __execute__ (without the game call) | Game call | Fee transfer | "
      "Unattributed residual: trace total minus invocations | Unattributed residual: receipt minus trace total | "
      "Non-game remainder (receipt minus game call) |")
print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
fixed = []
for name, label in ROWS:
    s = next(r for r in sepolia[label] if "trace" in r)
    t = s["trace"]
    game = sum(c["l2_gas"] for c in t["game_calls"])
    total = t["trace_resources"]["l2_gas"]
    protocol = total - t["validate"] - t["execute_total"] - t["fee_transfer"]
    size = s["l2_gas"] - total
    rest = s["l2_gas"] - game
    fixed.append(rest)
    print(f"| {name} | {s['l2_gas']:,} | {t['validate']:,} | {t['execute_total'] - game:,} | {game:,} | "
          f"{t['fee_transfer']:,} | {protocol:,} | {size:,} | {rest:,} |")
d = devnet[TICK]["trace"]
print(f"Devnet, same tick: validate {d['validate']:,}, fee transfer {d['fee_transfer']:,}, account execute "
      f"{d['account_execute']:,} (VM resources, not additive).")
print()

# ---------------------------------------------------------------------------------------------
# Expeditions, as SPK-2 §3.3 / money_devnet.py: 180 moves in queues, 100 fights, 20 others, enter, leave

MOVES, FIGHTS, OTHERS = 180, 100, 20


def gas(side, label):
    r = one(label) if side == "sepolia" else devnet[label]
    return (r["l2_gas"], r["l1_data_gas"])


def add(total, count, value):
    return (total[0] + count * value[0], total[1] + count * value[1])


def parts(fight, near_queue, near_len, far_queue, other, near):
    n_near = -(-round(MOVES * near) // near_len)
    n_far = -(-(MOVES - round(MOVES * near)) // 10)
    return [(n_near, near_queue), (n_far, far_queue), (FIGHTS, fight), (OTHERS, other), (1, "enter"), (1, "leave")]


def expedition(side, *scenario):
    total = (0, 0)
    for count, label in parts(*scenario):
        total = add(total, count, gas(side, label))
    return total


SCENARIOS = [
    ("S1 worst case everywhere",
     (TICK, "queue of 5 moves, checked", 5, "queue of 10 moves, no goblin, checked", "queue of 1 move, checked", 1.0)),
    ("S2 mixed (2/3 of the moves exploring)",
     (TICK, "queue of 5 moves, checked", 5, "queue of 10 moves, no goblin, checked", "queue of 1 move, checked", 1 / 3)),
]
print(f"Expedition: {MOVES} moves + {FIGHTS} fight actions + {OTHERS} others, plus enter and leave "
      f"(SPK-2 §3.3); every fight is the worst tick under D-127; native, one felt per goblin, owner checked")
print("| Scenario | Transactions | $ Sepolia | $ devnet (SPK-2) | Sepolia / devnet | Sepolia × $0.50 | "
      "Break-even L2 gas price, Sepolia | L2 gas per expedition, Sepolia | Fight budget, Sepolia |")
print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
for name, sc in SCENARIOS:
    st, dt = expedition("sepolia", *sc), expedition("devnet", *sc)
    su, du = usd(*st), usd(*dt)
    n_tx = sum(c for c, _ in parts(*sc))
    da = st[1] * P_DA * FRI * STRK_USD
    price = (THRESHOLD - da) / (st[0] * STRK_USD * FRI)
    # Fight budget (SPK-2 C-6): the fight's L2 gas at which the expedition costs $0.50
    fixed_usd = 0.0
    for count, label in parts(*sc):
        l2, dg = gas("sepolia", label)
        fixed_usd += usd(0, count * dg) if label == TICK else usd(count * l2, count * dg)
    budget = (THRESHOLD - fixed_usd) / (FIGHTS * P_L2 * STRK_USD * FRI)
    print(f"| {name} | {n_tx} | **{su:.3f}** | {du:.3f} | {su / du:.3f} | {su / THRESHOLD:.2f} | "
          f"{price / 1e9:.2f} Gfri | {st[0]:,} | {budget:,.0f} |")
print()
print("Not measured on Sepolia (out of the brief's list): goblins packed per instance (SPK-2's S3, S4) and "
      "the serpentine queue (S5); hub actions (quests, brewing), so no cost per day.")
print()

# ---------------------------------------------------------------------------------------------
# The tip (fix loop 1, finding 7). The fee charged is
#   L2 gas × (block L2 gas price + tip) + L1 data gas × block data price + L1 gas × block L1 price.
# Checked on every Sepolia receipt, then the projection's zero-tip assumption and the tip's effect.

matches, total_tip_fri = 0, 0
for r in sepolia_txs + [r for r in deploy_txs if r.get("type") == "INVOKE"]:
    tip = int(r["tip"], 16)
    expected = (r["l2_gas"] * (int(r["block_l2_gas_fri"]) + tip) + r["l1_data_gas"] * int(r["block_l1_data_gas_fri"])
                + r["l1_gas"] * int(r["block_l1_gas_fri"]))
    matches += expected == int(r["fee"])
    total_tip_fri += r["l2_gas"] * tip
checked = len(sepolia_txs) + len([r for r in deploy_txs if r.get("type") == "INVOKE"])
TIP = int(one(TICK)["tip"], 16)
print(f"Fee formula with the tip: actual fee = L2 gas × (block L2 price + tip) + L1 data gas × data price + "
      f"L1 gas × L1 price. It reproduces the fee to the fri on {matches} of {checked} invoke receipts. The tip was "
      f"{TIP / 1e9} Gfri per L2 gas (starknet.js recommended); it cost {total_tip_fri / 1e18:.4f} STRK of the run's fees.")
print(f"The dollar projections above assume a ZERO tip at mainnet prices. At the tip this run paid "
      f"({TIP / 1e9} Gfri):")
print("| Scenario | L2 gas per expedition | $ without tip | Tip's effect | $ with tip |")
print("|---|---:|---:|---:|---:|")
for name, sc in SCENARIOS:
    st = expedition("sepolia", *sc)
    tip_usd = st[0] * TIP * FRI * STRK_USD
    print(f"| {name} | {st[0]:,} | {usd(*st):.3f} | +{tip_usd:.4f} | {usd(*st) + tip_usd:.3f} |")
print()

ACTIONS = 300
DA_REF = one(TICK)["l1_data_gas"]
BUDGET_L2 = (THRESHOLD / ACTIONS - DA_REF * P_DA * FRI * STRK_USD) / (P_L2 * STRK_USD * FRI)
print(f"Equal-allocation reference: $0.50 / 300 = ${THRESHOLD / ACTIONS:.6f} per action = {BUDGET_L2:,.0f} L2 gas "
      f"with {DA_REF} L1 data gas (zero tip). Observed non-game remainder, for these actions and this account "
      f"only: {min(fixed):,} to {max(fixed):,} L2 gas ({min(fixed) / BUDGET_L2:.2f}× to {max(fixed) / BUDGET_L2:.2f}× "
      f"the reference). If every transaction carried at least the smallest observed remainder, the game's own "
      f"call could average at most {BUDGET_L2 - min(fixed):,.0f} L2 gas under equal allocation. That derived budget "
      f"holds only for this account class and transactions like these, not as a protocol floor.")
