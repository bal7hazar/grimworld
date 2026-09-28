# SPK-5 — Toolchain pins

## Agent
Title: `[Sonnet 5] SPK-5 toolchain pins` · Profile: implement · Branch:
`chore/spk-5-toolchain`

## Goal
After this task, the repository pins versions of Cairo and Scarb, starknet-foundry, Dojo
(`sozo`), Katana, Torii, Node.js, pnpm and dojo.js **that work together**, installs them on a
clean machine without root with one script, and proves it: a throwaway Dojo world builds,
tests, migrates to a local Katana, is indexed by Torii and is read back by a dojo.js script.
This is the "reproducible build from a clean machine" row of ADR-0001's validation table.

## Context
- ADR-0001 (validation table, SPK-5 row); ADR-0003 (client: TypeScript, dojo.js; the
  consequence "hosted indexer: Slot reported retired in April 2026, self-hosting Torii": to
  confirm here); CONTEXT §4 (stack).
- PLAN Phase 0: SPK-5 feeds FND-01 (scaffold), SPK-2, SPK-4, SPK-7, SPK-8. **Cartridge
  Controller is not pinned here** (SPK-9, version 1).
- Depends on: FND-03 (merged).
- What is on the machine today (2026-09-28): asdf with `scarb 2.19.4` and
  `starknet-foundry 0.61.0` set **globally** (`~/.tool-versions`, used by the owner's other
  programmes); Node 24.21 and pnpm 12.5 from the system; **no `sozo`, `katana`, `torii`**.
  asdf plugins exist for `dojo`, `nodejs`, `pnpm`, `scarb`, `starknet-foundry`
  (`asdf plugin list all`). Measured by the orchestrator: an empty project on
  `dojo = "1.8.0"` from scarbs.xyz, with `allow-prebuilt-plugins = ["dojo_cairo_macros"]`,
  builds with `scarb build` 2.19.4 (1.4 GB peak, 11 s).

## Scope
- In:
  - Find the newest set of versions that work together, from the projects' release notes
    and compatibility statements (Dojo's documentation and GitHub releases of `dojo`,
    `katana`, `torii`, `dojo.js`), and **prove it by running it**. Prefer the versions
    already on the machine when they are compatible; say why when they are not.
  - Install through asdf (and `asdf install` from a local `.tool-versions` only), or, for a
    tool asdf cannot provide, the project's official release binary under the user's home.
    **No root. Never change the global versions** (`~/.tool-versions`): other programmes
    depend on them.
  - `.tool-versions` at the repository root with every pinned tool asdf manages.
  - `scripts/setup-toolchain.sh`: idempotent, no root, installs exactly the pinned versions
    on a clean machine (asdf plugins and versions; the rest as documented), then prints each
    tool's version. Must pass `shellcheck`.
  - `scripts/with-katana.sh <command> [args…]`: starts a local Katana in dev mode inside the
    script, waits until it answers, runs the command in the foreground, stops Katana, exits
    with the command's status; optionally Torii too (`--torii`), same lifecycle. Logs of the
    nodes go to a file under the current directory. Must pass `shellcheck`. This is how
    every agent runs something that needs a node without a background command.
  - A throwaway world in `spikes/SPK-5/`: one model, one system, one test; build, test,
    migrate to Katana, index with Torii, and a dojo.js script (TypeScript or JavaScript,
    run with Node) that reads the model back from Torii. Its own `package.json` and
    lockfile inside `spikes/SPK-5/`; build outputs ignored by `spikes/SPK-5/.gitignore`.
  - `docs/research/SPK-5-toolchain.md`: the pinned versions and their sources; the
    compatibility constraints found (which version requires which); every command run with
    its real output; what failed and why; the answer on the hosted indexer (Slot's status,
    self-hosted Torii); memory and time of `scarb build`, `sozo build` and the test run of
    the throwaway world; open questions for FND-01.
- Out: the real repository scaffold (`contracts/`, `client/`, workspace manifests: FND-01);
  the CI (FND-02); gas tooling (FND-06); Cartridge Controller (SPK-9); any deployment
  outside a local Katana; upgrading the machine's global tools.
- Allowlist: `.tool-versions`, `scripts/setup-toolchain.sh`, `scripts/with-katana.sh`,
  `spikes/SPK-5/**`, `docs/research/SPK-5-toolchain.md`. Anything else is an escalation.

## Interfaces
- `scripts/setup-toolchain.sh` — no argument; exit 0 when every pinned tool is installed and
  answers `--version` with the pinned version.
- `scripts/with-katana.sh [--torii] <command> [args…]` — exit status of `<command>`; Katana
  (and Torii) always stopped on exit, including on failure (`trap`).

## Acceptance criteria
- [ ] AC-1 `.tool-versions` pins every asdf-managed tool; the research file lists every pin,
      including dojo.js and the `dojo` Cairo package, with its source.
- [ ] AC-2 `scripts/setup-toolchain.sh` run twice in a row succeeds and changes nothing the
      second time; the global `~/.tool-versions` is unchanged (`git diff --no-index` or
      `cat` before and after, shown in the report).
- [ ] AC-3 In `spikes/SPK-5/`: `sozo build` (or `scarb build`, whichever the pinned Dojo
      uses) and the world's test pass through `scripts/lock.sh`.
- [ ] AC-4 `scripts/with-katana.sh --torii <migrate then read>` migrates the world to a local
      Katana and the dojo.js script prints the model written by the system; Katana and
      Torii are stopped afterwards (`pgrep` shows nothing left).
- [ ] AC-5 Both scripts pass `shellcheck` in the CI.
- [ ] AC-6 The research file answers the hosted-indexer question with sources.

## Verification
From the worktree root (the allowlist matches `scripts/…`, not `../../scripts/…`):
```
scripts/setup-toolchain.sh && scripts/setup-toolchain.sh
cat ~/.tool-versions
scripts/lock.sh sozo build --manifest-path spikes/SPK-5/Scarb.toml    # or the scarb equivalent
scripts/lock.sh sozo test --manifest-path spikes/SPK-5/Scarb.toml     # or snforge
scripts/with-katana.sh --torii <the command that migrates and reads back>
pgrep -a katana; pgrep -a torii    # nothing
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7. The cost table holds the build and test
figures of the throwaway world (time, peak memory), not gas.
