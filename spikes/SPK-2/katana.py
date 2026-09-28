#!/usr/bin/env python3
"""Send the measured actions as transactions to the local Katana of scripts/with-katana.sh and
print, for each, the resources and the fee of its receipt. Run by run.sh, after the migration,
from this folder.
"""
import json
import os
import re
import subprocess
import urllib.request

MANIFEST = "Scarb.toml"
RPC = os.environ["KATANA_URL"]
def west(n):
    return "arr:" + ",".join(["3"] * n)


# (label, measured, tag, entrypoint, calldata); instance ids as in src/fixtures.cairo
CALLS = [
    ("setup worst case", False, "spk2-setup", "worst_case", ["1"]),
    ("setup worst case, packed", False, "spk2-setup", "worst_case", ["5"]),
    ("setup queue 10", False, "spk2-setup", "queue", ["2", "8"]),
    ("setup queue 5", False, "spk2-setup", "queue", ["3", "8"]),
    ("setup queue 1", False, "spk2-setup", "queue", ["4", "8"]),
    ("setup queue 10, no goblin", False, "spk2-setup", "queue", ["6", "0"]),
    ("setup alchemy", False, "spk2-setup", "alchemy", []),
    ("setup hub", False, "spk2-setup", "hub", []),
    ("worst-case tick", True, "spk2-tick_worst_case", "attack", ["1", "1"]),
    ("worst-case tick, packed goblins", True, "spk2-tick_worst_case", "attack_packed", ["5", "1"]),
    ("queue of 10 moves", True, "spk2-queue_moves", "walk", ["2", west(10)]),
    ("queue of 5 moves", True, "spk2-queue_moves", "walk", ["3", west(5)]),
    ("queue of 1 move", True, "spk2-queue_moves", "walk", ["4", west(1)]),
    ("queue of 10 moves, no goblin", True, "spk2-queue_moves", "walk", ["6", west(10)]),
    ("brew, signature, new pair", True, "spk2-brew", "brew", ["1", "1", "8", "9"]),
    ("brew, no signature, new pair", True, "spk2-brew", "brew_unsigned", ["2", "1", "8", "9"]),
    ("brew, known pair", True, "spk2-brew", "brew", ["1", "1", "8", "9"]),
    ("accept quest", True, "spk2-hub", "accept_quest", ["3", "1"]),
    ("claim quest", True, "spk2-hub", "claim_quest", ["3", "2"]),
    ("enter", True, "spk2-hub", "enter", ["3", "10"]),
    ("leave", True, "spk2-hub", "leave", ["3"]),
]


def rpc(method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    request = urllib.request.Request(RPC, data=body, headers={"content-type": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        answer = json.load(response)
    if "error" in answer:
        raise RuntimeError(f"{method}: {answer['error']}")
    return answer["result"]


def execute(tag, entrypoint, calldata):
    command = ["sozo", "execute", "--manifest-path", MANIFEST, "--wait", tag, entrypoint, *calldata]
    out = subprocess.run(command, capture_output=True, text=True, check=True)
    hashes = re.findall(r"0x[0-9a-fA-F]{40,}", out.stdout + out.stderr)
    if not hashes:
        raise RuntimeError(f"no transaction hash in: {out.stdout} {out.stderr}")
    return hashes[-1]


for label, measured, tag, entrypoint, calldata in CALLS:
    tx = execute(tag, entrypoint, calldata)
    receipt = rpc("starknet_getTransactionReceipt", [tx])
    block = rpc("starknet_getBlockWithTxHashes", [{"block_number": receipt["block_number"]}])
    resources = receipt["execution_resources"]
    line = {
        "label": label,
        "measured": measured,
        "call": f"{tag}.{entrypoint}",
        "tx": tx,
        "status": receipt.get("execution_status"),
        "revert_reason": receipt.get("revert_reason"),
        "l2_gas": resources.get("l2_gas"),
        "l1_data_gas": resources.get("l1_data_gas"),
        "l1_gas": resources.get("l1_gas"),
        "fee": int(receipt["actual_fee"]["amount"], 16),
        "fee_unit": receipt["actual_fee"]["unit"],
        "katana_l2_gas_fri": int(block["l2_gas_price"]["price_in_fri"], 16),
        "katana_l1_data_gas_fri": int(block["l1_data_gas_price"]["price_in_fri"], 16),
        "katana_l1_gas_fri": int(block["l1_gas_price"]["price_in_fri"], 16),
        "events": len(receipt.get("events", [])),
    }
    print(json.dumps(line), flush=True)
