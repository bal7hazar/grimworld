#!/usr/bin/env python3
"""SPK-1b: the non-game remainder of a transaction per case, with SPK-1's method (§4 of
docs/research/SPK-1-sepolia.md), from the committed, redacted receipts and traces.

    python3 spikes/SPK-1b/analyse.py > spikes/SPK-1b/analyse-output.txt

- The game call is the `enter` or `leave` invocation, wherever it sits in the tree.
- The account's execution (without the game call): `__execute__` minus the game call. For C and
  D it is split into its parts: the relayer's own `__execute__`, AVNU's forwarder, the burner's
  `execute_from_outside_v2` (signature check, nonce, and its own work) and the STRK transfers of
  the paymaster's fee.
- Two UNATTRIBUTED residuals, as in SPK-1: trace total minus the invocations (validate, execute,
  constructor, fee transfer), and receipt minus trace total.
- The account's fixed part: validate + the account's execution without the game call + fee
  transfer + the second residual. SPK-1's "about 1.09M" is this sum for the owner's account. The
  first residual is left out of it, because it is the same for the same action whatever the account
  (see the table): it follows the state the action writes, not the account.
- Every repeat of a case must give the same figures; a repeat that differs is listed.
"""
import glob
import json
import os
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
NAMES = json.load(open(os.path.join(HERE, "selectors.json")))
FILES = [os.path.join(HERE, "measure-output.txt")] + sorted(glob.glob(os.path.join(HERE, "measure-d-output.txt*")))
SPK1 = {"enter": (3_927_367, 927_212), "leave": (2_030_065, 682_000)}  # SPK-1 §4: receipt, game call
CASES = {
    "A owner": "A. The owner's account (Braavos, Sierra 1.7.0, Cairo 2.11.2), as SPK-1",
    "B burner direct": "B. Burner, direct (OpenZeppelin AccountUpgradeable v3.0.0, Cairo 2.13.1)",
    "C burner via relayer": "C. Burner, SNIP-9 outside execution, a relayer of our own pays (the owner's account)",
    "D burner via AVNU": "D. Burner, AVNU's public SNIP-29 paymaster, default fee mode (the burner pays AVNU in STRK)",
}


def name(node):
    return NAMES.get(hex(int(node["selector"], 16)), node["selector"][:10])


def find(node, wanted):
    if node is None:
        return None
    if name(node) == wanted:
        return node
    for c in node["calls"]:
        hit = find(c, wanted)
        if hit:
            return hit
    return None


def split(r, action):
    t = r["trace"]
    tree = t["tree"]
    game = find(tree["execute"], action)["l2_gas"]
    parts = {"validate": t["validate"], "fee transfer": t["fee_transfer"]}
    top = tree["execute"]
    kids = sum(c["l2_gas"] for c in top["calls"])
    parts["account __execute__ (own)"] = top["l2_gas"] - kids
    outside = find(top, "execute_from_outside_v2")
    if outside is None:
        pass  # A and B: the game call is the only child
    else:
        forwarder = top["calls"][0] if name(top["calls"][0]) == "execute" else None
        if forwarder:
            fwd_kids = sum(c["l2_gas"] for c in forwarder["calls"])
            parts["AVNU forwarder (own)"] = forwarder["l2_gas"] - fwd_kids
            parts["AVNU forwarder: STRK transfers and balanceOf"] = fwd_kids - outside["l2_gas"]
        sig = find(outside, "is_valid_signature")["l2_gas"]
        fee_to_avnu = sum(c["l2_gas"] for c in outside["calls"] if name(c) == "transfer")
        parts["burner execute_from_outside_v2: is_valid_signature"] = sig
        if forwarder:
            parts["burner execute_from_outside_v2: STRK transfer to AVNU"] = fee_to_avnu
        parts["burner execute_from_outside_v2 (own: nonce, checks)"] = outside["l2_gas"] - sig - fee_to_avnu - game
    total = t["trace_resources"]["l2_gas"]
    first = total - t["validate"] - t["execute_total"] - t["fee_transfer"]
    second = r["l2_gas"] - total
    account_exec = t["execute_total"] - game
    return {
        "receipt": r["l2_gas"], "validate": t["validate"], "account_exec": account_exec, "game": game,
        "fee_transfer": t["fee_transfer"], "residual_trace": first, "residual_receipt": second,
        "remainder": r["l2_gas"] - game,
        "fixed": t["validate"] + account_exec + t["fee_transfer"] + second,
        "l1_data_gas": r["l1_data_gas"], "fee": int(r["fee"]), "parts": parts,
        "block_l2_fri": int(r["block_l2_gas_fri"]), "block_da_fri": int(r["block_l1_data_gas_fri"]),
    }


records, paid = [], {}
for path in FILES:
    for line in open(path):
        r = json.loads(line)
        if r.get("step") == "paid to AVNU":
            paid[r["tx"]] = int(r["paid_by_burner_fri"])
        elif "l2_gas" in r:
            records.append(r)

rows = defaultdict(list)
for r in records:
    for case in CASES:
        if r["label"].startswith(case):
            action = r["label"].rsplit(": ", 1)[1]
            s = split(r, action)
            s["tx"] = r["tx"]
            s["paid"] = paid.get(r["tx"])
            rows[(case, action)].append(s)

print("# SPK-1b: the non-game remainder of a transaction per case (L2 gas, Sepolia, 2026-09-28)\n")
print(f"Receipts read: {len(records)} (the {len(records)} transactions of ledger.jsonl), from {len(FILES)} output files\n")
KEYS = ["receipt", "validate", "account_exec", "game", "fee_transfer", "residual_trace", "residual_receipt", "remainder",
        "fixed", "l1_data_gas"]
print("| Case | Action | n | Receipt | Validate | Account execution (without the game call) | Game call | Fee transfer | "
      "Unattributed: trace total minus invocations | Unattributed: receipt minus trace total | **Non-game remainder** | "
      "Account's fixed part | L1 data gas | Fee (STRK) |")
print("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
summary = {}
for case in CASES:
    for action in ("enter", "leave"):
        group = rows[(case, action)]
        first = group[0]
        variants = [g for g in group if any(g[k] != first[k] for k in KEYS)]
        summary[(case, action)] = first
        fee = sum(g["fee"] for g in group) / len(group) / 1e18
        print(f"| {case} | {action} | {len(group)} | " + " | ".join(
            f"**{first[k]:,}**" if k == "remainder" else f"{first[k]:,}" for k in KEYS) + f" | {fee:.4f} |")
        for v in variants:
            print(f"|  ↳ variant {v['tx'][:12]}… | {action} | 1 | " + " | ".join(f"{v[k]:,}" for k in KEYS) + f" | {v['fee'] / 1e18:.4f} |")

print("\nThe account's execution, split (first repeat of each case):\n")
for case in ("C burner via relayer", "D burner via AVNU"):
    for action in ("enter", "leave"):
        s = summary[(case, action)]
        print(f"- {case}, {action}: " + "; ".join(f"{k} {v:,}" for k, v in s["parts"].items()))

print("\nAgainst SPK-1 and against the reference measured today (A):\n")
for action in ("enter", "leave"):
    receipt, game = SPK1[action]
    a = summary[("A owner", action)]
    print(f"- {action}: SPK-1 receipt {receipt:,}, game call {game:,}, remainder {receipt - game:,}; today A: receipt "
          f"{a['receipt']:,}, game {a['game']:,}, remainder {a['remainder']:,} ({'identical' if a['receipt'] == receipt else 'DIFFERENT'})")
    for case in CASES:
        s = summary[(case, action)]
        print(f"  - {case}: remainder {s['remainder']:,} = {s['remainder'] / a['remainder']:.2f}× A's; account's fixed part "
              f"{s['fixed']:,} = {s['fixed'] / a['fixed']:.2f}× A's ({a['fixed']:,}); difference from SPK-1's 1.09M: "
              f"{s['fixed'] - 1_090_000:+,}")

print("\nThe floor no account removes (leave, B): fee transfer + second residual = "
      f"{summary[('B burner direct', 'leave')]['fee_transfer'] + summary[('B burner direct', 'leave')]['residual_receipt']:,}; "
      "with a zero-cost account (no validation, no execution) the account's fixed part could not go below it, "
      f"{(summary[('A owner', 'leave')]['fixed']) / (summary[('B burner direct', 'leave')]['fee_transfer'] + summary[('B burner direct', 'leave')]['residual_receipt']):.2f}× "
      "smaller than A's at best.")

print("\nMoney per action (average fee in STRK at the blocks' prices; D also what the burner paid AVNU):\n")
for case in CASES:
    for action in ("enter", "leave"):
        group = rows[(case, action)]
        fee = sum(g["fee"] for g in group) / len(group) / 1e18
        line = f"- {case}, {action}: receipt fee {fee:.4f} STRK"
        if group[0]["paid"] is not None:
            p = sum(g["paid"] for g in group) / len(group) / 1e18
            line += f" (paid by AVNU's relayer); the burner paid AVNU {p:.4f} STRK ({p / fee:.2f}× the receipt fee)"
        print(line)
prices = sorted({(s["block_l2_fri"], s["block_da_fri"]) for g in rows.values() for s in g})
print(f"\nBlock prices over the run: L2 gas {min(p[0] for p in prices):,} to {max(p[0] for p in prices):,} fri; "
      f"L1 data gas {min(p[1] for p in prices):,} to {max(p[1] for p in prices):,} fri")

# The transactions and their cost (AC-3)
ledger = [json.loads(l) for l in open(os.path.join(HERE, "ledger.jsonl"))]
by_type = defaultdict(lambda: [0, 0])
for row in ledger:
    by_type[row["label"].split(":")[0]][0] += 1
    by_type[row["label"].split(":")[0]][1] += int(row["fee"])
print(f"\nLedger: {len(ledger)} transactions, receipt fees {sum(int(r['fee']) for r in ledger) / 1e18:.4f} STRK")
for label, (n, fee) in by_type.items():
    print(f"- {label}: {n}, {fee / 1e18:.4f} STRK")
avnu_receipts = sum(int(r["fee"]) for r in ledger if r["label"].startswith("D "))
avnu_paid = sum(paid.values())
print(f"Of which paid by AVNU's relayers (case D receipts): {avnu_receipts / 1e18:.4f} STRK; paid to AVNU by the burner "
      f"instead: {avnu_paid / 1e18:.4f} STRK. The owner's money spent (the other receipts + what the burner paid AVNU): "
      f"{(sum(int(r['fee']) for r in ledger) - avnu_receipts + avnu_paid) / 1e18:.4f} STRK, plus what stays in the burner")
