# SPK-1b — The fixed part of a transaction, with the MVP's kind of account

> Sepolia account: granted (launch with `--with-sepolia`).

## Agent
Title: `[Opus 5.5] SPK-1b fixed part of a transaction` · Profile: implement · Branch:
`chore/spk-1b-fixed-part`

## Goal
After this task we know how much of a transaction's L2 gas is **not the game's** when it is sent
by the kind of account the MVP will use (a burner, ADR-0005 stage A), sent directly or through a
paymaster, on Sepolia. SPK-1 measured about 1.09M L2 gas per transaction from the owner's account
(class Sierra 1.7.0, Cairo 2.11.2): validation 392,815, the account's execution about 207,000, the
fee transfer 455,360. D-133 bets on batches; this measures the part batching cannot remove, and
would reverse D-133 if it is several times smaller.

## Context
- docs/decisions/2026-09-28-sepolia-verdict.md (D-133, *What would reverse it*),
  docs/research/SPK-1-sepolia.md (§4 the method: trace invocations, the non-game remainder, the
  unattributed residuals; §7 the transactions), `spikes/SPK-1/` (merged: `lib.mjs` with the chain-id
  guard, redaction, the send cap and the run guard; `sepolia.json`, the contracts already deployed
  on Sepolia). **Reuse `lib.mjs`'s safety as it is** (copy it into `spikes/SPK-1b/`), and the
  deployed contracts: nothing of the game is declared again.
- ADR-0005 (stage A burner; stage C requirements A-3, A-5), SNIP-9 (outside execution), SNIP-29
  (paymaster API), COMMON §4 (Sepolia rules).

## The Sepolia account: rules (OPERATIONS §7)
- The owner's account comes as variables used **by name only**: `STARKNET_NETWORK`,
  `STARKNET_RPC_URL`, `STARKNET_ACCOUNT_ADDRESS`, `STARKNET_PRIVATE_KEY`; **never print, log, echo
  or write a value**.
- **Every script that sends a transaction first asks the RPC for its chain id and stops unless it
  is `SN_SEPOLIA`.** Nothing is sent to any other network. A usual `User-Agent` on every request.
- **Measure, do not loop.** At most **60 transactions and 40 test STRK in total**, declares
  included; plan them before sending; the scripts enforce the cap. Report the count and the cost.
- The burner keys you generate are secrets too: in an ignored file of the worktree, never printed,
  never committed; the burners hold only what the measurement needs (a few STRK at most).
- **No account, sign-up or API key with any third party.** A public paymaster is used only if it
  works without one; otherwise the paymaster path is measured with a relayer of our own (below).
- `sncast` is denied against public networks by your profile: starknet.js or Python.

## Scope
- In, in `spikes/SPK-1b/`, each case measured on the same cheap game action as SPK-1 (enter then
  leave, alternating, on the deployed contracts), **10 transactions per case**, with trace
  attribution as in SPK-1 §4:
  1. **Burner, direct**: an account class of the kind the MVP would deploy per player. Candidates:
     a standard single-signer class **already declared on Sepolia** (OpenZeppelin's preset, say
     which version and class hash), and, only if the numbers justify it, a **minimal burner**
     written for this spike (single signer, SNIP-9 support, nothing else; Cairo 2.19; its declare
     counts in the budget). Deploy each burner with `DEPLOY_ACCOUNT`, funded from the owner's
     account.
  2. **Burner through a paymaster**: the burner signs an outside execution (SNIP-9) and **a relayer
     pays** (the owner's account calls `execute_from_outside` on the burner). This is the on-chain
     shape of a paymaster; a public SNIP-29 paymaster may be measured beside it if, and only if, it
     needs no account or key.
  3. **The reference**: the owner's account as in SPK-1, 10 transactions, same action, same day's
     prices, so that the three are comparable.
- For each case: validate, the account's execution, the fee transfer, the game call, the
  unattributed residuals, the non-game remainder; the difference from SPK-1's 1.09M and why.
- `docs/research/SPK-1b-fixed-part.md`: the table, what the MVP's account should be for cost, what
  a paymaster adds or saves, and whether D-133's reversal condition ("a fixed part several times
  smaller") is met, stated plainly.
- Out: mainnet (never); Controller and vRNG (SPK-9); any change to the deployed contracts;
  `contracts/`, `client/`.
- Allowlist: `spikes/SPK-1b/**`, `docs/research/SPK-1b-fixed-part.md`. Anything else is an
  escalation.

## Acceptance criteria
- [ ] AC-1 The non-game remainder of a transaction for each case, with receipts and traces, beside
      SPK-1's reference measured again the same day.
- [ ] AC-2 The verdict on D-133's reversal condition, stated plainly, with the recommended account
      path for the MVP on cost.
- [ ] AC-3 No secret anywhere in the repository, the log or the report (run SPK-1's
      `check_secrets.py`, adapted to cover the burner keys too); every sending script checks the
      chain id first; the number of transactions sent and their total cost are in the report,
      within the caps.

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7. Audit: `[GPT-6-Astra]`, cost and security lenses.
