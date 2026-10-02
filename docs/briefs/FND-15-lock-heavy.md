# FND-15 — `scripts/lock.sh` takes the machine's heavy lock for every scarb or snforge build

## Agent
Profile: implement · Branch: `hp/grimworld-game/t-0042-fnd-15-lock-sh-heavy-lock-for-every-buil`

## Goal
After this task `scripts/lock.sh scarb --manifest-path <pkg>/Scarb.toml build` (and every scarb or snforge
build, test, check, lint or execute) runs under the machine-wide heavy lock, with no `--heavy`.

## Context
- On the VPS the machine's `scarb` shim locks only when the subcommand is its first argument: after
  `--manifest-path` the build ran outside the heavy lock (OOM risk; the Overseer's VPS build rule, 2026-10-02).
  The documented form of this repository took only the project lock and the shim let it through.
- `scripts/lock.sh` is shared with track CV: a caller's behaviour may only gain the heavy lock where a build runs.
- Rule nexus #60: this brief names the workflow file it changes (below).

## Scope
- In:
  1. `scripts/lock.sh`: for `scarb` build, test, check, lint, execute and `snforge test`, wherever the
     subcommand sits (after `--manifest-path <path>` too), take the heavy lock as `--heavy` does, in the same
     order (project lock, then heavy lock), once. `--heavy` stays accepted, `--wait` applies as before.
     `scarb fmt`, `scarb metadata` and pnpm take no heavy lock. The set of wrapped subcommands and the
     refusals are unchanged.
  2. Docs, one line each: `docs/briefs/COMMON.md`, `contracts/README.md`, the docstrings of
     `contracts/tools/{accounts_probe,class_sizes,lifecycle_probe,reuse_probe}.py` say the lock covers it.
  3. Spikes not routed through the lock, one line each, no re-measure: `spikes/SPK-14/gen_tables.py`,
     `spikes/SPK-15/README.md`. `spikes/SPK-14/README.md:30-31` (`scarb --manifest-path … clean`) is left:
     `lock.sh` does not wrap `clean` (see the report).
  4. **Workflow file changed: `.github/workflows/tooling.yml`, test cases only**: next to the lock.sh cases,
     a held heavy lock with `--wait 1` ends `scripts/lock.sh scarb --manifest-path X build` in 75 with the busy
     line and the command does not run, while `scarb fmt --check` runs; in the `with-node` step, the asdf
     fallback (a stub `asdf`, a PATH without devnet, the node starts; a wrong directory gives 127).
- Out: `scripts/profiles/*`; any other workflow change; re-measuring anything.
- Allowlist: this brief, `scripts/lock.sh`, `.github/workflows/tooling.yml`, the doc lines above.

## Acceptance criteria
- [ ] AC-1 A held heavy lock stops `scripts/lock.sh --wait 1 scarb --manifest-path X build` (75, busy line, no run).
- [ ] AC-2 `scarb fmt --check` under the same held lock runs.
- [ ] AC-3 `--heavy` still accepted; the lock order and the refusals unchanged (existing cases stay green).
- [ ] AC-4 The with-node asdf-fallback case passes.
- [ ] AC-5 Docs and spike lines say or use the lock; `shellcheck` clean on `scripts/lock.sh`.

## Verification
`scripts/prepush.sh`; CI's `tooling` job on Linux.

## Audit
None needed.
