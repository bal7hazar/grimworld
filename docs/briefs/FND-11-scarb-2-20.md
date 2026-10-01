# FND-11 — The game on Scarb 2.20.1 and starknet-foundry 0.64.0

> D-180 (owner): every repository migrates to the latest Scarb (2.20.1 today; starknet-foundry 0.64.0).
> **Launched after the lots in flight merge** (ENG-R1a, CBT-04, CBT-03a, ENG-02), so their budgets are not
> measured twice, and after SPK-13's result on 2.20.1 (D-176's drift). **FND-10 is folded in**: the build pin
> it would add changes the same measurements, so they are taken once, here.

## Agent
Title: `[Sonnet 5.5] FND-11 Scarb 2.20.1` · Profile: implement · Branch: `feat/fnd-11-scarb-2-20`

## Goal
After this task the game builds, tests, measures and declares on **Scarb 2.20.1 and starknet-foundry
0.64.0**, locally (`scripts/setup-toolchain.sh`, the repository's `.tool-versions`) and in CI, with every gas
budget and class-size snapshot **re-measured and written down** (a new compiler moves them, and that is
expected, not hidden), the local node (`starknet-devnet`) proven to accept the new compiler's classes, and
D-176's single-threaded build pin **applied or dropped as SPK-13's result says**.

## Context
- **D-180** and **D-176** (`docs/decisions/`; SPK-13: the compiler's `withdraw_gas` placement follows rayon's
  thread order; `RAYON_NUM_THREADS=1` gives one build). **SPK-13's result on 2.20.1** decides the pin: if the
  drift persists on 2.20.1, FND-10's scope is yours (below); if not, write so and drop it. Ask the orchestrator
  for the result if it is not in `docs/decisions/` or PLAN when you start.
- **The toolchain today**: `.tool-versions` (scarb 2.19.4, starknet-foundry 0.61.0, starknet-devnet 0.10.0),
  `scripts/setup-toolchain.sh` (installs the repository's pins into asdf's data directory; never global: no
  `asdf set -u`, never `~/.tool-versions`, which is only read; the incident file it cites), `.github/workflows/ci.yml`
  (the matrix's `scarb` and `snforge`, the version checks), `.github/ci/install-snforge.sh` (a pinned SHA-256
  per version), `scripts/with-node.sh` (the local node), `contracts/Scarb.toml` and the packages'
  (`cairo-version`, `starknet`, `snforge_std`, `assert_macros`), `Scarb.lock`, the spikes that follow the root
  pins (the Dojo spikes keep their own `.tool-versions`: untouched).
- **`hexx` 0.1.0-rc.1** declares `cairo-version 2.19.4`: check that it resolves and builds under 2.20.1
  (a caret requirement should); if it does not, stop and escalate (the library's release is the library's).
- **Budgets**: `scripts/gas_budgets.py` (ceil(1.05 × measured); `--check`, `--report`), `docs/BUDGETS.md`,
  each package's `GAS.md`, `contracts/tools/class_sizes.py` (ENG-01 §1.3's 50 % rule), D-154, D-164 (the gas
  gate), D-144 (a measured replacement: here the cause is the compiler, stated once for all rows).
- **Not yours**: `indexer/emitter/` (IDX-01, lent to track CV, D-149: tell the orchestrator what it would need);
  the frozen launcher (`scripts/agent.sh` and its profiles); the machine's shared configuration.
- COMMON.md; CAIRO.md §2 (D-176's rule); OPERATIONS §7 (no sending from an agent).

## Scope
- In:
  - **The pins**: `.tool-versions`, the packages' `Scarb.toml` (`cairo-version`, the `starknet`, `snforge_std`,
    `assert_macros` versions), `Scarb.lock` regenerated, CI's matrix and checks, `install-snforge.sh`'s SHA-256
    for 0.64.0 (from the release's published checksum, its source named), `setup-toolchain.sh` run to install
    them (what it installs, said in the report).
  - **Every gas budget and class size re-measured**: `gas_budgets.py` regenerates `GAS.md` and `BUDGETS.md`;
    each moved row keeps ceil(1.05 × measured); one line in the report states the cause for all (the compiler),
    with the distribution of the moves (the largest rises and falls, by package); a rise of a budget the cost
    budget relies on (ENG-01 §9.2's rows, D-158's `enter` and `set_build`, the tick's bound) listed apart.
    `class_sizes.py` re-run; ENG-01 §1.3's table updated.
  - **The local node**: `scripts/with-node.sh` with the lifecycle probe (`contracts/tools/lifecycle_probe.py
    --expect contracts/tools/lifecycle-stream-before.json`): the classes declare and the stream holds. If
    starknet-devnet 0.10.0 refuses the new classes, find the version that accepts them and pin it.
  - **The build pin (FND-10's scope, if SPK-13 keeps it)**: `RAYON_NUM_THREADS=1` on CI's cairo jobs,
    `gas_budgets.py`'s runs and the scripts that declare; a CI check that 3 clean builds give one class hash; the
    slowdown measured.
  - **The documents that name 2.19**: ADR-0007's version line, CAIRO.md's, COMMON.md's, setup notes.
- Out: any change to a rule, an interface or a test's assertions; the indexer (track CV); the launcher.
- Allowlist: `.tool-versions`, `scripts/setup-toolchain.sh`, `scripts/gas_budgets.py` (the pin only),
  `.github/workflows/ci.yml`, `.github/ci/`, every `Scarb.toml` and `Scarb.lock` but `indexer/emitter/`'s, the
  generated `GAS.md` and `docs/BUDGETS.md`, `contracts/tools/` (the probe's pins), `docs/architecture/` and
  `docs/CAIRO.md`, `docs/briefs/COMMON.md` for the version lines, the spikes' budgets as generated. Anything
  else is an escalation.

## Acceptance criteria
- [ ] AC-1 Scarb 2.20.1 and starknet-foundry 0.64.0 pinned everywhere the game builds, locally and in CI;
      `setup-toolchain.sh` installs them on a clean machine; CI green.
- [ ] AC-2 Every budget and class size re-measured and written down; the cause stated once; the cost
      budget's rows listed apart with their moves.
- [ ] AC-3 The local node accepts the classes; the lifecycle probe's stream equal.
- [ ] AC-4 The build pin applied (and the 3-build check) or dropped, on SPK-13's result, said in the report.
- [ ] AC-5 Nothing global touched; `indexer/emitter/` untouched, its needs named.

## Audits
None as a gate (D-177): the review and the checks. The PR says so in one line.

## Verification
```
scripts/setup-toolchain.sh
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py --expect contracts/tools/lifecycle-stream-before.json
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the pins, what was installed, the budgets' moves (by package, the
cost budget's rows apart), the class sizes, the node, the build pin's outcome, the indexer's needs.
