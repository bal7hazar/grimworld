# SPK-1b — The fixed part of a transaction, with the MVP's kind of account

Measured on Sepolia on 2026-09-28, between 22:24 and 22:29 UTC, on SPK-1's deployed contracts
(`spikes/SPK-1/sepolia.json`, unchanged, nothing declared again). Scripts, receipts and traces are
in `spikes/SPK-1b/`. The numbers below come from `analyse.py`, printed in `analyse-output.txt`.

## 1. The answer

**D-133's reversal condition is not met.** The MVP's kind of account (a burner, ADR-0005 stage A)
makes the fixed part of a transaction **1.5 times smaller** than the owner's account, not several
times smaller:

- The fixed part is validation, the account's own execution, the fee transfer and the size
  residual. It is **717,435 L2 gas** with an OpenZeppelin burner sending directly, and 1,087,585
  with the owner's account (SPK-1's "about 1.09M", measured again today).
- The whole non-game remainder of the cheap action (`leave`) is **977,915** against 1,348,065:
  **1.38 times smaller**.
- **No account can do much better.** The fee transfer (455,360) and the size residual (32,600) are
  paid whatever the account. Even an account that cost nothing to validate and execute would leave
  a fixed part of 487,960: at most **2.2 times smaller** than the owner's account.
- **A paymaster makes it larger, not smaller.** With a relayer of our own the non-game remainder
  is 1.77× the reference; through AVNU's public paymaster it is 3.35×.

Batches of about ten actions divide the fixed part by about ten, so D-133 stands.

**Recommended account path for the MVP, on cost:**
- A burner of **OpenZeppelin's AccountUpgradeable preset**, the class already declared on Sepolia
  (v3.0.0, below). It sends its own transactions and pays its own fee, with STRK the game gives it
  out of sight (D-100).
- **No paymaster in the path of play.** A minimal burner written for this spike is **not
  justified** (§5); none was written or declared.

## 2. What was measured

The same action as SPK-1: `enter` then `leave`, alternating (adventurer 3, location 10). There are
10 transactions per case: 5 `enter` and 5 `leave`. Every one was traced, and every repeat of a
case gave identical figures, except one AVNU `leave` (§3). The L2 gas price did not move during
the run: 22,157,874,858 fri in every block.

| Case | Account that signs the game call | Who sends and pays |
|---|---|---|
| **A** reference | The owner's account: Braavos, class `0x3957f9f5…bf8a`, Sierra 1.7.0, Cairo 2.11.2 (as SPK-1) | the same account |
| **B** burner, direct | **OpenZeppelin Contracts for Cairo v3.0.0, `AccountUpgradeable` preset**, class `0x01d1777db36cdd06dd62cfde77b1b6ae06412af95d57a13dc40ac77b8a702381` (Sierra 1.7.0, Cairo 2.13.1, SNIP-9 v2). The hash is the one published in the release's docs, found already declared on Sepolia. Deployed with `DEPLOY_ACCOUNT`, funded from the owner's account | the burner |
| **C** burner, relayer of our own | the same burner signs a SNIP-9 v2 outside execution (caller: the relayer) | the owner's account calls `execute_from_outside_v2` on the burner and pays |
| **D** burner, AVNU's public SNIP-29 paymaster | the same burner signs the outside execution AVNU builds | AVNU's relayer sends and pays; in *default* fee mode the burner pays AVNU back in STRK inside its outside execution. No account, sign-up or key was needed (§6) |

Other OpenZeppelin account classes found declared on Sepolia are listed in `classes.mjs`'s output.
They are v1.0.0 `0x05b4b537…3564` (Cairo 2.9.4), v0.20.0 `0x02b31e19…065c` (Cairo 2.9.1), v2.0.0
`0x07fa9379…8062` (Cairo 2.11.4) and older ones without SNIP-9. v3.0.0 is the newest declared;
v4.0.0 (`0x0342f3c6…5207`) is not declared on Sepolia.

To let the burner play adventurer 3, the owner's account called the admin entrypoint `setup_hub`
with the burner's address. That entrypoint already existed; no contract was changed. The same call
gave the adventurer back to the owner at the end.

## 3. The table (L2 gas)

SPK-1 §4's method. The receipt is split into the invocations the trace attributes (validate, the
account's execution without the game call, the game call, the fee transfer) and two
**unattributed** residuals: the trace total minus the invocations, and the receipt minus the trace
total. The **non-game remainder** is the receipt minus the game call. The **account's fixed part**
is validate + the account's execution without the game call + fee transfer + the second residual:
SPK-1's "about 1.09M" is this sum. It leaves out the first residual, which is identical in A and B
for the same action: it follows what the action writes, not the account.

| Case | Action | Receipt | Validate | Account execution (without the game call) | Game call | Fee transfer | Unattributed: trace total − invocations | Unattributed: receipt − trace total | **Non-game remainder** | Account's fixed part | L1 data gas | Fee (STRK) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A owner | enter | 3,927,367 | 392,815 | 208,580 | 927,212 | 455,360 | 1,913,600 | 29,800 | **3,000,155** | 1,086,555 | 768 | 0.0879 |
| A owner | leave | 2,030,065 | 392,815 | 206,810 | 682,000 | 455,360 | 260,480 | 32,600 | **1,348,065** | 1,087,585 | 576 | 0.0456 |
| B burner direct | enter | 3,555,447 | 87,805 | 141,670 | 927,212 | 455,360 | 1,913,600 | 29,800 | **2,628,235** | 714,635 | 768 | 0.0796 |
| B burner direct | leave | 1,659,915 | 87,805 | 141,670 | 682,000 | 455,360 | 260,480 | 32,600 | **977,915** | 717,435 | 576 | 0.0373 |
| C burner via relayer | enter | 4,971,188 | 392,815 | 720,081 | 927,212 | 455,360 | 2,451,920 | 23,800 | **4,043,976** | 1,592,056 | 928 | 0.1112 |
| C burner via relayer | leave | 3,068,685 | 392,815 | 713,110 | 682,000 | 455,360 | 798,800 | 26,600 | **2,386,685** | 1,587,885 | 736 | 0.0688 |
| D burner via AVNU | enter | 7,063,760 | 400,000 | 2,798,720 | 896,320 | 455,360 | 2,473,360 | 40,000 | **6,167,440** | 3,694,080 | 1,056 | 0.1579 |
| D burner via AVNU | leave | 5,174,800 | 400,000 | 2,798,720 | 660,480 | 455,360 | 860,240 | 0 | **4,514,320** | 3,654,080 | 864 | 0.1147 |

- **The reference reproduces SPK-1 exactly.** A's receipts, game calls and invocations are those of
  SPK-1 §4, to the unit: `enter` 3,927,367 and `leave` 2,030,065.
- **One AVNU `leave` differs** (tx `0x34ee11cb…`): its validation is 320,000 instead of 400,000,
  with the same relayer class, so its remainder is 4,274,320. Why is not established.
- **Case D is metered differently.** AVNU's relayers are accounts of class `0x1a736d6e…2003`,
  Sierra 1.2.0, compiler 2.0.0 (`class-at.mjs`). Their figures are round (400,000, 80,000, 320,000)
  and the same game call costs 3% less there (`enter` 896,320 against 927,212). This is consistent
  with the transaction running in the Cairo VM and being charged by steps, because its account's
  class is too old for Sierra gas. That is an inference: it was not checked against the sequencer's
  rules.

### The account's execution, split (C and D)

| Part (leave) | C: relayer of our own | D: AVNU |
|---|---:|---:|
| The relayer's own `__execute__` | 210,350 (Braavos) | 355,840 |
| AVNU's forwarder, its own work | — | 480,000 |
| AVNU's forwarder: two STRK transfers and a `balanceOf` | — | 961,920 |
| The burner's `execute_from_outside_v2`: `is_valid_signature` | 67,765 | 320,000 |
| The burner's `execute_from_outside_v2`: its STRK transfer to AVNU | — | 440,960 |
| The burner's `execute_from_outside_v2`: its own work (nonce, time bounds, dispatch) | 434,995 | 240,000 |
| **Total, without the game call** | **713,110** | **2,798,720** |

## 4. The difference from SPK-1's 1.09M, and why

- **B (the burner, direct): −372,565** (717,435 against 1,087,585). Almost all of it is
  validation, 87,805 against 392,815. OpenZeppelin's `__validate__` checks one Stark signature;
  Braavos's goes through its signer management (multisig, secp256r1 signers, the daily withdrawal
  limit, sessions: see the interfaces in `classes.mjs`'s output). The account's own execution falls
  from 206,810 to 141,670. The fee transfer does not move: it is the STRK token's `transfer`,
  455,360 whatever the account. It is now **63% of the burner's fixed part**.
- **C (a relayer of our own): +497,885** in the account's fixed part. A relayer pays its own
  validation and execution, and the outside execution comes on top: a signature check, a SNIP-9
  nonce and the call dispatch (502,760). The first residual also rises by 538,320 for `leave`,
  260,480 → 798,800, with the same game call. The likely cause is the SNIP-9 nonce: a new storage
  key on every outside execution, like `enter`'s new instance in SPK-1 §4. That is an inference,
  not a measurement. The non-game remainder is 1.77× the reference.
  - **Derived, not measured:** with an OpenZeppelin account as the relayer instead of Braavos
    (B's validation and own execution put in place of C's), the remainder of `leave` would be
    about 2.01M. That is still twice the burner sending directly.
- **D (AVNU's public paymaster, default mode): +2,564,080.** On top of C's shape, the paymaster
  collects its fee in STRK: three token transfers (about 441,000 each), a `balanceOf`, and its
  forwarder's own work. The burner paid AVNU 1.19× (`enter`) to 1.21× (`leave`) the fee in the
  receipt. The *sponsored* mode, where the paymaster pays and takes nothing from the burner, needs
  an API key at AVNU: it was not measured (brief: no key).

## 5. What the MVP's account should be, for cost

- **The burner sends its own transactions.** Of every path measured, this one has the smallest
  fixed part: 717,435 L2 gas, and 0.0373 STRK for `leave` at today's prices, against 0.0456 from
  the owner's account.
- **Its class: OpenZeppelin's `AccountUpgradeable`, the v3.0.0 class already declared on
  Sepolia.** It is declared and audited, it supports SNIP-9 v2 (useful later, ADR-0005 stage C),
  and nothing needs declaring. Whether the same class hash is declared on mainnet was not checked
  (never touched).
- **A minimal burner is not justified.** The burner's validation and own execution are 229,475 of
  its 977,915 remainder on `leave`. A minimal account must still check a Stark signature, which
  costs 67,765 inside `is_valid_signature` here. At best it would save about 160,000: 16% of the
  remainder and 10% of the receipt. It could never reach "several times smaller" (§1: the floor is
  487,960 for the fixed part and 748,440 for the remainder of `leave`). No declare was spent on it.
- **A paymaster costs, it does not save.**
  - A relayer of our own adds 1.41M L2 gas to `leave` (+144%). Its only gain is that the burner
    needs no STRK, and D-100 is already met by a burner the game funds out of sight.
  - AVNU in default mode adds 3.54M (+362%) and charges about 1.2× the receipt fee.
  - If a paymaster is ever needed (a player without funds, a sponsored first session), it
    belongs outside the path of play. Batches (D-133) then divide its cost as they divide the rest.

## 6. The transactions and their cost (AC-3)

Planned before sending: **44 transactions**, with hard caps in the code. Each script has its own
cap, and `ledger.jsonl` records every transaction sent; `makeBudget` refuses past 60 transactions
or 40 STRK of fees, whatever the script. All 44 were sent, none twice.

| Step | Transactions | Receipt fees (STRK) |
|---|---:|---:|
| A: the owner's account, 5 × (enter, leave) | 10 | 0.6673 |
| Fund the burner with 3 STRK and give it adventurer 3 (one multicall) | 1 | 0.0627 |
| The burner's `DEPLOY_ACCOUNT` | 1 | 0.0485 |
| B: the burner, direct | 10 | 0.5847 |
| C: through a relayer of our own (the owner's account pays) | 10 | 0.9001 |
| D: through AVNU (AVNU's relayers pay the receipts; the burner paid AVNU 1.6346 STRK) | 10 | 1.3629 |
| Give adventurer 3 back to the owner | 1 | 0.0386 |
| The burner returns its STRK to the owner | 1 | 0.0287 |
| **Total** | **44** | **3.6938** |

- **The owner's money spent: 3.9654 STRK.** That is the receipts the owner and the burner paid
  (3.6938 − 1.3629) plus what the burner paid AVNU (1.6346). The burner holds 0.0988 STRK, left
  because the return kept a margin for its own fee.
- **Stops and retries.** `measure.mjs` stopped after 35 transactions: AVNU's
  `paymaster_buildTransaction` simulated the second `leave` as "not the owner", on a state that did
  not yet include the `enter` accepted in the block before. Nothing was sent for it.
  - `measure-d.mjs` finishes case D from what the outputs record.
  - Its first attempt stopped on a script error before any network send.
  - Its second attempt sent the pending `leave`. The next `enter` was then refused client-side by
    starknet.js ("gas token price is too high": the paymaster's second quote was above the first)
    before signing.
  - Its third attempt allowed 1.5× the first quote and finished. A refused build is retried after
    3 s; one was.
  - The outputs of the incomplete attempts are kept (`measure-d-output.txt.incomplete-*`).
- **Every sending script asks the RPC for its chain id first** (`requireSepolia()`, copied from
  SPK-1's `lib.mjs` with its safety unchanged) and stops unless it is `SN_SEPOLIA`. Every request
  to the RPC and to AVNU carries a usual `User-Agent`.
- **The burner's key** was generated into `spikes/SPK-1b/burners.secret.json`: ignored by git,
  mode 0600, never printed. `redactAlso` adds it to the redaction of every output from the moment
  it exists (`test_redaction.mjs`, synthetic values). `check_secrets.py`, adapted from SPK-1's,
  also counts the burner key and fails if the key file is tracked or not ignored.

## 7. Open questions

1. **Sponsored paymaster.** AVNU's sponsored mode, and any SNIP-29 paymaster with a modern relayer
   class, were not measured: the first needs a key. If the MVP ever needs one, its relayer class
   decides whether the transaction is metered by Sierra gas or by steps (§3).
2. **The first residual.** With the same game call, `leave`'s first residual is 260,480 sent
   directly and 798,800 through an outside execution. The cause is taken to be new storage keys
   (the SNIP-9 nonce), as for `enter` in SPK-1; that stays an inference.
3. **The burner's funding.** Each funding transfer costs a transaction, 0.0627 STRK here together
   with the adventurer's assignment. How often a burner is topped up, and by whom, is ADR-0005's
   question, not this spike's.
