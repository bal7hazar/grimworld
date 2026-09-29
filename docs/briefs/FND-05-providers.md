# FND-05 — Provider interfaces

## Agent
Title: `[Opus 5.5] FND-05 provider interfaces` · Profile: implement · Branch:
`feat/fnd-05-providers`

## Goal
After this task the game has its two provisional providers behind interfaces, so that
version 1 can replace them without touching game code: a **randomness provider**
(`fate(domain)`, implemented on the transaction hash, **refused on mainnet**) in the
contracts, and an **account provider** (four operations, implemented with **burner
accounts**) in the client. Nothing of the game uses them yet; they are ready and tested.

> **Amended after ENG-01 (#81, D-141).** ENG-01 froze `IFate` (`grimworld_logic::interface`, the
> name replaces `IRandomness` below) and implemented `TxHashFate` (`contracts/persistent/src/systems/fate.cairo`)
> with its mainnet refusal at deployment and at every call, tested (`test_fate_*`). `Hub` and
> `Instances` store the provider's address, set by `set_contracts`, which with `set_admin` is
> still a stub. This task builds on that and does not change a frozen signature. ENG-01b runs at
> the same time and edits `play`, `BatchPlayed`, `bundle` and the accounting: do not touch them.

## Context
- **ADR-0002 in full**: *MVP: a provisional source* (game code never reads the transaction
  hash, it calls `fate(domain)` of a provider behind an interface; the implementation is
  configuration; rules 1 to 3, 5 and 6 apply from the MVP; **a deployment check refuses the
  provisional provider on mainnet**), *Rules* (one draw per transaction, values derived as
  `poseidon(word, domain, index)` with a distinct domain constant per use, never one value
  for two decisions).
- **ADR-0005 in full**: §1 (an account provider with four operations: create or restore an
  account, execute a list of calls, report the status of an execution, sign out; no vendor
  library outside that module), §2 stage A (burner: a key generated on the device, an account
  deployed by the game; local network: no fees), §3 (what a burner is not).
- ADR-0001 *Keeping the exit open* (external addresses are configuration; no rule inside an
  instance reads block data or the transaction hash), design/11 *The chain, unseen* (no
  blockchain word reaches the player), CONTEXT §8, docs/CAIRO.md in full, COMMON §4.
- **ADR-0007** (native Starknet contracts on Cairo 2.19, no Dojo; *Access control*: registries
  and configuration written by an administrator role, contract-to-contract calls restricted).
- Depends on: ENG-01 (merged): `contracts/` holds the packages `grimworld_logic`,
  `grimworld_persistent` (`Hub`, `Market`, `Registry`, `TxHashFate`) and `grimworld_ephemeral`
  (`Instances`), and `docs/architecture/ENG-01-interfaces.md` (§1.2 access control, §4 the Fate
  entrypoints and where each draws); `client/` on starknet.js; `scripts/with-node.sh` (the local
  node of NS-1).

## Scope
- In, contracts:
  - The helper `derive(word, domain, index)` by Poseidon (ADR-0002 rule 2) in `grimworld_logic`,
    and **one domain constant per use of Fate** (every draw ENG-01 §4 lists: the entry draw, loot,
    a chest, identify, lift a modifier, brew a new pair, buy a hint, and any other), distinct and
    tested as distinct.
  - **The provider's address as configuration**: implement `set_contracts` and `set_admin` in
    `Hub` and `Instances` (the administrator role, ADR-0007 *Access control*): only the admin may
    call them, `set_admin` hands the role over; tested for the admin and for anyone else. The
    address is never hard-coded (pillar 6, ADR-0001). `upgrade` stays a stub.
  - `TxHashFate` as ENG-01 left it, unless a finding needs a change: say where the mainnet check
    lives and why that place cannot be skipped (the report, from the existing tests).
  - Tests (snforge, deploying the contracts) with gas budgets: determinism for the same
    transaction and domain; distinct values for distinct domains and indices through `derive`;
    what the interface allows and forbids (anyone may call `fate`, and gets only
    `poseidon(tx hash, domain)` for the domain it passes: document why that reaches nothing a
    game contract draws for another purpose).
- In, client (`client/`, TypeScript, a module of its own, for example
  `client/app/src/account/`):
  - An `AccountProvider` interface: `createOrRestore()`, `execute(calls)`, `status(tx)`,
    `signOut()`, with types that carry **no vendor type** outside the module.
  - A **burner** implementation on the local node of NS-1 (`scripts/with-node.sh`): key generated and kept in the device's
    storage (browser `localStorage`, with an injectable storage for tests), account deployed
    by the game (from a prefunded account of the local node in development), `execute` sending a list of
    calls without any prompt.
  - Tests with Vitest: unit tests of the module with a fake chain, and one integration test
    against the real local node through `scripts/with-node.sh` (create, execute one call, status,
    sign out, restore).
- Out: verifiable randomness (SPK-3, version 1); Cartridge Controller (SPK-9); fees and a
  paymaster; any game system using `fate`; any screen; Sepolia or mainnet.
- **D-137** (ADR-0005 stage A, `docs/decisions/2026-09-28-sepolia-verdict.md` § After SPK-1b): the
  burner implementation **sends directly** (the game funds it; no paymaster before version 1); the
  `AccountProvider` interface keeps room for a paymaster without the game knowing (a provider may
  route `execute` through one later; nothing outside the provider depends on who pays).
- Allowlist: `contracts/logic/src/` (a new module for `derive` and the domains, and its `mod`
  line), `set_contracts` and `set_admin` in `contracts/persistent/src/systems/hub.cairo` and
  `contracts/ephemeral/src/systems/instances.cairo`, `contracts/persistent/src/systems/fate.cairo`
  only for a finding, the packages' `tests/`, `GAS.md` and `docs/BUDGETS.md` as generated,
  `client/app/src/account/**`, `client/app/package.json` and the root `pnpm-lock.yaml` only
  for dependencies this module needs. Anything else is an escalation.

## Interfaces
```cairo
#[starknet::interface]
pub trait IRandomness<T> {
    fn fate(ref self: T, domain: felt252) -> felt252;
}
pub fn derive(word: felt252, domain: felt252, index: u32) -> felt252;
```
```ts
export interface AccountProvider {
  createOrRestore(): Promise<AccountHandle>;
  execute(calls: Call[]): Promise<ExecutionId>;
  status(id: ExecutionId): Promise<ExecutionStatus>;
  signOut(): Promise<void>;
}
```
Names and exact types may be refined; say why in the report.

## Acceptance criteria
- [ ] AC-1 `fate` is deterministic per transaction and domain; `derive` gives distinct values
      per domain and index; tests with gas budgets.
- [ ] AC-2 The provider is refused on the mainnet chain id, at deployment or initialisation
      **and** at call time; tests show both.
- [ ] AC-3 The provider's address is read from configuration that only the administrator role can set (tested); nothing in `contracts/`
      outside the provider reads the transaction hash (`grep` shown in the report).
- [ ] AC-4 The account provider's four operations work against the real local node (the
      integration test), and no vendor type is exported outside the module.
- [ ] AC-5 No prompt, no fee and no blockchain word in anything a player could see (there is
      no screen yet: the module's errors and messages are neutral).

## Audits
Security and quality (PLAN: S Q), and **`[GPT-6-Astra]`** because randomness and its providers
are always audited by codex (OPERATIONS §2).

## Verification
From the worktree root:
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check
pnpm -r test && pnpm -r lint && pnpm -r typecheck
scripts/with-node.sh <the command that runs the account integration test>
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7, with the gas table of every test.
