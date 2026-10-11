#!/usr/bin/env python3
"""OPS-01a: deploys the game on a local `starknet-devnet` for the client's tests, and writes where
everything is. The local-node first part of OPS-01 (the full deployment scripts, Sepolia included,
stay queued). From the repository root, after
`scripts/lock.sh --heavy scarb --manifest-path contracts/Scarb.toml build`:

    scripts/with-node.sh python3 scripts/devnet_deploy.py --out deployment.json

What it does, in the order `contracts/tools/lifecycle_probe.py` uses (the probe is the reference):
the classes are declared and `Registry` deployed, then `set_zone_checks` at once (before any record:
BND-01's guard refuses a GATE, QUOTAS or chunk-set OUTLINE otherwise), `TxHashFate`, the libraries,
`Hub`, `Instances`; `Hub.set_contracts`; the play classes (`Instances.set_play_class`, keys 0-5);
the records of `contracts/seed/` (the test region, and the fight content the probe's `--fight on`
writes: the zone names spawn table 1); `Hub.register`; one adventurer, `Hub.set_build` (an empty bar,
no belt), `Hub.enter` through gate 1 (the start hub into the zone) for the first pre-funded account.

Local node only: it refuses any NODE_URL that is not 127.0.0.1 and never reads a Sepolia variable.
It runs once per node: a node whose first account has already sent a transaction is refused (exit 1)
with a message, and nothing is deployed. The private key is read from the environment `with-node.sh`
sets, used to import the account into a throwaway `sncast` accounts file (under $WITH_NODE_LOG_DIR),
and never printed or written; the client reads it from devnet's `devnet_getPredeployedAccounts`.

The JSON file (`--out <path>`; without it the JSON goes to stdout) is an interface track CV's tests
read. Its keys, all strings of hex felts unless noted:

    node_url          the node's URL (http://127.0.0.1:<port>)
    chain_id          the chain id as text (SN_SEPOLIA on a devnet)
    commit            the git commit of the build (`git rev-parse HEAD`; "unknown" without git)
    account           the first pre-funded account's address (no key)
    classes           {registry, zone_checks, tx_hash_fate, hub, instances, reveal_library,
                       hosts_library, trap_library, flatten_library, play_library, tick_library,
                       ai_library, action_library, executor_library, segment_library}: class hashes
    contracts         {registry, tx_hash_fate, hub, instances}: addresses
    adventurer_id     the adventurer created, built and entered (a number)
    instance_id       the instance it entered: `InstanceEntered`'s id (a number)
    slot              the instance's slot, `instance_id >> 32` (a number)
"""
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTRACTS = os.path.join(ROOT, "contracts")
sys.path.insert(0, os.path.join(CONTRACTS, "tools"))
from seed_records import (  # noqa: E402  the records, shared with the lifecycle probe
    GATE, HUB_GATE, INGREDIENT, ITEM, LINK, FLOOR, LIVE, LOCATION, POTION, REGION,
    caste_record, gate, item, location, pack_record, region, seed_rows, short, skill_record,
    spawn_table_record)

# D-176: `sncast declare` builds the contract with Scarb; the build is single-threaded.
os.environ["RAYON_NUM_THREADS"] = "1"

POTIONS = (1, 8, 15, 22)
EMPTY_BUILD = 255 << 168  # an empty bar (elite slot 255, bit 168), ENG-01 §3.3
PLAY_CLASSES = [("ephemeral", "PlayLibrary"), ("logic", "TickLibrary"), ("logic", "AiLibrary"),
                ("logic", "ActionLibrary"), ("logic", "ExecutorLibrary"),
                ("logic", "SegmentLibrary")]


class Node:
    """The local node and the first pre-funded account, through the JSON-RPC and `sncast`."""

    def __init__(self, url, address, key, logs):
        if urllib.parse.urlparse(url).hostname != "127.0.0.1":
            sys.exit("devnet_deploy: the local node only (NODE_URL must be on 127.0.0.1)")
        self.url, self.address = url, address
        os.makedirs(logs, exist_ok=True)
        self.accounts = os.path.join(logs, "accounts-devnet-deploy.json")
        if os.path.exists(self.accounts):
            os.remove(self.accounts)
        self.key = key

    def rpc(self, method, params):
        body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
        request = urllib.request.Request(self.url, data=body,
                                         headers={"content-type": "application/json"})
        with urllib.request.urlopen(request, timeout=60) as response:
            answer = json.load(response)
        if "error" in answer:
            raise RuntimeError(f"{method}: {answer['error']}")
        return answer["result"]

    def sncast(self, package, *args, account=True):
        accounts = ["--accounts-file", self.accounts] if account else []
        out = subprocess.run(["sncast", *accounts, *args], cwd=os.path.join(CONTRACTS, package),
                             capture_output=True, text=True)
        if out.returncode != 0:
            # sncast echoes the command's arguments only on a usage error, never the key we import
            raise RuntimeError(f"sncast {' '.join(args[:4])}: {out.stdout[-2000:]} {out.stderr[-2000:]}")
        return out.stdout + out.stderr

    def import_account(self):
        # the key goes to sncast's argv, as in the probe; local node, test account
        self.sncast("persistent", "account", "import", "--url", self.url, "--name", "deployer",
                    "--type", "oz", "--address", self.address, "--private-key", self.key)
        self.key = None

    def declare(self, package, name):
        out = self.sncast(package, "--account", "deployer", "--wait", "declare", "--url", self.url,
                          "--contract-name", name, "--package", f"grimworld_{package}")
        return field("Class Hash", out)

    def deploy(self, package, class_hash, *calldata):
        args = ["--constructor-calldata", *[hex(c) if isinstance(c, int) else c for c in calldata]] \
            if calldata else []
        out = self.sncast(package, "--account", "deployer", "--wait", "deploy", "--url", self.url,
                          "--class-hash", class_hash, *args)
        return field("Contract Address", out)

    def invoke(self, contract, function, *calldata):
        args = ["--calldata", *[hex(c) if isinstance(c, int) else c for c in calldata]] \
            if calldata else []
        out = self.sncast("persistent", "--account", "deployer", "--wait", "invoke", "--url",
                          self.url, "--contract-address", contract, "--function", function, *args)
        tx = field("Transaction Hash", out)
        receipt = self.rpc("starknet_getTransactionReceipt", {"transaction_hash": tx})
        if receipt.get("execution_status") != "SUCCEEDED":
            raise RuntimeError(f"{function} reverted: {receipt.get('revert_reason')}")
        return receipt

    def view(self, package, contract, function, *calldata):
        """The raw response of a view, as felts."""
        out = self.sncast(package, "call", "--url", self.url, "--contract-address", contract,
                          "--function", function, *(["--calldata", *[hex(c) for c in calldata]]
                                                    if calldata else []),
                          "--block-id", "latest", account=False)
        match = re.search(r"Response Raw:\s*\[([^\]]*)\]", out)
        if not match:
            raise RuntimeError(f"{function}: no raw response in: {out}")
        return [int(f.strip(), 16) for f in match.group(1).split(",") if f.strip()]


def field(label, text):
    match = re.search(rf"{label}:\s*(0x[0-9a-fA-F]+)", text)
    if not match:
        raise RuntimeError(f"no {label} in: {text}")
    return match.group(1)


def entered(receipt, instances):
    """The id `InstanceEntered` names (its second key): the only event of `Instances` with three
    data felts (adventurer, location, gate)."""
    for event in receipt["events"]:
        if int(event["from_address"], 16) == int(instances, 16) and len(event["keys"]) == 2 \
                and len(event["data"]) == 3:
            return int(event["keys"][1], 16)
    raise RuntimeError("no InstanceEntered")


def seed_records():
    """The test region, its start hub, zone (naming spawn table 1) and dungeon, the gates, the
    items, and the probe's `--fight on` content: skills, castes, packs, spawn tables."""
    records = [(REGION, 1, region(1, 0, 1, "Test Region")),
               (LOCATION, 1, location(1, 0, 0, 0, 0, 0, 0)),
               (LOCATION, 2, location(3, 3, 0, 0, 0, 0, 105, spawn_table=1)),
               (LOCATION, 3, location(4, 15, 6, 2, 4, 112, 112)),
               (LOCATION, 4, location(4, 15, 8, 2, 0, 112, 112)),
               (GATE, 1, gate(1, 2, (0, 0), (0, 105), HUB_GATE)),
               (GATE, 2, gate(2, 1, (0, 105), (0, 0), HUB_GATE)),
               (GATE, 3, gate(2, 3, (16, 110), (112, 112), LINK)),
               (GATE, 4, gate(3, 2, (112, 112), (16, 110), LINK)),
               (GATE, 5, gate(3, 4, (0, 0), (112, 112), FLOOR)),
               (GATE, 6, gate(2, 3, (0, 105), (112, 112), LINK))]
    records += [(ITEM, i, item(POTION if i in POTIONS else INGREDIENT)) for i in range(1, 23)]
    records += [(9, row[0], skill_record(row)) for row in seed_rows("skills", 47)]
    records += [(8, row[0], caste_record(row)) for row in seed_rows("castes", 30)]
    records += [(7, row[0], pack_record(row)) for row in seed_rows("packs", 17)]
    records += [(6, row[0], spawn_table_record(row)) for row in seed_rows("spawn_tables", 16)]
    return records


def commit():
    out = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else "unknown"


def main(argv):
    out_path = None
    if argv:
        if len(argv) != 2 or argv[0] != "--out":
            sys.exit("usage: scripts/with-node.sh python3 scripts/devnet_deploy.py [--out <file>]")
        out_path = argv[1]
    try:
        url = os.environ["NODE_URL"]
        address = os.environ["NODE_ACCOUNT_ADDRESS"]
        key = os.environ["NODE_ACCOUNT_PRIVATE_KEY"]
    except KeyError as missing:
        sys.exit(f"devnet_deploy: {missing} is not set (run under scripts/with-node.sh)")
    node = Node(url, address, key,
                os.environ.get("WITH_NODE_LOG_DIR", os.path.join(os.getcwd(), ".with-node")))

    nonce = int(node.rpc("starknet_getNonce", {"block_id": "latest", "contract_address": address}), 16)
    if nonce != 0:
        print(f"devnet_deploy: this node already has a deployment (the account {address} has sent "
              f"{nonce} transactions); use a fresh node", file=sys.stderr)
        return 1
    chain = bytes.fromhex(node.rpc("starknet_chainId", [])[2:]).decode()
    node.import_account()

    classes = {}
    registry_class = node.declare("persistent", "Registry")
    registry = node.deploy("persistent", registry_class, address)
    # ENG-09 (D-245): the zone checks are set right after the Registry, before any record
    classes["zone_checks"] = node.declare("persistent", "ZoneChecks")
    node.invoke(registry, "set_zone_checks", classes["zone_checks"])
    classes["tx_hash_fate"] = node.declare("persistent", "TxHashFate")
    fate = node.deploy("persistent", classes["tx_hash_fate"])
    classes["reveal_library"] = node.declare("logic", "RevealLibrary")
    classes["hosts_library"] = node.declare("logic", "HostsLibrary")
    classes["trap_library"] = node.declare("logic", "TrapLibrary")
    classes["hub"] = node.declare("persistent", "Hub")
    hub = node.deploy("persistent", classes["hub"], address, registry, 3, 4, fate)
    classes["flatten_library"] = node.declare("logic", "FlattenLibrary")
    classes["instances"] = node.declare("ephemeral", "Instances")
    instances = node.deploy("ephemeral", classes["instances"], address, hub, registry, fate,
                            classes["reveal_library"], classes["hosts_library"],
                            classes["trap_library"])
    node.invoke(hub, "set_contracts", registry, instances, 4, fate, classes["flatten_library"])
    play = {}
    for key_, (package, name) in enumerate(PLAY_CLASSES):
        play[name] = node.declare(package, name)
        node.sncast("ephemeral", "--account", "deployer", "--wait", "invoke", "--url", node.url,
                    "--contract-address", instances, "--function", "set_play_class",
                    "--calldata", hex(key_), play[name])
    for kind, rid, parts in seed_records():
        node.invoke(registry, "set_record", kind, rid, len(parts), *parts)

    node.invoke(hub, "register")
    node.invoke(hub, "create_adventurer", short("Aldric"), 1)
    adventurer = 1  # the first the hub creates (it counts from 1)
    node.invoke(hub, "set_build", adventurer, EMPTY_BUILD, 0, 0)
    instance = entered(node.invoke(hub, "enter", adventurer, 1), instances)

    result = {
        "node_url": url, "chain_id": chain, "commit": commit(), "account": address,
        "classes": {"registry": registry_class, **classes,
                    **{re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower(): h
                       for name, h in play.items()}},
        "contracts": {"registry": registry, "tx_hash_fate": fate, "hub": hub,
                      "instances": instances},
        "adventurer_id": adventurer, "instance_id": instance, "slot": instance >> 32,
    }
    text = json.dumps(result, indent=2) + "\n"
    if out_path:
        with open(out_path, "w") as out:
            out.write(text)
        print(f"devnet_deploy: wrote {out_path}", file=sys.stderr)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
