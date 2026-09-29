# FND-09 — `scripts/with-node.sh` on macOS, and a full-archive node

> D-153 (owner), item 2: track CV runs the game's tooling on the owner's Mac, and the indexer
> (IDX-01) needs a node that keeps every block's state.

## Agent
Title: `[Sonnet 5.5] FND-09 with-node on macOS` · Profile: implement · Branch: `feat/fnd-09-with-node-mac`

## Goal
After this task `scripts/with-node.sh` runs on macOS as it does on the Linux VPS, and can start the
local node in **full-archive** mode for the indexer, without changing what it does today on Linux.

## Context
- `scripts/with-node.sh` in full: it starts starknet-devnet (pinned in `.tool-versions`) on a free
  port, runs the command in its own session and process group (`setsid`, line 160, so that stopping
  kills the whole group), and stops the node and the group on exit, on a signal and on a timeout.
- macOS has no `setsid` by default. The process-group semantics must hold another way there (a
  job-control shell `set -m`, a small `perl -e 'setpgrp'` or `python3 -c 'os.setsid()'` wrapper, or
  another portable means: choose, and say why it keeps the group's stop exact).
- starknet-devnet's options for keeping the state of every block (its full-archive or state-archive
  capacity): read `starknet-devnet --help` of the pinned version; do not assume a flag.
- COMMON (the shared machine: stop only what the script started, never by pattern), docs/CAIRO.md is
  not concerned. `.github/workflows/tooling.yml` runs shellcheck and the scripts' fixtures on Linux.

## Scope
- In: a fallback when `setsid` is absent, keeping the group semantics (the command and its children
  stopped together, nothing else); a `--full-archive` option that passes the pinned devnet's
  state-archive flag; the usage text and the script's header; tests in `tooling.yml`'s fixtures for
  the fallback path (forced on Linux by hiding `setsid` from `PATH`) and for `--full-archive` (the
  flag reaches the node's command line; a state read at an older block answers).
- Out: installing tools on macOS (track CV's), the launcher (`scripts/agent.sh` is frozen), the
  indexer.
- Allowlist: `scripts/with-node.sh`, `.github/workflows/tooling.yml` (its with-node fixtures only).

## Acceptance criteria
- [ ] AC-1 With `setsid` hidden, the script runs a command in its own group and stops the whole
      group on exit, on a signal and on a timeout (fixture).
- [ ] AC-2 `--full-archive` starts the node with the pinned devnet's state-archive option; a read at
      an older block answers (fixture).
- [ ] AC-3 On Linux with `setsid`, the behaviour is unchanged (the existing fixtures pass); shellcheck
      clean; CI green.

## Audits
Quality: **`[GPT-6-Sol]`**.

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the fallback chosen and why it keeps the group exact,
the devnet flag and where it was read, the fixtures.
