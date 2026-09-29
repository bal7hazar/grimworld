# ENG-01 — The core interfaces, frozen under a cost budget

| | |
|---|---|
| Status | Frozen by ENG-01 (2026-09-29), `[Opus 5.5]`. **Fix loop 1** after the `[GPT-6-Astra]` audit (FAIL, 6 majors): the belt's reserve (§6), per-batch and lifetime bounds (§9.1–9.2), the standalone actions by their behaviour (§4.1), every selector's complete write set, cold and initialised (§9.3), the per-action events restored (§5), remains through the roster (§9.3), registry allocation (§3.5), bounded deadlines and packers (§3.1), a validating encoder (§4.1). The escalations of §11 are open |
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
| `members[(slot, m)]` | `header.members` (members beyond the count are never read) | `create`, all eight words |
| `roster[(slot, page)]` | `header.roster_count`: a compact list (removal moves the last entry into the hole), entries beyond the count are never read | nothing at `create`: the count is reset to 0 there, so stale lanes are unreachable without a write |
| `chunks[(slot, c)]` | bit `c` of `revealed`: a chunk not revealed in this generation is never read (wall, D-136) | its reveal, both words |
| `goblins[(slot, e)]` | its spawn chunk revealed **and** bit `k` of that chunk's `touched` (the roster lists only goblins that pass this gate) | the chunk's reveal clears `touched`; the roster's count is reset at `create` |
| `placements[adventurer]` | the adventurer id (its reference to its instance, not instance state) | `create`, `leave` |

So a generation is **not** in any key (it would make every key new and defeat the rule), and not in
any record but the header: the gates above are rewritten in the same invocation that bumps it.
The security lens checks one invariant: *no read of a slot's record that does not first pass the
header's generation and the gate of the table*. The views (`instance_state`, `instance_region`)
apply the same gates: an id of an earlier generation, or a chunk outside `revealed`, returns no
stored word.

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
| `mine` | 3 (design/17), an activation | **none** (design/17: 1 stillstone, no draw; E-18) | a hit taken during the 3 ticks interrupts it: the vein stays, no stone | the 3 ticks' writes, the vein's state when completed | 1 stillstone; mine tasks |
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

## 9. What an invocation can touch (scope 2, AC-2; fix loop 1, F-2, F-4)

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

| Record | Union bound without a cap | With the cap of E-16 (16 goblins a batch) | Why |
|---|---:|---:|---|
| Goblin records | 140 (280 words) | 16 (32 words) | 10 ticks × 14. The goblins present in the union of the windows (at most 9 chunks, since 10 moves shift a 15 × 16 window by at most 10 tiles each way) × 10 spawns + the roster's 60 = 150 do not bound it lower |
| Chunk `features` | 9 | 9 | the chunks of the union of windows |
| Chunk `terrain` (reveals) | 4 | 4 | weight |
| Roster pages | 4 | 2 | 60 entries; 16 displacements reach at most 2 pages |
| Header, entropy, revealed, quotas | 4 | 4 | |
| Member words | 4 | 4 | |
| Hub `report` | 5 | 5 | core (experience, `pack_lanes`), quiver's held quests ≤ 4 |
| **Words** | **310** | **60** | |
| Events | ≤ 140 `GoblinKilled`, ≤ 4 `ChunkRevealed`, ≤ 1 `Defeated`, 1 `BatchPlayed` | ≤ 16, ≤ 4, ≤ 1, 1 | |

Without a cap on goblins, a batch's writes are bounded only by 280 goblin words: 8.98 M at O
initialised, 127 M at N cold. **E-16** proposes the cap, **E-1** the weight of a cold goblin key.

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

That is the bound. Real exposure is smaller: every location of a slot shares the same chunk indexes
(`15 cy + cx`, from the grid's origin), so Region 1's locations of at most 7 × 7 chunks use 49
indexes. That is 49 × 22 + 21 = 1,099 keys (498 M, $0.44) over the adventurer's life, paid as
first uses.

### 9.3 Every public entrypoint: its complete write set

Columns: the reads; every key written; **cold** new / overwritten (N / O) when the keys the row
names were never written; **initialised** N / O when they were. The fee token's 2 balances are in
F. `C` is the number of calls to other contracts. Counters are `Counter` records with `LIVE`, so an
allocation counter is always O, never N, and a count that falls to 0 and rises again stays O.

**`Instances`**

| Entrypoint | Reads | Writes | Cold N / O | Initialised N / O | C |
|---|---|---|---|---|---:|
| `create` (by `Hub.enter`) | gate, location, outline (1 `bundle`); placement | `next_slot` (first entry only) · placement · header · entropy · revealed · quotas · task pages `⌈t / 4⌉` (t ≤ 16; pages are written as needed, never initialised ahead) · member 8 words · entry chunk 2 words. The roster is **not** reset: it is a compact list gated by `header.roster_count` (0 at entry), so stale lanes are never read | **17 + ⌈t/4⌉ ≤ 19 / 1** | **0 / 19** (≤ 5 N: an entry chunk index or task pages never used in this slot) | 2 (registry, fate) |
| `play` | §9.2 | §9.2 | ≤ 40 / 20 with E-16 (≤ 288 / 22 without) | 0 / ≤ 60 (≤ 310 without) | 2 |
| `loot` (0 world ticks, Fate) | header, member, goblin, its spawn chunk, roster; loot table | header · entropy · goblin state (`LOOTED`) · roster page (removed, if displaced) | 0 / 4 | 0 / 4 | 2 (fate, hub `report`) |
| `open` (a chest: 1 world tick, then Fate) | + one tick's reads | + one tick (§9.2 per tick: ≤ 28 goblin words, ≤ 4 features, member 4, roster ≤ 1) + the chest's object state | ≤ 28 / 10 | 0 / ≤ 38 | 3 (registry, fate, hub) |
| `mine` (a vein: 3 world ticks, interrupted by a hit, **no draw**, design/17) | + three ticks' reads | three ticks: union ≤ 42 goblins (≤ 16 with E-16) · features ≤ 4 · member 4 · header, entropy · roster ≤ 3 · the vein's state if completed | ≤ 32 / 14 with E-16 | 0 / ≤ 46 with E-16 | 2 (registry, hub) |
| `barter` (1 world tick, design/04 *Interact*) | + one tick; collector (registry) | one tick (as `open`) | ≤ 28 / 10 | 0 / ≤ 38 | 3 (registry, hub `barter`, hub `report`) |
| `leave` / `travel_back` to a hub | header, member, placement | header (status) · placement · member state (gone) | 0 / 3 | 0 / 3 | 1 (hub `report`) |
| `leave` through a gate to a location | + the next gate and location | as `create` in the same slot: placement · header · entropy · revealed · quotas · member state (position) · entry chunk 2 words. The snapshot and task words carry over unchanged (a write of the same value changes nothing) | ≤ 2 / 7 | 0 / 9 | 3 (registry, fate, hub) |
| `set_controller` (by `Hub`) | placement | member's `controller` | 0 / 1 | 0 / 1 | — |
| `set_contracts`, `set_admin`, `upgrade` | admin | ≤ 3 addresses; the class | 0 / ≤ 3 | 0 / ≤ 3 | — |

The hub's side of the calls, added to each transaction:

| Hub call | Writes | Cold N / O | Initialised N / O |
|---|---|---|---|
| `Hub.enter` (before `create`) | place (instance id, inside) · the belt's reserve: pack balance pages of the belt items, at most 4 distinct pages (two slots of the same item are one debit of their sum, one page) · core (`pack_lanes`, when a lane falls to 0) | 0 / ≤ 6 | 0 / ≤ 6 |
| `report`, Open (a batch with a kill, an objective) | core (experience, merit, level) · quiver's held quests ≤ 4 | 0 / ≤ 5 | 0 / ≤ 5 |
| `report` of a loot or a chest (drops: ≤ 3 balances, gold, ≤ 3 equipment for a boss, 1 otherwise) | balance pages ≤ 3 · pack gold · each equipment item: base (a new entity: always N) and `next_item` · pack list pages ≤ 2 · core (`pack_lanes`) · account counter (Scavenger, design/13) · quiver ≤ 4 | ≤ 10 / 6 | ≤ 3 / 13 (the entities) |
| `report` of a mine | stillstone page · core · quiver ≤ 4 | ≤ 1 / 5 | 0 / 6 |
| `barter` | pack pages of the price ≤ 2 · the item given: base (N) + `next_item` + pack list page · core | ≤ 2 / 4 | 1 / 5 |
| `report`, closing (Returned, Defeated) | place · core · **the unused belt credited back**: pack pages ≤ 4 (F-1; on defeat per E-15) | 0 / ≤ 6 | 0 / ≤ 6 |
| `report`, Moved | place (the new id) · core | 0 / 2 | 0 / 2 |

**`Hub`**

| Entrypoint | Bounds | Reads | Writes | Cold N / O | Initialised N / O | C |
|---|---|---|---|---|---|---:|
| `register` | one per address | `account_of` | `account_of` · account owner · account record · `next_account` | 3 / 1 | — (once) | — |
| `set_account_owner` | the account's adventurers ≤ 7 (one page) | account, its adventurers' places | owner · `account_of[new]` · `account_of[old]` (set to 0: see E-19) · per adventurer inside: `Instances.set_controller` | 1 / 2 + 1 per inside | 1 / 2 + 1 per inside | ≤ 7 |
| `create_adventurer` | account slots | account | adventurer 6 words · `next_adventurer` · account record · account list page | 7 / 2 (6 / 3 once the page exists) | — (once) | — |
| `delete_adventurer` | pack empty: `pack_lanes` = 0 and pack list pages ≤ 4 empty | core, pack lists | core (deleted) · account record · account list page | 0 / 3 | 0 / 3 | — |
| `set_build` | bar 8, attributes 9, belt 4 items and 4 counts (lane 4 of `belt`: 4 × u8), 7 equipped | known skills, items ≤ 7 | build · belt · equipped | 0 / 3 | 0 / 3 | — |
| `enter` | as `create` | as above | hub part + `create` | ≤ 19 / 7 | 0 / 25 | 1 + 2 |
| `enter_rift` | index 0–4 | board | board (the first action of the day: its draw) + `enter` | ≤ 20 / 7 | 0 / 26 | 1 + 3 |
| `travel` | unlocked hubs | place | place | 0 / 1 | 0 / 1 | — |
| `accept_quest` | ≤ 4 held (D-135) | quiver, quest (registry) | quiver held record · known skills page (skills given at acceptance, design/14) | 2 / 0 | 0 / 2 | — |
| `abandon_quest` | | quiver | quiver held record | 0 / 1 | 0 / 1 | — |
| `accept_contract` | index 0–2, one held | quiver, the day's pool (registry) | quiver held record | 1 / 0 | 0 / 1 | — |
| `claim_quest` | | quiver, quest | core · pack gold · balance page · a reward item (base N, `next_item`, pack list) · known skills page · quiver 2 · the "distinct" counter (Warden) | 5 / 5 | 1 / 9 | — |
| `claim_title` | | counters, quiver | quiver's claim record (event mode) | 1 / 0 | 1 / 0 (each claim once) | — |
| `display_title` | earned | counters | nothing (event only, T-1) | 0 / 0 | 0 / 0 | — |
| `buy_skill` | | known skills, gold, shop | known skills page · pack gold | 1 / 1 | 0 / 2 | — |
| `buy` | quantity | shop, gold | gold · balance page; or an item: base (N) + `next_item` + pack list page · core | 3 / 3 | 1 / 4 | — |
| `sell` | | item or page | gold (N at the first income) · balance page, or item base (owner none) + pack list · core | 1 / 3 | 0 / 4 | — |
| `craft` | | shop, material pages | material pages ≤ 2 · gold · item base (N) · `next_item` · pack list · core | 2 / 5 | 1 / 6 | — |
| `recycle` | | item | item base · pack list · material pages ≤ 2 · core | 2 / 3 | 0 / 5 | — |
| `personalise` | | item | item base (flag) · stillstone page · gold | 0 / 3 | 0 / 3 | — |
| `identify` | unidentified | item | item base (`IDENTIFIED`) · item mods (they come to exist: N) · gold | 1 / 2 | 1 / 2 (each item once) | 1 (fate) |
| `lift_modifier` | slot 0–4 | item | item mods (or item base: destroyed) · the component: base + mods (N, N) · `next_item` · pack list · stillstone page (with a stone) | 2 / 4 | 2 / 4 | 1 (fate, without a stone) |
| `set_modifier` | | item, component | item mods · component base (consumed) · the returned component (with a stone): base + mods (N, N) · `next_item` · pack list · stillstone page | 2 / 5 | 2 / 5 | — |
| `brew` | a pair of one book | grimoire, book (registry), pages | grimoire state and pairs · ingredient pages ≤ 2 · potion page · core | 3 / 3 | 0 / 6 | 1 (fate, new pair) |
| `buy_hint` | 4 hints a book | grimoire | grimoire state · stillstone page | 0 / 2 | 0 / 2 | 1 (fate) |
| `stow` | ≤ 8 entities, ≤ 8 balances | pages | item bases (owner) ≤ 8 · pack lists ≤ 4 · vault lists ≤ 2 · pack pages ≤ 8 · vault pages ≤ 8 · gold both · core | **11 / 22** (an empty vault: 2 list pages, 8 balance pages, its gold) | 0 / 33 | — |
| `report`, `barter` (by `Instances`) | §6 | — | the table above | | | — |
| `seller`, `escrow`, `release`, `transfer_gold`, `exchange` (by `Market`) | as the market rows | | counted in the market rows | | | — |
| `set_contracts`, `set_admin`, `upgrade` | admin | | ≤ 4 addresses; the class | 0 / ≤ 4 | 0 / ≤ 4 | — |

**`Market`**

| Entrypoint | Bounds | Writes | Cold N / O | Initialised N / O | C |
|---|---|---|---|---|---:|
| `post_lot` | 10 + rank lots; Tin | lot (a new id: always N) · `lot_count` · `open_lot_count` · seller page · hub: pack page, or item base (owner escrow) + pack list · escrow page (owner id 0, contract-wide) · vault gold (the 2 % fee) · account record (open lots) · core | 3 / 7 | 1 / 9 | 3 (seller, escrow, gold) |
| `buy_lot` | the asked price | lot · `open_lot_count` · seller page · hub: buyer's vault gold · seller's vault gold · escrow page · buyer's vault page, or item base + vault list · seller's account record | 4 / 6 | 0 / 10 | 3 |
| `withdraw_lot`, `return_lot` | open; expired for `return_lot` | lot · `open_lot_count` · seller page · escrow page · vault page, or item base + vault list · account record | 1 / 6 | 0 / 7 | 2 |
| `open_trade` | invited in the same hub | trade head (a new id: N) · `trade_count` | 1 / 1 | 1 / 1 | 1 |
| `set_trade_side` | ≤ 7 entities, ≤ 2 balances, gold | head (revision, confirmations reset) · the side's 2 words | 2 / 1 | 0 / 3 | 1 |
| `confirm_trade`, first | the revision seen | head | 0 / 1 | 0 / 1 | 1 |
| `confirm_trade`, second (the swap) | | head · hub: item bases ≤ 14 · pack lists ≤ 4 · balance pages ≤ 8 · gold 2 · cores 2 | 5 / 26 | 0 / 31 | 1 |
| `decline_trade`, `cancel_trade` | the invited account; the inviter | head | 0 / 1 | 0 / 1 | ≤ 1 |
| `set_contracts`, `set_admin`, `upgrade` | admin | ≤ 2 addresses; the class | 0 / ≤ 2 | 0 / ≤ 2 | — |

**`Registry`**: `set_record` writes `parts(kind)` ≤ 3 words and `last_ids` for a sequential kind
(N the first time a kind is written, then O): **≤ 4 / 0** cold, **≤ 3 / 1** once the kind exists.
`set_admin`, `upgrade`: 0 / ≤ 1. **`TxHashFate.fate`** writes nothing.

**Views** (no transaction; reads bound what a node's call must allow):

| View | Bound | Reads |
|---|---|---:|
| `Instances.instance_state` | 1 member in the MVP (8 with a party), its window's 4 chunks, the roster | header, entropy, revealed, quotas, ≤ 4 task pages, 8 member words, ≤ 4 roster pages, ≤ 60 roster records × 2, 4 chunks × 2, ≤ 40 touched records × 2: **≤ 223** |
| `Instances.instance_region` | ≤ 16 chunks | 16 chunks × 2, their touched records ≤ 160 × 2, the roster (to find displaced goblins and remains lying in the range, F-6) ≤ 4 + 60: **≤ 416** |
| `Instances.placement` | | 1 |
| `Hub.counters` | ≤ 32 ids a call | 32 |
| `Hub.balances` | ≤ 32 pages a call; the client names the pages of the items it knows of (the registry lists items); no view enumerates an owner's pages | 32 |
| `Hub.pack`, `Hub.vault` | 4 pages; 4 a pane × ≤ 8 panes | 4; 32 |
| `Hub.adventurer`, `account`, `item`, `grimoire`, `rift_board`, `gold`, `account_of`, `known_skills` | fixed | ≤ 6, ≤ 3 + 1 page, 2, 3, 1, 1, 1, ≤ 1 page (skill ids < 250 in the MVP) |
| `Hub.quests` | ≤ 4 held | quiver's |
| `Market.lot`, `lot_count`, `open_lot_count`, `trade_count`, `trade`, `lots_of` | `lots_of` ≤ 7 pages | 1, 1, 1, 1, 5, ≤ 7 |
| `Registry.record`, `records`, `bundle` | `records` and `bundle` ≤ 32 records | ≤ 3 × 32 |

**Remains lying away from their spawn chunk (F-6).** A goblin displaced from its spawn stays in the
roster alive **and** dead, until it is looted or goes home (only the living go home). A view finds
it there: `instance_region` reads the roster (≤ 4 pages, entries beyond `header.roster_count` never
read) and each listed goblin's state word, and keeps those whose tile lies in the requested chunks.
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

`L2 ≈ F + computation + C × 136,000 + N × new + O × overwritten + events`. Computation is E (the
basis in the row); events are priced from `EventProbe` (§5: 56,740 per `GoblinKilled`, 40,048 per
`ChunkRevealed` in snforge, × 1.157 on Sepolia, E). The **target** of a row is its worst case in the
state named.

| Entrypoint | Computation (E) | Initialised: N / O → **target** | Cold: N / O → **target** | Against cost-budget.md |
|---|---:|---|---|---|
| `enter` (with `create`) | 1.45 M: checks, snapshot, entry draw, the entry chunk's generation 0.39–0.45 M (SPK-7, M) | 0 / 25 → **3,480,000** | 19 / 7 → **11,520,000** (once per adventurer) | 1.9 M reused (E): **departs** +1.58 M (E-7); 3.6 M cold: departs, but paid once, where the spike paid 4 N at every entry |
| `leave`, `travel_back` | 0.60 M | 0 / 9 → **1,850,000** | same | 1.7 M: **departs** +0.15 M, the belt's credit (F-1) |
| `leave` through a gate | 1.90 M | 0 / 11 → **3,480,000** | 2 / 9 → **4,320,000** | new row |
| `play`, weight 10 | §10.1 | 0 / 60 → **40,280,000 to 46,830,000** (ticks as alone); 21,690,000 to 28,240,000 (ticks shared) | with E-1: no worse than initialised | 40 M target: §10.1 |
| `loot` | 0.50 M; 0 ticks | 3 / 17 → **3,500,000** (a boss: 3 items) | 10 / 10 → **6,450,000** | 2.9 M: **departs** (E-8) |
| — `loot`, ordinary remains (ingredients and gold) | 0.50 M | 0 / 10 → **1,910,000** | 4 / 6 → **3,600,000** | meets initialised |
| `open` (chest: 1 tick + draw) | 0.50 M + one tick 3.57 M (M) + window ≤ 0.72 M | 3 / 51 → **9,010,000** | 38 / 16 → **23,760,000** (a fresh slot: 14 goblins' first records) | new row (E-8) |
| — `open` with no goblin near | 0.50 M + 0.30 M | 1 / 14 → **2,930,000** | 5 / 10 → **4,610,000** | ≈ 2.9 M |
| `mine` (3 ticks, no draw) | 3 × (3.57 + ≤ 0.72) M | 0 / 52 → **15,610,000** (with E-16) | 32 / 20 → **29,100,000** | new row (E-8, E-18) |
| — `mine` with no goblin near | 3 × 0.30 M | 0 / 10 → **2,310,000** | 1 / 9 → **2,730,000** | meets |
| `barter` (1 tick) | 0.40 M + one tick | 1 / 43 → **7,740,000** | 30 / 14 → **19,970,000** | new row |
| — `barter` with no goblin near | 0.70 M | 1 / 11 → **2,730,000** | 2 / 10 → **3,150,000** | new row |
| `register` | 0.20 M | — | 3 / 1 → **2,410,000** | once per address |
| `set_account_owner` | 0.20 M | 1 / 9 (7 inside) → **2,710,000** | same | new row (E-19) |
| `create_adventurer` | 0.30 M | 6 / 3 → **3,930,000** | 7 / 2 → **4,360,000** | once per adventurer |
| `delete_adventurer` | 0.20 M | 0 / 3 → **1,120,000** | same | |
| `set_build` | 0.30 M | 0 / 3 → **1,220,000** | same | meets 2.0 M |
| `enter_rift` | 1.55 M | 0 / 26 → **3,750,000** | 20 / 7 → **12,210,000** | as `enter` |
| `travel` | 0.10 M | 0 / 1 → **950,000** | same | meets |
| `display_title` | 0.05 M | 0 / 0 → **870,000** | same | meets |
| `accept_quest` | 0.40 M | 0 / 2 → **1,280,000** | 2 / 0 → **2,130,000** | 1.57 M measured (SPK-2, 1/0): meets 2.0 M initialised |
| `abandon_quest`, `accept_contract` | 0.30 M | 0 / 1 → **1,150,000** | 1 / 0 → **1,570,000** | meets |
| `claim_quest` | 0.60 M | 1 / 9 → **2,160,000** | 5 / 5 → **3,850,000** | 2.0 M: **departs** by 0.16 M initialised (the reward item is always a new entity) |
| `claim_title` | 0.40 M | 1 / 0 → **1,680,000** | same | meets |
| `buy_skill` | 0.20 M | 0 / 2 → **1,090,000** | 1 / 1 → **1,510,000** | meets |
| `buy` | 0.30 M | 1 / 4 → **1,700,000** | 3 / 3 → **2,580,000** | meets initialised |
| `sell` | 0.30 M | 0 / 4 → **1,250,000** | 1 / 3 → **1,670,000** | meets |
| `craft` | 0.30 M | 1 / 6 → **1,770,000** | 2 / 5 → **2,190,000** | meets |
| `recycle` | 0.30 M | 0 / 5 → **1,280,000** | 2 / 3 → **2,120,000** | meets |
| `personalise` | 0.30 M | 0 / 3 → **1,220,000** | same | meets |
| `identify` | 0.35 M | 1 / 2 → **1,830,000** | same | meets 2.9 M |
| `lift_modifier` | 0.35 M | 2 / 4 → **2,340,000** | same | meets |
| `set_modifier` | 0.35 M | 2 / 5 → **2,240,000** | same | meets |
| `brew` | 0.50 M | 0 / 6 → **1,650,000** | 3 / 3 → **2,910,000** | 2.8 M: **departs** by 0.11 M on a book's first brew (the potion's page is also new) |
| `buy_hint` | 0.35 M | 0 / 2 → **1,370,000** | same | meets |
| `stow` | 0.40 M | 0 / 33 → **2,280,000** | 11 / 22 → **6,920,000** (an empty vault) | new; bounded by 8 + 8 |
| `post_lot` | 0.30 M | 1 / 9 → **2,270,000** | 3 / 7 → **3,110,000** | new |
| `buy_lot` | 0.30 M | 0 / 10 → **1,850,000** | 4 / 6 → **3,530,000** | new |
| `withdraw_lot`, `return_lot` | 0.30 M | 0 / 7 → **1,610,000** | 1 / 6 → **2,040,000** | new |
| `open_trade` | 0.30 M | 1 / 1 → **1,740,000** | same | new |
| `set_trade_side` | 0.20 M | 0 / 3 → **1,250,000** | 2 / 1 → **2,090,000** | new |
| `confirm_trade`, the swap | 0.80 M | 0 / 31 → **2,750,000** | 5 / 26 → **4,860,000** | new; 7 + 7 items |
| `confirm_trade` (first), `decline_trade`, `cancel_trade` | 0.10 M | 0 / 1 → **1,090,000** | same | new |
| `Registry.set_record` | 0.05 M | 3 / 1 → **2,260,000** | 4 / 0 → **2,680,000** | administration |
| admin setters, `upgrade` | 0.10 M | 0 / ≤ 4 → **1,050,000** | same | administration |

`contracts/*/GAS.md` and `docs/BUDGETS.md` list the snforge figures of this task's tests (layouts,
packing, the batch's codec, the probes, deployments). None executes an entrypoint: those are the
implementing lots' benchmarks, each against its row above.

### 10.1 The 40 M bound of design/02, in slots and gas (OP-2, CB-3)

The worst batch is 10 world ticks with no reveal: a reveal takes weight 2 for about 1.4 M (0.45 M
generation, 2 words, its event), where two ticks take up to 8.6 M. With the cap of E-16:

| Part | Slots, initialised | L2 gas |
|---|---|---:|
| Floor, one call, 4 felts of arguments | — | 816,939 (D) |
| 10 ticks, each as measured alone (SPK-1 §4, M) | — | 35,649,130 |
| The window at each tick: 65,224 (in memory, M) to 720,000 (SPK-7's whole difference, M) | — | 652,240 to 7,200,000 |
| Writes, once per transaction (§9.2 with E-16, no reveal): goblins 32, features 9, roster 2, header and entropy 2, member 4, hub report 5 | 0 / 56 | 1,796,032 |
| Registry `bundle` and hub `report`: 2 calls | — | 272,000 |
| Events: 16 `GoblinKilled`, 1 `Defeated`, 1 `BatchPlayed` (E, from the probe) | — | 1,050,368 + 46,336 |
| **Total, ticks as alone** | **0 / 56** | **40,283,045 to 46,830,805** |
| **Total, ticks shared as a queue shares them** (1,705,764 a tick, E, cost-budget §3) | 0 / 56 | **21,691,555 to 28,239,315** |
| Without the cap of E-16 (140 goblins): 280 goblin words instead of 32 | 0 / 304 | + 7,953,856 |
| A cold slot, without E-1: 32 goblin words new | 32 / 24 | + 13,486,464 |

**What this settles, and what it does not.**
- **In slots: yes, with E-16.** 56 slots a batch initialised, none new; at most 40 new cold, each
  counted in the weight by E-1. Without a cap the union is 310 words (§9.2), and 40 M cannot be
  kept in a cold slot.
- **In gas: not proven, and now above 40 M even at the low end, if every tick is as expensive as
  when measured alone.** This fix loop adds 0.9 M of writes (the batch's union rather than one
  tick) and 1.1 M of events. With the ticks' shared part (CB-2) the batch is 21.7 M to 28.2 M. A
  measurement of the full tick in a batch decides it (ENG-07, CBT-*); design/02 item 6 cannot be
  answered by interfaces (E-13). Until then, **keep 40 M and weight 10**. If the measurement gives
  ticks near their cost alone, the recommendation is weight 9 (36.7 M to 42.5 M) or a bound of
  47 M.
- **E-1 (the first write of a goblin key weighs 1)** turns the cold case into a smaller batch:
  a cold goblin key costs 0.91 M for its 2 words, less than the ≥ 3.9 M of a tick it replaces.
- A reveal at weight 2 costs 1.4 M: E-12 is unchanged.

### 10.2 The expedition (D-129)

S1 (cost-budget.md §3, 300 actions) with this design, E:
- **About 30 batches** (100 fights in tens, 36 queues of 5 near goblins in tens, the other actions).
  A typical fight batch writes 29 slots: header, entropy, member 4, 8 goblins × 2, roster 1,
  features 1, report 5. That is 17 more than the 12 the estimate assumed: +0.55 M a batch. About 3
  kills a batch add 0.2 M of events. Together **+22.4 M**.
- `enter` 3.48 M instead of 3.56 M measured: −0.08 M. `leave` 1.85 M instead of 1.66 M: +0.19 M
  (the belt's credit).
- **S1 ≈ 608.2 + 22.4 + 0.1 = 630.7 M ≈ $0.556** at cost-budget's prices (the best row of §3 was
  $0.537). The difference is the goblins' two words and the events.
- **An adventurer's first expedition adds its lifetime initialisation as it goes**, E: the entry's
  19 N (+8.0 M over the initialised entry); about 40 goblins woken for the first time (80 words,
  +33.7 M); about 20 chunks revealed for the first time (40 words, +16.9 M). Together **+58.6 M,
  about $0.05, once**.
- Whether S1 meets $0.50 still turns on CB-2 (a tick inside a batch).

---

## 11. Escalations (review point (a) and (b), fix loop 1)

Each is a choice the documents do not settle, or where cost departs from a design rule. The code
follows the **default** named; the project manager decides.

| # | Question | Options, with their cost | Default in the code |
|---|---|---|---|
| **E-1** | **A goblin's first key in a slot costs N** (2 words: 0.91 M). Cold, 16 goblins in a batch add 13.5 M that no weight counts. The key is cold whenever this slot never woke that goblin index, in any generation (§9.1) | (a) **weigh it**: +1 per goblin record written for the first time in the slot (the contract reads the record as 0); (b) one word per goblin (drop `GoblinTimers`: loses conditions and the effect, saves 0.45 M a cold goblin); (c) accept | none yet (ENG-07's weight); **(a) recommended**: it keeps a cold batch below an initialised one |
| **E-2** | **The roster holds 60 entries**: displaced goblins, alive or dead and not looted (F-6). Design/02 bounds awake goblins, not displaced ones or unlooted remains | (a) 60, four pages, only pages in use are written; (b) no roster: scan the touched records of every revealed chunk (up to 2,250 records a view, and a tick cannot find followers cheaply) | (a). **The rule for a 61st** (a goblin that would be displaced, or would die away from its spawn, with the roster full) is a game rule to decide: it stays in its first state? its remains are not left? |
| **E-3** | At most 2 packs of 5 and 3 objects per chunk (the features word) | a third pack or a fourth object: a third chunk word (+1 slot a reveal) | 2 / 5 / 3; ENG-05 caps |
| **E-4** (corrected) | **Every deadline is at most `MAX_CLOCK` = 2^28 − 1**, not only the clock. An action runs only while `clock ≤ LAST_TICK = MAX_CLOCK − MAX_DURATION − 10` (`MAX_DURATION` = 65,535, the registry's widest duration, recharge or activation), so no deadline it sets can pass `MAX_CLOCK`. The packers refuse a deadline above `MAX_CLOCK` or 2^28, instead of spilling into the next lane (tested: `test_deadline_boundaries` and the refusal tests) | 32-bit deadlines: recharges need 2 slots a member | 2^28 − 1; an action past `LAST_TICK` is invalid (268,369,910 ticks: 8.5 years at a tick a second) |
| **E-5** | The ephemeral domain reads the registry during play (content, not a persistent model); a content update during an instance changes outcomes | (a) one `bundle` call an invocation (0.14 M); (b) mirror play's content in `Instances`; (c) (a) plus a content version checked at every invocation | (a) |
| **E-6** | `barter` calls the hub during play (the price is in the pack) | (a) `Hub.barter` in the transaction; (b) snapshot trophies at entry (+1 member word); (c) barter in hubs only | (a) |
| **E-7** | **`enter` exceeds 1.9 M**: 3.48 M initialised (with the belt's reserve, F-1); 11.52 M cold | the snapshot travelling as calldata against a hash (−3 slots), at the price of `instance_state` no longer holding it (design/02) | stored snapshot; target 3.48 M |
| **E-8** (corrected) | **The standalone actions are not one kind** (F-3). **`loot`**: 0 ticks, a draw; 3.50 M for a boss's three items, 1.91 M for ordinary remains, against 2.9 M. **`open`**: a chest is an *Interact* (1 tick, design/04), then a draw: up to 9.01 M with goblins near, 2.93 M without. **`mine`**: 3 ticks, no draw: up to 15.61 M with goblins near, 2.31 M without | the budget of 2.9 M holds only without goblins near; with them, a standalone action pays its ticks like a batch | per action, §10 |
| **E-9** | Version 1's Fate needs a request and a later draw | a provider that keeps requests, or a two-phase `loot` | ADR-0002's |
| **E-10** | **Class sizes in CI**: `python3 contracts/tools/class_sizes.py` after the build, in `.github/workflows/ci.yml` | — | **the orchestrator's (F-11)**: added by the orchestrator to this pull request before merge |
| **E-11** | Market: lots are new slots (ids never reused, SPK-11); a trade side ≤ 7 entities and ≤ 2 balances | reuse lot slots per account (−0.42 M a posting) | new slots; 7 / 2 |
| **E-12** | A reveal weighs 2 but costs 1.4 M (0.6 M after its first time) | weight 1 after ENG-05's measurement | 2 |
| **E-13** | design/02's tests that need game logic: batch = singles = multicall (item 5), the gas bound with the full execution and a revealed chunk measured (item 6), restart, window crossing, reveal, unrevealed and boundary (item 8), and **fix loop 1's view cases**: a goblin killed away from its spawn chunk, then a restart: `instance_region` of the chunk where it lies shows its remains; after `loot`, they are gone | ENG-05, ENG-06, ENG-07 | out of this task |
| **E-14** | quiver's components are not embedded (ARC) | — | ARC-03c/04 |
| **E-15** (F-1) | **What happens to the belt's unused potions on defeat.** The reserve is debited at entry and credited back unused at the closing report; what is consumed is gone (the orchestrator's ruling). design/03 and design/07 do not settle defeat for the belt: design/07 says loot is kept on defeat, and design/02's D-04 says defeat costs "the instance, nothing else" | (a) **credited back on defeat as on return** (D-04's reading: the potions are not loot but were not used); (b) **lost on defeat** (the belt is part of what the instance costs); (c) lost only in a sealed Red Rift. Cost: (a) and (c) write ≤ 4 pack pages at defeat (0.13 M); (b) none | **stopped, as the ruling asks.** The interface carries the counts (`Results.belt`) whatever the rule; the hub's rule waits for the decision |
| **E-16** (F-2) | **The union of goblins a batch can change is 140** (10 ticks × 14): 280 words, 8.98 M initialised, 127 M cold | (a) **a cap of 16 distinct goblin records a batch**: the batch stops before the action that would pass it (`Stop::Weight`), counted by the client as by the contract (steady state: 56 slots, §10.1); (b) cap 24 (+0.26 M a batch); (c) no cap: 40 M cannot hold | none (a rule of `play`, ENG-07); **(a) recommended** |
| **E-17** (F-7) | **The per-action events cost** 56,740 per `GoblinKilled` and 40,048 per `ChunkRevealed` (snforge, M; about ×1.157 on Sepolia): up to 1.1 M a batch at 16 kills, about 2.6 % of the bound; 0.2 M in a typical fight batch | (a) keep all three (restored, the ruling); (b) drop `GoblinKilled` (the client reads the dead goblin by view; −1.05 M a worst batch) | (a): restored, frozen, tested |
| **E-18** (F-3) | **`mine` draws nothing** (design/17) but design/02 sends it alone as a Fate action | (a) standalone, as frozen (it runs its 3 ticks outside any batch; one more transaction floor, 0.82 M, per vein); (b) an *Interact* on a vein inside `play` (weight 3), saving the floor | (a) |
| **E-19** | `set_account_owner` zeroes `account_of[old owner]`; if that address ever owns an account again, its key is new (N) | keep a tombstone (the old owner mapped to a sentinel, O) | zeroed: rare |

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
| 8. `instance_region` | `RegionChunk`, page of 16 chunks, kinds Void / Unrevealed / Revealed (§4.1); remains away from their spawn chunk through the roster (§9.3, F-6); tests, with the cross-chunk death and restart: E-13 |
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
