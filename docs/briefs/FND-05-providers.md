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
- Depends on: SPK-5b and FND-01b (merged): `contracts/` with the `persistent` and `ephemeral`
  contracts on Cairo 2.19, snforge tests that deploy them; `client/` on starknet.js;
  `scripts/with-node.sh` (the local node of NS-1); `spikes/SPK-5b/` as the reference.

## Scope
- In, contracts:
  - An interface `IRandomness` with `fate(domain: felt252) -> felt252`, and a helper that
    derives further values `derive(word, domain, index)` by Poseidon (ADR-0002 rule 2).
  - The **transaction-hash provider**: a contract implementing `IRandomness`, deployed
    separately, whose address the game reads from configuration in the **persistent
    contract's storage**, set by the administrator role (ADR-0007 *Access control*: say who may
    set it and test that nobody else can), never hard-coded (pillar 6, ADR-0001).
  - The **mainnet refusal**: the provider cannot be deployed or initialised when the chain id
    is Starknet mainnet's, and `fate` reverts on mainnet even if the provider was deployed
    another way. Say where the check lives and why that place cannot be skipped.
  - Tests (snforge, deploying the contracts) with gas budgets:
    determinism for the same transaction and domain; distinct values for distinct domains and
    indices; the refusal on the mainnet chain id (use the test framework's chain-id cheat);
    that no other contract can reach the transaction hash through the provider for a purpose
    it was not called for (document what the interface allows and forbids).
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
- Allowlist: `contracts/src/` (a new module for providers, the configuration storage and its
  administrator check, plus the one-line `mod` declarations they need), `contracts/tests/`,
  `contracts/Scarb.toml` only if a dependency must be declared,
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
- [ ] AC-3 The provider's address is read from configuration that only the administrator role can set (tested); nothing in `contracts/src`
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
scripts/lock.sh scarb build --manifest-path contracts/Scarb.toml
cd contracts && snforge test && cd -
pnpm -r test && pnpm -r lint && pnpm -r typecheck
scripts/with-node.sh <the command that runs the account integration test>
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7, with the gas table of every test.
