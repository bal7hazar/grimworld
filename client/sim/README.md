# `@grimworld/sim`

The client's simulation core (ADR-0003): a TypeScript mirror of the rules the chain decides, so
that the client predicts what the chain computes, bit for bit (D-140, option (a) of SPK-4). Pure:
no rendering, no chain access, no randomness, no clock, no I/O (mandate §6), except the tests and
the harness's reader.

## What is mirrored

| File                                          | Cairo                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Vector table                      | Cases       |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- | ----------- |
| `src/window.ts`                               | `WindowTrait` (`contracts/logic/src/types/window.cairo`, ENG-02)                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | `window.jsonl`                    | 2,065       |
| `src/hit.ts`                                  | `HitTrait::resolve` and the `Serde` of `Hit`, `HitTarget`, `HitOutcome` (`types/hit.cairo`, CBT-03a)                                                                                                                                                                                                                                                                                                                                                                                                                                        | `hit.jsonl`                       | 203         |
| `src/body/`, `src/effect.ts`, `src/combat.ts` | the `Body` operations (`types/executor.cairo`'s `Body`, `MemberBody`, `GoblinBody` and the dispatch `UnitBody`, CLI-02g-C) and what they call of `models/member.cairo` and `models/goblin.cairo` (the snapshot's reads, the lifecycle, the conditions, the interrupt), `types/infliction.cairo`, `durations.cairo`; the effect entry (`EntryTrait`: `line`, `value`, `duration`, `class`, `pack`, `unpack`)                                                                                                                                 | `body.jsonl`                      | 334         |
| `src/executor.ts`, `src/trap.ts`              | a trap's trigger (CLI-02g-D, D-257): `TrapLibrary::trigger` (`systems/trap.cairo`), `TrapTrait`'s lookup and source (`types/trap.cairo`: `locate`, `free`, `trigger`, `terrain`, `by_member`, `by_goblin`, `entries`, `occupied`, `write`) and the executor's trap path (`types/executor.cairo`: `trigger`, `trap`, `strike`, `resolve`, `entries`, `ops`, `hold`, `guards`, `spell`, `put`, `actor`, `DefenceTrait`, `holding`, `Levered`'s cache)                                                                                         | `trap.jsonl`, `segment2.jsonl`    | 87, 44      |
| `src/tick.ts`, `src/ai.ts`                    | the ticks with a fight (CLI-02g-F, D-257): `TickLibrary::ticks` (`systems/tick.cairo`), `TickTrait::run` with `Delegate`'s rules (`types/world.cairo`, `types/executor.cairo`: perception and the awake set, step 1's conclusions through the executor, `carrier`, `legal`, step 2 in `AiLibrary::act`, step 3, the defeat), the goblins' acts (`AiTrait`, `types/ai.cairo`; `FloodTrait::next_step_away`), the goblin and member tick rules (`src/body/`), `SegmentTrait::ticks`' path                                                     | `tick.jsonl`, `segment2.jsonl`    | 131, 44     |
| `src/fate.ts`                                 | `fate::domain`, `fate::derive` and the purposes (`contracts/logic/src/fate.cairo`), Poseidon through `@scure/starknet`                                                                                                                                                                                                                                                                                                                                                                                                                      | `fate.jsonl`                      | 227         |
| `src/packing.ts`                              | `contracts/logic/src/packing.cairo`: `split`, `limbs`, `join`, `peel`, `fits`, the field readers, `Lanes32`, `Lanes16`, `Counter`, `Bitmap`                                                                                                                                                                                                                                                                                                                                                                                                 | `packing.jsonl`                   | 520         |
| `src/movement.ts`                             | the moves of a played batch (ENG-07, CLI-02c): the window's board around the adventurer (`SegmentTrait::board`, `BoardTrait::position`, `AssemblyTrait::origin`), a Move's ticks (`TickMathTrait::move_ticks`), the tick's flood (`Bfs::flood`, `FloodTrait`) and step 0's awake set (`TickTrait::awake`)                                                                                                                                                                                                                                   | `movement.jsonl`                  | 94          |
| `src/batch.ts`                                | where a played batch stops (ENG-07b, CLI-02d): `SegmentTrait::admit` (E-16's cap of 16 records, E-1's weight with +1 a first record) and `SegmentTrait::revealed` (a reveal's weight, 2 a chunk)                                                                                                                                                                                                                                                                                                                                            | `batch.jsonl`                     | 28          |
| `src/segment.ts`                              | one segment of a played batch (ENG-07, D-248, CLI-02f, CLI-02g-A): `SegmentTrait::run` (`types/play.cairo`) on the real world: the owed ticks' fold, `max(1, ticks)`, the three weight checks (`run`'s, `turn`'s, `step`'s), the `ran` rule, a Move's reveal stop, `fits` with its goblin records, the illegal halts, `world.defeated`, the occupied tile, the companions, the fast path's ticks and regeneration, `MOVEMENT`, the followed window; the window's walkable board (`SegmentTrait::board`, `hexx`'s `AssemblyTrait::assemble`) | `segment.jsonl`, `segment2.jsonl` | 47, 44      |
| `src/segment/`                                | the `Serde` codecs of `Content`, `Words`, the ground, `Area`, `executor::Board`, `Action`, `Done` and the recorded calls (`serde.ts`); a member's load and store, the content's `Sheets`, `Index` and `Kit` (`words.ts`); a goblin's load, with its refusals, its store and the fields of its words (`goblin.ts`, CLI-02g-B1); the world's load, with the awake cap, and store (`world.ts`); the fast path's named tick functions, `flag::KEPT` and `can_act` (`tick.ts`); the seam of the classes and their call digests (`classes.ts`)    | `segment2.jsonl`                  | 44          |
| `src/reveal.ts`, `src/reveal/`, `src/hexx.ts` | the reveal of a chunk (ENG-05, ENG-05b, ENG-10b): `RevealTrait::reveal` and its steps (`types/reveal.cairo`, `reveal/board.cairo`, `reveal/placement.cairo`), `SightTrait::chunks`, `fate::EntropyTrait` (`word`, `feed`, `outline`), `PackPlacementTrait::member`, and what they call of `hexx` 0.2.0 (`RngTrait`, `CaverTrait::smooth` and `keep_component`)                                                                                                                                                                              | `reveal.jsonl`                    | 214         |
| `src/exp2.ts`                                 | `helpers/exp2.cairo`'s table, generated for both sides by `contracts/tools/exp2_table.py`                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `--check` in CI                   | 241 entries |
| `src/signed.ts`                               | `helpers/signed.cairo`'s `SignedTrait`: `bits8`, `from8`, `bits16`, `from16`, the two's complement of an `i8` and an `i16`                                                                                                                                                                                                                                                                                                                                                                                                                  | `signed.test.ts`                  | —           |
| `src/felt.ts`                                 | `P`, the integer types (`u8` … `u128`, `i8` … `i32`) with Cairo's panics, truncating division, signed felts, short strings                                                                                                                                                                                                                                                                                                                                                                                                                  | —                                 | —           |

The functions keep the Cairo names and argument order (`sight(open, from, to)`, `arc(source,
target, facing)`, …): `number` for positions, facings and ranges, `bigint` for felts, bitmaps and
the integers of a hit. A Cairo panic is a thrown `CairoPanic` carrying its short strings.

A packing guard that panics in Cairo (`join`'s high limb, `fits`, `pack_bitmap`) throws its
`CairoPanic`; the table records it as a refusal (`[0, result…]` accepted, `[1]` refused), and its
adapter in `src/parity/tables.ts` turns only that guard's own panic into `[1]`.

## The segment and its classes

`run` calls three classes: `TickLibrary::ticks`, `ActionLibrary::act`, `TrapLibrary::trigger`.
They go through one seam, `Classes` (`src/segment/classes.ts`). `run` computes each call's inputs
itself and passes them through it, then loads the words and the ground the class returns, as
`SegmentTrait::reload` does. A trap writes back the members, and the placer goblin of a placed
trap.

**Native**, as `run` holds them:

- the loop and its stops;
- Move: open, occupied by a living member or goblin, Crippled, a held `MOVEMENT` effect;
- Turn and Wait, the followed window;
- the trap lookup (`AiTrait::armed`) and the words it sends;
- `idle`'s choice and the fast path (`TickTrait::idle`): the clock, the flags, the members'
  regeneration out of combat (`MemberTickTrait::regenerate`: health, energy, adrenaline), the
  defeat check;
- `fits`' goblin records.

**Behind the seam**: the three classes. `segment2.jsonl`'s rows are replayed by
`src/parity/replayer.ts`, which is test scaffolding and is never exported by `src/index.ts`. At
each call it checks the kind and the Poseidon digest of the inputs `run` computed (the README of
the vectors gives their order), then returns the recorded words and ground. A replay is sound
only if it checks every digest and consumes every recorded call (D-255): a call of another kind,
other inputs, a call the row lacks or a recorded call left unused fails the row, naming the call's
index and kind (`src/parity/replayer.test.ts`).
Lots D to F replace the replayer with ports, class by class; the batch preview needs those ports,
since it predicts batches nobody recorded (D-255). All three are ported: `TrapLibrary::trigger`
(lot D), `ActionLibrary::act` (lot E) and `TickLibrary::ticks` (lot F), below. On a
`segment2.jsonl` row the replayer still takes each recorded call (its kind, its digest, its place
in the span), and the port's result, felt for felt, must equal it; the port's is what `run` loads.
The replayer stays, as the test of `run` itself: it alone checks that `run` makes exactly the
calls the row recorded, with the inputs it recorded (D-255); comparing the ports' results alone
would not see a call made with other inputs that return the same words.

**Not mirrored**: two branches, which throw `NotMirrored` (`unported`,
`src/segment/unported.test.ts`, `src/action.test.ts`):

- `EDGE`: a Move whose neighbour is missing (`LayoutTrait::neighbor` → `None`, the window's edge).
  `run` never reaches it: the adventurer stands at the window's column 7, and every direction has a
  neighbour.
- `MIXED`: an action's carrier whose entries mix a `TILE` target with an entity one (`FOE`, `ALLY`,
  an attack's hit), or whose first entry addresses `SELF` with a `TILE` entry later (`aim` gives
  it the source's id, which a `TILE` set reads as a tile): below, _The action_. No content of the
  tables holds one.

**A refusal leaves the ground as it was** (D-259, FIX-01): an Attack, a Skill or an Item refused as
Illegal or Heavy restores the words and the ground; `SegmentTrait::combat` takes `ActionLibrary`'s
ground only when the result is kept. Row 44 (an instant trap skill refused as Heavy) holds it, and
the mutant "a Heavy refusal keeps ActionLibrary's ground" is killed by it.

**A class must not mutate its inputs** (CLI-02g-C). A library call receives its inputs serialised;
`run` keeps that true whatever a port does: it passes each call a copy of the words and the ground
(`copyWords`, `copyGround` in `src/segment/classes.ts`; `play.cairo`'s `combat` clones the ground the
same way). No row records an Illegal refusal whose call changed the ground, nor a class that
mutates its inputs: `src/parity/seam.ts` holds those cases, run by `src/segment/unported.test.ts`
and, against each `seam` mutant (the Illegal refusal keeping the call's ground, the ground or the
words passed uncopied), by `src/parity/mutants.test.ts`.

## The `Body` operations

`src/body/` mirrors the operations the executor runs on an actor (CLI-02g-C, D-257), on a member
and on a goblin through one dispatch, as `UnitBody` (`Unit`: `{ kind: "M", member }` or
`{ kind: "G", goblin }`): the reads (`health`, `max_health`, `is_member`, `alive`, `place`,
`knocked`, `asleep`, `halves`, `armor_vs`, `infliction`, `enchant_percent`, `slots`, `effect`) and
the writes (`wound`, `heal`, `energize`, `struck`, `landed`, `halved`, `inflict`, `cure`, `hold`,
`spend`), each in place on the unit, as Cairo's `ref self` (`copyUnit` for a caller that keeps its
input). `src/effect.ts` is the effect entry. `defence` (lot D) and `offence` (lot E) are
`src/executor.ts`'s, held by `act.jsonl`'s `defence` and `offence` rows.
`src/body/serde.ts` reads and writes a unit, a `Held` and an `Infliction` as the table records
them. Lot D (the trap's path) builds on `body/index.ts`, `body/member.ts` (`interrupt`, `hold`,
`put`, `apply`, `knock`), `body/goblin.ts`, `body/infliction.ts` and `effect.ts`.

`body.jsonl`'s rows are its README's: row 0 the content every actor is loaded through, then one
operation a row. No mutant survives: the recharge lanes of bar slots 4–7 are killed by `act.jsonl`'s
row 44, and the table's three former holes by RV-03a2's rows: `hold`'s step 1 at a carrier held to
exactly `T` (327), a potion compared by its belt slot rather than its item (328), a goblin
activating caste slot 3 knocked down (333).

**Fail closed** (CLI-02g-B1): `world()` loads each goblin through `GoblinTrait::load`
(`src/segment/goblin.ts`), as `WordsTrait::indexed` does, and panics with Cairo's string where
Cairo panics: a caste not in the content (`tick: caste not in content`), a caste skill or the
effect's skill not in it (`tick: skill not in content`), an effect's regeneration above an `i8`
(`goblin: regeneration above i8`), a max health above a `u16` (`Option::unwrap failed.`), and more
than 8 goblins awake (`tick: more than 8 awake`). No row of `segment2.jsonl` records a refusal, so
the cases are `src/parity/refusals.ts`', hand copies of the Cairo unit tests where they exist, run by
`src/segment/goblin.test.ts` and, against each mutant that drops a refusal, by
`src/parity/mutants.test.ts`. The lifecycle and condition rules of both kinds, the infliction and
the durations are `src/body/`'s (below), and so are the tick's rules (`GoblinTickTrait`'s `start`,
`recover`, `use_instant`, `conclude`, `lapse`, `regenerate`; `MemberTickTrait::conclude`), since
lot F.

`segment.jsonl`'s rows hold a simplified adventurer. Their decoder builds its words as the
unit-test fixture's member (max health 480, no regeneration, no effect or skill), and its classes
fail on any call: the table never reaches one.

## The trap's trigger

`src/trap.ts` is `TrapLibrary::trigger`, computed (CLI-02g-D, D-257): `triggerClass` loads the
words through the content, finds the entrant by its entity (`ExecutorTrait::actor`), runs
`TrapTrait::trigger` with a fresh `Cache` and stores the words back; `src/index.ts` exports it as
`trapTrigger`, a `Classes.trigger`. `src/executor.ts` is the executor's path it runs: the payload's
guards on the trap's source, the hit (class `TRAP`, strength `3 × level`, no arc, never blocked or
evaded) on the target's defence through `Levered`'s cache, then the other entries in entry order
while the entrant lives, and the entrant written back (a goblin at 0 killed, in `killed`).
`segment.ts` takes `locate` and `occupied` from it.

`trap.jsonl`'s rows are its README's: rows 0 and 63 the content, 75 `trigger` rows (one call of the
class each) and 10 `free` rows. Each row reads the last `content` row before it (RV-03a2: rows 1–62
row 0's, rows 64–86 row 63's; `contentRow` in `src/parity/table.ts`). `segment2.jsonl`'s trap calls (rows 26, 28, 43) are computed by the port
and equal their recordings (`src/parity/parity.test.ts`).

A trap's one entrant is written back at once (`put` without `pending`, `Naive`'s write); the
action's carrier is below.

Until RV-03a2's row 86 (a Runt placer, a Hob entrant) the goblins of every row were Hobs of one
caste, so a port reading another goblin's caste than the placer's passed every row:
`src/parity/trapcases.ts` holds that case, and that the class leaves its inputs as they were, run by
`src/trap.test.ts` and, against each `trap` mutant, by `src/parity/mutants.test.ts`.

Of the trap path's 65 mutants, 39 were killed by `trap.jsonl` and 3 by `trapcases.ts` (another
goblin's kit, rank or level read for the placer's; since RV-03a2 by `trap.jsonl`'s row 86). Since
`act.jsonl` (lot E), 10 of the 21 survivors are killed by its rows: `strike`'s block spend (205),
the knocked-down (209) and sleeping (211) target, a trap's damage of no type (`offence` 185), the
cached and the expired defence (159, 161, 173), an `ARMOR` effect below 0 (164), a `HEAL` and a
holding entry (44, 215). On the trap path, `trap`'s and `entries`' checks of a dead entrant mask
each other; since `tick.jsonl` (lot F), `entries`' is killed by its row 85 (a carrier's hit killing
a goblin before its burn). RV-03a2's rows kill the nine holes of `trap.jsonl`: a position, a chunk
column or a chunk row past the location (64, 65, 66), `locate`'s guard of a tile West of `ORIGIN`
(68), a goblin placer's payload guarded (79), an entrant holding an `ARMOR` effect (71), a payload's
entry other than its hit guarded (81), a `CURE` entry (83), a dead goblin entering (85). None
survives. Three are equivalent, marked `equivalent`: `trap`'s check of a dead entrant, which
`entries`' masks on the trap path (track game's ruling in RV-03a2: no entry before it can kill, so
both checks read the same value); the same guard's South half, whose chunk is below
0, which no ground holds, and the block's cap at 63, which no state reaches: a member's charges are
6 bits (`MemberEffects` 16–21, read modulo 64), a goblin's too (rows 213 and 214), a `BLOCK` grant
is clamped to `MAX_BLOCK` (`tick.jsonl` rows 72, 73 and 80: 63, 62, and 64 clamped to 63), and the
defence takes one slot's charges, not a sum.

## The action

`src/action.ts` is `ActionLibrary::act`, computed (CLI-02g-E, D-257): `actClass` loads the words
through the content, runs `ActionTrait::act` for member 0 with `Delegate`'s rules and a fresh
`Cache`, and returns the words stored back (or the words as they came on a refusal), the ground and
the `Result`; `src/index.ts` exports it as `actionAct`, a `Classes.act`. `act` is the legality in
its order (the clock, the adventurer, knocked down, then each arm's: Turn's flag; the skill's
`Empty`, `Kind`, `Instant`, `Recharging`, `Adrenaline`, `Energy`, `aim`'s `Target` and `Reach`,
`Trap`; the item's `Empty`, `Belt`, `aim`), the costs at once (energy after _Fieldcraft_ and the
glyphs, consumed; adrenaline; the quick-cast counters; the belt's count), the facing, and the
carrier now (`carry`) or an activation started (`A = c + n`), with its tick cost.

`carry` is `Delegate`'s: a `TRAP` carrier is placed in the ground (`trap.ts`'s `spot`, `place`,
`placer`) if its guard holds, before any sub-world; any other runs through `executor.ts`'s
`execute`, on the whole world. That is equal to the sub-world for carriers whose entries share a
target kind; a mixed-target carrier is not mirrored. `Delegate` picks the sub-world's goblins (the
addressed one, those within one tile of the source and the address) by the carrier's first entry,
where `actors` centres each entry's set by its own target: a `TILE` set beside an entity one
(`FOE`, `ALLY`, an attack's hit), or beside a carrier addressing `SELF`, reads the address as the
other kind and may reach a goblin the sub-world does not hold (review t-0209). `action.ts`'s
`mixed` refuses those with `NotMirrored` (`unported.MIXED`); `SELF` with `FOE` or `ALLY`, `FOE`
with `ALLY`, and `TILE` first with `SELF` later stay mirrored. Since R-44 (`assert_carrier`, D-271,
D-276) the guard is defence in depth: the content pipeline refuses, in a carrier other than a trap,
a `TILE` entry beside a `FOE` or `ALLY` one and any `SELF` entry before an addressed one, so every
shape `mixed` refuses is illegal content, and so are `[SELF, FOE]` and `[SELF, ALLY]`, which it keeps.
The legal shapes it keeps are `SELF` after the addressed entry (`[TILE, SELF]`, `[FOE, SELF]`),
`SELF` alone, `FOE` with `ALLY`, all-`TILE`, all-entity and a `TRAP` with its payload; it refuses none
of them. `src/parity/actcases.ts` holds the refused shapes (a `TILE` hit then a `FOE`
or an `ALLY` condition; the reverse, an order `assert_carrier` also refuses, `HIT_NOT_FIRST`; a `SELF` hit then a
`TILE` condition; all marked "not legal content (R-44)") and the kept ones, each run against its
expected result (a `SELF` disc hit then a `FOE` condition, not legal content (R-44); a `TILE` disc hit then a
`SELF` condition and a `FOE` hit then an `ALLY` condition, legal),
run by `src/action.test.ts` and, against the `act` mutants of `mixed` (its guard, its `SELF` arm,
and two that refuse a kept shape), by `src/parity/mutants.test.ts`. `execute` is §5.14: the
carrier's entries (`read`), their guards, each entry's `Op`, the hit modifiers (`modifiers`), the
target sets (`actors`: every set's shape on its centre, the actors its filter takes, ascending
position; a carrier of `SINGLE` entries reads its source and the addressed entity alone), the
source's terms (`offence`: a member's weapon, passives and held `PENETRATION`, a goblin's caste
weapon; `penetration`, `attack`), each actor in order (`on`: the hit, then the other entries), the
source's side of a landed weapon hit, and each actor written back, a carrier's awake goblins
gathered into one write of the awake set (`put` with `pending`, `flush`: `Levered`'s lever). An
activation's end (`carrier`, `legal`) and the goblins' acts are the ticks' (below).

`act.jsonl`'s rows are its README's: rows 0 and 223 the content, 195 `act` rows (one call of the
class each), 19 `defence` and 28 `offence` rows (`Body::defence`, `Body::offence` through
`UnitBody`). Each row reads the last `content` row before it (rows 224–243 row 223's). On
a refusal the words and the ground are the case's, felt for felt. `segment2.jsonl`'s `act` calls
(rows 1 to 11 and 44) are computed by the port and equal their recordings
(`src/parity/parity.test.ts`). The liveness reads are the class's own: `locate` reads a goblin's AI
state and health, `TrapTrait::occupied` and a wide carrier's candidates its AI state alone (rows
217 to 222 hold goblins dead by one field only).

Of the action's 154 mutants, 145 are killed by the tables and 4 by `actcases.ts` (`mixed`'s guard,
its `SELF` arm, the `ALLY` one that makes a `TILE` then `ALLY` carrier run on the whole world, and
one that refuses a kept shape: `TILE` counted with `ALLY`; the two other such mutants, `SELF`
counted as a `TILE` one and every `TILE` carrier refused, are killed by the tables, the second by
row 241, a lone `SINGLE` `TILE` spell). `mixed`'s attack arm (`let entity = attack`) has no test: it is defence in depth.
`assert_carrier`'s `ATTACK_ENTRY` keeps an attack's entries `FOE` + `SINGLE`, so legal content
never holds an attack with a `TILE` entry, and no case reaches the arm. RV-03a2's rows (223–243,
read through their own content row 223) kill 14 of the 16 holes of `act.jsonl`: the weapon-required
bit of slot 0 read for every slot (224, 225), a negative `NEXT_SPELL_COST` (226), a quick-cast pair
from bar slot 1 (227), an attack skill's scope (228, 229), `ATTACK_BONUS` (230), `HIT_PENETRATION`
(231), a `PENETRATION` of scope `ALL` not taken (233, 234), an `ON_ATTACK_CONDITION` (235, 236),
`LIFE_STEAL_ON_HIT` (237), `ENERGY_ON_HIT` (238), a dead member a wide carrier's candidate (240), a
`SINGLE` `TILE` entry (241), the hit given to every set's actor (243). 2 survive, reported to track
game: a bomb or a trap taking held penetration (row 232 throws the bomb holding `PENETRATION` of
scope `ALL`, but `resolve` reads a bomb's or a trap's penetration nowhere, Cairo's neither: only an
`offence` row of scope 3 can tell it); the source in its own hit's set (row 239 puts it there, but
the source's bits reach `apply` only, where `HIT_BIT` is entry 3's bit, and skill 82 holds one
entry: a carrier of four entries is needed). A 17th, two actors of a carrier whose
index order is not their position order, is killed since lot F by `tick.jsonl`'s row 85 (the Cinder
Ring kills goblin 9 before goblin 8: tile order). Three are `equivalent`: a refusal's words stored back
(every refusal comes before any write, and a store of a load gives the words back); the awake
goblins written at once rather than gathered (the mirror's world is one array); a trap placed on a
wall (through `act`, `aim`'s reach refuses a walled tile first).

## The ticks

`src/tick.ts` is `TickLibrary::ticks`, computed (CLI-02g-F, D-257): `ticksClass` loads the words
through the content and runs `TickTrait::run` with `Delegate`'s rules and a fresh `Cache`, then
stores the words back; `src/index.ts` exports it as `tickTicks`, a `Classes.ticks`. One tick: the
adventurer at 0 before it stops it (step 5 only); step 0 the clock, the flags, perception and the
awake set (`perceive`: design/18's table, a noticing goblin's pack engaged, the eight nearest by
`movement.ts`'s `awake`); step 1 the members' activations due, then the awake set's, ascending
(`conclude`, `lapse`, a recovery over cleared), each concluded carrier through `legal` and
`action.ts`'s `carry`; step 2 (`step`); step 3 (`regenerate`); step 5 (`segment.ts`'s `check`).
The world is one array of goblins with their awake flags: a write is immediate where Cairo gathers
pending ones, which it flushes before every executor call and when the step ends, so every read
sees the same values.

Step 2 crosses `AiLibrary`'s boundary as Cairo does: `step` stores the members and the awake set,
computes the frozen goblins' tiles and the roster count (D-238), and `src/ai.ts`'s `aiClass` runs
`AiTrait::step` on that world with a fresh `Cache`: each goblin's act (its first usable skill, its
weapon, a step on the tick's flood toward the adventurer or away, the roster's hold), each carrier
through `carry`, each trap entered through `trap.ts`'s `triggerClass`; the words come back loaded.
Step 1's and step 2's carriers run on their call's whole world (lot E's reading of `Delegate`'s
sub-world). `segment.ts`'s `path` is `SegmentTrait::ticks`' choice (the class, the fast path,
none), which `tick.jsonl`'s `skip` rows hold.

`tick.jsonl`'s rows are its README's: row 0 the content, 120 `ticks` rows (one call of the class
each) and 10 `skip` rows. `segment2.jsonl`'s `ticks` calls (25, in rows 2–4, 6, 10, 12–14, 16–22,
25, 29, 46 and 47) are computed by the port and equal their recordings (`src/parity/parity.test.ts`).

Of the tick's 156 mutants, 103 are killed by the tables (and three earlier survivors with them:
the fast path's adrenaline decay, `tick.jsonl` row 20; `entries`' dead entrant and the actors'
position order, row 85). Eight are `equivalent`: the attackers' cap (the awake set holds at most
8); step 2 called with a goblin knocked down to `T`, busy or resolved and no other free (three
mutants: `AiTrait::capped` checks the same, and acts on none); a member at 0 read by perception or
regenerated in step 3 (two: the tick stops first); a `SELF` carrier's target checked (its source,
alive, on its own tile); the frozen tiles in a step's `blocked` (they are the flood's obstacles,
never in a layer). 45 survive, holes of `tick.jsonl` reported to track game:

- perception: no row with two members in the window (a goblin's nearest; a notice by the first
  undone by the second); no goblins of two chunks (the pack's chunk); no Alerted goblin in a
  noticing pack;
- step 1: no two goblins concluding at `T` whose order matters; no goblin activating its caste slot
  3; no goblin killed in step 1 while activating; no activation whose target has died or left the
  reach (`legal`, and its dead target); no lapse below the stored recharge; no concluding skill
  that is not an attack with `k ≥ n + 2`; no concluding caste skill whose entries change with the
  rank; no member's carrier bringing a member to 0; no member down or gone before a companion (the
  goblins' target), nor member 0 outside the board's window;
- step 2: no companion alive when the adventurer is downed in step 1 or 2; no awake set holding a
  resolved or dead goblin beside one free to act (`capped`'s checks, two mutants);
  no Runt reaching its empty slots 2 and 3; no goblin starting an activation of 1; no instant
  non-attack skill of a goblin whose weapon costs `k > 1`; no goblin skill addressing a `TILE`; no
  caste skill used now whose entries change with the rank; no goblin turning to use a skill or its
  weapon (they all face the adventurer); no `MOVEMENT` effect held by a crippled goblin stepping
  (two mutants); no flood stopped at its cap (three: `FLOOD_DEPTH`, `next_step_away`'s top layer
  and its unreached walker); no frozen goblin on a shortest path; no dead goblin on a path (awake
  or frozen); no adventurer on an unwalkable tile; the roster (D-238): no awake goblin away at a
  full roster, no two walkers leaving in one step, no step between two chunks away from home, no
  step home freeing an entry, no Fleeing goblin held by a full roster; no trap killing its entrant
  or changing a member; no goblin dying in step 2;
- step 3: no caste whose health regeneration is not 0 pips; no Engaged goblin outside the set with
  a member's adrenaline above 0.

"`fits` compares with the goblins before the segment" is `equivalent` since track game's ruling in
RV-03a2 (`contracts/logic/vectors/README.md`, `segment2.jsonl`): it differs only for a goblin whose
AI state goes back to the segment's start after an Engaged-only change, and no AI state leaves
`ENGAGED` but for `DEAD`.

## Where the vectors come from

The tables are printed by the tests of `grimworld_logic` and kept in `contracts/logic/vectors/`
(their format is its README); CI's `contracts` job runs `check.py`, which fails while a table
differs from what the code prints. The harness (`src/parity/`) reads them **in place**, never a
copy: CI's `client` job replays every table on every pull request, so a change of a rule on either
side fails until both agree.

- `src/parity/table.ts`: `readTable(name)`, the reader; it fails loudly on a malformed line, a
  felt not in hexadecimal, ids not consecutive from 0, an empty table. A case that panics carries
  `err` (its panic data) or `"ok": false`.
- `src/parity/replay.ts`: `replay(entry, vectors)` calls the mirror per `fn` and compares the whole
  `ok` (or the panic); it fails with the case's id on any divergence, an unknown `fn`, a count under
  the table's floor.
- `src/parity/mutants.test.ts`: the mutation check. Each mutant is one typical mistake applied to
  the mirror; the vectors must kill it. A mutant that survives is listed with `survives` (what
  the tables lack) and reported to track game: the tables are never edited from here. A kill by a
  crash (a TypeError, a ReferenceError, a stack overflow) must say with `crash` why the crash is
  the mutant's own divergence; otherwise it fails, as a broken mutant. A mutant no input tells
  from the mirror is marked `equivalent`: neither the tables nor the unit tests' cases may kill it.
  Of the 693 mutants, 51 survive and 15 are `equivalent` (since RV-03a2's rows, CLI-10m; 78 and 13
  before). The mutants run in a pool of at most four
  worker threads (`src/parity/mutate.ts`), each a few dozen mutants then a fresh one: no copy is
  written, a module hook serves the mutated file and the modules that import it from memory, and
  the modules the mutant does not reach are loaded once per worker and shared.

## How to add a table

One entry of `TABLES` in `src/parity/tables.ts`: the file name, its floor (the cases it holds),
and the mirror's function per `fn` (`""` for a table without `fn`), adapting a case's felts to the
mirror's arguments and its result to Cairo's `Serde`. Then add a mutant or more for the rule. A
mirror gets the case's id too: a table that appends a later `content` row (`trap.jsonl` 63,
`act.jsonl` 223) is read through `contentRow`, each row with the last content row before it.

## Commands

```
pnpm --filter @grimworld/sim test        # the unit tests, the parity and the mutation check
pnpm --filter @grimworld/sim bench       # the measurements (Poseidon, the replay), printed only
```
