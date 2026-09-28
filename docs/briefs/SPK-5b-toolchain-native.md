# SPK-5b — Toolchain pins, without Dojo

## Agent
Title: `[Sonnet 5] SPK-5b toolchain without Dojo` · Profile: implement · Branch:
`chore/spk-5b-toolchain-native`

## Goal
After this task the repository pins the toolchain of a **native Starknet game on Cairo
2.19** (ADR-0007, D-123) and proves it on a clean machine: Scarb and snforge, a **local
Starknet node that accepts the classes of Cairo 2.19** (open point NS-1: measured, not
assumed), a deployment tool, and starknet.js for the client. A throwaway contract is built,
tested, declared and deployed on the local node, called, and read back from TypeScript. Dojo's
tools leave the repository's toolchain.

## Context
- **ADR-0007 in full** (no Dojo world, `sozo`, Torii or dojo.js; Cairo 2.19; deployment
  scripts of our own; a local node chosen here; events as an interface; starknet.js), CONTEXT
  §4, D-123.
- SPK-5 (merged): `docs/research/SPK-5-toolchain.md`, `docs/reports/SPK-5-toolchain.md`,
  `scripts/setup-toolchain.sh` (asdf pins, system Node and pnpm used when they match, sha256
  checks, the rules of the incident below), `scripts/with-katana.sh` (a node for the lifetime
  of one foreground command: process group, ports, readiness, cleanup). Reuse their structure;
  what they learned about asdf plugins and binary hashes stands.
- **The machine**: the global asdf versions are already `scarb 2.19.4` and
  `starknet-foundry 0.61.0` (other programmes use them; never change them). Node 24.21 and pnpm
  12.5.1 are the system's. `docs/reports/INC-2026-09-28-asdf-node-shims.md` and COMMON §3:
  **an asdf plugin creates machine-wide shims**; never add one for a tool the system already
  provides at the pinned version, and check from `/tmp` after adding any.
- **The Dojo baseline must stay reproducible**: SPK-2 (running) measures a Dojo 1.8 world on
  Cairo 2.13 in `spikes/SPK-2/`, and `spikes/SPK-5/` is the Dojo spike. Their toolchain moves
  out of the root pins into their own `.tool-versions`.
- Depends on: SPK-5, FND-03 (merged).

## Scope
- In:
  - Root `.tool-versions`: `scarb 2.19.4`, `starknet-foundry 0.61.0` (which brings `sncast`),
    the local node if asdf provides it, `nodejs 24.21.0`, `pnpm 12.5.1`. **No `sozo`, no
    `torii`.**
  - **NS-1, the local node**: try, in this order, and **measure** which accepts a class
    compiled by Scarb 2.19.4 (declare, deploy, invoke, call, events in the receipt): Katana
    1.7.1 (already installed), Katana's newest release candidate, `starknet-devnet` (the Rust
    devnet). Keep the first that passes everything; record each attempt with its exact
    error. If none passes, stop that part and escalate.
  - **Deployment tool**: `sncast` (from starknet-foundry 0.61) with an account on the local
    node; declare, deploy, invoke, call, from a script.
  - `scripts/setup-toolchain.sh`: installs exactly the new pins, same rules as before
    (idempotent, no root, hashes verified before running, no plugin for a tool the system
    provides at the pinned version, never `~/.tool-versions`); `sozo` and `torii` removed.
  - `scripts/with-katana.sh` becomes **`scripts/with-node.sh`** for the node NS-1 keeps (same
    guarantees; `--torii` removed); `scripts/with-katana.sh` removed.
  - `spikes/SPK-5/.tool-versions` and `spikes/SPK-2/.tool-versions` pinning the old Dojo set
    (scarb 2.13.1, starknet-foundry 0.51.2, sozo 1.8.7, katana 1.7.1, torii 1.8.16), and one
    line in each spike's README (create it if absent) saying these spikes are the Dojo
    baseline, not installed by `setup-toolchain.sh`. **If `spikes/SPK-2/` does not exist on
    `origin/main` when you start (SPK-2 not merged yet), skip it and say so.**
  - `scripts/lock.sh`: `sozo` leaves its list of wrapped tools; `sncast` does not need the
    lock. `scripts/profiles/audit.txt` and `implement.txt`: the `sozo` and `torii` rules
    removed; rules for `sncast` and the node NS-1 keeps added; nothing else changed.
  - A throwaway native contract in `spikes/SPK-5b/`: one storage value, one entrypoint writing
    it, one event, one view; an snforge test with a gas budget; `scripts/with-node.sh` running a
    script that declares, deploys, invokes, calls and reads the event from the receipt; a
    TypeScript script with starknet.js (exact version pinned) that calls the view and decodes
    the event.
  - `docs/research/SPK-5b-toolchain-native.md`: the pins and their sources, NS-1 with every
    attempt, the deployment flow, starknet.js version and how bindings could be typed from the
    contract's ABI (for CLI-01), time and peak memory of build and test, and the open questions
    for FND-01b and SPK-11.
- Out: the game's scaffold (FND-01b); CI (FND-02); the indexer (SPK-11); Sepolia; removing
  `spikes/SPK-5/` or changing its code; changing the machine's global versions.
- Allowlist: `.tool-versions`, `scripts/setup-toolchain.sh`, `scripts/with-node.sh`,
  `scripts/with-katana.sh` (removal), `scripts/lock.sh` (the `sozo` case only),
  `scripts/profiles/audit.txt` and `implement.txt` (the rules named above only),
  `spikes/SPK-5/.tool-versions`, `spikes/SPK-5/README.md`, `spikes/SPK-2/.tool-versions`,
  `spikes/SPK-2/README.md`, `spikes/SPK-5b/**`, `docs/research/SPK-5b-toolchain-native.md`.
  Anything else is an escalation.

## Acceptance criteria
- [ ] AC-1 The root `.tool-versions` holds the native set and nothing of Dojo; the research
      file lists every pin with its source.
- [ ] AC-2 `scripts/setup-toolchain.sh` run twice succeeds, the second run installs nothing,
      `~/.tool-versions` is unchanged, and `node --version` still works from `/tmp`.
- [ ] AC-3 NS-1 answered: the node kept accepts a Cairo 2.19 class (declare, deploy, invoke,
      call, event), every other attempt recorded with its error.
- [ ] AC-4 `spikes/SPK-5b/`: build and test (with a gas budget) through `scripts/lock.sh`;
      `scripts/with-node.sh` runs the declare-deploy-invoke-call script and the starknet.js
      script reads the view and the event; no node left running (`pgrep`).
- [ ] AC-5 The Dojo spikes keep their own pins; `scripts/with-katana.sh`, `sozo` and `torii`
      are gone from the root toolchain, the lock and the profiles; `shellcheck` passes (CI).

## Verification
From the worktree root:
```
scripts/setup-toolchain.sh && scripts/setup-toolchain.sh
cd /tmp && node --version && cd -
scripts/lock.sh scarb build --manifest-path spikes/SPK-5b/Scarb.toml
cd spikes/SPK-5b && snforge test && cd -
scripts/with-node.sh <the script that declares, deploys, invokes, calls, then runs the starknet.js reader>
pgrep -a katana; pgrep -a starknet-devnet    # nothing
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7; the cost table has the throwaway contract's test
gas, and the build and test times and peak memory.
