# ENG-R1c — The logic package on the pattern: one layer per file, functions scoped, tests beside them

> ENG-R1's third lot (D-143, D-147, D-167; PLAN row ENG-R1: "then ENG-R1b (`Instances`, `Registry`,
> `Market`), ENG-R1c (the logic package)"). **A behaviour-preserving refactoring**: no game result, no
> word, no event, no class interface changes. **Waits for** the owner's reading of ENG-R1a (D-167; ENG-R1a's
> brief: "shown to the owner before any other lot of ENG-R1"), and for **CBT-05a, CBT-05b, FND-11 and
> ENG-R1b to merge**: each writes in this lot's files (see *Allowlist*). Inventory at `origin/main`
> `f55176c`.

## Goal
After this task **`grimworld_logic` follows docs/CAIRO.md §7 as `Hub` does since ENG-R1a**: every file in a
§7 layer (`models/`, `types/`, `helpers/`, `systems/`), every function scoped in a trait or justified in a
line above it, every check in an `Assert` impl with its `errors` module, every unit test in its module's
file (D-167). **Nothing anyone can observe changes**: the same vectors byte for byte, the same tick
digests, the same words in and out of `TickLibrary` and `FlattenLibrary`, the same events and storage on
the node, the same gas within D-144.

## Context
- **The pattern**: docs/CAIRO.md §7 (layers; "no `logic/` folder", D-147; functions scoped; checks in
  `Assert`), §8 (the organisation lens), §2 (D-167: "the unit tests of a module are in that module's file";
  "a test kept apart for a performance reason says so above it"). The reference is `quiver_quest` 0.2.0
  (`/home/claude/projects/quiver`, `packages/quest/src/`: `models/`, `types/`, `helpers/`, `events/`,
  `store.cairo`, `interface.cairo`, `errors.cairo`, `constants.cairo`), accepted by the owner (D-167).
- **What "on the pattern" meant for `Hub`** (ENG-R1a's brief and archived report,
  `docs/reports/ENG-R1a-hub-on-the-pattern.md`):
  - the checks into `Assert` impls with `errors`, same messages, same order (report, AC-2);
  - free functions into traits (`owner_key` became `OwnerTrait::key`, AC-2);
  - one file a stored model, with its struct, trait, `Assert`, `errors` and tests (fix loop 3, minor 1:
    the organisation audit found "each stored model has its own file" untrue until then);
  - unit tests moved from `tests/` into the modules; the integration and benchmark tests stay
    (AC-5; fix loop 1, finding 8: a unit test left in `tests/` needs its written reason);
  - **no change of representation where it costs**: quiver's literal shape (every word through its
    packer) cost `delete_adventurer` **+34 %** a call, against D-144's +10 % (report, *Differences from
    `quiver_quest`*); the typed stored models kept the word arithmetic and cost +0.4 % to +3.8 %.
  This lot moves and scopes code; it does not change how a word is read or written.
- **What ENG-R1a left to this lot**:
  - fix loop 1, finding 5: "`GateAssert` and `RegionAssert` are ENG-R1c's (the logic package)": `Hub`'s
    `AdventurerAssert::assert_gate` raises `gate::errors::NONE` from `grimworld_logic::models::gate`
    (`contracts/persistent/src/models/adventurer.cairo:474`);
  - `test_playable_professions`, a unit test of `grimworld_logic::professions` kept in
    `contracts/persistent/tests/test_accounts.cairo:391` "for ENG-R1c".
- **The logic package has no storage and emits no event** (`src/lib.cairo`: "Pure logic … state in, state
  out, no storage and no contract"; `grep -rn '#\[event\]' contracts/logic/src` finds none). So §7's
  `store.cairo` and `events/` have no object here: the words come in and go out of the library calls
  (`types/world.cairo`'s doc: `WordsTrait::load`, `WorldStoreTrait::store`), and the offsets are ENG-01's
  frozen ones, pinned by the ephemeral package's `test_tick_words` (`models/member.cairo`'s doc).
  **D-149**: no event of ENG-01 changes; nothing in this lot may move what `Instances` or `Hub` emit.
- **Inventory at `f55176c`** (14,897 lines in `src/`, 6,941 in `tests/`). Free functions are top-level
  `fn`; "reason" means a line above saying why no type owns it.

  | Module | Layer today | Off the pattern |
  |---|---|---|
  | `actions.cairo` | none (top level) | `Action` and four free functions without reason: `encode_action`, `decode_action`, `encode_batch`, `decode_batch` (45, 81, 139, 169) |
  | `content.cairo` | none | the record kinds; free `is_sequential` (59) and `parts` (86) without reason, `exists` (67) with one; an inline panic (87) |
  | `durations.cairo` | none | free `effective_duration` (23) without reason; two inline checks (24, 37) |
  | `fate.cairo` | none | free `domain` (35) and `derive` (41) without reason |
  | `packing.cairo` | none | 14 free functions without reason (`split`, `limbs`, `join`, `peel`, `fits`, `field`, `byte_at`, `u16_at`, `u32_at`, `low_field`, `pack_lanes32`, `unpack_lanes32`, `pack_lanes16`, `unpack_lanes16`); inline checks (55, 72, 278); imported by 18 files of `src/` and 22 of `persistent/src` and `ephemeral/src` |
  | `professions.cairo` | none | `ProfessionImpl` holds eight inline checks (42–85) beside its `Assert` |
  | `snapshot.cairo` | none | 2,801 lines, many entities in one file: `MemberStats`, `MemberBar`, `QuickCast`, `MemberKit`, `HeldPassive`, `Loadout`, `Worn`, `Snapshot`, `SnapshotWords`, `TaskEntry`, `TaskPage`, the flattening; six `Assert` impls and one `errors`; free `pack_stats`, `unpack_stats`, `pack_bar`, `unpack_bar`, `pack_kit`, `unpack_kit`, `pack_task`, `unpack_task`, `pack_task_page`, `unpack_task_page` without reason (`saturate`, `max_instances`, `fit` have one); inline checks in `FlattenImpl` and `SnapshotBuildImpl` (873–1126) |
  | `interface.cairo` | as quiver's | none found |
  | `types.cairo` | `types/`'s root | holds identifiers and bounds itself, with free `instance_id`, `instance_parts`, `goblin_entity` (29, 34, 87) without reason |
  | `types/combat.cairo` | `types/` | inline checks in `PlacerImpl` (148–159) |
  | `types/effect.cairo` | `types/` | inline checks in `EntryImpl` (290, 299); `reads` (342) has its reason |
  | `types/passive.cairo` | `types/` | free `source_bound` (111) without reason |
  | `types/tick.cairo` | `types/` | inline checks in `IndexImpl` and `SheetsImpl` (373–476); unit tests in file |
  | `types/hit.cairo`, `types/window.cairo`, `types/infliction.cairo` | `types/` | an inline check in `WindowImpl` (282); unit tests in file |
  | `types/world.cairo`, `types/world/fixtures.cairo` | `types/` | the pipeline as `World`'s behaviour (its doc gives the reason, D-147); `fixtures.cairo` is test code with four free functions without reason (`two`, `opaque`, `activation_of`, `run`) |
  | `models/member.cairo`, `models/goblin.cairo` | `models/` | one inline check each in the `ConditionImpl`s (696, 484); unit tests in file |
  | `models/{armor_set,base,caste,gate,item,location,modifier,outline,region,skill}.cairo`, `models/index.cairo` | `models/` | on the pattern (struct, trait, `Assert`, `errors`); **their unit tests are in `tests/`** (`test_models`, `test_combat`, `test_validators`, `test_capacity`, `test_build`, `test_build_records`, `test_lifecycle`) |
  | `helpers/{exp2,exp2_table,signed,tick}.cairo` | `helpers/` | scoped; `exp2`'s tests in `tests/test_exp2.cairo` |
  | `systems/{tick,flatten}.cairo` | `systems/` | the library classes; on the pattern |

  The inline checks above are the counts of a scan outside `Assert` impls and test modules; some may be
  unreachable `match` arms. The implementer's inventory (AC-1) settles each one.
- **Tests in `tests/`**: 16 files, 419 tests. Only `test_flatten` and `test_tick` declare or call a class
  (`grep -lE "declare\(|library_call|deploy"`); `test_hit_cost` is a benchmark (CBT-03a). The others are
  unit tests of one module each, per their headers, with no written reason to stay apart.
- **The behaviour's witnesses**: `contracts/logic/vectors/` (`hit.jsonl`, `window.jsonl`, the client's
  mirror, D-140; `check.py` in CI, `.github/workflows/ci.yml:150-155`; the tests hold each part's digest);
  `test_tick`'s digests (`digest`, `script_digest`, `tests/test_tick.cairo:2721-2738`); the node probe
  `contracts/tools/lifecycle_probe.py --expect contracts/tools/lifecycle-stream-before.json` (ENG-R1a,
  AC-3: "every later lot touching `Hub`'s storage or events runs `--expect`"); every test's gas in
  `GAS.md` and `docs/BUDGETS.md`; `class_sizes.py` (ENG-01 §1.3: a class under 50 %).
- **Where the logic package is named outside it**: `docs/architecture/ENG-01-interfaces.md` names
  `grimworld_logic` paths 14 times and `encode_batch`, `decode_batch`, `effective_duration`;
  `docs/design/19-effects.md` and `docs/design/20-castes.md` name `effective_duration` (5 times). The
  logic package is not published (no `scarb publish`; D-132), so its paths are not a published
  interface; ENG-01's ABI, words, layouts and events are, and none of them moves here.
- D-144 (ENG-R1a's brief: "a measured replacement accepted up to +10 %"), D-154, D-176 (measured builds
  single-threaded, `scripts/lock.sh` sets it), OPERATIONS §3 (pins generated on Linux only, #280),
  COMMON.md.

## Scope
- In:
  - **Every module of `contracts/logic/src/` in a §7 layer**: the top-level modules (`actions`,
    `content`, `durations`, `fate`, `packing`, `professions`, `snapshot`) moved into `types/`, `models/`
    or `helpers/` by what they hold; `types.cairo`'s own items into files of `types/`; `interface.cairo`
    stays where quiver has it. **`snapshot.cairo` split one file an entity** (the member's three words,
    the task page, the build's worn set and loadout, the flattening), each with its trait, `Assert`,
    `errors` and tests, as ENG-R1a did for `Hub`'s stored models.
  - **Free functions scoped in traits** (`PackingTrait::split`, `Lanes32Trait::pack`, `ActionTrait::encode`,
    `FateTrait::derive` or the names the implementer finds clearer, short and scoped, CAIRO §7), or
    justified in one line above them (CAIRO §7: "a constant table"). The test fixtures included.
  - **Checks in `Assert` impls** with `errors`, same messages, evaluated at the same point (ENG-R1a,
    AC-2); a `match` arm that cannot be reached stays, with its reason.
  - **`GateAssert` and `RegionAssert`** in the logic package's `models/gate.cairo` and `models/region.cairo`
    where a check of a gate or a region is the logic package's; `Hub` calls them (ENG-R1a fix loop 1,
    finding 5). The open question below says how far.
  - **Unit tests into their modules** (D-167): every test of `tests/` that needs no declared class and is
    no benchmark; `test_playable_professions` from the persistent package. What stays in `tests/` says why
    above it.
  - **Call sites** in `contracts/persistent/src`, `contracts/ephemeral/src` and their `tests/` updated to
    the new paths and names, and nothing else in those files.
  - **The proof of behaviour** (AC-3, AC-4): the vectors, the digests, the node probe and the gas
    compared against the lot's base commit.
- Out: any change of a rule, a word's layout, an offset, an encoding, an event, an ABI, a library class's
  interface, a budget's figure beyond D-144; a representation change of a word (typed packers where the
  code uses limb arithmetic: ENG-R1a measured its cost); `Instances`, `Registry`, `Market` (ENG-R1b);
  `Hub` beyond its call sites and `assert_gate`; new features of CBT-05, ENG-05, ENG-07; the design
  documents (they name rules, not paths).
- Allowlist: `contracts/logic/src/**`, `contracts/logic/tests/**`, `contracts/logic/vectors/README.md`
  (its test names, if a test moves; the `.jsonl` files never change); in `contracts/persistent/` and
  `contracts/ephemeral/`, `src/**` and `tests/**` **for imports and call sites only**, plus
  `contracts/persistent/src/models/adventurer.cairo` for `assert_gate`; `docs/architecture/ENG-01-interfaces.md`
  where it names a moved path or name; `contracts/*/GAS.md` and `docs/BUDGETS.md` as generated.
  Anything else is an escalation.
  - **Overlaps, and therefore when it starts**:
    - **CBT-05a** (running): its allowlist is `contracts/logic/src/**`, `registry.cairo`'s validators,
      ENG-01 §9.2, `GAS.md`, `docs/BUDGETS.md` (its brief). Every file of this lot.
    - **CBT-05b** (not briefed; PLAN row CBT-05: the action's costs, §5.3, and traps, §5.11): the tick
      in `contracts/logic/src/`, and its generated gas files.
    - **FND-11** (briefed, next after CBT-05a, STATUS): the toolchain, CI, every `Scarb.toml` and lock,
      every generated gas file re-measured.
    - **ENG-R1b** (waits for the owner's reading): `Instances`, `Registry`, `Market`, the files whose
      call sites this lot changes.
    - **ENG-05, ENG-07** (todo): they write the reveal and the window's assembly; if either starts in
      `contracts/logic/src/` first, this lot waits for it too.
    - **The order proposed**: ENG-R1c starts when CBT-05a, CBT-05b, FND-11 and ENG-R1b have merged and
      the owner has read ENG-R1a, on a base where no lot runs in `contracts/logic/src/`, and none starts
      there until it merges. **Why not a split around CBT-05**: `packing`'s free functions are imported by
      18 files of `src/` (the tick's `models/member.cairo`, `models/goblin.cairo` among them) and 22
      files of the other two packages, so scoping them touches CBT-05's files whatever the cut; and a
      behaviour-preserving proof needs one fixed base commit for its vectors, digests and gas, which a
      moving executor does not give.

## Acceptance criteria
- [ ] AC-1 **The inventory**: the report opens with the table above re-made at the lot's base commit
      (modules moved, free functions, inline checks, tests), and for each row what the lot did. A grep
      for top-level `fn` in `contracts/logic/src` (shown) finds only functions with their reason above.
- [ ] AC-2 Every module in a §7 layer; one file an entity in `models/` with struct, trait, `Assert` and
      `errors` where it owns checks; checks with the same messages at the same point; CAIRO §8 items 1, 2
      and 4 hold (item 3, tracking, has no object: no storage, no event).
- [ ] AC-3 **Game results unchanged**: `git diff --exit-code <base> -- contracts/logic/vectors/*.jsonl`
      empty and `vectors/check.py` passes with every digest unchanged; `test_tick`'s digests and expected
      values unchanged; no assertion of a test changed but its imports and names (a test whose body
      changed says why in the report); the node probe's `--expect` gives `"stream": "equal"`.
- [ ] AC-4 **Gas**: every budget holds; `gas_budgets.py --report` against the base, with a table of the
      moved tests (old path, new path, before, after); a rise is a replacement under D-144 (≤ +10 %, its
      reason above the budget), beyond that an escalation; the tick's worst-case benchmarks
      (`test_tick`, CBT-02d's bound) and ENG-01 §9.2's share reported before and after;
      `TickLibrary` and `FlattenLibrary` under 50 % (`class_sizes.py`).
- [ ] AC-5 Unit tests in their modules (D-167), `test_playable_professions` included; what stays in
      `tests/` has its reason above it; CI green; `gas_budgets.py --check`.
- [ ] AC-6 Every path or name that ENG-01 states and that moved is updated there; none of ENG-01's ABI,
      words, layouts or events changed.

## Verification
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 contracts/logic/vectors/check.py
git diff --exit-code <base> -- contracts/logic/vectors/
python3 scripts/gas_budgets.py --check && python3 scripts/gas_budgets.py --report
python3 contracts/tools/class_sizes.py
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py --expect contracts/tools/lifecycle-stream-before.json
grep -rnE '^(pub )?fn ' contracts/logic/src
```
Gas, class sizes and snapshots are generated on Linux only (OPERATIONS §3).

## Audit
This lot meets the exception rule as "a large refactoring (ENG-R1's lots, a package rewritten)"
(OPERATIONS §6, D-177): one audit, the organisation lens (CAIRO §8); the tests, vectors and probe carry
cost and determinism.

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7, opening with AC-1's inventory; then the new layout of
`contracts/logic/src/` (a tree), the free functions left with their reasons, the checks moved, the tests
moved, the proof of behaviour (vectors, digests, probe), and the gas table of every test.

## Open questions
1. **ENG-R1c before or after ENG-07.** ENG-07 writes in the tick and the window; landing it on the pattern
   saves it a later move, but ENG-07 is on the engine's path and this lot waits for four others and the
   owner's reading. *Recommendation*: ENG-R1c takes the first window where no lot runs in
   `contracts/logic/src/`; it never delays ENG-07 once ENG-05 and `hexx` rc.2 allow ENG-07 to start. The
   project manager orders them.
2. **How far `GateAssert` and `RegionAssert` go.** Today `Hub` reads the registry and calls
   `AdventurerAssert::assert_gate(exists)` (`persistent/src/models/adventurer.cairo:474`) with the logic
   package's error. *Recommendation*: the check moves to `grimworld_logic::models::gate::GateAssert`
   (and a `RegionAssert` for the start region if it is the region's) with the same message; `Hub`'s call
   changes, nothing else of `adventurer.cairo`.
3. **The tolerance on the tick.** The tick is 3.72× its target (STATUS, ENG-01 §9.2), and this lot moves
   code without changing it. *Recommendation*: on the tick's worst-case benchmarks any rise is an
   escalation, not a D-144 replacement; D-144 applies elsewhere.
4. **Names in ENG-01 and the design documents.** ENG-01 names `encode_batch`, `decode_batch`,
   `effective_duration`; design/19 and design/20 name `effective_duration`. *Recommendation*: update ENG-01
   (allowlisted); leave the design documents, or keep the rule's name as the method's
   (`DurationTrait::effective_duration`), since the design names a rule, not a path.
5. **`snapshot.cairo`'s split** goes to `models/` (the words are stored by the ephemeral package in the
   member's record) or `types/` (the logic package stores nothing). *Recommendation*: `models/`, as the
   registry records already are (`models/index.cairo`: records the persistent `Registry` stores), and as
   `models/member.cairo` holds the member's words.
