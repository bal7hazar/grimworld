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
| A budget exceeded is a failed test | A regression in cost fails the build like a regression in behaviour |
| Benchmarks are tests | One per algorithm and per entrypoint, on the **worst case** stated by the design (8 awake goblins, the longest queue, a reveal of 3 chunks), not on a convenient case |
| Figures are written down | `docs/BUDGETS.md`: per entrypoint and per algorithm, measured value, budget, date, commit. A `GAS.md` per package for the detail, as in the map library |
| Reports carry them | `REPORT.md` has a gas table: before, after, budget, for everything the lot touched |
| Raising a budget | Needs a reason written in the pull request and the orchestrator's agreement. Lowering one needs nothing |
| Oracles | An optimised algorithm is tested against a plain, obviously correct version kept in the tests (a scalar flood against the bit-parallel one) |

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
| **`u252` from `origami_hexmap`** for bitmaps and packed values | One felt, with arithmetic, bitwise operations, ordering and storage packing |
| Boards of 128 tiles or fewer | The single-limb path of the library, about a third cheaper per step |
| Smallest integer that holds the value | `u8` positions, `u16` health, `u32` identifiers |
| Packing | Several small fields in one felt, by explicit packing; layout documented next to the model |
| Signed values | Only where the rule needs them |

A chunk is 15 × 15 = 225 tiles and therefore fits a `u252`; the design chose that size
for this reason (ADR-0006).

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
