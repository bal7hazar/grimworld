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
  set_build, empty, first              CBT-02e (D-168): the snapshot flattened by `FlattenLibrary`,
                                       its three words new (the first write's premium)
  set_build, empty, again              the three words written with the values they hold
  set_build, counts / slots swapped    fix loop 1: one snapshot word (the kit) overwritten
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

Declares `FlattenLibrary` (grimworld_logic) and registers its class hash with `Hub.set_contracts`
(D-168): `enter` copies the snapshot `set_build` stored and refuses a missing one, so every
adventurer's `set_build` comes before its first `enter`. Adventurer 1 carries no belt; adventurer 2
carries the belt's worst case. Its pack is filled by one
`report` the administrator sends while the hub names it as `instances` (no entrypoint fills a pack
yet), then the real `Instances` is registered again. The bar and the equipment stay empty on the
node: no entrypoint teaches a skill or creates an equipment entity yet (the snforge tests measure
them, with `store`). The first pre-funded account is the administrator and plays
account 1; accounts 2 to 4 of the node play the `set_account_owner` cases. One JSON line per
transaction on stdout. Local node only: the script refuses any node URL that is not 127.0.0.1 and
never reads a Sepolia variable. From the repository root, after
`scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build` (it takes the heavy lock itself):

    scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py \
        > contracts/tools/lifecycle-probe-output.txt

ENG-R1a (the event stream and the layout kept, AC-3): with `--stream <file>` the run also
writes, as JSON, every transaction after `Hub`'s deployment in order (recorded or not): `Hub`'s
storage writes (key, value) and every event of `Hub` (keys and data) and of `Instances` (its name's
selector alone: its draws follow the transaction hashes, which follow the addresses), in emission
order; then every key of `Hub`'s storage with its last value. The deployed addresses and
`FlattenLibrary`'s class hash in a value are replaced by their names, so that two runs of different
classes compare. `lifecycle-stream-before.json`, recorded on `main`'s code before ENG-R1a, is the
stream the indexer reads and the storage `Hub` keeps: ENG-R1b and every later lot that touches
`Hub`'s storage or events run `--expect` against it, and a change of it is a change of ENG-01's
frozen events or layout (D-149). With `--expect <file>` it compares its stream with that file's and exits 1
on the first difference.

ENG-07t (`--fight on`, with `--play on`): the seed's castes and skill (`contracts/seed/test-region.json`)
and the packs and spawn table the zone names are written (the zone, location 2, then names spawn table
1), and after the exploration the adventurer walks to the nearest pack of the revealed chunks (revealing
what sight touches on the way), then plays 10 Waits within 3 tiles of it: a fight batch, the goblins
engaging it. The case is behind the option, so the compared streams (`--stream`, `--expect`) and the
recorded output do not move without it. The scenario is fixed (the zone's entry, the walk toward the
nearest pack of the revealed chunks, 10 Waits within 3 tiles of it), the packs are not: the entry
draw follows the transaction hash, which the node does not let a script fix. A run counts only when
the member is engaged (its health fell, or a goblin of the pack has a record afterwards); the line
`fight` gives the pack's goblins (entity ids), those with a record (tile, health) and the member's
health before and after, and the run exits 3 when no pack was reached or nobody engaged. The node
emits no event per hit, so the ticks with attacks are not observable from a batch.

ENG-09 (`--authored on`, with or without `--quotas on`): the zone is the authored sample of
`tools/map-format/` (see the option below): `enter` and `leave` into it read its terrain from the
registry (D-214, D-215). A measure for D-144, not the recorded streams.

ENG-R1b (`Instances` and `Registry` on the store, AC-3): with `--scope r1b` the same two options
write and compare another stream, of the same transactions: `Instances`' and `Registry`'s storage
writes (key, value) and every event of `Instances` with its keys and data, in emission order; then
every key of both contracts' storage with its last value. A value the entry draw feeds is recorded
by its key alone, as `"draw"`: the entropy word of each instance entered (found by the instance's
`instance_state`, whose third felt it is), the only stored value derived from the draw, which
follows the transaction hash. ENG-05 adds the entry reveal's values, which follow the draw too:
each revealed chunk's terrain word (found by `instance_region`) and a dungeon's quotas word (its
open edges are drawn), recorded by key alone; a chunk's features word, in the slot after its
terrain, is left out of the stream: it is written only when the draw places something, so even its
key depends on the draw (#348's delta review: the stream must not change between two runs). A
zone's quota hosts (D-208), `Instances`' `hosts` entries `(slot, quota)` written at the entry, are
drawn too: their keys are computed by starknet.js (the client's dependency, through Node, which
`scripts/with-node.sh` provides) and their values recorded as `"draw"`. So are the three `outline`
words of a dungeon floor entered (ENG-10b, FND-26: the gate-6 leave enters one).
`RevealLibrary` and `HostsLibrary` (D-210) are declared before `Hub`'s deployment, and their class
hashes given to `Instances`' constructor, so the transactions recorded are the same. `lifecycle-stream-before-r1b.json`,
recorded on `main`'s code before
ENG-R1b's first change, is what `Instances` and `Registry` keep: run
`--scope r1b --expect contracts/tools/lifecycle-stream-before-r1b.json`. Without `--scope`, the
stream is ENG-R1a's, unchanged.
"""
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

# ENG-R1a: `--stream <file>` writes the stream, `--expect <file>` compares it (see above);
# ENG-R1b: `--scope r1b` makes it the stream of `Instances` and `Registry`.
OPTIONS = dict(zip(sys.argv[1::2], sys.argv[2::2]))
SCOPE = OPTIONS.get("--scope", "hub")
if SCOPE not in ("hub", "r1b"):
    sys.exit("lifecycle_probe: --scope is hub (the default) or r1b")
HERE = os.path.dirname(os.path.abspath(__file__))
CONTRACTS = os.path.dirname(HERE)
URL = os.environ["NODE_URL"]
# D-176: `sncast declare` builds the contract with Scarb; the build is single-threaded.
os.environ["RAYON_NUM_THREADS"] = "1"
if urllib.parse.urlparse(URL).hostname != "127.0.0.1":
    sys.exit("lifecycle_probe: the local node only (NODE_URL must be on 127.0.0.1)")
ADDRESS = os.environ["NODE_ACCOUNT_ADDRESS"]
KEY = os.environ["NODE_ACCOUNT_PRIVATE_KEY"]
LOGS = os.environ.get("WITH_NODE_LOG_DIR", os.path.join(os.getcwd(), ".with-node"))
ACCOUNTS = os.path.join(LOGS, "accounts-eng06.json")

LIVE = 1 << 250
REGION, LOCATION, GATE, QUOTAS, ITEM = 1, 2, 4, 5, 11
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


def location(kind, width, target, floors, next_floor, entry_chunk, entry_tile, spawn_table=0):
    low = (kind + (1 << 8) + (1 << 24) + (1 << 32) + (3 << 40) + (width << 56) + (width << 64)
           + (target << 72) + (floors << 80) + (next_floor << 88) + (spawn_table << 104))
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


def seed_rows(name, columns):
    """The rows of one table of `contracts/seed/test-region.json`, `columns` numbers a row."""
    with open(os.path.join(CONTRACTS, "seed", "test-region.json")) as seed_file:
        flat = json.load(seed_file)[name]
    assert len(flat) % columns == 0, f"seed: {name} is not whole rows"
    return [flat[i:i + columns] for i in range(0, len(flat), columns)]


def entry_bits(row):
    """`EntryTrait::pack`: kind 0, param 8, v0 16, v12 32, d0 48, d12 64, charges 80, target 86,
    shape 88, filter 91, guard 92, scope 95 (the values here are not negative)."""
    kind, param, v0, v12, d0, d12, charges, target, shape, filter_, guard, scope = row
    return (kind + (param << 8) + (v0 << 16) + (v12 << 32) + (d0 << 48) + (d12 << 64)
            + (charges << 80) + (target << 86) + (shape << 88) + (filter_ << 91) + (guard << 92)
            + (scope << 95))


def skill_record(row):
    """`SkillRecord::pack`: the header, then the first entry above it; the other two."""
    _, prof, attr, kind, energy, adrenaline, activation, recharge, range_, target, elite = row[:11]
    header = (prof + (attr << 8) + (kind << 16) + (energy << 24) + (adrenaline << 32)
              + (activation << 40) + (recharge << 56) + (range_ << 72) + (target << 80)
              + (elite << 82))
    a, b, c = (entry_bits(row[11 + 12 * i:23 + 12 * i]) for i in range(3))
    return [header + (a << 128) + LIVE, b + (c << 128) + LIVE]


def caste_record(row):
    """`CasteRecord::pack`: the sheet's low limb and the per-type armors and loot table, then the
    four skills."""
    (_, tier, ai, health, regen, armor), vs = row[:6], row[6:15]
    wclass, wdamage, wtype, wticks, wrange = row[15:20]
    energy, energy_regen, skills, (rank, flee, loot, boss) = row[20], row[21], row[22:26], row[26:30]
    weapon = wclass + (wdamage << 4) + (wtype << 20) + (wticks << 24) + (wrange << 28)
    low = (tier + (ai << 8) + (health << 16) + (regen << 32) + (armor << 40) + (weapon << 48)
           + (energy << 80) + (energy_regen << 88) + (flee << 96) + (rank << 104) + (boss << 108))
    high = sum(v << (6 * i) for i, v in enumerate(vs)) + (loot << 54)
    packed = sum(sk << (16 * i) for i, sk in enumerate(skills))
    return [low + (high << 128) + LIVE, packed + LIVE]


def pack_record(row):
    """`PackRecord::pack`: five `(caste, min, max)` of 32 bits, the level (signed 8 bits) above."""
    bits = [row[1 + 3 * i] + (row[2 + 3 * i] << 16) + (row[3 + 3 * i] << 24) for i in range(5)]
    level = row[16] % 256
    low = bits[0] + (bits[1] << 32) + (bits[2] << 64) + (bits[3] << 96)
    return [low + ((bits[4] + (level << 32)) << 128) + LIVE]


def spawn_table_record(row):
    """`SpawnTableRecord::pack`: seven `(template, weight)` of 24 bits, the density above."""
    bits = [row[1 + 2 * i] + (row[2 + 2 * i] << 16) for i in range(7)]
    low = sum(b << (24 * i) for i, b in enumerate(bits[:5]))
    return [low + ((bits[5] + (bits[6] << 24) + (row[15] << 48)) << 128) + LIVE]


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
# ENG-05: the reveal's library class, declared before `Hub`'s deployment so that the recorded
# transactions are the ones they were; its class hash is `Instances`' constructor argument.
reveal = declare("logic", "RevealLibrary")
hosts_library = declare("logic", "HostsLibrary")
trap_library = declare("logic", "TrapLibrary")
hub = deploy("persistent", declare("persistent", "Hub"), ADDRESS, registry, 3, 4, fate)
flatten = declare("logic", "FlattenLibrary")
instances = deploy("ephemeral", declare("ephemeral", "Instances"), ADDRESS, hub, registry, fate,
                   reveal, hosts_library, trap_library)
emit({"registry": registry, "fate": fate, "hub": hub, "instances": instances,
      "flatten_class": flatten, "reveal_class": reveal, "hosts_class": hosts_library,
      "trap_class": trap_library})
WATCHED = {int(hub, 16): "hub", int(instances, 16): "instances"}
NAMES = {int(registry, 16): "registry", int(fate, 16): "fate", int(hub, 16): "hub",
         int(instances, 16): "instances", int(flatten, 16): "flatten_class",
         int(reveal, 16): "reveal_class", int(hosts_library, 16): "hosts_class",
         int(trap_library, 16): "trap_class"}
STREAM = []
# ENG-R1b: the stream of `Instances` and `Registry`, and the keys whose value the entry draw feeds.
STREAM_R1B = []
DRAWN = set()
# ENG-05: the features slots of the chunks revealed, left out of the r1b stream (module doc).
UNSTREAMED = set()
OWNERS = {int(instances, 16): "instances", int(registry, 16): "registry"}


def named(value):
    return NAMES.get(value, hex(value))


def drawn(address, key, value):
    """A stored value as the r1b stream records it: `"draw"` where the entry draw feeds it."""
    return "draw" if (address, key) in DRAWN else named(value)


def view(function, *calldata):
    """The raw response of a view of `Instances`, as felts."""
    out = sncast("ephemeral", "call", "--url", URL, "--contract-address", instances, "--function",
                 function, "--calldata", *[hex(c) for c in calldata], "--block-id", "latest")
    match = re.search(r"Response Raw:\s*\[([^\]]*)\]", out)
    if not match:
        raise RuntimeError(f"{function}: no raw response in: {out}")
    return [int(f.strip(), 16) for f in match.group(1).split(",")]


def entropy_of(instance_id):
    """The entropy word `instance_state` returns for `instance_id`: its third felt."""
    return view("instance_state", instance_id)[2]


MAP_KEYS = {}


def map_keys(name, slot, count):
    """The storage keys of `Instances`' map `name` at `(slot, 0..count)`: the Pedersen chain of the
    map's name and the key's parts, as a storage address."""
    if (name, slot) not in MAP_KEYS:
        script = (f"const {{hash}}=require('starknet');const b=hash.starknetKeccak('{name}');"
                  f"for(let i=0;i<{count};i++)console.log(hash.computePedersenHash("
                  f"hash.computePedersenHash(b,{slot}),i));")
        node_path = os.path.join(os.path.dirname(CONTRACTS), "client", "app", "node_modules")
        out = subprocess.run(["node", "-e", script], env={**os.environ, "NODE_PATH": node_path},
                             capture_output=True, text=True, check=True).stdout
        MAP_KEYS[(name, slot)] = [int(line, 16) % (2 ** 251 - 256) for line in out.split()]
    return MAP_KEYS[(name, slot)]


def hosts_keys(slot):
    """ENG-05 (D-208): the keys of `Instances`' `hosts` entries of `slot`, quotas 0-13."""
    return map_keys("hosts", slot, 14)


def outline_keys(slot):
    """FND-26: the keys of `Instances`' `outline` words of `slot` (ENG-10b): a dungeon floor's
    chunks and its two seam words, drawn at the entry."""
    return map_keys("outline", slot, 3)


def drawn_words(instance_id):
    """ENG-05: the stored values the entry reveal draws, beside the entropy: each revealed chunk's
    terrain word (`instance_region`'s, one chunk a call; its `features` word is the next slot) and,
    when it is not `LIVE` alone (a dungeon's open edges), the quotas word. Returns
    `(terrains, quotas)`."""
    state = view("instance_state", instance_id)
    revealed, quotas = state[3] - LIVE, state[4]
    terrains = []
    for chunk in range(225):
        if (revealed >> chunk) & 1:
            # `Span<RegionChunk>`: its length, then chunk, kind, terrain, features, goblins.
            terrains.append(view("instance_region", instance_id, chunk, 1)[3])
    return terrains, (quotas if quotas != LIVE else None)


def streamed_r1b(label, function, receipt, diff):
    """ENG-R1b: the writes of `Instances` and `Registry` and the events of `Instances` of one
    transaction, in order. An entered instance's entropy key joins `DRAWN` first."""
    for event in receipt.get("events", []):
        if int(event["from_address"], 16) == int(instances, 16) and len(event["keys"]) == 2 \
                and len(event["data"]) == 3:
            entered_id = int(event["keys"][1], 16)
            entropy = entropy_of(entered_id)
            terrains, quotas = drawn_words(entered_id)
            for key in hosts_keys(entered_id >> 32) + outline_keys(entered_id >> 32):
                DRAWN.add((int(instances, 16), key))
            for entry in diff:
                if int(entry["address"], 16) == int(instances, 16):
                    for s in entry["storage_entries"]:
                        key, value = int(s["key"], 16), int(s["value"], 16)
                        if value == entropy or value == quotas:
                            DRAWN.add((int(instances, 16), key))
                        if value in terrains:
                            DRAWN.add((int(instances, 16), key))
                            UNSTREAMED.add((int(instances, 16), key + 1))
    writes = {}
    for entry in diff:
        address = int(entry["address"], 16)
        if address in OWNERS:
            writes[OWNERS[address]] = sorted(
                [hex(int(s["key"], 16)), drawn(address, int(s["key"], 16), int(s["value"], 16))]
                for s in entry["storage_entries"]
                if (address, int(s["key"], 16)) not in UNSTREAMED)
    events = [{"keys": [named(int(k, 16)) for k in event["keys"]],
               "data": [named(int(d, 16)) for d in event["data"]]}
              for event in receipt.get("events", [])
              if int(event["from_address"], 16) == int(instances, 16)]
    STREAM_R1B.append({"label": label, "function": function,
                       "status": receipt.get("execution_status"),
                       "writes": dict(sorted(writes.items())), "events": events})


def streamed(label, function, tx, receipt):
    """ENG-R1a: `Hub`'s writes and the events of `tx`, in order, for `--stream`."""
    trace = rpc("starknet_traceTransaction", {"transaction_hash": tx})
    if SCOPE == "r1b":
        streamed_r1b(label, function, receipt, (trace.get("state_diff") or {}).get("storage_diffs", []))
        return
    writes = []
    for entry in (trace.get("state_diff") or {}).get("storage_diffs", []):
        if int(entry["address"], 16) == int(hub, 16):
            writes += sorted([hex(int(s["key"], 16)), named(int(s["value"], 16))]
                             for s in entry["storage_entries"])
    events = []
    for event in receipt.get("events", []):
        who = WATCHED.get(int(event["from_address"], 16))
        if who == "hub":
            events.append({"from": who, "keys": [named(int(k, 16)) for k in event["keys"]],
                           "data": [named(int(d, 16)) for d in event["data"]]})
        elif who == "instances":
            events.append({"from": who, "name": event["keys"][0]})
    STREAM.append({"label": label, "function": function,
                   "status": receipt.get("execution_status"), "writes": writes, "events": events})


def invoke(label, contract, function, *calldata, player=0, record=True):
    args = ["--calldata", *[hex(c) if isinstance(c, int) else c for c in calldata]] if calldata else []
    out = sncast("persistent", "--account", names[player], "--wait", "invoke", "--url", URL,
                 "--contract-address", contract, "--function", function, *args)
    tx = field("Transaction Hash", out)
    receipt = rpc("starknet_getTransactionReceipt", {"transaction_hash": tx})
    streamed(label, function, tx, receipt)
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


invoke("Hub.set_contracts", hub, "set_contracts", registry, instances, 4, fate, flatten,
       record=False)
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
# ENG-05 (D-208): with `--quotas on`, the zone's `QUOTAS` of the seed (a collector, id 1, once), so
# that `create` draws and writes a host; a measure, not the recorded streams (which run without).
if OPTIONS.get("--quotas") == "on" and OPTIONS.get("--authored") != "on":
    records.append((QUOTAS, 2, [LIVE + 4 + 1 * 2 ** 8 + 1 * 2 ** 24]))
# ENG-09 (`--authored on`): the zone (location 2) is `tools/map-format`'s sample, the test region's
# zone drawn as an authored 3 x 2 zone, its marker set, its records as the converter writes them
# (the chunk set, the masks, each `ZONE_CHUNK` and its bridge), after the seed's two pack templates
# its spawn points and Heart name; its chunk 0 names gates 2 and 6, both anchored on the entry tile
# (R-25). With `--quotas on`, its `CANDIDATES` and `QUOTAS` too (a collector, a landmark and a Heart
# drawn among the author's candidates at `create`); without, none. A measure (D-144), not the
# recorded streams.
if OPTIONS.get("--authored") == "on":
    sys.path.insert(0, os.path.join(os.path.dirname(CONTRACTS), "tools", "map-format"))
    import convert as map_convert  # noqa: E402
    import records as map_records  # noqa: E402
    samples = os.path.join(os.path.dirname(CONTRACTS), "tools", "map-format", "samples")
    writes, _ = map_convert.convert(map_convert.load_json(os.path.join(samples, "zone.json")),
                                    map_convert.load_json(os.path.join(samples, "manifest.json")))
    authored = [(7, row[0], pack_record(row)) for row in seed_rows("packs", 17)]
    for kind, rid, felts, _ in writes:
        if kind == map_records.LOCATION:
            records[2] = (LOCATION, 2, felts)
            continue
        if kind == map_records.GATE:
            continue
        if kind in (map_records.CANDIDATES, map_records.QUOTAS) and OPTIONS.get("--quotas") != "on":
            continue
        if kind == map_records.ZONE_CHUNK:
            # Chunk 0 names both gates anchored on its entry tile; without quotas no chunk keeps a
            # candidate tile (R-14: none where no `CANDIDATES` names the chunk)
            chunk = map_records.unpack_zone_chunk(felts)
            if rid % 256 == 0:
                chunk["gates"] = [2, 6]
            if OPTIONS.get("--quotas") != "on":
                chunk["tiles"] = [0] * 6
            felts = map_records.pack_zone_chunk(chunk)
        authored.append((kind, rid, felts))
    records[5:5] = authored
# ENG-05b (the orchestrator, 2026-10-07): with `--floor on`, gate 7, a link from the start hub into
# the dungeon's first floor (location 3), and one `enter` through it before the accounts change
# owner; a measure, not the recorded streams (which run without).
if OPTIONS.get("--floor") == "on":
    records.append((GATE, 7, gate(1, 3, (0, 0), (112, 112), LINK)))
# Items 1 to 22 (sequential ids): potions 1, 8, 15, 22, one per pack page; the others ingredients.
records += [(ITEM, i, item(POTION if i in POTIONS else INGREDIENT)) for i in range(1, 23)]
# ENG-07t (`--fight on`): the seed's skill and castes, the packs and the spawn table the zone names,
# and the zone itself (location 2) naming spawn table 1, so that a chunk revealed holds goblins.
if OPTIONS.get("--fight") == "on":
    records[2] = (LOCATION, 2, location(3, 3, 0, 0, 0, 0, 105, spawn_table=1))
    records += [(9, row[0], skill_record(row)) for row in seed_rows("skills", 47)]
    records += [(8, row[0], caste_record(row)) for row in seed_rows("castes", 30)]
    records += [(7, row[0], pack_record(row)) for row in seed_rows("packs", 17)]
    records += [(6, row[0], spawn_table_record(row)) for row in seed_rows("spawn_tables", 16)]
# ENG-09: an authored zone's records need the registry's zone checks (`ZoneChecks`, its library
# class); only with `--authored on`, so that the recorded streams do not move.
if OPTIONS.get("--authored") == "on":
    invoke("Registry.set_zone_checks", registry, "set_zone_checks",
           declare("persistent", "ZoneChecks"), record=False)
for kind, rid, parts in records:
    invoke(f"set_record {kind} {rid}", registry, "set_record", kind, rid, len(parts), *parts,
           record=False)

invoke("register", hub, "register")
invoke("create_adventurer, cold (D-144: the start hub from the registry)", hub,
       "create_adventurer", short("Aldric"), 1)
invoke("create_adventurer, initialised", hub, "create_adventurer", short("Brenna"), 2)
invoke("create_adventurer, initialised (third)", hub, "create_adventurer", short("Cedric"), 3)

# CBT-02e (D-168): the snapshot stored by `set_build`, new at an adventurer's first, then
# overwritten; an empty build, the equipment's flattening being the snforge tests' (no entrypoint
# creates an item yet).
invoke("set_build, empty, first (the snapshot's 3 words new)", hub, "set_build", 1, EMPTY_BUILD, 0,
       0)
invoke("set_build, empty, again (the snapshot's 3 words rewritten unchanged)", hub, "set_build", 1,
       EMPTY_BUILD, 0, 0)
for adventurer in (2, 3):
    invoke("set_build, empty", hub, "set_build", adventurer, EMPTY_BUILD, 0, 0, record=False)

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
       ADDRESS, 4, fate, flatten, record=False)
invoke("report (Open: 3 of each potion into the pack)", hub, "report",
       setup_in, 1, 2, 0, 0, 4, *[f for item in POTIONS for f in (item, 3)], 0, 0, 0, 0,
       OPEN, 0, 0, 0, 0, 0, 0, record=False)
invoke("Hub.set_contracts (instances back)", hub, "set_contracts", registry, instances, 4, fate,
       flatten, record=False)
invoke("leave to a hub", instances, "leave", setup_in, 2, 0, 2, record=False)
invoke("set_build, 4 potions on 4 pack pages (empty bar, no equipment)", hub, "set_build", 2,
       EMPTY_BUILD, belt(POTIONS, (3, 3, 3, 3)), 0)
belted = entered(invoke("enter, later entry, the belt's worst case (4 pages, each lane emptied)",
                        hub, "enter", 2, 1))
invoke("leave to a hub, the belt credited back (4 pages)", instances, "leave", belted, 2, 0, 2)
belted = entered(invoke("enter, later entry, the belt's worst case (again)", hub, "enter", 2, 1))
invoke("travel_back, the belt credited back (4 pages)", instances, "travel_back", belted, 2, 0)

# ENG-05b: `enter` into a dungeon floor (`--floor on`), adventurer 1's later entry (its slot
# reused): `create` draws the floor's outline and hosts (`HostsLibrary::floor`), writes its three
# slots, and reveals the chunks sight touches.
if OPTIONS.get("--floor") == "on":
    invoke("travel_back", instances, "travel_back", fifth, 1, 0, record=False)
    invoke("enter, later entry, into a dungeon floor (gate 7: the outline and its hosts drawn)",
           hub, "enter", 1, 7)

# ENG-07 (`--play on`, D-235, D-236): `play` on the node. The classes `play` calls are declared and
# registered (`set_play_class`, keys `PLAY` … `SEGMENT`); adventurer 1, inside the zone (`fifth`),
# looks for an open direction from its entry tile with one-Move batches (a wall refuses the Move:
# `BatchPlayed` with `Stop::Invalid`, nothing written), then plays the exploration batch: 10 Moves
# back and forth across that edge, its ticks on the fast path, the chunks sight touches revealed
# between segments (E-12). Each batch is one record; `BatchPlayed`'s data and the count of
# `ChunkRevealed` go with it.
if OPTIONS.get("--play") == "on":
    keys = [("ephemeral", "PlayLibrary"), ("logic", "TickLibrary"), ("logic", "AiLibrary"),
            ("logic", "ActionLibrary"), ("logic", "ExecutorLibrary"), ("logic", "SegmentLibrary")]
    for key, (package, name) in enumerate(keys):
        invoke(f"set_play_class {name}", instances, "set_play_class", key, declare(package, name),
               record=False)

    def batch(actions):
        """`actions::encode_batch`: the count at bits 0-3, action `i` (24 bits: kind 0-2, the
        direction 3-5 for a Move) at `4 + 24 i` for `i` 0-4 and `128 + 24 (i - 5)` after."""
        word = len(actions)
        for i, direction in enumerate(actions):
            shift = 4 + 24 * i if i < 5 else 128 + 24 * (i - 5)
            word += (direction * 8) << shift
        return word

    def played(receipt):
        """`BatchPlayed`'s data (adventurer, from, played, stop, sequence, clock, version) and the
        count of `ChunkRevealed` (one key felt after its selector, no data but the chunk)."""
        data, reveals = None, 0
        for event in receipt["events"]:
            if int(event["from_address"], 16) != int(instances, 16):
                continue
            if len(event["data"]) == 7:
                data = [int(d, 16) for d in event["data"]]
            elif len(event["keys"]) == 2 and len(event["data"]) == 1:
                reveals += 1
        return data, reveals

    # The registry's content version, which a batch carries (D-141, E-5).
    out = sncast("persistent", "call", "--url", URL, "--contract-address", registry, "--function",
                 "content_version", "--block-id", "latest")
    version = int(re.search(r"Response Raw:\s*\[([^\]]*)\]", out).group(1).strip(), 16)
    sequence, direction = 0, None
    for d in range(6):
        receipt = invoke(f"play, one Move ({d})", instances, "play", fifth, 1, sequence, version,
                         batch([d]))
        data, reveals = played(receipt)
        emit({"batch": f"one Move ({d})", "played": data, "chunks_revealed": reveals})
        if data and data[2] == 1:
            sequence, direction = data[4], d
            break
    if direction is not None:
        back = (direction + 3) % 6
        moves = [back if i % 2 == 0 else direction for i in range(10)]
        receipt = invoke("play, exploration: 10 Moves (fast path)", instances, "play", fifth, 1,
                         sequence, version, batch(moves))
        data, reveals = played(receipt)
        sequence = data[4]
        emit({"batch": "exploration", "played": data, "chunks_revealed": reveals})

        # E-12: a walk that brings sight onto a chunk not revealed. The tiles of the revealed
        # chunks (`instance_region`), the moves by hexx's rule (`LayoutTrait::neighbor`, the row's
        # parity global: the window's origin row is even), sight by hex distance (axial
        # `q = x - floor(y / 2)`, `r = y`).
        def step(x, y, d):
            odd = y % 2 == 1
            return [(x - 1, y), (x, y + 1) if odd else (x - 1, y + 1),
                    (x + 1, y + 1) if odd else (x, y + 1), (x + 1, y),
                    (x + 1, y - 1) if odd else (x, y - 1), (x, y - 1) if odd else (x - 1, y - 1)][d]

        def distance(a, b):
            (ax, ay), (bx, by) = a, b
            aq, bq = ax - ay // 2, bx - by // 2
            dq, dr = bq - aq, by - ay
            return (abs(dq) + abs(dr) + abs(dq + dr)) // 2

        raw = view("instance_region", fifth, 0, 16)
        walkable, unrevealed = set(), set()
        i = 1
        while i < len(raw):
            # `RegionChunk`: chunk, kind (0 void, 1 not revealed, 2 revealed), terrain, features,
            # goblins (a span, empty until a view lists them)
            chunk, kind, terrain, goblins = raw[i], raw[i + 1], raw[i + 2], raw[i + 4]
            assert goblins == 0, "instance_region: goblins listed"
            i += 5
            cx, cy = chunk % 15, chunk // 15
            if kind == 2:
                walls = terrain % (1 << 225)
                for t in range(225):
                    if not (walls >> t) & 1:
                        walkable.add((cx * 15 + t % 15, cy * 15 + t // 15))
            elif kind == 1:
                unrevealed.add(chunk)
        # `InstanceView`: id, header, entropy, revealed, quotas, the task words (a span), the
        # members' words (a span, `MemberState` first: x 32-39, y 40-47)
        state = view("instance_state", fifth)
        word = state[6 + state[5] + 1]
        at = ((word >> 32) % 256, (word >> 40) % 256)

        def sees_new(tile):
            for chunk in unrevealed:
                cx, cy = chunk % 15, chunk // 15
                for t in range(225):
                    if distance(tile, (cx * 15 + t % 15, cy * 15 + t // 15)) <= 6:
                        return True
            return False

        path = None
        if True:
            frontier, seen = [(at, [])], {at}
            while frontier and path is None:
                nxt = []
                for tile, moves_so_far in frontier:
                    if len(moves_so_far) >= 8:
                        continue
                    for d in range(6):
                        n = step(*tile, d)
                        if n in walkable and n not in seen:
                            seen.add(n)
                            if sees_new(n):
                                path = moves_so_far + [d]
                                break
                            nxt.append((n, moves_so_far + [d]))
                    if path is not None:
                        break
                frontier = nxt
        emit({"reveal_walk": path, "from": at, "unrevealed": sorted(unrevealed)})
        if path is not None:
            receipt = invoke(f"play, a walk of {len(path)} Moves revealing in play (E-12)",
                             instances, "play", fifth, 1, sequence, version, batch(path))
            data, reveals = played(receipt)
            emit({"batch": "reveal walk", "played": data, "chunks_revealed": reveals})
            sequence = data[4]

        # ENG-07t (`--fight on`): a fight on the node. The zone names spawn table 1, so the chunks
        # revealed hold packs of the seed's castes. The adventurer looks at the goblins of its window
        # (`instance_state`), walks toward the nearest one, within 3 tiles (`bfs`, one batch of at
        # most 10 Moves at a time, exploring when no goblin is in the window or none can be
        # reached), then plays 10 Waits: the goblins engage and hit it (`TickLibrary`, `AiLibrary`,
        # `ExecutorLibrary` on the node). The fight batch is the figure; the member's health before
        # and after shows the fight. Behind the option: the compared streams do not move.
        if OPTIONS.get("--fight") == "on":
            def batch_codes(codes):
                """`batch` for action codes: 2 is a Wait (`actions::encode_action`)."""
                word = len(codes)
                for i, code in enumerate(codes):
                    word += code << (4 + 24 * i if i < 5 else 128 + 24 * (i - 5))
                return word

            def play_codes(label, codes):
                global sequence
                receipt = invoke(label, instances, "play", fifth, 1, sequence, version,
                                 batch_codes(codes))
                data, reveals = played(receipt)
                emit({"batch": label, "played": data, "chunks_revealed": reveals})
                sequence = data[4]
                return data

            def region_sets():
                """The walkable tiles of the revealed chunks, the chunks not revealed and the packs
                of the revealed ones as `(chunk, x, y, count, alert)`: `instance_state` lists no
                goblin yet, so the packs are read from the chunks' features (`PackPlacement`: tile
                0-7, count 32-35, alert 61-63; the pack at bit 0 and at bit 64)."""
                walkable, unrevealed, packs = set(), set(), []
                for page in (0, 16, 32):
                    raw = view("instance_region", fifth, page, 16)
                    i = 1
                    while i < len(raw):
                        chunk, kind, terrain = raw[i], raw[i + 1], raw[i + 2]
                        i += 5
                        cx, cy = chunk % 15, chunk // 15
                        if kind == 2:
                            walls = terrain % (1 << 225)
                            for t in range(225):
                                if not (walls >> t) & 1:
                                    walkable.add((cx * 15 + t % 15, cy * 15 + t // 15))
                            features = raw[i - 2] % (1 << 128)
                            for slot in range(2):
                                pack = (features >> (64 * slot)) % (1 << 64)
                                tile, count, alert = pack % 256, (pack >> 32) % 16, pack >> 61
                                if count:
                                    packs.append((chunk, cx * 15 + tile % 15, cy * 15 + tile // 15,
                                                  count, alert))
                        elif kind == 1:
                            unrevealed.add(chunk)
                return walkable, unrevealed, packs

            def bfs(start, walkable, goal, limit=40):
                frontier, seen = [(start, [])], {start}
                while frontier:
                    nxt = []
                    for tile, moves_so_far in frontier:
                        if goal(tile):
                            return moves_so_far
                        if len(moves_so_far) >= limit:
                            continue
                        for d in range(6):
                            n = step(*tile, d)
                            if n in walkable and n not in seen:
                                seen.add(n)
                                nxt.append((n, moves_so_far + [d]))
                    frontier = nxt
                return None

            def unseen(unrevealed):
                def sees(tile):
                    for chunk in unrevealed:
                        cx, cy = chunk % 15, chunk // 15
                        for t in range(225):
                            if distance(tile, (cx * 15 + t % 15, cy * 15 + t // 15)) <= 6:
                                return True
                    return False
                return sees

            near = None
            FIGHT_FOUND = False
            blocked = set()
            for attempt in range(14):
                st = view("instance_state", fifth)
                word = st[6 + st[5] + 1]
                at = ((word >> 32) % 256, (word >> 40) % 256)
                walkable, unrevealed, packs = region_sets()
                walkable -= blocked
                emit({"fight_scan": attempt, "at": at, "packs": packs,
                      "unrevealed": sorted(unrevealed)})
                if packs:
                    nearest = min(packs, key=lambda g: distance(at, g[1:3]))
                    if distance(at, nearest[1:3]) <= 3:
                        near = nearest
                        break
                    taken = {g[1:3] for g in packs}
                    path = bfs(at, walkable - taken, lambda t: distance(t, nearest[1:3]) <= 3)
                else:
                    path = None
                if path is None:
                    path = bfs(at, walkable, unseen(unrevealed)) if unrevealed else None
                if not path:
                    break
                data = play_codes(f"play, {len(path[:10])} Moves toward a goblin or the unrevealed",
                                  [d * 8 for d in path[:10]])
                if data[3] == 2:
                    # Invalid: the tile after the Moves played is not enterable (a goblin on it)
                    tile = at
                    for d in path[:data[2] + 1]:
                        tile = step(*tile, d)
                    blocked.add(tile)
            emit({"fight_target": near, "attempts": attempt + 1})
            FIGHT_FOUND = near is not None
            if near is not None:
                def goblin_word(slot, entity, word):
                    """A goblin's stored word `word` (0 state, 1 timers) in `slot`: the Pedersen chain
                    of the map's name and the key's parts (`hosts_keys`' way)."""
                    script = ("const {hash}=require('starknet');const b=hash.starknetKeccak("
                              f"'goblins');console.log(hash.computePedersenHash(hash.computePed"
                              f"ersenHash(b,{slot}),{entity}));")
                    node_path = os.path.join(os.path.dirname(CONTRACTS), "client", "app",
                                             "node_modules")
                    out = subprocess.run(["node", "-e", script],
                                         env={**os.environ, "NODE_PATH": node_path},
                                         capture_output=True, text=True, check=True).stdout
                    key = int(out.split()[0], 16) % (2 ** 251 - 256) + word
                    return int(rpc("starknet_getStorageAt", {"contract_address": instances, "key": hex(key),
                                                              "block_id": "latest"}), 16)

                st = view("instance_state", fifth)
                health = lambda s: (s[6 + s[5] + 1] >> 64) % 65536
                before = health(st)
                chunk, _, _, count, alert = near
                entities = [8 + 16 * chunk + k for k in range(count)]
                data = play_codes("play, a fight: 10 Waits within 3 tiles of a goblin", [2] * 10)
                st = view("instance_state", fifth)
                after = health(st)
                # A goblin has a record once it changed (awake and acting): the engaged ones, with
                # their tile and health (`GoblinState` bits 0-15 and 32-47).
                touched = []
                for entity in entities:
                    word = goblin_word(1, entity, 0)
                    if word % (1 << 250):
                        touched.append({"entity": entity, "x": word % 256, "y": (word >> 8) % 256,
                                        "health": (word >> 32) % 65536})
                engaged = after < before or bool(touched)
                emit({"fight": engaged, "pack_chunk": chunk, "pack_alert": alert,
                      "pack_entities": entities, "engaged_goblins": touched,
                      "played": data, "health_before": before, "health_after": after,
                      "note": "figure counts only if fight is true; the node gives no per-tick "
                              "attack events, so the ticks with attacks are not observable here"})
                FIGHT_FOUND = FIGHT_FOUND and engaged

# CBT-02e fix loop 1 (AC-5): a snapshot word's overwrite on the node. Three `set_build` of
# adventurer 2 with the same reads and the same computation (two potions, pages 0 and 1): the
# belt's counts changed (the belt word overwritten; the snapshot's words written with the values
# they hold, no change), the belt's two slots swapped (the belt word and the kit word overwritten:
# the kit names the belt's items), the same again (no state change). The kit word's overwrite is
# the second less the first.
invoke("set_build, two potions (setup)", hub, "set_build", 2, EMPTY_BUILD,
       belt((1, 8, 0, 0), (1, 1, 0, 0)), 0, record=False)
invoke("set_build, the belt's counts changed (belt overwritten, snapshot unchanged)", hub,
       "set_build", 2, EMPTY_BUILD, belt((1, 8, 0, 0), (1, 2, 0, 0)), 0)
invoke("set_build, the belt's slots swapped (belt and the snapshot's kit word overwritten)", hub,
       "set_build", 2, EMPTY_BUILD, belt((8, 1, 0, 0), (2, 1, 0, 0)), 0)
invoke("set_build, the same again (no state change)", hub, "set_build", 2, EMPTY_BUILD,
       belt((8, 1, 0, 0), (2, 1, 0, 0)), 0)

# set_account_owner with k adventurers inside, k = 0 to 3, the real set_controller (D-144).
# Accounts 2, 3 and 4 are players 3, 1 and 2's; adventurers 4 to 7 theirs.
next_adventurer = 4
for k, player in ((0, 3), (1, 1), (2, 2)):
    invoke(f"register (account of player {player})", hub, "register", player=player, record=False)
    ids = []
    for n in range(max(k, 1)):
        invoke("create_adventurer", hub, "create_adventurer", short(f"P{player}A{n}"), 1,
               player=player, record=False)
        invoke("set_build, empty", hub, "set_build", next_adventurer, EMPTY_BUILD, 0, 0,
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

# ENG-R1a (AC-3): the stream, and every key of `Hub`'s storage with its last value. ENG-R1b: with
# `--scope r1b`, `Instances`' and `Registry`'s.
if SCOPE == "r1b":
    STREAM = STREAM_R1B
    storage = {who: sorted([hex(key), drawn(address, key, value)]
                           for (address, key), value in KNOWN.items()
                           if address == owner and (address, key) not in UNSTREAMED)
               for owner, who in sorted(OWNERS.items(), key=lambda o: o[1])}
elif OPTIONS:
    storage = sorted([hex(key), named(value)] for (address, key), value in KNOWN.items()
                     if address == int(hub, 16))
if OPTIONS:
    stream = {"transactions": STREAM, "storage": storage}
    if "--stream" in OPTIONS:
        with open(OPTIONS["--stream"], "w") as out:
            json.dump(stream, out, indent=1)
            out.write("\n")
    if "--expect" in OPTIONS:
        with open(OPTIONS["--expect"]) as expected_file:
            expected = json.load(expected_file)
        for i, (a, b) in enumerate(zip(expected["transactions"], STREAM)):
            if a != b:
                sys.exit(f"lifecycle_probe: transaction {i} ({b['label']}) differs:\n"
                         f"expected {json.dumps(a)}\nfound    {json.dumps(b)}")
        if len(expected["transactions"]) != len(STREAM):
            sys.exit("lifecycle_probe: not the same number of transactions")
        if expected["storage"] != storage:
            sys.exit(f"lifecycle_probe: the storage of the scope {SCOPE} differs")
        keys = {f"{who}_keys": len(kept) for who, kept in storage.items()} \
            if SCOPE == "r1b" else {"hub_keys": len(storage)}
        emit({"stream": "equal", "scope": SCOPE, "transactions": len(STREAM),
              "events": sum(len(t["events"]) for t in STREAM), **keys,
              **({"drawn_keys": len(DRAWN)} if SCOPE == "r1b" else {})})

# ENG-07t: `--fight on` exits 3 when no pack was reached or the member was not engaged: such a run
# gives no figure (the batch gas of its line is not a fight's).
if OPTIONS.get("--fight") == "on" and not globals().get("FIGHT_FOUND", False):
    sys.exit(3)
