# [Opus 5.5] CV-01 — Mac launcher

## Summary

`scripts/mac/agent.sh` is the new launcher for track CV's sub-agents on the owner's Mac: it launches, resumes, watches and stops them, and keeps the contract of OPERATIONS §3–§4. Each agent is a launchd job of the GUI domain, started with an environment built from nothing. The launcher checks the claude-b7r account before every launch and resume, and counts a budget of 2 with `lockf` locks on `~/orchestrator/slots/cv-1` and `cv-2`. `scripts/mac/test.sh` checks all of this with stub CLIs, and all 56 of its cases pass on the Mac (26 s). `scripts/agent.sh`, `scripts/lock.sh` and `scripts/profiles/` were read and not edited.

- Pull request: https://github.com/bal7hazar/grimworld/pull/121 (branch `cv/CV-01-mac-launcher`, commit `54146b3`). `gh pr checks 121`: "no checks reported". As the brief expected, the CI has nothing to run for `scripts/mac/`.
- The model in my session is Opus 5.5 (`claude-opus-5-5`), the same as the brief names.
- Per ORCH-client-visual §3, `[GPT-6-Sol]` still has to audit the launcher (security lens) before it launches anything. No real agent was launched, and I never ran a real `claude` or `codex`.

## Files changed

- `scripts/mac/agent.sh`: the launcher (new, about 560 lines).
- `scripts/mac/test.sh`: the tests. They use stub CLIs, a test home and a local git origin, and print one `ok`/`FAIL` line per case.
- `scripts/mac/README.md`: usage, a summary table, why `lockf` and `vm_stat`, the test-only overrides, and the tests.
- `scripts/mac/test/.gitignore`: ignores the test homes (`run.*`), which the test removes itself.

## Commands run

Probes of the machine (throwaway scripts, removed before the commit; one throwaway job labelled `grimworld.cv.test.probe*`, booted out by its label):
- `lockf -s -t 5 7` on a descriptor gives exit 0. A second open of the same file then gets exit 75 (with `-t 1` or `-t 0`). After the first descriptor is closed, the second open gets exit 0. So the lock belongs to the open file.
- A job bootstrapped with `/usr/bin/env -i … /usr/bin/caffeinate -i /opt/homebrew/bin/bash -c …` has ppid 1, pgid equal to its pid, and nice 10. Its environment names were `HOME PATH PWD SHLVL _ __CF_USER_TEXT_ENCODING`. `pmset -g assertions` showed "caffeinate asserting on behalf of '/opt/homebrew/bin/bash' (pid <job pid>)". After the job exited it stayed loaded (`state = not running`, `last exit code = 0`) until it was booted out; after that, `launchctl print` exited with 113.
- `which -a claude codex`: `claude` is `~/.asdf/installs/nodejs/22.22.2/bin/claude`, a native Mach-O binary (`claude.exe` from the npm package). `codex` is `~/.local/bin/codex`, also Mach-O. `sysctl -n vm.loadavg` printed `{ 2.10 2.12 2.14 }`; `vm_stat` reports a page size of 16384.

Verification, from the brief:

```
$ bash -n scripts/mac/agent.sh scripts/mac/test.sh
(no output)
$ shellcheck scripts/mac/agent.sh scripts/mac/test.sh
(no output)
$ time scripts/mac/test.sh
ok   AC-1 account refused ({"loggedIn": true, "email": "bal7hazar@example.com"}): exit 5, no worktree, log, lock or job
ok   AC-1 account refused ({"loggedIn": false, "email": "claude-b7r@proton.me"}): exit 5, no worktree, log, lock or job
ok   AC-1 account refused (loggedIn: true email: claude-b7r@proton.me): exit 5, no worktree, log, lock or job
ok   AC-1 account refused ({"loggedIn": true, "email": "x"} {"loggedIn": true, "email": "claude-b7r@proton.me"}): exit 5, no worktree, log, lock or job
ok   AC-1 no job was created for A1
ok   slots-init: cv-1, cv-2, directory read-only
ok   AC-9 --with-sepolia refused (exit 2)
ok   AC-9 unknown model refused (exit 2)
ok   AC-9 unknown codex model refused (exit 2)
ok   AC-9 load above 10 refuses (thresholds and launch: exit 4, no worktree)
ok   AC-9 memory under 8 GB refuses (exit 4)
ok   thresholds pass with the machine's own values
ok   a HOME that is neither the user's nor a test home is refused
ok   AC-4 dry run: profile rules, Mac deny rules, --settings, --name
ok   AC-4 dry run: never --dangerously-skip-permissions
ok   AC-4 dry run: the foreground rule ends the prompt
ok   AC-4 dry run codex: exec -s read-only, profile audit
ok   AC-4 dry run codex: header [GPT-6-Sol] … (audit)
ok   AC-4 codex with another profile than audit is refused
ok   launch of T2-Q8UbhR: exit 0, holds a slot
ok   AC-8 the label is grimworld.cv.test.T2-Q8UbhR.<hhmmss>
ok   AC-2 the job's process is alive after the launching shell exited
ok   AC-2 the job's parent is launchd (pid 1)
ok   AC-2 the job runs at nice 10
ok   AC-2 caffeinate asserts on behalf of the job
ok   AC-2 the plist says RunAtLoad true, KeepAlive false, AbandonProcessGroup true
ok   AC-3 the stub's environment is exactly the whitelist (decoys set in the caller)
ok   AC-3 CLAUDE_CONFIG_DIR is the test home's .claude-b7r, TMPDIR the task's
ok   AC-4 the stub's argv: profile rules, Mac deny rules, --settings, --name
ok   AC-4 the stub's argv: never --dangerously-skip-permissions
ok   AC-4 the plist: never --dangerously-skip-permissions
ok   AC-7 a new launch refuses while the task's worktree exists with a record
ok   AC-8 wait returns the exit and the model
ok   AC-8 the log has the header, model= and exit=
ok   AC-8 the job is booted out: launchctl print gui/501/grimworld.cv.test.T2-Q8UbhR.102727 finds nothing
ok   AC-8 status shows the task stopped, implement, ran=claude-opus-5-5
ok   AC-7 resume without a record is refused
ok   AC-7 resume with another model is refused
ok   AC-7 resume with another profile is refused
ok   AC-7 resume runs claude --continue, keeps the profile implement
ok   AC-7 resume argv: --continue and the implement rules, no --name
ok   AC-7 the resumed run has its own header and exit=
ok   AC-5 two stubs run (a claude, a codex)
ok   AC-5 both slots are held
ok   AC-5 a third launch refuses (exit 4) before any worktree or job
ok   AC-5 when a stub ends its slot is free again, without any cleanup step
ok   AC-5 codex ran -s read-only and its model was read
ok   AC-6 a job that never reports: exit 2, stopped by its label, verified
ok   AC-6 its label is gone from launchd and both slots are free
ok   stop: the job is stopped, booted out, verified; its process is gone; its slot free
ok   AC-10 bash -n
ok   AC-10 shellcheck scripts/mac/*.sh
ok   AC-10 /bin/bash 3.2 is refused by the launcher
ok   AC-11 every job is gone (6 labels checked, none containing Q8UbhR in launchctl list)
ok   AC-11 the test home is removed
ok   AC-11 no process of the stubs is left
all passed

real	0m26.404s
user	0m5.484s
sys	0m9.754s

$ scripts/mac/agent.sh --dry-run CV-01-dry claude opus new "hello" implement
# [Opus 5.5] CV-01-dry new (implement)
# worktree /Users/bal7hazar/git/grimworld/.claude/worktrees/cli-CV-01-dry  log /Users/bal7hazar/git/grimworld/.claude/worktrees/logs/CV-01-dry.log  launchd job gui/501/grimworld.cv.CV-01-dry.102644  with-assets=0
/Users/bal7hazar/.asdf/installs/nodejs/22.22.2/bin/claude -p $'hello\n\nForeground only: never run a command in the background and never end your turn waiting for one; in headless mode that ends the session. Your turn ends when REPORT.md is written.' --model claude-opus-5-5 --name \[Opus\ 5.5\]\ CV-01-dry --settings \{\"env\":\{\"SCARB_REGISTRY_AUTH_TOKEN\":\"\"\,…\"ATLANTIC_API_KEY\":\"\"\}\} --permission-mode acceptEdits --allowedTools Read Grep Glob … --disallowedTools Bash\(find\ \*\ -delete\*\) … Bash\(launchctl\*\) Bash\(\*\ launchctl\*\) Bash\(open\ \*\) Bash\(osascript\*\) Bash\(caffeinate\*\) Bash\(security\ \*\) Bash\(scripts/mac/agent.sh\*\) … Read\(~/.claude-b7r/\*\*\) … Read\(//Users/bal7hazar/.claude-b7r/\*\*\) … --max-turns 400 --output-format text
```
(The dry-run line is trimmed with "…" here; the full line lists every rule of `implement` and the Mac rules.)

Two earlier test runs failed, and I fixed both causes:
1. bash 5.3 has `patsub_replacement` on, so `&` in `${s//</&lt;}` stood for the matched text and produced an invalid plist. The replacements are now quoted.
2. The test's `agent status | grep -q` failed under `pipefail` because `grep -q` exits early and the writer gets SIGPIPE. The test now captures the output first. For the same reason `job_pid` no longer pipes into `head`.

The first failing run left its test home behind because the slot directory is mode 555. I removed that folder by its exact path, and the cleanup now makes the directory writable before `rm`.

## Cost

— (no Cairo).

## Acceptance criteria

| | Shown by |
|---|---|
| AC-1 | 4 account variants refused with exit 5: another email, `loggedIn: false`, not JSON, two JSON objects. In each case no worktree, log, label, `~/orchestrator` (so no launch lock) or job was created. |
| AC-2 | The job's pid has ppid 1, is alive after the `bash -c` that launched it has exited, and runs at nice 10. caffeinate's assertion names that pid. The plist's `RunAtLoad`, `KeepAlive` and `AbandonProcessGroup` were read with `plutil -extract`. |
| AC-3 | The stub lists its environment's names with perl's `%ENV`. They are exactly the whitelist plus the shell-added `PWD SHLVL _` (and `OLDPWD`, `__CF_USER_TEXT_ENCODING` if present), none of the forbidden prefixes appears, and the caller held decoys for `STARKNET_PRIVATE_KEY`, `ANTHROPIC_BASE_URL`, `CLAUDE_CODE_OAUTH_TOKEN`, `ATLANTIC_API_KEY`, `GH_TOKEN`, `SCARB_REGISTRY_AUTH_TOKEN` and `OPENAI_API_KEY`. |
| AC-4 | Checked in the dry run's argv (re-read with `eval` of its `%q` output) and in the stub's argv: profile allow and deny rules, all 14 Mac rules of the brief, the `--settings` JSON, `--name "[Opus 5.5] <task>"`, and the foreground rule. `dangerously` appears in neither, nor in the plist. Codex: `exec -s read-only`, and any profile other than `audit` is refused. |
| AC-5 | A claude stub and a codex stub hold `cv-1` and `cv-2`. A third launch gets exit 4 with no worktree, no label and no job. When one stub ends, `thresholds` passes again with no cleanup step. |
| AC-6 | In test mode, `test-hang` stops the job before its slot. After a 3 s deadline the launcher exits 2 and reports "its job <label> is stopped and booted out, and slot cv-N is free (verified)"; the label is gone and both slots are free. |
| AC-7 | Resume is refused (exit 2) without a record, with another model, or with another profile. Resume keeps `implement`, runs `--continue` without `--name`, and writes its own header and a second `exit=0`. `new` is refused while the worktree and the record exist. |
| AC-8 | The log holds the header regex `--- <utc> [Opus 5.5] <task> new (implement) claude claude-opus-5-5 label=<label> account=claude-b7r@proton.me`, plus `model=claude-opus-5-5` and `exit=0 <utc>`. `wait` booted the job out, and afterwards `launchctl print` finds nothing. `status` shows the task as `stopped implement ran=claude-opus-5-5`. |
| AC-9 | `--with-sepolia` and unknown models (claude, codex) are refused with exit 2. A forced load of 11.5 and forced memory of 7 GB both give exit 4 (`thresholds` and a launch). |
| AC-10 | `bash -n` and `shellcheck` are clean, run by hand and inside the test. `/bin/bash scripts/mac/agent.sh` gets exit 2. |
| AC-11 | The cleanup stops each task (`agent.sh stop`) and boots out each recorded label. It then checks that all 6 labels are absent, that `launchctl list` has no label containing the run id, that the test home is gone, and that no stub process is left. |

### Requirements 1–9, how each is met

1. **Account.** `check_account` runs after every local refusal and before the launch lock, the worktree or any record. It calls `env -i <whitelist> <resolved claude> auth status`, which must exit 0, and `jq -e -s` requires exactly one object with `.loggedIn == true` and `.email == "claude-b7r@proton.me"`; otherwise it exits 5. For codex, `login status` must exit 0 and print a line starting with `Logged in`; the header records `codex-chatgpt`, `codex-api-key` or `codex-logged-in`, never the raw text. The claude and codex binaries are resolved once on the agents' PATH, so the check and the job run the same binary. Tested by AC-1, and AC-8 checks `account=` in the header.
2. **Detached.** `write_plist` plus `launchctl bootstrap gui/<uid>`, with label `grimworld.cv.<task>.<utc hhmmss>` (`grimworld.cv.test.` in test mode), recorded in `logs/<task>.label`. The plist is `logs/<label>.plist`, with `RunAtLoad` true, `KeepAlive` false, `AbandonProcessGroup` true, `Nice` 10, and stdout and stderr to the log; the job runs `caffeinate -i`. A finished job is booted out by its exact label in `wait`, `status`, `stop` and the next launch (`reap`). The script never uses `launchctl submit`. Tested by AC-2 and AC-8.
3. **Environment.** `build_env`: `HOME` and `USER`/`LOGNAME` (from `id -un`), `SHELL` (the login shell from `getpwuid`), `LANG=en_US.UTF-8`, `TMPDIR=logs/tmp-<task>/`, the fixed `PATH`, `BASH_*_TIMEOUT_MS`, `CLAUDE_CONFIG_DIR` (claude only) and `GW_*`, all passed through `/usr/bin/env -i`. `--settings` empties the token, the five `STARKNET_*` and `ATLANTIC_API_KEY`. Tested by AC-3 and AC-4.
4. **Permissions.** `read_profile`/`load_profile` are copied verbatim from `scripts/agent.sh`, and `MAC_DENY` holds the brief's 14 rules plus 7 absolute-path forms (see *Deviations*). There is no `--dangerously-skip-permissions` anywhere. Codex uses `-s read-only` for new runs and `sandbox_mode="read-only"` for resume, with `audit` only. Tested by AC-4.
5. **Budget.** `SLOT_NAMES=(cv-1 cv-2)`; `slots-init` creates missing slots, and only while every slot is free, under the launch lock. The inner shell runs `exec 7< slot; lockf -s -t 5 7`, then writes `slots-acquired` to the `.run` file. I chose `lockf` over perl because it is macOS's own `flock(2)` tool and the descriptor form matches the VPS's `flock -w 5 7` exactly, without keeping a perl process alive. The launch lock (`lockf -t 600` on `~/orchestrator/agent-launch.lock`) is held from the count until `slots-acquired`. If that never comes, `stop_job` signals the job's process group, runs `bootout <label>`, and reports the stop as verified only when the label, the group and the slot are all gone. Tested by AC-5, AC-6 and `stop`.
6. **Thresholds.** `MAX_LOAD5=10 MIN_MEM_GB=8`, fixed. Load is field 3 of `sysctl -n vm.loadavg`. Memory is (free + inactive + speculative pages) × page size from `vm_stat`; I chose it over `memory_pressure` because it gives the same counters faster. A running agent is never stopped for load. Tested by AC-9.
7. **Contract.** The worktree comes from `origin/main` with `--branch`; `--with-assets` initialises the submodule. The files are `.log`, `.profile`, `.cli`, `.run`, `.label`, `.start`, codex `.last.md` and `tmp-<task>/`. The header and the `model=`/`exit=` lines follow the brief. The rules copied from `scripts/agent.sh` are: `new` refused while the worktree and record exist; `resume` needs the record, the same CLI and model, and keeps the profile; the foreground rule is appended word for word; the tag table is the same; unknown models are refused; claude `new` gets `--name "[<tag>] <task>"`. Tested by AC-4, AC-7, AC-8 and AC-9.
8. **Status and wait.** `status` shows running or stopped, the profile, `ran=` (with MISMATCH when it differs from the record), the last write, and the header or `exit=` line, then the slots. `model` reads the newest `.jsonl` under `~/.claude-b7r/projects/<mangled>` (BSD `stat -f '%m %N'`), or codex's `model:` line. `sid` is as on the VPS. `wait` polls `launchctl print` every 5 s, then reaps. `stop <task>` acts on the recorded label only. Tested by AC-8, AC-5 (codex model) and `stop`.
9. **Portable.** The shebang is `/opt/homebrew/bin/bash`, and a first check, written in bash 3.2 syntax, refuses any bash older than 5 (exit 2). The script also refuses a system other than Darwin and checks that `lockf`, `caffeinate`, `launchctl`, `plutil`, `perl` and `jq` are present. `bash -n` and `shellcheck` are clean. Tested by AC-10.

### Test-only overrides, and why production cannot use them

No environment variable turns on any test behaviour. The launcher reads the user's real home from the user database (`getpwuid`) and accepts only two values of `HOME`:
- the real home;
- a **test home**, whose physical path is `<this checkout>/scripts/mac/test/run.<alnum>`, owned by the user and holding `.grimworld-mac-test`.

Anything else gets exit 2 (tested). All overrides are files inside the test home and are read only in test mode:
- `test-load5` and `test-mem-gb`: the thresholds;
- `test-deadline`: the wait for `slots-acquired`;
- `test-hang`: the launcher then adds `GW_TEST_HANG=1` to the job's environment, which it builds from nothing, so no caller can set it;
- `$HOME/bin`: the stubs. In test mode the CLI must resolve to them, or the launch is refused.

A test home also cannot reach anything real. Its slots and lock are inside it, its repository is `$HOME/repo` with a local origin, and its `CLAUDE_CONFIG_DIR` is `$HOME/.claude-b7r` of the test home, which has no login. Its labels are `grimworld.cv.test.*`. So an override can neither pass the real account check nor change the real budget. As OPERATIONS §3 says of the launcher, this guards against accidents, not against a deliberate act by the same Unix user.

## Deviations from the brief

- **Mac deny rules**: I added 7 rules beyond the brief's list. They are the absolute-path forms of the home: `Read(//Users/<u>/.claude-b7r/**)`, `.claude/**`, `.codex/**` and `.config/gh/**`, and `Bash(* /Users/<u>/.claude-b7r*)`, `Bash(* /Users/<u>/.claude/*)` and `Bash(* /Users/<u>/orchestrator*)`. The profiles cover `/home/claude/...` (the VPS home) only, so without these the Mac's absolute paths would be uncovered. They only add denials.
- **Resume with an explicit different profile is refused** (exit 2); `scripts/agent.sh` would accept it. I made it strict to match "keeps the profile". The same profile, or none, is accepted, so the OPERATIONS resume form for codex (`… audit <sid>`) still works.
- **The account check's `TMPDIR`**: the whitelisted environment of requirement 3 names the task's `TMPDIR`. The brief also forbids creating anything before the check, so the check uses the system's per-user temp directory (`getconf DARWIN_USER_TEMP_DIR`) instead.
- **Stopping a job** signals its process group before `bootout`. With `AbandonProcessGroup` true (required by the brief), a bootout alone signals only the main process, so the claude or codex child would keep running. The group is the one launchd made for that exact label (pgid = the job's pid, checked); if it is not a group leader, the pid alone is signalled. After a verified stop, `stop` writes `exit=stopped <utc>` to the log.
- **`status` boots out** finished jobs of the tasks it lists (by their exact labels), just as `wait` does.
- **The fixed `PATH`**: I read the brief's "the asdf installs" as the one install that holds the claude CLI, `~/.asdf/installs/nodejs/22.22.2/bin`, placed first. After it come `~/.asdf/shims`, `~/go/bin` (asdf), `~/.local/bin`, `/opt/homebrew/bin` and the system folders. This mirrors the PATH of the session that launched me.

## Escalations

- **`scripts/profiles/` on macOS** (frozen, so I did not edit it):
  - The machine-specific deny rules name `/home/claude/...` only. The launcher's Mac rules compensate for `.claude-b7r`, `.claude`, `.codex`, `gh` and `orchestrator`, but not for `/Users/<u>/.local/bin` or `/Users/<u>/.cargo/bin`, where the profiles also deny the `~` and `$HOME` forms.
  - `Bash(free *)` and `Bash(nproc)` are Linux commands with no macOS equivalent in the profiles (`sysctl`, `vm_stat` are not allowed). This is harmless: it only means an agent cannot read the machine's load.
- **Node on the Mac**: the repository pins `nodejs 24.21.0` in `.tool-versions`, but the Mac has `24.16.0`, not `24.21.0` (`~/.asdf/installs/nodejs`). With the fixed PATH, `node` in an agent resolves to 22.22.2 (the claude install), ahead of the shim. For a client task that needs the pinned Node, either install 24.21.0 (the owner's decision, not the launcher's) or run claude through an absolute path and put the shims first. I did not change this, because it goes beyond the launcher's scope.

## Open questions

- **The shape of `claude auth status`**: the check expects a top-level `loggedIn` and `email`, as the brief describes, and exit 0 when logged in. I could not run the real CLI (forbidden). If CLI 2.1.281 nests the email or exits non-zero while logged in, the launcher fails closed with exit 5, and `check_account` would need a one-line change. The orchestrator can compare with its own `CLAUDE_CONFIG_DIR=~/.claude-b7r claude auth status` before the first launch.
- **The codex read-only sandbox (Seatbelt) inside a launchd job**: stubs cannot test this. The audit or the first real codex launch will show it.
- **Label collisions**: the label carries the task and the UTC time to the second. Two launches of the same task within one second are refused ("a job … is already loaded"), not merged.

## Resume 1

The model in this session is Opus 5.5 (`claude-opus-5-5`). I fixed the four findings of the `[GPT-6-Sol]` security audit (verdict FAIL), as the orchestrator checked them. The fixes are in commit `8fbb632`, pushed to PR #121, with a summary comment on the PR (https://github.com/bal7hazar/grimworld/pull/121#issuecomment-5888582006). No real agent was launched and no real CLI was run.

### Fixes

1. **Major: a recorded label was trusted.**
   - **Launcher:** `task_label` now checks the label before any `launchctl print`, kill or bootout. It must be exactly `$LABEL_PREFIX<task>.<6 digits>`, where the prefix is `grimworld.cv.` or, in test mode, `grimworld.cv.test.`. Anything else prints "`<file>` holds '`<label>`', which is not a label of `<task>` … refused, nothing done to that job; check the file" and returns 1.
   - **Commands:**
     - `stop` and `wait` exit 2.
     - `status` lists the task as `refused` and never reads its job.
     - A launch or resume exits 2, both at an early check (before the account check and before anything is created) and at the `reap` under the launch lock.
     - `running` returns 2 for a refused label.
   - **Task names:** `stop`, `wait`, `model` and `sid` now check the task name too (`check_task`). Outside the tests, a task name may not start with `test.`, so no real label can look like a test label.
   - **Tests** (A1): with the race winner running, I copied its label into the label file of the ended task t5a. Then `stop`, `wait`, a new launch and a resume of t5a each exit 2 with the message, `status` shows t5a as `refused` and the winner as `running`, and after each command the winner's job is still running. A label with the other mode's prefix is refused too.
2. **Note: `Read(//…)`.** The form is unchanged. A comment beside `MAC_DENY` now explains that `//path` is absolute in Claude Code rules and `/path` would be relative to the project. New test: the stub's argv holds exactly `Read(~/.claude-b7r/**)`, `Read(~/.codex/**)`, `Read(~/.config/gh/**)` and `Read(//<home without its leading slash>/.claude-b7r/**)`, plus `.claude`, `.codex` and `.config/gh` in the same form, and no `Read(/x…)` rule with a single slash.
3. **Major: the test cleanup.**
   - **Naming and recording:** test tasks are now named `<run id>-<case>`, so every label of a run starts with `grimworld.cv.test.<run id>-` (`PREFIX`). `record` runs before each launch.
   - **Recovery:** `cleanup` is trapped on EXIT, INT (exit 130) and TERM (exit 143), and runs only once. It recovers labels from the run's own files: the contents of `logs/*.label` and the names of `logs/<label>.plist`. It keeps only labels of the form `PREFIX<alnum>.<6 digits>`.
   - **Stop and verify:** it stops each task through `agent.sh stop`. For each recovered label still loaded, it signals the job's process group (only if the pgid equals the pid), boots out the label, and waits until it is absent. It then checks every label again, and removes the test home only if none is loaded; otherwise it prints `FAIL cleanup: still loaded: …` and keeps the home.
   - **Test:** a job is launched on purpose without `record`, and the cleanup recovers it and boots it out.
4. **Minor: the race.** With `t5b` holding one slot and one slot free, two launchers start concurrently inside the test's foreground command and are both waited for. Checks:
   - the exit codes are exactly `{0, 4}`;
   - the refused launcher has no worktree, no `.label`, no `.log` and no job;
   - the winner runs and both slots are held.

### Verification, run again

```
$ bash -n scripts/mac/agent.sh scripts/mac/test.sh
(no output)
$ shellcheck scripts/mac/agent.sh scripts/mac/test.sh
(no output)
$ time scripts/mac/test.sh
ok   AC-1 account refused ({"loggedIn": true, "email": "bal7hazar@example.com"}): exit 5, no worktree, log, lock or job
ok   AC-1 account refused ({"loggedIn": false, "email": "claude-b7r@proton.me"}): exit 5, no worktree, log, lock or job
ok   AC-1 account refused (loggedIn: true email: claude-b7r@proton.me): exit 5, no worktree, log, lock or job
ok   AC-1 account refused ({"loggedIn": true, "email": "x"} {"loggedIn": true, "email": "claude-b7r@proton.me"}): exit 5, no worktree, log, lock or job
ok   AC-1 no job was created for A1
ok   slots-init: cv-1, cv-2, directory read-only
ok   AC-9 --with-sepolia refused (exit 2)
ok   AC-9 unknown model refused (exit 2)
ok   AC-9 unknown codex model refused (exit 2)
ok   AC-9 load above 10 refuses (thresholds and launch: exit 4, no worktree)
ok   AC-9 memory under 8 GB refuses (exit 4)
ok   thresholds pass with the machine's own values
ok   a HOME that is neither the user's nor a test home is refused
ok   AC-4 dry run: profile rules, Mac deny rules, --settings, --name
ok   AC-4 dry run: never --dangerously-skip-permissions
ok   AC-4 dry run: the foreground rule ends the prompt
ok   AC-4 dry run codex: exec -s read-only, profile audit
ok   AC-4 dry run codex: header [GPT-6-Sol] … (audit)
ok   AC-4 codex with another profile than audit is refused
ok   launch of mIMM5L-T2: exit 0, holds a slot
ok   AC-8 the label is grimworld.cv.test.mIMM5L-T2.<hhmmss>
ok   AC-2 the job's process is alive after the launching shell exited
ok   AC-2 the job's parent is launchd (pid 1)
ok   AC-2 the job runs at nice 10
ok   AC-2 caffeinate asserts on behalf of the job
ok   AC-2 the plist says RunAtLoad true, KeepAlive false, AbandonProcessGroup true
ok   AC-3 the stub's environment is exactly the whitelist (decoys set in the caller)
ok   AC-3 CLAUDE_CONFIG_DIR is the test home's .claude-b7r, TMPDIR the task's
ok   AC-4 the stub's argv: profile rules, Mac deny rules, --settings, --name
ok   AC-4 the stub's argv: the Read denies, exactly, in the ~ and //$HOME forms
ok   AC-4 the stub's argv: no absolute Read rule with a single slash
ok   AC-4 the stub's argv: never --dangerously-skip-permissions
ok   AC-4 the plist: never --dangerously-skip-permissions
ok   AC-7 a new launch refuses while the task's worktree exists with a record
ok   AC-8 wait returns the exit and the model
ok   AC-8 the log has the header, model= and exit=
ok   AC-8 the job is booted out: launchctl print gui/501/grimworld.cv.test.mIMM5L-T2.104051 finds nothing
ok   AC-8 status shows the task stopped, implement, ran=claude-opus-5-5
ok   AC-7 resume without a record is refused
ok   AC-7 resume with another model is refused
ok   AC-7 resume with another profile is refused
ok   AC-7 resume runs claude --continue, keeps the profile implement
ok   AC-7 resume argv: --continue and the implement rules, no --name
ok   AC-7 the resumed run has its own header and exit=
ok   AC-5 two stubs run (a claude, a codex)
ok   AC-5 both slots are held
ok   AC-5 a third launch refuses (exit 4) before any worktree or job
ok   AC-5 when a stub ends its slot is free again, without any cleanup step
ok   AC-5 codex ran -s read-only and its model was read
ok   AC-5 race: exactly one launcher took the free slot (exit 0), the other refused (exit 4) [0, 4]
ok   AC-5 race: the refused launcher created no worktree, no record, no job
ok   AC-5 race: the winner runs, both slots are held
ok   A1 stop of a task whose label file holds another task's label: refused (exit 2), the other job still runs
ok   A1 wait on it: refused at once (exit 2), the other job still runs
ok   A1 status: lists it as refused and leaves the other job running
ok   A1 a new launch of it (whose reap reads the label): refused (exit 2), the other job still runs
ok   A1 a resume of it: refused (exit 2), the other job still runs
ok   A1 a label of the other mode's prefix is refused too (exit 2)
ok   AC-6 a job that never reports: exit 2, stopped by its label, verified
ok   AC-6 its label is gone from launchd and both slots are free
ok   stop: the job is stopped, booted out, verified; its process is gone; its slot free
ok   AC-10 bash -n
ok   AC-10 shellcheck scripts/mac/*.sh
ok   AC-10 /bin/bash 3.2 is refused by the launcher
ok   AC-11 an unrecorded job runs before the cleanup
ok   AC-11 the cleanup verified every label gone (8 labels recovered from the run's files)
ok   AC-11 the unrecorded job was recovered and booted out
ok   AC-11 launchctl list holds no label of grimworld.cv.test.mIMM5L-*
ok   AC-11 the test home is removed
ok   AC-11 no process of the stubs is left
all passed

real	0m28.283s
user	0m7.018s
sys	0m13.215s

$ scripts/mac/agent.sh --dry-run CV-01-dry claude opus new "hello" implement
# [Opus 5.5] CV-01-dry new (implement)
# worktree /Users/bal7hazar/git/grimworld/.claude/worktrees/cli-CV-01-dry  log /Users/bal7hazar/git/grimworld/.claude/worktrees/logs/CV-01-dry.log  launchd job gui/501/grimworld.cv.CV-01-dry.104212  with-assets=0
/Users/bal7hazar/.asdf/installs/nodejs/22.22.2/bin/claude -p $'hello\n\nForeground only: never run a command in the background and never end your turn waiting for one; in headless mode that ends the session. Your turn ends when REPORT.md is written.' --model claude-opus-5-5 --name \[Opus\ 5.5\]\ CV-01-dry --settings \{\"env\":\{\"SCARB_REGISTRY_AUTH_TOKEN\":\"\"\,…\"ATLANTIC_API_KEY\":\"\"\}\} --permission-mode acceptEdits --allowedTools Read Grep Glob … --disallowedTools Bash\(find\ \*\ -delete\*\) … Bash\(launchctl\*\) … Read\(~/.claude-b7r/\*\*\) Read\(~/.codex/\*\*\) Read\(~/.config/gh/\*\*\) Bash\(\*\ ~/.claude-b7r\*\) Bash\(\*\ \$HOME/.claude-b7r\*\) Read\(//Users/bal7hazar/.claude-b7r/\*\*\) Read\(//Users/bal7hazar/.claude/\*\*\) Read\(//Users/bal7hazar/.codex/\*\*\) Read\(//Users/bal7hazar/.config/gh/\*\*\) Bash\(\*\ /Users/bal7hazar/.claude-b7r\*\) Bash\(\*\ /Users/bal7hazar/.claude/\*\) Bash\(\*\ /Users/bal7hazar/orchestrator\*\) --max-turns 400 --output-format text
```
(The dry-run line is trimmed with "…" here; it is otherwise identical to the one in *Commands run*, apart from the label's time.)

Interruption, checked by hand: I started `scripts/mac/test.sh` from `python3` (`subprocess.Popen`) and sent it SIGINT after 8 s, 12 s and 17 s. At 17 s the run had just finished the A1 cases, so the race winner, `t5b` and the ended `t5a` were loaded. Each run exited 130, and afterwards `ls -a scripts/mac/test/` showed only `.gitignore`. The cleanup removes the test home only after verifying that every label is gone, so each interrupted run left no job loaded. I did not run `launchctl list` by hand, because my profile refuses typed `launchctl`.

### Deviations in this resume

- A1 asked for "the reap of a new launch" to refuse. It does, and a new launch or resume is also refused earlier, right after the argument checks and before the account check. So a corrupt label file costs nothing, not even the launch lock.
- Outside the tests, a task name may not start with `test.`. Without this rule, a real task named `test.X` would get a label (`grimworld.cv.test.X.<hhmmss>`) that reads like a test label. No task of the track uses such a name.
- In the tests, the race's two launchers run concurrently with `&` inside `scripts/mac/test.sh` and are both `wait`ed for within the same foreground command. This is the only way to start two launchers at once; nothing outlives the command.

### Escalations and open questions

Unchanged from above. A new audit of `8fbb632` is for the orchestrator to decide.

## Resume 2

The model in this session is Opus 5.5 (`claude-opus-5-5`). This resume fixes the three findings in `scripts/mac/test.sh` from the second pass of `[GPT-6-Sol]` (verdict FAIL), which the orchestrator accepted. The fixes are in commit `7a5b075`, pushed to PR #121, with a comment on the PR (https://github.com/bal7hazar/grimworld/pull/121#issuecomment-5888793246). `scripts/mac/agent.sh` is unchanged; `scripts/mac/test.sh` and `scripts/mac/README.md` changed. No real agent was launched and no real CLI was run.

### Fixes

1. **Major: launchers in flight could bootstrap after the cleanup's scan.**
   - `agent_bg` starts the launcher as `(exec env HOME=<test home> <decoys> scripts/mac/agent.sh …) &`, so `$!` is the launcher's own pid. That pid is recorded in `inflight` until it is waited for. The race now uses `agent_bg`.
   - The cleanup is now `drain`, then removal of the home. `drain` does this, in order:
     1. `stop_inflight`: for each pid in `inflight`, `kill -STOP` (so it cannot start a new command), list its direct children with `pgrep -P <pid>` (by parent pid, never by name), then `kill -TERM` and `kill -CONT`. It then `wait`s for each launcher and waits (up to 30 s each, `pid_gone`) for each child it listed. A `launchctl bootstrap` under way therefore ends before the scan. Children are waited for, not signalled.
     2. `agent.sh stop` for every recorded task.
     3. The label scan from the run's files, with `stop_label` on each label still loaded.
     4. After a pause of 0.5 s, a check that every recovered label is absent and that `launchctl list` holds nothing with the run's prefix. This is a check only: nothing is done to a label not recovered from the run's files.
   - `cleanup` runs once and sets `trap '' INT TERM` at its start, so a second signal cannot cut it short (before, the trap re-entered, returned at once because of `cleaned=1`, and exited).
   - **New test** (A1(2)): with both slots free, two launchers are started with `agent_bg`, and `drain` runs 0.1, 0.3, 0.6, 1.0, 1.5, 2.0, 2.5 and 3.5 s later. The case line shows each launcher's exit status (143 means stopped by the TERM) and how many labels were written. Across the delays that covers:
     - launchers stopped before any label (all four early delays: `143 143`, 0 labels);
     - a launcher stopped after it wrote its label (1.5 and 2.0 s: `143 0`, 1 and 2 labels);
     - both finished with their jobs running (2.5 and 3.5 s: `0 0`, 2 labels).
     
     Each time: `drain` returns 0 with nothing of the run loaded, `inflight` is empty, no process names either task (`pgrep -f`, a read), and both slots are free.
   - **By hand**: I started `scripts/mac/test.sh` from `python3` and sent it SIGINT after 36 s. The last line printed was the 0.6 s case, so the signal landed during the 1.0 s iteration, with two launchers in flight. The run exited 130, and `ls -a scripts/mac/test/` then showed only `.gitignore`. The home is removed only after `drain` has checked that nothing of the run is loaded (the check includes `launchctl list` for the run's prefix).
2. **Minor: `wait_for` with a value computed once.** `stop_label` now waits with `wait_for 5 label_absent "$l"`; `label_absent` runs `launchctl print` on each call. I added a comment above `wait_for`: pass a command, never a value computed by the caller. The other calls re-evaluate on every try: `wait_for 10 test -s <file>`, `wait_for 10 grep -q '^ended' <run file>`, `wait_for 30 pid_gone <pid>` and `wait_for 5 nothing_runs_for <task>`.
3. **Minor: no test for `test.` names.** New dry-run cases (A3):
   - outside test mode (the real home, a dry run, nothing created), `test.<id>-D5` is refused with exit 2 and the message "'test.' starts the labels of the tests only";
   - outside test mode, `<id>-D5` is accepted and would get `grimworld.cv.<id>-D5.<hhmmss>`;
   - in test mode, `test.<id>-D5` is accepted and would get `grimworld.cv.test.test.<id>-D5.<hhmmss>`;
   - in test mode, the run's own names get the prefix `grimworld.cv.test.<id>-`.

Also in `test.sh`: the AC-11 label count now counts unique labels, because the drain runs several times. The README's test section describes the new cleanup order and the new duration.

### Verification, run again

```
$ bash -n scripts/mac/agent.sh scripts/mac/test.sh; echo "bash -n exit $?"
bash -n exit 0
$ shellcheck scripts/mac/agent.sh scripts/mac/test.sh; echo "shellcheck exit $?"
shellcheck exit 0
$ time scripts/mac/test.sh
ok   AC-1 account refused ({"loggedIn": true, "email": "bal7hazar@example.com"}): exit 5, no worktree, log, lock or job
ok   AC-1 account refused ({"loggedIn": false, "email": "claude-b7r@proton.me"}): exit 5, no worktree, log, lock or job
ok   AC-1 account refused (loggedIn: true email: claude-b7r@proton.me): exit 5, no worktree, log, lock or job
ok   AC-1 account refused ({"loggedIn": true, "email": "x"} {"loggedIn": true, "email": "claude-b7r@proton.me"}): exit 5, no worktree, log, lock or job
ok   AC-1 no job was created for A1
ok   slots-init: cv-1, cv-2, directory read-only
ok   AC-9 --with-sepolia refused (exit 2)
ok   AC-9 unknown model refused (exit 2)
ok   AC-9 unknown codex model refused (exit 2)
ok   AC-9 load above 10 refuses (thresholds and launch: exit 4, no worktree)
ok   AC-9 memory under 8 GB refuses (exit 4)
ok   thresholds pass with the machine's own values
ok   a HOME that is neither the user's nor a test home is refused
ok   AC-4 dry run: profile rules, Mac deny rules, --settings, --name
ok   AC-4 dry run: never --dangerously-skip-permissions
ok   AC-4 dry run: the foreground rule ends the prompt
ok   AC-4 dry run codex: exec -s read-only, profile audit
ok   AC-4 dry run codex: header [GPT-6-Sol] … (audit)
ok   AC-4 codex with another profile than audit is refused
ok   A3 outside test mode, a task named test.<…> is refused (exit 2)
ok   A3 outside test mode, an ordinary name is accepted, with a real label grimworld.cv.<task>.<hhmmss>
ok   A3 in test mode, test.<…> is accepted, with a test label grimworld.cv.test.test.<task>.<hhmmss>
ok   A3 in test mode, the run's own names (<id>-<case>) are accepted, with the prefix grimworld.cv.test.JKmJDZ-
ok   launch of JKmJDZ-T2: exit 0, holds a slot
ok   AC-8 the label is grimworld.cv.test.JKmJDZ-T2.<hhmmss>
ok   AC-2 the job's process is alive after the launching shell exited
ok   AC-2 the job's parent is launchd (pid 1)
ok   AC-2 the job runs at nice 10
ok   AC-2 caffeinate asserts on behalf of the job
ok   AC-2 the plist says RunAtLoad true, KeepAlive false, AbandonProcessGroup true
ok   AC-3 the stub's environment is exactly the whitelist (decoys set in the caller)
ok   AC-3 CLAUDE_CONFIG_DIR is the test home's .claude-b7r, TMPDIR the task's
ok   AC-4 the stub's argv: profile rules, Mac deny rules, --settings, --name
ok   AC-4 the stub's argv: the Read denies, exactly, in the ~ and //$HOME forms
ok   AC-4 the stub's argv: no absolute Read rule with a single slash
ok   AC-4 the stub's argv: never --dangerously-skip-permissions
ok   AC-4 the plist: never --dangerously-skip-permissions
ok   AC-7 a new launch refuses while the task's worktree exists with a record
ok   AC-8 wait returns the exit and the model
ok   AC-8 the log has the header, model= and exit=
ok   AC-8 the job is booted out: launchctl print gui/501/grimworld.cv.test.JKmJDZ-T2.105522 finds nothing
ok   AC-8 status shows the task stopped, implement, ran=claude-opus-5-5
ok   AC-7 resume without a record is refused
ok   AC-7 resume with another model is refused
ok   AC-7 resume with another profile is refused
ok   AC-7 resume runs claude --continue, keeps the profile implement
ok   AC-7 resume argv: --continue and the implement rules, no --name
ok   AC-7 the resumed run has its own header and exit=
ok   AC-5 two stubs run (a claude, a codex)
ok   AC-5 both slots are held
ok   AC-5 a third launch refuses (exit 4) before any worktree or job
ok   AC-5 when a stub ends its slot is free again, without any cleanup step
ok   AC-5 codex ran -s read-only and its model was read
ok   AC-5 race: exactly one launcher took the free slot (exit 0), the other refused (exit 4) [0, 4]
ok   AC-5 race: the refused launcher created no worktree, no record, no job
ok   AC-5 race: the winner runs, both slots are held
ok   A1 stop of a task whose label file holds another task's label: refused (exit 2), the other job still runs
ok   A1 wait on it: refused at once (exit 2), the other job still runs
ok   A1 status: lists it as refused and leaves the other job running
ok   A1 a new launch of it (whose reap reads the label): refused (exit 2), the other job still runs
ok   A1 a resume of it: refused (exit 2), the other job still runs
ok   A1 a label of the other mode's prefix is refused too (exit 2)
ok   AC-6 a job that never reports: exit 2, stopped by its label, verified
ok   AC-6 its label is gone from launchd and both slots are free
ok   stop: the job is stopped, booted out, verified; its process is gone; its slot free
ok   A1(2) drain 0.1 s after starting two launchers (launchers exit 143 143; labels written: 0): they are stopped first, nothing of the run is loaded
ok   A1(2) after that drain: no stub of JKmJDZ-I01a or JKmJDZ-I01b runs, both slots are free
ok   A1(2) drain 0.3 s after starting two launchers (launchers exit 143 143; labels written: 0): they are stopped first, nothing of the run is loaded
ok   A1(2) after that drain: no stub of JKmJDZ-I03a or JKmJDZ-I03b runs, both slots are free
ok   A1(2) drain 0.6 s after starting two launchers (launchers exit 143 143; labels written: 0): they are stopped first, nothing of the run is loaded
ok   A1(2) after that drain: no stub of JKmJDZ-I06a or JKmJDZ-I06b runs, both slots are free
ok   A1(2) drain 1.0 s after starting two launchers (launchers exit 143 143; labels written: 0): they are stopped first, nothing of the run is loaded
ok   A1(2) after that drain: no stub of JKmJDZ-I10a or JKmJDZ-I10b runs, both slots are free
ok   A1(2) drain 1.5 s after starting two launchers (launchers exit 143 0; labels written: 1): they are stopped first, nothing of the run is loaded
ok   A1(2) after that drain: no stub of JKmJDZ-I15a or JKmJDZ-I15b runs, both slots are free
ok   A1(2) drain 2.0 s after starting two launchers (launchers exit 143 0; labels written: 2): they are stopped first, nothing of the run is loaded
ok   A1(2) after that drain: no stub of JKmJDZ-I20a or JKmJDZ-I20b runs, both slots are free
ok   A1(2) drain 2.5 s after starting two launchers (launchers exit 0 0; labels written: 2): they are stopped first, nothing of the run is loaded
ok   A1(2) after that drain: no stub of JKmJDZ-I25a or JKmJDZ-I25b runs, both slots are free
ok   A1(2) drain 3.5 s after starting two launchers (launchers exit 0 0; labels written: 2): they are stopped first, nothing of the run is loaded
ok   A1(2) after that drain: no stub of JKmJDZ-I35a or JKmJDZ-I35b runs, both slots are free
ok   AC-10 bash -n
ok   AC-10 shellcheck scripts/mac/*.sh
ok   AC-10 /bin/bash 3.2 is refused by the launcher
ok   AC-11 an unrecorded job runs before the cleanup
ok   AC-11 the cleanup verified every label gone (15 labels recovered from the run's files)
ok   AC-11 the unrecorded job was recovered and booted out
ok   AC-11 launchctl list holds no label of grimworld.cv.test.JKmJDZ-*
ok   AC-11 the test home is removed
ok   AC-11 no process of the stubs is left
all passed

real	0m58.182s
user	0m15.320s
sys	0m29.541s

$ scripts/mac/agent.sh --dry-run CV-01-dry claude opus new "hello" implement
# [Opus 5.5] CV-01-dry new (implement)
# worktree /Users/bal7hazar/git/grimworld/.claude/worktrees/cli-CV-01-dry  log /Users/bal7hazar/git/grimworld/.claude/worktrees/logs/CV-01-dry.log  launchd job gui/501/grimworld.cv.CV-01-dry.105503  with-assets=0
/Users/bal7hazar/.asdf/installs/nodejs/22.22.2/bin/claude -p $'hello\n\nForeground only: never run a command in the background and never end your turn waiting for one; in headless mode that ends the session. Your turn ends when REPORT.md is written.' --model claude-opus-5-5 --name \[Opus\ 5.5\]\ CV-01-dry --settings \{\"env\":\{\"SCARB_REGISTRY_AUTH_TOKEN\":\"\"\,\"STARKNET_NETWORK\":\"\"\,\"STARK…
… Bash\(launchctl\*\) Bash\(\*\ launchctl\*\) Bash\(open\ \*\) Bash\(osascript\*\) Bash\(caffeinate\*\) Bash\(security\ \*\) Bash\(scripts/mac/agent.sh\*\) Bash\(./scripts/mac/agent.sh\*\) Bash\(bash\ scripts/mac/agent.sh\*\) Read\(~/.claude-b7r/\*\*\) Read\(~/.codex/\*\*\) Read\(~/.config/gh/\*\*\) Bash\(\*\ ~/.claude-b7r\*\) Bash\(\*\ \$HOME/.claude-b7r\*\) Read\(//Users/bal7hazar/.claude-b7r/\*\*\) Read\(//Users/bal7hazar/.claude/\*\*\) Read\(//Users/bal7hazar/.codex/\*\*\) Read\(//Users/bal7hazar/.config/gh/\*\*\) Bash\(\*\ /Users/bal7hazar/.claude-b7r\*\) Bash\(\*\ /Users/bal7hazar/.claude/\*\) Bash\(\*\ /Users/bal7hazar/orchestrator\*\) --max-turns 400 --output-format text
```
I printed the dry run in two excerpts of the same command (`cut -c1-400`, then the part from the Mac deny rules to the end); "…" marks the cut. `agent.sh` is unchanged since `8fbb632`, and so is the command, apart from the label's time.

### Deviations in this resume

- Beyond the audit, `cleanup` ignores INT and TERM while it runs. Without that, a second signal re-entered the trap, found `cleaned=1`, and exited before the drain had finished.
- The in-flight test calls `drain` directly, as the audit allowed ("or the cleanup function"), at eight delays. I also sent SIGINT to the whole runner once by hand, during those cases. Neither run left a test home.
- In the drain, a child of a launcher is waited for, never signalled. If an orphaned `launchctl bootstrap` hung for more than 30 s, the scan would run anyway. The final check (recovered labels plus `launchctl list` for the run's prefix) would then report it, and the home would be kept, not removed.
- The test suite now takes 58 s instead of 28 s, because of the eight drain delays.

### Escalations and open questions

Unchanged. A new audit of `7a5b075` is for the orchestrator to decide.

## Resume 3

The model in this session is Opus 5.5 (`claude-opus-5-5`). This is the last fix loop allowed on this lot (OPERATIONS §6), limited to the two findings of `scripts/mac/test.sh` that the orchestrator accepted. The fixes are in commit `d541de0`, pushed to PR #121, with a comment on the PR (https://github.com/bal7hazar/grimworld/pull/121#issuecomment-5888953580). Only `scripts/mac/test.sh` changed (`git diff --stat`: 71 insertions, 16 deletions). No real agent was launched and no real CLI was run.

### Fixes

1. **Major: `stop_inflight` ignored a child that outlived the bound.**
   - The bound is now `KID_BOUND=30`, a variable of the test script. The children listed from the stopped launchers (by parent pid) go into `kids_pending`, a list that persists across drains. `stop_inflight` waits up to `KID_BOUND` for each child; any still alive stays in `kids_pending`, and `stop_inflight` fails.
   - When `stop_inflight` fails, `drain` returns 1 at once and scans no label. `DRAIN_LEFT` then reads " children of stopped launchers still alive after <bound> s: <pids> (labels not scanned)". `cleanup` prints `FAIL cleanup: still loaded: …; the test home <path> is kept` and keeps the home.
   - The labels are scanned only once every listed child has exited. A later drain waits again for any child still pending.
   - **Test** (A1(3)):
     - A stand-in launcher is tracked like a launcher: `track_bg /opt/homebrew/bin/bash -c 'sleep 6 & wait'`, with `KID_BOUND=1`. The drain fails, `DRAIN_LEFT` names the child's pid, `labels` did not grow (no scan), the stand-in is reaped and gone from `inflight`, and the child is still alive.
     - `(cleanup)` in a subshell returns 1, the home still exists, and its stderr says the home is kept and names the child.
     - After the child has exited (`wait_for 10 pid_gone`), with `KID_BOUND=30`, a drain returns 0 and `kids_pending` is empty.
     - The margin is 6 s of sleep against about 2.5 s of drain plus cleanup, both with a 1 s bound.
2. **Major: reaped pids stayed in `inflight`.**
   - `track_bg <command…>` runs `(exec "$@") &` and records `$!`; `agent_bg` now uses it.
   - `reap_bg <pid>` waits for that one pid and removes it from `inflight` at once. The race (`reap_bg "$p1"`, then `reap_bg "$p2"`) and `stop_inflight` (which reaps each launcher in turn) use it.
   - So `inflight` only ever holds unreaped children of the runner, and STOP/TERM reach nothing else. Those are the only background launchers in the test.
   - **Tests** (A2(3)):
     - In the race, the first launcher's pid is gone from `inflight` right after its `reap_bg`, and `inflight` is empty after the second.
     - After each of the eight in-flight drains, `inflight` holds neither of that iteration's two pids.

### Verification, run again

```
$ bash -n scripts/mac/agent.sh scripts/mac/test.sh; echo "bash -n exit $?"; shellcheck scripts/mac/agent.sh scripts/mac/test.sh; echo "shellcheck exit $?"
bash -n exit 0
shellcheck exit 0
$ time scripts/mac/test.sh
ok   AC-1 account refused ({"loggedIn": true, "email": "bal7hazar@example.com"}): exit 5, no worktree, log, lock or job
ok   AC-1 account refused ({"loggedIn": false, "email": "claude-b7r@proton.me"}): exit 5, no worktree, log, lock or job
ok   AC-1 account refused (loggedIn: true email: claude-b7r@proton.me): exit 5, no worktree, log, lock or job
ok   AC-1 account refused ({"loggedIn": true, "email": "x"} {"loggedIn": true, "email": "claude-b7r@proton.me"}): exit 5, no worktree, log, lock or job
ok   AC-1 no job was created for A1
ok   slots-init: cv-1, cv-2, directory read-only
ok   AC-9 --with-sepolia refused (exit 2)
ok   AC-9 unknown model refused (exit 2)
ok   AC-9 unknown codex model refused (exit 2)
ok   AC-9 load above 10 refuses (thresholds and launch: exit 4, no worktree)
ok   AC-9 memory under 8 GB refuses (exit 4)
ok   thresholds pass with the machine's own values
ok   a HOME that is neither the user's nor a test home is refused
ok   AC-4 dry run: profile rules, Mac deny rules, --settings, --name
ok   AC-4 dry run: never --dangerously-skip-permissions
ok   AC-4 dry run: the foreground rule ends the prompt
ok   AC-4 dry run codex: exec -s read-only, profile audit
ok   AC-4 dry run codex: header [GPT-6-Sol] … (audit)
ok   AC-4 codex with another profile than audit is refused
ok   A3 outside test mode, a task named test.<…> is refused (exit 2)
ok   A3 outside test mode, an ordinary name is accepted, with a real label grimworld.cv.<task>.<hhmmss>
ok   A3 in test mode, test.<…> is accepted, with a test label grimworld.cv.test.test.<task>.<hhmmss>
ok   A3 in test mode, the run's own names (<id>-<case>) are accepted, with the prefix grimworld.cv.test.qGcQkR-
ok   launch of qGcQkR-T2: exit 0, holds a slot
ok   AC-8 the label is grimworld.cv.test.qGcQkR-T2.<hhmmss>
ok   AC-2 the job's process is alive after the launching shell exited
ok   AC-2 the job's parent is launchd (pid 1)
ok   AC-2 the job runs at nice 10
ok   AC-2 caffeinate asserts on behalf of the job
ok   AC-2 the plist says RunAtLoad true, KeepAlive false, AbandonProcessGroup true
ok   AC-3 the stub's environment is exactly the whitelist (decoys set in the caller)
ok   AC-3 CLAUDE_CONFIG_DIR is the test home's .claude-b7r, TMPDIR the task's
ok   AC-4 the stub's argv: profile rules, Mac deny rules, --settings, --name
ok   AC-4 the stub's argv: the Read denies, exactly, in the ~ and //$HOME forms
ok   AC-4 the stub's argv: no absolute Read rule with a single slash
ok   AC-4 the stub's argv: never --dangerously-skip-permissions
ok   AC-4 the plist: never --dangerously-skip-permissions
ok   AC-7 a new launch refuses while the task's worktree exists with a record
ok   AC-8 wait returns the exit and the model
ok   AC-8 the log has the header, model= and exit=
ok   AC-8 the job is booted out: launchctl print gui/501/grimworld.cv.test.qGcQkR-T2.110308 finds nothing
ok   AC-8 status shows the task stopped, implement, ran=claude-opus-5-5
ok   AC-7 resume without a record is refused
ok   AC-7 resume with another model is refused
ok   AC-7 resume with another profile is refused
ok   AC-7 resume runs claude --continue, keeps the profile implement
ok   AC-7 resume argv: --continue and the implement rules, no --name
ok   AC-7 the resumed run has its own header and exit=
ok   AC-5 two stubs run (a claude, a codex)
ok   AC-5 both slots are held
ok   AC-5 a third launch refuses (exit 4) before any worktree or job
ok   AC-5 when a stub ends its slot is free again, without any cleanup step
ok   AC-5 codex ran -s read-only and its model was read
ok   A2(3) race: each launcher leaves inflight as soon as it is reaped (first: removed, then 0 left)
ok   AC-5 race: exactly one launcher took the free slot (exit 0), the other refused (exit 4) [0, 4]
ok   AC-5 race: the refused launcher created no worktree, no record, no job
ok   AC-5 race: the winner runs, both slots are held
ok   A1 stop of a task whose label file holds another task's label: refused (exit 2), the other job still runs
ok   A1 wait on it: refused at once (exit 2), the other job still runs
ok   A1 status: lists it as refused and leaves the other job running
ok   A1 a new launch of it (whose reap reads the label): refused (exit 2), the other job still runs
ok   A1 a resume of it: refused (exit 2), the other job still runs
ok   A1 a label of the other mode's prefix is refused too (exit 2)
ok   AC-6 a job that never reports: exit 2, stopped by its label, verified
ok   AC-6 its label is gone from launchd and both slots are free
ok   stop: the job is stopped, booted out, verified; its process is gone; its slot free
ok   A1(2) drain 0.1 s after starting two launchers (launchers exit 143 143; labels written: 0): they are stopped first, nothing of the run is loaded
ok   A2(3) after that drain, inflight holds no reaped pid
ok   A1(2) after that drain: no stub of qGcQkR-I01a or qGcQkR-I01b runs, both slots are free
ok   A1(2) drain 0.3 s after starting two launchers (launchers exit 143 143; labels written: 0): they are stopped first, nothing of the run is loaded
ok   A2(3) after that drain, inflight holds no reaped pid
ok   A1(2) after that drain: no stub of qGcQkR-I03a or qGcQkR-I03b runs, both slots are free
ok   A1(2) drain 0.6 s after starting two launchers (launchers exit 143 143; labels written: 0): they are stopped first, nothing of the run is loaded
ok   A2(3) after that drain, inflight holds no reaped pid
ok   A1(2) after that drain: no stub of qGcQkR-I06a or qGcQkR-I06b runs, both slots are free
ok   A1(2) drain 1.0 s after starting two launchers (launchers exit 143 143; labels written: 0): they are stopped first, nothing of the run is loaded
ok   A2(3) after that drain, inflight holds no reaped pid
ok   A1(2) after that drain: no stub of qGcQkR-I10a or qGcQkR-I10b runs, both slots are free
ok   A1(2) drain 1.5 s after starting two launchers (launchers exit 143 0; labels written: 1): they are stopped first, nothing of the run is loaded
ok   A2(3) after that drain, inflight holds no reaped pid
ok   A1(2) after that drain: no stub of qGcQkR-I15a or qGcQkR-I15b runs, both slots are free
ok   A1(2) drain 2.0 s after starting two launchers (launchers exit 0 0; labels written: 2): they are stopped first, nothing of the run is loaded
ok   A2(3) after that drain, inflight holds no reaped pid
ok   A1(2) after that drain: no stub of qGcQkR-I20a or qGcQkR-I20b runs, both slots are free
ok   A1(2) drain 2.5 s after starting two launchers (launchers exit 0 0; labels written: 2): they are stopped first, nothing of the run is loaded
ok   A2(3) after that drain, inflight holds no reaped pid
ok   A1(2) after that drain: no stub of qGcQkR-I25a or qGcQkR-I25b runs, both slots are free
ok   A1(2) drain 3.5 s after starting two launchers (launchers exit 0 0; labels written: 2): they are stopped first, nothing of the run is loaded
ok   A2(3) after that drain, inflight holds no reaped pid
ok   A1(2) after that drain: no stub of qGcQkR-I35a or qGcQkR-I35b runs, both slots are free
ok   A1(3) a child alive past the bound: the drain fails and names it, scans no label, the stand-in is reaped [ children of stopped launchers still alive after 1 s: 41703 (labels not scanned)]
ok   A1(3) the cleanup then keeps the test home and says so
ok   A1(3) once the child has exited, a drain passes again and nothing is pending
ok   AC-10 bash -n
ok   AC-10 shellcheck scripts/mac/*.sh
ok   AC-10 /bin/bash 3.2 is refused by the launcher
ok   AC-11 an unrecorded job runs before the cleanup
ok   AC-11 the cleanup verified every label gone (15 labels recovered from the run's files)
ok   AC-11 the unrecorded job was recovered and booted out
ok   AC-11 launchctl list holds no label of grimworld.cv.test.qGcQkR-*
ok   AC-11 the test home is removed
ok   AC-11 no process of the stubs is left
all passed

real	1m4.075s
user	0m15.506s
sys	0m29.303s

$ scripts/mac/agent.sh --dry-run CV-01-dry claude opus new "hello" implement
# [Opus 5.5] CV-01-dry new (implement)
# worktree /Users/bal7hazar/git/grimworld/.claude/worktrees/cli-CV-01-dry  log /Users/bal7hazar/git/grimworld/.claude/worktrees/logs/CV-01-dry.log  launchd job gui/501/grimworld.cv.CV-01-dry.110407  with-assets=0
/Users/bal7hazar/.asdf/installs/nodejs/22.22.2/bin/claude -p $'hello\n\nForeground only: never run a command in the background and never end your turn waiting for one; in headless mode that ends the session. Your turn ends when REPORT.md is written.' --model claude-opus-5-5 --name \[Opus\ 5.5\]\ CV-01-dry --settings \{\"env\":\{\"SCARB_REGISTRY_AUTH_TOKEN\":\"\"\,\"STARKNET_NETWORK\":\"\"\,\"STARK…
… Bash\(launchctl\*\) Bash\(\*\ launchctl\*\) Bash\(open\ \*\) Bash\(osascript\*\) Bash\(caffeinate\*\) Bash\(security\ \*\) Bash\(scripts/mac/agent.sh\*\) Bash\(./scripts/mac/agent.sh\*\) Bash\(bash\ scripts/mac/agent.sh\*\) Read\(~/.claude-b7r/\*\*\) Read\(~/.codex/\*\*\) Read\(~/.config/gh/\*\*\) Bash\(\*\ ~/.claude-b7r\*\) Bash\(\*\ \$HOME/.claude-b7r\*\) Read\(//Users/bal7hazar/.claude-b7r/\*\*\) Read\(//Users/bal7hazar/.claude/\*\*\) Read\(//Users/bal7hazar/.codex/\*\*\) Read\(//Users/bal7hazar/.config/gh/\*\*\) Bash\(\*\ /Users/bal7hazar/.claude-b7r\*\) Bash\(\*\ /Users/bal7hazar/.claude/\*\) Bash\(\*\ /Users/bal7hazar/orchestrator\*\) --max-turns 400 --output-format text
```
I printed the dry run in two excerpts of the same command (`cut -c1-400`, then the part from the first Mac deny rule to the end); "…" marks the cut. `agent.sh` is unchanged since `8fbb632`.

### Deviations in this resume

None beyond the two findings. `KID_BOUND` is a variable of `scripts/mac/test.sh` alone (the launcher has no such bound), so shortening it for the test changes nothing outside the tests. The README was not changed: its description of the cleanup order still holds, and the suite now takes 64 s rather than the 59 s it states.

### Escalations and open questions

Unchanged.
