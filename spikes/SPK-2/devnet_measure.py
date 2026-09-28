#!/usr/bin/env python3
"""SPK-2, fix loop 1 (C-1): both sides on one node and one account, metered in Sierra gas.

On starknet-devnet (scripts/with-node.sh), declare and deploy an OpenZeppelin account compiled with
Cairo 2.19 (spikes/SPK-2/account/), then send through it:
  - the native contracts' transactions (spikes/SPK-2/native/);
  - the Dojo world's transactions (part 1, migrated with sozo 1.8.7 from this folder's pins).
For each transaction: the receipt, and the breakdown of its trace (`starknet_traceTransaction`):
validation, the account's own execution, the game's calls, the fee transfer, and the rest of the
receipt (calldata, signature, events and state-diff charges outside the invocations).
Prints one JSON line per record. From the repository root:

    scripts/with-node.sh python3 spikes/SPK-2/devnet_measure.py > spikes/SPK-2/devnet-output.txt
"""
import json
import os
import re
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
NATIVE = os.path.join(HERE, "native")
NATIVE213 = os.path.join(HERE, "native213")
ACCOUNT_PKG = os.path.join(HERE, "account")
URL = os.environ["NODE_URL"]
DEFAULT = os.environ["NODE_ACCOUNT_ADDRESS"]
DEFAULT_KEY = os.environ["NODE_ACCOUNT_PRIVATE_KEY"]
LOGS = os.environ.get("WITH_NODE_LOG_DIR", os.path.join(os.getcwd(), ".with-node"))
ACCOUNTS = os.path.join(LOGS, "accounts-spk2-219.json")


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


def run(command, cwd):
    out = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"{' '.join(command)} (in {cwd}): {out.stdout[-3000:]} {out.stderr[-3000:]}")
    return out.stdout + out.stderr


def sncast(cwd, *args):
    return run(["sncast", "--accounts-file", ACCOUNTS, *args], cwd)


def field(label, text):
    m = re.search(rf"{label}:\s*(0x[0-9a-fA-F]+)", text)
    if not m:
        raise RuntimeError(f"no {label} in: {text}")
    return m.group(1)


def versions(class_hash):
    """Sierra and compiler versions from the head of the class's `sierra_program`."""
    program = rpc("starknet_getClass", {"block_id": "latest", "class_hash": class_hash})["sierra_program"]
    head = [int(x, 16) for x in program[:6]]
    return ".".join(map(str, head[:3])), ".".join(map(str, head[3:6]))


def l2(invocation):
    return (invocation or {}).get("execution_resources", {}).get("l2_gas")


def tree(invocation):
    """The call tree of an invocation: callee, selector, L2 gas, sub-calls."""
    return {
        "to": invocation.get("contract_address", "")[:12],
        "class": invocation.get("class_hash", "")[:12],
        "selector": invocation.get("entry_point_selector", "")[:12],
        "l2": l2(invocation),
        "calls": [tree(c) for c in invocation.get("calls", [])],
    }


def measure(side, label, tx):
    receipt = rpc("starknet_getTransactionReceipt", {"transaction_hash": tx})
    resources = receipt["execution_resources"]
    record = {
        "side": side,
        "label": label,
        "tx": tx,
        "status": receipt.get("execution_status"),
        "revert_reason": receipt.get("revert_reason"),
        "l2_gas": resources.get("l2_gas"),
        "l1_data_gas": resources.get("l1_data_gas"),
        "l1_gas": resources.get("l1_gas"),
        "fee": int(receipt["actual_fee"]["amount"], 16),
        "fee_unit": receipt["actual_fee"]["unit"],
    }
    try:
        trace = rpc("starknet_traceTransaction", {"transaction_hash": tx})
        execute = trace.get("execute_invocation") or {}
        validate = l2(trace.get("validate_invocation"))
        execute_total = l2(execute)
        game = sum(l2(c) or 0 for c in execute.get("calls", []))
        fee_transfer = l2(trace.get("fee_transfer_invocation"))
        record["trace"] = {
            "validate": validate,
            "execute_total": execute_total,
            "game_calls": game,
            "account_execute": (execute_total - game) if execute_total is not None else None,
            "fee_transfer": fee_transfer,
            "rest": (record["l2_gas"] - validate - execute_total - fee_transfer)
            if None not in (validate, execute_total, fee_transfer) else None,
            "trace_resources": trace.get("execution_resources"),
            "tree": tree(execute),
        }
    except Exception as error:  # noqa: BLE001 - record and go on
        record["trace_error"] = str(error)
    emit(record)
    return record


# ---------------------------------------------------------------------------------------------
# Accounts

if os.path.exists(ACCOUNTS):
    os.remove(ACCOUNTS)
sncast(NATIVE, "account", "import", "--url", URL, "--name", "dev", "--type", "oz",
       "--address", DEFAULT, "--private-key", DEFAULT_KEY)
default_class = rpc("starknet_getClassHashAt", {"block_id": "latest", "contract_address": DEFAULT})
sierra, compiler = versions(default_class)
emit({"account": "devnet default (harness of part 2)", "address": DEFAULT, "class_hash": default_class,
      "sierra": sierra, "compiler": compiler})

out = sncast(ACCOUNT_PKG, "--account", "dev", "--wait", "declare", "--url", URL, "--contract-name", "Account")
account_class = field("Class Hash", out)
out = sncast(ACCOUNT_PKG, "account", "create", "--url", URL, "--name", "gw219", "--class-hash", account_class,
             "--type", "oz")
address = field("Address", out)
rpc("devnet_mint", {"address": address, "amount": 10**24, "unit": "FRI"})
rpc("devnet_mint", {"address": address, "amount": 10**24, "unit": "WEI"})
sncast(ACCOUNT_PKG, "--wait", "account", "deploy", "--url", URL, "--name", "gw219")


def find_key(node, name):
    if isinstance(node, dict):
        if name in node and isinstance(node[name], dict) and "private_key" in node[name]:
            return node[name]
        for value in node.values():
            found = find_key(value, name)
            if found:
                return found
    return None


gw = find_key(json.load(open(ACCOUNTS)), "gw219")
KEY = gw["private_key"]
sierra, compiler = versions(account_class)
emit({"account": "OpenZeppelin account 4.0.1, compiled here (spikes/SPK-2/account)", "address": address,
      "class_hash": account_class, "sierra": sierra, "compiler": compiler})

ACC = ["--account", "gw219", "--wait"]

# ---------------------------------------------------------------------------------------------
# Native

def west(n):
    return [str(n)] + ["3"] * n


FELT, SLOTS, PACKED = "0", "1", "2"


def run_native(side, package):
    """Declare, deploy, set up and measure the native contracts built in `package`."""
    addresses = {}
    for name in ("Hub", "Instances"):
        out = sncast(package, *ACC, "declare", "--url", URL, "--contract-name", name)
        class_hash = field("Class Hash", out)
        out = sncast(package, *ACC, "deploy", "--url", URL, "--class-hash", class_hash,
                     "--constructor-calldata", address)
        addresses[name] = field("Contract Address", out)
    HUB, INST = addresses["Hub"], addresses["Instances"]


    NATIVE_SETUP = [
        (HUB, "set_instances", [INST]), (INST, "set_hub", [HUB]),
        *[(INST, "setup_worst_case", [str(i), address]) for i in (1, 7, 15, 5, 16)],
        *[(INST, "setup_queue", [str(i), str(g), address])
          for i, g in ((2, 8), (3, 8), (4, 8), (6, 0), (18, 8), (19, 8), (20, 8), (21, 0), (8, 8), (9, 8),
                       (10, 8), (17, 8))],
        *[(INST, "setup_board", [str(i), address]) for i in (11, 12, 13, 30, 31, 32, 33)],
        *[(INST, "setup_serpent", [str(i), address]) for i in (14, 25)],
        (HUB, "setup_alchemy", [address]), (HUB, "setup_hub", [address]),
    ]
    NATIVE_MEASURED = [
        ("worst-case tick, one felt per goblin, unchecked", INST, "attack", ["1", "1", FELT, "0"]),
        ("worst-case tick, one felt per goblin, checked", INST, "attack", ["7", "1", FELT, "1"]),
        ("worst-case tick, goblins packed, unchecked", INST, "attack", ["5", "1", PACKED, "0"]),
        ("worst-case tick, goblins packed, checked", INST, "attack", ["16", "1", PACKED, "1"]),
        ("worst-case tick, 11 slots per goblin, checked", INST, "attack", ["15", "1", SLOTS, "1"]),
        ("queue of 10 moves, unchecked", INST, "walk", ["2", *west(10), FELT, "0"]),
        ("queue of 5 moves, unchecked", INST, "walk", ["3", *west(5), FELT, "0"]),
        ("queue of 1 move, unchecked", INST, "walk", ["4", *west(1), FELT, "0"]),
        ("queue of 10 moves, no goblin, unchecked", INST, "walk", ["6", *west(10), FELT, "0"]),
        ("queue of 10 moves, checked", INST, "walk", ["18", *west(10), FELT, "1"]),
        ("queue of 5 moves, checked", INST, "walk", ["19", *west(5), FELT, "1"]),
        ("queue of 1 move, checked", INST, "walk", ["20", *west(1), FELT, "1"]),
        ("queue of 10 moves, no goblin, checked", INST, "walk", ["21", *west(10), FELT, "1"]),
        ("queue of 10 moves, goblins packed, checked", INST, "walk", ["8", *west(10), PACKED, "1"]),
        ("queue of 5 moves, goblins packed, checked", INST, "walk", ["9", *west(5), PACKED, "1"]),
        ("queue of 1 move, goblins packed, checked", INST, "walk", ["10", *west(1), PACKED, "1"]),
        ("queue of 10 moves, 11 slots per goblin, checked", INST, "walk", ["17", *west(10), SLOTS, "1"]),
        ("tick, corridor maze (45 layers unlimited; capped at 15), unchecked", INST, "attack", ["11", "1", FELT, "0"]),
        ("tick, unreachable target (13 layers), unchecked", INST, "attack", ["12", "1", FELT, "0"]),
        ("tick, deepest board found (92 layers unlimited; capped at 15), unchecked", INST, "attack", ["13", "1", FELT, "0"]),
        ("capped worst-case tick (15 layers, 8 goblins reached), one felt per goblin, unchecked", INST,
         "attack", ["30", "1", FELT, "0"]),
        ("capped worst-case tick (15 layers, 8 goblins reached), one felt per goblin, checked", INST,
         "attack", ["31", "1", FELT, "1"]),
        ("capped worst-case tick (15 layers, 8 goblins reached), goblins packed, checked", INST,
         "attack", ["32", "1", PACKED, "1"]),
        ("capped worst-case tick (15 layers, 8 goblins reached), goblins packed, unchecked", INST,
         "attack", ["33", "1", PACKED, "0"]),
        ("queue of 10 moves, serpentine (capped), unchecked", INST, "walk", ["14", *west(10), FELT, "0"]),
        ("queue of 10 moves, serpentine (capped), checked", INST, "walk", ["25", *west(10), FELT, "1"]),
        ("brew, signature, new pair", HUB, "brew", ["1", "1", "8", "9"]),
        ("brew, no signature, new pair", HUB, "brew_unsigned", ["2", "1", "8", "9"]),
        ("brew, known pair", HUB, "brew", ["1", "1", "8", "9"]),
        ("accept quest", HUB, "accept_quest", ["3", "1"]),
        ("claim quest", HUB, "claim_quest", ["3", "2"]),
        ("enter", HUB, "enter", ["3", "10"]),
        ("leave", INST, "leave", ["101"]),
    ]

    def native_invoke(contract, function, calldata):
        out = sncast(package, *ACC, "invoke", "--url", URL, "--contract-address", contract,
                     "--function", function, "--calldata", *calldata)
        return field("Transaction Hash", out)


    for contract, function, calldata in NATIVE_SETUP:
        native_invoke(contract, function, calldata)
    for label, contract, function, calldata in NATIVE_MEASURED:
        measure(side, label, native_invoke(contract, function, calldata))


run_native("native", NATIVE)
# The same sources built with Cairo 2.13 (Sierra 1.7.0): is the class metered by its version?
run(["python3", "build.py"], NATIVE213)
run_native("native-2.13", NATIVE213)

# ---------------------------------------------------------------------------------------------
# Dojo (part 1), on the same node and account

SOZO_ACCOUNT = ["--rpc-url", URL, "--account-address", address, "--private-key", KEY]
try:
    run(["./locked.sh", "sozo", "build", "--manifest-path", "Scarb.toml"], HERE)
    # devnet 0.10 (Starknet 0.14, chain id SN_SEPOLIA) checks the Blake2s compiled class hash
    out = run(["./locked.sh", "sozo", "migrate", "--manifest-path", "Scarb.toml", *SOZO_ACCOUNT,
               "--use-blake2s-casm-class-hash"], HERE)
    emit({"dojo_migrate": out[-800:]})
except Exception as error:  # noqa: BLE001
    emit({"dojo_migrate_error": str(error)[-3000:]})
    sys.exit(0)


def arr(n):
    return "arr:" + ",".join(["3"] * n)


DOJO_SETUP = [
    ("spk2-setup", "worst_case", ["1"]), ("spk2-setup", "worst_case", ["5"]),
    ("spk2-setup", "queue", ["2", "8"]), ("spk2-setup", "queue", ["3", "8"]),
    ("spk2-setup", "queue", ["4", "8"]), ("spk2-setup", "queue", ["6", "0"]),
    ("spk2-setup", "board", ["11"]), ("spk2-setup", "board", ["12"]), ("spk2-setup", "board", ["13"]),
    ("spk2-setup", "board", ["30"]), ("spk2-setup", "board", ["31"]),
    ("spk2-setup", "serpent", ["14"]), ("spk2-setup", "alchemy", []), ("spk2-setup", "hub", []),
]
DOJO_MEASURED = [
    ("worst-case tick", "spk2-tick_worst_case", "attack", ["1", "1"]),
    ("worst-case tick, packed goblins", "spk2-tick_worst_case", "attack_packed", ["5", "1"]),
    ("queue of 10 moves", "spk2-queue_moves", "walk", ["2", arr(10)]),
    ("queue of 5 moves", "spk2-queue_moves", "walk", ["3", arr(5)]),
    ("queue of 1 move", "spk2-queue_moves", "walk", ["4", arr(1)]),
    ("queue of 10 moves, no goblin", "spk2-queue_moves", "walk", ["6", arr(10)]),
    ("tick, corridor maze (45 layers unlimited; capped at 15)", "spk2-tick_worst_case", "attack", ["11", "1"]),
    ("tick, unreachable target (13 layers)", "spk2-tick_worst_case", "attack", ["12", "1"]),
    ("tick, deepest board found (92 layers unlimited; capped at 15)", "spk2-tick_worst_case", "attack", ["13", "1"]),
    ("capped worst-case tick (15 layers, 8 goblins reached)", "spk2-tick_worst_case", "attack", ["30", "1"]),
    ("capped worst-case tick (15 layers, 8 goblins reached), packed goblins", "spk2-tick_worst_case",
     "attack_packed", ["31", "1"]),
    ("queue of 10 moves, serpentine (capped)", "spk2-queue_moves", "walk", ["14", arr(10)]),
    ("brew, signature, new pair", "spk2-brew", "brew", ["1", "1", "8", "9"]),
    ("brew, no signature, new pair", "spk2-brew", "brew_unsigned", ["2", "1", "8", "9"]),
    ("brew, known pair", "spk2-brew", "brew", ["1", "1", "8", "9"]),
    ("accept quest", "spk2-hub", "accept_quest", ["3", "1"]),
    ("claim quest", "spk2-hub", "claim_quest", ["3", "2"]),
    ("enter", "spk2-hub", "enter", ["3", "10"]),
    ("leave", "spk2-hub", "leave", ["3"]),
]


def dojo_invoke(tag, function, calldata):
    out = run(["sozo", "execute", "--manifest-path", "Scarb.toml", *SOZO_ACCOUNT, "--wait", tag, function,
               *calldata], HERE)
    hashes = re.findall(r"0x[0-9a-fA-F]{40,}", out)
    if not hashes:
        raise RuntimeError(f"no transaction hash in: {out}")
    return hashes[-1]


for tag, function, calldata in DOJO_SETUP:
    dojo_invoke(tag, function, calldata)
for label, tag, function, calldata in DOJO_MEASURED:
    measure("dojo", label, dojo_invoke(tag, function, calldata))
