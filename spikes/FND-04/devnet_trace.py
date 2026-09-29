#!/usr/bin/env python3
"""The storage slots each of SPK-2's native entrypoints changes, read from the local node's traces.

Reads only (the read methods of `rpc.py`). The transactions are those SPK-2's unchanged script
`spikes/SPK-2/devnet_measure.py` sends to the throwaway local node that `scripts/with-node.sh`
starts and stops, from the node's pre-funded seed-0 account and an account it deploys there; this
file only reads them, while the node lives. From the repository root:

    scripts/with-node.sh bash -c 'python3 spikes/SPK-2/devnet_measure.py > .with-node/spk2.jsonl; \
      python3 spikes/FND-04/devnet_trace.py .with-node/spk2.jsonl' > spikes/FND-04/devnet-output.txt

The node keeps no past state, so this walks every block from genesis and reads the state diff of
every transaction in order: a slot's previous value is the last value an earlier transaction wrote
there. A slot is *new* when that value was 0 (or no transaction wrote it, for a contract deployed on
this node). For the contracts that exist at genesis (the fee tokens, the pre-funded accounts), a
slot no transaction wrote before is counted `genesis`: its previous value is not known here.
"""
import json
import os
import sys

from rpc import Rpc

URL = os.environ["NODE_URL"]


def main(path):
    rpc = Rpc(URL)
    print(json.dumps({"step": "node", "spec": rpc.call("starknet_specVersion", []),
                      "chain": rpc.call("starknet_chainId", [])}), flush=True)
    labels = {}
    for line in open(path):
        line = line.strip()
        if not line.startswith("{"):
            continue
        rec = json.loads(line)
        if rec.get("tx"):
            labels[int(rec["tx"], 16)] = (rec.get("side"), rec.get("label"))
        elif "account" in rec or "dojo_migrate_error" in rec or "dojo_migrate" in rec:
            print(json.dumps({"step": "harness", **{k: str(v)[:300] for k, v in rec.items()}}), flush=True)
    last = {}  # (contract, key) -> last value written
    deployed = set()
    latest = rpc.call("starknet_blockNumber", [])
    seen = 0
    for n in range(latest + 1):
        block = rpc.call("starknet_getBlockWithTxHashes", [{"block_number": n}])
        for tx in block["transactions"]:
            tr = rpc.call("starknet_traceTransaction", [tx])
            sd = tr.get("state_diff")
            if sd is None:
                if int(tx, 16) in labels:
                    print(json.dumps({"tx": tx, "label": labels[int(tx, 16)][1], "state_diff": None}), flush=True)
                continue
            for d in sd.get("deployed_contracts", []):
                deployed.add(int(d["address"], 16))
            storage = []
            for c in sd["storage_diffs"]:
                addr = int(c["address"], 16)
                counts = {"new": 0, "overwritten": 0, "zeroed": 0, "genesis": 0}
                for e in c["storage_entries"]:
                    k, v = int(e["key"], 16), int(e["value"], 16)
                    if (addr, k) in last:
                        prev = last[(addr, k)]
                    elif addr in deployed:
                        prev = 0
                    else:
                        prev = None
                    if prev is None:
                        counts["genesis"] += 1
                    elif prev == 0:
                        counts["new"] += 1
                    elif v == 0:
                        counts["zeroed"] += 1
                    else:
                        counts["overwritten"] += 1
                    last[(addr, k)] = v
                storage.append({"contract": hex(addr), "slots": len(c["storage_entries"]), **counts})
            if int(tx, 16) not in labels:
                continue
            seen += 1
            side, label = labels[int(tx, 16)]
            receipt = rpc.call("starknet_getTransactionReceipt", [tx])
            print(json.dumps({
                "side": side, "label": label, "tx": tx, "block": n,
                "status": receipt.get("execution_status"),
                "l2_gas": int(receipt["execution_resources"]["l2_gas"]),
                "l1_data_gas": int(receipt["execution_resources"]["l1_data_gas"]),
                "state_diff": {
                    "storage": storage,
                    "nonces": len(sd["nonces"]),
                    "deployed_contracts": len(sd["deployed_contracts"]),
                    "declared_classes": len(sd["declared_classes"]),
                },
            }), flush=True)
    print(json.dumps({"step": "done", "blocks": latest + 1, "measured_transactions_traced": seen,
                      "measured_transactions_listed": len(labels)}), flush=True)


if __name__ == "__main__":
    main(sys.argv[1])
