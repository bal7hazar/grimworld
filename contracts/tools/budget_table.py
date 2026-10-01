#!/usr/bin/env python3
"""ENG-01: the write set and the budget of every entrypoint, derived from physical keys
(docs/architecture/ENG-01-interfaces.md §9.3, §10, §10.1). ENG-01b: F-2, F-3, F-4 of the final audit,
the content version (D-141, E-5), and D-141's rules of a batch (E-1, E-16, E-21).

Every write is a **physical key** with an identity (a tuple: the storage variable and its keys, the
word of a multi-slot record), and a **rule**:
  first   new if the key was never written (cold), overwritten once it was (initialised);
  warm    written only when the slot is initialised (a roster page a swap removal reaches holds
          entries, so it exists); absent from the cold case;
  new     new every time (a new entity, lot, trade id, the first modifiers of an item);
  old     overwritten every time (the key exists by construction: counters written at deployment,
          the instance's header after `create`, a page that holds what is being spent).
A **branch** (completion, interruption, refusal, defeat, objective) is the union of the keys its
parts write, **deduplicated by identity**: a key written by two parts of one transaction is paid
once (FND-04). If two parts give one key different rules, `new` wins over `first` over `old`. Every
count is then derived from the set; a row's target is the maximum over its branches.

    L2 = F + computation + C × calls + 5,120 × calldata felts + events + N × new + O × overwritten

Prices:
  F = 816,939  floor of a burner transaction (cost-budget.md §1, D): it holds the signature and one
               call's header (4 felts); the **arguments** are counted here, 5,120 a felt (FND-04, M)
  N = 453,524  a new slot (FND-04, M);  O = 32,072 an overwritten one (FND-04, M)
  C = 136,000  a call between our contracts: 117,910 in snforge (M, CallProbe) × 1.157 (E)
  event = 1.157 × (23,356 + 5,564 × felts), felts = keys (selector included) + data: a line through
          the two measured shapes of EventProbe (snforge, M: ChunkRevealed 3 felts 40,048; GoblinKilled
          6 felts 56,740), × SPK-1's Sepolia ratio (E). Every event is priced from its frozen shape.
Computation figures are estimates (E), named with each branch.

    python3 contracts/tools/budget_table.py            §10's table, §10.1 and the checks
    python3 contracts/tools/budget_table.py --keys     §9.3's key sets, branch by branch
"""
import math
import sys

F, N, O, C, FELT = 816_939, 453_524, 32_072, 136_000, 5_120
TICK_ACTION_CALLDATA = 5  # instance, adventurer, sequence, content version (D-141), tile
PLAY_CALLDATA = 5  # instance, adventurer, sequence, content version (D-141, E-5), actions
TICK_ALONE, TICK_SHARED = 3_564_913, 1_705_764
CLASS_BOUND = 58_000_000  # the cold bound of an unsplittable action (E-21)
WINDOW_LOW, WINDOW_HIGH = 65_224, 720_000
GENERATION = 450_000  # a chunk's generation, the high end of SPK-7's 0.39-0.45 M (M)
RATIO = 1.157

# Frozen event shapes: keys (selector included) + data felts (contracts/*/src/events.cairo).
EVENT_FELTS = {
    "InstanceEntered": 2 + 3, "BatchPlayed": 2 + 7, "Refused": 2 + 4, "InstanceClosed": 2 + 1,
    "GoblinKilled": 2 + 4, "ChunkRevealed": 2 + 1, "Defeated": 2 + 1,
    "AdventurerLocated": 2 + 1, "TitleDisplayed": 2 + 2, "TrialPassed": 2 + 2,
    "DungeonCleared": 2 + 1, "RankReached": 2 + 1,
    "LotPosted": 3 + 5, "LotClosed": 2 + 1, "TradeOpened": 2 + 2, "TradeClosed": 2 + 1,
}


def event_gas(name):
    return round(RATIO * (23_356 + 5_564 * EVENT_FELTS[name]))


# Precedence when two parts of one transaction write the same key: a key always new stays new; a
# key that exists by construction (`old`) cannot be new; `warm` keys exist only when the slot is
# initialised (a page a swap removal reaches holds entries, so it was written before) and are absent
# from the cold count.
RANK = {"warm": 0, "first": 1, "old": 2, "new": 3}


class Keys:
    """A set of physical keys with their rules, unioned by identity."""

    def __init__(self):
        self.rules = {}

    def add(self, key, rule="first"):
        old = self.rules.get(key)
        if old is None or RANK[rule] > RANK[old]:
            self.rules[key] = rule
        return self

    def many(self, keys, rule="first"):
        for key in keys:
            self.add(key, rule)
        return self

    def union(self, other):
        for key, rule in other.rules.items():
            self.add(key, rule)
        return self

    def counts(self, cold):
        rules = [r for r in self.rules.values() if not (cold and r == "warm")]
        new = sum(1 for r in rules if r == "new" or (cold and r == "first"))
        return new, len(rules) - new

    def families(self):
        fam = {}
        for key, rule in self.rules.items():
            name = key[0]
            count, rules = fam.get(name, (0, set()))
            fam[name] = (count + 1, rules | {rule})
        return fam


class Branch:
    def __init__(self, name, compute, calls, calldata, events, keys, basis=""):
        self.name, self.compute, self.calls, self.calldata = name, compute, calls, calldata
        self.events, self.keys, self.basis = events, keys, basis

    def gas(self, cold):
        new, old = self.keys.counts(cold)
        ev = sum(event_gas(e) * n for e, n in self.events.items())
        return (F + self.compute + C * len(self.calls) + FELT * self.calldata + ev + N * new + O * old)


# ---- key builders (identities) --------------------------------------------------------------
ADV, ACCT, OTHER_ADV, OTHER_ACCT = "adv", "acct", "adv2", "acct2"


def instance_head():
    return [("I.header",), ("I.entropy",)]


def member_transient(m=0):
    return [("I.member", m, w) for w in ("state", "timers", "effects", "recharges")]


def world(goblins, feature_chunks, cold_roster_appends, roster_removals):
    """The instance's writes of some ticks: `goblins` distinct goblin records (2 words each),
    `feature_chunks` chunk features (alerts, used objects), the member's transient words, the
    header and entropy, and the roster: appends write the last page (first used when cold), a swap
    removal writes the hole's page and the last page."""
    k = Keys()
    for g in range(goblins):
        k.add(("I.goblin", g, "state"), "first").add(("I.goblin", g, "timers"), "first")
    for c in range(feature_chunks):
        k.add(("I.chunk", c, "features"), "old")
    k.many(member_transient(), "old").many(instance_head(), "old")
    for p in range(math.ceil(cold_roster_appends / 15)):
        k.add(("I.roster", p), "first")
    if roster_removals:
        for p in range(4):
            k.add(("I.roster", p), "warm")
    return k


def world_one_word(goblins, feature_chunks, cold_roster_appends):
    k = Keys()
    for g in range(goblins):
        k.add(("I.goblin", g, "state"), "first")
    for c in range(feature_chunks):
        k.add(("I.chunk", c, "features"), "old")
    k.many(member_transient(), "old").many(instance_head(), "old")
    for p in range(math.ceil(cold_roster_appends / 15)):
        k.add(("I.roster", p), "first")
    return k


def report_open(quests=4):
    """A report's aggregated results of kills and objectives: experience (core), held quests."""
    k = Keys().add(("H.core", ADV), "old")
    for q in range(quests):
        k.add(("H.quiver", ADV, q), "old")
    return k


def report_objective():
    """A Rift cleared or a dungeon cleared: the account's board, the 'distinct' counter
    (Nestbreaker), with `DungeonCleared`."""
    return Keys().add(("H.board", ACCT), "old").add(("H.counter", ADV, "dungeons"), "first")


def closing(belt_pages=4):
    """The closing report (Returned, Defeated): the placement, the hub's place, the core, the belt
    credited back on distinct pack pages (E-15 option a on defeat)."""
    k = Keys().add(("I.placement", ADV), "old").add(("H.place", ADV), "old").add(("H.core", ADV), "old")
    for p in range(belt_pages):
        k.add(("H.pack_page", ADV, "belt", p), "old")
    return k


def loot_report(items, equipment):
    """Drops to the pack: balance pages (distinct), gold, each equipment item (a new entity and
    the counter), the pack list page it lands on, the core, the Scavenger counter, held quests."""
    k = Keys()
    for i in range(items):
        k.add(("H.pack_page", ADV, "loot", i), "first")
    k.add(("H.gold", ADV), "first")
    for e in range(equipment):
        k.add(("H.item", "drop", e, "base"), "new")
    if equipment:
        k.add(("H.next_item",), "old")
        for p in range(math.ceil(equipment / 7) + 1 if equipment > 1 else 1):
            k.add(("H.pack_list", ADV, p), "first")
    k.add(("H.core", ADV), "old").add(("H.acct_counter", ACCT, "scavenger"), "first")
    return k.union(report_open())


def ev(**counts):
    return {name: n for name, n in counts.items() if n}


ROWS = []


def row(name, *branches):
    ROWS.append((name, list(branches)))


# ---- Instances + the hub's side -------------------------------------------------------------
def create_keys(tasks=16, first_entry=True):
    """A first entry writes every key for the first time; a later entry finds the slot's keys
    written: only its entry chunk index and task pages beyond those used before can be new."""
    slot_rule = "first" if first_entry else "old"
    k = Keys()
    k.many([("I.placement", ADV), ("I.header",), ("I.entropy",), ("I.revealed",), ("I.quotas",)], slot_rule)
    for w in ("state", "timers", "effects", "recharges", "stats", "bar", "kit", "controller"):
        k.add(("I.member", 0, w), slot_rule)
    k.add(("I.chunk", "entry", "terrain"), "first").add(("I.chunk", "entry", "features"), "first")
    for p in range(math.ceil(tasks / 4)):
        k.add(("I.task", p), "first")
    if first_entry:
        k.add(("I.next_slot",), "old")
    k.add(("H.place", ADV), "old").add(("H.core", ADV), "old")
    for p in range(4):
        k.add(("H.pack_page", ADV, "belt", p), "old")
    return k


row("`enter` (with `create`), first entry of the adventurer",
    Branch("entered", 1_450_000, ["instances", "registry(hub)", "registry", "fate"], 2,
           ev(InstanceEntered=1, AdventurerLocated=1), create_keys(first_entry=True),
           "checks, snapshot, entry draw, the first chunk's generation"),
    Branch("refused (a gate's requirement)", 300_000, ["registry(hub)"], 2, {}, Keys(), "a revert: nothing written"))
row("`enter`, a later entry",
    Branch("entered", 1_450_000, ["instances", "registry(hub)", "registry", "fate"], 2,
           ev(InstanceEntered=1, AdventurerLocated=1), create_keys(first_entry=False), ""))
RIFT_BOARD = Keys().add(("H.board", ACCT), "first")
RIFT_CALLS = ["instances", "registry(hub)", "registry", "fate", "fate(board)"]
RIFT_EVENTS = ev(InstanceEntered=1, AdventurerLocated=1)
row("`enter_rift`, either entry: the adventurer's first (a Rift can be its first instance, F-4) or a later one",
    Branch("entered, first entry of the adventurer", 1_550_000, RIFT_CALLS, 2, RIFT_EVENTS,
           create_keys(first_entry=True).union(RIFT_BOARD), "`enter` + the board's draw; the first instance slot, `I.next_slot`"),
    Branch("entered, later entry", 1_550_000, RIFT_CALLS, 2, RIFT_EVENTS,
           create_keys(first_entry=False).union(RIFT_BOARD), "`enter` + the board's draw"))
row("`enter_rift`, later entry alone, the day's first board action",
    Branch("entered", 1_550_000, RIFT_CALLS, 2, RIFT_EVENTS,
           create_keys(first_entry=False).union(RIFT_BOARD), "kept apart from the selector's maximum (F-4)"))


def leave_to_hub():
    k = Keys().many([("I.header",), ("I.member", 0, "state")], "old").union(closing())
    return Branch("returned", 600_000, ["hub"], 4, ev(InstanceClosed=1, AdventurerLocated=1), k)


row("`leave`, `travel_back` to a hub", leave_to_hub(),
    Branch("refused (sequence, gate, sealed)", 150_000, [], 4, ev(Refused=1), Keys(), "changes nothing"))


def gate_keys():
    k = Keys().many([("I.placement", ADV), ("I.header",), ("I.entropy",), ("I.revealed",), ("I.quotas",)], "old")
    k.many(member_transient(), "old")
    k.add(("I.chunk", "next-entry", "terrain"), "first").add(("I.chunk", "next-entry", "features"), "first")
    return k.add(("H.place", ADV), "old").add(("H.core", ADV), "old")


row("`leave` through a gate to a location",
    Branch("moved", 1_900_000, ["registry", "fate", "hub"], 4,
           ev(InstanceClosed=1, InstanceEntered=1), gate_keys(), "the next entry draw and generation"))

# loot: 0 ticks; completion or refusal
# The looted goblin's record exists (it died there); its roster entry exists: a swap removal writes
# the hole's page and the last page, both holding entries.
LOOT_INST = Keys().many(instance_head(), "old").add(("I.goblin", 0, "state"), "old").many(
    [("I.roster", 0), ("I.roster", 3)], "old")
row("`loot`",
    Branch("a boss's 3 items", 500_000, ["registry", "fate", "hub"], 4, {},
           Keys().union(LOOT_INST).union(loot_report(3, 3)), "0 world ticks"),
    Branch("ordinary remains", 500_000, ["registry", "fate", "hub"], 4, {},
           Keys().union(LOOT_INST).union(loot_report(2, 0)), ""),
    Branch("refused", 150_000, [], 4, ev(Refused=1), Keys(), "a check fails before the draw: changes nothing"))


def tick_branches(action, extra_inst, completion_report, completion_calls, ticks, goblins, extra_events, compute0,
                  price_refusal=False):
    """A standalone action's branches (F-3): each of completion, interruption or refusal, defeat and a
    quiet completion, alone and **with the objective its ticks can complete** (a burning or poisoned
    Rift Heart dying, a dungeon cleared: the account's board, the 'distinct' counter, `DungeonCleared`);
    a collector's refusal on price is its own branch, with its `Hub.barter` call."""
    tick_compute = compute0 + ticks * (TICK_ALONE + WINDOW_HIGH)
    base = world(goblins, 4, goblins, True).union(extra_inst)
    near = world(goblins, 4, goblins, True).union(report_open())
    kills = ev(GoblinKilled=goblins)
    closed = {"Defeated": 1, "InstanceClosed": 1, "AdventurerLocated": 1}
    quiet = Keys().many(instance_head(), "old").add(("I.member", 0, "state"), "old").union(extra_inst)
    plain = [
        ("completion, goblins near", tick_compute, completion_calls, {**kills, **extra_events},
         Keys().union(base).union(completion_report).union(report_open()),
         f"{ticks} tick(s) as alone and their window; {goblins} goblins (14 a tick); ≤ {goblins} kills (traps)"),
        ("interrupted before its result, goblins near", tick_compute, ["registry", "hub"], {**kills, "Refused": 1},
         near, "the ticks ran; no result of the action itself"),
    ]
    if price_refusal:
        plain.append(("refused on price, goblins near", tick_compute, ["registry", "hub.barter", "hub"],
                      {**kills, "Refused": 1}, near, "the ticks ran; `Hub.barter` found the price absent: nothing exchanged"))
    plain += [
        ("defeat, goblins near", tick_compute, ["registry", "hub"], {**kills, **closed},
         Keys().union(near).union(closing()), "closes: both placements, the belt credited back (E-15 a)"),
        ("completion, no goblin near", compute0 + ticks * 300_000, completion_calls, extra_events,
         Keys().union(quiet).union(completion_report).union(report_open()), "quiet ticks, 0.30 M each"),
    ]
    out = []
    for name, compute, calls, events, keys, basis in plain:
        out.append(Branch(name, compute, calls, TICK_ACTION_CALLDATA, events, keys, basis))
        out.append(Branch(name + ", with the objective", compute, calls, TICK_ACTION_CALLDATA, {**events, "DungeonCleared": 1},
                          Keys().union(keys).union(report_objective()), "and the objective the ticks completed"))
    # A different content version is refused before any tick, like a failed precondition (D-141): the
    # `bundle` call that returns the version, `Refused`, nothing written.
    out.append(Branch("refused, content version differs", 150_000, ["registry"], TICK_ACTION_CALLDATA,
                      ev(Refused=1), Keys(), "before any tick: changes nothing"))
    return out


CHEST = Keys().add(("I.chunk", 0, "features"), "old")
row("`open` (a chest: 1 tick, then a draw)",
    *tick_branches("open", CHEST, loot_report(3, 1), ["registry", "fate", "hub"], 1, 14, {}, 500_000))
VEIN = Keys().add(("I.chunk", 0, "features"), "old")
STONE = Keys().add(("H.pack_page", ADV, "stillstone"), "first").add(("H.core", ADV), "old")
row("`mine` (up to 3 ticks, no draw), its own union",
    *tick_branches("mine", VEIN, STONE, ["registry", "hub"], 3, 42, {}, 200_000))
BARTER = Keys().many([("H.pack_page", ADV, "price", 0), ("H.pack_page", ADV, "price", 1)], "old").add(
    ("H.item", "given", "base"), "new").add(("H.next_item",), "old").add(("H.pack_list", ADV, 0), "first").add(
    ("H.core", ADV), "old")
row("`barter` (1 tick, then the hub's exchange)",
    *tick_branches("barter", Keys(), BARTER, ["registry", "hub.barter", "hub"], 1, 14, {}, 400_000, price_refusal=True))

# ---- play: a batch ------------------------------------------------------------------------------
def batch(goblins, one_word=False, reveals=0, features=9, goblin_rule="first"):
    """A batch's instance writes. Chunks have **one physical identity per word**, whether a reveal or a
    tick writes it (F-2): the batch's chunks are the `features` of the union of the windows (at most
    9), a `reveals` of them revealed by this batch (their `terrain` and `features` words start the
    transaction unwritten: `first`), the others existing (`features`: `old`). `goblin_rule` is the
    goblins' classification at the start: `old` for the gas-maximising batch of E-1's weight (the
    branch with n first records is scanned in `checks()`, where n new records cost n ticks), `first`
    for the single action that runs whatever it changes (E-21)."""
    if one_word:
        k = world_one_word(goblins, 0, goblins)
    else:
        k = world(goblins, 0, goblins, True)
    if goblin_rule != "first":
        for key in list(k.rules):
            if key[0] == "I.goblin":
                k.rules[key] = goblin_rule
    for c in range(features):
        k.add(("I.chunk", c, "features"), "first" if c < reveals else "old")
    for c in range(reveals):
        k.add(("I.chunk", c, "terrain"), "first")
    if reveals:
        k.many([("I.revealed",), ("I.quotas",)], "old")
    return k.union(report_open())


def play_branches(goblins, ticks=10, tick=TICK_ALONE, window=WINDOW_HIGH, one_word=False, label="", reveals=0,
                  goblin_rule="first", single=False):
    """Open, objective, defeat, and objective then defeat, each the union of its parts. A single
    action does not move the window (4 chunks); a batch of 10 moves spans the union of 9. With
    `reveals`, 4 chunks are revealed by 2 ticks of the weight (E-12: a reveal weighs 2)."""
    features = 4 if single else 9
    compute = ticks * (tick + window) + reveals * GENERATION
    events = {"BatchPlayed": 1, "GoblinKilled": goblins}
    if reveals:
        events["ChunkRevealed"] = reveals

    def body():
        return batch(goblins, one_word, reveals=reveals, features=features, goblin_rule=goblin_rule)

    closed = {"Defeated": 1, "InstanceClosed": 1, "AdventurerLocated": 1}
    return [
        Branch(f"open{label}", compute, ["registry", "hub"], PLAY_CALLDATA, events, body()),
        Branch(f"objective (a Rift or a dungeon cleared){label}", compute, ["registry", "hub"], PLAY_CALLDATA,
               {**events, "DungeonCleared": 1}, body().union(report_objective())),
        Branch(f"defeat{label}", compute, ["registry", "hub"], PLAY_CALLDATA, {**events, **closed},
               body().union(closing())),
        Branch(f"objective and defeat{label}", compute, ["registry", "hub"], PLAY_CALLDATA,
               {**events, "DungeonCleared": 1, **closed}, body().union(report_objective()).union(closing())),
    ]


# The weighted batch (E-16, E-1): goblin records already written (`old`); the first-record weight is
# what makes the gas maximum the batch with none new; the batch with the most new keys is another
# (five ticks, five first records, scanned in `checks()`).
PLAY_CAPPED = play_branches(16, goblin_rule="old")
PLAY_REVEALS = play_branches(16, ticks=2, reveals=4, label=", 4 reveals, 2 ticks", goblin_rule="old")
row("`play`, weight 10, the cap of 16 goblins (E-16), first records weighed (E-1), ticks as alone",
    *PLAY_CAPPED, *PLAY_REVEALS)
row("`play`, one 3-tick action alone, 42 goblins (E-21)", *play_branches(42, ticks=3, single=True))
row("`play`, one 3-tick action alone, 42 goblins, one word per goblin (E-1 b, not adopted)",
    *play_branches(42, ticks=3, one_word=True, single=True))

# ---- Hub --------------------------------------------------------------------------------------
def B(name, compute, calls, calldata, events, keys, basis=""):
    return Branch(name, compute, calls, calldata, events, keys, basis)


row("`register`", B("registered", 200_000, [], 0, {}, Keys().many(
    [("H.account_of", "me"), ("H.account", ACCT, "owner"), ("H.account", ACCT, "record")], "new").add(("H.next_account",), "old")))
row("`set_account_owner`, 7 adventurers inside", B("changed", 200_000, ["instances"] * 7, 2, {}, Keys()
    .add(("H.account", ACCT, "owner"), "old").add(("H.account_of", "old owner"), "old").add(("H.account_of", "new owner"), "new")
    .many([("I.member", f"slot{i}", "controller") for i in range(7)], "old"), "E-19"))
row("`create_adventurer`", B("created", 300_000, ["registry"], 2, {}, Keys()
    .many([("H.adventurer", "new", w) for w in ("core", "place", "build", "belt", "equipped", "name")], "new")
    .many([("H.next_adventurer",), ("H.account", ACCT, "record")], "old").add(("H.acct_list", ACCT, 0), "first")))
row("`delete_adventurer`", B("deleted", 200_000, [], 1, {}, Keys()
    .many([("H.core", ADV), ("H.account", ACCT, "record"), ("H.acct_list", ACCT, 0), ("H.acct_list", ACCT, 1)], "old"),
    "a swap removal: the hole's page, the last page"))
row("`set_build`", B("set", 300_000, ["registry"], 4, {}, Keys().many(
    [("H.build", ADV), ("H.belt", ADV), ("H.equipped", ADV)], "old")))
row("`travel`", B("travelled", 100_000, [], 2, ev(AdventurerLocated=1), Keys().add(("H.place", ADV), "old")))
row("`display_title`", B("displayed", 50_000, [], 3, ev(TitleDisplayed=1), Keys(), "event only (T-1)"))
row("`accept_quest`", B("accepted", 400_000, ["registry"], 2, {}, Keys().add(("H.quiver", ADV, 0), "first")
    .add(("H.known", ADV, 0), "first"), "skills given at acceptance"))
row("`abandon_quest`", B("abandoned", 300_000, [], 2, {}, Keys().add(("H.quiver", ADV, 0), "old")))
row("`accept_contract`", B("accepted", 300_000, ["registry"], 2, {}, Keys().add(("H.quiver", ADV, 3), "first")))
row("`claim_quest`", B("claimed, a trial promoting", 600_000, ["registry"], 2, ev(TrialPassed=1, RankReached=1), Keys()
    .add(("H.core", ADV), "old").many([("H.gold", ADV), ("H.pack_page", ADV, "reward"), ("H.pack_list", ADV, 0),
                                        ("H.known", ADV, 0), ("H.counter", ADV, "quests")], "first")
    .add(("H.item", "reward", "base"), "new").many([("H.next_item",), ("H.quiver", ADV, 0), ("H.quiver", ADV, 1)], "old")))
row("`claim_title`", B("claimed", 400_000, [], 2, {}, Keys().add(("H.quiver", ADV, "claim"), "new")))
row("`buy_skill`", B("bought", 200_000, ["registry"], 2, {}, Keys().add(("H.known", ADV, 0), "first").add(("H.gold", ADV), "old")))
row("`buy`", B("equipment", 300_000, ["registry"], 4, {}, Keys().add(("H.item", "bought", "base"), "new")
    .add(("H.pack_list", ADV, 0), "first").many([("H.gold", ADV), ("H.next_item",), ("H.core", ADV)], "old")),
    B("a balance", 300_000, ["registry"], 4, {}, Keys().add(("H.pack_page", ADV, "bought"), "first")
      .many([("H.gold", ADV), ("H.core", ADV)], "old")))
row("`sell`", B("equipment", 300_000, ["registry"], 4, {}, Keys().add(("H.gold", ADV), "first").many(
    [("H.item", "sold", "base"), ("H.pack_list", ADV, 0), ("H.pack_list", ADV, 3), ("H.core", ADV)], "old")))
row("`craft`", B("crafted", 300_000, ["registry"], 3, {}, Keys().add(("H.item", "crafted", "base"), "new")
    .add(("H.pack_list", ADV, 0), "first").many([("H.pack_page", ADV, "iron"), ("H.pack_page", ADV, "hide"),
                                                  ("H.gold", ADV), ("H.next_item",), ("H.core", ADV)], "old")))
row("`recycle`", B("recycled", 300_000, ["registry"], 2, {}, Keys().many(
    [("H.item", "recycled", "base"), ("H.pack_list", ADV, 0), ("H.pack_list", ADV, 3), ("H.core", ADV)], "old")
    .many([("H.pack_page", ADV, "iron"), ("H.pack_page", ADV, "hide")], "first")))
row("`personalise`", B("personalised", 300_000, ["registry"], 2, {}, Keys().many(
    [("H.item", "mine", "base"), ("H.pack_page", ADV, "stillstone"), ("H.gold", ADV), ("H.core", ADV)], "old"),
    "the last stone: `pack_lanes`"))
row("`identify`", B("identified", 350_000, ["registry", "fate"], 2, {}, Keys().add(("H.item", "mine", "mods"), "new")
    .many([("H.item", "mine", "base"), ("H.gold", ADV)], "old")))
row("`lift_modifier`",
    B("with a stone", 350_000, ["registry"], 4, {}, Keys().many([("H.item", "comp", "base"), ("H.item", "comp", "mods")], "new")
      .add(("H.pack_list", ADV, 3), "first").many([("H.item", "mine", "mods"), ("H.next_item",),
                                                    ("H.pack_page", ADV, "stillstone"), ("H.core", ADV), ("H.gold", ADV)], "old")),
    B("without, the item survives", 350_000, ["registry", "fate"], 4, {}, Keys()
      .many([("H.item", "comp", "base"), ("H.item", "comp", "mods")], "new").add(("H.pack_list", ADV, 3), "first")
      .many([("H.item", "mine", "mods"), ("H.next_item",), ("H.gold", ADV)], "old")),
    B("without, the item destroyed", 350_000, ["registry", "fate"], 4, {}, Keys()
      .many([("H.item", "comp", "base"), ("H.item", "comp", "mods")], "new")
      .many([("H.item", "mine", "base"), ("H.pack_list", ADV, 0), ("H.pack_list", ADV, 3), ("H.next_item",),
             ("H.gold", ADV)], "old"), "the component takes the item's lane"))
row("`set_modifier`, with a stone", B("set", 350_000, ["registry"], 4, {}, Keys()
    .many([("H.item", "comp2", "base"), ("H.item", "comp2", "mods")], "new")
    .many([("H.item", "mine", "mods"), ("H.item", "comp", "base"), ("H.pack_list", ADV, 0), ("H.pack_list", ADV, 3),
           ("H.next_item",), ("H.pack_page", ADV, "stillstone"), ("H.core", ADV), ("H.gold", ADV)], "old")))
row("`brew`", B("a new pair", 500_000, ["registry", "fate"], 3, {}, Keys()
    .many([("H.grimoire", ADV, "state"), ("H.grimoire", ADV, "pairs"), ("H.pack_page", ADV, "potion")], "first")
    .many([("H.pack_page", ADV, "ing0"), ("H.pack_page", ADV, "ing1"), ("H.core", ADV)], "old")))
row("`buy_hint`", B("bought", 350_000, ["registry", "fate"], 2, {}, Keys().add(("H.grimoire", ADV, "state"), "first")
    .many([("H.pack_page", ADV, "stillstone"), ("H.core", ADV)], "old"), "the book's first hint: its state may be new"))


def stow(to_vault):
    k = Keys()
    for i in range(8):
        k.add(("H.item", "stowed", i, "base"), "old")
        k.add(("H.pack_page", ADV, "stow", i), "old" if to_vault else "first")
        k.add(("H.vault_page", ACCT, "stow", i), "first" if to_vault else "old")
    if to_vault:
        k.many([("H.pack_list", ADV, p) for p in range(4)], "old")
        k.many([("H.vault_list", ACCT, p) for p in range(2)], "first")
        k.add(("H.gold", ADV), "old").add(("H.gold", ACCT), "first")
    else:
        k.many([("H.vault_list", ACCT, p) for p in range(10)], "old")  # 8 holes + the tail's 2
        k.many([("H.pack_list", ADV, p) for p in range(2)], "first")
        k.add(("H.gold", ACCT), "old").add(("H.gold", ADV), "first")
    return k.add(("H.core", ADV), "old")


row("`stow` (8 entities, 8 balances)", B("to the vault", 400_000, [], 29, {}, stow(True)),
    B("to the pack", 400_000, [], 29, {}, stow(False)))

# ---- Market -------------------------------------------------------------------------------------
row("`post_lot` (the account's 4th lot)",
    B("a balance", 300_000, ["hub.seller", "hub.escrow", "hub.gold", "registry"], 5, ev(LotPosted=1), Keys()
      .add(("M.lot", "new"), "new").add(("M.seller", ACCT, 1), "first").add(("H.escrow_page", "item"), "first")
      .many([("M.lot_count",), ("M.open_lot_count",), ("M.seller", ACCT, 0), ("H.pack_page", ADV, "sold"),
             ("H.gold", ACCT), ("H.account", ACCT, "record"), ("H.core", ADV)], "old")),
    B("equipment", 300_000, ["hub.seller", "hub.escrow", "hub.gold", "registry"], 5, ev(LotPosted=1), Keys()
      .add(("M.lot", "new"), "new").add(("M.seller", ACCT, 1), "first")
      .many([("M.lot_count",), ("M.open_lot_count",), ("M.seller", ACCT, 0), ("H.item", "sold", "base"),
             ("H.pack_list", ADV, 0), ("H.pack_list", ADV, 3), ("H.gold", ACCT), ("H.account", ACCT, "record")], "old")))
row("`buy_lot`", B("bought", 300_000, ["hub.seller", "hub.gold", "hub.release"], 3, ev(LotClosed=1), Keys()
    .many([("H.gold", OTHER_ACCT), ("H.vault_page", ACCT, "bought")], "first")
    .many([("M.lot", "x"), ("M.open_lot_count",), ("M.seller", OTHER_ACCT, 0), ("M.seller", OTHER_ACCT, 1),
           ("M.seller", OTHER_ACCT, 2), ("H.gold", ACCT), ("H.escrow_page", "item"), ("H.account", OTHER_ACCT, "record")], "old"),
    "a swap removal in the seller's pages: the hole's, the last, page 0's count"))
row("`withdraw_lot`, `return_lot`", B("returned", 300_000, ["hub.seller", "hub.release"], 2, ev(LotClosed=1), Keys()
    .add(("H.vault_page", ACCT, "returned"), "first")
    .many([("M.lot", "x"), ("M.open_lot_count",), ("M.seller", ACCT, 0), ("M.seller", ACCT, 1), ("M.seller", ACCT, 2),
           ("H.escrow_page", "item"), ("H.account", ACCT, "record")], "old")))
row("`open_trade`", B("opened", 300_000, ["hub.seller"], 2, ev(TradeOpened=1), Keys()
    .add(("M.trade", "new", "head"), "new").add(("M.trade_count",), "old")))
row("`set_trade_side`", B("set", 200_000, ["hub.seller"], 4, {}, Keys()
    .many([("M.trade", "t", "goods"), ("M.trade", "t", "money")], "first").add(("M.trade", "t", "head"), "old")))


def swap():
    k = Keys().add(("M.trade", "t", "head"), "old")
    for side, other in ((ADV, OTHER_ADV), (OTHER_ADV, ADV)):
        for i in range(7):
            k.add(("H.item", side, "traded", i, "base"), "old")
        # each pack's list: 7 removals and 7 appends lie in its own 4 pages, a union of 4 a pack
        # (8 physical pages for the trade): the pages holding the given items exist; the last one
        # may be opened by the received items
        for p in range(3):
            k.add(("H.pack_list", side, p), "old")
        k.add(("H.pack_list", side, 3), "first")
        for b in range(2):
            k.add(("H.pack_page", side, "given", b), "old")
            k.add(("H.pack_page", side, "received", b), "first")
        k.add(("H.gold", side), "first").add(("H.core", side), "old")
    return k


row("`confirm_trade`", B("the swap (7 + 7 items, 2 + 2 balances, gold)", 800_000, ["hub.seller", "hub.exchange"], 3,
                         ev(TradeClosed=1), swap(), "the pack lists: a union of at most 8 physical pages"),
    B("the first confirmation", 100_000, ["hub.seller"], 3, {}, Keys().add(("M.trade", "t", "head"), "old")))
row("`decline_trade`, `cancel_trade`", B("closed", 100_000, ["hub.seller"], 2, ev(TradeClosed=1),
                                         Keys().add(("M.trade", "t", "head"), "old")))
row("`Registry.set_record` (3 parts)", B("written", 50_000, [], 6, {}, Keys()
    .many([("R.record", p) for p in range(3)], "first").add(("R.last_id", "kind"), "first")
    .add(("R.versions",), "first"), "the content version rises by one (D-141, E-5), the inputs version with it in the same slot for a rewritten input of the flattening (D-169): 0 at deployment, so its first write is new"))
row("admin setters, `upgrade`", B("set", 100_000, [], 4, {}, Keys().many([("A.address", i) for i in range(4)], "old")))


# ---- output --------------------------------------------------------------------------------------
def worst(branches, cold):
    return max(branches, key=lambda b: b.gas(cold))


def keys_table():
    print("| Entrypoint | Branch | Key families (count; `first`: new when cold; `new`: always; `old`: never) | Cold N / O | Initialised N / O | Calldata felts | Events |")
    print("|---|---|---|---|---|---:|---|")
    for name, branches in ROWS:
        for b in branches:
            fams = "; ".join(f"`{f}` {c} ({'/'.join(sorted(r))})" for f, (c, r) in sorted(b.keys.families().items())) or "none"
            evs = ", ".join(f"{e} ×{n}" for e, n in b.events.items()) or "—"
            cn, co = b.keys.counts(True)
            inn, io = b.keys.counts(False)
            print(f"| {name} | {b.name} | {fams} | {cn} / {co} | {inn} / {io} | {b.calldata} | {evs} |")


def budget_table():
    print("| Entrypoint | Worst branch | Calls | Calldata | Events gas | Initialised: N / O → **L2** | Cold: N / O → **L2** |")
    print("|---|---|---:|---:|---:|---|---|")
    for name, branches in ROWS:
        wi, wc = worst(branches, False), worst(branches, True)
        ev_gas = sum(event_gas(e) * n for e, n in wc.events.items())
        inn, io = wi.keys.counts(False)
        cn, co = wc.keys.counts(True)
        label = wc.name if wc is wi else f"{wi.name} / {wc.name}"
        print(f"| {name} | {label} | {len(wc.calls)} | {wc.calldata} | {ev_gas:,} | {inn} / {io} → **{wi.gas(False):,}** "
              f"| {cn} / {co} → **{wc.gas(True):,}** |")


def batch_branch(br, new_records):
    """`br` with its first `new_records` goblin records written for the first time in the slot."""
    k = Keys().union(br.keys)
    for g in range(new_records):
        k.add(("I.goblin", g, "state"), "new").add(("I.goblin", g, "timers"), "new")
    return Branch(br.name, br.compute, br.calls, br.calldata, br.events, k)


def checks():
    print("\nEvent prices from their shapes (E):")
    for e in sorted(EVENT_FELTS):
        print(f"  {e}: {EVENT_FELTS[e]} felts, {event_gas(e):,}")
    capped = PLAY_CAPPED + PLAY_REVEALS
    print("\n§10.1, a batch with the cap (16 goblins), branch by branch:")
    for b in capped:
        print(f"  {b.name}: keys {len(b.keys.rules)}; initialised {b.keys.counts(False)} → {b.gas(False):,}; "
              f"cold {b.keys.counts(True)} → {b.gas(True):,}")
    for label, tick in (("shared", TICK_SHARED),):
        low = play_branches(16, tick=tick, window=WINDOW_LOW, goblin_rule="old")
        high = play_branches(16, tick=tick, window=WINDOW_HIGH, goblin_rule="old")
        print(f"  ticks {label}: {max(b.gas(False) for b in low):,} to {max(b.gas(False) for b in high):,}")
    low = play_branches(16, window=WINDOW_LOW, goblin_rule="old")
    print(f"  ticks alone, the window at its low end: {max(b.gas(False) for b in low):,}")
    b16 = batch(16, goblin_rule="old")
    b24 = batch(24, goblin_rule="old")
    print(f"  cap 24 instead of 16: +{(len(b24.rules) - len(b16.rules)) * O:,} ({len(b24.rules) - len(b16.rules)} more keys overwritten)")

    # The slot bound, from the key sets alone (F-2): the most distinct keys any branch of a capped batch
    # writes, whatever it costs; the branch that costs the most is another one.
    most = max(capped, key=lambda b: len(b.keys.rules))
    top = max(capped, key=lambda b: b.gas(False))
    print(f"\nSlot bound, from the key sets: at most {len(most.keys.rules)} keys, in '{most.name}' "
          f"(initialised {most.gas(False):,}); the gas maximum is '{top.name}' "
          f"({len(top.keys.rules)} keys, {top.gas(False):,})")
    chunk_keys = sum(1 for k in most.keys.rules if k[0] == "I.chunk")
    print(f"  chunk keys of that branch: {chunk_keys} = 9 features words (a revealed chunk's is one of them) "
          f"+ 4 terrain words")

    # E-1: a goblin record written for the first time weighs 1 more, so a batch of weight 10 with n such
    # records runs 10 - n ticks. The worst branch as n grows, cold (every `first` key new).
    print("\nE-1, first records weighed: the worst branch of a batch of 16 goblins, n of them new, 10 - n ticks:")
    before = max(play_branches(16), key=lambda b: b.gas(True))
    print(f"  no weight (before D-141): {before.name}, cold {before.gas(True):,}")
    for n in range(10):
        branches = [batch_branch(br, n) for br in play_branches(16, ticks=10 - n, goblin_rule="old")]
        w = max(branches, key=lambda b: b.gas(True))
        print(f"  n = {n}: {w.name}: keys {len(w.keys.rules)}, cold {w.keys.counts(True)} → {w.gas(True):,}")

    # E-21: the class of an action that cannot be split has its own bound.
    unsplittable = [b for name, brs in ROWS if name.startswith("`mine`") or "one 3-tick action alone, 42 goblins (E-21)" in name
                    for b in brs]
    cold = max(b.gas(True) for b in unsplittable)
    print(f"\nE-21, the unsplittable class (3-tick action among 42 goblins, `mine`): cold maximum {cold:,} "
          f"against {CLASS_BOUND:,} → {'holds' if cold <= CLASS_BOUND else 'EXCEEDED'}")

    # The audit's figure for the one-word alternative, reproduced under fix loop 2's model: 42 goblin
    # words + 3 roster pages new, 16 other (the 4th roster page counted), events 42 × 65,648 + 2 × 46,336.
    old_model = F + 3 * (TICK_ALONE + WINDOW_HIGH) + 2 * C + 45 * N + 16 * O + 42 * 65_648 + 2 * 46_336
    print(f"\nthe audit's one-word figure under fix loop 2's model: {old_model:,} (61 keys: 45 new, 16 other)")
    one = play_branches(42, ticks=3, one_word=True, single=True)
    for b in one:
        print(f"  one word per goblin, {b.name}: keys {len(b.keys.rules)}; cold {b.keys.counts(True)} → {b.gas(True):,}")


def main():
    if "--keys" in sys.argv:
        keys_table()
        return
    budget_table()
    checks()


if __name__ == "__main__":
    main()
