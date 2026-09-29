# CV-01 — The launcher of track CV on the owner's Mac

Written by the orchestrator of track CV, `[Opus 5.5] Orchestrateur client visuel (Mac)`, on
2026-09-29, under [ORCH-client-visual](ORCH-client-visual.md) §3 (D-146).

## Agent
Title: `[Opus 5.5] CV-01 Mac launcher` · Profile: implement

## Goal

After this task, the orchestrator of track CV launches, resumes, watches and closes its sub-agents
on the owner's Mac with one script, `scripts/mac/agent.sh`, that keeps the contract of
[OPERATIONS.md](../../OPERATIONS.md) §3–§4 as `scripts/agent.sh` keeps it on the VPS: a committed
brief, a fresh worktree, a log, `REPORT.md`, resume and never a relaunch from scratch, the model's
tag in every title and log line, a budget counted by locks, and nothing secret in an agent's
environment. `scripts/agent.sh` is systemd-only and **frozen**: it is read, never edited.

## Context

- [OPERATIONS.md](../../OPERATIONS.md) §2 (models, tags, account), §3 (the machine; the scope of the
  launcher: it guards against accidental over-launch and fails closed, not against a deliberate act
  of the same Unix user), §4 (the contract, the profiles, the residuals accepted).
- [scripts/agent.sh](../../scripts/agent.sh): the reference. Port its behaviour, not its systemd
  and `/proc` mechanics. Its comments name the audit findings each part answers; keep those answers.
- [scripts/profiles/](../../scripts/profiles/): the allowlists, used as they are (never edited).
- The mandate of the track, `docs/briefs/ORCH-client-visual.md` §3 (on `main` once the project
  manager's PR #117 is merged; until then on the branch `pm/client-visual-track`): 2 agents at a
  time on the Mac, audits included; detached; profiles passed; never
  `--dangerously-skip-permissions`; no Sepolia account and no registry token in an agent's
  environment; the model tag everywhere.

### What differs on the Mac (measured by the orchestrator, 2026-09-29)

| | Mac | Consequence |
|---|---|---|
| OS | macOS 26.6 arm64, 12 cores, 64 GB | No systemd, no `/proc`, no `flock(1)`, no `setsid(1)`, no GNU `find -printf`; BSD `stat`, `sed`, `date` |
| Shells | `/bin/bash` is **3.2** (no `{fd}` redirections, no `mapfile`); `/opt/homebrew/bin/bash` is 5.x | Say which one the script needs and check it at start |
| Tools present | `/usr/bin/lockf`, `/usr/bin/shlock`, `/usr/bin/perl`, `launchctl`, `caffeinate`, `/opt/homebrew/bin/shellcheck`, `python3` (3.11), `python3.12` | Locks by `lockf(1)` or `perl`'s `flock`; detachment by launchd |
| The `claude` CLI | 2.1.281. Its default configuration (`~/.claude`) is logged in as **bal7hazar**, the owner's desktop sessions: **never used by an agent and never touched**. Agents use `CLAUDE_CONFIG_DIR=$HOME/.claude-b7r`, logged in as **claude-b7r** | Forced by the launcher, and checked before every launch and resume (below) |
| `codex` | 0.156.1, `~/.local/bin/codex`; on macOS its read-only sandbox is Seatbelt, not bubblewrap | The VPS's reason to keep codex out of systemd does not hold here: codex is detached like claude |
| The calling session's environment | The desktop app's sessions carry, by name: the Sepolia account (`STARKNET_*`), `ATLANTIC_API_KEY`, the app's own credentials and routing (`ANTHROPIC_BASE_URL`, `CLAUDE_CODE_*`, including an OAuth and a messaging token) | An agent inherits **nothing** from it: a whitelisted environment, built from nothing |
| The machine | The owner's personal Mac, shared with the owner's own work | 2 agents at a time; delete and kill only what the launcher created, by exact path, pid or launchd label |

## Scope

- In: `scripts/mac/agent.sh`, its tests `scripts/mac/test.sh` (and fixtures under `scripts/mac/test/`
  if needed), `scripts/mac/README.md`.
- Out: `scripts/agent.sh`, `scripts/lock.sh`, `scripts/profiles/` (frozen; if a profile rule is
  wrong on macOS, write it under *Escalations*); `OPERATIONS.md` and every shared file; the CI
  (`.github/`): the tests run locally on the Mac, their output in the report. No build lock for the
  Mac (`scripts/lock.sh` uses `flock`): the Mac's heavy builds are serialised by the budget of 2;
  say so in the README.
- Allowlist: `scripts/mac/**`, `REPORT.md`.

## Interfaces

The same command line as `scripts/agent.sh`, minus what the Mac refuses:

```
scripts/mac/agent.sh [--dry-run] [--with-assets] [--branch <b>] <task> <claude|codex> <model> <new|resume> "<prompt>" [profile] [sid] [effort]
scripts/mac/agent.sh status | wait <task> | sid <task> | model <task> | thresholds | slots | slots-init | stop <task>
```

`--with-sepolia` is refused on the Mac (exit 2): no task of track CV holds the account.

## Requirements

Each one maps to a test in `scripts/mac/test.sh` (acceptance criteria below).

1. **Account, every launch and resume.** Before anything is created, the launcher runs
   `claude auth status` with `CLAUDE_CONFIG_DIR=$HOME/.claude-b7r`, in the whitelisted environment
   of 3, and refuses (a dedicated exit code, before any worktree, lock, log or job) unless it
   reports `"loggedIn": true` and the email `claude-b7r@proton.me`, parsed as JSON (not by
   substring). For codex, `codex login status` must report a login; its account is recorded in the
   log header.
2. **Detached, never a child of the session.** An agent is a **launchd job of the user's GUI domain**
   (`launchctl bootstrap gui/$(id -u) <plist>` with a plist the launcher writes in the logs folder,
   `RunAtLoad` true, **`KeepAlive` false**, `AbandonProcessGroup` true, its label
   `grimworld.cv.<task>.<utc hhmmss>`, stdout and stderr to the task's log), so that closing or
   restarting the desktop app does not stop it and the app's sandbox does not reach it.
   **`launchctl submit` is forbidden**: it restarts a job that exits, which is a relaunch from
   scratch. A finished job is removed with `launchctl bootout` **by its exact label**, recorded in
   `logs/<task>.label`, never by a pattern. The agent runs under `caffeinate -i` so that idle sleep
   does not suspend it, and at `nice` 10.
3. **Environment built from nothing.** The job's environment is exactly: `HOME`, `USER`, `LOGNAME`,
   `SHELL`, `LANG`, `TMPDIR` (a folder of the task under the logs folder), a fixed `PATH` (the
   asdf installs and shims, `~/.local/bin`, `/opt/homebrew/bin`, the system folders),
   `CLAUDE_CONFIG_DIR=$HOME/.claude-b7r` (claude), `BASH_DEFAULT_TIMEOUT_MS=1800000`,
   `BASH_MAX_TIMEOUT_MS=3600000`, and the launcher's own `GW_*` variables. Nothing else: in
   particular no `STARKNET_*`, `SCARB_*`, `ATLANTIC_*`, `ANTHROPIC_*`, `CLAUDE_CODE_*`, `GH_*`,
   `GITHUB_*`, `OPENAI_*`, `CODEX_*` variable, whatever the calling environment holds. As on the VPS,
   every claude agent also gets `--settings` emptying `SCARB_REGISTRY_AUTH_TOKEN`, the five
   `STARKNET_*` variables and `ATLANTIC_API_KEY` (defence in depth).
4. **Permissions.** Claude: `--permission-mode acceptEdits --allowedTools … --disallowedTools …`
   from `scripts/profiles/<profile>.txt`, read exactly as `scripts/agent.sh` reads it (`@include`,
   `!deny`, comments), **plus Mac deny rules the launcher appends**, because the profiles were
   written for the VPS: `Bash(launchctl*)`, `Bash(* launchctl*)`, `Bash(open *)`, `Bash(osascript*)`,
   `Bash(caffeinate*)`, `Bash(security *)` (the keychain), `Bash(scripts/mac/agent.sh*)`,
   `Bash(./scripts/mac/agent.sh*)`, `Bash(bash scripts/mac/agent.sh*)`, `Read(~/.claude-b7r/**)`,
   `Read(~/.codex/**)`, `Read(~/.config/gh/**)`, `Bash(* ~/.claude-b7r*)`, `Bash(* $HOME/.claude-b7r*)`.
   **Never `--dangerously-skip-permissions`**, and a test greps the built command for it. Codex:
   `exec -s read-only` (resume: `-c 'sandbox_mode="read-only"'`), profile `audit` only.
5. **Budget of 2, counted by locks.** Slot files `cv-1`, `cv-2` in `$HOME/orchestrator/slots` (a
   directory of the Mac only; created by `slots-init`, read-only afterwards; a missing or unreadable
   slot refuses the launch, as on the VPS). The agent's inner shell takes one slot by a kernel lock
   on a descriptor its children inherit (`lockf(1)` or `perl`'s `flock`; say which and why), writes
   `slots-acquired` in `logs/<task>.run`, and the kernel frees the lock however the agent ends. The
   launcher holds a launch lock (`$HOME/orchestrator/agent-launch.lock`) from the count to
   `slots-acquired`, stops the job it started if that never comes (by its label), and says whether
   the stop is verified. Nothing is counted by reading processes.
6. **Thresholds**, fixed in the script: no launch or resume while the 5-minute load average
   (`sysctl -n vm.loadavg`) is above **10**, or less than **8 GB** of memory is available (free +
   inactive + speculative pages from `vm_stat`, or `memory_pressure`; say which). A running agent is
   never stopped for load.
7. **The contract of OPERATIONS §4.** Worktree `<main>/.claude/worktrees/cli-<task>` from
   `origin/main` (`--branch`); `--with-assets` initialises the `assets` submodule in it; logs in
   `<main>/.claude/worktrees/logs/`: `<task>.log` (each run starts with a header
   `--- <utc> [<Model tag>] <task> <mode> (<profile>) <cli> <model id> label=<label> account=<account>`
   and ends with `model=<what ran>` and `exit=<status> <utc>`), `.profile`, `.cli`, `.run`, `.label`,
   `.start`, codex `.last.md`. A new launch refuses while the task's worktree exists with a record
   (resume it instead); a resume needs the record and **the same model**, and keeps the profile. The
   foreground rule is appended to every prompt, word for word as `scripts/agent.sh` does. The model
   tag table is `scripts/agent.sh`'s (`sonnet`, `opus`, `fable`, full ids; codex `gpt-6-astra`,
   `gpt-6-sol`, `gpt-6-luna`); an unknown model is refused. Claude new: `--name "[<tag>] <task>"`.
8. **Status and wait.** `status` lists each task (running or stopped, profile, the model that ran,
   last write, the header of the run or its `exit=` line) and each slot; `model <task>` reads the
   model from the claude transcript under `$HOME/.claude-b7r/projects/<mangled worktree path>/`
   (the newest `.jsonl`, by BSD `stat`) or codex's `model:` line; `sid <task>` finds codex's session
   id; `wait <task>` blocks until the job has exited; `stop <task>` boots out the task's own job by
   its recorded label, and nothing else.
9. **Portable and checked**: `bash -n` and `shellcheck` clean; the script says at start which bash it
   needs and refuses another.

## Acceptance criteria

`scripts/mac/test.sh` runs every case below **with stub CLIs** (fake `claude` and `codex`), a
temporary `HOME` for the slots and the lock under the worktree, and prints one `ok`/`FAIL` line per
case. It never starts a real agent and never spends a token.

- [ ] AC-1 The account check refuses when the stub reports another email, `loggedIn: false`, or
  output that is not JSON; nothing is created (no worktree, log, lock taken, job).
- [ ] AC-2 A launched stub job's parent is `launchd` (pid 1), and it survives the exit of the shell
  that launched it (the test launches from a subshell that exits, then checks the job is alive).
- [ ] AC-3 The stub prints its environment's names: exactly the whitelist, none of the forbidden
  prefixes, although the test sets decoys (`STARKNET_PRIVATE_KEY=decoy`, `ANTHROPIC_BASE_URL=decoy`,
  `CLAUDE_CODE_OAUTH_TOKEN=decoy`, `ATLANTIC_API_KEY=decoy`, `GH_TOKEN=decoy`) in the caller.
- [ ] AC-4 The built command (`--dry-run` and the stub's argv) holds the profile's rules, the Mac
  deny rules, the `--settings` override and `--name "[Opus 5.5] <task>"`, and never
  `--dangerously-skip-permissions`; codex runs `-s read-only`.
- [ ] AC-5 With both slots held by two running stubs, a third launch refuses before any worktree or
  job is created; when a stub ends, its slot is free again without any cleanup step.
- [ ] AC-6 A job that never writes `slots-acquired` is stopped by its label and reported.
- [ ] AC-7 `resume` refuses without a record or with another model, keeps the profile, and runs
  `claude --continue`; a `new` refuses while the task's worktree exists with a record.
- [ ] AC-8 After a stub ends: `exit=` and `model=` lines in the log, the job booted out by its exact
  label, `launchctl print gui/<uid>/<label>` finds nothing.
- [ ] AC-9 `--with-sepolia` and an unknown model are refused; the thresholds refuse when forced
  above their limits by a test-only override.
- [ ] AC-10 `bash -n` and `shellcheck scripts/mac/*.sh` are clean.
- [ ] AC-11 The tests leave nothing behind: every launchd job, temporary folder and lock file they
  created is removed by exact label and path, and the test checks it.

The test-only overrides (the stub CLIs on `PATH`, the thresholds, the account's email) are the
weakest part of such a script: an override that production honours is a way around the account
check or the budget. Make them impossible to use outside the tests (for example, the script reads
them only when invoked by `scripts/mac/test.sh` with a `HOME` under the worktree, or the tests
source a function-level seam rather than setting variables), and say how in the README.

## Verification

```
bash -n scripts/mac/agent.sh scripts/mac/test.sh
shellcheck scripts/mac/*.sh
scripts/mac/test.sh
scripts/mac/agent.sh --dry-run CV-01-dry claude opus new "hello" implement
```

## Rules of this run

- You run on the owner's personal Mac. The launchd jobs, files and locks you create are named with
  the prefix `grimworld.cv.test.` or live under your worktree, and you remove them yourself, by exact
  label and path. Never `launchctl` on a label you did not create, never a kill by pattern, never
  `rm` outside your worktree. Your profile refuses typed `launchctl`: the tests call it from the
  scripts.
- Never run a real `claude` or `codex`, from the tests or by hand (your profile refuses them): stubs
  only. Never read `~/.claude`, `~/.claude-b7r`, `~/.codex`, `~/.config/gh`, or the keychain.
- Pull request: branch `cv/CV-01-mac-launcher` (your worktree is on it, with this brief as its first
  commit), title `feat(scripts/mac): CV-01, the launcher of track CV on the Mac`, body with the test
  output and the README's summary. Commits end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. The CI has nothing to run for
  `scripts/mac/`: the local test output is the evidence.

## Report

`REPORT.md` at the worktree root, header `[Opus 5.5] CV-01 — Mac launcher`: summary; files; the
commands of *Verification* with their real output; how each requirement 1–9 is met and tested; the
test-only overrides and why production cannot use them; deviations; escalations (a profile rule that
is wrong on macOS, anything the frozen files would need); open questions.
