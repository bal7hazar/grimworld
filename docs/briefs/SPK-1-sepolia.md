# SPK-1 — Latency and cost on Sepolia

> Unblocked on 2026-09-28: the owner added the Sepolia account to the machine's settings.
> Sepolia account: granted (launch with `--with-sepolia`).

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

## The Sepolia account: rules (OPERATIONS §7)
- The account is given to you by **variable names only**: `STARKNET_NETWORK`, `STARKNET_RPC_URL`,
  `STARKNET_ACCOUNT_ADDRESS`, `STARKNET_PRIVATE_KEY`. Use them by name in your scripts; **never
  print, log, echo or write a value** (not in a file, a commit, the report or a command line);
  check their presence with `env | cut -d= -f1` only if you must.
- **Every script that sends a transaction first asks the RPC for its chain id and stops unless it is
  `SN_SEPOLIA`.** Nothing is sent to any other network.
- The endpoint refuses requests without a usual `User-Agent` header: set one on every request.
- The account's balance is the owner's money on a test network: **measure, do not loop**. Plan the
  number of transactions before sending them (the counts below are the maximum), and state in the
  report how many were sent and what they cost in total.
- Use starknet.js or Python scripts; `sncast` is denied against public networks by your profile.

## How it runs
1. Deploy the measured native contracts of `spikes/SPK-2/native/` on Sepolia with the account
   (declare, deploy), and record their public addresses and class hashes in
   `spikes/SPK-1/sepolia.json`.
2. Measure from that account (the MVP's burner is the same kind of account: an account deployed by
   the game with a key it holds, ADR-0005 stage A). A burner of your own is not needed.

## Scope
- In, in `spikes/SPK-1/`:
  1. **Latency**: 50 transactions of a cheap action and 20 of the worst tick (no more); for each,
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
- Allowlist: `spikes/SPK-1/**`, `docs/research/SPK-1-sepolia.md`. Anything else is an escalation.

## Acceptance criteria
- [ ] AC-1 Latency p50, p95 and max to pre-confirmed and to accepted on L2, against ADR-0001's
      thresholds.
- [ ] AC-2 Receipts for every measured action, with the meter applied and its evidence.
- [ ] AC-3 The expedition's cost on Sepolia's figures, beside the local node's, and the verdict on
      $0.50 stated plainly.
- [ ] AC-4 No secret anywhere in the repository, the log or the report (`git log -p` shows none);
      every sending script checks the chain id first; the number of transactions sent and their
      total cost are in the report.

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7; the cost table has every measured action on
Sepolia and on the local node.
