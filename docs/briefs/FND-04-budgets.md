# FND-04 — Spike results into the ADRs, and the cost budget ENG-01 designs to

## Agent
Title: `[Opus 5.5] FND-04 budgets` · Profile: implement · Branch: `docs/fnd-04-budgets`

## Goal
After this task the ADRs state what the Phase 0 spikes measured, and one document,
`docs/architecture/cost-budget.md`, gives ENG-01 the budgets it designs to: per kind of transaction,
the L2 gas and the **storage slots changed**, and per expedition the dollar target, each derived
from measured figures with its source. The first input is checked on our own receipts: what a
changed storage slot costs.

## Context
- The measurements: SPK-2 (`docs/research/SPK-2-cost.md`, native part), SPK-1
  (`docs/research/SPK-1-sepolia.md`, `spikes/SPK-1/measure-output.txt`: every measured transaction's
  hash and receipt), SPK-1b (`docs/research/SPK-1b-fixed-part.md`, `spikes/SPK-1b/measure-output.txt`,
  `measure-d-output.txt`), SPK-7 (`docs/research/SPK-7-chunked-maps.md`), SPK-5/5b, SPK-11.
- The decisions: D-129, D-133 (batches; `docs/decisions/2026-09-28-sepolia-verdict.md`), D-134, D-136,
  the programme's figures in `docs/reports/SPK-1b-audit-gpt-6-astra.md` (orchestrator's note).
- **Quiver's measurement** (`docs/decisions/2026-09-28-quest-cost-cap.md`): about 402,000 L2 gas per
  storage slot a transaction changes, beyond the write's computation, once per slot and per
  transaction. The project manager asks that it be checked against SPK-2's and SPK-1's receipts.
- design/02 § Size (the 40M target of a batch of weight 10) and its open point OP-2 (slots).
- **D-137** (`docs/decisions/2026-09-28-sepolia-verdict.md`, section *After SPK-1b*; ADR-0005 stage A):
  in the MVP a burner sends directly and the game funds it; no paymaster before version 1. **Write
  every budget against the burner sending directly (717,435 L2 gas of fixed part), in batches of 10,
  with the slots changed per transaction as the first item, and state beside each budget whether
  its figure is measured or estimated.**

## Scope
1. **The slot count, on our receipts** (`spikes/FND-04/`, read-only):
   - For each measured Sepolia transaction of SPK-1 and SPK-1b (the hashes are in their outputs), read
     its trace (`starknet_traceTransaction`, a read) and count what it changed: storage slots (per
     contract), nonces, classes. Use the public Sepolia endpoint already listed in
     `spikes/SPK-2/prices.py`; set a usual `User-Agent`. **Reads only**: no account, no key, no
     sending code of any kind, no `--with-sepolia` (COMMON §4: sending lives in one module; this task
     has none).
   - Relate each receipt's L2 gas to its slots changed and its computation (the trace's invocations,
     as SPK-1 §4 does): does ~402,000 per changed slot explain the non-game residuals of SPK-1 §4 and
     the differences between actions (enter's new storage, SPK-1b's SNIP-9 nonce)? A table per
     action, and the per-slot figure our data supports, with its spread.
   - For SPK-2's native entrypoints (a local node, `scripts/with-node.sh`), the slots each changes,
     by the same trace read on devnet, if devnet reports state diffs; say if it does not.
2. **The ADRs**: a short *Measured* section (or rows) in ADR-0001 (latency and cost on Sepolia, the
   threshold's state, batches), ADR-0005 (the MVP's account on cost: an OpenZeppelin burner sending
   directly, no paymaster in the path of play; the figures), ADR-0006 (SPK-7's costs, R-12 conditional
   on batches), ADR-0007 (native against Dojo, the fixed part). Figures and sources only; no new
   decision.
3. **`docs/architecture/cost-budget.md`**: per kind of transaction the MVP sends (a batch of played
   actions, a planned queue, enter, leave, a Fate action, a reveal, the hub's actions ENG-01 will
   define): the budget in L2 gas and in slots changed, the fixed part of the burner, and the
   expedition's target ($0.50 per 300 actions, D-129) with the arithmetic from these budgets to
   dollars at stated prices. Where a budget is a guess, say so and what would measure it.
   "Power" in PLAN's row (a power budget of the adventurer) is out of scope: list it as an open
   question.

- Out: code of the game, contracts, decisions, CONTEXT, PLAN.
- Allowlist: `spikes/FND-04/**`, `docs/research/FND-04-slots.md`, `docs/architecture/cost-budget.md`,
  `docs/architecture/ADR-0001-*.md`, `ADR-0005-*.md`, `ADR-0006-*.md`, `ADR-0007-*.md`. Anything else is
  an escalation.

## Acceptance criteria
- [ ] AC-1 The slot table for every measured Sepolia transaction, from the traces, with the per-slot
      figure our data supports against quiver's 402,000, and the script and its raw output committed.
- [ ] AC-2 The ADRs carry the measured figures with their sources; no decision is changed.
- [ ] AC-3 `cost-budget.md` gives every kind of transaction a budget in L2 gas and slots, and the
      expedition arithmetic, each figure traced to a measurement or labelled an estimate.
- [ ] AC-4 No credential used or needed; no sending code anywhere in the task.

## Report
`REPORT.md` as in COMMON §7. Audit: `[GPT-6-Astra]`, cost and design lenses.
