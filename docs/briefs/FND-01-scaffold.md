# FND-01 — Repository scaffold

## Agent
Title: `[Sonnet 5] FND-01 repository scaffold` · Profile: implement · Branch:
`chore/fnd-01-scaffold`

## Goal
After this task the repository has the empty but real structure every later task writes
into: a Dojo contracts package laid out as CONTEXT §4 says, with the two domains apart, and a
TypeScript client workspace with the simulation core separate from rendering and chain
access. Both build and test green through the build lock, on the toolchain SPK-5 pinned. No
game rule is implemented.

## Context
- CONTEXT §4 (stack, contract architecture pattern, the two domains), ADR-0001 *Keeping the
  exit open* (persistent and ephemeral domains: separate namespaces, separate systems),
  ADR-0003 *Decision* (simulation core: a standalone package, no dependency on rendering or
  chain access; PixiJS on demand; DOM interface; Capacitor later), ADR-0006 (chunks),
  docs/CAIRO.md (every test has a gas budget).
- Depends on: SPK-5 (merged): `.tool-versions` (Scarb 2.13.1, snforge 0.51.2, Node 24.21.0,
  pnpm 12.5.1), sozo 1.8.7, Katana 1.7.1, Torii 1.8.16, `dojo` 1.8.0, `dojo_snf_test` 1.8.0,
  dojo.js 2.0.0. **The whole game stays on Cairo 2.13** (docs/research/SPK-5-toolchain.md §2).
  `spikes/SPK-5/` is the working reference for manifests and test setup; it stays where it is.
- Run `scripts/setup-toolchain.sh` first if a pinned tool is missing.

## Scope
- In:
  - `contracts/`: one Dojo package `grimworld` (Scarb 2.13.1, `dojo` 1.8.0, `edition`
    and manifests as in `spikes/SPK-5/`), with `dojo_dev.toml`, and `src/` laid out as
    CONTEXT §4: `systems/`, `components/`, `store.cairo`, `models/`, `types/`, `elements/`,
    `helpers/`, `registries/` — each a module with a one-line doc comment saying what goes
    there, and no game code.
  - **The two domains**, visible from the first commit: two Dojo namespaces, `grimworld`
    (persistent) and `grimworld_instance` (ephemeral), and `models/persistent/` and
    `models/ephemeral/` (same split for `systems/`). A short `contracts/README.md` states
    the rule (no model mixes fields of both; the ephemeral domain reads a snapshot and writes
    to the persistent one only through the results interface) with a link to ADR-0001.
  - **`origami_hexmap` 1.8.0** as a dependency of `contracts/`, used by one placeholder test
    that calls one of its functions (for example a distance between two tiles), to prove it
    builds on Cairo 2.13. **If it does not resolve or build, stop that part and escalate**
    with the error: it is a finding for track LIB (R-18), not something to work around.
  - One placeholder test per package with a gas budget in the form of docs/CAIRO.md §2
    (`#[available_gas(l2_gas: N)]` with `N = ceil(1.05 × measured)`), proving the harness
    (`dojo_snf_test` world spawn) works. FND-06 generalises budgets; do not build that tooling.
  - `client/`: a pnpm workspace (root `package.json` and `pnpm-workspace.yaml` at the
    repository root, `packageManager` pinned to the SPK-5 pnpm), with two packages:
    `client/sim` (TypeScript, **no dependency** on PixiJS, React, dojo.js or starknet.js;
    one placeholder function and one test) and `client/app` (TypeScript, Vite, React, PixiJS 8,
    dojo.js 2.0.0 declared; a page that renders one static PixiJS frame **on demand**, no
    render loop (ADR-0003 power rules), and one test). Test runner: Vitest. Lint: ESLint
    with the TypeScript plugin; format: Prettier. Versions exact, lockfile committed.
  - Root `README.md`-level instructions are **not** yours: write `contracts/README.md` and
    `client/README.md` only (how to build and test, from the root, through `scripts/lock.sh`).
  - Root `.gitignore`: add the build outputs you create (`contracts/target/`,
    `node_modules/`, `client/*/dist/`, `.with-katana/`).
- Out: CI (FND-02); gas tooling and `docs/BUDGETS.md` (FND-06); provider interfaces
  (FND-05); Capacitor (CLI-01); any model, system or rule of the game (ENG-01 and after);
  deployment; moving or deleting `spikes/SPK-5/`.
- Allowlist: `contracts/**`, `client/**`, root `package.json`, `pnpm-workspace.yaml`,
  `pnpm-lock.yaml`, `.npmrc` if needed, `.gitignore` (the lines above only). Anything else
  is an escalation.

## Interfaces
None of the game yet. Namespaces `grimworld` and `grimworld_instance`; package names
`grimworld` (Cairo), `@grimworld/sim`, `@grimworld/app` (TypeScript).

## Acceptance criteria
- [ ] AC-1 `scripts/lock.sh sozo build --manifest-path contracts/Scarb.toml` and
      `scripts/lock.sh sozo test --manifest-path contracts/Scarb.toml` (or the `scarb`/`snforge`
      forms if they are the ones that work) pass; the placeholder tests have gas budgets.
- [ ] AC-2 The `origami_hexmap` 1.8.0 placeholder test passes, or the escalation says
      exactly why it cannot.
- [ ] AC-3 `scripts/lock.sh pnpm install --frozen-lockfile`, then `pnpm -r test`,
      `pnpm -r lint` and `pnpm -r typecheck` (through `scripts/lock.sh pnpm …` where the lock
      wraps them) pass from the root.
- [ ] AC-4 `client/sim` has no dependency on rendering or chain packages
      (`pnpm --filter @grimworld/sim why pixi.js` finds nothing), and `client/app` has no
      render loop (no `ticker` started, render called on demand).
- [ ] AC-5 The layering folders and the two namespaces exist as listed; `git ls-files`
      shows no build output and no image.

## Verification
From the worktree root:
```
scripts/setup-toolchain.sh
scripts/lock.sh sozo build --manifest-path contracts/Scarb.toml
scripts/lock.sh sozo test --manifest-path contracts/Scarb.toml
scripts/lock.sh pnpm install --frozen-lockfile
pnpm -r test && pnpm -r lint && pnpm -r typecheck
git ls-files | grep -E '(^|/)(target|node_modules|dist)/' ; echo "none expected"
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7; the cost table has the placeholder tests' gas
and the build times and peak memory of `sozo build` and the client build.
