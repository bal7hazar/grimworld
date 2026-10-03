Archived at the merge of #314, 86c0322.

## Report

Model: claude-sonnet-5-5

### Summary
`scripts/lock.sh` now takes the machine's heavy lock itself (project lock, then heavy lock, once, as `--heavy` does) for every `scarb` build/test/check/lint/execute and `snforge test`, wherever the subcommand sits (`--manifest-path` included). `--heavy` and `--wait` unchanged; `scarb fmt`, `scarb metadata` and pnpm take no heavy lock; wrapped subcommands and refusals unchanged. Docs and two spikes aligned; `tooling.yml` has the new cases. Head: `e2b85829c4cc46a1c9b3100ce42e9cfef7f27b6f`. CI not yet polled (CI is the Linux proof).

Shared with track CV: callers only gain the heavy lock where a build runs. Tell grimworld-cv at merge.

### Files changed
- `docs/briefs/FND-15-lock-heavy.md` (new)
- `scripts/lock.sh`
- `.github/workflows/tooling.yml` (test cases only; FND-16 #312 also edits it: whoever merges second merges origin/main in)
- `docs/briefs/COMMON.md`, `contracts/README.md`, `contracts/tools/{accounts_probe,class_sizes,lifecycle_probe,reuse_probe}.py` (docs/docstrings)
- `spikes/SPK-14/gen_tables.py`, `spikes/SPK-15/README.md`

### Commands run
`time scripts/prepush.sh` (Mac, no lock), real output:
```
prepush: base a97f4f055c19417e9d0f64496937b17ef3a0e408; 11 changed file(s)
::: scarb fmt --check (contracts): ok in 0.3s
::: gas_budgets.py --self-test: ok in 0.2s   (10 tests OK)
prepush: total 0.5s
prepush: all checks passed
scripts/prepush.sh  1.78s user 0.32s system 221% cpu 0.950 total
```
(No Cairo compile: no Cairo source, manifest, lock or pin changed.) Also: `shellcheck scripts/lock.sh` clean; `actionlint` on tooling.yml reports only shellcheck infos already present on main, none from the new lines; the lock cases of tooling.yml ran locally with a Python flock shim (exit 0); the asdf-fallback case ran on the Mac (real devnet via asdf) and passed.

### Acceptance criteria
- Held heavy lock + `--wait 1` + `scarb --manifest-path x/Scarb.toml build`: 75, busy line, no run — new case in tooling.yml (passed locally with shim).
- `scarb fmt --check` (also after `--manifest-path`) runs under the held heavy lock — same case.
- `--heavy` accepted, order and refusals unchanged — existing cases still pass.
- with-node asdf fallback: stub asdf, PATH without devnet, node starts; wrong directory gives 127 — new case (passed on the Mac).
- Docs lines and spike lines aligned; shellcheck clean.

### Deviations from the task
- `spikes/SPK-14/README.md:30-31` left untouched: those are `scarb --manifest-path … clean`, which `lock.sh` refuses (it wraps no `clean`) and I did not widen it. Those lines then run `test.sh` (snforge shim, locked). Say if you want `clean` wrapped.
- The task's list included prove, cairo-run, cairo-test, doc; `lock.sh` does not accept them today, so I kept refusing them (no dead entries). They would need adding to the accepted set.
- Dropped a "no asdf at all gives 127" case: on a machine with real asdf on PATH (the Mac) it is not hermetic.
- Not run on Linux: the lock cases rely on real `flock`; the CI `tooling` job is the proof.

### Escalations
None blocking. Decisions above (clean, extra subcommands).

## Next
Poll CI on PR 314 once in 5 minutes and fix red
Launch a review of PR 314
Tell grimworld-cv at merge that lock.sh now takes the heavy lock

## Remember
- lock.sh refuses `scarb clean`; `scarb --manifest-path … clean` cannot be routed through it.
- Compound shell commands (`;`, `&&` chains with heredocs) can be refused by the permission layer: one command per call.
