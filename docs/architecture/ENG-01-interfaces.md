# ENG-01 — The core interfaces, frozen under a cost budget

| | |
|---|---|
| Status | Frozen by ENG-01 (2026-09-29), `[Opus 5.5]`, for review by the orchestrator and audit `[GPT-6-Astra]` (lenses D, S). The escalations of §11 are open |
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
| `Hub` | 194,281 | 9,555 | 11.66 % |
| `Instances` | 134,304 | 6,410 | 7.82 % |
| `Market` | 53,214 | 2,707 | 3.30 % |
| `Registry` | 42,410 | 1,435 | 1.75 % |
| `TxHashFate` | 18,039 | 368 | 0.45 % |

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
their size is unknown (ARC). Running `class_sizes.py` in CI needs a line in `.github/` (§11, E-10).

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
| `tasks[(slot, page)]` | `header.tasks` (pages beyond `⌈tasks / 4⌉` are never read) | `create` |
| `members[(slot, m)]` | `header.members` (members beyond the count are never read) | `create`, all eight words |
| `roster[(slot, page)]` | the header; both pages | `create` (emptied: `LIVE` only) |
| `chunks[(slot, c)]` | bit `c` of `revealed`: a chunk not revealed in this generation is never read (wall, D-136) | its reveal, both words |
| `goblins[(slot, e)]` | its spawn chunk revealed **and** bit `k` of that chunk's `touched`, or its id in the roster | the chunk's reveal clears `touched`; the roster is emptied at `create` |
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
- Deadlines are on the instance clock (M-2). **The clock never passes `MAX_CLOCK = 2^28 − 1`**
  (268,435,455 ticks; an action that would pass it is invalid), so that deadlines fit 28 bits where a
  record needs it (E-4).
- Several-slot records are `Store` structs of packed felts: field `i` is at offset `i` from the
  map entry's address (tested: `test_record_sizes`).
- `u256` appears only in `split` and `decode_batch`, to split a felt into limbs (written reason in
  `packing.cairo`; ENG-02 may replace it by `u252`).

### 3.2 `Instances` storage

| Variable | Key | Slots | Record | Written by |
|---|---|---:|---|---|
| `admin`, `hub`, `registry`, `fate` | — | 4 | addresses | constructor, `set_contracts` |
| `next_slot` | — | 1 | `u32` | first entry of an adventurer |
| `placements` | adventurer `u32` | 1 | `Placement` | `create`, `leave` |
| `headers` | slot | 1 | `Header` | every invocation that runs an action |
| `entropy` | slot | 1 | felt: entry draw + Σ hashes of irreversible actions (a set, ADR-0006 option C) | `create`; an action that feeds it |
| `revealed` | slot | 1 | `Bitmap`, bit `15 cy + cx` | `create`, reveal |
| `quotas` | slot | 1 | `Quotas` | `create`, reveal |
| `tasks` | (slot, page 0–3) | 1 each | `TaskPage`: 4 × `TaskEntry` | `create` |
| `members` | (slot, member 0–7) | **8** each | `Member` | `create` (all); play (the first four) |
| `roster` | (slot, page 0–1) | 1 each | `Lanes16`: entity ids of goblins displaced from their spawn, 0 = empty | `create`; a goblin wakes, dies or goes home |
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
  each goblin's tile as one of the 19 tiles within 2, 5 bits each, 36–60) · objects at 128, 160, 192
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

**The roster** holds every goblin displaced from its spawn and not dead: at most 30 (two pages).
Design/02 bounds awake goblins (8), not displaced ones; E-2.

### 3.3 `Hub` storage

| Variable | Key | Slots | Record |
|---|---|---:|---|
| `admin`, `registry`, `instances`, `market`, `fate` | — | 5 | addresses |
| `next_account`, `next_adventurer`, `next_item` | — | 3 | counters |
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
  trials tried 160–175 · status 176–183 (deleted).
- `AdventurerPlace`: instance id 0–63 · hub 64–79 (0 inside) · last hub 80–95 · inside 96–103 ·
  unlocked hubs 128–191.
- `Build`: bar 8 × `u16` 0–127 · attribute ranks 9 × 4 bits 128–163 · elite slot 168–175.
- `belt` (`Lanes32`, lanes 0–3: potion items) · `equipped` (`Lanes32`: weapon, off-hand, chest,
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
| `lot_count`, `open_lot_count` | — | 2 | `u64` (SPK-11 §6) |
| `lots` | lot `u64` | 1 | `Lot`: price 0–63 · expiry 64–127 · seller account 128–159 · lot size 160–167 · state 168–175 (open, sold, withdrawn, returned) · kind 176–183 (balance, equipment) · item or entity 184–215 · market 216–231 |
| `seller_lots` | (account, page) | 1 | `SellerPage`: 3 lot ids of 64 bits · count on page 0 at 192–199 ("my lots", 10 + rank: ≤ 7 pages) |
| `trade_count` | — | 1 | `u64` |
| `trades` | trade `u64` | **5** | `Trade { head, inviter: TradeSide, invited: TradeSide }`; `TradeHead`: inviter 0–31 · invited account 32–63 · invited adventurer 64–95 · state 96–103 · confirmations 104–111 · revision 112–119 · opened at 128–191; `TradeSide { goods: Lanes32 (7 entities), money: TradeMoney }`; `TradeMoney`: gold 0–63 · item 64–95 · amount 96–127 · item 128–159 · amount 160–191 |

Lot and trade ids come from their counters, never reused (SPK-11 §6: the indexer detects a gap). A
lot is therefore always a new slot (N, once per posting); reusing lot slots per account would save
about 0.42 M a posting at the price of the gap check (§11, E-11).

**The market key** (SPK-11 *scope 5*, one felt, frozen with `LotPosted`, `models::market::market_key`):
a balance: its item id; equipment: `2^40 + base × 2^16 + requirement × 2^8 + rarity × 2 + identified`;
a boss item: `2^41 + base`.

### 3.5 `Registry` storage and shapes (scope 6)

`records: Map<(kind u8, id u32, part u8), felt252>`, `last_ids: Map<kind, u32>`. A record is
`parts(kind)` felts (`grimworld_logic::content`); ids are **append-only** (a new id is the next of
its kind), values may change (design/01 rules 1–2). Pillar 6 and S-6: a zone or a quest is data.

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
(`decode_batch` refuses a count out of 1–10, a bad argument, a bit beyond the count: tested).
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

**Views** return the stored words in their layouts (the client decodes them with the same code):
`InstanceView { instance_id, header, entropy, revealed, quotas, tasks, members (8 words each),
roster, goblins (every goblin of the members' windows), chunks (the chunks the windows overlap) }`;
`RegionChunk { chunk, kind (Void, Unrevealed, Revealed), terrain, features, goblins }`, words only
for a revealed chunk. A `GoblinView` says whether the goblin is **derived** (untouched, at its
spawn, from its pack placement) or stored. Both views are pure reads: callable at a block hash or
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
| `Registry.set_record.record` | exactly `parts(kind)` | the writer |
| a trade side | ≤ 7 entities, ≤ 2 balances, gold (E-11) | the stored layout |
| held quests | ≤ 4 (D-135) | quiver |

---

## 5. Events (scope 4)

The first key is the selector of the name. A change is a new event name (SPK-11 §6). Tested:
`test_hub_events`, `test_market_events`, `test_instances_event_keys_and_data`.

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

The first nine are SPK-11's (five MVP, two of the trade, three rankings emitted from the MVP on).
The instance's four serve the client from its own receipts; the indexer needs none. `Stop`,
`Refusal`, `Outcome` are enums whose variant index is their encoding (order frozen in
`grimworld_logic::types`). **Views of the indexer:** `Market.lot_count`, `open_lot_count`,
`trade_count` (SPK-11 §6). Completeness (every path emits its event exactly once) is the implementing
lots' invariant, with tests.

No event per goblin killed or chunk revealed: an event costs gas in the emitting call (SPK-11: 25,600
to 65,600 each), and the client reads the state by views. design/02's "each action emits what it
emits alone" is answered with `BatchPlayed` only in the MVP.

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

## 9. The slot table (scope 2, AC-2)

Worst case per entrypoint. **New** is a slot whose value is 0 at the start of the transaction; a
reused slot keeps `LIVE`, so it is never new again. The fee token's 2 balances are in F, not here.
"First" is the first time the keys exist (an adventurer's first entry, a chunk index never revealed
in this slot); "reused" is every time after.

| Entrypoint | Slots read | Slots changed, first / reused | of which new | Why |
|---|---|---|---|---|
| `Hub.enter` → `Instances.create` | hub: account, adventurer (6), known skills, pack pages ≤ 4, held quests ≤ 4; registry: gate, location, outline (1 call); instances: placement | **22 / 22** | **21 / ≤ 2** | instances: placement 1, header 1, entropy 1, revealed 1, quotas 1, tasks ≤ 4, member 8, roster 2, entry chunk 2; hub: place 1. Reused: new only if the entry chunk index was never revealed in this slot |
| `leave` / `travel_back` to a hub | header, member, placement; hub: adventurer | 5 | 0 | header (status), placement, member state (gone); hub: place, core (experience, last report) |
| `leave` through a gate to a location | as `leave` + `create` | 25 | ≤ 2 | the next instance in the same slot |
| `play`, weight 10, no reveal | header, entropy, member (8), roster (2), the window's chunks (≤ 4 × 2), the goblins in the window (≤ 30 records), registry (1 `bundle` call) | **≤ 33** | **0 in steady state; ≤ 16 the first time goblins wake in a slot** | header 1, entropy 1, member 4 (state, timers, effects, recharges), 8 awake goblins × 2, roster 2, chunks' `features` ≤ 4 (a pack wakes: `touched`); hub `report` ≤ 5 (core; quiver's held quests ≤ 4) |
| — a revealed chunk (weight 2) | outline or neighbours' edges | +2 chunk, revealed and quotas once | **2 the first time this chunk index is revealed in the slot**, 0 after | SPK-7 wrote 1 (terrain) + occupancy on moves; here terrain and features at reveal, no occupancy ever |
| `loot`, `open`, `mine` | header, member, target (goblin or chunk), registry (loot table) | ≤ 15 | ≤ 3 | header, entropy, member state, target 1; hub: pack balance pages ≤ 2, gold 1, an equipment drop (1 new entity + 1 pack page), title counter 1, held quests ≤ 4. New: the drop's entity, a balance page first held |
| `barter` | header, member, chunk; hub: pack pages | ≤ 7 | ≤ 1 | header, member state, chunk features; hub: pack pages ≤ 2, item entity (new), pack list 1 |
| `register` | — | 3 | 3 | account 2, account_of 1 |
| `create_adventurer` | account | 8 | 7 | adventurer 6, roster page 1 (new), account record 1 |
| `set_build` | adventurer, known skills, items ≤ 7 | 3 | 0 (3 at the first) | build, belt, equipped |
| `travel`, `display_title` | adventurer | 1, 0 | 0 | `display_title` writes nothing: the event only (T-1) |
| `accept_quest`, `abandon_quest` | quiver | 1–2 | ≤ 1 | quiver's held-quest record (D-135) |
| `claim_quest` | quiver, adventurer | ≤ 8 | ≤ 2 | core, gold, balance page, known skills, quiver 2, counters 1 |
| `buy_skill` | known skills, gold | 2 | 0 | known page, gold |
| `buy`, `sell`, `craft` | shop (registry), gold, pages | ≤ 5 | ≤ 2 | gold, balance pages ≤ 2, entity (new for equipment), pack page |
| `recycle`, `personalise` | item, pages | ≤ 4 | ≤ 1 | item base, pack page, material or stone page, gold |
| `identify` | item | 2 | 1 | item mods (new: modifiers come to exist), gold |
| `lift_modifier`, `set_modifier` | items | ≤ 5 | ≤ 1 | item mods × 2, a component entity (new), stone page, pack page |
| `brew` | grimoire (3), pages, book (registry) | ≤ 6 | ≤ 2 | grimoire state and pairs (new at the first brew of the book: SPK-2's 2 / 3), ingredient pages ≤ 2, potion page |
| `stow` | pages | ≤ 20 | ≤ 4 | pack and vault lists ≤ 4, balance pages ≤ 16, gold 2; new: vault pages first used |
| `enter_rift` | board | 23 | ≤ 1 more | the board (new on the account's first day) + `enter` |
| `post_lot` | market, hub | ≤ 7 | **1** | lot (new, ids never reused), counts 2, seller page; hub: pack page or item base, escrow page, gold (fee) |
| `buy_lot` | lot, hub | ≤ 9 | ≤ 2 | lot, open count, seller page; hub: gold × 2, escrow, buyer's vault list or page (new first time) |
| `withdraw_lot`, `return_lot` | lot | ≤ 6 | ≤ 1 | lot, open count, seller page, escrow, vault page |
| `open_trade` | hub (seller) | 2 | 1 | trade head (new), `trade_count` |
| `set_trade_side` | trade | 3 | 2 at the first | head, the side's 2 words |
| `confirm_trade` (the swap) | trade, items | ≤ 32 | ≤ 4 | head; up to 14 item bases, pack lists ≤ 4, balance pages ≤ 8, gold 2; new: pages first held |
| `Registry.set_record` | — | ≤ 3 + 1 | ≤ 4 | the record's parts, `last_ids` |

Checked against the receipts (cost-budget.md §1 formula, M on the left): SPK-1b's `enter` (4 new, 2
overwritten, the spike's layout) 3,555,447 measured against 3,629,831 by the formula; `leave`
1,659,915 against 1,664,419. SPK-2's native traces (FND-04 §5): tick 0/10, queue 0/10, brew new
pair 2/3, accept a quest 1/0, claim 1/2: the same shapes as this table's rows for those actions,
with this design's larger instance records (members of 8 words, goblins of 2) on top.

---

## 10. The budget (scope 8)

`L2 ≈ F + computation + C × calls + N × new + O × overwritten`. Computation figures are E unless
marked. Targets are for the burner sending directly (D-137).

| Entrypoint | Computation (E) | Calls | Slots, new / overwritten | **L2 gas target** | Against cost-budget.md |
|---|---:|---|---|---:|---|
| **`enter`, reused slot** | 1.45 M: the hub's checks and snapshot, the entry chunk's generation 0.39–0.45 M (SPK-7, M), the entry draw | 3 (instances, registry, fate) | 0 / 22 (worst 2 / 20) | **3,380,000** (worst 4,230,000) | 1.9 M with reused keys (E) and 0/6. **Departs** (+1.48 M): 16 more slots at entry (the snapshot's words, the task pages, the entry chunk's 2, the roster), the generation of the first chunk and two more calls, which SPK-2's `enter` did not have. The slots are 0.51 M of it |
| **`enter`, an adventurer's first** (D-129 point 4: the new storage of `enter`, an item of its own) | the same | 3 | **21 / 1** | **12,240,000** | 3.6 M (4 new). **Departs**: 21 new slots once per adventurer (9.52 M). Every later entry is the row above. Over an adventurer's life this is 21 new slots, where the spike's layout paid 4 new at **every** entry (1.81 M each) |
| **`leave`**, `travel_back` | 0.60 M (hub call, results) | 1 | 0 / 5 | **1,720,000** | 1.7 M (0/5): meets within 1 % |
| `leave` through a gate | 1.90 M | 4 | 0 / 25 (worst 2) | **4,070,000** | new row |
| **`play`, weight 10, steady state** | 10 ticks: 1.71 M each shared (E, cost-budget §3) to 3.56 M alone (M, SPK-1), + the window 0.065–0.72 M a tick (M, SPK-7) | 2 (registry `bundle`, hub `report`) | 0 / 33 | **19,900,000 to 45,000,000**; bound target **40,000,000** | §10.1 |
| — the first wake of 8 goblins in a slot | + 16 new | | 16 / 17 | + 6.74 M | §10.1, E-1 |
| — a revealed chunk (weight 2) | 0.45 M generation (SPK-7, M) | — | 2 / 0 the first time in the slot, then 0 / 2 (+ revealed, quotas) | **+1,360,000** first, **+0.58 M** after | 2.5 M a chunk: meets. Weight 2 (≈ 7.7 M of the bound) overprices it by 5× (E-12) |
| **`loot`**, `open`, `mine` | 0.50 M | 2 (fate, hub) | 3 / 12 | **3,340,000** | 2.9 M (≤ 2/≤ 4). **Departs** by 0.44 M: the hub's report writes more (title counter, held quests, the drop's pack page) |
| `barter` | 0.40 M | 1 | 1 / 6 | **2,000,000** | new row |
| `register` | 0.20 M | — | 3 / 0 | **2,380,000** | once per account |
| `create_adventurer` | 0.30 M | — | 7 / 1 | **4,330,000** | once per adventurer |
| `set_build` | 0.30 M | — | 0 / 3 | **1,220,000** | hub action 2.0 M: meets |
| `travel` | 0.10 M | — | 0 / 1 | **950,000** | meets |
| `display_title` | 0.05 M | — | 0 / 0 | **870,000** | meets |
| `accept_quest` | 0.40 M (quiver) | — | 1 / 1 | **1,700,000** | 1.57 M measured (SPK-2): meets 2.0 M |
| `claim_quest` | 0.60 M | — | 2 / 6 | **2,540,000** | 1.82 M measured (SPK-2, 1/2); the rewards' writes are more: **departs** from 2.0 M by 0.54 M, first claim only (pages first held) |
| `buy_skill`, `buy`, `sell`, `craft` | 0.30 M | — | ≤ 2 / ≤ 3 | **2,120,000** | 2.0 M; `craft` of equipment is the worst (a new entity): 2.12 M |
| `identify` | 0.35 M | 1 (fate) | 1 / 1 | **1,790,000** | a Fate action 2.9 M: meets |
| `brew`, a new pair | 0.50 M | 1 | 2 / 4 | **2,490,000** | 2.8 M (2/3): meets |
| `stow` | 0.40 M | — | 4 / 16 | **3,540,000** | new; bounded by 8 + 8 |
| `post_lot` | 0.30 M | 2 (hub) | 1 / 6 | **2,040,000** | new |
| `buy_lot` | 0.30 M | 2 | 2 / 7 | **2,540,000** | new |
| `confirm_trade` (swap) | 0.80 M | 1 | 4 / 28 | **4,470,000** | new; the worst trade (7 + 7 items) |
| `Registry.set_record` | 0.05 M | — | 4 / 0 | **2,680,000** | administration, not play |

`contracts/*/GAS.md` and `docs/BUDGETS.md` list the snforge figures of this task's tests (layouts,
packing, the batch's codec, the probes, deployments). None is an entrypoint's execution: those are
the implementing lots' benchmarks, each against its row above.

### 10.1 The 40 M bound of design/02, in slots and gas (OP-2, CB-3)

A batch of weight 10, worst case:

| Part | Slots, new / overwritten | L2 gas (E unless marked) |
|---|---|---:|
| Floor, one call, 4 felts of arguments (header of one call included in F) | — | 816,939 (D) |
| 10 ticks, each as measured alone (SPK-1 §4, M) | — | 35,649,130 |
| The window at each tick: 65,224 (in memory, M) to 720,000 (SPK-7's whole difference, M) | — | 652,240 to 7,200,000 |
| The instance's writes, once per transaction | 0 / 28 | 898,016 |
| One registry `bundle` call, one hub `report` call | 0 / 5 | 272,000 + 160,360 |
| **Total, steady state** | **0 / 33** | **38,448,685 to 44,996,445** |
| The first wake of 8 goblins in this slot | + 16 / − 16 | + 6,743,232 |
| **Total, a fresh slot** | **16 / 17** | **45,191,917 to 51,739,677** |

With the ticks shared as a queue shares them (1,705,764 a tick, E, cost-budget §3) the steady state is
**19.9 M to 26.4 M**, well inside.

**What this settles, and what it does not.**
- **In slots: yes.** A batch changes at most 33 slots and creates none in steady state; the
  instance's records are written once per transaction whatever the number of actions (CAIRO §5). The
  budget of cost-budget.md (0 new / ≤ 16) is **exceeded in count** (33): the goblins' two words and
  the member's four; at O each, the excess is 0.55 M, 1.4 % of the bound.
- **In gas: not proven.** The bound depends on how much of SPK-7's 720,000 a tick pays inside a batch
  (CB-3), and on the ticks' shared part (CB-2): 38.4 M to 45.0 M with every tick as measured alone.
  The proof needs the full tick (ENG-07, CBT-*), measured in a batch: design/02 item 6 cannot be
  answered by interfaces (E-13).
- **The first wake in a fresh slot adds 6.74 M** that no weight counts. The contract can count it (a
  goblin record read as 0 is new): E-1 proposes to weigh it.
- **Keep 40 M and the weights until ENG-07 measures**; the reveal weight 2 is 5 times what a reveal
  costs (1.36 M first, 0.58 M after, against ≈ 7.7 M of the bound): E-12.

### 10.2 The expedition (D-129)

One expedition of cost-budget.md §3 (S1: 300 actions) adds, with this design, to the rows already
there: `enter` 3.38 M instead of 3.56 M measured (reused slot; −0.18 M), `leave` 1.72 M instead of 1.66 M;
the batches' 5 extra overwritten slots each (≈ 0.16 M a batch, ≈ 5 M over S1's batches, E). The
first expedition of a new adventurer pays its 21 new entry slots (+9.52 M, $0.008) and the first
wakes of its goblins (up to 16 new a batch). Whether S1 meets $0.50 still turns on CB-2 (a tick
inside a batch).

---

## 11. Escalations (review point (a) and (b))

Each is a choice the documents do not settle, or where cost departs from a design rule. The code
follows the **default** named; the project manager decides.

| # | Question | Options, with their cost | Default in the code |
|---|---|---|---|
| **E-1** | **A goblin's first record in a slot is a new slot** (2 × N): up to 6.74 M in one batch, not counted by design/02's weights. | (a) weigh it: +1 per goblin woken for the first time in the slot (the contract sees a 0 record); (b) one word per goblin (drop `GoblinTimers` into the state word: loses conditions or the effect, 3.37 M saved); (c) accept: the bound is exceeded in a fresh slot only | None yet: the weight is ENG-07's; (a) recommended |
| **E-2** | **The roster (displaced goblins) is bounded at 30**; design/02 bounds awake goblins (8), not displaced ones | (a) 30 (2 slots), a 31st that would be displaced stays in its first state; (b) 45 (3 slots, +1 overwrite a batch, 32 k); (c) no roster: find displaced goblins by scanning the records of the chunks near the window (reads, no bound on distance followed) | (a) in the layout; the rule for the 31st is a game rule to decide |
| **E-3** | **At most 2 packs of 5 and 3 objects per chunk** (the features word) | a third pack or a fourth object needs a third chunk word (+1 slot a reveal: N the first time, O after) | 2 / 5 / 3; ENG-05's generator caps; design/18's frequencies make more rare |
| **E-4** | **The instance clock stops at 2^28 − 1 ticks** (8.5 years at 1 tick a second) | 32-bit deadlines: recharges need 2 slots a member (+1 overwrite a batch) | 2^28 − 1; an action that would pass it is invalid |
| **E-5** | **The ephemeral domain reads the registry during play.** ADR-0001 says it never reads persistent **models** during play; the registry is content, and pillar 6 requires reading it. A registry change during an instance changes outcomes for the same actions (determinism across a content update) | (a) read per invocation, one `bundle` call (C ≈ 0.14 M a batch); (b) mirror what play reads in `Instances` (0 calls; the administrator writes both, content can diverge); (c) (a) plus a content version in the header, refusing play across an update | (a); the client reads the registry at the same block as the instance |
| **E-6** | **`barter` calls the hub during play** (the price is in the pack). The results interface is "a list of results" (ADR-0001) | (a) `Hub.barter` in the instance's transaction (default); (b) snapshot trophies at entry (+1 member word, +1 slot at entry) and report the exchange as a result; (c) barter only in a hub (design/15 places collectors in the wilds) | (a) |
| **E-7** | **`enter` exceeds its budget**: 3.38 M reused against 1.9 M; 12.24 M the first time against 3.6 M | the snapshot (3 words), task pages (≤ 4), entry chunk (2) and roster (2) are the extra slots; the snapshot could travel as calldata checked against a hash (≈ 20 k a batch, 3 fewer slots at entry) but then `instance_state` would not hold it (design/02: one call, everything a played action depends on) | stored snapshot, budget raised to 3.38 M |
| **E-8** | **The Fate actions exceed 2.9 M** (3.34 M): the report's writes | fewer title counters per loot (Scavenger is an account counter written at every loot) | 3.34 M |
| **E-9** | **Version 1's Fate** needs a request in one transaction and the draw in a later one; the interface is synchronous | a provider that keeps requests (`fate` reverts until fulfilled) or a two-phase `loot` | ADR-0002's to decide (already escalated by DES-21) |
| **E-10** | **Class sizes in CI**: `snforge` cannot read a class's size (`read_json` refuses the CASM file); CI is a shared file | a step `python3 contracts/tools/class_sizes.py` after the build in `.github/workflows/ci.yml` | not in CI; run by hand, table in §1.3 |
| **E-11** | Market: lots are new slots (ids never reused, SPK-11); a trade side holds ≤ 7 entities and ≤ 2 balances (design/16 gives no bound) | reuse lot slots per account (0.42 M saved a posting) with the lot id in the record and the gap check on a posted counter | new slots; 7 / 2 |
| **E-12** | **A reveal weighs 2** but costs 1.36 M the first time, 0.58 M after (≈ 7.7 M of the bound) | weight 1 per reveal after ENG-05's measurement | 2, unchanged |
| **E-13** | design/02's list asks for tests that need game logic: the batch = single invocations = multicall (item 5), the gas bound with the full execution and a revealed chunk measured (item 6), restart, window crossing, reveal, unrevealed and boundary (item 8) | ENG-05, ENG-06, ENG-07 write them against this interface | out of this task (brief: "Out: game logic") |
| **E-14** | quiver's components are not embedded (ARC); `Hub`'s quest and title entrypoints and their slot counts rest on D-131/D-135 | — | ARC-03c/04 then ENG |

---

## 12. Answers to design/02's "What ENG-01 must do" and to the PLAN row (AC-1)

| Item | Answer |
|---|---|
| 1. `Instance.sequence` | `Header.sequence` (32 bits): §4.1 semantics; `create` at 0; `leave` to a location → a new id at 0 in the same slot |
| 2. `play` | Signature, batch encoding, stops and `BatchPlayed` frozen (§4.1, §5); code ENG-07 |
| 3. Loot, open, mine, leave, travel back | Signatures with `sequence`; preconditions before `fate`; `Refused` with `Refusal`; draw and consumption in one invocation (§4.1) |
| 4. No stop condition in the contract | None in the interface (§4.1) |
| 5. Batch = singles = multicall tests | E-13 |
| 6. Prove the gas bound | §10.1 in slots and with measured parts; the proof with the full execution: E-13, E-1, E-12 |
| 7. `instance_state` | `InstanceView`, one call, the stored words (§4.1) |
| 8. `instance_region` | `RegionChunk`, page of 16 chunks, kinds Void / Unrevealed / Revealed (§4.1); tests: E-13 |
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
| PLAN: slots each entrypoint changes | §9 |
| PLAN: D-135 | held quests ≤ 4 (§4.5) |
| PLAN: D-136 | a chunk outside `revealed` is never read (§2.1); `ChunkKind` (§4.1) |
