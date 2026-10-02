#!/usr/bin/env python3
"""ENG-01: what a storage key costs when it is written, kept or zeroed, then written again, each
from its receipt on the local node (docs/architecture/ENG-01-interfaces.md, *Reuse, measured*).

FND-04 priced a new slot (its value was 0 before the transaction) and an overwritten or zeroed one
from Sepolia's receipts, and never saw a key written again after it was zeroed, nor an instance key
reused. This script sends, through the local node's first account, `ReuseProbe.write(first, count,
value)` transactions whose calldata has the same length, so that two receipts differ only by what
the probe writes:

  empty      count 0                                  no storage change (the baseline)
  new        keys never written                       value 0 -> 1
  kept       the same keys, another value             1 -> 2 (the key was kept holding a value)
  same       the same keys, the same value            2 -> 2 (no change)
  zeroed     the same keys set to 0                    2 -> 0
  rewritten  the zeroed keys written again             0 -> 3 (a key reused after zeroing)
  new again  fresh keys, as a control of `new`         0 -> 1

for 1, 4 and 20 keys (4 is `enter`'s count in SPK-2; 20 is this design's `enter` on a reused
instance slot). Each case also reads the trace's state diff, to show which keys changed. One JSON
line per transaction on stdout. Local node only: the script refuses any node URL that is not
127.0.0.1 and never reads a Sepolia variable. From the repository root, after
`scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build`:

    env -i PATH="$PATH" HOME="$HOME" scripts/with-node.sh python3 contracts/tools/reuse_probe.py \
        > contracts/tools/reuse-probe-output.txt
"""
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PACKAGE = os.path.join(os.path.dirname(HERE), "ephemeral")
URL = os.environ["NODE_URL"]
# D-176: `sncast declare` builds the contract with Scarb; the build is single-threaded.
os.environ["RAYON_NUM_THREADS"] = "1"
if urllib.parse.urlparse(URL).hostname != "127.0.0.1":
    sys.exit("reuse_probe: the local node only (NODE_URL must be on 127.0.0.1)")
ADDRESS = os.environ["NODE_ACCOUNT_ADDRESS"]
KEY = os.environ["NODE_ACCOUNT_PRIVATE_KEY"]
LOGS = os.environ.get("WITH_NODE_LOG_DIR", os.path.join(os.getcwd(), ".with-node"))
ACCOUNTS = os.path.join(LOGS, "accounts-eng01.json")


def emit(record):
    print(json.dumps(record), flush=True)


def rpc(method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    request = urllib.request.Request(URL, data=body, headers={"content-type": "application/json"})
    with urllib.request.urlopen(request, timeout=60) as response:
        answer = json.load(response)
    if "error" in answer:
        raise RuntimeError(f"{method}: {answer['error']}")
    return answer["result"]


def sncast(*args):
    out = subprocess.run(["sncast", "--accounts-file", ACCOUNTS, *args], cwd=PACKAGE,
                         capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"sncast {' '.join(args[:4])}: {out.stdout[-2000:]} {out.stderr[-2000:]}")
    return out.stdout + out.stderr


def field(label, text):
    match = re.search(rf"{label}:\s*(0x[0-9a-fA-F]+)", text)
    if not match:
        raise RuntimeError(f"no {label} in: {text}")
    return match.group(1)


def l2(invocation):
    return (invocation or {}).get("execution_resources", {}).get("l2_gas")


if os.path.exists(ACCOUNTS):
    os.remove(ACCOUNTS)
sncast("account", "import", "--url", URL, "--name", "dev", "--type", "oz",
       "--address", ADDRESS, "--private-key", KEY)
chain = bytes.fromhex(rpc("starknet_chainId", [])[2:]).decode()
emit({"node": "starknet-devnet (scripts/with-node.sh)", "chain_id": chain,
      "spec": rpc("starknet_specVersion", [])})

out = sncast("--account", "dev", "--wait", "declare", "--url", URL, "--contract-name", "ReuseProbe",
             "--package", "grimworld_ephemeral")
class_hash = field("Class Hash", out)
out = sncast("--account", "dev", "--wait", "deploy", "--url", URL, "--class-hash", class_hash)
probe = field("Contract Address", out)
emit({"probe": probe, "class_hash": class_hash})


def write(label, first, count, value):
    out = sncast("--account", "dev", "--wait", "invoke", "--url", URL, "--contract-address", probe,
                 "--function", "write", "--calldata", str(first), str(count), str(value))
    tx = field("Transaction Hash", out)
    receipt = rpc("starknet_getTransactionReceipt", {"transaction_hash": tx})
    trace = rpc("starknet_traceTransaction", {"transaction_hash": tx})
    execute = trace.get("execute_invocation") or {}
    diff = (trace.get("state_diff") or {}).get("storage_diffs", [])
    probe_keys = [e for d in diff if int(d["address"], 16) == int(probe, 16) for e in d["storage_entries"]]
    other = sum(len(d["storage_entries"]) for d in diff if int(d["address"], 16) != int(probe, 16))
    resources = receipt["execution_resources"]
    emit({
        "label": label,
        "keys": count,
        "tx": tx,
        "status": receipt.get("execution_status"),
        "l2_gas": resources.get("l2_gas"),
        "l1_data_gas": resources.get("l1_data_gas"),
        "l1_gas": resources.get("l1_gas"),
        "validate": l2(trace.get("validate_invocation")),
        "execute": l2(execute),
        "probe_call": sum(l2(c) or 0 for c in execute.get("calls", [])),
        "fee_transfer": l2(trace.get("fee_transfer_invocation")),
        "probe_slots_changed": len(probe_keys),
        "probe_values": sorted({e["value"] for e in probe_keys}),
        "other_slots_changed": other,
    })


# Baselines first, then each count on its own key range. The account's nonce and the fee token's
# balances change in every transaction alike.
for n in (0, 0):
    write("empty", 1_000_000, 0, 0)
for count, first in ((1, 10), (4, 100), (20, 1000)):
    write("new", first, count, 1)
    write("kept", first, count, 2)
    write("same", first, count, 2)
    write("zeroed", first, count, 0)
    write("rewritten", first, count, 3)
    write("kept after rewrite", first, count, 4)
    write("new again", first + 50_000, count, 1)
