# FND-01b — Scaffold as native contracts

## Agent
Title: `[Sonnet 5] FND-01b native scaffold` · Profile: implement · Branch:
`chore/fnd-01b-scaffold-native`

## Goal
After this task the scaffold of FND-01 is native Starknet (ADR-0007): no Dojo dependency, two
contracts — **persistent** and **ephemeral** — laid out with the layering of ADR-0007, tested by
snforge tests that deploy them, on Cairo 2.19; `origami_hexmap` 1.8.0 builds in the game; the
client talks to the chain through starknet.js. Still no rule of the game.

## Context
- **ADR-0007 in full**, especially *The layering is kept* (systems are contracts; components
  are Starknet components; `store` is the single access point to storage; `models/` are
  storage structs with their packing and invariants; pure logic as a library without storage;
  class size), *Access control*, *Events are an interface*; CONTEXT §4; D-123.
- ADR-0001 *Keeping the exit open* (two domains; the ephemeral contract writes to the
  persistent one through one narrow interface); docs/CAIRO.md in full (a gas budget on every
  test); COMMON.
- What exists (FND-01, merged): `contracts/` as a Dojo package on Cairo 2.13 (namespaces,
  `dojo_dev.toml`, a `dojo_snf_test` world-spawn test), `client/` (`@grimworld/sim` without
  chain or rendering dependencies, `@grimworld/app` with PixiJS on demand and dojo.js packages
  declared), `contracts/README.md`, `client/README.md`.
- Depends on: **SPK-5b** (merged): Cairo 2.19 (Scarb 2.19.4, snforge 0.61), the local node and
  `scripts/with-node.sh`, `sncast`, starknet.js at its pinned version; `spikes/SPK-5b/` is the
  working reference for a native contract, its tests and the deployment flow.

## Scope
- In, `contracts/`:
  - A Scarb workspace (or one package; say why) on Cairo 2.19, **no Dojo** (`dojo`,
    `dojo_snf_test`, `dojo_dev.toml`, namespaces removed), with `origami_hexmap = "1.8.0"`.
  - **Two contracts**: `persistent` and `ephemeral` (names may be refined; say why), each with
    the layering of ADR-0007 as modules (`systems/`, `components/`, `store`, `models/`,
    `types/`, `elements/`, `helpers/`, `registries/`), each module with a one-line doc comment
    and **no game code**. A **pure logic library** (for example a `logic` package or module
    without storage) where the rules of a tick will live.
  - Each contract has one placeholder view (for example `version() -> felt252`) so that it can
    be deployed and called. No access control yet, no results interface, no storage beyond what
    the placeholder needs: those are ENG-01's, frozen with the security lens.
  - snforge tests that **declare and deploy both contracts** and call the placeholder views,
    with gas budgets (docs/CAIRO.md §2); one test calling a function of `origami_hexmap` 1.8.0
    (for example a distance), proving it builds on the game's compiler.
  - `contracts/README.md`: the layout, the two-contract rule with a link to ADR-0007 and
    ADR-0001, build and test commands through `scripts/lock.sh`.
- In, `client/`:
  - `@grimworld/app`: dojo.js packages removed; starknet.js at SPK-5b's version; nothing uses it
    yet beyond a type import or a trivial provider construction in a test (no network in
    tests). `@grimworld/sim` unchanged (still no chain or rendering dependency).
  - `client/README.md` updated.
- Out: access control, the results interface, events, storage layouts (ENG-01); providers
  (FND-05); the indexer (SPK-11); CI (FND-02); gas tooling (FND-06); deployment scripts beyond
  a test (OPS-01).
- Allowlist: `contracts/**`, `client/**`, root `package.json`, `pnpm-lock.yaml`,
  `pnpm-workspace.yaml`, `.gitignore` (build outputs only). Anything else is an escalation.

## Acceptance criteria
- [ ] AC-1 No Dojo anywhere in `contracts/` or `client/` (`grep -ri dojo contracts client`
      finds only the READMEs' sentence saying why there is none).
- [ ] AC-2 `scripts/lock.sh scarb build` and the snforge tests pass; the tests deploy both
      contracts; every test has a gas budget.
- [ ] AC-3 The `origami_hexmap` 1.8.0 test passes on Cairo 2.19.
- [ ] AC-4 The two contracts and the pure logic library exist with the layering; no storage
      struct mixes the two domains (there are none yet: say so).
- [ ] AC-5 `pnpm install --frozen-lockfile`, `pnpm -r test`, `lint`, `typecheck` and the
      client build pass; `@grimworld/sim` has no chain or rendering dependency.

## Verification
From the worktree root:
```
scripts/setup-toolchain.sh
scripts/lock.sh scarb build --manifest-path contracts/Scarb.toml
cd contracts && snforge test && cd -
scripts/lock.sh pnpm install --frozen-lockfile
pnpm -r test && pnpm -r lint && pnpm -r typecheck && scripts/lock.sh pnpm build
grep -ril dojo contracts client
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7, with the gas of every test.
