#!/usr/bin/env python3
"""FND-04: what a changed storage slot costs, on SPK-1's and SPK-1b's Sepolia receipts.

Reads `traces.jsonl` (trace.py) and `devnet-output.txt` (devnet_trace.py); no network. Prints the
tables of docs/research/FND-04-slots.md:

    python3 spikes/FND-04/analyse.py > spikes/FND-04/slots-output.txt

Terms (SPK-1 §4's method):
- invocations: validate + execute (the account's `__execute__`, the game call inside) + fee transfer;
- res1: the trace's total minus the invocations; res2: the receipt minus the trace's total;
- felts: the transaction's calldata and signature, in felts;
- slots: the storage slots of the state diff, split by their value at the block before: *new*
  (it was 0), *overwritten* (non-zero to non-zero), *zeroed* (non-zero to 0).
"""
import json
import os
import statistics
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
PER_FELT = 5_120  # found below: per felt of calldata, inside res1 (controlled pairs)
# An assumed normalisation, not an identified term: every transaction here carries a signature of
# 2 felts, so the signature's price cannot be separated from the constant. BASE is the constant
# *if* a signature felt costs what a calldata felt costs (base 14,880 with a free signature fits
# the same data).
SIG_FELTS = 2
BASE = 4_640
GAME_CONTRACTS = {"Hub", "Instances"}


def game_calls(node):
    """The inclusive L2 gas of the topmost invocations of the game's contracts, each counted once."""
    if not node:
        return 0
    if node["to"] in GAME_CONTRACTS:
        return node["l2_gas"]
    return sum(game_calls(c) for c in node.get("calls", []))


def load():
    rows = []
    for line in open(os.path.join(HERE, "traces.jsonl")):
        d = json.loads(line)
        sd = d["state_diff"]
        ent = [(c["contract"], e) for c in sd["storage"] for e in c["entries"]]
        inv = sum(x["l2_gas"] for x in (d["validate"], d["execute"], d["fee_transfer"]) if x)
        game = game_calls(d["execute"]) if d["type"] == "INVOKE" else 0
        new = sum(e["prev_zero"] for _, e in ent)
        zeroed = sum((not e["prev_zero"]) and e["value_zero"] for _, e in ent)
        over = len(ent) - new - zeroed
        per_contract = OrderedDict()
        for c, e in sorted(ent, key=lambda x: x[0]):
            k = "n" if e["prev_zero"] else ("z" if e["value_zero"] else "o")
            per_contract.setdefault(c, {"n": 0, "o": 0, "z": 0})[k] += 1
        felts = d["calldata_felts"] + d["signature_felts"]
        res1 = d["trace_total"]["l2_gas"] - inv
        rows.append({
            "source": d["source"], "label": d["label"], "type": d["type"], "tx": d["tx"],
            "sender": d["sender"],
            "receipt": d["receipt"]["l2_gas"], "da": d["receipt"]["l1_data_gas"],
            "validate": d["validate"]["l2_gas"] if d["validate"] else 0,
            "execute": d["execute"]["l2_gas"] if d["execute"] else 0,
            "game": game,
            "fee_transfer": d["fee_transfer"]["l2_gas"] if d["fee_transfer"] else 0,
            "res1": res1, "res2": d["receipt"]["l2_gas"] - d["trace_total"]["l2_gas"],
            "felts": felts, "events": d["receipt"]["events"],
            "event_felts": d["receipt"]["event_keys"] + d["receipt"]["event_data"],
            "new": new, "over": over, "zeroed": zeroed, "slots": len(ent),
            "per_contract": per_contract,
            "nonces": sd["nonces"], "deployed": sd["deployed_contracts"], "declared": sd["declared_classes"],
            "state": res1 - PER_FELT * felts - BASE,
        })
    return rows


def signature(r):
    return (r["receipt"], r["res1"], r["res2"], r["validate"], r["execute"], r["game"], r["fee_transfer"],
            r["felts"], r["new"], r["over"], r["zeroed"])


def groups(rows):
    g = OrderedDict()
    for r in rows:
        g.setdefault((r["source"].replace(" deploy", ""), r["label"]), []).append(r)
    return g


def fmt(n):
    return f"{n:,}"


def slots_text(r):
    parts = []
    for c, k in r["per_contract"].items():
        s = "/".join(f"{v}{t}" for t, v in (("new", k["n"]), ("over", k["o"]), ("zero", k["z"])) if v)
        parts.append(f"{c} {s}")
    return "; ".join(parts)


def main():
    rows = load()
    g = groups(rows)
    print(f"# FND-04 slots — {len(rows)} Sepolia transactions (SPK-1 deploy 7, SPK-1 measure 98, SPK-1b 44)\n")

    print("## 1. Every group of identical transactions\n")
    print("A group is one label; `identical` says whether all its transactions have the same figures.\n")
    print("| Source | Label | n | identical | Receipt | Validate | Execute (with game) | Game call | Fee transfer "
          "| res1 | res2 | Felts | Slots new/over/zero | Per contract | Nonces |")
    print("|---|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|")
    for (src, label), rs in g.items():
        r = rs[0]
        same = len({signature(x) for x in rs}) == 1
        print(f"| {src} | {label} | {len(rs)} | {'yes' if same else 'NO'} | {fmt(r['receipt'])} | {fmt(r['validate'])} "
              f"| {fmt(r['execute'])} | {fmt(r['game'])} | {fmt(r['fee_transfer'])} | {fmt(r['res1'])} | {fmt(r['res2'])} "
              f"| {r['felts']} | {r['new']}/{r['over']}/{r['zeroed']} | {slots_text(r)} | {', '.join(r['nonces'])} |")
        if not same:
            for x in rs:
                if signature(x) != signature(r):
                    print(f"|  | differs: {x['tx']} |  |  | {fmt(x['receipt'])} | {fmt(x['validate'])} | {fmt(x['execute'])} "
                          f"| {fmt(x['game'])} | {fmt(x['fee_transfer'])} | {fmt(x['res1'])} | {fmt(x['res2'])} | {x['felts']} "
                          f"| {x['new']}/{x['over']}/{x['zeroed']} | {slots_text(x)} | |")

    # Distinct shapes, Sierra-metered (the AVNU relayer's case D is metered by steps: SPK-1b §3), no declare.
    distinct = OrderedDict()
    for r in rows:
        if r["type"] == "DECLARE" or r["label"].startswith("D burner"):
            continue
        distinct.setdefault(signature(r), r)
    shapes = list(distinct.values())

    print("\n## 2. res1 = BASE + PER_FELT × felts + the state part (an accounting identity, not a model)\n")
    print(f"BASE = {fmt(BASE)}, PER_FELT = {fmt(PER_FELT)}. The *state part* is res1 − BASE − PER_FELT × felts, "
          "felts counting calldata and the signature. **The split between BASE and the signature is an assumed "
          f"normalisation**: every transaction carries {SIG_FELTS} signature felts, so only BASE + "
          f"{SIG_FELTS} × (the signature felt's price) is identified, here {fmt(BASE + SIG_FELTS * PER_FELT)}. "
          "Every distinct Sierra-metered shape (declares and AVNU's step-metered case D left out):\n")
    print("| Label | Felts (calldata + signature) | Event felts | res1 | State part | Slots new/over/zero | Contracts with storage | State part mod 2,000 |")
    print("|---|---:|---:|---:|---:|---|---:|---:|")
    for r in shapes:
        print(f"| {r['label']} | {r['felts']} | {r['event_felts']} | {fmt(r['res1'])} | {fmt(r['state'])} "
              f"| {r['new']}/{r['over']}/{r['zeroed']} | {len(r['per_contract'])} | {r['state'] % 2000} |")
    # Which constants keep every state part a multiple of 2,000, for a signature felt priced 0 or like calldata?
    print("\nObserved divisibility, not predictive accuracy: the normalisations below all leave every state part "
          "a multiple of 2,000 (a property of these receipts); how well slots *predict* the state part is §4.\n")
    print("| Signature felt priced at | Constants in 0..20,000 that keep every state part a multiple of 2,000 |")
    print("|---:|---|")
    for sig_price in (0, PER_FELT):
        ok = [b for b in range(0, 20_001, 40)
              if all((r["res1"] - PER_FELT * (r["felts"] - SIG_FELTS) - sig_price * SIG_FELTS - b) % 2000 == 0
                     for r in shapes)]
        print(f"| {fmt(sig_price)} | {', '.join(fmt(b) for b in ok)} |")

    by_label = {r["label"]: r for r in shapes}

    def first(label, **kw):
        for r in shapes:
            if r["label"] == label and all(r[k] == v for k, v in kw.items()):
                return r
        raise KeyError(label)

    print("\n## 3. Controlled pairs: one thing differs\n")
    print("| Pair (b − a) | What differs | Δ res1 | Δ state part | Per unit |")
    print("|---|---|---:|---:|---:|")

    def pair(a, b, what, units):
        dr, ds = b["res1"] - a["res1"], b["state"] - a["state"]
        per = ds / units if what != "calldata" else dr / units
        print(f"| {b['label']} − {a['label']} | {what} ({units}) | {fmt(dr)} | {fmt(ds)} | {fmt(round(per))} |")
        return per

    tick = by_label["capped worst-case tick (15 layers, 8 goblins reached), one felt per goblin, checked"]
    q10 = by_label["queue of 10 moves, checked"]
    q5 = by_label["queue of 5 moves, checked"]
    q1 = by_label["queue of 1 move, checked"]
    explo = by_label["queue of 10 moves, no goblin, checked"]
    board_again = first("setup board 31", new=0)
    pair(q5, q10, "calldata", q10["felts"] - q5["felts"])
    pair(tick, q5, "calldata", q5["felts"] - tick["felts"])
    print(f"| {tick['label']} − setup board 31 (again) | 2 felts of calldata, and one event more "
          f"({tick['event_felts'] - board_again['event_felts']} event felts) | {fmt(tick['res1'] - board_again['res1'])} "
          f"| {fmt(tick['state'] - board_again['state'])} | events: 0 in res1 |")
    news = []
    news.append(pair(first("deploy Hub"), first("deploy Instances"), "new slot", 1))
    news.append(pair(first("give adventurer 3 back to the owner"), first("fund the burner, give it adventurer 3"),
                     "new slot (the burner's STRK balance)", 1))
    news.append(pair(first("link hub"), first("setup hub"), "new slots", 5))
    news.append(pair(first("setup queue 21"), first("setup queue 18"), "new slots", 64))
    news.append(pair(first("leave"), first("C burner via relayer: leave"),
                     "new slot (the SNIP-9 nonce) in one contract more", 1))
    news.append(pair(first("enter"), first("C burner via relayer: enter"),
                     "new slot (the SNIP-9 nonce) in one contract more", 1))
    overs = []
    overs.append(pair(q1, q10, "overwritten slot", 1))
    overs.append(pair(explo, q10, "overwritten slots", 8))
    overs.append(pair(first("give adventurer 3 back to the owner"), first("leave"), "zeroed slots", 4))
    ret = first("return the burner's STRK")
    print(f"| return the burner's STRK (alone) | 3 overwritten STRK balances, one contract | — | {fmt(ret['state'])} "
          f"| {fmt(ret['state'] // 3)} |")
    give = first("give adventurer 3 back to the owner")
    print(f"| give adventurer 3 back (alone) | 2 STRK balances + 1 Hub slot, two contracts | — | {fmt(give['state'])} "
          f"| {fmt(give['state'] // 3)} |")

    print("\n## 4. One price per new slot and one per other changed slot: least squares over the shapes\n")
    # state ≈ a·new + b·(over + zeroed), no intercept (BASE is already out).
    xs = [(r["new"], r["over"] + r["zeroed"], r["state"]) for r in shapes]
    s11 = sum(n * n for n, _, _ in xs)
    s12 = sum(n * o for n, o, _ in xs)
    s22 = sum(o * o for _, o, _ in xs)
    t1 = sum(n * y for n, _, y in xs)
    t2 = sum(o * y for _, o, y in xs)
    det = s11 * s22 - s12 * s12
    a = (t1 * s22 - t2 * s12) / det
    b = (s11 * t2 - s12 * t1) / det
    print(f"Fit over {len(xs)} shapes: **new slot {fmt(round(a))}**, **overwritten or zeroed slot {fmt(round(b))}** "
          "(L2 gas, beyond the write's computation, once per slot and per transaction).\n")
    print("| Label | Slots new/other | State part | Fitted | Error | Error % |")
    print("|---|---|---:|---:|---:|---:|")
    worst = 0
    for r in shapes:
        fit = a * r["new"] + b * (r["over"] + r["zeroed"])
        err = r["state"] - fit
        worst = max(worst, abs(err))
        pct = 100 * err / r["state"] if r["state"] else 0
        print(f"| {r['label']} | {r['new']}/{r['over'] + r['zeroed']} | {fmt(r['state'])} | {fmt(round(fit))} "
              f"| {fmt(round(err))} | {pct:+.1f} % |")
    print(f"\nLargest error: {fmt(round(worst))} L2 gas.")

    print("\n## 5. The figure per slot our data supports\n")
    print("| Kind of slot | From the controlled pairs: min / median / max | Least squares | quiver (D-135) |")
    print("|---|---:|---:|---:|")
    med = statistics.median  # the conventional median: the mean of the two middle values when even
    print(f"| New (its value was 0) | {fmt(round(min(news)))} / {med(news):,.1f} / {fmt(round(max(news)))} "
          f"| {fmt(round(a))} | 402,000 |")
    others = overs + [ret["state"] / 3, give["state"] / 3]
    print(f"| Overwritten or zeroed | {fmt(round(min(others)))} / {med(others):,.1f} / {fmt(round(max(others)))} "
          f"| {fmt(round(b))} | — |")

    print("\n## 6. SPK-1 §4's non-game remainder, rebuilt\n")
    print("Non-game remainder = receipt − game call = validate + account execution + fee transfer + res1 + res2.\n")
    print("| Label | Non-game remainder | Validate + account execution + fee transfer | res2 | BASE + felts | New slots | Other slots |")
    print("|---|---:|---:|---:|---:|---:|---:|")
    for lbl in ("capped worst-case tick (15 layers, 8 goblins reached), one felt per goblin, checked",
                "queue of 10 moves, checked", "queue of 5 moves, checked", "queue of 1 move, checked",
                "queue of 10 moves, no goblin, checked", "enter", "leave", "B burner direct: enter",
                "B burner direct: leave", "C burner via relayer: leave"):
        r = by_label.get(lbl) or first(lbl)
        rem = r["receipt"] - r["game"]
        fixed = r["validate"] + (r["execute"] - r["game"]) + r["fee_transfer"]
        print(f"| {lbl} | {fmt(rem)} | {fmt(fixed)} | {fmt(r['res2'])} | {fmt(BASE + PER_FELT * r['felts'])} "
              f"| {r['new']} × ≈ {fmt(round(a))} | {r['over'] + r['zeroed']} × ≈ {fmt(round(b))} |")

    print("\n## 7. SPK-2's native entrypoints on the local node (devnet_trace.py)\n")
    print("| Entrypoint (SPK-2 label) | Game slots new/over/zero | Fee token slots | Receipt (devnet meter) |")
    print("|---|---|---|---:|")
    for line in open(os.path.join(HERE, "devnet-output.txt")):
        d = json.loads(line)
        if d.get("side") != "native":
            continue
        game = [c for c in d["state_diff"]["storage"] if not c["contract"].startswith("0x4718")]
        fee = [c for c in d["state_diff"]["storage"] if c["contract"].startswith("0x4718")]
        gs = f"{sum(c['new'] for c in game)}/{sum(c['overwritten'] for c in game)}/{sum(c['zeroed'] for c in game)}"
        fs = sum(c["slots"] for c in fee)
        print(f"| {d['label']} | {gs} | {fs} | {fmt(d['l2_gas'])} |")


if __name__ == "__main__":
    main()
