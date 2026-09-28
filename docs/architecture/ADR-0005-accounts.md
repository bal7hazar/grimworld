# ADR-0005 — Accounts, fees and sessions

| | |
|---|---|
| Status | **Proposed** |
| Date | 2026-09-28 |
| Decides | How a player gets an account, who signs, who pays, without the player seeing any of it |
| Supersedes | The assumption, in ADR-0001 and ADR-0003, that Cartridge Controller is the account layer |

## Context

- Pillar 7: the chain is invisible. No fee, no wallet, no signature prompt.
- The owner doubts that Cartridge Controller is maintained well enough, and does not know
  whether it works properly on Sepolia (D-102). It must be treated as one candidate, not
  as a given.
- What our research read on 2026-09-28, to be weighed against the owner's experience: the
  Controller repository showed a release on 2026-09-08 (v0.14.2); its native bindings had
  no release and were about seven months behind; documentation for native flows gave no
  statement of production readiness. **None of it was tested by us.**

## What depends on the account layer

| Need | With Controller | Without |
|---|---|---|
| Account creation without seed phrase | Passkey | Ours to provide |
| No prompt per action | Session policies | The game holds the signing key: no prompt by construction |
| **Fees paid by the game** | Cartridge paymaster | Another paymaster, or an account funded by the game |
| **Fate randomness** | Cartridge vRNG, **which works through Cartridge's paymaster** wrapping the transaction | **To be re-examined**: a vRNG request outside that path is not documented |
| Quests and titles shown in a profile | Controller profile | Our own screens |
| Recovery on a new device | Passkey sync | Ours to provide |

The third and fourth rows are the important ones: **dropping Controller also touches fees
and randomness**, which are Cartridge services today (ADR-0002).

## Decision (proposed)

### 1. An interface, not a vendor

The client talks to an **account provider** with four operations: create or restore an
account, execute a list of calls, report the status of an execution, sign out. The game
never imports a vendor's library outside that module.

### 2. Stages

| Stage | Account | Fees | Randomness | For |
|---|---|---|---|---|
| **A — Burner** | A key generated on the device, an account deployed by the game | Local network: none. Sepolia: accounts funded by the game, or a paymaster | Local: a mock. Sepolia: see spike | Development and first playtests |
| **B — Evaluate Controller** | Controller behind the interface | Its paymaster | Its vRNG | Spike SPK-9 decides |
| **C — Production** | Controller if it passes; otherwise **our own**: passkey-owned account, session key on the device, our paymaster | The game | The source kept by SPK-3 and SPK-9 | Public test and mainnet |

### 3. What a burner is, and is not

| | |
|---|---|
| Is | The fastest way to play: no screen, no login |
| Is not | A production account. The key lives in the device's storage: clearing it, or losing the phone, loses the account and everything it owns |
| Therefore | Burners are for stages where nothing of value exists. No real player is ever onboarded on one without a way to attach a recoverable owner later |

### 4. Requirements for stage C, whatever the solution

| # | Requirement |
|---|---|
| A-1 | Account creation in under 30 seconds, with nothing to write down |
| A-2 | No prompt during play |
| A-3 | The player never holds the fee token |
| A-4 | Recovery on a new device without a seed phrase |
| A-5 | The signing key on the device can only call the game's entrypoints, and expires |
| A-6 | The screens the player sees carry the game's name and no blockchain vocabulary |
| A-7 | The account can be moved from one provider to another without losing the adventurers: ownership is a field the account can change, not the account's address |

## Validation — spike SPK-9

| Question | Pass |
|---|---|
| Does Controller work on Sepolia today, from the Capacitor shell, on a phone? | Login, session, 50 sponsored transactions in a row without prompt |
| Does vRNG work through it? | 20 Fate draws, verified |
| What does the player see at first login? | Meets A-6, or can be themed to meet it |
| Can a burner use a paymaster and a verifiable random source on Sepolia without Controller? | One working path identified, with its trust model |

## Consequences

| | |
|---|---|
| + | Work can start at once on burners, without waiting for any third party |
| + | The vendor can be replaced |
| − | If Controller is dropped, fees and randomness need another answer: ADR-0002 is reopened |
| − | Quests and titles lose the ready-made profile screens (ADR-0004); ours must be built |
| − | An account system of our own is security-critical code: external audit |
