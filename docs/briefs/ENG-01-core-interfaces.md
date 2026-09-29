# ENG-01 — Freeze the core interfaces, under a cost budget

> Launched after FND-04 (the budgets) is merged. The orchestrator reviews the design with the agent
> at two points (below); the project manager decides what the design leaves open.

## Agent
Title: `[Opus 5.5] ENG-01 core interfaces` · Profile: implement · Branch: `feat/eng-01-core-interfaces`

## Goal
After this task the game's contracts have **frozen interfaces**: every entrypoint, view, event,
storage layout and registry shape the MVP needs, with the boundaries between contracts, each one
with a **cost budget** (storage slots changed per transaction, L2 gas) that the implementation
tasks (ENG-02 to ENG-10) build against. Interfaces are Cairo code that compiles (traits, types,
events, storage structs) with no game logic, and a document that says why each is shaped so.

## Context (read in this order)
1. **The cost constraint** (D-129, D-133, `docs/decisions/2026-09-28-sepolia-verdict.md`): $0.50 per
   300 actions is the target; fights are played on the client and sent in batches.
   - **Storage slots first**, measured on our receipts by FND-04 (`docs/research/FND-04-slots.md`):
     about **453,500 L2 gas per new slot** (zero before) and **32,000 per overwritten or zeroed slot**,
     per transaction, beyond the write's computation; a batch that changes the same slot pays it
     once. New keys are what cost: `enter`'s 1.9M is its 4 new slots; a slot zeroed by `leave` is new
     again at the next `enter`. Quiver's 402,000 (`docs/decisions/2026-09-28-quest-cost-cap.md`) is of
     the size of a new slot.
   - **design/02's 40M batch bound leaves out the window assembled from chunks** (SPK-7): a batch of
     10 worst ticks with the window at each tick is about 44.2M (FND-04, an estimate). Settle the
     bound in slots and gas with that included (design/02's OP-2 is answered by FND-04's prices).
   - The non-game part of a transaction: about 1.09M L2 gas from the owner's account, 717k from the
     MVP's OpenZeppelin burner (SPK-1 §4, SPK-1b); the fee transfer (455k) is paid by any account.
   - The worst tick: 5.13M on Sepolia (SPK-1), plus 720,000 for the chunked map (SPK-7).
   - **FND-04's budgets** (`docs/architecture/cost-budget.md`, the slot table of
     `docs/research/FND-04-slots.md`, and the ADRs after FND-04): the numbers you design to.
2. **DES-21, design/02 § Planned queues and played batches**: `play(instance_id, adventurer_id,
   sequence, actions[1..10])`, the action enum, weights, `BatchPlayed`, the sequence rules, the
   standalone Fate and gate entrypoints, the views `instance_state` and `instance_region`, the three
   kinds of chunk and D-136 (an unrevealed chunk is wall in the window until sight reveals it),
   **its list "What ENG-01 must do"**, open point OP-2 (slots).
3. The domains and ADRs: ADR-0001 (persistent and ephemeral domains, snapshot and results, the
   chain follows the player), ADR-0002 (`fate(domain)`, the providers behind an interface), ADR-0005
   (accounts), ADR-0006 (chunked maps, D-111, D-134, D-136), ADR-0007 (native Starknet, the class
   size limit, no indexer to play).
4. The indexer's interface (SPK-11, D-130): the nine events and the views `open_lot_count`,
   `trade_count`, and SPK-11 §4's correctness rules; quiver's inputs (D-131: an instance snapshots at
   most 16 task ids at entry and reports them in one aggregated call per transaction; D-135: quest
   acceptance mandatory, at most 4 quests held).
5. The design documents the MVP covers (design/09 lists them): design/01 to 07, 13 to 18 as they
   bear on storage and entrypoints; design/08's M-1…M-6 (multiplayer door); CONTEXT §5, §8.
6. docs/CAIRO.md (in full), `contracts/` (the three packages of FND-01b), COMMON.

## Scope
1. **Contracts and their boundaries**: which contracts exist, what each owns (persistent: adventurer,
   inventory, progress, registries; ephemeral: instances), who may call whom (access control), and
   the class size of each against the limit (ADR-0007): an estimate now, a measured check at the end.
2. **Storage layouts and packing**, per contract: every stored struct, its keys (instance id, never
   adventurer id, for instance state: M-1), its packing into felts, and **the slots each entrypoint
   changes**. A table: entrypoint × {slots read, slots changed, of which new}, worst case, with the
   reason for each.
3. **Entrypoints and views**, with their Cairo signatures: `play` and the standalone Fate and gate
   entrypoints of design/02, entry and leaving, the hub and persistent actions the MVP needs, the
   registry writers, `instance_state`, `instance_region`, and the views of the indexer. Bounds on
   every list argument.
4. **Events**: the indexer's nine, `BatchPlayed`, and any other the design needs, with their keys.
5. **The snapshot and the results interface** between the domains (ADR-0001): what an instance reads
   at entry, what it writes back, and when (D-131's aggregated call).
6. **Registry shapes**: regions, locations (zone outline, dungeon targets), gates, content (pillar 6:
   core systems read registries, never a hard-coded id).
7. **The randomness and account seams**: `fate(domain)` behind its interface (ADR-0002, the MVP's
   provider and version 1's requirements from DES-21); the account interface (ADR-0005).
8. **The cost budget** (`docs/architecture/ENG-01-interfaces.md` § Budget): per entrypoint, the slots
   changed and the L2 gas target, derived from FND-04; the 40M batch bound of design/02 checked in
   slots and gas; the new storage of `enter` as an item of its own (D-129 point 4); where the design
   departs from a budget, say so and why.
9. **Tests that pin the interfaces**: the code compiles; a test per contract that its storage layout
   and event keys are what the document says; the class sizes measured.

Deliverables: `contracts/` (interfaces, types, events, storage structs, stubs that revert with
"not implemented"), `docs/architecture/ENG-01-interfaces.md` (the design and the budget),
`docs/BUDGETS.md` regenerated if tests move.

**Two review points with the orchestrator** (write them in `REPORT.md` and stop at each only if the
brief allows no default): (a) after the contract boundaries and storage layouts (scope 1-2), push
and write under *Escalations* any choice that trades cost against a design rule; (b) at the end.
Design questions the documents do not settle stop that part (COMMON §2): list them, with the
options and their cost in slots and gas.

- Out: game logic (ENG-02…); the client; the indexer (IDX-01); CONTEXT §6.
- Allowlist: `contracts/**`, `docs/architecture/ENG-01-interfaces.md`, `docs/BUDGETS.md` and the
  packages' `GAS.md`. Anything else is an escalation.

## Acceptance criteria
- [ ] AC-1 Every item of design/02's "What ENG-01 must do" and of the PLAN row is answered in the
      document or the code, or listed as an escalation.
- [ ] AC-2 The slot table covers every entrypoint, worst case, with reasons; the budget per
      entrypoint is derived from FND-04 and checked against SPK-1's and SPK-2's receipts.
- [ ] AC-3 M-1…M-6 hold in the storage keys and the entrypoints (instance id keys, instance clock,
      lists of adventurers and contributors, entity-id targets, no single-writer assumption).
- [ ] AC-4 The code compiles on the repository's toolchain; layout, event and class-size tests pass
      in CI; every test has a budget (CAIRO §2).

## Report
`REPORT.md` as in COMMON §7. Audit: `[GPT-6-Astra]`, design and security lenses (PLAN: D S).
