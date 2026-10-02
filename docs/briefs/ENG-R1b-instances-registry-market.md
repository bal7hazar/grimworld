# ENG-R1b — `Instances`, `Registry` and `Market` on the pattern, and the storage's typed slots measured

> ENG-R1's second lot (PLAN row ENG-R1: "then ENG-R1b (`Instances`, `Registry`, `Market`)"; D-143,
> D-147, D-167). **Its work can run now; its merge waits for the owner's reading of ENG-R1a**
> (#221, `d3ad22d`; PLAN row ENG-R1 and STATUS: "the owner's reading pending"), which may adjust the
> pattern or the typed slots below. Its `Registry` part waits for CBT-05a's merge (overlap below).

## Goal
After this task **`Instances`, `Registry` and `Market` read and write their storage only through a
store**, as typed models, on the pattern ENG-R1a set for `Hub` (`contracts/persistent/src/store.cairo`,
`HubStoreTrait`): no word offset, no raw storage syscall, no map access left in their systems; the
checks in `Assert` impls; the unit tests beside their code. And **the open question of ENG-R1a's
report (the audit's note 4) is answered by a measurement**: the storage declared with typed slots, as
`quiver` does, built for one contract first, measured against the current store, then kept or
dropped by the rule in *Scope*. **Nothing a player or the indexer sees changes**: the same
entrypoints, the same storage layout, the same events in the same order, the same results.

## Context
- **The pattern**: docs/CAIRO.md §7 (layers, scoped functions, every stored entity a model, the store
  emits on write), §8 (the organisation lens), §2 (D-167: unit tests in their module's file).
  **The reference is ENG-R1a as merged**: `contracts/persistent/src/store.cairo` (its module doc:
  stored models, tracking, layers), the stored models `models/stored_*.cairo` and `models/lanes.cairo`,
  and its archived report `docs/reports/ENG-R1a-hub-on-the-pattern.md` (*For the owner*, *Differences
  from `quiver_quest` 0.2.0's pattern*). Behind it, `quiver_quest` 0.2.0 (`bal7hazar/quiver`,
  `origin/main` `2e6bb77`; on the VPS at `/home/claude/projects/quiver`): `packages/quest/src/store.cairo`.
- **Note 4, the typed slots** (ENG-R1a's report, *Open question for the owner*, lines 56–63, and
  *Fix loop 3*, line 451):
  - quiver declares its storage with its stored slot types (`Quest_definitions: Map<u32, HeadSlot>`,
    `packages/quest/src/component.cairo:58`; `HeadSlot` a `StorePacking<HeadSlot, felt252>`,
    `models/definition.cairo:362`), so its store reads each slot typed and does no address arithmetic;
  - `Hub` declares the full models (`adventurers: Map<u32, Adventurer>`) and its store reads the
    stored words at offsets through `__storage_pointer_address__` and `Store::<felt252>::read_at_offset`
    / `write_at_offset` (`WordImpl`, `store.cairo:554`), for the adventurer's words, `accounts`'
    record, the list, balance and pack pages; `test_adventurer_offsets` pins the offsets;
  - the alternative keeps the same slots and addresses (a struct's members are consecutive slots
    under the entry's address), so ENG-01 §3.3's layout and the probe's stream stay equal; its cost
    was **not measured**; the implementer recommended "do it in ENG-R1b, measured beside `Instances`'
    own storage".
- **`Instances`** is in the ephemeral package, **`contracts/ephemeral/src/systems/instances.cairo`**
  (ENG-01 §3.2, §4.1), and its ENG-06 audit's F-2 is this lot's (PLAN row ENG-R1;
  `docs/reports/ENG-06-audit-gpt-6-astra.md`, F-2: "`Instances`' raw storage syscalls, lifecycle map
  access", `Hub.change_pack`'s part being done by ENG-R1a, report line 72). On `origin/main`:
  - `Storage` (lines 199–225); `WordImpl`'s `word`/`set_word` over `read_at_offset`/`write_at_offset`
    (600–611); `.word(` in `instance_state` (418–466: the header, task pages, members' eight words, revealed
    set, quotas) and `leave` (373, the member's `stats`); `set_word` of the member's three transient
    words in `begin` (698–700); direct `.entry(`/`.read(`/`.write(` in
    `create`, `set_controller`, `set_contracts`, `set_admin`, `admit`, `begin`, `close`, `write_tasks`;
  - `contracts/ephemeral/src/store.cairo`: `StoreTrait::set_snapshot`, the snapshot's three words
    written at `Member`'s offsets (CBT-02e, D-168), its module doc saying it waits for this lot;
  - `Member` (`models/member.cairo:336`) is already a struct of per-slot models (`MemberState`,
    `MemberTimers`, … each a `StorePacking` to one felt, offsets `TIMERS_WORD`…`STATS_WORD` at 20–23),
    and the code already writes some fields typed (`member.state.write`, `member.controller.write`).
- **`Registry`**, `contracts/persistent/src/systems/registry.cairo` (ENG-01 §3.5): `Parts` (52–78)
  reads and writes a record's parts by raw `storage_read_syscall`/`storage_write_syscall` at a Pedersen
  key computed once (a measured saving, pinned by `test_part_address_is_the_maps`); `last_ids`,
  `records` and `caste_skills` read and written in `set_record` (196–226) and `name_skills` (357–387);
  the versions already through `StoreTrait::get_versions`/`set_versions` (`store.cairo:497–503`, whose
  module doc, line 42, says "`Registry`'s storage is ENG-R1b's"). Its checks are already
  `RegistryAssert` (246–349) inside the contract module.
- **`Market`**, `contracts/persistent/src/systems/market.cairo` (ENG-01 §3.4, §4.4): every entrypoint
  reverts `NOT_IMPLEMENTED` (113–181); only the constructor writes storage (104–109). Its models are in
  `models/market.cairo`.
- **D-149** (the indexer is lent to track CV; `indexer/emitter/` is theirs): as in ENG-R1a's brief,
  **no event may change**: not its name, keys or data, nor where, how often or in which order it is
  emitted. A model whose writes match one ENG-01 §5 event exactly may become tracked with it; one
  that does not stays untracked and its event stays where it is emitted today, with a written reason.
- **The event and layout check**: `contracts/tools/lifecycle_probe.py` (its doc, lines 46–57) records
  `Hub`'s storage and events and `Instances`' events **by selector only** ("its draws follow the
  transaction hashes, which follow the addresses"); `--expect contracts/tools/lifecycle-stream-before.json`
  is the contract every lot touching `Hub`'s storage or events runs. It records nothing of
  `Instances`' or `Registry`'s storage.
- **Cost**: D-144 (`docs/decisions/2026-09-29-eng-04-budgets.md`, decision 1): a measured replacement
  is accepted **by the orchestrator up to +10 %**; beyond +10 %, **or on the expedition's path (`play`,
  the actions sent alone, `enter`, `leave`, `travel_back`)**, it goes to the project manager. So a rise
  of `leave`, `travel_back` or of `create` (which `enter` calls) is the project manager's at any size.
  ENG-01 §1.3: a class under 50 % (`Instances` 29.05 %, `Registry` 30.23 % at CBT-02f's report,
  line 37: re-measure). Pinned figures are generated on Linux only (OPERATIONS.md §3, #280). COMMON.md.

## Scope
- In:
  - **One store per contract**, implemented on that contract's state as `HubStoreTrait` is
    (`InstancesStoreTrait` in `contracts/ephemeral/src/store.cairo`, replacing `StoreTrait`;
    `RegistryStoreTrait` and `MarketStoreTrait` beside `HubStoreTrait` in the persistent store, which
    then loses its two path methods): `get_x`/`set_x` per model, focused reads and writes where a path
    needs less than the model (a member's one word, a header word for a view, a record's parts).
    **Every storage access of the three systems** goes through it. `Registry`'s pre-hashed part
    addresses stay as a measured saving, inside the store, with their test.
  - **Note 4, measured, in this order:**
    1. **`Instances` first**: its `Storage` declared with typed slots (one-felt stored types for the
       words now read or written at offsets: the member's transient and snapshot words, the header,
       revealed set and quotas words the view returns), so that `WordImpl`, the offsets and
       `__storage_pointer_address__` leave it. **Measured against the offset store** it replaces: test
       pairs on the same paths (a view's read, `begin`'s writes, `set_snapshot`), and every
       entrypoint's figure before and after.
    2. **The rule**: typed slots are kept for `Instances` if `test_instances_storage_addresses` and the
       probe's comparisons stay equal and the cost holds D-144 (no rise of `create`, `leave` or
       `travel_back` without the project manager; at most +10 % elsewhere). Then the same change is
       made to `Hub`'s declaration (`adventurers`, `accounts`, `account_adventurers`, `balances`,
       `packs`), measured the same way under the same rule, with `layout_tests`,
       `test_adventurer_offsets` (or its typed equivalent) and `--expect` equal. If `Instances`' measure
       fails the rule, stop there: `Hub` is not changed, and the report gives the figures.
    3. A slot the rule refuses keeps its offset access in the store, with a line above it naming the
       measure.
  - **Checks** into `Assert` impls with `errors` modules (the inline `assert`s of `create`,
    `set_controller`, `set_contracts`, `set_admin` in `Instances`); **free functions** in the files
    this lot touches scoped in traits or justified in a line above them (CAIRO §8; `instance_parts`
    and `exists` are the logic package's, ENG-R1c's).
  - **Tracking**: for each model of the three contracts, tracked or not and with which event, decided
    under D-149's constraint, a table in the report, as ENG-R1a's.
  - **Tests**: the unit tests of every module this lot touches moved into it (D-167); integration and
    benchmark tests stay in `tests/`. **The probe extended**: it also records `Instances`' and
    `Registry`'s storage keys with their last values and `Instances`' events with keys and data, every
    value the entry draw feeds (the entropy word, any field derived from it) recorded by key only;
    the "before" stream of this extension recorded **from the lot's base on `origin/main`, before the
    first code change**, as a new file `contracts/tools/lifecycle-stream-before-r1b.json`; the run
    against `lifecycle-stream-before.json` passes unchanged.
- Out: the logic package (ENG-R1c); `Registry`'s validators and `RegistryAssert`'s content checks
  (CBT-05a's while it runs; their place is an open question below); `Market`'s entrypoints (their own
  lot); store methods for paths no code takes yet; any change of an interface, a storage layout, an
  event, a rule or a figure the design states; `indexer/emitter/` (track CV's, D-149).
- Allowlist: `contracts/ephemeral/src/**`; `contracts/ephemeral/tests/**`; `contracts/persistent/src/store.cairo`,
  `systems/registry.cairo` (but its validators: `RegistryAssert::assert_record`, `assert_content` and
  what they call), `systems/market.cairo`, `models/**` (stored types and `Assert` impls for the three
  contracts, and for `Hub` only under step 2 of the rule), `systems/hub.cairo`'s `Storage` struct
  (step 2 only); `contracts/persistent/tests/**`; `contracts/tools/lifecycle_probe.py` and the new
  `lifecycle-stream-before-r1b.json`; `docs/architecture/ENG-01-interfaces.md` §3.2, §3.4, §3.5 where they
  name an access path; `GAS.md` and `docs/BUDGETS.md` as generated. Anything else is an escalation.
  **Overlaps, hence when it starts:**
  - **CBT-05a** (in progress; allowlist `contracts/logic/src/**`, `registry.cairo`'s validators,
    ENG-01 §9.2, `GAS.md`, `BUDGETS.md`): this lot's `Registry` part starts **after CBT-05a merges**,
    on `origin/main` merged in; `Instances`, `Market` and note 4's measurement can start now.
  - **FND-11** (briefed; toolchain, CI, every `Scarb.toml`/`Scarb.lock`, the generated gas files,
    `contracts/tools/` for the probe's pins): whichever merges second merges `origin/main` and
    regenerates `GAS.md` and `docs/BUDGETS.md` (never by hand); if FND-11 merges before this lot's
    "before" stream is final, that stream is re-recorded from the new `origin/main`, never from this
    lot's code.

## Acceptance criteria
- [ ] AC-1 No storage access in `systems/instances.cairo`, `systems/registry.cairo` or
      `systems/market.cairo` but through their store: a grep for `.read(`, `.write(`, `.entry(`,
      `set_word`, `word(`, `_syscall(`, `read_at_offset`, `write_at_offset` in each file, shown in the
      report, finds none outside tests, or each with its written reason.
- [ ] AC-2 Checks in `Assert` impls with `errors` modules; no free function without a reason (CAIRO §8).
- [ ] AC-3 **The same storage layout and the same events**: the three contracts' layout tests equal;
      `lifecycle_probe.py --expect contracts/tools/lifecycle-stream-before.json` and the extension's
      `--expect` against `lifecycle-stream-before-r1b.json` equal, both outputs in the report.
- [ ] AC-4 **Note 4 answered by figures**: the test pairs and the per-entrypoint table of step 1, the
      rule applied, its outcome for `Instances` and, if reached, for `Hub`; the store's module docs
      say which slots are typed and which keep offsets, and why.
- [ ] AC-5 Gas: every budget holds; a rise is a replacement under D-144 (its reason above the budget;
      `create`, `leave`, `travel_back` to the project manager at any size; beyond +10 % elsewhere, an
      escalation); every class under 50 %.
- [ ] AC-6 The tracking table; unit tests in their modules (D-167); CI green; `gas_budgets.py --check`;
      `class_sizes.py`.
- [ ] AC-7 **For the owner's reading**, as ENG-R1a's AC-6: the report opens with the files to read in
      order (the stores, one stored type, `instances.cairo`'s `leave` and `instance_state` as they read
      now, one module's tests), one line each on what changed and why, and the differences from
      ENG-R1a's pattern with their reasons.

## Audit
This lot meets the exception rule as a large refactoring (OPERATIONS.md §6, "ENG-R1's lots"): one
audit, the organisation lens (CAIRO.md §8); the orchestrator decides at the close.

## Verification
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py --expect contracts/tools/lifecycle-stream-before.json
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py <the extension's option> --expect contracts/tools/lifecycle-stream-before-r1b.json
grep -nE '\.read\(|\.write\(|\.entry\(|set_word|word\(|_syscall\(|read_at_offset|write_at_offset' \
  contracts/ephemeral/src/systems/instances.cairo contracts/persistent/src/systems/registry.cairo \
  contracts/persistent/src/systems/market.cairo
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7, opening with AC-7's section for the owner; then each
store's methods, note 4's measurement and the rule's outcome, the tracking table, the layout and event
comparisons, the tests moved, the gas table of every test.

## Open questions
1. **Which contract first for note 4.** The sources name `Instances` ("measured beside `Instances`' own
   storage", ENG-R1a's report line 63) while the question is about `Hub`'s declaration.
   *Recommendation*: `Instances` first, as written above: its `Member` is already a struct of
   one-felt models, so the typed declaration is nearest there and the measure is cleanest; `Hub`
   follows under the same rule in this lot rather than reopening ENG-R1a's lot.
   **Decided by the orchestrator, 2026-10-02:** as recommended.
2. **`RegistryAssert`'s place.** CAIRO §7 puts `Assert` impls in `models/`; `RegistryAssert` sits in the
   contract module and its content checks are the validators CBT-05a edits. *Recommendation*: leave it
   where it is in this lot; move it after CBT-05a's merge, in ENG-R1c or a fix loop, so that two lots
   never edit the validators at once.
   **Decided by the orchestrator, 2026-10-02:** as recommended.
3. **A CI job for the probe.** ENG-R1a's escalation (report line 325): the probe's `--expect` runs by
   hand. *Recommendation*: not in this lot (`.github/` is the orchestrator's and FND-11 owns CI now);
   a CI job running both `--expect` through `scripts/with-node.sh` after FND-11.
   **Decided by the orchestrator, 2026-10-02:** as recommended.
4. **`Market`'s tracking.** Its events (`LotPosted`, `LotClosed`, `TradeOpened`, `TradeClosed`) are
   emitted by no code yet. *Recommendation*: no model tracked here; the lot that writes `Market`'s
   entrypoints decides, under D-149.
   **Decided by the orchestrator, 2026-10-02:** as recommended.
