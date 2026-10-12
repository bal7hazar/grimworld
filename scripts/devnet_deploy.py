#!/usr/bin/env python3
"""OPS-01a: deploys the game on a local `starknet-devnet` for the client's tests, and writes where
everything is. The local-node first part of OPS-01 (the full deployment scripts, Sepolia included,
stay queued). From the repository root, after
`scripts/lock.sh --heavy scarb --manifest-path contracts/Scarb.toml build`:

    scripts/with-node.sh python3 scripts/devnet_deploy.py --out deployment.json

What it does, in the order `contracts/tools/lifecycle_probe.py` uses (the probe is the reference):
the classes are declared and `Registry` deployed, then `set_zone_checks` at once (before any record:
BND-01's guard refuses a GATE, QUOTAS or chunk-set OUTLINE otherwise), `TxHashFate`, the libraries,
`Hub`, `Instances`; `Hub.set_contracts`; the play classes (`Instances.set_play_class`, keys 0-6);
the records of `contracts/seed/` (the test region, and the fight content the probe's `--fight on`
writes: the zone names spawn table 1); `Hub.register`; one adventurer, `Hub.set_build` (an empty bar,
no belt), `Hub.enter` through gate 1 (the start hub into the zone) for the first pre-funded account.

OPS-01b, `--build full` (the default is `--build empty`, as above): the adventurer is built from the seed's
own records before it enters. The pack is funded first, as the lifecycle probe does (no entrypoint fills a
pack yet but `Hub.report`): the adventurer enters once, the hub's `instances` is pointed at the account
for one `report` (Open) that credits the potions, then back, and the adventurer leaves by gate 2; then
`set_build` carries the belt, and the entry that follows is the one the JSON names. What the seed gives:
bar: skill 1 (an instant attack) is the seed's only skill, and no entrypoint makes a skill known (the
`known_skills` words are never written, `set_build` refuses an unknown one, and devnet has no
set-storage), so the bar stays empty and the skills wanted are named under `build.dropped`; belt: healing
potion (item 1) x2, the seed has no REGENERATION potion (every potion heals), so that kind is dropped;
pack: twice the belt, so the entry debits the belt and one re-entry with it is covered. Seed ids come
from `build_plan()`, which reads `seed_records()`'s rows, never hard-coded; the seed is not changed.

Local node only: it refuses any NODE_URL that is not 127.0.0.1 and never reads a Sepolia variable.
It runs once per node: a node whose first account has already sent a transaction is refused (exit 1)
with a message, and nothing is deployed. The node must be a devnet whose `devnet_getPredeployedAccounts`
answers with the account first, and the URL must be exactly `http://127.0.0.1:<port>`. The private key
is read from the environment `with-node.sh` sets and written only to `sncast`'s throwaway accounts file
under $WITH_NODE_LOG_DIR (default `.with-node/`, gitignored); it is never printed or put in the JSON,
and the client reads it from devnet's `devnet_getPredeployedAccounts`.

The JSON file (`--out <path>`; without it the JSON goes to stdout) is an interface track CV's tests
read. Its keys, all strings of hex felts unless noted:

    node_url          the node's URL (http://127.0.0.1:<port>)
    chain_id          the chain id as text (SN_SEPOLIA on a devnet)
    commit            the git commit of the build (`git rev-parse HEAD`; "unknown" without git)
    account           the first pre-funded account's address (no key)
    classes           {registry, zone_checks, tx_hash_fate, hub, instances, reveal_library,
                       hosts_library, trap_library, flatten_library, play_library, tick_library,
                       ai_library, action_library, executor_library, segment_library,
                       goblins_library}: class hashes
    contracts         {registry, tx_hash_fate, hub, instances}: addresses
    adventurer_id     the adventurer created, built and entered (a number)
    instance_id       the instance it entered: `InstanceEntered`'s id (a number)
    slot              the instance's slot, `instance_id >> 32` (a number)
    build             what the adventurer was built with (OPS-01b; numbers): {mode, bar: the 8 skill
                       ids by slot (0 empty), belt: [{item, count}], pack: [{item, count}] funded
                       before the entry, pack_after_entry: [{item, count}] what the entry left (derived, listed in
                       `derived`: no view reads a pack yet),
                       dropped: {name: reason} for each part the seed or the chain cannot give}
"""
import argparse
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
BAR_SLOTS = 8
HUB_GATE_BACK = 2  # the gate from the zone back to the start hub (`seed_records`)
OPEN = 0  # `Outcome::Open`
PLAY_CLASSES = [("ephemeral", "PlayLibrary"), ("logic", "TickLibrary"), ("logic", "AiLibrary"),
                ("logic", "ActionLibrary"), ("logic", "ExecutorLibrary"),
                ("logic", "SegmentLibrary"), ("ephemeral", "GoblinsLibrary")]


def check_url(url):
    """The local node only: exactly `http://127.0.0.1:<port>` (no userinfo, no backslash tricks)."""
    parts = urllib.parse.urlparse(url)
    if parts.scheme != "http" or not re.fullmatch(r"127\.0\.0\.1:[0-9]{1,5}", parts.netloc) \
            or parts.path not in ("", "/") or parts.query or parts.fragment or "\\" in url:
        sys.exit("devnet_deploy: the local node only (NODE_URL must be http://127.0.0.1:<port>)")


class Node:
    """The local node and the first pre-funded account, through the JSON-RPC and `sncast`."""

    def __init__(self, url, address, key, logs):
        check_url(url)
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
        # as in the probe: sncast stores it in its throwaway accounts file (local node, test account)
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


def build_word(bar):
    """`set_build`'s `Build` word without `LIVE`: the bar's skills at 16 bits a slot, no attribute
    rank, no elite (slot 255, bit 168)."""
    return sum(skill << (16 * slot) for slot, skill in enumerate(bar)) + EMPTY_BUILD


def belt_word(belt):
    """`set_build`'s belt word: the items in lanes 0-3, their counts in lane 4 (8 bits each)."""
    items, counts = [i for i, _ in belt], [c for _, c in belt]
    return (sum(item << (32 * lane) for lane, item in enumerate(items))
            + (sum(c << (8 * lane) for lane, c in enumerate(counts)) << 128))


def build_plan():
    """What `--build full` asks of the seed (OPS-01b), read from `seed_records()`'s tables, never
    hard-coded: the four skills wanted, the two potions wanted, and what the seed lacks."""
    columns = ("id", "profession", "attribute", "kind", "energy", "adrenaline", "activation")
    rows = []
    for row in seed_rows("skills", 47):
        entries = [row[11 + 12 * i] for i in range(3)]  # each entry's kind, `skill_record`'s order
        rows.append({**dict(zip(columns, row)), "entries": entries})
    wanted = {  # name: (what it is, its test over a skill row)
        "instant_attack": ("instant attack skill", lambda r: r["kind"] == 1 and r["activation"] == 0),
        "activation_skill": ("skill with an activation of 1 or more", lambda r: r["activation"] >= 1),
        "trap": ("trap skill", lambda r: r["kind"] == 9),
        "regeneration_skill": ("skill with a REGENERATION entry", lambda r: 5 in r["entries"]),
    }
    skills, dropped = {}, {}
    for name, (what, test) in wanted.items():
        found = [r["id"] for r in rows if test(r) and r["id"] not in skills.values()]
        if found:
            skills[name] = found[0]
        else:
            dropped[name] = f"the seed has no {what}"
    # every potion of the seed heals (`seed_records.item`): the first is the healing potion, and
    # there is no REGENERATION potion
    if skills:  # found in the seed, but never on the bar
        dropped["bar"] = ("no entrypoint makes a skill known (buy_skill is not implemented, D-275; "
                          "devnet has no set-storage): the skills wanted are in `skills_wanted`")
    dropped["regeneration_potion"] = "the seed has no REGENERATION potion (every potion heals)"
    return {"skills": skills, "belt": [(POTIONS[0], 2)], "dropped": dropped}


def commit():
    out = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else "unknown"


def parse(argv):
    plan = build_plan()
    skills = ", ".join(f"{name} = skill {skill}" for name, skill in plan["skills"].items()) or "none"
    belt = ", ".join(f"item {item} x{count}" for item, count in plan["belt"])
    dropped = "; ".join(f"{name}: {why}" for name, why in plan["dropped"].items()) or "none"
    parser = argparse.ArgumentParser(
        prog="scripts/with-node.sh python3 scripts/devnet_deploy.py",
        description="Deploys the game on a local starknet-devnet.",
        epilog=f"--build full (OPS-01b) ids, read from the seed. Skills wanted: {skills} (none can "
               f"go on the bar: no entrypoint makes a skill known). Belt: {belt}. The pack holds "
               f"twice the belt. Dropped: {dropped}. The same ids are in the JSON's `build` key.")
    parser.add_argument("--out", help="write the JSON here instead of stdout")
    parser.add_argument("--build", choices=("empty", "full"), default="empty",
                        help="the adventurer's build: empty (default: an empty bar, no belt) or "
                             "full (a belt of the seed's potions and a pack for a second entry)")
    return parser.parse_args(argv)


def fund_pack(node, hub, instances, registry, fate, flatten, adventurer, credits):
    """The pack, as the lifecycle probe does it: `report` is the only call that credits a pack. The
    adventurer enters, the hub's `instances` is the account for one Open report, then it is the real
    `Instances` again and the adventurer leaves by the gate back to the start hub."""
    inside = entered(node.invoke(hub, "enter", adventurer, 1), instances)
    node.invoke(hub, "set_contracts", registry, node.address, 4, fate, flatten)
    try:
        node.invoke(hub, "report", inside, 1, adventurer, 0, 0, len(credits),
                    *[f for item, count in credits for f in (item, count)],
                    0, 0, 0, 0, OPEN, 0, 0, 0, 0, 0, 0)
    finally:  # the real `Instances` is restored even when the report fails
        node.invoke(hub, "set_contracts", registry, instances, 4, fate, flatten)
    node.invoke(instances, "leave", inside, adventurer, 0, HUB_GATE_BACK)


def main(argv):
    args = parse(argv)
    out_path = args.out
    try:
        url = os.environ["NODE_URL"]
        address = os.environ["NODE_ACCOUNT_ADDRESS"]
        key = os.environ["NODE_ACCOUNT_PRIVATE_KEY"]
    except KeyError as missing:
        sys.exit(f"devnet_deploy: {missing} is not set (run under scripts/with-node.sh)")
    node = Node(url, address, key,
                os.environ.get("WITH_NODE_LOG_DIR", os.path.join(os.getcwd(), ".with-node")))

    try:
        predeployed = node.rpc("devnet_getPredeployedAccounts", {})
    except Exception as error:  # not a devnet: the method is unknown
        sys.exit(f"devnet_deploy: the node is not a starknet-devnet ({error})")
    if not predeployed or int(predeployed[0]["address"], 16) != int(address, 16):
        sys.exit("devnet_deploy: the first predeployed account of the node is not NODE_ACCOUNT_ADDRESS")
    nonce = int(node.rpc("starknet_getNonce", {"block_id": "latest", "contract_address": address}), 16)
    if nonce != 0:
        print(f"devnet_deploy: this node already has a deployment (the account {address} "
              f"has sent {nonce} transactions (an earlier deployment, or another tool); use a fresh "
              "node)", file=sys.stderr)
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
        node.invoke(instances, "set_play_class", key_, play[name])
    for kind, rid, parts in seed_records():
        node.invoke(registry, "set_record", kind, rid, len(parts), *parts)

    node.invoke(hub, "register")
    node.invoke(hub, "create_adventurer", short("Aldric"), 1)
    adventurer = 1  # the first the hub creates (it counts from 1)
    node.invoke(hub, "set_build", adventurer, EMPTY_BUILD, 0, 0)
    plan = build_plan()
    bar = [0] * BAR_SLOTS  # no skill can be made known on chain: see the module docstring
    belt, pack, left = [], [], []
    if args.build == "full":
        belt = plan["belt"]
        pack = [(item, 2 * count) for item, count in belt]
        left = [(item, count) for item, count in belt]
        fund_pack(node, hub, instances, registry, fate, classes["flatten_library"], adventurer, pack)
        node.invoke(hub, "set_build", adventurer, build_word(bar), belt_word(belt), 0)
    instance = entered(node.invoke(hub, "enter", adventurer, 1), instances)

    result = {
        "node_url": url, "chain_id": chain, "commit": commit(), "account": address,
        "classes": {"registry": registry_class, **classes,
                    **{re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower(): h
                       for name, h in play.items()}},
        "contracts": {"registry": registry, "tx_hash_fate": fate, "hub": hub,
                      "instances": instances},
        "adventurer_id": adventurer, "instance_id": instance, "slot": instance >> 32,
        "build": {"mode": args.build, "bar": bar,
                  "belt": [{"item": i, "count": c} for i, c in belt],
                  "pack": [{"item": i, "count": c} for i, c in pack],
                  "pack_after_entry": [{"item": i, "count": c} for i, c in left],
                  "derived": ["pack_after_entry"],  # computed here (no pack view yet), not read
                  "dropped": plan["dropped"] if args.build == "full" else {},
                  **({"skills_wanted": plan["skills"]} if args.build == "full" else {})},
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
