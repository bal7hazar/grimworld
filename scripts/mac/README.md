# scripts/mac — the launcher of track CV on the owner's Mac

`scripts/mac/agent.sh` starts, resumes, watches and stops the sub-agents of track CV on the owner's
Mac. It keeps the contract of [OPERATIONS.md](../../OPERATIONS.md) §3–§4 as `scripts/agent.sh` keeps
it on the VPS (a committed brief, a fresh worktree, a log, `REPORT.md`, resume and never a relaunch
from scratch, the model's tag everywhere, a budget counted by locks, nothing secret in an agent's
environment), with macOS mechanics. `scripts/agent.sh`, `scripts/lock.sh` and `scripts/profiles/`
are frozen and used as they are. Brief: [CV-01](../../docs/briefs/CV-01-mac-launcher.md).

```
scripts/mac/agent.sh [--dry-run] [--with-assets] [--branch <b>] <task> <claude|codex> <model> <new|resume> "<prompt>" [profile] [sid] [effort]
scripts/mac/agent.sh status | wait <task> | sid <task> | model <task> | thresholds | slots | slots-init | stop <task>
scripts/mac/test.sh     # the tests, with stub CLIs; never a real agent, never a token
```

Exit codes: 0 done, 2 refused (usage, record, model, profile, `--with-sepolia`, a launch that did not
report), 4 thresholds or budget, 5 account. Once on the Mac, before the first launch:
`scripts/mac/agent.sh slots-init`.

## Summary

| | How |
|---|---|
| Shell | bash 5, `/opt/homebrew/bin/bash` (the shebang). `/bin/bash` 3.2 is refused at start (no `{fd}` redirections). |
| Account | Before anything is created, `claude auth status` runs in the agents' environment with `CLAUDE_CONFIG_DIR=~/.claude-b7r`; its output must be exactly one JSON object with `"loggedIn": true` and `"email": "claude-b7r@proton.me"` (parsed by `jq`), else exit 5. Codex: `codex login status` must start with `Logged in`; only the kind of login (`codex-chatgpt`, `codex-api-key`) is written to the log header, never the text. The owner's `~/.claude` (bal7hazar) is never used. `--dry-run` checks nothing (it launches nothing). |
| Detached | A launchd job of the GUI domain: `launchctl bootstrap gui/<uid> logs/<label>.plist`, label `grimworld.cv.<task>.<utc hhmmss>`, `RunAtLoad` true, `KeepAlive` false (never restarted), `AbandonProcessGroup` true, `Nice` 10, stdout and stderr to the task's log, run under `caffeinate -i`. Its parent is launchd (pid 1): closing the desktop app does not stop it. `launchctl submit` is never used. |
| Environment | The job starts `/usr/bin/env -i` with a whitelist: `HOME USER LOGNAME SHELL LANG TMPDIR PATH BASH_DEFAULT_TIMEOUT_MS BASH_MAX_TIMEOUT_MS`, `CLAUDE_CONFIG_DIR` (claude) and the launcher's `GW_*`. The shells add `PWD SHLVL _` and caffeinate `__CF_USER_TEXT_ENCODING`; nothing of the caller. `HOME`, `USER` and `SHELL` come from the user database. claude also gets `--settings` emptying the registry token, the five `STARKNET_*` and `ATLANTIC_API_KEY`. |
| Permissions | The profile of `scripts/profiles/`, read as `scripts/agent.sh` reads it, plus Mac deny rules (launchd, `open`, `osascript`, `caffeinate`, the keychain, this launcher, the credentials of `~/.claude-b7r`, `~/.codex`, `~/.config/gh` by `~`, `$HOME` and absolute path). Never `--dangerously-skip-permissions`. Codex: `exec -s read-only` (resume: `sandbox_mode="read-only"`), profile `audit` only. |
| Budget | 2 agents at a time on the Mac, audits included: slot files `~/orchestrator/slots/cv-1`, `cv-2` (directory mode 555; `slots-init` creates missing ones). The agent's inner shell locks one with `/usr/bin/lockf -s -t 5 7` on a descriptor its children inherit, writes `slots-acquired` in `logs/<task>.run`; the kernel frees the lock however the agent ends. The launcher holds `~/orchestrator/agent-launch.lock` from the count to `slots-acquired` and stops the job by its label if that never comes (20 s), saying whether the stop is verified. |
| Thresholds | Fixed: no launch or resume while the 5-minute load (`sysctl vm.loadavg`) is above 10 or less than 8 GB is available (free + inactive + speculative pages of `vm_stat`). A running agent is never stopped for load. |
| Builds | No build lock on the Mac (`scripts/lock.sh` needs `flock`): the Mac's heavy builds are serialised by the budget of 2. |
| Labels | The label read from `logs/<task>.label` is checked before any `launchctl print`, kill or bootout: it must be exactly `grimworld.cv.<task>.<hhmmss>` (`grimworld.cv.test.<task>.<hhmmss>` in test mode). Anything else, such as a copy of another task's label, is refused and never acted on: `stop`, `wait`, a launch or resume of the task exit 2, and `status` lists the task as `refused`. Outside the tests a task name may not start with `test.`, so no real label reads as a test label. |
| Closing a job | A finished job stays loaded in launchd until it is booted out by its exact label (`logs/<task>.label`): `wait`, `status`, `stop` and the next launch of the task do it. `stop` signals the job's process group (launchd makes the job a group leader; `AbandonProcessGroup` means a bootout alone would leave the CLI running), then boots it out, then checks the label, the group and the slot are gone. |

Files, under `<main checkout>/.claude/worktrees/`: `cli-<task>/` (the worktree), and in `logs/`:
`<task>.log` (each run starts with
`--- <utc> [<Model tag>] <task> <mode> (<profile>) <cli> <model id> label=<label> account=<account>`
and ends with `model=` and `exit=`), `.label`, `<label>.plist`, `.profile`, `.cli`, `.run`, `.start`,
codex `.last.md`, and `tmp-<task>/` (the agent's `TMPDIR`).

## Why lockf, why vm_stat

- **`lockf(1)`**, macOS's own tool, in its descriptor form (`lockf -s -t <seconds> <fd>`): it takes a
  `flock(2)` lock on the open file behind the descriptor and exits; the lock stays with the open
  file, which the inner shell and every child share, and ends when the last of them closes it. It is
  the `flock -w 5 7` of the VPS, with exit 75 for "held". `perl`'s `flock` would do the same with a
  process more.
- **`vm_stat`** rather than `memory_pressure`: the same counters, read faster; free + inactive +
  speculative is what the kernel hands out without swapping.

## Test-only overrides, and why production cannot use them

`scripts/mac/test.sh` needs stub CLIs, forced thresholds, a short deadline and a job that hangs. None
of these is a variable. The launcher accepts two homes only: the user's real home (from the user
database, not from `$HOME`), or a **test home**: a folder `scripts/mac/test/run.<id>` of the same
checkout as the script, owned by the user, holding the marker `.grimworld-mac-test`. Any other `HOME`
is refused (exit 2). Every override is read from files of the test home and only in test mode:

| Override | Test mode only |
|---|---|
| Stub CLIs | `$HOME/bin` comes first on the agents' PATH, and the CLI **must** resolve there, else refused |
| Thresholds | `$HOME/test-load5`, `$HOME/test-mem-gb` |
| Deadline of `slots-acquired` | `$HOME/test-deadline` |
| A job that never reports | `$HOME/test-hang`: the launcher then adds `GW_TEST_HANG=1` to the job's environment, which it builds from nothing, so no caller can set it |

A test home cannot reach anything real: its slots and launch lock are `$HOME/orchestrator/…` of the
test home (not the real budget), its repository is `$HOME/repo` with a local origin, the claude
configuration is `$HOME/.claude-b7r` of the test home (no login), the CLIs must be its stubs, and its
labels are `grimworld.cv.test.*`. So an override can neither pass the real account check nor count
against, or around, the real budget. As for every rule of the launcher (OPERATIONS §3), this guards
against accidents, not against a deliberate act of the same Unix user.

## Tests

`scripts/mac/test.sh` creates the test home, a repository with its own origin, and stub `claude` and
`codex` that print their argv and environment names and hold while a file exists. It checks the
account refusals (nothing created), the detachment (parent pid 1, alive after the launching shell
exits, nice 10, caffeinate's assertion), the environment against decoys (`STARKNET_PRIVATE_KEY`,
`ANTHROPIC_BASE_URL`, `CLAUDE_CODE_OAUTH_TOKEN`, `ATLANTIC_API_KEY`, `GH_TOKEN`…), the command line,
the budget of 2 with a claude and a codex, two launchers racing for the last free slot, a label file
holding another task's label, a job that never reports, resume, `wait`, `stop`, the refusals,
`bash -n` and `shellcheck`, and finally that every job, file and lock it made is gone. It prints one
`ok`/`FAIL` line per case and takes about a minute (59 s measured on 2026-09-29).

Its tasks are named `<run id>-<case>`, so every label of a run starts with
`grimworld.cv.test.<run id>-`. A task is recorded before it is launched, and a launcher started in the
background (the race) has its exact pid recorded. The cleanup runs on EXIT, INT and TERM (and ignores
a second signal while it runs):
1. It stops the in-flight launchers by pid: SIGSTOP, their direct children listed by parent pid,
   TERM and CONT. It waits for the launchers and for those children, so a `launchctl bootstrap` that
   is under way ends before the next step.
2. It recovers every exact label from the run's own files (`logs/*.label` and the
   `logs/<label>.plist` the launcher wrote), never a label outside that prefix, and stops and boots
   out each job.
3. It checks that no label of the run is loaded, and only then removes the test home. If any label
   is still loaded, it keeps the home and says so.

A test runs this drain 0.1 to 3.5 s after starting two launchers, so that it catches them in every
phase from the account check to a running job.
