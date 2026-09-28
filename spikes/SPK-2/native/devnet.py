#!/usr/bin/env python3
"""SPK-2 part 2: declare and deploy the two native contracts on the local node, write the
fixtures, send the measured actions with `sncast`, and print, for each, the resources and the fee
of its receipt (one JSON line each). Runs under scripts/with-node.sh, from the repository root:

    scripts/with-node.sh python3 spikes/SPK-2/native/devnet.py > spikes/SPK-2/native/devnet-output.txt

The environment comes from with-node.sh: NODE_URL, NODE_ACCOUNT_ADDRESS, NODE_ACCOUNT_PRIVATE_KEY.
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
                        "accounts-spk2.json")


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


def west(n):
    return [str(n)] + ["3"] * n


if os.path.exists(ACCOUNTS):
    os.remove(ACCOUNTS)
sncast("account", "import", "--url", URL, "--name", "dev", "--type", "oz",
       "--address", ACCOUNT, "--private-key", os.environ["NODE_ACCOUNT_PRIVATE_KEY"])

addresses = {}
for name in ("Hub", "Instances"):
    out = sncast("--account", "dev", "--wait", "declare", "--url", URL, "--contract-name", name)
    class_hash = field("Class Hash", out)
    out = sncast("--account", "dev", "--wait", "deploy", "--url", URL, "--class-hash", class_hash,
                 "--constructor-calldata", ACCOUNT)
    addresses[name] = field("Contract Address", out)

HUB, INSTANCES = addresses["Hub"], addresses["Instances"]
OWNER = ACCOUNT

# (label, measured, contract, function, calldata); instance ids as in part 1, plus 7 (one felt per
# goblin) and 8, 9, 10 (queues of 10, 5, 1 moves on the packed layout)
CALLS = [
    ("link hub", False, HUB, "set_instances", [INSTANCES]),
    ("link instances", False, INSTANCES, "set_hub", [HUB]),
    ("setup worst case", False, INSTANCES, "setup_worst_case", ["1", OWNER]),
    ("setup worst case, packed", False, INSTANCES, "setup_worst_case", ["5", OWNER]),
    ("setup worst case, felt", False, INSTANCES, "setup_worst_case", ["7", OWNER]),
    ("setup queue 10", False, INSTANCES, "setup_queue", ["2", "8", OWNER]),
    ("setup queue 5", False, INSTANCES, "setup_queue", ["3", "8", OWNER]),
    ("setup queue 1", False, INSTANCES, "setup_queue", ["4", "8", OWNER]),
    ("setup queue 10, no goblin", False, INSTANCES, "setup_queue", ["6", "0", OWNER]),
    ("setup queue 10, packed", False, INSTANCES, "setup_queue", ["8", "8", OWNER]),
    ("setup queue 5, packed", False, INSTANCES, "setup_queue", ["9", "8", OWNER]),
    ("setup queue 1, packed", False, INSTANCES, "setup_queue", ["10", "8", OWNER]),
    ("setup alchemy", False, HUB, "setup_alchemy", [OWNER]),
    ("setup hub", False, HUB, "setup_hub", [OWNER]),
    ("worst-case tick", True, INSTANCES, "attack", ["1", "1"]),
    ("worst-case tick, one felt per goblin", True, INSTANCES, "attack_felt", ["7", "1"]),
    ("worst-case tick, packed goblins", True, INSTANCES, "attack_packed", ["5", "1"]),
    ("queue of 10 moves", True, INSTANCES, "walk", ["2", *west(10)]),
    ("queue of 5 moves", True, INSTANCES, "walk", ["3", *west(5)]),
    ("queue of 1 move", True, INSTANCES, "walk", ["4", *west(1)]),
    ("queue of 10 moves, no goblin", True, INSTANCES, "walk", ["6", *west(10)]),
    ("queue of 10 moves, packed goblins", True, INSTANCES, "walk_packed", ["8", *west(10)]),
    ("queue of 5 moves, packed goblins", True, INSTANCES, "walk_packed", ["9", *west(5)]),
    ("queue of 1 move, packed goblins", True, INSTANCES, "walk_packed", ["10", *west(1)]),
    ("brew, signature, new pair", True, HUB, "brew", ["1", "1", "8", "9"]),
    ("brew, no signature, new pair", True, HUB, "brew_unsigned", ["2", "1", "8", "9"]),
    ("brew, known pair", True, HUB, "brew", ["1", "1", "8", "9"]),
    ("accept quest", True, HUB, "accept_quest", ["3", "1"]),
    ("claim quest", True, HUB, "claim_quest", ["3", "2"]),
    ("enter", True, HUB, "enter", ["3", "10"]),
    ("leave", True, INSTANCES, "leave", ["101"]),
]

for label, measured, contract, function, calldata in CALLS:
    out = sncast("--account", "dev", "--wait", "invoke", "--url", URL, "--contract-address", contract,
                 "--function", function, "--calldata", *calldata)
    tx = field("Transaction Hash", out)
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
        "events": len(receipt.get("events", [])),
    }), flush=True)
