# ENG-01 — The core interfaces, frozen under a cost budget

| | |
|---|---|
| Status | Frozen by ENG-01 (2026-09-29), `[Opus 5.5]`. **Fix loop 1** after the `[GPT-6-Astra]` audit (FAIL, 6 majors): the belt's reserve (§6), per-batch and lifetime bounds (§9.1–9.2), the standalone actions by their behaviour (§4.1), every selector's complete write set, cold and initialised (§9.3), the per-action events restored (§5), remains through the roster (§9.3), registry allocation (§3.5), bounded deadlines and packers (§3.1), a validating encoder (§4.1). **Fix loop 2** after the re-audit: every generation-changing path initialises the member's transient words (§2.1, F-12); roster pages masked, not rewritten (§2.1, §4.1, F-13); per-invocation unions with compact lists and the unsplittable action (§9.2, E-21); the standalone actions' own unions (§9.3, E-8); every key set re-enumerated and every gas figure computed from it by `contracts/tools/budget_table.py` (§9.3, §10); the views' reads (§9.3); effective durations bounded after modifiers (§3.1). The escalations of §11 are open |
| Code | `contracts/`: `grimworld_logic` (shared types, wire formats, calls between contracts), `grimworld_ephemeral` (`Instances`), `grimworld_persistent` (`Hub`, `Market`, `Registry`, `TxHashFate`). Interfaces, storage structs, events and packing compile; every game entrypoint reverts with `'not implemented'` |
| Budgets rest on | [cost-budget.md](cost-budget.md) (FND-04), and one measurement of this task: a reused key (§2) |
| Rules applied | D-129 (a cost budget), D-133 (batches), D-135 (4 held quests), D-131 (16 tasks, one results call per transaction), D-136, ADR-0001, ADR-0002, ADR-0005, ADR-0006, ADR-0007, M-1…M-6, CAIRO.md, the project manager's rule of 2026-09-29 (instance slots are reused) |

Every figure is marked like cost-budget.md: **M** measured (with its source), **D** derived by
arithmetic from measurements, **E** an estimate on a stated assumption.

Prices used everywhere (cost-budget.md §1): the floor of a burner transaction
**F = 816,939** (D); a **new** slot **N = 453,524** (M); an overwritten or zeroed slot
**O = 32,072** (M); a felt of calldata 5,120 (M). A call from one of our contracts to another:
**C ≈ 118,000** in snforge (M, §2.3), about **136,000** on Sepolia (E: × 1.157, SPK-1 §3's
median ratio).

```
L2 gas of a transaction ≈ F + calldata beyond one call's header + computation + C × calls
                          + N × new slots + O × overwritten or zeroed slots
```

---

## 1. Contracts and their boundaries

### 1.1 Five contracts, three packages

| Contract | Package | Domain | Owns | Called by |
|---|---|---|---|---|
| **`Instances`** | `grimworld_ephemeral` | ephemeral | every instance: header, entropy, revealed set, quotas, task snapshot, members (with the snapshot), roster, chunks, goblins; the adventurer's placement | players (play, Fate, gates); `Hub` (create, set_controller) |
| **`Hub`** | `grimworld_persistent` | persistent | accounts, adventurers, known skills, title counters, grimoires, balances, gold, equipment entities, packs, vaults, Rift boards; quiver's quests and achievements (when embedded, ARC) | players (hub actions); `Instances` (results, barter); `Market` (escrow, gold, swaps) |
| **`Market`** | `grimworld_persistent` | persistent | lots, trades, their counters | players |
| **`Registry`** | `grimworld_persistent` | persistent (content) | every registry record, `(kind, id, part)` | everyone reads; the administrator writes |
| **`TxHashFate`** | `grimworld_persistent` | — (the provider) | nothing | `Instances`, `Hub` (`fate(domain)`) |

`grimworld_logic` is not a contract. It holds what both domains share without either package
depending on the other (ADR-0007): identifiers and bounds (`types`), the wire format of a batch
(`actions`), the snapshot and task layouts (`snapshot`), the packing rules (`packing`), the kinds of
registry records (`content`), and the calls between contracts (`interface`: `IResults`,
`IInstanceEntry`, `IRegistryRead`, `IFate`).

**Why a separate `Market`.** The `Hub` stub is already 11.7 % of the CASM limit with interfaces
only (§1.3), and the market is a feature of its own: lots, trades and their counters. Its cost is one
call to the hub per market action (escrow, gold), about 0.14 M (E), on actions that are not play.

**Why a separate `Registry`.** Content is read by both domains and by the client (pillar 6). One
uniform record store keeps its class small (1.8 %) and its interface stable: a new kind of content
is a new kind number, not a new entrypoint.

**Why the provider is a contract.** ADR-0002: the provider is configuration. Version 1 changes the
address in `Hub` and `Instances` (`set_contracts`), not the game's code.

### 1.2 Who may call whom (access control, ADR-0007)

| Caller → callee | Entrypoints | The check |
|---|---|---|
| player → `Instances` | `play`, `loot`, `open`, `mine`, `barter`, `leave`, `travel_back` | **the caller is the member's `controller`, and the member is in this instance** (`placement.inside`, generation equal, status `INSIDE`): M-6, design/02 item 9. Never "the caller created the instance" |
| `Hub` → `Instances` | `create`, `set_controller` | caller = the registered `hub` |
| player → `Hub` | every `IHub` entrypoint naming an adventurer | caller = `accounts[adventurer.account].owner`; the adventurer is in a hub (not inside) for services, build, trade |
| player → `Hub` | `register`, `set_account_owner` | `set_account_owner`: caller = current owner (A-7) |
| `Instances` → `Hub` | `report`, `barter` | caller = the registered `instances` |
| `Market` → `Hub` | `seller`, `escrow`, `release`, `transfer_gold`, `exchange` | caller = the registered `market` |
| player → `Market` | lots and trades | through `Hub.seller(adventurer, caller)`: the caller owns the adventurer's account; Tin rank to sell (design/16) |
| anyone → `Market.return_lot` | an expired lot | nothing beyond expiry (design/16: "the seller, or anyone") |
| administrator → every contract | `set_contracts`, `set_admin`, `upgrade`, `Registry.set_record` | caller = `admin` (who holds it: Q-08) |
| anyone → `TxHashFate.fate` | | none needed (no state); refuses chain id `SN_MAIN` at deployment and at every call (tested) |
| anyone → views | | none |

When an account changes owner while one of its adventurers is inside, `Hub.set_account_owner` calls
`Instances.set_controller`, so that the new owner plays and the old one cannot.

### 1.3 Class size (ADR-0007, NS-3, R-22)

Limits (docs.starknet.io, *Chain info*, read 2026-09-29): **4,089,446 bytes** of Sierra class,
**81,920 felts** of CASM bytecode. Measured by `python3 contracts/tools/class_sizes.py` after
`scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build` (M, this commit):

| Contract | Sierra class, bytes | CASM bytecode, felts | Share of the nearer limit |
|---|---:|---:|---:|
| `Hub` | 200,851 | 9,819 | 11.99 % |
| `Instances` | 135,728 | 6,410 | 7.82 % |
| `Market` | 57,517 | 2,816 | 3.44 % |
| `Registry` | 42,410 | 1,435 | 1.75 % |
| `TxHashFate` | 18,039 | 368 | 0.45 % |

(After fix loop 1. The probes `ReuseProbe`, `CallProbe` and `EventProbe` are under 1.4 % each and
never deployed.)

CASM bytecode is the binding limit (the Sierra limit is 21 to 50 times farther). **Estimate of the
full classes (E)**, from the spikes that hold game code, measured the same way:

| Reference | CASM felts | Share |
|---|---:|---:|
| SPK-2 native `Instances` (tick, queue, enter, leave, three goblin layouts) | 31,783 | 38.8 % |
| SPK-7 `Instances` (reveal with generation, the tick on the chunked window, five variants of `act`) | 37,074 | 45.3 % |
| SPK-2 native `Hub` (enter, leave, brew, quests) | 13,755 | 16.8 % |

`Instances` with the full rules (generation, the tick, full AI, skills, conditions, Fate actions,
views) will pass the limit if it holds all of them. **The boundary for that is decided now:**
`Instances` stays the only owner of the ephemeral storage; the pure rules of the tick and of
generation go into **library classes** (`grimworld_logic` code declared as their own classes,
called by `library_call` with their class hash as configuration, state in and state out, one call
per invocation). A library call costs about one call C (E: same syscall family as §2.3). The rule
for later lots: **a class that passes 50 % of a limit is split before it grows further**
(`class_sizes.py --warn 50` fails above). `Hub` holds quiver's two components when ARC embeds them;
their size is unknown (ARC). Running `class_sizes.py` in CI is the orchestrator's step in
`.github/` (§11, E-10).

---

## 2. Reusing an instance's slots

### 2.1 The rule (project manager, 2026-09-29) and how it is kept

An adventurer gets **one slot** (a `u32`) at its first entry, from the counter `next_slot`, and
keeps it: every later instance of that adventurer is written under the same slot, over the previous
instance's keys. The **instance id** is `slot × 2^32 + generation`; the generation is +1 at every
entry. Storage is keyed by the slot, never by adventurer id (M-1). A co-op party (not in the MVP)
plays in the host member's slot.

**Nothing of an old instance is reachable from the new one**, by construction: every record of a
slot is reached only through a gate that `create` or a reveal rewrites.

| Record | Reached through | Rewritten at |
|---|---|---|
| `headers[slot]` | the instance id: `header.generation` must equal the id's generation, else the call is refused (`Closed`) and views answer nothing | `create` (generation + 1, sequence 0, clock 0, counts reset) |
| `entropy`, `revealed`, `quotas` | the header | `create` (entry draw; the entry chunk only; the location's quotas) |
| `tasks[(slot, page)]` | `header.tasks` (pages beyond `⌈tasks / 4⌉` are never read) | `create`, only the pages it needs: a page never used before is new then (§9.3) |
| `members[(slot, m)]` | `header.members` (members beyond the count are never read) | `create`, all eight words; **every generation-changing path** (`create`, and `leave` through a gate to a location) writes every transient word for the new clock 0: state from the snapshot, timers, effects and recharges empty (fix loop 2, F-12) |
| `roster[(slot, page)]` | `header.roster_count`: a compact list (removal moves the last entry into the hole). **Masked, not rewritten** (F-13): every read of a page, internal or in a view, zeroes the lanes of entries at or beyond the count (`mask_roster_page`), and no raw page is returned | nothing at `create`: the count is reset to 0 there, so stale lanes are masked without a write |
| `chunks[(slot, c)]` | bit `c` of `revealed`: a chunk not revealed in this generation is never read (wall, D-136) | its reveal, both words |
| `goblins[(slot, e)]` | its spawn chunk revealed **and** bit `k` of that chunk's `touched` (the roster lists only goblins that pass this gate) | the chunk's reveal clears `touched`; the roster's count is reset at `create` |
| `placements[adventurer]` | the adventurer id (its reference to its instance, not instance state) | `create`, `leave` |

So a generation is **not** in any key (it would make every key new and defeat the rule), and not in
any record but the header: the gates above are rewritten in the same invocation that bumps it.
The security lens checks one invariant: *no read of a slot's record that does not first pass the
header's generation and the gate of the table*. The views (`instance_state`, `instance_region`)
apply the same gates: an id of an earlier generation, or a chunk outside `revealed`, returns no
stored word; a roster page is returned masked.

**Nothing carries into a new generation but the belt's reserve** (fix loop 2, F-12, the
orchestrator's ruling). At `create` and at every location or gate transition inside `leave`, the
member's four transient words are written for clock 0 of the new instance:
- `MemberState`: position at the entrance, facing away from it (design/18), health, energy and
  adrenaline from the snapshot (their maxima, and 0 adrenaline), status inside, the hit and cast
  counters 0, flags 0; **the belt's counts are the reserve's**, carried as the F-1 ruling says;
- `MemberTimers`, `MemberEffects`, `Recharges`: empty (`LIVE` only). No deadline of the old clock
  survives, so no deadline can point into the new clock's past or future by mistake.

The snapshot's words (stats, bar, kit), the controller and the task pages are identical across a
gate within one expedition. They are left as they are: a write of the same value changes nothing.
If the design means some state to carry across a gate (health, energy, adrenaline, conditions,
recharges), it is escalated with its clock conversion rather than carried (E-20). Cost: 4 member
words in `leave` through a gate (§9.3, §10).

### 2.2 Reuse, measured

`contracts/tools/reuse_probe.py` on the local node (`scripts/with-node.sh`, starknet-devnet 0.10.0,
RPC 0.10.2), through `ReuseProbe.write(first, count, value)`: every transaction has the same
calldata; only what it writes differs. Raw output: `contracts/tools/reuse-probe-output.txt`. L2 gas
of the whole receipt (M):

| Keys written | Empty (no write) | **New** (0 → 1) | **Kept, overwritten** (1 → 2) | Same value (2 → 2) | **Zeroed** (2 → 0) | **Written again after zeroing** (0 → 3) | Kept after that (3 → 4) | New again (control) |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 1,006,080 | 1,528,080 | 1,126,080 | 1,046,080 | 1,126,080 | **1,528,080** | 1,126,080 | 1,528,080 |
| 4 | 1,006,080 | 2,974,080 | 1,366,080 | 1,246,080 | 1,366,080 | **2,974,080** | 1,366,080 | 2,974,080 |
| 20 | 1,006,080 | 10,846,080 | 2,806,080 | 2,286,080 | 2,806,080 | **10,846,080** | 2,806,080 | 10,846,080 |

Per key, against "same value" (the same computation, no state change) (D):

| Keys | New | Overwritten or zeroed | Written again after zeroing |
|---:|---:|---:|---:|
| 1 | 482,000 | 80,000 | 482,000 |
| 4 | 432,000 | 30,000 | 432,000 |
| 20 | 428,000 | 26,000 | 428,000 |

Every trace's state diff shows exactly the probe's `count` keys changed (or none for "same"), plus
the fee token's 2 balances.

**What it says.**
1. **A key written again after it was zeroed costs exactly a new key.** Zeroing at `leave` and
   writing at the next `enter` would pay a new slot twice per expedition. The price depends on the
   value the key holds at the start of the transaction, not on its history.
2. **A key kept holding a value is priced as an overwrite**: 26,000 to 80,000, FND-04's range. The
   extrapolation of cost-budget.md (CB-5) holds on the local node.
3. **Hence the rule of every layout of the game: bit 250 (`LIVE`) is set in every stored record**,
   so that a reused slot is never 0 when the next instance writes it, even when its fields are all 0
   (an empty roster page, a member without conditions). Nothing is ever zeroed.
4. A write of the value already stored costs no state change (40,000 over "empty" is the write's
   computation on this meter, for one key).

Not measured: the same on Sepolia (the local node's meter is VM resources, SPK-2 §8.2; the per-slot
figures agree with FND-04's Sepolia fit within its spread).

### 2.3 A call between contracts, measured

`test_probe_read_direct` and `test_probe_read_through_a_call` (snforge, `contracts/ephemeral/tests/
test_instances.cairo`): the same eight records read from a `CallProbe`, directly and through a
second one. 5,213,110 − 5,095,200 = **117,910 L2 gas** for one call more (M, snforge's Sierra
gas). This is C.

---

## 3. Storage layouts and packing

### 3.1 Packing rules (`grimworld_logic::packing`)

- A record is one felt, read as two `u128` limbs (`split`); **no field straddles bit 128**.
- **Bit 250 is `LIVE`**, set in every stored record (§2.2). A felt holds 251 bits; bits 0–249 are
  data.
- `Lanes32`: seven `u32` (lanes 0–3 at bits 0, 32, 64, 96; lanes 4–6 at 128, 160, 192) for lists of
  ids and pages of balances. `Lanes16`: fifteen `u16` (0–7 at 16 i; 8–14 at 128 + 16 (i − 8)).
  `Bitmap`: 250 bits.
- Deadlines are on the instance clock (M-2). **No deadline passes `MAX_CLOCK = 2^28 − 1`**: an
  action runs only while `clock ≤ LAST_TICK = MAX_CLOCK − MAX_DURATION − 10`, with `MAX_DURATION`
  = 65,535 the registry's widest duration, recharge or activation. So every deadline fits 28 bits
  (E-4, corrected in fix loop 1).
- **Effective durations are bounded after modifiers** (fix loop 2, F-9;
  `grimworld_logic::durations`). design/15's modifiers lengthen durations: conditions inflicted
  +33 %, enchantments +10 to +20 %, a set bonus +1 tick. The rule:
  - the registry holds base durations, recharges and activations of at most
    `MAX_BASE_DURATION = 43,688` ticks, and its writer refuses more;
  - the percent bonuses that apply to one duration are summed and capped at 50 % (the MVP's largest
    is +33 %);
  - the flat bonuses are summed and capped at 3 ticks;
  - so `effective_duration(base, percent, flat) = ⌊base × (100 + percent) / 100⌋ + flat ≤ 65,535 =
    MAX_DURATION`, the maximum being exactly it (tested: `test_effective_duration_maximum`,
    `test_base_above_cap_refused`).

  `LAST_TICK` then keeps every deadline an action sets, `clock + ticks + effective`, at or below
  `MAX_CLOCK`.
- **Every packer refuses a field wider than its layout** (fix loop 1, F-9): `join` refuses a high
  limb that would reach `LIVE`; `fits` checks every field narrower than its Cairo type (28-bit
  deadlines, the pack's count, offsets and alert, an object's kind and state, the walls above bit
  224, the edges, the attributes, the grimoire's counters and pairs, a bitmap above bit 249). A
  value out of range reverts the write; it never spills into the next lane. Tested at the boundaries.
- **Counters are `Counter` records** (`u64` with `LIVE`): `next_slot`, `next_account`,
  `next_adventurer`, `next_item`, `lot_count`, `open_lot_count`, `trade_count`, `last_ids`. A counter
  is never 0 in storage, so a count that falls to 0 (the open lots) and rises again costs O, not N
  (F-4). The market's three counters are written at deployment.
- Several-slot records are `Store` structs of packed felts: field `i` is at offset `i` from the
  map entry's address (tested: `test_record_sizes`).
- `u256` appears only in `split` and `decode_batch`, to split a felt into limbs (written reason in
  `packing.cairo`; ENG-02 may replace it by `u252`).

### 3.2 `Instances` storage

| Variable | Key | Slots | Record | Written by |
|---|---|---:|---|---|
| `admin`, `hub`, `registry`, `fate` | — | 4 | addresses | constructor, `set_contracts` |
| `next_slot` | — | 1 | `Counter` | first entry of an adventurer |
| `placements` | adventurer `u32` | 1 | `Placement` | `create`, `leave` |
| `headers` | slot | 1 | `Header` | every invocation that runs an action |
| `entropy` | slot | 1 | felt: entry draw + Σ hashes of irreversible actions (a set, ADR-0006 option C) | `create`; an action that feeds it |
| `revealed` | slot | 1 | `Bitmap`, bit `15 cy + cx` | `create`, reveal |
| `quotas` | slot | 1 | `Quotas` | `create`, reveal |
| `tasks` | (slot, page 0–3) | 1 each | `TaskPage`: 4 × `TaskEntry` | `create` |
| `members` | (slot, member 0–7) | **8** each | `Member` | `create` (all); play (the first four) |
| `roster` | (slot, page 0–3) | 1 each | `Lanes16`: entity ids of goblins displaced from their spawn, alive or dead and not looted; a compact list of `header.roster_count` entries | a goblin is displaced, is looted or goes home |
| `chunks` | (slot, chunk 0–224) | **2** each | `Chunk { terrain, features }` | reveal (both); a pack wakes or an object is used (`features`) |
| `goblins` | (slot, entity) | **2** each | `Goblin { state, timers }` | a goblin leaves its first state, acts, dies, is looted |

**`Placement`** (1 felt): slot 0–31 · generation 32–63 · member 64–71 · inside 72–79 · `LIVE`.

**`Header`** (1 felt): generation 0–31 · sequence 32–63 · clock 64–95 (≤ 2^28 − 1) ·
location 96–111 · status 112–119 (0 open, 1 returned, 2 defeated, 3 moved) · members 120–127 ·
tasks 128–135 · revealed count 136–143 · roster count 144–151 · flags 152–159 (bit 0 sealed, Red
Rift) · entry chunk 160–167 · entry tile 168–175 · gate 176–191 · `LIVE`.

**`Quotas`** (1 felt): target `N` 0–7 (dungeon floor, 6–12; 0 in a zone) · open edges 8–15 · left
to place of quota `i` at `16 + 8 i`, 14 quotas (the location's registry list first, then the
snapshotted tasks' quotas). ADR-0006: "two counters per quota", the second being the chunks left,
`N − revealed count`.

**`TaskPage`** (1 felt, `grimworld_logic::snapshot`): four `TaskEntry` of 56 bits at 0, 56 (low)
and 128, 184 (high): task `u32` · kind `u8` (1 kill a caste, 2 reach a landmark, 3 clear a
dungeon, 4 reveal a zone, 5 loot, 6 mine, 7 activate) · param `u16` (the caste, landmark or
location).

**`Member`** (8 consecutive felts; the first four change in play, the last four are fixed at entry):

| Offset | Word | Layout |
|---:|---|---|
| 0 | `MemberState` | adventurer 0–31 · x 32–39 · y 40–47 · facing 48–55 · status 56–63 (inside, down, gone) · health 64–79 · energy (thirds) 80–95 · adrenaline (quarter strikes) 96–111 · hits 112–119 · casts 120–127 · belt counts 4 × 8 at 128–159 · flags 160–167 (turned, instant used, since the last tick) |
| 1 | `MemberTimers` | activation: slot 0–7 (255 none) · target 8–23 · target is a tile 24–31 · deadline 32–63; conditions as deadlines: bleeding 64–95 · poison 96–127 · burning 128–159 · crippled 160–191 · knocked down 192–223 |
| 2 | `MemberEffects` | four effects of 56 bits at 0, 56, 128, 184: skill `u16` · charges `u8` · deadline 32 |
| 3 | `Recharges` | eight 28-bit deadlines: slots 0–3 at 0, 28, 56, 84; slots 4–7 at 128, 156, 184, 212 |
| 4 | `MemberStats` (snapshot) | max health 0–15 · max energy 16–23 · energy regen 24–31 · health regen + 10 32–39 · armor 40–47 · vs physical 48–55 · vs elemental 56–63 · level 64–71 · profession 72–79 · primary rank 80–87 · weapon 88–95 · damage 96–103 · ticks 104–111 · range 112–119 · strength 120–127 · the attribute rank of each bar skill 128–159 (4 bits each) · damage type 160–167 · penetration 168–175 · requirement met 176–183 · set bonuses 184–199 |
| 5 | `MemberBar` (snapshot) | 8 skill ids `u16` at 16 i · elite slot 128–135 |
| 6 | `MemberKit` (snapshot) | belt: 4 potion items `u32` at 0, 32, 64, 96 · the equipment's modifiers flattened: conditional damage 128 · its threshold 136 · life steal 144 · energy on hit 152 · condition duration 160 · enchantment duration 168 · double adrenaline every N hits 176 · quicker cast every N spells 184 · health bonus 192–207 |
| 7 | `controller` | the account address allowed to play this member (M-6) |

**`Chunk`** (2 consecutive felts):
- `Terrain`: walls, bit `15 row + column` for the 225 tiles (1 = wall) · edges 225–228 (West, East,
  South, North; 1 open) for a dungeon, decided at its reveal (ADR-0006, *Outlines*) · `LIVE`.
- `Features`: packs at 0 and 64 (tile 0–7 · template 8–23 · level 24–31 · count 32–35 (0–5) ·
  each goblin's tile as one of the 19 tiles within 2, 5 bits each, 36–60 · the pack's shared `alert` 61–63:
  asleep, on watch, alerted, while none of its goblins has a record) · objects at 128, 160, 192
  (tile 0–7 · kind 8–11 (chest, vein, node, trap, collector, landmark, lever or brazier) · state
  12–15 (used) · param 16–31) · `touched` 224–239 (bit `k`: goblin `k` has a record) · `LIVE`.
- **Occupancy is not stored.** The window's occupancy is the tiles of the members and of the
  goblins in it (the roster's, and the untouched ones of the chunks it overlaps, derived from the
  pack placements), set with one table-driven addition each (E: 70 goblins at most, an estimate of
  about 70,000 L2 gas a tick). SPK-7's layout wrote an occupancy slot per chunk crossed by a goblin
  (2 writes per crossing); here a batch writes none.
- **Bounds this puts on generation (ENG-05, E-3):** ≤ 2 packs of ≤ 5 goblins and ≤ 3 objects per
  chunk. Gates are anchors of the registry, not placements; remains are goblin records.

**`Goblin`** (2 consecutive felts), only for a goblin that left its first state:
- `GoblinState`: x 0–7 · y 8–15 · facing 16–23 · AI state 24–31 (asleep, watch, alerted, engaged,
  fleeing, returning, **dead**: its record is its remains, **looted**) · health 32–47 · energy 48–55 ·
  adrenaline 56–63 · caste 64–79 · level 80–87 (copied from the pack: no registry read to know them) ·
  target entity 88–103 (M-3) · memory x 104–111 · memory y 112–119 · flags 120–127 · the recharge
  deadlines of its four caste skills, 28 bits each at 128–239 · `LIVE`.
- `GoblinTimers`: activation slot 0–7 · target 8–23 · deadline 24–51 · bleeding 52–79 · poison 80–107 ·
  effect skill 108–123 · burning 128–155 · crippled 156–183 · knocked 184–211 · effect deadline
  212–239 · `LIVE`.

**Entity ids** (M-5), `u16`: members 0–7; goblins `8 + 16 × chunk + k`, `k` 0–9 in the chunk where
the goblin spawned (at most 3,601). **Tiles**, `u16`: `x + 256 y`, global, x and y below 225.
**Locations are at most 15 × 15 chunks** (225 × 225 tiles; R-2 asks for about 100 × 100): the revealed
set is one felt. A dungeon's entrance chunk is at (7, 7), so an emerging outline of 12 chunks fits.

**The roster** holds every goblin displaced from its spawn, alive or dead and not looted: at most
60 (four pages). A view finds remains lying away from their spawn chunk through it (§9.3, F-6).
Design/02 bounds awake goblins (8), not displaced ones; E-2.

**Alerting a pack** (design/05: a pack shares aggro) writes its `alert` bits in its chunk's
`features`, not one record per goblin: a goblin gets a record only when it acts, moves or is hit
(fix loop 1, F-2).

### 3.3 `Hub` storage

| Variable | Key | Slots | Record |
|---|---|---:|---|
| `admin`, `registry`, `instances`, `market`, `fate` | — | 5 | addresses |
| `next_account`, `next_adventurer`, `next_item` | — | 3 | `Counter` |
| `account_of` | owner address | 1 | account id |
| `accounts` | account `u32` | 2 | `Account { owner, record: AccountRecord }` |
| `account_adventurers` | (account, page) | 1 | `Lanes32` of adventurer ids |
| `adventurers` | adventurer `u32` | **6** | `Adventurer { core, place, build, belt, equipped, name }` |
| `known_skills` | (adventurer, page) | 1 | `Bitmap` by skill id |
| `counters`, `account_counters` | (adventurer or account, counter `u16`) | 1 | `Bitmap`: title "distinct" counters (T-2) |
| `grimoires` | (adventurer, book `u16`) | **3** | `Grimoire { state, pairs, pairs_more }` |
| `balances` | (owner key, page `u32`) | 1 | `Lanes32`: item `7 page + lane` |
| `gold` | owner key | 1 | `Gold` (`u64`) |
| `items` | entity `u32` | **2** | `Item { base: ItemBase, mods: ItemMods }` |
| `packs` | (adventurer, page) | 1 | `Lanes32` of equipment entities (20 + 5 per bag: ≤ 4 pages) |
| `vaults` | (account, page) | 1 | `Lanes32` of equipment entities (25 per pane: 4 pages a pane) |
| `rift_boards` | account | 1 | `RiftBoard` |

The **owner key** of balances and gold is `kind × 2^32 + id`: 1 an adventurer's pack, 2 an
account's vault, 3 escrow (one owner, id 0: the market; the lot says what it holds). An item balance
always says which of the two owns it (design/03); gold and items are keyed by owner and item id
(design/07, Q-07).

Layouts (`contracts/persistent/src/models/`), every one with `LIVE`:
- `AccountRecord`: slots 0–7 · adventurers 8–15 · highest rank 16–23 · vault panes 24–31 · open lots 32–39.
- `AdventurerCore`: account 0–31 · experience 32–63 · merit 64–95 · level 96–103 · rank 104–111 ·
  profession 112–119 · secondary 120–127 · unspent points 128–143 · trials passed first time 144–159 ·
  trials tried 160–175 · status 176–183 (deleted) · `pack_lanes` 184–199: the pack's non-zero balance
  lanes, kept by every balance change that empties or fills a lane (then +1 O), so that
  `delete_adventurer` checks an empty pack without scanning pages (fix loop 1, F-5).
- `AdventurerPlace`: instance id 0–63 · hub 64–79 (0 inside) · last hub 80–95 · inside 96–103 ·
  unlocked hubs 128–191.
- `Build`: bar 8 × `u16` 0–127 · attribute ranks 9 × 4 bits 128–163 · elite slot 168–175.
- `belt` (`Lanes32`, lanes 0–3: potion items; lane 4: the count to carry in each slot, 4 × `u8`) · `equipped` (`Lanes32`: weapon, off-hand, chest,
  legs, head, hands, feet) · `name` (short string).
- `ItemBase`: base 0–15 · requirement 16–23 · rarity 24–31 · level 32–39 · flags 40–47 (identified,
  personalised, boss, component) · look 48–63 · set 64–79 · owner kind 80–87 · owner 88–119.
  `ItemMods`: five `(modifier u16, value u8)` at 0, 24, 48, 72, 96 (prefix, suffix, inscription,
  insignia, rune): written at identification, when the modifiers come to exist (design/15).
- `GrimoireState`: known recipes 0–15 · untried pairs per signature 6 × 8 at 16–63 · 4 hints of 16
  bits at 64–127. `Pairs`: 5 bits a pair (tried, recipe + 1), pairs 0–24 in the low limb, 25–48 in
  the high one: a book of 10 ingredients (45 pairs) in one felt; 11 or 12 need `pairs_more`.
- `Gold`: amount 0–63. `RiftBoard`: day 0–31 · cleared 32–39 · 5 identities of 16 bits at 40–119.

Quests and achievements are **quiver's components** (D-131, D-135), embedded by ARC: their storage
is the package's ("every record in one storage slot"), at most **4 held quests** per adventurer.
Their entrypoints on `Hub` are frozen here (§4.3).

### 3.4 `Market` storage

| Variable | Key | Slots | Record |
|---|---|---:|---|
| `admin`, `hub`, `registry` | — | 3 | addresses |
| `lot_count`, `open_lot_count` | — | 2 | `Counter` (SPK-11 §6), written at deployment |
| `lots` | lot `u64` | 1 | `Lot`: price 0–63 · expiry 64–127 · seller account 128–159 · lot size 160–167 · state 168–175 (open, sold, withdrawn, returned) · kind 176–183 (balance, equipment) · item or entity 184–215 · market 216–231 |
| `seller_lots` | (account, page) | 1 | `SellerPage`: 3 lot ids of 64 bits · count on page 0 at 192–199 ("my lots", 10 + rank: ≤ 7 pages) |
| `trade_count` | — | 1 | `Counter`, written at deployment |
| `trades` | trade `u64` | **5** | `Trade { head, inviter: TradeSide, invited: TradeSide }`; `TradeHead`: inviter 0–31 · invited account 32–63 · invited adventurer 64–95 · state 96–103 · confirmations 104–111 · revision 112–119 · opened at 128–191; `TradeSide { goods: Lanes32 (7 entities), money: TradeMoney }`; `TradeMoney`: gold 0–63 · item 64–95 · amount 96–127 · item 128–159 · amount 160–191 |

Lot and trade ids come from their counters, never reused (SPK-11 §6: the indexer detects a gap). A
lot is therefore always a new slot (N, once per posting); reusing lot slots per account would save
about 0.42 M a posting at the price of the gap check (§11, E-11).

**The market key** (SPK-11 *scope 5*, one felt, frozen with `LotPosted`, `models::market::market_key`):
a balance: its item id; equipment: `2^40 + base × 2^16 + requirement × 2^8 + rarity × 2 + identified`;
a boss item: `2^41 + base`.

### 3.5 `Registry` storage and shapes (scope 6)

`records: Map<(kind u8, id u32, part u8), felt252>`, `last_ids: Map<kind, Counter>`. A record is
`parts(kind)` felts (`grimworld_logic::content`); values may change (design/01 rules 1–2). Pillar 6
and S-6: a zone or a quest is data.

**Allocation** (fix loop 1, F-8; `content::is_sequential`):
- **Sequential kinds** (every kind but four): ids 1, 2, 3 … A new id must be `last_id(kind) + 1`;
  `last_id` is the highest written. Append-only: an id is never reused.
- **Composite kinds**: `OUTLINE` (`location × 256 + chunk`, 255 for the chunk set), `SHOP`
  (`hub × 16 + service`), `TASK` and `QUEST` (the ids quiver hands out). Any id whose parent exists
  (the location, the hub, quiver's task or quest); `last_id` stays 0 for them.
- **Existence**, for every kind: a record exists when its part 0 is not 0. Its writer sets `LIVE`
  (bit 250) in part 0, so that a record whose fields are all 0 still exists, and a rewrite is O.

| Kind | # | Parts | Holds (fields; ENG-03 writes the bit layout within the parts) |
|---|---:|---:|---|
| `REGION` | 1 | 1 | town hub, book, first location, name |
| `LOCATION` | 2 | 2 | type (town, outpost, zone, dungeon, elite, Rift, trial), region, biome, level band, rank required, size in chunks, dungeon `N` and floors, next floor, spawn table, set pieces, entry chunk and tile, sealed |
| `OUTLINE` | 3 | 1 | id `location × 256 + 255`: the zone's chunk set (bitmap); id `location × 256 + chunk`: a border chunk's tile mask (ADR-0006, *Outlines*) |
| `GATE` | 4 | 1 | source, destination, source anchor (chunk, tile), destination entry, kind (hub, link, floor, Rift), rank required, quest required |
| `QUOTAS` | 5 | 1 | up to 6 quotas of a location: kind (exit, Heart, vein, collector, landmark, set piece), param, count |
| `SPAWN_TABLE` | 6 | 1 | up to 7 (pack template, weight), density |
| `PACK` | 7 | 1 | up to 5 (caste, count min, max), level offset |
| `CASTE` | 8 | 2 | tier, AI profile, health multiplier, armor, weapon, 4 skills, loot table, boss |
| `SKILL` | 9 | 2 | profession, attribute, kind, elite, energy, adrenaline, activation, recharge, range, target, 3 effects (kind, value at 0 and 12, duration) |
| `LOOT_TABLE` | 10 | 2 | up to 7 (item, weight), nothing weight, gold range, equipment chance and rarity weights |
| `ITEM` | 11 | 1 | class (ingredient, material, potion, trophy, stillstone, heartstone, quest, failed brew), region, rarity, value, book index, potion effect |
| `BASE` | 12 | 2 | equipment base: slot, weapon or armor class, profession, damage by requirement, rating, look |
| `MODIFIER` | 13 | 1 | slot, effect, value range, condition or cost (Q-4, Q-6) |
| `ARMOR_SET` | 14 | 1 | pieces, two bonuses |
| `BOOK` | 15 | 3 | ingredients, their rarities packed, recipe masks per signature, potion of each recipe |
| `TASK` | 16 | 1 | what counts toward a quiver task: criterion and param (D-131) |
| `QUEST` | 17 | 2 | giver hub, kind, rank required, rewards (xp, gold, merit, skills, item), prerequisites' task ids |
| `RANK` | 18 | 1 | merit threshold, trial quest, points given, unlocks |
| `RIFT_GRADE` | 19 | 1 | rank required, tiers, floors, Heart caste |
| `COLLECTOR` | 20 | 1 | price (items, counts), what it gives |
| `SHOP` | 21 | 2 | id `hub × 16 + service`: the offers of a trainer, merchant, smith, armorer |
| `LANDMARK` | 22 | 1 | location, placed by quota or anchor |
| `CONTRACT_POOL` | 23 | 1 | a hub's daily contracts (design/14) |
| `SET_PIECE` | 24 | 2 | an authored chunk: terrain, placements (ADR-0006) |
| `COUNTER` | 25 | 1 | what sets the bits of a title's "distinct" counter |

Reads: `record(kind, id)`, `records(kind, ids)`, and **`bundle(requests)`**: every record an
invocation needs in **one call** (C ≈ 0.12–0.14 M), whatever the kinds.

---

## 4. Entrypoints and views

Signatures are the code's (`contracts/*/src/systems/*.cairo`, `contracts/logic/src/interface.cairo`).

### 4.1 `Instances` (design/02, *Entrypoints*)

```
play(instance_id: u64, adventurer_id: u32, sequence: u32, actions: felt252)
loot(instance_id, adventurer_id, sequence, target: u16)          remains: a goblin's entity id
open(instance_id, adventurer_id, sequence, tile: u16)            a chest
mine(instance_id, adventurer_id, sequence, tile: u16)            a vein
barter(instance_id, adventurer_id, sequence, tile: u16)          a collector
leave(instance_id, adventurer_id, sequence, gate: u16) -> u64    closes; enters the next location in the same slot
travel_back(instance_id, adventurer_id, sequence)
instance_state(instance_id) -> InstanceView
instance_region(instance_id, first: u8, count: u8) -> Span<RegionChunk>     count ≤ REGION_PAGE (16)
placement(adventurer_id) -> (u64, u8, bool)
create(adventurer_id, controller, gate: u16, snapshot: Snapshot, tasks: Span<TaskEntry>) -> u64   Hub only
set_controller(adventurer_id, controller)                                                         Hub only
version, set_contracts(hub, registry, fate), set_admin, upgrade(class_hash)                        admin
```

**The batch in one felt** (`grimworld_logic::actions`): count at bits 0–3 (1–10); actions 0–4 at
`4 + 24 i`, 5–9 at `128 + 24 (i − 5)`. An action is 24 bits: kind 0–2 (Move, Turn, Wait, Attack,
Skill, Item, Interact); Move/Turn: direction 3–5; Attack: entity 3–18; Skill: slot 3–5, tile flag 6,
target 7–22; Item: belt slot 3–4, entity 5–20; Interact: tile 3–18. A batch has one encoding
(`decode_batch` refuses a count out of 1–10, a bad argument, a bit beyond the count;
`encode_action` and `encode_batch` refuse a direction above 5, a bar slot above 7, a belt slot
above 3, fix loop 1 F-10: tested).
`play`'s calldata is **4 felts** whatever the batch: 30 felts per batch in cost-budget.md's
estimate cost 153,600, one felt 5,120.

**Semantics frozen from design/02** (the code of ENG-06/07 implements them):
- `Header.sequence`: 0 at `create`; +1 per executed action (play, loot, open, mine, barter); `leave`
  and `travel_back` carry the sequence of the instance they close; `leave` to a location creates
  the next instance at sequence 0 in the same slot (generation + 1) and returns its id.
- `play`: a sequence that differs runs nothing (`Stop::Sequence`); an id of an earlier generation,
  or a closed instance, runs nothing (`Stop::Closed`); the weight is counted as the actions run
  (`max(1, ticks) + 2 × chunks revealed`), and the action that would pass 10 stops the batch
  (`Stop::Weight`); the first illegal action stops it (`Stop::Invalid`); defeat stops it
  (`Stop::Defeated`). **No revert for invalidity in the game.** `BatchPlayed` always.
- Fate and gate actions: sequence and every precondition **before** `fate(domain)`; a failure
  emits `Refused` and changes nothing; the draw and the consumption (the goblin's `LOOTED`, the
  chest's state) in the same invocation (ADR-0002 rules 3, 5). `domain = poseidon(instance_id,
  sequence, purpose)`: one word per domain (rule 2).
- No stop condition in the contract (design/02 item 4).
- An action runs only while `clock ≤ LAST_TICK` (E-4); otherwise it is invalid.

**The standalone actions, by their real behaviour** (fix loop 1, F-3; budgets in §10):

| Action | World ticks | Draw | Interrupted | What it writes | Results |
|---|---:|---|---|---|---|
| `loot` | 0 (design/04: *pick up*, 0 ticks) | Fate: the drop (D-50) | — | header, entropy, the goblin's state (`LOOTED`), the roster (removed if displaced) | the drop to the pack; Scavenger; loot tasks |
| `open` | 1 (design/04: *Interact*, a chest) | Fate, after the tick: the chest's content | the tick runs first; if it defeats the member, nothing is drawn and the chest stays | the tick's writes (§9.2 per tick), the chest's object state | the content to the pack |
| `mine` | up to 3 (design/17), an activation | **none** (design/17: 1 stillstone, no draw; E-18) | **stopping**: the ticks run one by one; a hit taken at tick k (1–3) ends the action after that tick: the vein stays, no stone, the sequence still +1. **Completion**: 3 ticks without a hit mark the vein mined (its object state) and feed the entropy. Defeat ends it too (closing report) | the ticks' writes (its own union, §9.3: up to 42 goblins), the vein's state when completed | completion: 1 stillstone, mine tasks; every branch: the ticks' results (experience, tasks) in one aggregated report, `GoblinKilled` and `Defeated` as they happen |
| `barter` | 1 (design/04: *Interact*) | none | the tick runs first; the exchange happens if the member still stands next to the collector | the tick's writes | `Hub.barter`: the price out of the pack, the item in (E-6) |
| `leave`, `travel_back` | 0 | Fate for the next location's entry draw (`leave` to a location) | — | §9.3 | closing report, or Moved |

**Views** return the stored words in their layouts (the client decodes them with the same code):
`InstanceView { instance_id, header, entropy, revealed, quotas, tasks, members (8 words each),
roster, goblins (every goblin of the members' windows), chunks (the chunks the windows overlap) }`;
`RegionChunk { chunk, kind (Void, Unrevealed, Revealed), terrain, features, goblins }`, words only
for a revealed chunk. A `GoblinView` says whether the goblin is **derived** (untouched, at its
spawn, from its pack placement) or stored. `instance_region` finds remains lying away from their
spawn chunk through the roster (§9.3, F-6). Both views are pure reads: callable at a block hash or
at `pre_confirmed`.

**The roster in views is masked** (fix loop 2, F-13). `InstanceView.roster` returns the pages up
to `⌈roster_count / 15⌉` with every lane of an entry at or beyond `header.roster_count` zeroed
(`models::instance::mask_roster_page`); the goblins they list are the only roster goblins in
`InstanceView.goblins` and `RegionChunk.goblins`. The same masking applies to every internal read
(the tick, `loot`, the reveal of a follower's position). A raw page is never returned. Tested at
the helper (`test_roster_masking`); the view case is in the deferred view tests (E-13): an earlier
generation fills page 0, the new one has one entry, and the view shows that one entry and zeros
elsewhere.

**Every generation-changing path initialises the member's transient words** (fix loop 2, F-12; §2.1):
`create`, and `leave` through a gate to a location. Nothing carries but the belt's reserve.

### 4.2 The calls between contracts (`grimworld_logic::interface`)

```
IInstanceEntry (Instances; Hub only):  create(...) -> u64,  set_controller(adventurer_id, controller)
IResults (Hub; Instances only):        report(results: Results),  barter(adventurer_id, collector) -> bool
IRegistryRead (Registry):              record, records, bundle
IFate (provider):                      fate(domain) -> felt252
IHubMarket (Hub; Market only):         seller, escrow, release, transfer_gold, exchange
```

### 4.3 `Hub` (hub and persistent actions of the MVP)

```
register() -> u32                         set_account_owner(account_id, owner)
create_adventurer(name, profession) -> u32    delete_adventurer(adventurer_id)
set_build(adventurer_id, build: felt252, belt: felt252, equipped: felt252)     one call, stored layouts
enter(adventurer_id, gate: u16) -> u64    enter_rift(adventurer_id, index: u8) -> u64    travel(adventurer_id, hub: u16)
accept_quest / abandon_quest / claim_quest(adventurer_id, quest: u32)          accept_contract(adventurer_id, index: u8)
claim_title(adventurer_id, achievement: u32)    display_title(adventurer_id, title: u16, tier: u8)
buy_skill(adventurer_id, skill: u16)
buy(adventurer_id, shop: u32, offer: u8, quantity: u32)    sell(adventurer_id, item: u32, quantity: u32, entity: u32)
craft(adventurer_id, shop: u32, offer: u8)    recycle(adventurer_id, entity)    personalise(adventurer_id, entity)
identify(adventurer_id, entity)                                 Fate
lift_modifier(adventurer_id, entity, slot: u8, stone: bool)     Fate without a stone
set_modifier(adventurer_id, entity, component: u32, stone: bool)
brew(adventurer_id, a: u32, b: u32)                             Fate on a new pair
buy_hint(adventurer_id, book: u16)                              Fate
stow(adventurer_id, to_vault: bool, entities: Span<u32>, balances: Span<(u32, u32)>, gold: u64)   ≤ 8 and ≤ 8
views: account_of, account, adventurer, known_skills, counters, balances, gold, item, pack, vault,
       grimoire, rift_board, quests
```

### 4.4 `Market` (design/16)

```
post_lot(adventurer_id, kind: u8, item: u32, lot_size: u8, price: u64) -> u64
buy_lot(adventurer_id, lot: u64, price: u64)    withdraw_lot(adventurer_id, lot)    return_lot(lot)
open_trade(adventurer_id, invited: u32) -> u64
set_trade_side(adventurer_id, trade, goods: felt252, money: felt252)    confirm_trade(adventurer_id, trade, revision: u8)
decline_trade(trade)    cancel_trade(adventurer_id, trade)
views: lot, lot_count, open_lot_count, lots_of, trade, trade_count
```

### 4.5 Bounds on every list argument

| Argument | Bound | Where it is enforced |
|---|---|---|
| `play.actions` | 1–10 actions, weight ≤ 10 | the encoding; the weight as the actions run |
| `create.tasks` | ≤ 16 (D-131) | `create` |
| `Results.contributors` | ≤ 8 (M-3) | `report` |
| `Results.balances`, `equipment`, `tasks` | ≤ 8, ≤ 3, ≤ 16 and snapshotted ids only | `report` |
| `stow.entities`, `stow.balances` | ≤ 8 each | `stow` |
| `instance_region.count` | ≤ 16 chunks | the view |
| `records.ids`, `bundle.requests` | ≤ 32 | the view |
| `Hub.counters.counters`, `Hub.balances.pages` | ≤ 32 | the view |
| `set_account_owner`: adventurers updated | ≤ 7 (one account page) | `set_account_owner` |
| the belt | 4 slots, a count of ≤ 255 each (lane 4 of `belt`) | `set_build`, `enter` |
| `Registry.set_record.record` | exactly `parts(kind)` | the writer |
| a trade side | ≤ 7 entities, ≤ 2 balances, gold (E-11) | the stored layout |
| held quests | ≤ 4 (D-135) | quiver |

---

## 5. Events (scope 4)

The first key is the selector of the name. A change is a new event name (SPK-11 §6). Tested:
`test_hub_events`, `test_market_events`, `test_instances_event_keys_and_data`,
`test_per_action_event_keys_and_data`.

| Event | Emitted by | Keys | Data |
|---|---|---|---|
| `AdventurerLocated` | `Hub` | `hub: u16` (0: in no hub) | `adventurer: u32` |
| `TitleDisplayed` | `Hub` | `adventurer: u32` | `title: u16, tier: u8` |
| `TrialPassed` | `Hub` | `adventurer` | `rank: u8, first_attempt: bool` |
| `DungeonCleared` | `Hub` | `adventurer` | `dungeon: u16` |
| `RankReached` | `Hub` | `adventurer` | `rank: u8` |
| `LotPosted` | `Market` | `market_key: felt252, lot_size: u8` | `lot: u64, price: u64, expiry: u64, equipment: u32, modifiers: felt252` |
| `LotClosed` | `Market` | `lot: u64` | `sold: bool` |
| `TradeOpened` | `Market` | `invited: u32` (account) | `trade: u64, inviter: u32` |
| `TradeClosed` | `Market` | `trade: u64` | `outcome: u8` (0 done, 1 declined, 2 cancelled) |
| `InstanceEntered` | `Instances` | `instance_id: u64` | `adventurer_id: u32, location: u16, gate: u16` |
| `BatchPlayed` | `Instances` | `instance_id` | `adventurer_id, from: u32, played: u8, stop: Stop, sequence: u32, clock: u32` |
| `Refused` | `Instances` | `instance_id` | `adventurer_id, from, sequence, reason: Refusal` |
| `InstanceClosed` | `Instances` | `instance_id` | `outcome: Outcome` |
| `GoblinKilled` | `Instances` | `instance_id` | `entity: u16, caste: u16, tile: u16` (where its remains lie)`, by: u16` |
| `ChunkRevealed` | `Instances` | `instance_id` | `chunk: u8` |
| `Defeated` | `Instances` | `instance_id` | `adventurer_id: u32` |

The first nine are SPK-11's (five MVP, two of the trade, three rankings emitted from the MVP on).
The instance's seven serve the client from its own receipts; the indexer needs none. `Stop`,
`Refusal`, `Outcome` are enums whose variant index is their encoding (order frozen in
`grimworld_logic::types`). **Views of the indexer:** `Market.lot_count`, `open_lot_count`,
`trade_count` (SPK-11 §6). Completeness (every path emits its event exactly once) is the implementing
lots' invariant, with tests.

**The per-action events of design/02 are restored** beside `BatchPlayed` (fix loop 1, F-7, the
orchestrator's ruling): `GoblinKilled` at each death, `ChunkRevealed` at each reveal, `Defeated` at
a member's defeat, in the invocation where they happen (a batch, `open`, `mine`, `barter`). Their
price, measured by `EventProbe` (the same call with and without them, snforge, M):

| Test | L2 gas | Per event |
|---|---:|---:|
| `test_probe_events_none` | 282,660 | — |
| `test_probe_events_eight_killed` (8 `GoblinKilled`, 4 data felts each) | 736,580 | **56,740** |
| `test_probe_events_four_revealed` (4 `ChunkRevealed`, 1 data felt) | 442,850 | **40,048** |

On Sepolia about × 1.157 (E): 65,648 and 46,336. A batch's worst is 16 kills (with E-16), one
defeat and no reveal: about 1.1 M, 2.6 % of the bound (E-17). A typical fight batch is about
3 kills: 0.2 M.

---

## 6. The snapshot and the results (ADR-0001, scope 5)

**At entry** (`Hub.enter` → `Instances.create`, one transaction): the hub checks the gate's
requirements, locks the build (the adventurer is `inside`: `set_build`, services and trade refuse
it), and passes:
- `Snapshot { stats: MemberStats, bar: MemberBar, kit: MemberKit, belt_counts }`: everything a tick
  needs of the adventurer, computed from its level, attributes, equipment and belt (design/03,
  design/15); stored as the member's words 4–6 and the belt counts of word 0;
- `controller`: the account's owner (M-6);
- `tasks`: at most 16 `TaskEntry` (D-131): the held quests' and contract's tasks and the titles in
  progress, each with the criterion the instance can check alone (a caste, a landmark, a location).

The instance never reads the hub during play. **It reads the registry** (content, not a model of
the persistent state): one `bundle` call per invocation that needs content (E-5).

**Results** (`IResults.report`, **one call per transaction** that has any): contributors (M-4),
experience, gold, balances, equipment drops (unidentified `ItemBase`), task increments (only
snapshotted ids), facts (dungeon cleared, trial passed, Rift cleared, zone revealed, hub reached),
outcome (open, returned, defeated, moved), the hub, the next instance. When:
- a `play` with a kill, a landmark, an objective: its increments and experience;
- a Fate action: what the draw gave (design/07: straight to the inventory);
- `leave`, `travel_back`, defeat: the outcome and the hub (`AdventurerLocated` from the hub);
- `barter` is the one exception: the collector's price is in the pack, which only the persistent
  domain holds; `Instances` asks `Hub.barter`, which exchanges or answers `false` (`Refused`,
  `Refusal::Price`) (E-6).

**The belt's reserve** (fix loop 1, F-1, the orchestrator's ruling). Potions, and any consumable
carried in, are **reserved at entry**:
- `Hub.enter` debits each belt slot's count (`belt` lane 4, set by `set_build`) from the pack's
  balance of that slot's item, in the entry transaction. It refuses the entry if the pack holds
  less. **Two slots of the same item** are one debit of their sum, on one page.
- The counts live in the member (`MemberState.belt`); a potion used in the instance lowers its
  slot's count and is gone.
- The **report that closes the member's presence** carries the unused counts (`Results.belt`); the
  hub credits them back to the pack, again as one credit per item.
- A **location transition** (`leave` through a gate, Outcome `Moved`) credits nothing: the reserve
  carries into the next instance, whose member keeps the same counts.
- **On defeat**: design/03 and design/07 do not settle it. design/07 says loot is kept on defeat;
  design/02's D-04 says defeat costs "the instance, nothing else". **That part is stopped and
  escalated (E-15)**; the interface carries the counts on every closing report, whatever the rule.
- **Storage**: the entry writes the belt items' pack pages (≤ 4 distinct pages, O: they hold the
  potions, so they exist) and the core's `pack_lanes` if a lane falls to 0; the closing report
  writes the same pages back (≤ 4 O) and `pack_lanes`. No new key: +0.16 M on `enter` and on
  `leave` (5 × O; §9.3, §10).

---

## 7. Randomness and accounts (scope 7)

**`fate(domain)`** (`IFate`, ADR-0002). Game code calls only this, at the provider address of its
configuration. The MVP's `TxHashFate` returns `poseidon(transaction hash, domain)`, refuses chain id
`SN_MAIN` at deployment and at every call (tested: `test_fate_refuses_mainnet_*`), and is steerable by
the sender (the accepted weakness). Domains are `poseidon(instance_id, sequence, purpose)` in an
instance, `poseidon(adventurer_id, counter, purpose)` in the hub: distinct per use (rule 2).
**Version 1** (DES-21's requirements: attempt-stable draws, no re-roll by a conditional abort, the
permitted composition stated) is not met by any synchronous `fate(domain)`: a request committed in
one transaction and fulfilled in a later one needs either a provider that keeps the request (its
`fate` reverting until fulfilled, the domain binding the request) or a two-phase entrypoint in the
game. The interface does not foreclose either; the choice is ADR-0002's (already escalated by DES-21).

**Accounts** (ADR-0005). On chain the game sees `get_caller_address()`: the burner (OpenZeppelin
`AccountUpgradeable` v3.0.0, D-137). Adventurers belong to an **account id**, whose owner is a field
(`set_account_owner`, A-7): moving to another provider (Controller, our own) keeps the adventurers.
The client's four operations (create or restore, execute, status, sign out) are CLI-01's.

---

## 8. The multiplayer door (AC-3)

| # | Held by |
|---|---|
| M-1 | Every `Instances` map is keyed by the instance's slot (tested: `test_instances_storage_addresses`); `placements` is keyed by adventurer as the adventurer's reference to its instance (design/02) |
| M-2 | `Header.clock`; every duration, recharge, activation and condition is a deadline on it (`MemberTimers`, `MemberEffects`, `Recharges`, `GoblinTimers`, `GoblinState.recharges`) |
| M-3 | `Header.members` and `members[(slot, m)]` (up to 8); `GoblinState.target` is an entity chosen among the members |
| M-4 | `Results.contributors: Span<u32>` |
| M-5 | `Action::Attack(entity)`, `Skill(slot, Target::Entity | Tile)`, `Item(slot, entity)`; `MemberTimers.act_target` |
| M-6 | the permission is "the caller is this member's controller and it is in this instance" (§1.2); `sequence` is the instance's |

---

## 9. What an invocation can touch (scope 2, AC-2; fix loops 1 and 2: F-2 to F-5)

### 9.1 Three kinds of bound

A slot count depends on **which** keys an invocation writes and **whether they exist yet**. Three
bounds are kept apart, and every row of §9.3 gives both key states:
- **Per tick**: what one world tick can change.
- **Per batch**: the **union** over the ticks and actions of one invocation. Each slot is paid once
  per transaction (FND-04), however many ticks change it; but different ticks can change
  different goblins, chunks and targets.
- **Lifetime initialisation**: a key costs N only the first time it is ever written. Every later
  write is O, because `LIVE` keeps it non-zero (§2.2). Keys are made **cold** (never written) or
  **initialised** (written at least once). A reused slot is *not* entirely initialised: a later
  generation that reveals a chunk index, wakes a goblin index or fills a task page this slot never
  used before writes new keys.

### 9.2 `play`: per tick, per batch, lifetime

**Per tick** (design/02, design/04; MVP skills of design/03):

| Record | At most | Why |
|---|---:|---|
| Goblins acting | 8 | the awake set (design/02) |
| Goblins changed by the adventurer's action, beyond those 8 | 6 | the widest MVP area is "adjacent foes" (Cinder Ring: 6 tiles); a trap (Snare) hits the one goblin entering it |
| Goblin words | 28 | (8 + 6) × 2 |
| Chunk `features` | 4 | the window overlaps at most 4 chunks. Alerting a pack writes its shared `alert` bits there, **not** one record per goblin (fix loop 1: `PackPlacement.alert`, bits 61–63) |
| Member words | 4 | state, timers, effects, recharges (one member in the MVP; M-3 allows 8) |

**Per batch** (weight ≤ 10: at most 10 world ticks, at most 10 moves, at most **4** chunks
revealed, because `Σ (1 + 2 cᵢ) ≤ 10`):

| Record | Union bound without a cap | With the cap of E-16 (16 goblins an invocation) | Why |
|---|---:|---:|---|
| Goblin records | 140 (280 words) | 16 (32 words) | 10 ticks × 14. The goblins present in the union of the windows (at most 9 chunks, since 10 moves shift a 15 × 16 window by at most 10 tiles each way) × 10 spawns + the roster's 60 = 150 do not bound it lower |
| Chunk `features` | 9 | 9 | the chunks of the union of windows |
| Chunk `terrain` (reveals) | 4 | 4 | weight |
| Roster pages | 4 (≤ 4 first used) | 4 (≤ 2 first used) | a **compact list** (fix loop 2): an append writes the last page; a removal moves the last entry into the hole, so it writes the hole's page and the last page. Over a batch every page can change. Pages first used are new (N): 16 appends reach at most 2 new pages |
| Header, entropy, revealed, quotas | 4 | 4 | |
| Member words | 4 | 4 | |
| Hub `report` | 5 | 5 | core (experience, `pack_lanes`), quiver's held quests ≤ 4 |
| **Words** | **310** | **62** | the gas-worst batch has no reveal: 56 (§10.1) |
| **Of which new, cold** | 288 + 4 roster | 32 + 2 roster + 8 revealed chunk words = **42** | |
| Events | ≤ 140 `GoblinKilled`, ≤ 4 `ChunkRevealed`, ≤ 1 `Defeated`, 1 `BatchPlayed` | ≤ 16, ≤ 4, ≤ 1, 1 | |

Without a cap on goblins, a batch's writes are bounded only by 280 goblin words: 8.98 M at O
initialised, 127 M at N cold. **E-16** proposes the cap, **E-1** the weight of a cold goblin key.

**One action that cannot be split** (fix loop 2, F-2). The cap and the cold weight bound a batch
of several actions, but a single action runs all its ticks: a 3-tick action (a 3-tick skill; `mine`)
can change 3 × 14 = **42 goblins** by itself, above the cap of 16, and in a cold slot it can write
84 new goblin words, above any weight. Its figures (`contracts/tools/budget_table.py`):
initialised **20,096,982**, cold **56,763,306** (84 goblin words and 3 roster pages new), cold with
one word per goblin (E-1 option b) **38,966,106**. What happens to it is **E-21**:
- (a) **it runs**: the cap and the cold weight bind from an invocation's second action on, and the
  first action is bounded by its own class: 20.1 M initialised, **56.8 M cold**. The bound is raised
  for that class, cold, to 57 M (or 39 M with E-1 b);
- (b) **it is refused**: the action is invalid while it would pass the cap or the weight. Cost: a
  player among many goblins cannot use a 2- or 3-tick action; and in a cold slot the keys can only
  warm by running, so a refused action can stay refused (a stall).
- **Recommended: (a) with E-1 (b)**: no stall, and every invocation stays under 40 M
  (38.97 M cold, 20.10 M initialised).

**Lifetime initialisation of one slot** (all its keys that can ever be new, then O forever):

| Keys | Count | At N |
|---|---:|---:|
| placement, header, entropy, revealed, quotas | 5 | 2.27 M |
| task pages | 4 | 1.81 M |
| member words (1 member; ×8 with a full party) | 8 | 3.63 M |
| roster pages | 4 | 1.81 M |
| chunk words, 225 chunk indexes × 2 | 450 | 204.1 M |
| goblin words, 225 × 10 goblins × 2 | 4,500 | 2,040.9 M |
| **All** | **4,971** | **2,254 M ≈ $1.99** (1 M = $0.000881) |

That is the bound, and **it is also Region 1's** (corrected in fix loop 2). Zones of at most 7 × 7
chunks use the indexes `cx, cy ≤ 6` (49 indexes, 49 × 22 + 21 = 1,099 keys, 498 M). But every
dungeon floor, Rift floor and trial emerges from its entrance chunk at **(7, 7)** (§3.2), and an
outline of up to 12 chunks can reach any index within 11 edge steps of it: every index of the
15 × 15 grid. Over many runs, the floors of Region 1 alone can use the whole grid: **4,971 keys,
$1.99, once per adventurer slot**, paid as first uses. An expected figure: each dungeon run adds its
chunk indexes never used before, at most 12 × 22 = 264 keys (120 M, $0.11), so the first runs cost
most. Placing zones around (7, 7) too would let zones and floors share keys; it lowers the expected
cost, not the bound.

### 9.3 Every public entrypoint: its complete write set

Re-enumerated in fix loop 2 (F-4), **physical key by physical key, per branch**, and the counts
**derived from those sets** by `contracts/tools/budget_table.py --keys` (raw output:
`contracts/tools/budget-keys-output.txt`). A key marked **N** is new when the row's keys were never
written (**cold**); **N!** is new every time (a new entity, a new lot, a new trade id, the first
modifiers of an item). Every other key is O. The fee token's 2 balances are in F. Counters are
`Counter` records with `LIVE`: never N after deployment.

Conventions of the key sets:
- **Compact lists** (the roster, pack and vault lists, the account's adventurers, the seller's
  pages): an append writes the last page (N the first time a page is used); a removal moves the last
  entry into the hole, writing the hole's page and the last page. The seller's pages keep their count
  on page 0: a 4th lot writes page 1 **and** page 0; a removal writes up to 3 pages.
- **`core.pack_lanes`** is written by every balance change that empties or fills a pack lane: the
  last stillstone spent (`buy_hint`, `personalise`, the modifier services), the last potion reserved.
- **Registry reads**: every row that needs content makes **one** `bundle` call (§3.5): `enter` (gate,
  location, outline; the snapshot's skills and bases), `buy`, `sell`, `craft`, `recycle`,
  `personalise`, `identify`, the modifier services, `brew`, `buy_hint`, `buy_skill`, `accept_quest`,
  `accept_contract`, `claim_quest`, `set_build`, `create_adventurer`, `post_lot` (the market key),
  and the instance's actions (§4.1).
- **`create`** writes 15 + ⌈t/4⌉ keys (t ≤ 16 tasks): placement, header, entropy, revealed, quotas,
  the member's 8 words, the entry chunk's 2, the task pages; plus `next_slot` at an adventurer's
  first entry only. The roster is not written (§2.1: masked by its count). **Task pages are not
  initialised ahead**: a later entry with more tasks writes its extra pages new then.

| Entrypoint | Keys written (count; **N** new when cold; **N!** new every time) | Cold N / O | Initialised N / O |
|---|---|---|---|
| `enter` (with `create`) | placement, header, entropy, revealed, quotas (5) **N** · member words (8: state from the snapshot, empty timers, effects, recharges, snapshot, controller) (8) **N** · entry chunk: terrain, features (2) **N** · task pages ⌈t/4⌉, t = 16 (4) **N** · next_slot (written at the first entry only) (1 cold, 0 after) · hub: place (1) · hub: belt reserve, pack pages (4) · hub: core (pack_lanes) (1) | 19 / 7 | 0 / 25 |
| `enter_rift` | placement, header, entropy, revealed, quotas (5) **N** · member words (8: state from the snapshot, empty timers, effects, recharges, snapshot, controller) (8) **N** · entry chunk: terrain, features (2) **N** · task pages ⌈t/4⌉, t = 16 (4) **N** · next_slot (written at the first entry only) (1 cold, 0 after) · hub: place (1) · hub: belt reserve, pack pages (4) · hub: core (pack_lanes) (1) · the account's board (1) **N** | 20 / 7 | 0 / 26 |
| `leave`, `travel_back` | header, placement, member state (3) · hub: place, core (2) · hub: belt credit, pack pages (4) | 0 / 9 | 0 / 9 |
| `leave` through a gate | placement, header, entropy, revealed, quotas (5) · member state, timers, effects, recharges: initialised for clock 0 (F-12) (4) · entry chunk of the next location (2) **N** · hub: place, core (Moved) (2) | 2 / 11 | 0 / 13 |
| `loot`, a boss (3 items) | header, entropy, goblin state (3) · roster: a swap removal (hole page, last page) (2) · balance pages (3 items) (3) **N** · pack gold (1) **N** · item bases (3 drops, always new) (3) **N!** · next_item (1) · pack list pages, appended (2) **N** · core (pack_lanes, experience) (1) · account counter (Scavenger) (1) **N** · quiver held quests (4) | 10 / 11 | 3 / 18 |
| `loot`, ordinary remains | header, entropy, goblin state (3) · roster: a swap removal (2) · balance pages (2 ingredients) (2) **N** · pack gold (1) **N** · core (1) · account counter (1) **N** · quiver held quests (4) | 4 / 10 | 0 / 14 |
| `open`, goblins near (1 tick, then a draw) | goblin words (28) **N** · chunk features (window) (4) · member state, timers, effects, recharges (4) · header, entropy (2) · roster pages, first used (1) **N** · roster pages, others (3) · balance pages (3 items) (3) **N** · pack gold (1) **N** · item bases (3 drops, always new) (3) **N!** · next_item (1) · pack list pages, appended (2) **N** · core (pack_lanes, experience) (1) · account counter (Scavenger) (1) **N** · quiver held quests (4) | 39 / 19 | 3 / 55 |
| `open`, no goblin near | header, entropy, member state, the chest's features (4) · balance pages (2 ingredients) (2) **N** · pack gold (1) **N** · core (1) · account counter (1) **N** · quiver held quests (4) | 4 / 9 | 0 / 13 |
| `mine`, goblins near (3 ticks, own union) | goblin words (84) **N** · chunk features (window) (4) · member state, timers, effects, recharges (4) · header, entropy (2) · roster pages, first used (3) **N** · roster pages, others (1) · hub: stillstone page (1) **N** · hub: core, quiver held quests (5) | 88 / 16 | 0 / 104 |
| `mine`, goblins near, with the invocation cap of 16 (E-16) | goblin words (32) **N** · chunk features (window) (4) · member state, timers, effects, recharges (4) · header, entropy (2) · roster pages, first used (2) **N** · roster pages, others (2) · hub: stillstone page (1) **N** · hub: core, quiver held quests (5) | 35 / 17 | 0 / 52 |
| `mine`, no goblin near | header, entropy, member state, the vein's features (4) · hub: stillstone page (1) **N** · hub: core, quiver (5) | 1 / 9 | 0 / 10 |
| `barter`, goblins near (1 tick) | goblin words (28) **N** · chunk features (window) (4) · member state, timers, effects, recharges (4) · header, entropy (2) · roster pages, first used (1) **N** · roster pages, others (3) · hub: price pages (2) · hub: the item given, its base (1) **N!** · hub: next_item (1) · hub: pack list page (1) **N** · hub: core (1) · hub: the tick's Open report, quiver (4) | 31 / 21 | 1 / 51 |
| `barter`, no goblin near | header, member state (2) · hub: price pages (2) · hub: item base (1) **N!** · hub: next_item, core (2) · hub: pack list page (1) **N** | 2 / 6 | 1 / 7 |
| `register` | account_of, account owner, account record (3) **N!** · next_account (1) | 3 / 1 | 3 / 1 |
| `set_account_owner` (7 adventurers inside) | owner, account_of[old] (zeroed, E-19) (2) · account_of[new] (1) **N!** · each inside: its member's controller (7) | 1 / 9 | 1 / 9 |
| `create_adventurer` | adventurer: 6 words (6) **N!** · next_adventurer, account record (2) · account list page, appended (1) **N** | 7 / 2 | 6 / 3 |
| `delete_adventurer` | core, account record (2) · account list: a swap removal (2) | 0 / 4 | 0 / 4 |
| `set_build` | build, belt, equipped (3) | 0 / 3 | 0 / 3 |
| `travel` | place (1) | 0 / 1 | 0 / 1 |
| `display_title` | none | 0 / 0 | 0 / 0 |
| `accept_quest` | quiver held record (1) **N** · known skills page (skills given at acceptance) (1) **N** | 2 / 0 | 0 / 2 |
| `abandon_quest` | quiver held record (1) | 0 / 1 | 0 / 1 |
| `accept_contract` | quiver held record (1) **N** | 1 / 0 | 0 / 1 |
| `claim_quest` | core (1) · pack gold, balance page, pack list page, known skills page, counter (5) **N** · reward item base (1) **N!** · next_item, quiver 2 (3) | 6 / 4 | 1 / 9 |
| `claim_title` | quiver's claim record (1) **N!** | 1 / 0 | 1 / 0 |
| `buy_skill` | known skills page (1) **N** · pack gold (1) | 1 / 1 | 0 / 2 |
| `buy`, equipment | item base (1) **N!** · pack list page (1) **N** · gold, next_item, core (3) | 2 / 3 | 1 / 4 |
| `sell`, equipment | pack gold (first income) (1) **N** · item base, pack list: a swap removal (2), core (4) | 1 / 4 | 0 / 5 |
| `craft` | item base (1) **N!** · pack list page (1) **N** · material pages 2, gold, next_item, core (5) | 2 / 5 | 1 / 6 |
| `recycle` | item base, pack list: a swap removal (2), core (4) · material pages (2) **N** | 2 / 4 | 0 / 6 |
| `personalise` | item base, stillstone page, gold, core (the last stone: pack_lanes) (4) | 0 / 4 | 0 / 4 |
| `identify` | item mods (they come to exist) (1) **N!** · item base (IDENTIFIED), gold (2) | 1 / 2 | 1 / 2 |
| `lift_modifier`, with a stone | component base and mods (2) **N!** · pack list page (1) **N** · item mods, next_item, stillstone page, core (last stone), gold (5) | 3 / 5 | 2 / 6 |
| `lift_modifier`, without (destroyed) | component base and mods (2) **N!** · item base, pack list: a swap removal (2), next_item, gold (5) | 2 / 5 | 2 / 5 |
| `set_modifier`, with a stone | returned component: base and mods (2) **N!** · item mods, consumed component base, pack list pages 2, next_item, stillstone page, core, gold (8) | 2 / 8 | 2 / 8 |
| `brew`, a new pair | grimoire state and pairs (2) **N** · potion page (1) **N** · ingredient pages 2, core (3) | 3 / 3 | 0 / 6 |
| `buy_hint` | grimoire state, stillstone page, core (last stone) (3) | 0 / 3 | 0 / 3 |
| `stow`, to the vault (8 + 8) | vault list pages, appended (2) **N** · vault balance pages (8) **N** · vault gold (1) **N** · item bases 8, pack list pages 4, pack pages 8, pack gold, core (22) | 11 / 22 | 0 / 33 |
| `stow`, to the pack (8 + 8) | pack balance pages (8) **N** · pack list pages, appended (2) **N** · pack gold (1) **N** · vault list pages: 8 swap removals (8 hole pages + the tail's 2) (10) · vault balance pages 8, item bases 8, vault gold, core (18) | 11 / 28 | 0 / 39 |
| `post_lot`, a balance | lot (a new id) (1) **N!** · seller page k (the 4th lot: page 1) (1) **N** · escrow page (1) **N** · lot_count, open_lot_count, seller page 0 (count), pack page, vault gold (fee), account record, core (7) | 3 / 7 | 1 / 9 |
| `post_lot`, equipment | lot (1) **N!** · seller page k (1) **N** · lot_count, open_lot_count, seller page 0, item base, pack list: a swap removal (2), vault gold, account record (8) | 2 / 8 | 1 / 9 |
| `buy_lot` | seller's vault gold (1) **N** · buyer's vault page or vault list page (1) **N** · lot, open_lot_count, seller pages: a swap removal (hole, last, page 0), buyer's gold, escrow page or item base, account record (8) | 2 / 8 | 0 / 10 |
| `withdraw_lot`, `return_lot` | vault page or vault list page (1) **N** · lot, open_lot_count, seller pages 3, escrow page or item base, account record (7) | 1 / 7 | 0 / 8 |
| `open_trade` | trade head (a new id) (1) **N!** · trade_count (1) | 1 / 1 | 1 / 1 |
| `set_trade_side` | the side's 2 words (2) **N** · head (1) | 2 / 1 | 0 / 3 |
| `confirm_trade`, the swap (7 + 7) | pack list pages appended, 2 a side (4) **N** · balance pages credited, 2 a side (4) **N** · pack gold credited, a side (2) **N** · head, item bases 14, pack list removals 4 a side, balance pages debited 4, cores 2 (29) | 10 / 29 | 0 / 39 |
| `confirm_trade` (first), `decline_trade`, `cancel_trade` | head (1) | 0 / 1 | 0 / 1 |
| `Registry.set_record` | parts (3) **N!** · last_ids (1) **N** | 4 / 0 | 3 / 1 |
| admin setters, `upgrade` | addresses (4) | 0 / 4 | 0 / 4 |

**Views** (no transaction; reads bound what a node's call must allow):

| View | Bound | Reads |
|---|---|---:|
| `Instances.instance_state` | 1 member in the MVP (8 with a party), its window's 4 chunks, the roster | header 1, entropy 1, revealed 1, quotas 1, task pages ≤ 4, member words 8, roster pages ≤ 4 (masked, F-13), roster records ≤ 60 × 2 (state and timers), window chunks 4 × 2, their touched records ≤ 40 × 2: **228**; plus the `touched` gate of each roster goblin whose spawn chunk lies outside the window, ≤ 60 `features` reads: **≤ 288** |
| `Instances.instance_region` | ≤ 16 chunks | header 1 (generation, roster count), revealed 1, 16 chunks × 2 = 32, their touched records ≤ 160 × 2 = 320, roster pages ≤ 4 (masked), every roster goblin's state (its tile) ≤ 60, the timers of those lying in the range ≤ 60, the `touched` gate of their spawn chunks outside the range ≤ 60: **≤ 538** |
| `Instances.placement` | | 1 |
| `Hub.counters` | ≤ 32 ids a call | 32 |
| `Hub.balances` | ≤ 32 pages a call; the client names the pages of the items it knows of (the registry lists items); no view enumerates an owner's pages | 32 |
| `Hub.pack`, `Hub.vault` | 4 pages; 4 a pane × ≤ 8 panes | 4; 32 |
| `Hub.adventurer`, `account`, `item`, `grimoire`, `rift_board`, `gold`, `account_of`, `known_skills` | fixed | ≤ 6, ≤ 3 + 1 page, 2, 3, 1, 1, 1, ≤ 1 page (skill ids < 250 in the MVP) |
| `Hub.quests` | ≤ 4 held | quiver's |
| `Market.lot`, `lot_count`, `open_lot_count`, `trade_count`, `trade`, `lots_of` | `lots_of` ≤ 7 pages | 1, 1, 1, 1, 5, ≤ 7 |
| `Registry.record`, `records`, `bundle` | `records` and `bundle` ≤ 32 records | ≤ 3 × 32 |
| `Registry.last_id` | one kind | 1 |
| `version` (`Instances`, `Hub`, `Market`, `Registry`) | a constant of the class | 0 |
| `TxHashFate` | no view; `fate` reads the transaction's info, no storage | 0 |
| Addresses of the registered contracts and the admin | not exposed by a view: storage only (read by the contracts themselves at each check) | — |

**Remains lying away from their spawn chunk (F-6).** A goblin displaced from its spawn stays in the
roster alive **and** dead, until it is looted or goes home (only the living go home). A view finds
it there: `instance_region` reads the roster through **masked** pages (§2.1, F-13: lanes beyond
`header.roster_count` are zeros) and each listed goblin's state word, and keeps those whose tile lies in the requested chunks.
Remains that never left their spawn chunk are found through that chunk's `touched` bits. The reuse
gates are §2.1's: the roster count is reset at `create`, and a listed goblin is read only if its
spawn chunk is revealed in this generation with its `touched` bit set. Cost: at most 64 reads a
page, no write. The roster's bound of 60 now counts unlooted displaced remains too (E-2).

Checked against the receipts (cost-budget.md §1, M on the left):
- SPK-1b's `enter` (the spike's layout: 4 new, 2 overwritten) measured 3,555,447, against 3,629,831
  by the formula; `leave` 1,659,915 against 1,664,419.
- SPK-2's native traces (FND-04 §5) show the same shapes as this table's rows: tick 0/10, queue
  0/10, brew of a new pair 2/3, accepting a quest 1/0, claiming it 1/2. This design's larger records
  add to them.

---

## 10. The budget (scope 8)

`L2 = F + computation + C × calls + N × new + O × overwritten + events`, **computed by
`contracts/tools/budget_table.py`** from §9.3's key sets (raw output:
`contracts/tools/budget-output.txt`; fix loop 2, F-2 to F-4). F = 816,939; N = 453,524; O = 32,072;
C = 136,000 a call between contracts (117,910 in snforge × 1.157, E); events B = 65,648 (four data
felts: `GoblinKilled`, `LotPosted`) and S = 46,336 (one or two: every other event), from `EventProbe`
× 1.157 (E). Computation is E, with its basis in the row. The **target** of a row is its worst case
in the state named: **initialised** (every key it writes exists) or **cold** (none does).

| Entrypoint | Computation (E) | Calls | Events | Initialised: N / O → L2 | Cold: N / O → L2 | Basis |
|---|---:|---:|---:|---|---|---|
| `enter` (with `create`) | 1.45 M | 4 | 92,672 | 0 / 25 → **3,705,411** | 19 / 7 → **11,745,071** | checks, snapshot, entry draw, first chunk's generation 0.39–0.45 M (SPK-7, M); calls: instances, registry ×2, fate |
| `enter_rift` | 1.55 M | 5 | 92,672 | 0 / 26 → **3,973,483** | 20 / 7 → **12,434,595** | `enter` + the day's board (first action of the day: its draw) |
| `leave`, `travel_back` | 0.60 M | 1 | 92,672 | 0 / 9 → **1,934,259** | 0 / 9 → **1,934,259** | the closing report; `InstanceClosed`, `AdventurerLocated` |
| `leave` through a gate | 1.90 M | 3 | 92,672 | 0 / 13 → **3,634,547** | 2 / 11 → **4,477,451** | the next entry draw and generation; snapshot, controller and task words unchanged |
| `loot`, a boss (3 items) | 0.50 M | 3 | 0 | 3 / 18 → **3,662,807** | 10 / 11 → **6,612,971** | 0 world ticks; calls: registry, fate, hub |
| `loot`, ordinary remains | 0.50 M | 3 | 0 | 0 / 14 → **2,173,947** | 4 / 10 → **3,859,755** | as above |
| `open`, goblins near (1 tick, then a draw) | 4.78 M | 3 | 919,072 | 3 / 55 → **10,053,456** | 39 / 19 → **25,225,728** | one tick as alone (SPK-1, M) and its window; ≤ 14 `GoblinKilled` (traps); the draw branch |
| `open`, no goblin near | 0.80 M | 3 | 0 | 0 / 13 → **2,441,875** | 4 / 9 → **4,127,683** | a quiet tick 0.30 M |
| `mine`, goblins near (3 ticks, own union) | 13.05 M | 2 | 2,757,216 | 0 / 104 → **20,236,382** | 88 / 16 → **57,324,158** | 3 ticks, 42 goblins (3 × 14), ≤ 42 `GoblinKilled`; completion branch |
| `mine`, goblins near, with the invocation cap of 16 (E-16) | 13.05 M | 2 | 1,050,368 | 0 / 52 → **16,861,790** | 35 / 17 → **31,612,610** | the same, 16 goblins |
| `mine`, no goblin near | 0.90 M | 2 | 0 | 0 / 10 → **2,309,659** | 1 / 9 → **2,731,111** | 3 quiet ticks |
| `barter`, goblins near (1 tick) | 4.68 M | 3 | 919,072 | 1 / 51 → **8,918,120** | 31 / 21 → **21,561,680** | calls: registry, hub `barter`, hub `report` |
| `barter`, no goblin near | 0.70 M | 3 | 0 | 1 / 7 → **2,602,967** | 2 / 6 → **3,024,419** |  |
| `register` | 0.20 M | 0 | 0 | 3 / 1 → **2,409,583** | 3 / 1 → **2,409,583** | once per address |
| `set_account_owner` (7 adventurers inside) | 0.20 M | 7 | 0 | 1 / 9 → **2,711,111** | 1 / 9 → **2,711,111** |  |
| `create_adventurer` | 0.30 M | 1 | 0 | 6 / 3 → **4,070,299** | 7 / 2 → **4,491,751** | the profession (registry) |
| `delete_adventurer` | 0.20 M | 0 | 0 | 0 / 4 → **1,145,227** | 0 / 4 → **1,145,227** | pack empty: `pack_lanes` 0, pack lists empty |
| `set_build` | 0.30 M | 1 | 0 | 0 / 3 → **1,349,155** | 0 / 3 → **1,349,155** | skills and bases (registry) |
| `travel` | 0.10 M | 0 | 46,336 | 0 / 1 → **995,347** | 0 / 1 → **995,347** | `AdventurerLocated` |
| `display_title` | 0.05 M | 0 | 46,336 | 0 / 0 → **913,275** | 0 / 0 → **913,275** | event only (T-1) |
| `accept_quest` | 0.40 M | 1 | 0 | 0 / 2 → **1,417,083** | 2 / 0 → **2,259,987** | the quest (registry) |
| `abandon_quest` | 0.30 M | 0 | 0 | 0 / 1 → **1,149,011** | 0 / 1 → **1,149,011** |  |
| `accept_contract` | 0.30 M | 1 | 0 | 0 / 1 → **1,285,011** | 1 / 0 → **1,706,463** | the day's pool (registry) |
| `claim_quest` | 0.60 M | 1 | 92,672 | 1 / 9 → **2,387,783** | 6 / 4 → **4,495,043** | `RankReached`, `TrialPassed` |
| `claim_title` | 0.40 M | 0 | 0 | 1 / 0 → **1,670,463** | 1 / 0 → **1,670,463** |  |
| `buy_skill` | 0.20 M | 1 | 0 | 0 / 2 → **1,217,083** | 1 / 1 → **1,638,535** | the trainer (registry) |
| `buy`, equipment | 0.30 M | 1 | 0 | 1 / 4 → **1,834,751** | 2 / 3 → **2,256,203** | the offer (registry) |
| `sell`, equipment | 0.30 M | 1 | 0 | 0 / 5 → **1,413,299** | 1 / 4 → **1,834,751** | the value (registry) |
| `craft` | 0.30 M | 1 | 0 | 1 / 6 → **1,898,895** | 2 / 5 → **2,320,347** | the offer (registry) |
| `recycle` | 0.30 M | 1 | 0 | 0 / 6 → **1,445,371** | 2 / 4 → **2,288,275** | the base's materials (registry) |
| `personalise` | 0.30 M | 1 | 0 | 0 / 4 → **1,381,227** | 0 / 4 → **1,381,227** | the fee (registry) |
| `identify` | 0.35 M | 2 | 0 | 1 / 2 → **1,956,607** | 1 / 2 → **1,956,607** | calls: registry, fate |
| `lift_modifier`, with a stone | 0.35 M | 1 | 0 | 2 / 6 → **2,402,419** | 3 / 5 → **2,823,871** | the modifier (registry) |
| `lift_modifier`, without (destroyed) | 0.35 M | 2 | 0 | 2 / 5 → **2,506,347** | 2 / 5 → **2,506,347** | calls: registry, fate |
| `set_modifier`, with a stone | 0.35 M | 1 | 0 | 2 / 8 → **2,466,563** | 2 / 8 → **2,466,563** |  |
| `brew`, a new pair | 0.50 M | 2 | 0 | 0 / 6 → **1,781,371** | 3 / 3 → **3,045,727** | calls: registry (book), fate |
| `buy_hint` | 0.35 M | 2 | 0 | 0 / 3 → **1,535,155** | 0 / 3 → **1,535,155** | calls: registry, fate |
| `stow`, to the vault (8 + 8) | 0.40 M | 0 | 0 | 0 / 33 → **2,275,315** | 11 / 22 → **6,911,287** |  |
| `stow`, to the pack (8 + 8) | 0.40 M | 0 | 0 | 0 / 39 → **2,467,747** | 11 / 28 → **7,103,719** |  |
| `post_lot`, a balance | 0.30 M | 4 | 65,648 | 1 / 9 → **2,468,759** | 3 / 7 → **3,311,663** | calls: hub seller, escrow, gold; registry (key) |
| `post_lot`, equipment | 0.30 M | 4 | 65,648 | 1 / 9 → **2,468,759** | 2 / 8 → **2,890,211** |  |
| `buy_lot` | 0.30 M | 3 | 46,336 | 0 / 10 → **1,891,995** | 2 / 8 → **2,734,899** | calls: seller, gold, release |
| `withdraw_lot`, `return_lot` | 0.30 M | 2 | 46,336 | 0 / 8 → **1,691,851** | 1 / 7 → **2,113,303** |  |
| `open_trade` | 0.30 M | 1 | 46,336 | 1 / 1 → **1,784,871** | 1 / 1 → **1,784,871** |  |
| `set_trade_side` | 0.20 M | 1 | 0 | 0 / 3 → **1,249,155** | 2 / 1 → **2,092,059** |  |
| `confirm_trade`, the swap (7 + 7) | 0.80 M | 1 | 46,336 | 0 / 39 → **3,050,083** | 10 / 29 → **7,264,603** |  |
| `confirm_trade` (first), `decline_trade`, `cancel_trade` | 0.10 M | 1 | 46,336 | 0 / 1 → **1,131,347** | 0 / 1 → **1,131,347** |  |
| `Registry.set_record` | 0.05 M | 0 | 0 | 3 / 1 → **2,259,583** | 4 / 0 → **2,681,035** | administration |
| admin setters, `upgrade` | 0.10 M | 0 | 0 | 0 / 4 → **1,045,227** | 0 / 4 → **1,045,227** | administration |

Against cost-budget.md:
- `enter` **3.71 M** initialised (1.9 M expected with reused keys, E-7); 11.75 M cold, once per
  adventurer (3.6 M measured with the spike's 4 new keys at every entry).
- `leave` **1.93 M** (1.7 M: +0.23 M, the belt's credit and the two events).
- A Fate action, 2.9 M: `loot` meets it for ordinary remains (2.17 M) and exceeds it for a boss's
  three items (3.66 M). `open`, `mine` and `barter` meet it only with no goblin near (E-8).
- A hub action, 2.0 M: met initialised by every row but these:
  - `claim_quest`, 2.39 M: the reward entity is always new;
  - `lift_modifier` and `set_modifier`, 2.40 M to 2.51 M: the component is always new;
  - `post_lot`, 2.47 M: the lot is always new;
  - `stow`, 2.28 M to 2.47 M: 8 entities and 8 balances at once;
  - the trade's swap, 3.05 M: 14 items.
- A new discovery in brewing, 2.8 M: 3.05 M cold (the potion's page is also new), 1.78 M after.

`contracts/*/GAS.md` and `docs/BUDGETS.md` list the snforge figures of this task's tests (layouts,
packing, the batch's codec, the probes, deployments). None executes an entrypoint: those are the
implementing lots' benchmarks, each against its row above.

### 10.1 The 40 M bound of design/02, in slots and gas (OP-2, CB-3)

The worst batch is 10 world ticks with no reveal: a reveal takes weight 2 for about 1.4 M
(generation 0.45 M, 2 words, its event), where two ticks take up to 8.6 M. With the cap of E-16
(16 goblins an invocation):

| Part | Slots | L2 gas |
|---|---|---:|
| Floor, one call, 4 felts of arguments | — | 816,939 (D) |
| 10 ticks, each as measured alone (SPK-1 §4, M) | — | 35,649,130 |
| The window at each tick: 65,224 (in memory, M) to 720,000 (SPK-7's whole difference, M) | — | 652,240 to 7,200,000 |
| Writes, once per transaction: goblin words 32 + chunk `features` 9 + roster pages 4 + header and entropy 2 + member 4 + hub report 5 = **56** | 0 / 56 | 1,796,032 |
| Registry `bundle` and hub `report`: 2 calls | — | 272,000 |
| Events: 16 `GoblinKilled`, 1 `Defeated`, 1 `BatchPlayed` (E) | — | 1,050,368 + 92,672 |
| **Total, ticks as alone** | **0 / 56** | **40,329,381 to 46,877,141** |
| **Total, ticks shared as a queue shares them** (1,705,764 a tick, E, cost-budget §3) | 0 / 56 | **21,737,891 to 28,285,651** |
| A cap of 24 instead of 16: 16 more goblin words | 0 / 72 | + 513,152 |
| Without a cap (140 goblins): 248 more goblin words | 0 / 304 | + 7,953,856 |
| A cold slot, without E-1: the 32 goblin words and 2 roster pages first used, new | 34 / 22 | + 14,329,368 |

Fix loop 2's corrections:
- The fix-loop-1 table listed terms that summed to 54 (roster 2) and wrote 56. The terms are now
  complete: a compact roster's swap removals can touch all 4 pages, so the sum is 56 as listed.
- The alternative cap of 24 costs +513,152 overwrite gas (16 words × O), not +0.26 M.
- A cold batch's new keys include the roster pages first used.

**What this settles, and what it does not.**
- **In slots: yes, with E-16 and E-21.** 56 slots a batch initialised, none new. At most 42 new
  keys cold (32 goblin words, 2 roster pages, 8 words of 4 revealed chunks), each goblin key
  weighed by E-1. A single action of 3 ticks is bounded by its own class (§9.2): 20.1 M initialised,
  56.8 M cold (39.0 M with E-1 b).
- **In gas: not proven, and above 40 M at the low end** if every tick is as expensive as when
  measured alone. With the ticks' shared part (CB-2) the batch is 21.7 M to 28.3 M. A measurement of
  the full tick in a batch decides it (ENG-07, CBT-*); design/02 item 6 cannot be answered by
  interfaces (E-13). Until then, **keep 40 M and weight 10**; if the ticks prove near their cost
  alone, weight 9 (36.7 M to 42.6 M) or a bound of 47 M.
- A reveal at weight 2 costs about 1.4 M: E-12 is unchanged.

### 10.2 The expedition (D-129)

S1 (cost-budget.md §3, 300 actions) with this design, E:
- **About 30 batches.** A typical fight batch writes 29 slots: header, entropy, member 4, 8
  goblins × 2, roster 1, features 1, report 5. That is 17 more than the 12 the estimate assumed
  (+0.55 M a batch), plus about 3 kills of events (+0.2 M): **+22.4 M**.
- `enter` 3.71 M instead of 3.56 M measured: +0.15 M. `leave` 1.93 M instead of 1.66 M: +0.27 M.
- **S1 ≈ 608.2 + 22.4 + 0.4 = 631.0 M ≈ $0.556** at cost-budget's prices (the best row of §3 was
  $0.537).
- **An adventurer's first expedition adds its lifetime initialisation as it goes** (E): the entry's
  19 new keys (+8.04 M over an initialised entry); about 40 goblins woken for the first time (80
  words, +33.7 M); 4 roster pages first used (+1.7 M); about 20 chunks revealed for the first time
  (40 words, +16.9 M). Together **+60.3 M, about $0.053, once**.
- Whether S1 meets $0.50 still turns on CB-2 (a tick inside a batch).

---

## 11. Escalations (review points (a) and (b), fix loops 1 and 2)

Each is a choice the documents do not settle, or where cost departs from a design rule. The code
follows the **default** named; the project manager decides.

| # | Question | Options, with their cost | Default in the code |
|---|---|---|---|
| **E-1** (recomputed, fix loop 2) | **A goblin's first key in a slot costs N** (2 words: 0.84 M over O). Cold, a capped batch adds **+14.33 M** (32 goblin words and 2 roster pages first used) that no weight counts. The key is cold whenever this slot never woke that goblin index, in any generation (§9.1) | (a) **weigh it**: +1 per goblin record written for the first time in the slot (the contract reads the record as 0); (b) **one word per goblin** (drop `GoblinTimers`: loses conditions and the effect): a cold goblin costs 0.45 M, and a 3-tick action in a cold slot 38.97 M instead of 56.76 M (E-21); (c) accept | none yet (ENG-07's weight); **(a) for batches, with (b) if E-21 (a) is chosen** |
| **E-2** | **The roster holds 60 entries**: displaced goblins, alive or dead and not looted (F-6). Design/02 bounds awake goblins, not displaced ones or unlooted remains | (a) 60, four pages, only pages in use are written; (b) no roster: scan the touched records of every revealed chunk (up to 2,250 records a view, and a tick cannot find followers cheaply) | (a). **The rule for a 61st** (a goblin that would be displaced, or would die away from its spawn, with the roster full) is a game rule to decide: it stays in its first state? its remains are not left? |
| **E-3** | At most 2 packs of 5 and 3 objects per chunk (the features word) | a third pack or a fourth object: a third chunk word (+1 slot a reveal) | 2 / 5 / 3; ENG-05 caps |
| **E-4** (corrected, fix loops 1 and 2) | **Every deadline is at most `MAX_CLOCK` = 2^28 − 1**, not only the clock. An action runs only while `clock ≤ LAST_TICK = MAX_CLOCK − MAX_DURATION − 10`. `MAX_DURATION` = 65,535 is the widest **effective** duration: the registry holds bases of at most 43,688 ticks, the modifiers' percents are capped at +50 % and their flat bonuses at +3 (F-9, `durations.cairo`), so the effective maximum is exactly 65,535 (tested). The packers refuse a deadline above `MAX_CLOCK` or 2^28 (tested) | 32-bit deadlines: recharges need 2 slots a member | 2^28 − 1; an action past `LAST_TICK` is invalid (268,369,910 ticks: 8.5 years at a tick a second) |
| **E-5** | The ephemeral domain reads the registry during play (content, not a persistent model); a content update during an instance changes outcomes | (a) one `bundle` call an invocation (0.14 M); (b) mirror play's content in `Instances`; (c) (a) plus a content version checked at every invocation | (a) |
| **E-6** | `barter` calls the hub during play (the price is in the pack) | (a) `Hub.barter` in the transaction; (b) snapshot trophies at entry (+1 member word); (c) barter in hubs only | (a) |
| **E-7** | **`enter` exceeds 1.9 M**: 3.71 M initialised (the belt's reserve, the snapshot's bundle, two events); 11.75 M cold | the snapshot travelling as calldata against a hash (−3 slots), at the price of `instance_state` no longer holding it (design/02) | stored snapshot; target 3.71 M |
| **E-8** (recomputed, fix loop 2) | **The standalone actions have their own union bounds**, not play's cap (F-3). **`loot`**: 0 ticks, a draw: 3.66 M for a boss's three items, 2.17 M for ordinary remains, against 2.9 M. **`open`**: 1 tick then a draw: 10.05 M with goblins near (25.23 M cold), 2.44 M without. **`mine`**: up to 3 ticks, no draw, 42 goblins in its union: **20.24 M** initialised with goblins near, **57.32 M cold** (88 new, 16 other); with the cap of 16 applied to it, 16.86 M and 31.61 M cold (35 new, 17 other; 33 new, 19 other when its two roster pages were already used); 2.31 M with no goblin near. **`barter`**: 1 tick: 8.92 M with goblins near (21.56 M cold), 2.60 M without | the 2.9 M budget holds only with no goblin near. A cold `mine` among goblins passes 40 M: it cannot be split, so it follows E-21 | per action, §10; E-21 |
| **E-9** | Version 1's Fate needs a request and a later draw | a provider that keeps requests, or a two-phase `loot` | ADR-0002's |
| **E-10** | **Class sizes in CI**: `python3 contracts/tools/class_sizes.py` after the build, in `.github/workflows/ci.yml` | — | **the orchestrator's (F-11)**: added by the orchestrator to this pull request before merge |
| **E-11** | Market: lots are new slots (ids never reused, SPK-11); a trade side ≤ 7 entities and ≤ 2 balances | reuse lot slots per account (−0.42 M a posting) | new slots; 7 / 2 |
| **E-12** | A reveal weighs 2 but costs 1.4 M (0.6 M after its first time) | weight 1 after ENG-05's measurement | 2 |
| **E-13** | design/02's tests that need game logic: batch = singles = multicall (item 5), the gas bound with the full execution and a revealed chunk measured (item 6), restart, window crossing, reveal, unrevealed and boundary (item 8), and the view cases of the fix loops: **(F-6)** a goblin killed away from its spawn chunk, then a restart: `instance_region` of the chunk where it lies shows its remains; after `loot`, they are gone. **(F-13)** an earlier generation fills roster page 0; the new one has one entry: `instance_state` and `instance_region` show that entry and zeros in every other lane. **(F-12)** an instance with conditions, effects and recharges running leaves through a gate: the new instance's member has none, and its belt counts are the reserve's | ENG-05, ENG-06, ENG-07 | out of this task (the masking helper is tested: `test_roster_masking`) |
| **E-14** | quiver's components are not embedded (ARC) | — | ARC-03c/04 |
| **E-15** (F-1) | **What happens to the belt's unused potions on defeat.** The reserve is debited at entry and credited back unused at the closing report; what is consumed is gone (the orchestrator's ruling). design/03 and design/07 do not settle defeat for the belt: design/07 says loot is kept on defeat, and design/02's D-04 says defeat costs "the instance, nothing else" | (a) **credited back on defeat as on return** (D-04's reading: the potions are not loot but were not used); (b) **lost on defeat** (the belt is part of what the instance costs); (c) lost only in a sealed Red Rift. Cost: (a) and (c) write ≤ 4 pack pages at defeat (0.13 M); (b) none | **stopped, as the ruling asks.** The interface carries the counts (`Results.belt`) whatever the rule; the hub's rule waits for the decision |
| **E-16** (F-2) | **The union of goblins an invocation can change is 140** in a batch (10 ticks × 14): 280 words, 8.98 M initialised, 127 M cold; 42 in a single 3-tick action | (a) **a cap of 16 distinct goblin records an invocation**: the batch stops before the action that would pass it (`Stop::Weight`), counted by the client as by the contract (steady state: 56 slots, §10.1); (b) cap 24: **+513,152** a batch (16 more words at O); (c) no cap: 40 M cannot hold. The first action of an invocation is E-21's | none (a rule of `play`, ENG-07); **(a) recommended** |
| **E-17** (F-7) | **The per-action events cost** 56,740 per `GoblinKilled` and 40,048 per `ChunkRevealed` (snforge, M; about ×1.157 on Sepolia): up to 1.1 M a batch at 16 kills, about 2.6 % of the bound; 0.2 M in a typical fight batch | (a) keep all three (restored, the ruling); (b) drop `GoblinKilled` (the client reads the dead goblin by view; −1.05 M a worst batch) | (a): restored, frozen, tested |
| **E-18** (F-3) | **`mine` draws nothing** (design/17) but design/02 sends it alone as a Fate action | (a) standalone, as frozen (it runs its 3 ticks outside any batch; one more transaction floor, 0.82 M, per vein); (b) an *Interact* on a vein inside `play` (weight 3), saving the floor | (a) |
| **E-19** | `set_account_owner` zeroes `account_of[old owner]`; if that address ever owns an account again, its key is new (N) | keep a tombstone (the old owner mapped to a sentinel, O) | zeroed: rare |
| **E-20** (F-12) | **What of a member carries across a gate** within one expedition (to the next zone, the next floor). The ruling: nothing but the belt's reserve; the design does not say (design/02: "each floor is its own instance entered from the previous one") | (a) **nothing** (the ruling; the code's rule); (b) **health, energy, adrenaline carry**: plain values, no clock conversion; (c) **conditions, effects and recharges carry too**: each deadline `d` becomes `max(0, d − clock_old)` on the new clock 0 (the ticks left), then capped at `MAX_DURATION`. Cost: none of the three changes the writes, since the same 4 member words are written in any case (§9.3); (b) and (c) change the game | (a); escalated for the design (whether a descent heals) |
| **E-21** (F-2, F-3) | **One action that cannot be split** passes the batch's cap or cold weight by itself: a 3-tick action (a 3-tick skill, `mine`) changes up to 42 goblins; in a cold slot it writes 84 new goblin words | (a) **it runs**: the cap and the weight bind from the second action on; its class's bound is its own, 20.10 M initialised, **56.76 M cold** (38.97 M with E-1 b); (b) **it is refused**: a player among many goblins cannot use a 2- or 3-tick action, and in a cold slot the keys warm only by running, so a refused action can stay refused (a stall) | none (ENG-07); **(a) with E-1 (b) recommended**: no stall, every invocation under 40 M |

---

## 12. Answers to design/02's "What ENG-01 must do" and to the PLAN row (AC-1)

| Item | Answer |
|---|---|
| 1. `Instance.sequence` | `Header.sequence` (32 bits): §4.1 semantics; `create` at 0; `leave` to a location → a new id at 0 in the same slot |
| 2. `play` | Signature, batch encoding, stops and `BatchPlayed` frozen (§4.1, §5); code ENG-07 |
| 3. Loot, open, mine, leave, travel back | Signatures with `sequence`; preconditions before `fate`; `Refused` with `Refusal`; draw and consumption in one invocation; each action's ticks, draw and interruption (§4.1, F-3) |
| 4. No stop condition in the contract | None in the interface (§4.1) |
| 5. Batch = singles = multicall tests | E-13 |
| 6. Prove the gas bound | §9.2 per tick, per batch and lifetime; §10.1 in slots and with measured parts; the proof with the full execution: E-13, E-1, E-12, E-16 |
| 7. `instance_state` | `InstanceView`, one call, the stored words (§4.1) |
| 8. `instance_region` | `RegionChunk`, page of 16 chunks, kinds Void / Unrevealed / Revealed (§4.1); remains away from their spawn chunk through the roster, read masked (§9.3, F-6, F-13); tests, with the cross-chunk death and restart and the masking case: E-13 |
| 9. Permission | §1.2, M-6 |
| OP-2 | §9, §10 |
| PLAN: domains | §1; no storage struct mixes them (§3) |
| PLAN: snapshot and results | §6 |
| PLAN: storage layouts and packing | §3; tested (`test_*_layout`, `test_*_storage_addresses`) |
| PLAN: registry shapes | §3.5 |
| PLAN: nine events, `open_lot_count`, `trade_count` | §5 |
| PLAN: 16 task ids (D-131) | `create.tasks`, `TaskPage`, `Header.tasks` |
| PLAN: access control between contracts | §1.2 |
| PLAN: contracts against the class size | §1.3 |
| PLAN: slots each entrypoint changes | §9.3: every public selector, cold and initialised |
| PLAN: D-135 | held quests ≤ 4 (§4.5) |
| PLAN: D-136 | a chunk outside `revealed` is never read (§2.1); `ChunkKind` (§4.1) |
