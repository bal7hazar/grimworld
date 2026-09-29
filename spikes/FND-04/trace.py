#!/usr/bin/env python3
"""Read the trace, the receipt and the state diff of every Sepolia transaction SPK-1 and SPK-1b
sent, and write one redacted record per transaction to `traces.jsonl`. Reads only (`rpc.py`).

For every storage slot the transaction changed, it also reads the slot's value at the block
before, to tell a slot written for the first time (previous value 0) from one overwritten.

The owner's account address is never written or printed: it is learned from the transactions'
sender in memory and replaced by `<ACCOUNT>`; the STRK token's storage keys are replaced by
labels (a balance key is derived from the holder's address). The run checks its own output for
the address before it ends, and fails if it is found.

    python3 spikes/FND-04/trace.py            # resumes: transactions already in traces.jsonl are kept
"""
import json
import os
import sys
import time

from rpc import Rpc, RpcError

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "traces.jsonl")
ENDPOINT = "https://starknet-sepolia-rpc.publicnode.com"  # the one of prices.py's list that returns state diffs

HUB = 0x98E5E98DD076C62AD0F89C2931D29BE06A227A4EF2901B42E33A1BB5015300
INSTANCES = 0x408DBC81E3D39EF65EE9393464F2DEE3CCE13DF43F9E65EDDA07D4C63393A84
STRK = 0x4718F5A0FC34CC1AF16A1CDEE98FFB20C31F5CD61D6AB07201858F4287C938D
BURNER = 0x65A24BCFA16F9F0647BAC9C62A043CB7004F6632E4978AB38BFE865FFFD2716  # SPK-1b, public in its output
GAME = {HUB: "Hub", INSTANCES: "Instances"}


def spk1_transactions():
    """(source, label, measured, tx) of every transaction SPK-1 sent, in order."""
    out = []
    for line in open(os.path.join(ROOT, "spikes/SPK-1/deploy-output.txt")):
        d = json.loads(line)
        if "tx" in d and not d.get("step", "").endswith(" sent"):
            out.append(("SPK-1 deploy", d.get("label") or d["step"], False, d["tx"]))
    for line in open(os.path.join(ROOT, "spikes/SPK-1/measure-output.txt")):
        d = json.loads(line)
        if "tx" in d:
            out.append(("SPK-1", d["label"], bool(d.get("measured")), d["tx"]))
    return out


def spk1b_transactions():
    """(source, label, measured, tx) of the 44 SPK-1b transactions, from its ledger."""
    labels, out = {}, []
    for line in open(os.path.join(ROOT, "spikes/SPK-1b/ledger.jsonl")):
        d = json.loads(line)
        if d["kind"] == "reserve":
            labels[d["id"]] = d["label"]
        elif d["kind"] == "sent":
            label = labels[d["id"]]
            measured = label[:2] in ("A ", "B ", "C ", "D ") or label == "deploy the burner"
            out.append(("SPK-1b", label, measured, d["tx"]))
    return out


def norm(h):
    return hex(int(h, 16))


class Redactor:
    def __init__(self):
        self.owner = None  # int, in memory only
        self.strk_keys = {}

    def contract(self, address):
        a = int(address, 16)
        if self.owner is not None and a == self.owner:
            return "<ACCOUNT>"
        if a in GAME:
            return GAME[a]
        if a == STRK:
            return "STRK"
        if a == BURNER:
            return "burner"
        return norm(address)

    def value(self, felt):
        """A game storage key or value; the owner's address (an admin, an adventurer's owner) is redacted."""
        if self.owner is not None and int(felt, 16) == self.owner:
            return "<ACCOUNT>"
        return norm(felt)

    def strk_key(self, key):
        return self.strk_keys.setdefault(int(key, 16), f"strk-key-{len(self.strk_keys) + 1}")


def gas(inv):
    return int(inv["execution_resources"]["l2_gas"]) if inv else 0


def tree(inv, red, depth=0):
    if not inv:
        return None
    node = {
        "to": red.contract(inv["contract_address"]),
        "selector": norm(inv["entry_point_selector"]),
        "l2_gas": gas(inv),
        "events": len(inv.get("events", [])),
    }
    if depth < 3:
        node["calls"] = [tree(c, red, depth + 1) for c in inv.get("calls", [])]
    return node


def record(rpc, red, source, label, measured, tx):
    t = rpc.call("starknet_getTransactionByHash", [tx])
    r = rpc.call("starknet_getTransactionReceipt", [tx])
    tr = rpc.call("starknet_traceTransaction", [tx])
    block = r["block_number"]
    ex = tr.get("execute_invocation") or tr.get("constructor_invocation")
    if isinstance(ex, dict) and "revert_reason" in ex:
        ex = None
    sd = tr["state_diff"]
    storage = []
    for c in sd["storage_diffs"]:
        addr = int(c["address"], 16)
        entries = []
        for e in c["storage_entries"]:
            try:
                prev = rpc.call("starknet_getStorageAt", [c["address"], e["key"], {"block_number": block - 1}])
            except RpcError as err:
                if '"code": 20' not in str(err):  # the contract did not exist yet: deployed by this transaction
                    raise
                prev = "0x0"
            entry = {"prev_zero": int(prev, 16) == 0, "value_zero": int(e["value"], 16) == 0}
            if addr == STRK:
                entry["key"] = red.strk_key(e["key"])
            elif addr in GAME or addr == BURNER:
                entry["key"] = red.value(e["key"])
                entry["prev"] = red.value(prev)
                entry["value"] = red.value(e["value"])
            else:
                entry["key"] = "<redacted>"
            entries.append(entry)
        storage.append({"contract": red.contract(c["address"]), "entries": entries})
    res = r["execution_resources"]
    return {
        "source": source,
        "label": label,
        "measured": measured,
        "tx": tx,
        "type": r["type"],
        "block": block,
        "status": r["execution_status"],
        "sender": red.contract(t.get("sender_address") or t.get("contract_address") or "0x0"),
        "calldata_felts": len(t.get("calldata") or t.get("constructor_calldata") or []),
        "signature_felts": len(t.get("signature") or []),
        "receipt": {
            "l2_gas": int(res["l2_gas"]),
            "l1_data_gas": int(res["l1_data_gas"]),
            "l1_gas": int(res["l1_gas"]),
            "events": len(r.get("events", [])),
        },
        "trace_total": {k: int(v) for k, v in tr["execution_resources"].items()},
        "validate": tree(tr.get("validate_invocation"), red),
        "execute": tree(ex, red),
        "fee_transfer": tree(tr.get("fee_transfer_invocation"), red),
        "state_diff": {
            "storage": storage,
            "nonces": [red.contract(n["contract_address"]) for n in sd["nonces"]],
            "deployed_contracts": [red.contract(d["address"]) for d in sd["deployed_contracts"]],
            "declared_classes": [norm(d["class_hash"]) for d in sd["declared_classes"]],
            "deprecated_declared_classes": len(sd["deprecated_declared_classes"]),
            "replaced_classes": [red.contract(d["contract_address"]) for d in sd["replaced_classes"]],
            "migrated_compiled_classes": len(sd.get("migrated_compiled_classes", [])),
        },
    }


def main():
    rpc = Rpc(ENDPOINT)
    if rpc.call("starknet_chainId", []) != "0x534e5f5345504f4c4941":
        sys.exit("refused: the endpoint is not SN_SEPOLIA")
    txs = spk1_transactions() + spk1b_transactions()
    print(f"transactions: {len(txs)} (SPK-1 deploy {sum(s == 'SPK-1 deploy' for s, *_ in txs)}, "
          f"SPK-1 measure {sum(s == 'SPK-1' for s, *_ in txs)}, SPK-1b {sum(s == 'SPK-1b' for s, *_ in txs)})")
    red = Redactor()
    # The owner's account: the sender of SPK-1's first measured transaction (held in memory only).
    first = rpc.call("starknet_getTransactionByHash", [txs[0][3]])
    red.owner = int(first["sender_address"], 16)
    done = {}
    if os.path.exists(OUT):
        for line in open(OUT):
            d = json.loads(line)
            done[d["tx"]] = d
    for i, (source, label, measured, tx) in enumerate(txs):
        if tx in done:
            continue
        for attempt in range(4):
            try:
                rec = record(rpc, red, source, label, measured, tx)
                break
            except Exception as e:  # noqa: BLE001 - a public endpoint fails now and then
                msg = str(e)[:200]
                if red.owner is not None and f"{red.owner:x}" in msg.lower():
                    msg = "<message withheld: it names the owner's account>"
                print(f"  retry {attempt + 1} for {i}: {type(e).__name__} {msg}")
                time.sleep(3 * (attempt + 1))
        else:
            sys.exit(f"failed on transaction {i}")
        line = json.dumps(rec, separators=(",", ":"))
        check(line, red.owner)
        with open(OUT, "a") as f:
            f.write(line + "\n")
        print(f"{i + 1:3d}/{len(txs)} {source:12s} {label[:50]:50s} slots "
              f"{sum(len(c['entries']) for c in rec['state_diff']['storage'])}")
    check(open(OUT).read(), red.owner)
    print("redaction check: the owner's address is in no line of traces.jsonl")


def check(text, owner):
    low = text.lower()
    forms = {hex(owner)[2:], f"{owner:064x}", f"{owner:x}".lstrip("0")}
    if any(f in low for f in forms):
        sys.exit("refused: the owner's address would be written")


if __name__ == "__main__":
    main()
