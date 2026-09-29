# [Sonnet 5.5] CV-02 — launcher budget

## Summary
`scripts/mac/agent.sh` now runs up to 5 agents at a time (slots `cv-1`…`cv-5`), refuses a launch while the 5-minute load is above 18 (memory floor 8 GB unchanged), gives agents a `PATH` that starts with `$HOME/.asdf/shims` (no `nodejs/22.22.2` on it), and starts `claude` and `codex` by absolute path from a fixed table. `status` is silent for a task without `.cli`. Tests and README moved to match. The model I ran as matches the brief (Sonnet 5.5).
Pull request: https://github.com/bal7hazar/grimworld/pull/129 (CI: no `.github` workflow concerns this folder; not watched, see Deviations).

## Files changed
- `scripts/mac/agent.sh`: five `SLOT_NAMES`; `MAX_LOAD5=18`; `PATH_FIXED` without the 22.22.2 folder and without the test-mode `$HOME/bin` prefix; new `cli_bin` table (real paths, or `$HOME/bin/<cli>` in test mode); binary checked (`-x`, exit 2) before the account check, dry run unchecked; `# PATH` line in the dry run; `reported_model` tests the `.cli` file before reading it; comments updated.
- `scripts/mac/test.sh`: stub records `$0` (`argv0.<task>`); AC-1 slots-init on a two-slot directory; AC-3 thresholds at 18.01 / 18 / 11.5; AC-4 real-table dry runs, PATH and absolute-path checks, missing / non-executable CLI for claude and codex; AC-5 status without `.cli`; AC-2 five stubs and a sixth refused, race for the last of five; free/held counts moved from 2 to 5.
- `scripts/mac/README.md`: summary cites the owner's decision of 2026-09-29 (D-149); budget, thresholds, PATH and CLIs rows; test-override table; tests paragraph.

## Commands run
- `bash -n scripts/mac/agent.sh scripts/mac/test.sh` → no output, exit 0.
- `shellcheck scripts/mac/*.sh` → no output, exit 0 (after adding two `SC2034` disables on variables read by `checkx`).
- `scripts/mac/test.sh` → every line `ok`, last line `all passed`; the new cases include:
  - `ok AC-1 slots-init on a directory holding cv-1 and cv-2 (free): adds cv-3, cv-4, cv-5, keeps cv-1 and cv-2 (same files), directory read-only`
  - `ok AC-3 load above 18 refuses …` / `ok AC-3 load of exactly 18 is accepted (exit 0)`
  - `ok AC-2 five stubs run at once (four claude, a codex)` / `ok AC-2 a sixth launch refuses (exit 4) before any worktree or job`
  - `ok AC-4 the agent's PATH begins with $HOME/.asdf/shims and holds no nodejs/22.22.2 …` / `ok AC-4 the CLI was started by its absolute path …`
  - `ok AC-4 claude binary missing: refused (exit 2) …` (and the codex / not-executable variants)
  - `ok AC-5 status of a task without .cli: exit 0, nothing on stderr, listed with ran=unknown`
  - `ok AC-11 the test home is removed`, `ok AC-11 no process of the stubs is left`
- `scripts/mac/agent.sh --dry-run CV-02-dry claude sonnet new "hello" implement`:
  ```
  # PATH /Users/bal7hazar/.asdf/shims:/Users/bal7hazar/go/bin:/Users/bal7hazar/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
  /Users/bal7hazar/.asdf/installs/nodejs/22.22.2/bin/claude -p $'hello …
  ```

## Cost
—

## Acceptance criteria
- AC-1: test "AC-1 slots-init on a directory holding cv-1 and cv-2 …" (inodes of cv-1, cv-2 unchanged, cv-3..5 created, directory 555). The refusal while a slot is held is unchanged code, not re-tested.
- AC-2: "five stubs run at once", "a sixth launch refuses (exit 4) …", race case with one free slot of five.
- AC-3: 18.01 refuses (thresholds and launch), 18 and 11.5 accepted.
- AC-4: PATH and argv[0] checks on the launched stub; missing / non-executable CLI exit 2 before any file is created.
- AC-5: status test above.
- AC-6: the three commands and the dry run above.

## Deviations from the brief
- **`claude` native or not**: `~/.asdf/installs/nodejs/22.22.2/bin/claude` is a symlink to `../lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (seen with `readlink`). I could not run `file` on it (blocked outside the worktree), so I rely on the CV-01 report ("a native Mach-O binary") that it is native and needs no `node`; no node was given to it. I did not run the real `claude` to confirm. If it turns out to need `node`, the narrowest fix is a `node` symlink in a launcher-owned folder placed last on PATH (not the 22.22.2 folder).
- In test mode the stubs are no longer on the agent's `PATH` (they are started by absolute path), so the test PATH is the production one with the test home.
- The dry run stays lenient about a missing binary (it "checks nothing on the machine"); only a real launch refuses.
- I did not run `gh pr checks --watch`: the change is in `scripts/mac/**` only and the task's instruction is to end when REPORT.md is written and the PR is open.

## Escalations
None.

## Open questions
None.
