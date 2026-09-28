#!/usr/bin/env python3
"""SPK-7: declare and deploy the `Instances` contract on the local node, write the fixtures, send the
measured transactions with `sncast`, and print, for each, the resources and the fee of its receipt
(one JSON line each). Runs under scripts/with-node.sh, from the repository root:

    scripts/with-node.sh python3 spikes/SPK-7/devnet.py > spikes/SPK-7/devnet-output.txt

The environment comes from with-node.sh: NODE_URL, NODE_ACCOUNT_ADDRESS, NODE_ACCOUNT_PRIVATE_KEY.

Measured:
- the worst-case tick (4 chunks, 2 layers each, 8 awake goblins, winding board, flood at its cap of
  15 layers, 8 steps, 5 across chunks): A = window assembled at each tick (D-120), B = stored window
  (rejected, for comparison); each when the adventurer waits (B reads its stored window) and when it
  moves (B re-centres and writes its window back); S = SPK-2's stand-in (the window's terrain in one
  slot, occupancy from the goblins, no chunk read or write), so that A - S is the chunked map's cost;
  B' = the stored window as the working copy: the chunks' occupancy is written back only when the
  window moves;
- reveals per biome: 1 chunk with no neighbour known, 1 chunk with its 4 neighbours known, 3 chunks
  (an L) with none known, 3 chunks with the 7 around them known. Each from a fresh instance.
"""
import json
import os
import re
import subprocess
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
URL = os.environ["NODE_URL"]
ACCOUNT = os.environ["NODE_ACCOUNT_ADDRESS"]
ACCOUNTS = os.path.join(os.environ.get("WITH_NODE_LOG_DIR", os.path.join(os.getcwd(), ".with-node")),
                        "accounts-spk7.json")
BIOMES = ["meadow", "forest", "cave", "ruin"]
STAY, EAST = "6", "0"
L_SHAPE = ["3", "2", "2", "3", "2", "2", "3"]  # 3 chunks: (2, 2), (3, 2), (2, 3)
ONE = ["1", "2", "2"]  # chunk A = (2, 2)


def sncast(*args):
    """sncast from the package's folder (it reads the package there)."""
    command = ["sncast", "--accounts-file", ACCOUNTS, *args]
    out = subprocess.run(command, cwd=HERE, capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"{' '.join(command)}: {out.stdout} {out.stderr}")
    return out.stdout


def field(label, text):
    m = re.search(rf"^{label}:\s*(\S+)", text, re.M)
    if not m:
        raise RuntimeError(f"no {label} in: {text}")
    return m.group(1)


def rpc(method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    request = urllib.request.Request(URL, data=body, headers={"content-type": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        answer = json.load(response)
    if "error" in answer:
        raise RuntimeError(f"{method}: {answer['error']}")
    return answer["result"]


def invoke(contract, function, calldata):
    out = sncast("--account", "dev", "--wait", "invoke", "--url", URL, "--contract-address", contract,
                 "--function", function, "--calldata", *calldata)
    return field("Transaction Hash", out)


def call(contract, function, calldata):
    out = sncast("call", "--url", URL, "--contract-address", contract, "--function", function,
                 "--calldata", *calldata)
    return out.strip()


if os.path.exists(ACCOUNTS):
    os.remove(ACCOUNTS)
sncast("account", "import", "--url", URL, "--name", "dev", "--type", "oz",
       "--address", ACCOUNT, "--private-key", os.environ["NODE_ACCOUNT_PRIVATE_KEY"])
out = sncast("--account", "dev", "--wait", "declare", "--url", URL, "--contract-name", "Instances")
class_hash = field("Class Hash", out)
out = sncast("--account", "dev", "--wait", "deploy", "--url", URL, "--class-hash", class_hash)
MAP = field("Contract Address", out)

# (label, measured, function, calldata)
CALLS = [
    ("setup tick A wait", False, "setup_worst_case", ["1", "0", "0"]),
    ("setup tick B wait", False, "setup_worst_case", ["2", "0", "1"]),
    ("setup tick A move", False, "setup_worst_case", ["3", "1", "0"]),
    ("setup tick B move", False, "setup_worst_case", ["4", "1", "1"]),
    ("setup tick S wait", False, "setup_standin", ["5", "0"]),
    ("setup tick S move", False, "setup_standin", ["6", "1"]),
    ("setup tick B' wait", False, "setup_worst_case", ["7", "0", "1"]),
    ("setup tick B' move", False, "setup_worst_case", ["8", "1", "1"]),
    ("setup tick B' move pending", False, "setup_worst_case", ["9", "1", "1"]),
    ("setup tick B' move pending, stale chunks", False, "setup_stale", ["9"]),
]
for b, name in enumerate(BIOMES):
    CALLS += [
        (f"setup reveal 1 open {name}", False, "setup_reveal", [str(10 + b), str(b), "0"]),
        (f"setup reveal 1 known {name}", False, "setup_reveal", [str(20 + b), str(b), "2"]),
        (f"setup reveal 3 open {name}", False, "setup_reveal", [str(30 + b), str(b), "0"]),
        (f"setup reveal 3 around {name}", False, "setup_reveal", [str(40 + b), str(b), "1"]),
    ]
CALLS += [
    ("worst-case tick, A (assembled), adventurer waits", True, "act", ["1", STAY]),
    ("worst-case tick, B (stored), adventurer waits", True, "act_stored", ["2", STAY]),
    ("worst-case tick, A (assembled), adventurer moves", True, "act", ["3", EAST]),
    ("worst-case tick, B (stored, re-centred and written back), adventurer moves", True, "act_stored", ["4", EAST]),
    ("worst-case tick, S (SPK-2's stand-in), adventurer waits", True, "act_standin", ["5", STAY]),
    ("worst-case tick, S (SPK-2's stand-in), adventurer moves", True, "act_standin", ["6", EAST]),
    ("worst-case tick, B' (stored, occupancy deferred), adventurer waits", True, "act_deferred", ["7", STAY]),
    ("worst-case tick, B' (stored, occupancy deferred, nothing pending, re-centred), adventurer moves", True, "act_deferred", ["8", EAST]),
    ("worst-case tick, B' (stored, occupancy deferred, 4 chunks written back, re-centred), adventurer moves", True, "act_deferred", ["9", EAST]),
]
for b, name in enumerate(BIOMES):
    CALLS += [
        (f"reveal 1 chunk, no neighbour known, {name}", True, "reveal", [str(10 + b), *ONE]),
        (f"reveal 1 chunk, 4 neighbours known, {name}", True, "reveal", [str(20 + b), *ONE]),
        (f"reveal 3 chunks, no neighbour known, {name}", True, "reveal", [str(30 + b), *L_SHAPE]),
        (f"reveal 3 chunks, 7 neighbours known, {name}", True, "reveal", [str(40 + b), *L_SHAPE]),
    ]

for label, measured, function, calldata in CALLS:
    tx = invoke(MAP, function, calldata)
    receipt = rpc("starknet_getTransactionReceipt", {"transaction_hash": tx})
    block = rpc("starknet_getBlockWithTxHashes", {"block_id": {"block_number": receipt["block_number"]}})
    resources = receipt["execution_resources"]
    print(json.dumps({
        "label": label,
        "measured": measured,
        "call": function,
        "tx": tx,
        "status": receipt.get("execution_status"),
        "revert_reason": receipt.get("revert_reason"),
        "l2_gas": resources.get("l2_gas"),
        "l1_data_gas": resources.get("l1_data_gas"),
        "l1_gas": resources.get("l1_gas"),
        "fee": int(receipt["actual_fee"]["amount"], 16),
        "fee_unit": receipt["actual_fee"]["unit"],
        "node_l2_gas_fri": int(block["l2_gas_price"]["price_in_fri"], 16),
        "node_l1_data_gas_fri": int(block["l1_data_gas_price"]["price_in_fri"], 16),
    }), flush=True)

# The four ticks leave the same goblins (the snforge tests check chunks and windows too)
goblins = {i: call(MAP, "goblins", [str(i)]) for i in (1, 2, 3, 4, 5, 6, 7, 8, 9)}
print(json.dumps({"check": "goblins after the nine ticks are equal", "ok": len(set(goblins.values())) == 1,
                  "goblins": goblins[1]}), flush=True)
