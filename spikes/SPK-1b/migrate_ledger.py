#!/usr/bin/env python3
"""SPK-1b fix loop 1: rewrites the ledger of the run of 2026-09-28 into the format of `makeLedger`.
The ledger before fix loop 1 held one row per transaction, written after its receipt (kept as
ledger-v1.jsonl); the new one holds a reservation, the hash and a settlement per transaction, with
the receipt's fee and the owner's spending apart.

- Payer, from the label: the owner's account (A, the funding, C, the adventurer given back), the
  burner (its deploy, B, the return of its STRK), or the burner through AVNU (D).
- Spending: the receipt fee, except through AVNU, where it is the burner's net STRK transfers in
  the receipt (what it sent minus the refund). Each of these is checked against the burner's
  balance before and after, as measured in the run (`paid to AVNU` lines); a mismatch stops.
- A reservation's maximum is not known for these rows (they were written after the fact): it is
  set to the settled amount and marked `legacy`. Every row is settled, so the maximum counts for
  nothing.

    python3 spikes/SPK-1b/migrate_ledger.py      (reads ledger-v1.jsonl, writes ledger.jsonl)
"""
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
STRK = 0x04718F5A0FC34CC1AF16A1CDEE98FFB20C31F5CD61D6AB07201858F4287C938D
TRANSFER = 0x99CD8BDE557814842A3121E8DDFD433A539B8C9F14BF31EBF108D12E6196E9


def payer(label):
    if label.startswith("D "):
        return "burner via AVNU"
    if label.startswith(("B ", "deploy the burner", "return the burner")):
        return "burner"
    return "owner"


def net_transfer(record, address):
    out = back = 0
    seen = False
    for e in record.get("event_list", []):
        if int(e["from"], 16) != STRK or len(e["keys"]) != 3 or int(e["keys"][0], 16) != TRANSFER:
            continue
        amount = int(e["data"][0], 16) + (int(e["data"][1], 16) << 128)
        if int(e["keys"][1], 16) == address:
            out += amount
            seen = True
        if int(e["keys"][2], 16) == address:
            back += amount
    return out - back if seen else None


records, paid, burner = {}, {}, None
for path in [os.path.join(HERE, "measure-output.txt")] + sorted(glob.glob(os.path.join(HERE, "measure-d-output.txt*"))):
    for line in open(path):
        r = json.loads(line)
        if r.get("step") == "start" and r.get("burner"):
            burner = int(r["burner"], 16)
        if r.get("step") == "paid to AVNU":
            paid[r["tx"]] = int(r["paid_by_burner_fri"])
        elif "l2_gas" in r:
            records[r["tx"]] = r

old = [json.loads(l) for l in open(os.path.join(HERE, "ledger-v1.jsonl"))]
out = []
for n, row in enumerate(old, 1):
    who = payer(row["label"])
    fee = int(row["fee"])
    if who == "burner via AVNU":
        spent = net_transfer(records[row["tx"]], burner)
        if spent is None or spent != paid[row["tx"]]:
            sys.exit(f"{row['tx']}: net transfers {spent} and the measured balance change {paid[row['tx']]} disagree")
        how = "the payer's net STRK transfers in the receipt (equal to its balance change measured in the run)"
    else:
        spent, how = fee, "receipt fee"
    ident = f"{row['at']}#{n}"
    out.append({"kind": "reserve", "id": ident, "label": row["label"], "payer": who, "payer_address": None,
                "max_fee": str(spent), "paymaster": who == "burner via AVNU", "nonce": None, "legacy": True, "at": row["at"]})
    out.append({"kind": "sent", "id": ident, "tx": row["tx"], "legacy": True, "at": row["at"]})
    out.append({"kind": "settle", "id": ident, "tx": row["tx"], "fee": str(fee), "spent": str(spent), "how": how,
                "legacy": True, "at": row["at"]})
with open(os.path.join(HERE, "ledger.jsonl"), "w") as f:
    for e in out:
        f.write(json.dumps(e) + "\n")
fees = sum(int(r["fee"]) for r in old)
spent = sum(int(e["spent"]) for e in out if e["kind"] == "settle")
print(f"{len(old)} transactions migrated; receipt fees {fees / 1e18:.4f} STRK; the owner's money spent {spent / 1e18:.4f} STRK "
      f"(AVNU receipts {sum(int(r['fee']) for r in old if r['label'].startswith('D ')) / 1e18:.4f} replaced by the burner's "
      f"payments {sum(paid.values()) / 1e18:.4f})")
