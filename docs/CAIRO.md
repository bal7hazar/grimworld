# Cairo engineering rules

Binding on every Cairo task. Referenced by every brief through `docs/briefs/COMMON.md`.
These are the owner's rules (2026-09-28); the map library `origami_hexmap` is the
reference for how they are applied.

## 1. What we optimise

> **Execution cost first.** Every player action is a transaction that the game pays for
> (pillar 7). A contract is deployed once and executed millions of times.

| When they conflict | Choose |
|---|---|
| Cheaper execution vs smaller contract | Cheaper execution |
| A lookup table vs computing at run time | The table |
| Code repeated and specialised vs one generic routine with branches | The specialised code, when it is measurably cheaper |
| Work done once at deployment or registration vs at every call | At deployment or registration |
| A precomputed field stored with the data vs derived at each read | The stored field, if it saves more than its write costs over the life of the data |

Limits that remain: the maximum size of a class, and readability. A specialisation that
saves nothing measurable is not made.

## 2. Test-driven, with gas as a test result

| Step | |
|---|---|
| 1 | Write the tests from the design document and the brief's acceptance criteria. They fail |
| 2 | Write the simplest code that passes |
| 3 | **Measure** the gas of each test |
| 4 | Optimise, following §3, with the tests as the safety net |
| 5 | Set each test's budget and record the figures |

| Rule | |
|---|---|
| Every test has a gas budget | `#[available_gas(l2_gas: N)]`, with `N = ceil(1.05 × measured)`, as the map library does |
| Fuzz and parameterized tests | One attribute covers every run or case: `N = ceil(1.05 × the most expensive)`. Cases whose costs differ widely are split into separate tests |
| A budget exceeded is a failed test | A regression in cost fails the build like a regression in behaviour |
| Benchmarks are tests | One per algorithm and per entrypoint, on the **worst case** stated by the design (8 awake goblins, the longest queue, a reveal of 3 chunks), not on a convenient case |
| Figures are written down | `docs/BUDGETS.md`: per entrypoint and per algorithm, measured value, budget, date, commit. A `GAS.md` per package for the detail, as in the map library |
| Reports carry them | `REPORT.md` has a gas table: before, after, budget, for everything the lot touched |
| Raising a budget | Needs a reason, written as `// gas: raised, <reason>` above the attribute (checked by `scripts/gas_budgets.py`) and in the pull request, and the orchestrator's agreement, given at review from the `raised` notes of the gas table. Lowering one needs nothing |
| Oracles | An optimised algorithm is tested against a plain, obviously correct version kept in the tests (a scalar flood against the bit-parallel one) |
| **Where a test lives** (owner, 2026-09-30, D-167) | The unit tests of a module are **in that module's file**, under `#[cfg(test)] mod tests`, so that whoever changes the code sees its tests. Only what needs a deployed contract or several packages (integration, an entrypoint's gas benchmark, a parity table) is in `tests/`. A test kept apart for a performance reason says so above it |

## 3. Order of preference

For any computation, try in this order and stop at the first that works:

| Rank | Technique | Example |
|---|---|---|
| 1 | **Plain arithmetic** on felts and small integers | Shifting by multiplying or dividing by a power of two taken from a table; selecting with `a + cond × (b − a)`; an index from a division with remainder |
| 2 | **Bitwise operations** | Masks, population count, lowest set bit, a whole board handled in one operation |
| 3 | **Loops**, as a last resort | Bounded, with the bound stated in the design; never over something a mask can express |

| Do | Avoid |
|---|---|
| Treat a board, a set of goblins or a set of flags as one value and act on all of it at once | Visiting tiles or items one by one |
| Tables of constants for powers, inverses, offsets | Computing them in a loop |
| Branch-free selection when both sides are cheap | Branching inside a hot path |
| Early exit with a cheap lower bound | Computing the full answer to discover it was not needed |

## 4. Types

| Rule | |
|---|---|
| **No `u256`** by default | Its operations are costly. A use needs a written reason in the code and in the report |
| **`felt252` bitmaps through `hexx`'s `Bits`** for boards and packed values (D-174; `u252` of `origami_hexmap` until ENG-02) | One felt, with the bitwise operations, ordering and storage packing of `hexx` 0.1.0-rc.1 and later; `u256` only where a board passes 252 bits, with the written reason of the first rule |
| Boards of 128 tiles or fewer | The single-limb path of `hexx`, about a third cheaper per step |
| Smallest integer that holds the value | `u8` positions, `u16` health, `u32` identifiers |
| Packing | Several small fields in one felt, by explicit packing; layout documented next to the model |
| Signed values | Only where the rule needs them |

A chunk is 15 × 15 = 225 tiles and therefore fits one felt; the design chose that size for this
reason (ADR-0006, confirmed by the owner on SPK-14, D-165).

## 5. Storage

| Rule | |
|---|---|
| Writes cost more than computation | Compute rather than store, unless §1 says otherwise |
| One write per model per transaction | Load, change in memory, write once at the end |
| Read only what the action needs | The instance reads a snapshot of the adventurer, taken once (ADR-0001) |
| Data that lives as long as an instance | Discarded with it; never migrated to the persistent domain except through the results interface |
| Events | For what is only displayed or indexed; models for what a contract must read (ADR-0004) |

## 6. What an auditor checks (cost lens)

1. Every test has a budget, and budgets match the measured figures within 5%.
2. Benchmarks cover the worst cases named in the design.
3. No loop where arithmetic or a mask would do.
4. No `u256` without its written reason.
5. No computation at run time of what could be a table or a stored field.
6. The gas table of the report matches a re-run.

## 7. Organisation of the code (owner's rule, 2026-09-29, D-143)

The layering is the one of the owner's Arcade packages (`cartridge-gg/arcade`,
`packages/quest`), without Dojo. Starknet storage replaces Dojo's models; the semantics stay.

### Layers

| Folder or file | Holds |
|---|---|
| `models/` | One file per stored entity: its struct, its `...Impl of ...Trait` (constructor and behaviour), its `...Assert` impl, its `errors` module |
| `models/index.cairo` | The structs of every model, together |
| `events/` | One file per event, same shape; `events/index.cairo` holds the structs |
| `types/` | Enums and value types that are not stored on their own (a task, a reward, a direction) |
| `helpers/` | What belongs to no entity (packing primitives, bits, a seeder), still scoped in traits |
| `store.cairo` | The only access to storage: `Store::get_x`, `Store::set_x` |
| `component.cairo` or `systems/` | Entrypoints and access control, nothing else |
| `elements/` (the game) | One file per content behaviour |

No other layer: no `logic/` folder (owner, 2026-09-29, D-147).

### Functions are scoped

| Do | Not |
|---|---|
| `#[generate_trait] pub impl DefinitionImpl of DefinitionTrait { fn new(...) -> Definition; fn is_active(self: @Definition, time: u64) -> bool; }`, called `DefinitionTrait::new(...)` and `definition.is_active(time)` | `pub fn definition_create(...)`, `pub fn definition_is_active(...)`, free functions in a file |
| Checks in `impl DefinitionAssert of AssertTrait { fn assert_valid_id(...) }` | Checks inlined anywhere |
| Short names, scoped by the trait: `Held::remove`, `Batch::merge` | `held_remove`, `batch_merge` |

A free function remains only where no type owns it and a trait would add nothing (a
constant table). An auditor reads a free function as a finding to justify.

### Every stored entity is a model

| | |
|---|---|
| A struct | Its keys and fields, named as the design names them |
| Into its storage | `StorePacking<Model, Packed>` (or `starknet::Store` derived when packing saves nothing), so that the store reads and writes the struct, never raw felts |
| Into its event | For a model the indexer tracks, a conversion `Into<@Model, ModelEvent>`, the event carrying the keys and the new values |
| Tracked or not | A property of the model, known at compile time (a trait the model implements, or a constant), never a runtime lookup |
| Optional | Tracking is optional: a model the indexer does not need emits nothing, and a package lets its consumer leave a model untracked (owner, 2026-09-29, D-147) |

### The store emits on write

`Store::set_x` writes the model and, **if and only if the model is tracked**, emits its
event, like a Dojo world does, without a world: no registry, no dispatch, no permission
lookup at run time. A model that the indexer does not need is not tracked and emits
nothing. The list of tracked models is part of the interface of the indexer (D-130).

The exact mechanism (a generic trait of the store, a macro, or a convention written by
hand), its cost against a hand-written write, and a reference implementation are
settled by task ARC-06, shown to the owner on one model before the code is reworked.

## 8. What an auditor checks (organisation lens)

1. The layers of §7; nothing stored outside a model, nothing read or written outside the store.
2. No free function without a written reason.
3. Every tracked model emits on every write, and only tracked models emit.
4. Names short and scoped; the design's words.
