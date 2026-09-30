#!/usr/bin/env python3
"""ENG-06: the instance lifecycle on the local node, with the real contracts together: what each
entrypoint costs, from its receipt, and which storage keys it changes, from its trace's state diff,
each key classified new (0 before), overwritten or zeroed against every value the run wrote
(docs/briefs/ENG-06-instance-lifecycle.md AC-3, AC-5; ENG-01 §9.3 and §10).

Declares and deploys `Registry`, `TxHashFate`, `Hub` and `Instances`, registers them with each
other, writes the test region of `contracts/seed/` (region 1, locations 1-4, gates 1-5) and one
probe gate, 6: zone -> the dungeon's first floor, a link anchored on the zone's entry tile, so that
a location transition is reachable without `play` (ENG-07). Then one transaction per case:

  create_adventurer (x3)               D-144: the start hub read from the registry
  enter, first entry (cold)            a new slot: the slot's keys written for the first time
  leave to a hub (gate 2)              Returned, the town reached
  enter, later entry (initialised)     the slot reused, generation 2
  leave to a location (gate 6)         Moved: the next instance in the same slot, its entry draw
  leave to a location (gate 4)         Moved again, back to the zone
  travel_back                          Returned to the last hub
  travel                               map travel to the start town
  leave refused (a wrong sequence)     `Refused`, nothing changed
  set_build, 4 potions on 4 pages      CBT-08a: the belt `enter` reserves (adventurer 2)
  enter, the belt's worst case         4 pack pages debited, each lane emptied (D-148)
  leave to a hub / travel_back         the 4 pages credited back by the closing report
  set_account_owner, 0 to 3 inside     the real `Instances.set_controller`, from other accounts

Adventurer 1 carries no belt; adventurer 2 carries the belt's worst case. Its pack is filled by one
`report` the administrator sends while the hub names it as `instances` (no entrypoint fills a pack
yet), then the real `Instances` is registered again. The bar and the equipment stay empty on the
node: no entrypoint teaches a skill or creates an equipment entity yet (the snforge tests measure
them, with `store`). The first pre-funded account is the administrator and plays
account 1; accounts 2 to 4 of the node play the `set_account_owner` cases. One JSON line per
transaction on stdout. Local node only: the script refuses any node URL that is not 127.0.0.1 and
never reads a Sepolia variable. From the repository root, after
`scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build`:

    scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py \
        > contracts/tools/lifecycle-probe-output.txt
"""
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CONTRACTS = os.path.dirname(HERE)
URL = os.environ["NODE_URL"]
if urllib.parse.urlparse(URL).hostname != "127.0.0.1":
    sys.exit("lifecycle_probe: the local node only (NODE_URL must be on 127.0.0.1)")
ADDRESS = os.environ["NODE_ACCOUNT_ADDRESS"]
KEY = os.environ["NODE_ACCOUNT_PRIVATE_KEY"]
LOGS = os.environ.get("WITH_NODE_LOG_DIR", os.path.join(os.getcwd(), ".with-node"))
ACCOUNTS = os.path.join(LOGS, "accounts-eng06.json")

LIVE = 1 << 250
REGION, LOCATION, GATE, ITEM = 1, 2, 4, 11
HUB_GATE, LINK, FLOOR = 1, 2, 3
INGREDIENT, POTION = 1, 3


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


def sncast(package, *args):
    out = subprocess.run(["sncast", "--accounts-file", ACCOUNTS, *args],
                         cwd=os.path.join(CONTRACTS, package), capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"sncast {' '.join(args[:4])}: {out.stdout[-2000:]} {out.stderr[-2000:]}")
    return out.stdout + out.stderr


def field(label, text):
    match = re.search(rf"{label}:\s*(0x[0-9a-fA-F]+)", text)
    if not match:
        raise RuntimeError(f"no {label} in: {text}")
    return match.group(1)


# The registry's records, packed as `grimworld_logic::models` packs them (ENG-01 §3.5).
def short(text):
    return int.from_bytes(text.encode(), "big")


def region(town, book, first, name):
    return [town + (book << 16) + (first << 32) + (short(name) << 128) + LIVE]


def location(kind, width, target, floors, next_floor, entry_chunk, entry_tile):
    low = (kind + (1 << 8) + (1 << 24) + (1 << 32) + (3 << 40) + (width << 56) + (width << 64)
           + (target << 72) + (floors << 80) + (next_floor << 88))
    return [low + ((entry_chunk + (entry_tile << 8)) << 128) + LIVE, LIVE]


def gate(source, destination, anchor, entry, kind):
    low = (source + (destination << 16) + (anchor[0] << 32) + (anchor[1] << 40) + (entry[0] << 48)
           + (entry[1] << 56) + (kind << 64))
    return [low + LIVE]


def item(klass):
    """An `ITEM` of region 1, value 1. A potion's entry heals its holder, 20 at every rank
    (`HEAL`, `SELF`, `SINGLE`): `Registry.set_record` refuses a potion without a legal entry
    (D-166, `ItemAssert::assert_legal`)."""
    entry = 3 + (20 << 16) + (20 << 32) + (1 << 88) if klass == POTION else 0
    return [klass + (1 << 8) + (1 << 32) + (entry << 128) + LIVE]


# `set_build`'s words, without `LIVE` (ENG-01 §3.3): an empty bar (elite slot 255, bit 168), and a
# belt of items in lanes 0-3 and their counts in lane 4.
EMPTY_BUILD = 255 << 168
POTIONS = (1, 8, 15, 22)
OPEN = 0


def belt(items, counts):
    lane4 = sum(c << (8 * i) for i, c in enumerate(counts))
    return sum(it << (32 * i) for i, it in enumerate(items)) + (lane4 << 128)


if os.path.exists(ACCOUNTS):
    os.remove(ACCOUNTS)
chain = bytes.fromhex(rpc("starknet_chainId", [])[2:]).decode()
emit({"node": "starknet-devnet (scripts/with-node.sh)", "chain_id": chain,
      "spec": rpc("starknet_specVersion", [])})
players = rpc("devnet_getPredeployedAccounts", {})[:4]
assert int(players[0]["address"], 16) == int(ADDRESS, 16)
names = []
for i, player in enumerate(players):
    name = f"player{i}"
    sncast("persistent", "account", "import", "--url", URL, "--name", name, "--type", "oz",
           "--address", player["address"], "--private-key", player["private_key"])
    names.append(name)


def declare(package, name):
    out = sncast(package, "--account", names[0], "--wait", "declare", "--url", URL,
                 "--contract-name", name, "--package", f"grimworld_{package}")
    return field("Class Hash", out)


# Every storage value the run's transactions wrote, by (contract, key): the contracts are deployed
# by this run, so a key absent from it held 0 before (the node keeps no state of earlier blocks).
KNOWN = {}


def remember(tx):
    """The state diff of `tx`, recorded in `KNOWN`; returns (contract, before, after) per key."""
    trace = rpc("starknet_traceTransaction", {"transaction_hash": tx})
    diff = (trace.get("state_diff") or {}).get("storage_diffs", [])
    changes = []
    for entry in diff:
        address = int(entry["address"], 16)
        for slot in entry["storage_entries"]:
            key, value = int(slot["key"], 16), int(slot["value"], 16)
            changes.append((address, KNOWN.get((address, key), 0), value))
            KNOWN[(address, key)] = value
    return changes


def deploy(package, class_hash, *calldata):
    args = ["--constructor-calldata", *[hex(c) if isinstance(c, int) else c for c in calldata]] \
        if calldata else []
    out = sncast(package, "--account", names[0], "--wait", "deploy", "--url", URL, "--class-hash",
                 class_hash, *args)
    remember(field("Transaction Hash", out))
    return field("Contract Address", out)


registry = deploy("persistent", declare("persistent", "Registry"), ADDRESS)
fate = deploy("persistent", declare("persistent", "TxHashFate"))
hub = deploy("persistent", declare("persistent", "Hub"), ADDRESS, registry, 3, 4, fate)
instances = deploy("ephemeral", declare("ephemeral", "Instances"), ADDRESS, hub, registry, fate)
emit({"registry": registry, "fate": fate, "hub": hub, "instances": instances})
WATCHED = {int(hub, 16): "hub", int(instances, 16): "instances"}


def invoke(label, contract, function, *calldata, player=0, record=True):
    args = ["--calldata", *[hex(c) if isinstance(c, int) else c for c in calldata]] if calldata else []
    out = sncast("persistent", "--account", names[player], "--wait", "invoke", "--url", URL,
                 "--contract-address", contract, "--function", function, *args)
    tx = field("Transaction Hash", out)
    receipt = rpc("starknet_getTransactionReceipt", {"transaction_hash": tx})
    changes = remember(tx)
    if not record:
        return receipt
    counts = {}
    for address, prior, value in changes:
        who = WATCHED.get(address)
        if who is None or prior == value:
            continue
        kind = "new" if prior == 0 else ("zeroed" if value == 0 else "overwritten")
        counts.setdefault(who, {"new": 0, "overwritten": 0, "zeroed": 0})[kind] += 1
    events = [e for e in receipt.get("events", []) if int(e["from_address"], 16) in WATCHED]
    resources = receipt["execution_resources"]
    emit({
        "label": label,
        "tx": tx,
        "status": receipt.get("execution_status"),
        "l2_gas": resources.get("l2_gas"),
        "l1_data_gas": resources.get("l1_data_gas"),
        "l1_gas": resources.get("l1_gas"),
        "calldata_felts": len(calldata),
        "writes": counts,
        "events": len(events),
    })
    return receipt


def entered(receipt):
    """The id of the instance the receipt's `InstanceEntered` names (its second key): the only
    event of `Instances` with three data felts (adventurer, location, gate)."""
    for event in receipt["events"]:
        if int(event["from_address"], 16) == int(instances, 16) and len(event["keys"]) == 2 \
                and len(event["data"]) == 3:
            return int(event["keys"][1], 16)
    raise RuntimeError("no InstanceEntered")


invoke("Hub.set_contracts", hub, "set_contracts", registry, instances, 4, fate, record=False)
records = [(REGION, 1, region(1, 0, 1, "Test Region")),
           (LOCATION, 1, location(1, 0, 0, 0, 0, 0, 0)),
           (LOCATION, 2, location(3, 3, 0, 0, 0, 0, 105)),
           (LOCATION, 3, location(4, 15, 6, 2, 4, 112, 112)),
           (LOCATION, 4, location(4, 15, 8, 2, 0, 112, 112)),
           (GATE, 1, gate(1, 2, (0, 0), (0, 105), HUB_GATE)),
           (GATE, 2, gate(2, 1, (0, 105), (0, 0), HUB_GATE)),
           (GATE, 3, gate(2, 3, (16, 110), (112, 112), LINK)),
           (GATE, 4, gate(3, 2, (112, 112), (16, 110), LINK)),
           (GATE, 5, gate(3, 4, (0, 0), (112, 112), FLOOR)),
           (GATE, 6, gate(2, 3, (0, 105), (112, 112), LINK))]
# Items 1 to 22 (sequential ids): potions 1, 8, 15, 22, one per pack page; the others ingredients.
records += [(ITEM, i, item(POTION if i in POTIONS else INGREDIENT)) for i in range(1, 23)]
for kind, rid, parts in records:
    invoke(f"set_record {kind} {rid}", registry, "set_record", kind, rid, len(parts), *parts,
           record=False)

invoke("register", hub, "register")
invoke("create_adventurer, cold (D-144: the start hub from the registry)", hub,
       "create_adventurer", short("Aldric"), 1)
invoke("create_adventurer, initialised", hub, "create_adventurer", short("Brenna"), 2)
invoke("create_adventurer, initialised (third)", hub, "create_adventurer", short("Cedric"), 3)

first = entered(invoke("enter, first entry (cold: a new slot)", hub, "enter", 1, 1))
invoke("leave to a hub (gate 2: Returned, the town reached)", instances, "leave", first, 1, 0, 2)
second = entered(invoke("enter, later entry (initialised: the slot reused)", hub, "enter", 1, 1))
third = entered(invoke("leave to a location (gate 6: Moved, the next instance, its draw)",
                       instances, "leave", second, 1, 0, 6))
fourth = entered(invoke("leave to a location again (gate 4: back to the zone)", instances, "leave",
                        third, 1, 0, 4))
invoke("travel_back (Returned to the last hub)", instances, "travel_back", fourth, 1, 0)
invoke("travel (to the start town)", hub, "travel", 1, 1)
fifth = entered(invoke("enter, later entry (again)", hub, "enter", 1, 1))
invoke("leave refused (sequence 7 against 0: Refused)", instances, "leave", fifth, 1, 7, 2)

# CBT-08a: the belt's worst case (D-148), with adventurer 2: four potions (items 1, 8, 15, 22, lane
# 1 of pack pages 0 to 3) carried in by `set_build`, debited by `enter`, credited back by the
# closing report. No entrypoint fills a pack yet but a report, so the probe credits it with one:
# the hub's `instances` is pointed at the administrator's account for one `report` (Open, the four
# balances, from an instance the adventurer is inside), then back; then the adventurer leaves.
setup_in = entered(invoke("enter (adventurer 2, to fill its pack)", hub, "enter", 2, 1,
                          record=False))
invoke("Hub.set_contracts (instances: the administrator)", hub, "set_contracts", registry,
       ADDRESS, 4, fate, record=False)
invoke("report (Open: 3 of each potion into the pack)", hub, "report",
       setup_in, 1, 2, 0, 0, 4, *[f for item in POTIONS for f in (item, 3)], 0, 0, 0, 0,
       OPEN, 0, 0, 0, 0, 0, 0, record=False)
invoke("Hub.set_contracts (instances back)", hub, "set_contracts", registry, instances, 4, fate,
       record=False)
invoke("leave to a hub", instances, "leave", setup_in, 2, 0, 2, record=False)
invoke("set_build, 4 potions on 4 pack pages (empty bar, no equipment)", hub, "set_build", 2,
       EMPTY_BUILD, belt(POTIONS, (3, 3, 3, 3)), 0)
belted = entered(invoke("enter, later entry, the belt's worst case (4 pages, each lane emptied)",
                        hub, "enter", 2, 1))
invoke("leave to a hub, the belt credited back (4 pages)", instances, "leave", belted, 2, 0, 2)
belted = entered(invoke("enter, later entry, the belt's worst case (again)", hub, "enter", 2, 1))
invoke("travel_back, the belt credited back (4 pages)", instances, "travel_back", belted, 2, 0)

# set_account_owner with k adventurers inside, k = 0 to 3, the real set_controller (D-144).
# Accounts 2, 3 and 4 are players 3, 1 and 2's; adventurers 4 to 7 theirs.
next_adventurer = 4
for k, player in ((0, 3), (1, 1), (2, 2)):
    invoke(f"register (account of player {player})", hub, "register", player=player, record=False)
    ids = []
    for n in range(max(k, 1)):
        invoke("create_adventurer", hub, "create_adventurer", short(f"P{player}A{n}"), 1,
               player=player, record=False)
        ids.append(next_adventurer)
        next_adventurer += 1
    for adventurer in ids[:k]:
        invoke("enter", hub, "enter", adventurer, 1, player=player, record=False)
    account = {3: 2, 1: 3, 2: 4}[player]
    invoke(f"set_account_owner, {k} inside", hub, "set_account_owner", account,
           0x1000 + player, player=player)
for adventurer in (2, 3):
    invoke("enter", hub, "enter", adventurer, 1, record=False)
invoke("set_account_owner, 3 inside", hub, "set_account_owner", 1, 0x2000)
