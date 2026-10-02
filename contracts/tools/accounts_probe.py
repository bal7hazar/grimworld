#!/usr/bin/env python3
"""ENG-04: what `Hub`'s accounts and adventurers cost on the local node, each from its receipt, and
which of `Hub`'s storage keys each changes, from its trace's state diff (docs/briefs/ENG-04-adventurers.md
AC-2; ENG-01 §9.3 and §10).

Declares and deploys `Hub` (the caller is the node's first account, which is also the
administrator), then sends one transaction per case:

  register                                   the account (3 new keys, 1 overwritten)
  create_adventurer, cold                    the list's page 0 written for the first time
  create_adventurer, initialised (x2)        the page exists
  delete_adventurer, worst of 3 slots        the 2nd of 3: the latest entry that is not the last,
                                             the longest search of the MVP's 3 slots (audit 1, F-2)
  set_account_owner, none inside             no adventurer inside, so no call to `Instances`

The node cannot reach an account of 8 (no entrypoint sells slots) nor an adventurer inside (`enter`
is ENG-06's): those cases are measured in snforge only (contracts/persistent/tests/test_accounts.cairo).
One JSON line per transaction on stdout. Local node only: the script refuses any node URL that is
not 127.0.0.1 and never reads a Sepolia variable. From the repository root, after
`scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build`:

    scripts/with-node.sh python3 contracts/tools/accounts_probe.py \
        > contracts/tools/accounts-probe-output.txt
"""
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PACKAGE = os.path.join(os.path.dirname(HERE), "persistent")
URL = os.environ["NODE_URL"]
# D-176: `sncast declare` builds the contract with Scarb; the build is single-threaded.
os.environ["RAYON_NUM_THREADS"] = "1"
if urllib.parse.urlparse(URL).hostname != "127.0.0.1":
    sys.exit("accounts_probe: the local node only (NODE_URL must be on 127.0.0.1)")
ADDRESS = os.environ["NODE_ACCOUNT_ADDRESS"]
KEY = os.environ["NODE_ACCOUNT_PRIVATE_KEY"]
LOGS = os.environ.get("WITH_NODE_LOG_DIR", os.path.join(os.getcwd(), ".with-node"))
ACCOUNTS = os.path.join(LOGS, "accounts-eng04.json")


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


if os.path.exists(ACCOUNTS):
    os.remove(ACCOUNTS)
sncast("account", "import", "--url", URL, "--name", "dev", "--type", "oz",
       "--address", ADDRESS, "--private-key", KEY)
chain = bytes.fromhex(rpc("starknet_chainId", [])[2:]).decode()
emit({"node": "starknet-devnet (scripts/with-node.sh)", "chain_id": chain,
      "spec": rpc("starknet_specVersion", [])})

out = sncast("--account", "dev", "--wait", "declare", "--url", URL, "--contract-name", "Hub",
             "--package", "grimworld_persistent")
class_hash = field("Class Hash", out)
# (admin, registry, instances, market, fate): the other contracts are never called by these cases.
out = sncast("--account", "dev", "--wait", "deploy", "--url", URL, "--class-hash", class_hash,
             "--constructor-calldata", ADDRESS, "0x2", "0x3", "0x4", "0x5")
hub = field("Contract Address", out)
emit({"hub": hub, "class_hash": class_hash})


def invoke(label, function, *calldata):
    args = ["--calldata", *calldata] if calldata else []
    out = sncast("--account", "dev", "--wait", "invoke", "--url", URL, "--contract-address", hub,
                 "--function", function, *args)
    tx = field("Transaction Hash", out)
    receipt = rpc("starknet_getTransactionReceipt", {"transaction_hash": tx})
    trace = rpc("starknet_traceTransaction", {"transaction_hash": tx})
    diff = (trace.get("state_diff") or {}).get("storage_diffs", [])
    hub_keys = [e for d in diff if int(d["address"], 16) == int(hub, 16) for e in d["storage_entries"]]
    resources = receipt["execution_resources"]
    emit({
        "label": label,
        "tx": tx,
        "status": receipt.get("execution_status"),
        "l2_gas": resources.get("l2_gas"),
        "l1_data_gas": resources.get("l1_data_gas"),
        "l1_gas": resources.get("l1_gas"),
        "calldata_felts": len(calldata),
        "hub_slots_changed": len(hub_keys),
        "hub_zeroed": sum(1 for e in hub_keys if int(e["value"], 16) == 0),
    })


invoke("register", "register")
invoke("create_adventurer, cold (page 0 first written)", "create_adventurer", "0x416c64726963", "0x1")
invoke("create_adventurer, initialised", "create_adventurer", "0x4272656e6e61", "0x2")
invoke("create_adventurer, initialised (third)", "create_adventurer", "0x436564726963", "0x3")
invoke("delete_adventurer, worst of 3 slots (the 2nd of 3)", "delete_adventurer", "0x2")
invoke("set_account_owner, none inside", "set_account_owner", "0x1", "0x123456")
