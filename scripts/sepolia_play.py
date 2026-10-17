#!/usr/bin/env python3
"""GATE-1a (D-308): plays the Phase 1 path on a deployment, and writes the run's record. The gate (PLAN.md,
Overview): create an adventurer, enter a zone, cross rooms, reach a hub. From the repository root, with the
account in the environment (OPERATIONS §7, used by name, as `scripts/sepolia_deploy.py` reads it):

    python3 scripts/sepolia_play.py                                   # the newest deployment record
    python3 scripts/sepolia_play.py --deployment deployments/sepolia/<record>.json
    python3 scripts/sepolia_play.py --dry-run                         # the plan; nothing sent
    scripts/with-node.sh python3 scripts/sepolia_play.py --devnet --deployment <devnet_deploy.py's JSON> \\
        --out <path>.json                                             # the same path on a local devnet

The variables `STARKNET_NETWORK`, `STARKNET_RPC_URL`, `STARKNET_ACCOUNT_ADDRESS`, `STARKNET_PRIVATE_KEY` are
read by name, and the guards are `sepolia_deploy.py`'s, imported: **no value of a secret `STARKNET_*`
variable (the RPC URL and its host, the account address, the key) is printed, logged or written** (its
`Redactor`, with the same limits); the key reaches `sncast` through a 0600 file, deleted at once, and the
URL through a 0600 `snfoundry.toml` in a private folder removed in a `finally`; a rate-limited read is
retried with a backoff, and a transaction that failed on a rate limit is sent again only when the account's
nonce shows nothing was accepted (OPS-03); `--pace` waits between transactions.

What it does, in order, and nothing is sent before step 5:
  1. the URL: remote and https, or with `--devnet` exactly `http://127.0.0.1:<port>` and a starknet-devnet;
  2. the chain id, which must be `SN_SEPOLIA` (a devnet answers it too: `--devnet` is the one way to run on
     one, and a Sepolia run refuses a node that answers `devnet_getPredeployedAccounts`);
  3. the deployment: the record named by `--deployment`, or the newest of `deployments/sepolia/` (by date,
     then by `artefact.run`, as its README says); a Sepolia record must not be a rehearsal, and the Hub's
     class on the chain must be the record's (a record of another network or a wrong file stops here);
  4. the gates, read from the registry: gate 1 (the town into the zone) and gate 2 (the zone back to the
     town, a hub gate); prints the plan. `--dry-run` stops here;
  5. `Hub.register` when the account has none, `create_adventurer` (profession 1, the name `GATE-1a`; its
     id is the one `Hub.account` gains), `set_build` with an empty build (the snapshot `enter` needs);
  6. `Hub.enter` through gate 1: the instance's id is `InstanceEntered`'s;
  7. **crosses rooms**: `play` batches of Moves (at most 10 a batch) out of the entry chunk into at least
     `--chunks` (2) other chunks of the zone's set, then back to gate 2's anchor. Each batch is planned from
     what the chain has revealed: `Instances.instance_state` (the member's tile, its health, the goblins a
     batch would load) and `Instances.instance_region` (each chunk's kind, walls, packs and objects), read
     again after every batch. The route is the cheapest over the walkable tiles of the revealed chunks; a
     chunk not yet revealed is approached until sight reveals it (the batch reveals it on the way). Each
     chunk entered is recorded, from the Moves `BatchPlayed` counts, and the member's tile on the chain must
     be the one the Moves played lead to;
  8. `Instances.leave` by gate 2 on its anchor: the instance closes, Returned, and the adventurer is in the
     town, **the hub is reached** (read back: `Hub.adventurer`'s place and `Instances.placement`);
  9. the record: the JSON (the deployment record's name and commit, every transaction with its hash and fee,
     the adventurer's id, the chunks crossed in order, the final location, the hits taken, the total fee,
     the times) and a
     short Markdown summary beside it, `docs/reports/GATE-1-sepolia-play-<date>-<record>.{json,md}` by
     default. A stopped run writes what it sent, `"completed": false` and why.

**Goblins: the script never fights.** The zone names a spawn table, so a revealed chunk may hold a pack. The
route never steps within 2 tiles of a pack's tile (its goblins stand there), nor on a living goblin, an
object (a trap among them) or a tile a Move found blocked, and it keeps away from packs (a tile within
`AVOID` of one costs `DETOUR` more): a pack in the way is routed around. A goblin that wakes and hits the
member is not fought either: the hit is recorded (`hits`: the tile, the health before and after, the goblins
near) and the route goes on, around the goblins, to its goal. When goblins are all that blocks the way
(they chase, and a corridor is one tile wide), the member walks up to the first and plays Waits, two a
batch, until they move, then the route is planned again. When no route is left, even through goblins, or
goblins block it for `MAX_WAITING` batches of Waits in a row, or the member's health
falls below half of what it entered with, or a batch ends `Defeated` or `Closed`, the run stops with a
message that names the tile and the instance, and writes its record (`"completed": false`); the adventurer
is left inside (the client, or `Instances.travel_back`, brings it out).

The log is `$WITH_NODE_LOG_DIR/sepolia-play.log` (default `./.with-node/`, gitignored), redacted.
"""
import argparse
import datetime
import glob
import heapq
import json
import os
import re
import shutil
import signal
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import devnet_deploy as dd  # noqa: E402  the node, the build words, the events
import sepolia_deploy as sd  # noqa: E402  the guards: Redactor, Log, SepoliaNode, the checks

NAME = "gate1a"
RECORDS = sd.RECORDS
REPORTS = os.path.join(ROOT, "docs", "reports")
GATE_IN, GATE_OUT = 1, 2  # the town into the zone; the zone back to the town (`seed_records`)
PROFESSION = 1
HERO = "GATE-1a"  # the adventurer's name, a short string
CHUNKS = 2  # chunks of the zone entered besides the entry one
MAX_MOVES = 10  # a batch's actions (`types::batch`)
MAX_BATCHES = 60
AVOID, DETOUR = 5, 20  # a tile within AVOID of a pack's tile costs DETOUR more
WAIT, K_WAIT = "wait", 2  # a Wait, and its action code (`types::batch`)
WAITS, MAX_WAITING = 2, 8  # Waits a batch while goblins block the way; such batches in a row at most
GOBLIN_COST = 50  # a goblin's tile, on a route through goblins (they move: the member waits for them)
SIDE = 15  # tiles a chunk side; chunk `15 cy + cx`
WALLS = (1 << 225) - 1
# `Stop` (grimworld_logic::types): None, Sequence, Invalid, Weight, Defeated, Closed, Version
NONE, SEQUENCE, INVALID, WEIGHT, DEFEATED, CLOSED, VERSION = range(7)
STOPS = ("None", "Sequence", "Invalid", "Weight", "Defeated", "Closed", "Version")
RETURNED = 1  # `Outcome::Returned`
VOID, HIDDEN, REVEALED = range(3)  # `ChunkKind`
EVENTS = {name: dd.storage_key(name) for name in
          ("InstanceEntered", "BatchPlayed", "Refused", "InstanceClosed", "ChunkRevealed", "Defeated")}


class Stopped(RuntimeError):
    """The run cannot go on without fighting or guessing: the message says where and why."""


# --- the board: hexx's layout, as `contracts/tools/lifecycle_probe.py` walks it ---------------------------

def step(x, y, d):
    """The neighbour of a global tile in direction `d` (`LayoutTrait::neighbor`, the row's parity global)."""
    odd = y % 2 == 1
    return [(x - 1, y), (x, y + 1) if odd else (x - 1, y + 1),
            (x + 1, y + 1) if odd else (x, y + 1), (x + 1, y),
            (x + 1, y - 1) if odd else (x, y - 1), (x, y - 1) if odd else (x - 1, y - 1)][d]


def distance(a, b):
    """Hex distance of two global tiles (axial `q = x - floor(y / 2)`, `r = y`)."""
    (ax, ay), (bx, by) = a, b
    dq, dr = (bx - by // 2) - (ax - ay // 2), by - ay
    return (abs(dq) + abs(dr) + abs(dq + dr)) // 2


def chunk_of(tile):
    return (tile[1] // SIDE) * SIDE + tile[0] // SIDE


def tile_of(chunk, tile):
    """The global tile of `tile` (`15 row + column`) in `chunk` (`15 cy + cx`)."""
    return (chunk % SIDE) * SIDE + tile % SIDE, (chunk // SIDE) * SIDE + tile // SIDE


def centre(chunk):
    return tile_of(chunk, 7 * SIDE + 7)


def batch(actions):
    """`types::batch::BatchTrait::encode` of Moves and Waits: the count at bits 0-3, action `i` (24 bits: a
    Move's kind 0 and its direction at bits 3-5, a Wait's kind 2) at `4 + 24 i` for `i` 0-4 and
    `128 + 24 (i - 5)` after. An action is a direction 0-5 or `WAIT`."""
    if not 1 <= len(actions) <= MAX_MOVES or any(a != WAIT and a not in range(6) for a in actions):
        raise ValueError(f"not a batch of Moves and Waits: {actions}")
    word = len(actions)
    for i, a in enumerate(actions):
        word += (K_WAIT if a == WAIT else a * 8) << (4 + 24 * i if i < 5 else 128 + 24 * (i - 5))
    return word


class Board:
    """What the chain has revealed of the instance, read through the two views."""

    def __init__(self, state, rows):
        self.at, self.health, self.goblins = member(state)
        self.patient = False  # a route may run through living goblins (they move; the member waits)
        self.kinds, self.walkable, self.objects, self.packs = {}, set(), set(), []
        for chunk, kind, terrain, features in rows:
            self.kinds[chunk] = kind
            if kind != REVEALED:
                continue
            walls = terrain & WALLS
            for t in range(SIDE * SIDE):
                if not (walls >> t) & 1:
                    self.walkable.add(tile_of(chunk, t))
            low, high = features & ((1 << 128) - 1), features >> 128
            for slot in range(2):  # `PackPlacement`: tile 0-7, count 32-35, alert 61-63
                pack = (low >> (64 * slot)) & ((1 << 64) - 1)
                if (pack >> 32) & 0xF:
                    self.packs.append((tile_of(chunk, pack & 0xFF), (pack >> 32) & 0xF, pack >> 61))
            for slot in range(3):  # `Object`: tile 0-7, kind 8-11 (a trap is one)
                thing = (high >> (32 * slot)) & 0xFFFFFFFF
                if (thing >> 8) & 0xF:
                    self.objects.add(tile_of(chunk, thing & 0xFF))

    def blocked(self, extra):
        """Tiles a route never takes: a living goblin (`instance_state` lists the window's, with their
        tiles), the tiles within 2 of a pack none of whose goblins it lists (they stand there), an object,
        and the tiles a Move found blocked."""
        living = self.living()
        out = set(extra) | self.objects | (set() if self.patient else living)
        for tile, _, _ in self.packs:
            if not any(distance(tile, g) <= 2 for g in living):
                out |= {t for t in self.walkable if distance(t, tile) <= 2}
        return out

    def living(self):
        return {(g[0], g[1]) for g in self.goblins if g[2] > 0}

    def route(self, goal, extra=()):
        """The cheapest Moves from the member's tile to a tile `goal` accepts, over the revealed walkable
        tiles, keeping away from packs; None when no tile is reachable."""
        blocked = self.blocked(extra) - {self.at}
        living = self.living()
        packs = [p[0] for p in self.packs] + list(living)
        cost = lambda t: 1 + (DETOUR if any(distance(t, p) <= AVOID for p in packs) else 0) \
            + (GOBLIN_COST if t in living else 0)
        frontier, best = [(0, self.at, [])], {self.at: 0}
        while frontier:
            spent, tile, moves = heapq.heappop(frontier)
            if goal(tile):
                return moves
            if spent > best.get(tile, spent):
                continue
            for d in range(6):
                n = step(*tile, d)
                if n in self.walkable and n not in blocked and spent + cost(n) < best.get(n, 1 << 30):
                    best[n] = spent + cost(n)
                    heapq.heappush(frontier, (spent + cost(n), n, moves + [d]))
        return None

    def toward(self, chunk, extra=()):
        """The Moves to `chunk`: into it when it is revealed and reachable; else to the reachable tile
        nearest its centre, when nearer than the member is (sight reveals it on the way); else None."""
        moves = self.route(lambda t: chunk_of(t) == chunk, extra)
        if moves is not None:
            return moves
        target = centre(chunk)
        reach = self.reachable(extra)
        nearest = min(reach, key=lambda t: (distance(t, target), t), default=None)
        if nearest is None or distance(nearest, target) >= distance(self.at, target):
            return None
        return self.route(lambda t: t == nearest, extra)

    def reachable(self, extra):
        blocked, seen, todo = self.blocked(extra) - {self.at}, {self.at}, [self.at]
        while todo:
            tile = todo.pop()
            for d in range(6):
                n = step(*tile, d)
                if n in self.walkable and n not in blocked and n not in seen:
                    seen.add(n)
                    todo.append(n)
        return seen


def member(state):
    """The member's tile and health (`MemberState`: x 32-39, y 40-47, health 64-79) and the living goblins
    of the window (`GoblinView` (entity, derived, state, timers); `GoblinState`: x 0-7, y 8-15, health
    32-47), from `instance_state`'s raw felts: id, header, entropy, revealed, quotas, then the spans of the
    tasks, the members, the roster and the goblins, then width, height, level_min."""
    at = 5
    tasks = state[at]
    at += 1 + tasks
    if state[at] == 0:
        raise RuntimeError("instance_state: no member (the instance is not this adventurer's current one)")
    word = state[at + 1]
    at += 1 + state[at]
    at += 1 + state[at]  # the roster
    goblins = []
    for i in range(state[at]):
        word_g = state[at + 1 + 4 * i + 2]
        goblins.append((word_g & 0xFF, (word_g >> 8) & 0xFF, (word_g >> 32) & 0xFFFF))
    return ((word >> 32) & 0xFF, (word >> 40) & 0xFF), (word >> 64) & 0xFFFF, goblins


def region_rows(raw):
    """`instance_region`'s raw felts as (chunk, kind, terrain, features); each chunk's goblins span skipped."""
    rows, i = [], 1
    while i < len(raw):
        rows.append((raw[i], raw[i + 1], raw[i + 2], raw[i + 3]))
        i += 5 + 4 * raw[i + 4]
    return rows


# --- the deployment and the gates ---------------------------------------------------------------------------

def newest_record(folder=RECORDS):
    """The newest record of `folder`: by the date of its name, then by its `artefact.run` id (README)."""
    def key(path):
        with open(path) as handle:
            run = json.load(handle).get("artefact", {}).get("run", "")
        found = re.search(r"/runs/([0-9]+)$", run)
        return os.path.basename(path)[:10], int(found.group(1)) if found else -1
    paths = [p for p in glob.glob(os.path.join(folder, "*.json")) if re.match(r"\d{4}-\d{2}-\d{2}-", os.path.basename(p))]
    return max(paths, key=key, default=None)


def load_deployment(path, devnet, log):
    try:
        with open(path) as handle:
            dep = json.load(handle)
        contracts = {k: dep["contracts"][k] for k in ("registry", "hub", "instances")}
        hub_class = dep["classes"]["hub"]
    except (OSError, ValueError, KeyError, TypeError) as error:
        log.die(f"--deployment {os.path.basename(path)}: not a deployment record ({type(error).__name__})")
    if not devnet and (dep.get("rehearsal") is not False or dep.get("chain_id") != sd.CHAIN):
        log.die(f"{os.path.basename(path)}: not a Sepolia deployment record (a rehearsal, or another chain)")
    if devnet and dep.get("rehearsal") is False:
        log.die(f"{os.path.basename(path)}: a Sepolia record: --devnet plays a devnet deployment")
    return dep, contracts, hub_class


def gate_of(node, registry, gate):
    """The gate's record from the registry: (source, destination, anchor (chunk, tile), arrival, kind)
    (`seed_records.gate`'s packing)."""
    words = node.view("persistent", registry, "record", 4, gate)  # GATE
    if not words or words[0] == 0 or not (words[1] >> 250) & 1:
        raise Stopped(f"gate {gate}: no record in the registry")
    w = words[1]
    return {"source": w & 0xFFFF, "destination": (w >> 16) & 0xFFFF,
            "anchor": ((w >> 32) & 0xFF, (w >> 40) & 0xFF), "arrival": ((w >> 48) & 0xFF, (w >> 56) & 0xFF),
            "kind": (w >> 64) & 0xFF}


def events(receipt, instances, name):
    return [e for e in receipt.get("events", []) if int(e["from_address"], 16) == int(instances, 16)
            and e["keys"] and int(e["keys"][0], 16) == EVENTS[name]]


# --- the run ------------------------------------------------------------------------------------------------

class Play:
    """The Phase 1 path for one account, every transaction kept with what it was for."""

    def __init__(self, node, log, contracts, chunks):
        self.node, self.log, self.chunks = node, log, chunks
        self.hub, self.instances, self.registry = contracts["hub"], contracts["instances"], contracts["registry"]
        self.steps = []  # (what, transaction hash)
        self.crossed = []  # every chunk entered, in order: {chunk, tile, batch}
        self.adventurer = self.instance = None
        self.sequence = 0
        self.health, self.hits = None, []  # the health at the first board; each fall of it, where

    def invoke(self, what, contract, function, *calldata):
        before = len(self.node.sent)
        receipt = self.node.invoke(contract, function, *calldata)
        for tx in self.node.sent[before:]:
            self.steps.append((what, tx))
        return receipt

    def adventurer_ids(self, account):
        words = self.node.view("persistent", self.hub, "account", account)  # owner, record, the ids' span
        return words[3:3 + words[2]]

    def create(self):
        address = int(self.node.address, 16)
        account = self.node.view("persistent", self.hub, "account_of", address)[0]
        if not account:
            self.invoke("register", self.hub, "register")
            account = self.node.view("persistent", self.hub, "account_of", address)[0]
            self.log.say(f"account registered: account {account}")
        before = self.adventurer_ids(account)
        self.invoke("create_adventurer", self.hub, "create_adventurer", dd.short(HERO), PROFESSION)
        created = [i for i in self.adventurer_ids(account) if i not in before]
        if len(created) != 1:
            raise Stopped(f"the new adventurer is not in Hub.account: {before} -> {created}")
        self.adventurer = created[0]
        self.log.say(f"adventurer {self.adventurer} created ({HERO}, profession {PROFESSION})")
        self.invoke("set_build", self.hub, "set_build", self.adventurer, dd.EMPTY_BUILD, 0, 0)

    def place(self):
        """`Hub.adventurer`'s place word (the second): (hub, inside)."""
        word = self.node.view("persistent", self.hub, "adventurer", self.adventurer)[2]
        return (word >> 64) & 0xFFFF, (word >> 96) & 0xFF

    def enter(self, gate):
        receipt = self.invoke(f"enter (gate {gate})", self.hub, "enter", self.adventurer, gate)
        self.instance = dd.entered(receipt, self.instances)
        self.log.say(f"entered instance {self.instance} (slot {self.instance >> 32}) by gate {gate}")

    def board(self):
        state = self.node.view("ephemeral", self.instances, "instance_state", self.instance)
        width, height = state[-3], state[-2]
        rows = []
        for cy in range(height):
            rows += region_rows(self.node.view("ephemeral", self.instances, "instance_region", self.instance,
                                               cy * SIDE, width))
        return Board(state, rows)

    def play(self, moves, number):
        """One batch; returns (played, stop)."""
        kind = f"{len(moves)} Waits" if WAIT in moves else f"{len(moves)} Moves"
        receipt = self.invoke(f"play (batch {number}, {kind})", self.instances, "play",
                              self.instance, self.adventurer, self.sequence, self.version, batch(moves))
        if events(receipt, self.instances, "Defeated"):
            raise Stopped(f"batch {number}: the adventurer was defeated in instance {self.instance}")
        played = events(receipt, self.instances, "BatchPlayed")
        if len(played) != 1:
            raise RuntimeError(f"batch {number}: {len(played)} BatchPlayed events")
        data = [int(d, 16) for d in played[0]["data"]]  # adventurer, from, played, stop, sequence, clock, version
        count, stop, self.sequence = data[2], data[3], data[4]
        if stop == VERSION:
            self.version = data[6]
        revealed = [int(e["data"][0], 16) for e in events(receipt, self.instances, "ChunkRevealed")]
        self.log.say(f"batch {number}: {count} of {kind} played, stop {STOPS[stop]}, "
                     f"sequence {self.sequence}" + (f", chunks revealed {revealed}" if revealed else ""))
        return count, stop

    def walk(self, goal_of, done, what):
        """Batches until `done(board)`; `goal_of(board, blocked)` gives the next Moves or None."""
        blocked, health, waiting = set(), None, 0
        for _ in range(MAX_BATCHES):
            board = self.board()
            if self.health is None:
                self.health = board.health
            if health is not None and board.health < health:
                near = sorted((distance(board.at, g[:2]), g[:2]) for g in board.goblins if g[2] > 0)[:4]
                self.hits.append({"tile": list(board.at), "health": [health, board.health],
                                  "goblins": [{"tile": list(t), "distance": d} for d, t in near]})
                self.log.say(f"hit: health {health} to {board.health} at {board.at}, goblins near: "
                             f"{', '.join(f'{t} at {d}' for d, t in near) or 'none'}; not fighting, going on")
                if board.health * 2 < self.health:
                    raise Stopped(f"the member's health fell to {board.health} of {self.health} at {board.at} "
                                  f"in instance {self.instance}: goblins engaged it, and this script does not "
                                  f"fight")
            health = board.health
            if done(board):
                return board
            moves = goal_of(board, blocked)
            if not moves:  # goblins in the way: walk up to the first, then wait for them to move
                board.patient = True
                moves = goal_of(board, blocked) or []
                tile = board.at
                for i, d in enumerate(moves):
                    tile = step(*tile, d)
                    if tile in board.living():
                        moves = moves[:i]
                        break
                else:
                    moves = moves if moves else None
                if moves is None:
                    packs = ", ".join(f"{p[0]} ({p[1]} goblins)" for p in board.packs) or "none"
                    goblins = ", ".join(str(g[:2]) for g in board.goblins if g[2] > 0) or "none"
                    raise Stopped(f"{what}: no route from {board.at} over the revealed tiles in instance "
                                  f"{self.instance} (packs: {packs}; goblins: {goblins}); the script does not "
                                  f"fight its way through")
            waiting = waiting + 1 if not moves else 0
            if waiting > MAX_WAITING:
                raise Stopped(f"{what}: goblins blocked the way from {board.at} for {MAX_WAITING} batches of "
                              f"Waits in instance {self.instance}; the script does not fight its way through")
            moves = moves[:MAX_MOVES]
            path = [board.at]
            for d in moves:
                path.append(step(*path[-1], d))
            if waiting:
                self.log.say(f"goblins in the way from {board.at}: waiting for them to move")
            number = len([s for s in self.steps if s[0].startswith("play")]) + 1
            count, stop = self.play(moves or [WAIT] * WAITS, number)
            count = min(count, len(moves))
            if stop in (DEFEATED, CLOSED):
                raise Stopped(f"batch stopped {STOPS[stop]} in instance {self.instance}")
            # the Move after the ones played met a wall or an actor; an actor moves: the next plan only
            blocked = {path[count + 1]} if stop == INVALID and count < len(moves) else set()
            for tile in path[1:count + 1]:
                if chunk_of(tile) != chunk_of(self.trail[-1]):
                    self.crossed.append({"chunk": chunk_of(tile), "tile": list(tile)})
                    self.log.say(f"entered chunk {chunk_of(tile)} at {tile}")
                self.trail.append(tile)
            at = self.board().at
            if at != path[count]:
                raise RuntimeError(f"the member is at {at} on the chain, the Moves played lead to {path[count]}")
        raise Stopped(f"{what}: not done after {MAX_BATCHES} batches (instance {self.instance})")

    def cross(self):
        """Out of the entry chunk into `self.chunks` others of the zone's set, the nearest first."""
        self.trail = [self.board().at]
        entry_chunk = chunk_of(self.trail[0])
        target = [None]  # kept while it can be approached, so that two chunks at the same distance never alternate

        def others():
            return {c["chunk"] for c in self.crossed} - {entry_chunk}

        def goal(board, blocked):
            skipped = set()
            while True:
                candidates = [c for c, kind in board.kinds.items()
                              if kind != VOID and c != entry_chunk and c not in others() and c not in skipped]
                if not candidates:
                    return None
                if target[0] not in candidates:
                    target[0] = min(candidates, key=lambda c: (distance(board.at, centre(c)), c))
                moves = board.toward(target[0], blocked)
                if moves:
                    return moves
                if board.patient:
                    self.log.say(f"chunk {target[0]}: no route from {board.at} now, trying another")
                skipped.add(target[0])

        self.walk(goal, lambda board: len(others()) >= self.chunks, "crossing rooms")
        return sorted(others())

    def back(self, anchor):
        self.walk(lambda board, blocked: board.route(lambda t: t == anchor, blocked),
                  lambda board: board.at == anchor, f"back to the gate's anchor {anchor}")

    def leave(self, gate):
        receipt = self.invoke(f"leave (gate {gate})", self.instances, "leave", self.instance, self.adventurer,
                              self.sequence, gate)
        if events(receipt, self.instances, "Refused"):
            raise Stopped(f"leave by gate {gate}: refused in instance {self.instance}")
        closed = events(receipt, self.instances, "InstanceClosed")
        if not closed or int(closed[0]["data"][0], 16) != RETURNED:
            raise Stopped(f"leave by gate {gate}: the instance did not close Returned")


def fees(node, steps):
    """Each transaction's fee, from its receipt; the total (one unit)."""
    out, total, units = [], 0, set()
    for what, tx in steps:
        paid = node.rpc("starknet_getTransactionReceipt", {"transaction_hash": tx})["actual_fee"]
        out.append({"what": what, "hash": tx, "fee": str(int(paid["amount"], 16)), "unit": paid["unit"]})
        total += int(paid["amount"], 16)
        units.add(paid["unit"])
    if len(units) > 1:
        raise RuntimeError(f"fees in several units: {sorted(units)}")
    return out, {"amount": str(total), "unit": units.pop() if units else "FRI"}


def summary(record):
    """The Markdown summary for docs/reports/."""
    done = "reached" if record["completed"] else "**not reached**"
    lines = [f"# GATE-1: the Phase 1 path on {record['network']} ({record['started'][:10]})", "",
             f"The Phase 1 gate (PLAN.md, Overview): create an adventurer, enter a zone, cross rooms, reach a hub: "
             f"{done}. Played by `scripts/sepolia_play.py` at commit `{record['script_commit'][:7]}` on the "
             f"deployment `{record['deployment']['name']}` (commit `{record['deployment']['commit'][:7]}`).", "",
             f"- Adventurer: {record['adventurer_id']}",
             f"- Entered: instance {record['instance_id']}, by gate {record['gates']['in']['id']} "
             f"(location {record['gates']['in']['source']} to {record['gates']['in']['destination']})",
             "- Chunks crossed, in order: " + (", ".join(
                 f"{c['chunk']} (at {tuple(c['tile'])})" for c in record["chunks_crossed"]) or "none"),
             f"- Final location: {record['final_location']}",
             f"- Hits taken (the script never attacks): {len(record['hits'])}" + "".join(
                 f"; at {tuple(h['tile'])}, health {h['health'][0]} to {h['health'][1]}" for h in record["hits"]),
             f"- Transactions: {len(record['transactions'])}, total fee {record['total_fee']['amount']} "
             f"{record['total_fee']['unit']}",
             f"- Time: {record['started']} to {record['finished']} ({record['seconds']} s)"]
    if not record["completed"]:
        lines.append(f"- Stopped: {record['stopped']}")
    lines += ["", "| # | Transaction | Hash | Fee |", "|---|---|---|---|"]
    lines += [f"| {i} | {t['what']} | `{t['hash']}` | {t['fee']} {t['unit']} |"
              for i, t in enumerate(record["transactions"], 1)]
    return "\n".join(lines) + "\n"


def write_new(path, text):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "x") as out:  # never over an earlier record
        out.write(text)


def parse(argv):
    parser = argparse.ArgumentParser(
        prog="python3 scripts/sepolia_play.py",
        description="Plays the Phase 1 path (create an adventurer, enter the zone, cross rooms, reach the hub) on "
                    "a deployment, and writes the run's record (GATE-1a, D-308). The account is read from "
                    "STARKNET_NETWORK, STARKNET_RPC_URL, STARKNET_ACCOUNT_ADDRESS and STARKNET_PRIVATE_KEY, by "
                    "name; no value is ever printed.")
    parser.add_argument("--deployment", help="the deployment record (default: the newest of deployments/sepolia/; "
                                             "with --devnet, devnet_deploy.py's JSON, required)")
    parser.add_argument("--devnet", action="store_true",
                        help="play on a local starknet-devnet (http://127.0.0.1:<port>) after devnet_deploy.py; "
                             "the only way the script runs on a local node; needs --deployment and --out")
    parser.add_argument("--out", help="the JSON record's path; the Markdown summary goes beside it (.md) "
                                      "(default docs/reports/GATE-1-sepolia-play-<date>-<record>.json)")
    parser.add_argument("--dry-run", action="store_true", help="check, read and print the plan; send nothing")
    parser.add_argument("--chunks", type=int, default=CHUNKS,
                        help=f"chunks of the zone to enter besides the entry one (default {CHUNKS})")
    parser.add_argument("--pace", type=float, default=sd.PACE, metavar="SECONDS",
                        help=f"wait this long between two transactions, against the RPC's rate limit "
                             f"(default {sd.PACE:g}; --devnet uses 0)")
    parser.add_argument("--backoff", type=float, default=sd.BACKOFF, help=argparse.SUPPRESS)
    parser.add_argument("--account-type", choices=("oz", "argent", "braavos"), default="oz",
                        help="the account's class, as sncast names it (default oz)")
    return parser.parse_args(argv)


def run(args, log, redact, environ):
    started = datetime.datetime.now(datetime.timezone.utc)
    if args.devnet and not (args.deployment and args.out):
        log.die("--devnet needs --deployment (devnet_deploy.py's JSON) and --out")
    if args.out and args.devnet and os.path.abspath(args.out).startswith((REPORTS + os.sep, RECORDS + os.sep)):
        log.die("--out is under docs/reports or deployments/sepolia: a devnet run's record is never written there")
    if args.chunks < 1 or args.pace < 0 or args.backoff < 0:
        log.die("--chunks is 1 or more; --pace: a number of seconds, 0 or more")
    missing = [name for name in sd.VARIABLES if not environ.get(name)]
    if missing:
        log.die(f"{', '.join(missing)}: not set")
    url = environ["STARKNET_RPC_URL"]
    try:
        address = hex(int(environ["STARKNET_ACCOUNT_ADDRESS"], 16))
        key = hex(int(environ["STARKNET_PRIVATE_KEY"], 16))
    except ValueError:
        log.die("STARKNET_ACCOUNT_ADDRESS or STARKNET_PRIVATE_KEY: not hex")
    sd.check_endpoint(url, args.devnet, log, flag="--devnet")
    pace = 0.0 if args.devnet else args.pace

    logs = tempfile.mkdtemp(prefix="sepolia-play-")  # 0700: the accounts file holds the key
    try:
        node = sd.SepoliaNode(url, address, "unused", logs, {}, redact, log.say, pace=pace, backoff=args.backoff,
                              tag="latest" if args.devnet else "pre_confirmed")
        chain = sd.check_chain(node, args.devnet, log, flag="--devnet")
        sncast_version = sd.read_sncast_version(log)
        path = args.deployment or newest_record()
        if not path:
            log.die("no deployment record in deployments/sepolia")
        dep, contracts, hub_class = load_deployment(path, args.devnet, log)
        name = os.path.splitext(os.path.basename(path))[0]
        on_chain = node.rpc("starknet_getClassHashAt", {"block_id": "latest", "contract_address": contracts["hub"]})
        if int(on_chain, 16) != int(hub_class, 16):
            log.die(f"{name}: the Hub's class on this chain is not the record's: another deployment or network")
        gates = {"in": gate_of(node, contracts["registry"], GATE_IN), "out": gate_of(node, contracts["registry"], GATE_OUT)}
        if gates["out"]["kind"] != 1 or gates["out"]["source"] != gates["in"]["destination"] \
                or gates["out"]["destination"] != gates["in"]["source"]:
            log.die(f"gates {GATE_IN} and {GATE_OUT}: not a way into a location and a hub gate back ({gates})")
        anchor = tile_of(*gates["out"]["anchor"])
        log.say(f"deployment {name} (commit {dep.get('commit', 'unknown')[:7]}): hub {contracts['hub']}, "
                f"instances {contracts['instances']}")
        log.say(f"plan: register if needed, create_adventurer, set_build (empty), enter by gate {GATE_IN} "
                f"(location {gates['in']['source']} to {gates['in']['destination']}), play batches of at most "
                f"{MAX_MOVES} Moves into {args.chunks} chunks besides the entry one, back to gate {GATE_OUT}'s "
                f"anchor {anchor}, leave by gate {GATE_OUT} to location {gates['out']['destination']}")
        log.say(f"pace: {pace:g} s between transactions" + (" (devnet)" if args.devnet else ""))
        if args.dry_run:
            log.say("--dry-run: nothing sent")
            return 0
        out = args.out or os.path.join(REPORTS, f"GATE-1-sepolia-play-{started:%Y-%m-%d}-{name}.json")
        for target in (out, os.path.splitext(out)[0] + ".md"):
            if os.path.exists(target):
                log.die(f"{os.path.basename(target)} exists: a record is never overwritten")
        nonce = int(node.rpc("starknet_getNonce", {"block_id": "latest", "contract_address": address}), 16)
        log.say(f"STARKNET_ACCOUNT_ADDRESS: nonce {nonce}")
        sd.import_account(node, url, address, key, logs, args.account_type)

        play = Play(node, log, contracts, args.chunks)
        play.version = node.view("persistent", contracts["registry"], "content_version")[0]
        stopped, final = None, None
        try:
            play.create()
            play.enter(GATE_IN)
            others = play.cross()
            log.say(f"crossed chunks {others} besides the entry one")
            play.back(anchor)
            play.leave(GATE_OUT)
            hub, inside = play.place()
            placement = node.view("ephemeral", contracts["instances"], "placement", play.adventurer)
            if inside or placement[2] or hub != gates["out"]["destination"]:
                raise Stopped(f"after the leave: hub {hub}, inside {inside}, placement {placement}")
            final = {"kind": "hub", "location": hub}
            log.say(f"the hub is reached: adventurer {play.adventurer} in location {hub}")
        except (Stopped, RuntimeError) as error:
            stopped = str(redact(error))
            log.say(f"stopped: {stopped}", error=True)
        transactions, total = fees(node, play.steps)
        finished = datetime.datetime.now(datetime.timezone.utc)
        record = {
            "gate": "GATE-1 (D-308)", "network": "Starknet Sepolia" if not args.devnet else "devnet",
            "devnet": args.devnet, "chain_id": chain,
            "deployment": {"name": name, "commit": dep.get("commit", "unknown"), "contracts": contracts},
            "script_commit": dd.commit(), "tools": {"sncast": sncast_version},
            "completed": stopped is None, **({"stopped": stopped} if stopped else {}),
            "adventurer_id": play.adventurer, "instance_id": play.instance,
            "gates": {k: {"id": g, **v} for (k, v), g in zip(gates.items(), (GATE_IN, GATE_OUT))},
            "chunks_crossed": play.crossed, "final_location": final, "hits": play.hits,
            "transactions": transactions, "total_fee": total,
            "started": started.isoformat(timespec="seconds"), "finished": finished.isoformat(timespec="seconds"),
            "seconds": round((finished - started).total_seconds()),
        }
        text, markdown = json.dumps(record, indent=2) + "\n", summary(record)
        # The redactor is the check: the record must come out of it unchanged (as sepolia_deploy.py's)
        if redact(text) != text or redact(markdown) != markdown:
            raise RuntimeError("the record would hold the value of a STARKNET_* variable: not written")
        write_new(out, text)
        write_new(os.path.splitext(out)[0] + ".md", markdown)
        log.say(f"{len(transactions)} transactions, total fee {total['amount']} {total['unit']}; record "
                f"{os.path.basename(out)}")
        return 0 if stopped is None else 1
    finally:
        shutil.rmtree(logs, ignore_errors=True)


def main(argv, environ=os.environ):
    args = parse(argv)
    for number in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(number, sd.terminate)
    redact = sd.Redactor(environ)
    log = sd.Log(redact, os.path.join(environ.get("WITH_NODE_LOG_DIR", os.path.join(os.getcwd(), ".with-node")),
                                      "sepolia-play.log"), name=NAME)
    try:
        return run(args, log, redact, environ)
    except SystemExit:
        raise
    except BaseException as error:  # an echo of the URL or the address is redacted before it is shown
        log.say(f"failed: {type(error).__name__}: {error}", error=True)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
