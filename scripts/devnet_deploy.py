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

OPS-01b, `--build full` (the default is `--build empty`, as above), and SEED-02 (D-275, D-280): the adventurer is
built from the seed's own records before it enters. It enters once, and the pack is funded as the lifecycle
probe does (no entrypoint fills a pack or credits gold yet but `Hub.report`): the hub's `instances` is pointed at
the account for one `report` (Open) that credits the potions and the gold, then back, and the adventurer leaves
by gate 2. The gold step is a devnet harness (D-280), never used on Sepolia or later, and removed when
expedition rewards land. It refuses to run unless the RPC's chain id is `SN_SEPOLIA`, the node answers
`devnet_getPredeployedAccounts` and the URL is local; it restores `Hub.instances` to the real `Instances`
in a `finally`, reads the storage back and fails unless it is the `Instances` address; and it credits exactly
the four skills' price at D-277's trainer prices (50 + 60 + 70 + 80 = 260 gold, no margin). Then `buy_skill`
makes the four bar skills known, `set_build` carries the bar and the belt, and the entry that follows is the one
the JSON names. What the seed gives: bar: skill 1 (an instant attack), the activation skill, the trap skill and
the REGENERATION skill, in that order, slots 0 to 3; belt: the healing potion (item 1) x2 and the REGENERATION
potion (item 23) x1; pack: twice the belt, so the entry debits the belt and one re-entry with it is covered.
Seed ids come from `build_plan()`, which reads `seed_records()`'s rows, never hard-coded.

DEPLOY-SALT (`--salt <felt>`, opt-in): `sncast deploy` draws a random salt, so each run on a fresh node
gets other addresses. They reach the entry's transaction hash (the `Hub.enter` call names the Hub, and
its calldata and the sender's nonce follow the same history), and `TxHashFate.fate` is
`poseidon(transaction hash, domain)` (`contracts/persistent/src/systems/fate.cairo:31`), consumed by
`Instances.begin`'s entry draw (`contracts/ephemeral/src/systems/instances.cairo:874`): another address,
another world (the goblins track CV records). With `--salt`, every `sncast deploy` gets the salt
`sha256("<salt>:<class hash>")` truncated to 250 bits (one salt per class, so two runs of the same
build give the same addresses), and a re-run on a fresh node (same build, same node seed) draws the same
world. "Same build" means the same class hashes, and in this repository those depend on the build's path:
the same commit built elsewhere (another worktree, the CI, the VPS) gives other addresses and another
world. Why: the Cairo compiler writes the absolute build path into the closure type names of Sierra ids
(upstream starkware-libs/cairo#10358, D-183), so class hashes, and with them the addresses, the `enter`
transaction hash and the drawn world, change with the checkout path (gas, Sierra felt counts and CASM do
not). So the same world needs the same commit, the same Scarb, single-threaded builds and the same absolute
checkout path; any machine that builds at one fixed path gets the same world. Adopting a Scarb release that
carries the fix (cairo#10359) reverses it (D-183). The entry's transaction hash also holds the fee bounds, so the draw is the same only under
devnet's default gas prices, as `with-node.sh` starts it, and `sncast`'s tip of 0. Without it nothing changes (a random salt per deploy, `salt` is null in the JSON). The fixed salt
is for the devnet only; the node itself is fixed (`with-node.sh` uses devnet's seed 0 accounts).

DEPLOY-BUILD-FOR: two more modes, run on a node this script has already deployed to. They read the
deployment JSON (`--deployment <path>`, the file `--out` wrote) and are a D-280 devnet harness like the gold step:
never for Sepolia or later, removed when expedition rewards land. They refuse a node that is not a local devnet
(same guards as the gold step: `assert_local_devnet`), a deployment file that is missing or whose Hub has no code on
the node, and they keep D-280's restore (`Hub.instances` back to the real `Instances` in a `finally`, read back).
The admin's key (account 0) is read from the node's `devnet_getPredeployedAccounts` (it must be the deployment's
`account`), so the dev server needs no environment but the deployment file; `NODE_URL`, when set, overrides the
file's `node_url` (and is checked the same way). No key is ever on a command line of this script, printed, or in
the output: each one goes through a file (mode 0600, deleted at once) into `sncast`'s throwaway accounts file
under $WITH_NODE_LOG_DIR. The harness (`credit_harness`, both modes) is serialised by an exclusive `flock`
on `devnet-harness.lock` in that directory, so overlapping runs (one credit per burner) cannot clash on account 0's
nonce; if the restore itself fails the error says "Hub.instances NOT restored". Output (stdout, or `--out`): JSON.

    --give-build --deployment <json> --account <1-9 | address> [--key-env NAME] [--adventurer <id>]

  Gives SEED-02's build (the four bar skills, the belt of the healing potion x2 and item 23 x1, a pack of twice
  the belt) to an adventurer of another account, in `--build full`'s order and with its functions
  (`build_plan`, `fund_pack`, `buy_skill`, `set_build`). `--account` is a predeployed account's index, 1 to 9 (0
  stays the admin; any other index is refused), whose key is read from the node; or an account address, whose
  private key is in the environment variable named by `--key-env` (never its value). Without `--adventurer` the
  account is registered when it has none and a new adventurer is created (the id is read from `Hub.account`'s
  list, before and after); with one, the chain refuses it when the account does not own it (the error is passed
  on). The owner's calls (`register`, `create_adventurer`, `set_build`, `enter`, `leave`, `buy_skill`) are sent
  from that account (`Hub` checks `caller == owner`, `owned_in_hub`; `Instances.leave` the member's controller,
  the one `enter` named); only `set_contracts` and the forged `report` are sent from account 0. The adventurer
  ends in the hub, built and not inside; it enters itself. A second build of an adventurer that knows the skills
  is refused by the chain at `buy_skill` (`SkillTrainerAssert::assert_unknown`), after the empty `set_build`
  reset its bar and the gold was credited again: a build per adventurer. Output: `account` (no key),
  `adventurer_id`, `build` (the deployment JSON's `build` shape, mode `full`).

    --credit-only --deployment <json> --adventurer <id>

  For an adventurer whose owner's key never leaves the browser (track CV's burners): account 0's harness calls
  only, no owner call. The caller's order:
    1. the owner registers, creates the adventurer (`set_build` empty, so the snapshot is fresh) and enters
       through gate 1 (`Hub.enter`): the adventurer is now inside an open instance;
    2. this mode: `set_contracts` to account 0, one forged Open `report` (SEED-02's 260 gold and the pack of
       twice the belt, as `--build full` credits), `set_contracts` back, read back;
    3. the owner leaves by gate 2 (`Instances.leave(instance_id, adventurer, 0, 2)`; the member must still stand
       on the gate's anchor, as it does right after the entry; a refused leave emits `Refused` and returns 0
       without a revert), then `buy_skill` x4, then `set_build`.
  What the state must be: `Hub.report` asserts the adventurer's place is inside the reported instance
  (`assert_in_instance`); the mode reads `Instances.placement(adventurer)` -> (instance id, member index,
  inside) and refuses, before any write, an adventurer that never entered or is not inside now ("not inside an
  instance"). What the report leaves: Open changes nothing of the place, so the instance stays open and the
  adventurer inside, and the owner calls (`buy_skill`, `set_build`) refuse (`NOT_IN_HUB`) until it has left. The
  instance id is read from `Instances.placement`, not from an event or an argument. Credited twice, gold and pack
  add up. Output: `adventurer_id`, `instance_id`, `gold`, `pack` ([{item, count}]), `instance_read_from`.

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
    salt              the `--salt` value as a hex string (DEPLOY-SALT), or null without the option
    adventurer_id     the adventurer created, built and entered (a number)
    instance_id       the instance it entered: `InstanceEntered`'s id (a number)
    slot              the instance's slot, `instance_id >> 32` (a number)
    build             what the adventurer was built with (OPS-01b, SEED-02; numbers): {mode, bar: the 8
                       skill ids by slot (0 empty), belt: [{item, count}], pack: [{item, count}] funded
                       before the entry, pack_after_entry: [{item, count}] what the entry left (derived, listed in
                       `derived`: no view reads a pack yet), gold: what the harness credited (D-280),
                       skills: {name: id} of the bar's skills,
                       dropped: {name: reason} for each part the seed or the chain cannot give (empty)}
"""
import argparse
import fcntl
import hashlib
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
    GATE, HUB_GATE, INGREDIENT, ITEM, LINK, FLOOR, LIVE, LOCATION, POTION, REGENERATION_POTION,
    REGION, caste_record, gate, item, location, pack_record, region, regeneration_item, seed_rows,
    short, skill_record, spawn_table_record)

# D-176: `sncast declare` builds the contract with Scarb; the build is single-threaded.
os.environ["RAYON_NUM_THREADS"] = "1"

POTIONS = (1, 8, 15, 22)
EMPTY_BUILD = 255 << 168  # an empty bar (elite slot 255, bit 168), ENG-01 §3.3
BAR_SLOTS = 8
HUB_GATE_BACK = 2  # the gate from the zone back to the start hub (`seed_records`)
DEVNET_CHAIN = "SN_SEPOLIA"  # what a local starknet-devnet answers (OPERATIONS §7: stop unless it is)
SKILL_PRICES = (50, 60, 70, 80)  # D-277's trainer prices for a first to a fourth skill
GOLD = sum(SKILL_PRICES)  # 260: the four skills, no margin
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


def keccak256(data):
    """Keccak-256 (the original padding, not SHA3), for `storage_key`: Python's hashlib has none."""
    rotation = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61], [28, 55, 25, 21, 56],
                [27, 20, 39, 8, 14]]
    mask, state, lfsr = (1 << 64) - 1, [0] * 25, 1
    constants = []
    for _ in range(24):  # the round constants, from the spec's LFSR
        constant = 0
        for j in range(7):
            if lfsr & 1:
                constant ^= 1 << ((1 << j) - 1)
            lfsr = (lfsr << 1) ^ (0x71 if lfsr & 0x80 else 0) & 0xFF
        constants.append(constant)
    padded = bytearray(data) + b"\x01"
    padded += b"\x00" * (-len(padded) % 136)
    padded[-1] |= 0x80
    for block in range(0, len(padded), 136):
        for i in range(17):
            state[i] ^= int.from_bytes(padded[block + 8 * i:block + 8 * i + 8], "little")
        for constant in constants:
            c = [state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20]
                 for x in range(5)]
            for x in range(5):
                d = c[(x + 4) % 5] ^ (((c[(x + 1) % 5] << 1) | (c[(x + 1) % 5] >> 63)) & mask)
                for y in range(0, 25, 5):
                    state[x + y] ^= d
            moved = [0] * 25
            for x in range(5):
                for y in range(5):
                    r = rotation[x][y]
                    v = state[x + 5 * y]
                    moved[y + 5 * ((2 * x + 3 * y) % 5)] = ((v << r) | (v >> (64 - r))) & mask if r else v
            for y in range(0, 25, 5):
                for x in range(5):
                    state[x + y] = moved[x + y] ^ (~moved[(x + 1) % 5 + y] & mask
                                                  & moved[(x + 2) % 5 + y])
            state[0] ^= constant
    return b"".join(state[i].to_bytes(8, "little") for i in range(4))


def storage_key(name):
    """The storage address of a plain storage variable: `sn_keccak(name)`, the low 250 bits."""
    return int.from_bytes(keccak256(name.encode()), "big") & ((1 << 250) - 1)


def chain_of(node):
    return bytes.fromhex(node.rpc("starknet_chainId", [])[2:]).decode()


def assert_local_devnet(node):
    """D-280: the gold harness runs on a local devnet only. The URL is `http://127.0.0.1:<port>`,
    the chain id is read from the RPC now and must be `SN_SEPOLIA` (OPERATIONS §7), and the node
    must answer `devnet_getPredeployedAccounts`, which no public node does. Returns the chain id."""
    check_url(node.url)
    chain = chain_of(node)
    if chain != DEVNET_CHAIN:
        sys.exit(f"devnet_deploy: the gold step runs on a local devnet only (chain id {chain!r}, "
                 f"not {DEVNET_CHAIN!r})")
    try:
        node.rpc("devnet_getPredeployedAccounts", {})
    except Exception as error:  # not a devnet: the method is unknown
        sys.exit(f"devnet_deploy: the gold step runs on a local devnet only ({error})")
    return chain


class RpcError(RuntimeError):
    """A JSON-RPC error answer; `code` is the answer's error code (OPS-02a reads CLASS_HASH_NOT_FOUND, 28)."""

    code = None


class Node:
    """The local node and the first pre-funded account, through the JSON-RPC and `sncast`."""

    def __init__(self, url, address, key, logs, salt=None, name="deployer"):
        self.check_url(url)
        self.url, self.address, self.salt, self.name, self.logs = url, address, salt, name, logs
        self.sent = []  # the hash of each transaction `sncast` sent (OPS-02a counts them)
        os.makedirs(logs, exist_ok=True)
        # DEPLOY-BUILD-FOR: another account of the same node gets a file of its own, by process
        self.accounts = os.path.join(logs, "accounts-devnet-deploy.json" if name == "deployer"
                                     else f"accounts-devnet-{name}-{os.getpid()}.json")
        if os.path.exists(self.accounts):
            os.remove(self.accounts)
        self.key = key

    check_url = staticmethod(check_url)  # OPS-02a: the Sepolia node checks its own URL

    @staticmethod
    def redact(text):
        """OPS-02a: what an error message goes through; the Sepolia node hides its variables here."""
        return text

    def rpc(self, method, params):
        body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
        request = urllib.request.Request(self.url, data=body,
                                         headers={"content-type": "application/json"})
        with urllib.request.urlopen(request, timeout=60) as response:
            answer = json.load(response)
        if "error" in answer:
            error = RpcError(self.redact(f"{method}: {answer['error']}"))
            error.code = answer["error"].get("code") if isinstance(answer["error"], dict) else None
            raise error
        return answer["result"]

    def sncast_cwd(self, package):
        """Where `sncast` runs (OPS-02a: the Sepolia node runs it in a folder of its own)."""
        return os.path.join(CONTRACTS, package)

    def sncast_args(self, args):
        return args

    def sncast(self, package, *args, account=True):
        accounts = ["--accounts-file", self.accounts] if account else []
        out = subprocess.run(["sncast", *accounts, *self.sncast_args(args)], cwd=self.sncast_cwd(package),
                             capture_output=True, text=True)
        if out.returncode != 0:
            # sncast echoes the command's arguments only on a usage error, never the key we import
            raise RuntimeError(self.redact(
                f"sncast {' '.join(self.redact(' '.join(args[:4])).split())}: "
                f"{self.redact(out.stdout)[-2000:]} {self.redact(out.stderr)[-2000:]}"))  # redact, then cut
        sent = re.search(r"Transaction Hash:\s*(0x[0-9a-fA-F]+)", out.stdout)
        if sent and args[0] not in ("call", "account"):
            self.sent.append(sent.group(1))
        return out.stdout + out.stderr

    def import_account(self):
        # as in the probe: sncast stores it in its throwaway accounts file (local node, test account)
        # the key goes through a file of mode 0600, deleted at once, never an argument of ours
        path = os.path.join(self.logs, f"key-{self.name}-{os.getpid()}")
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            with os.fdopen(descriptor, "w") as handle:
                handle.write(self.key)
            self.sncast("persistent", "account", "import", "--url", self.url, "--name", self.name,
                        "--type", "oz", "--address", self.address, "--private-key-file", path)
        finally:
            os.remove(path)
        self.key = None

    def close(self):
        """Removes the throwaway accounts file of an account that is not the deployer's."""
        if self.name != "deployer" and os.path.exists(self.accounts):
            os.remove(self.accounts)

    def declare(self, package, name):
        out = self.sncast(package, "--account", self.name, "--wait", "declare", "--url", self.url,
                          "--contract-name", name, "--package", f"grimworld_{package}")
        return field("Class Hash", out)

    def deploy(self, package, class_hash, *calldata):
        args = ["--constructor-calldata", *[hex(c) if isinstance(c, int) else c for c in calldata]] \
            if calldata else []
        fixed = ["--salt", hex(deploy_salt(self.salt, class_hash))] if self.salt is not None else []
        out = self.sncast(package, "--account", self.name, "--wait", "deploy", "--url", self.url,
                          "--class-hash", class_hash, *fixed, *args)
        return field("Contract Address", out)

    def invoke(self, contract, function, *calldata):
        args = ["--calldata", *[hex(c) if isinstance(c, int) else c for c in calldata]] \
            if calldata else []
        out = self.sncast("persistent", "--account", self.name, "--wait", "invoke", "--url",
                          self.url, "--contract-address", contract, "--function", function, *args)
        tx = field("Transaction Hash", out)
        receipt = self.rpc("starknet_getTransactionReceipt", {"transaction_hash": tx})
        if receipt.get("execution_status") != "SUCCEEDED":
            raise RuntimeError(self.redact(f"{function} reverted: {receipt.get('revert_reason')}"))
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


def deploy_salt(salt, class_hash):
    """DEPLOY-SALT: the salt of the deploy of `class_hash` under `--salt`: a hash of both, 250 bits."""
    digest = hashlib.sha256(f"{salt:#x}:{int(class_hash, 16):#x}".encode()).digest()
    return int.from_bytes(digest, "big") & ((1 << 250) - 1)


def felt(text):
    value = int(text, 0)
    if not 0 <= value < 1 << 251:
        raise argparse.ArgumentTypeError("not a felt (0 to 2^251)")
    return value


def hub_instances(node, hub):
    """`Hub.instances` as the chain stores it (no view returns it): the plain variable's slot."""
    word = node.rpc("starknet_getStorageAt", {"contract_address": hub, "block_id": "latest",
                                               "key": hex(storage_key("instances"))})
    return int(word, 16)


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
    records.append((ITEM, REGENERATION_POTION, regeneration_item()))  # SEED-02
    records += [(9, row[0], skill_record(row)) for row in seed_rows("skills", 47)]
    records += [(8, row[0], caste_record(row)) for row in seed_rows("castes", 30)]
    records += [(7, row[0], pack_record(row)) for row in seed_rows("packs", 17)]
    records += [(6, row[0], spawn_table_record(row)) for row in seed_rows("spawn_tables", 17)]
    return records


def deploy_core(node, address):
    """The game's classes and contracts, in OPERATIONS §7's order: `Registry`, `set_zone_checks` at once
    (before any record), `TxHashFate`, the libraries, `Hub`, `Instances`, `Hub.set_contracts`, the play
    classes (keys 0-6, GoblinsLibrary last). Shared by this script and `sepolia_deploy.py` (OPS-02a); `node`
    declares (`node.declare(package, name)`) and deploys. Returns `classes` (name: class hash, the JSON's
    `classes` key, in its order) and the four addresses."""
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
    return {"classes": {"registry": registry_class, **classes,
                        **{re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower(): h
                           for name, h in play.items()}},
            "registry": registry, "fate": fate, "hub": hub, "instances": instances}


def write_seed(node, registry):
    """The records of `seed_records()`, one `Registry.set_record` each."""
    for kind, rid, parts in seed_records():
        node.invoke(registry, "set_record", kind, rid, len(parts), *parts)


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
    """What `--build full` asks of the seed (OPS-01b, SEED-02), read from `seed_records()`'s tables,
    never hard-coded: the four skills wanted, the two potions wanted, and what the seed lacks."""
    columns = ("id", "profession", "attribute", "kind", "energy", "adrenaline", "activation")
    rows = []
    for row in seed_rows("skills", 47):
        entries = [row[11 + 12 * i] for i in range(3)]  # each entry's kind, `skill_record`'s order
        rows.append({**dict(zip(columns, row)), "entries": entries})
    wanted = {  # name: (what it is, its test over a skill row), in the bar's order
        "instant_attack": ("instant attack skill", lambda r: r["kind"] == 1 and r["activation"] == 0),
        "activation_skill": ("skill with an activation of 1 or more",
                             lambda r: r["activation"] >= 1 and r["kind"] != 9),
        "trap": ("trap skill of profession 1", lambda r: r["kind"] == 9 and r["profession"] == 1),
        "regeneration_skill": ("skill with a REGENERATION entry", lambda r: 5 in r["entries"]),
    }
    skills, dropped = {}, {}
    for name, (what, test) in wanted.items():
        found = [r["id"] for r in rows if test(r) and r["id"] not in skills.values()]
        if found:
            skills[name] = found[0]
        else:
            dropped[name] = f"the seed has no {what}"
    # the potions: the first healing potion of the seed's items, and the REGENERATION one (SEED-02)
    return {"skills": skills, "belt": [(POTIONS[0], 2), (REGENERATION_POTION, 1)], "dropped": dropped}


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
        epilog=f"--build full (OPS-01b, SEED-02) ids, read from the seed. Bar: {skills}, bought with "
               f"{GOLD} gold credited by the devnet harness (D-280, devnet only). Belt: {belt}. The "
               f"pack holds twice the belt. Dropped: {dropped}. The same ids are in the JSON's "
               f"`build` key.")
    parser.add_argument("--out", help="write the JSON here instead of stdout")
    parser.add_argument("--build", choices=("empty", "full"), default="empty",
                        help="the adventurer's build: empty (default: an empty bar, no belt) or "
                             "full (a belt of the seed's potions and a pack for a second entry)")
    parser.add_argument("--salt", type=felt, default=None,
                        help="a fixed salt for every deploy (DEPLOY-SALT), so that two runs on fresh "
                             "nodes give the same addresses and the same world; default: random")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--give-build", action="store_true",
                       help="DEPLOY-BUILD-FOR: give SEED-02's build to an adventurer of another account "
                            "(needs --deployment and --account)")
    modes.add_argument("--credit-only", action="store_true",
                       help="DEPLOY-BUILD-FOR: only credit SEED-02's gold and pack to an adventurer "
                            "inside an instance (needs --deployment and --adventurer)")
    parser.add_argument("--deployment", help="the deployment JSON that --out wrote (the two modes above)")
    parser.add_argument("--account", help="--give-build: a predeployed account's index (1-9), or an "
                                          "account address (with --key-env)")
    parser.add_argument("--key-env", help="--give-build: the NAME of the environment variable that holds "
                                          "the private key of the address given as --account")
    parser.add_argument("--adventurer", type=int,
                        help="--give-build: the adventurer's id (default: a new one); "
                             "--credit-only: the adventurer inside an instance")
    return parser.parse_args(argv)


def credit_harness(admin, hub, instances, registry, fate, flatten, inside, adventurer, credits, gold):
    """The admin's half of the harness (D-280), shared by `fund_pack` and the credit-only mode: the hub's
    `instances` is account 0 for one forged Open `report` of the instance `inside` (the pack and the
    gold), then the real `Instances` again, in a `finally`, and read back from the chain: the run fails
    unless it is the `Instances` address. No owner call: only `set_contracts` and `report`."""
    assert_local_devnet(admin)
    logs = os.environ.get("WITH_NODE_LOG_DIR", os.path.join(os.getcwd(), ".with-node"))
    os.makedirs(logs, exist_ok=True)
    with open(os.path.join(logs, "devnet-harness.lock"), "w") as lock:
        # runs overlap (one credit per burner) and all send from account 0: one at a time, or a nonce
        # clash could fail the restore and leave `Hub.instances` pointing at account 0
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            admin.invoke(hub, "set_contracts", registry, admin.address, 4, fate, flatten)
            admin.invoke(hub, "report", inside, 1, adventurer, 0, gold, len(credits),
                         *[f for item, count in credits for f in (item, count)],
                         0, 0, 0, 0, OPEN, 0, 0, 0, 0, 0, 0)
        finally:  # the real `Instances` is restored even when anything above fails, and checked
            try:
                admin.invoke(hub, "set_contracts", registry, instances, 4, fate, flatten)
            except RuntimeError as error:
                raise RuntimeError(f"Hub.instances NOT restored: {error}") from error
            if hub_instances(admin, hub) != int(instances, 16):
                raise RuntimeError("Hub.instances was not restored to the Instances address")


def fund_pack(node, hub, instances, registry, fate, flatten, adventurer, credits, gold, admin=None):
    """The pack and the gold, as the lifecycle probe does it: `report` is the only call that credits
    either. The adventurer enters, the harness credits it (`credit_harness`), and it leaves by the gate
    back to the start hub. The devnet harness of D-280: it refuses any node but a local devnet before it
    writes anything. `node` makes the owner's calls (`enter`, `leave`); `admin` (default: `node`, the
    deployer, who owns the adventurer in `--build full`) the two that only account 0 can make."""
    admin = admin or node
    assert_local_devnet(node)
    inside = entered(node.invoke(hub, "enter", adventurer, 1), instances)
    credit_harness(admin, hub, instances, registry, fate, flatten, inside, adventurer, credits, gold)
    node.invoke(instances, "leave", inside, adventurer, 0, HUB_GATE_BACK)


def pack_for(plan):
    """What the harness credits besides the gold: the pack of twice the belt."""
    return [(item, 2 * count) for item, count in plan["belt"]]


def build_json(mode, plan, bar, belt, pack, left, gold):
    """The `build` key of the deployment JSON, which both modes write in the same shape."""
    full = mode == "full"
    return {"mode": mode, "bar": bar,
            "belt": [{"item": i, "count": c} for i, c in belt],
            "pack": [{"item": i, "count": c} for i, c in pack],
            "pack_after_entry": [{"item": i, "count": c} for i, c in left],
            "derived": ["pack_after_entry"],  # computed here (no pack view yet), not read
            "gold": gold,  # credited by the devnet harness (D-280), all spent on the skills
            "dropped": plan["dropped"] if full else {},
            **({"skills": plan["skills"]} if full else {})}


def load_deployment(path):
    """The deployment JSON of an earlier run: refused when it is missing or lacks what the modes read."""
    try:
        with open(path) as handle:
            dep = json.load(handle)
        dep["node_url"], dep["account"], dep["classes"]["flatten_library"]
        for name in ("registry", "tx_hash_fate", "hub", "instances"):
            dep["contracts"][name]
    except (OSError, ValueError, KeyError, TypeError) as error:
        sys.exit(f"devnet_deploy: no deployment in {path} ({error!r}): run the script first, --out <path>")
    return dep


def mode_nodes(args, dep):
    """The admin's `Node` (account 0, key from the devnet) after every refusal that needs no write, and
    the predeployed accounts. `NODE_URL`, when set, overrides the file's `node_url`."""
    url = os.environ.get("NODE_URL") or dep["node_url"]
    check_url(url)
    logs = os.environ.get("WITH_NODE_LOG_DIR", os.path.join(os.getcwd(), ".with-node"))
    probe = Node(url, dep["account"], "unused", logs, name="probe")
    try:
        assert_local_devnet(probe)
        hub = dep["contracts"]["hub"]
        try:
            probe.rpc("starknet_getClassHashAt", {"block_id": "latest", "contract_address": hub})
        except RuntimeError as error:
            sys.exit(f"devnet_deploy: this node has no deployment (the Hub {hub} has no class: {error})")
        predeployed = probe.rpc("devnet_getPredeployedAccounts", {})
    finally:
        probe.close()
    if not predeployed or int(predeployed[0]["address"], 16) != int(dep["account"], 16):
        sys.exit("devnet_deploy: the first predeployed account of the node is not the deployment's account")
    admin = Node(url, dep["account"], predeployed[0]["private_key"], logs, name="admin")
    try:
        admin.import_account()
    except BaseException:
        admin.close()
        raise
    return admin, predeployed, logs


def owner_of(args, admin, predeployed, logs):
    """`--account` as a `Node` of its own: a predeployed index 1-9, or an address with its key in the
    environment variable `--key-env` names."""
    text = args.account
    if text.isdigit():
        index = int(text)
        if not 1 <= index <= 9 or index >= len(predeployed):
            sys.exit(f"devnet_deploy: --account {index}: the index is 1 to 9 (0 stays the admin)")
        if args.key_env:
            sys.exit("devnet_deploy: --key-env goes with an address, not with a predeployed index")
        address, key = predeployed[index]["address"], predeployed[index]["private_key"]
    else:
        try:
            address = hex(int(text, 16))
        except ValueError:
            sys.exit(f"devnet_deploy: --account {text!r} is neither an index nor an address")
        if not args.key_env or not os.environ.get(args.key_env):
            sys.exit("devnet_deploy: an address needs --key-env NAME, the environment variable "
                     "that holds its private key (not set or empty)")
        key = os.environ[args.key_env]
    owner = Node(admin.url, address, key, logs, name="owner")
    try:
        owner.import_account()
    except BaseException:
        owner.close()
        raise
    return owner


def give_build(admin, owner, dep, adventurer):
    """DEPLOY-BUILD-FOR, `--give-build`: `--build full`'s order for an adventurer of `owner`. Returns
    `(adventurer id, build)`."""
    hub, instances = dep["contracts"]["hub"], dep["contracts"]["instances"]
    registry, fate, flatten = dep["contracts"]["registry"], dep["contracts"]["tx_hash_fate"], \
        dep["classes"]["flatten_library"]
    if adventurer is None:
        if not owner.view("persistent", hub, "account_of", int(owner.address, 16))[0]:
            owner.invoke(hub, "register")
        account_id = owner.view("persistent", hub, "account_of", int(owner.address, 16))[0]

        def ids():  # `Hub.account`: owner, record, then the span of the adventurers' ids
            words = owner.view("persistent", hub, "account", account_id)
            return words[3:3 + words[2]]
        before = ids()
        owner.invoke(hub, "create_adventurer", short("Burner"), 1)
        created = [i for i in ids() if i not in before]
        if len(created) != 1:
            raise RuntimeError(f"the new adventurer's id is not in Hub.account: {before} -> {ids()}")
        adventurer = created[0]
    # an empty build first: the snapshot `enter` needs, and the first owner call, so that an adventurer
    # the account does not own is refused by the chain before the admin writes anything
    owner.invoke(hub, "set_build", adventurer, EMPTY_BUILD, 0, 0)
    plan = build_plan()
    belt, pack, gold = plan["belt"], pack_for(plan), GOLD
    fund_pack(owner, hub, instances, registry, fate, flatten, adventurer, pack, gold, admin=admin)
    for skill in plan["skills"].values():
        owner.invoke(hub, "buy_skill", adventurer, skill)
    bar = [0] * BAR_SLOTS
    bar[:len(plan["skills"])] = plan["skills"].values()
    owner.invoke(hub, "set_build", adventurer, build_word(bar), belt_word(belt), 0)
    return adventurer, build_json("full", plan, bar, belt, pack, list(belt), gold)


def credit_only(admin, dep, adventurer):
    """DEPLOY-BUILD-FOR, `--credit-only`: the harness's admin calls for an adventurer that is inside an
    instance, no owner call. The instance id is read from `Instances.placement`. Refused, before any
    write, when the adventurer is not inside one."""
    hub, instances = dep["contracts"]["hub"], dep["contracts"]["instances"]
    assert_local_devnet(admin)
    placement = admin.view("ephemeral", instances, "placement", adventurer)
    inside_id, _, inside = placement
    if not inside_id or not inside:
        sys.exit(f"devnet_deploy: adventurer {adventurer} is not inside an instance (placement "
                 f"{placement}): it must enter first (Hub.enter) before it is credited, and leave by "
                 f"gate {HUB_GATE_BACK} afterwards")
    plan = build_plan()
    pack = pack_for(plan)
    credit_harness(admin, hub, instances, dep["contracts"]["registry"], dep["contracts"]["tx_hash_fate"],
                   dep["classes"]["flatten_library"], inside_id, adventurer, pack, GOLD)
    return {"adventurer_id": adventurer, "instance_id": inside_id, "gold": GOLD,
            "pack": [{"item": i, "count": c} for i, c in pack],
            "instance_read_from": "Instances.placement"}


def write_output(args, result):
    text = json.dumps(result, indent=2) + "\n"
    if args.out:
        with open(args.out, "w") as out:
            out.write(text)
        print(f"devnet_deploy: wrote {args.out}", file=sys.stderr)
    else:
        sys.stdout.write(text)


def run_mode(args):
    """`--give-build` and `--credit-only`: every refusal comes before a write that needs a refusal."""
    if not args.deployment:
        sys.exit("devnet_deploy: --deployment <json> is needed")
    if args.credit_only:
        if args.adventurer is None or args.account or args.key_env:
            sys.exit("devnet_deploy: --credit-only takes --adventurer <id> and no account (it makes "
                     "no owner call)")
    elif not args.account:
        sys.exit("devnet_deploy: --give-build needs --account <1-9 | address>")
    if args.give_build and args.account.isdigit() and not 1 <= int(args.account) <= 9:
        sys.exit(f"devnet_deploy: --account {args.account}: the index is 1 to 9 (0 stays the admin)")
    dep = load_deployment(args.deployment)
    admin, owner = None, None
    try:
        admin, predeployed, logs = mode_nodes(args, dep)
        if args.credit_only:
            result = credit_only(admin, dep, args.adventurer)
        else:
            owner = owner_of(args, admin, predeployed, logs)
            adventurer, build = give_build(admin, owner, dep, args.adventurer)
            result = {"account": owner.address, "adventurer_id": adventurer, "build": build}
    except RuntimeError as error:  # a refusal of the chain (not the owner, a known skill): passed on
        print(f"devnet_deploy: the chain refused: {error}", file=sys.stderr)
        return 1
    finally:
        for node in (admin, owner):
            if node:
                node.close()
    write_output(args, result)
    return 0


def main(argv):
    args = parse(argv)
    if args.give_build or args.credit_only:
        return run_mode(args)
    out_path = args.out
    try:
        url = os.environ["NODE_URL"]
        address = os.environ["NODE_ACCOUNT_ADDRESS"]
        key = os.environ["NODE_ACCOUNT_PRIVATE_KEY"]
    except KeyError as missing:
        sys.exit(f"devnet_deploy: {missing} is not set (run under scripts/with-node.sh)")
    node = Node(url, address, key,
                os.environ.get("WITH_NODE_LOG_DIR", os.path.join(os.getcwd(), ".with-node")),
                args.salt)

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

    core = deploy_core(node, address)
    classes, registry, fate, hub, instances = (core["classes"], core["registry"], core["fate"],
                                               core["hub"], core["instances"])
    write_seed(node, registry)

    node.invoke(hub, "register")
    node.invoke(hub, "create_adventurer", short("Aldric"), 1)
    adventurer = 1  # the first the hub creates (it counts from 1)
    node.invoke(hub, "set_build", adventurer, EMPTY_BUILD, 0, 0)
    plan = build_plan()
    bar = [0] * BAR_SLOTS
    belt, pack, left, gold = [], [], [], 0
    if args.build == "full":
        belt = plan["belt"]
        pack = pack_for(plan)
        left = [(item, count) for item, count in belt]
        gold = GOLD
        fund_pack(node, hub, instances, registry, fate, classes["flatten_library"], adventurer, pack,
                  gold)
        for skill in plan["skills"].values():  # D-275: the trainer is the only way to know a skill
            node.invoke(hub, "buy_skill", adventurer, skill)
        bar[:len(plan["skills"])] = plan["skills"].values()
        node.invoke(hub, "set_build", adventurer, build_word(bar), belt_word(belt), 0)
    instance = entered(node.invoke(hub, "enter", adventurer, 1), instances)

    result = {
        "node_url": url, "chain_id": chain, "commit": commit(), "account": address,
        "salt": None if args.salt is None else hex(args.salt),
        "classes": classes,
        "contracts": {"registry": registry, "tx_hash_fate": fate, "hub": hub,
                      "instances": instances},
        "adventurer_id": adventurer, "instance_id": instance, "slot": instance >> 32,
        "build": build_json(args.build, plan, bar, belt, pack, left, gold),
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
