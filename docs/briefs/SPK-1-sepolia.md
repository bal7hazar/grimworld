# SPK-1 — Latency and cost on Sepolia

> **Blocked** until the Sepolia credentials are in the orchestrator's environment (D-129).
> The orchestrator checks by variable names only; no credential ever reaches this brief, a
> log, a report or the agent.

## Agent
Title: `[Opus 5.5] SPK-1 latency and cost on Sepolia` · Profile: implement · Branch:
`chore/spk-1-sepolia`

## Goal
After this task we know, **on a public network** and from the account the MVP will use, what
an action of the game costs and how long it takes to be confirmed: latency from submission to
pre-confirmed and to accepted on L2, and the L2 gas of the same worst cases SPK-2 measured on a
local node (the worst tick under D-127, a queue of 10 moves, an exploring queue, enter, leave),
as native contracts. The owner decides the cost threshold on these figures (D-129).

## Context
- **docs/decisions/2026-09-28-cost-threshold.md** (D-129): the threshold of $0.50 for 300
  actions stays the target; nothing is decided on the local node's figures, which are probably
  upper bounds (the node meters by VM resources, mainnet and Sepolia meter these contracts in
  Sierra gas: to verify).
- **docs/research/SPK-2-cost.md** (summary, §7 to §9) and `spikes/SPK-2/native/` (merged): the
  native contracts, the capped worst-case board, the queues, the money method and scripts.
  **Reuse them unchanged**: the point is the same work on another network.
- ADR-0001 (validation table: SPK-1 latency p50 ≤ 1 s and p95 ≤ 3 s to pre-confirmed), ADR-0005
  stage A (burner: a key generated on the device, an account deployed by the game; Sepolia:
  accounts funded by the game), ADR-0007, D-127, docs/CAIRO.md, COMMON.
- Depends on: SPK-2 (merged), SPK-5b, FND-01b.

## How it runs (credentials never reach you)
1. **Before your launch, the orchestrator** declares and deploys the measured native contracts
   of `spikes/SPK-2/native/` on Sepolia with its own deployer account, and commits their public
   addresses and class hashes to `spikes/SPK-1/sepolia.json` on `main`.
2. **Your first run**: generate a burner key inside your worktree (an ignored file, never
   printed, never committed), compute its account address, write that address (public) under
   *Escalations* in `REPORT.md` as "fund this address", and **stop**.
3. The orchestrator funds that address with test STRK from its account and resumes you.
4. **Your second run**: deploy the burner account, then measure. Use a public Sepolia RPC
   endpoint (say which) through starknet.js or Python scripts; `sncast` is denied against public
   networks by your profile.

## Scope
- In, in `spikes/SPK-1/`:
  1. **Latency**: at least 50 transactions of a cheap action and 20 of the worst tick; for each,
     submission time, first pre-confirmed status, accepted on L2 (and the block), by polling the
     receipt at a fixed interval (state it); p50, p95, max.
  2. **Gas**, with receipts, for the same actions and boards as SPK-2's native part: the worst
     tick under D-127 (the capped serpentine board, owner checked), a queue of 10 moves with
     goblins following, an exploring queue, enter, leave. Record the resource bounds, the fee,
     the L2 gas, L1 data gas, and **which meter was applied** (Sierra gas or VM resources), with
     the evidence.
  3. **The money table** with SPK-2's method and scripts, on Sepolia's receipts and today's
     mainnet prices (with source and time), side by side with the local node's figures; the
     expedition's cost and the verdict on $0.50; the fixed part of a transaction measured as
     well as the receipts allow (ENG-01's cost constraint, D-129).
- `docs/research/SPK-1-sepolia.md`: everything above, the verdict stated plainly, what Sepolia
  says about mainnet and what it cannot say.
- Out: mainnet (never); a paymaster or Controller (SPK-9); any change to the measured contracts;
  `contracts/`, `client/`.
- Allowlist: `spikes/SPK-1/**` (the burner key file ignored), `docs/research/SPK-1-sepolia.md`.
  Anything else is an escalation. Spend only the test STRK the orchestrator sent.

## Acceptance criteria
- [ ] AC-1 Latency p50, p95 and max to pre-confirmed and to accepted on L2, against ADR-0001's
      thresholds.
- [ ] AC-2 Receipts for every measured action, with the meter applied and its evidence.
- [ ] AC-3 The expedition's cost on Sepolia's figures, beside the local node's, and the verdict on
      $0.50 stated plainly.
- [ ] AC-4 No secret anywhere in the repository, the log or the report (the burner key file is
      ignored; `git log -p` shows none).

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7; the cost table has every measured action on
Sepolia and on the local node.
