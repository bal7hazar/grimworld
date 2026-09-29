<!-- Archived by the orchestrator of track CV, 2026-09-29. Four passes of the same codex session
(gpt-6-sol, reasoning high, read-only), each on the commit of #121 named in its text. The
orchestrator's decisions: pass 1, finding 2 (`Read(//…)`) not accepted, since `//path` is the
absolute-path form of Claude Code's permission rules, and withdrawn by the auditor in pass 2; every
other finding accepted and fixed by resuming the implementer (three fix loops). Final verdict: PASS,
#121 merged. -->

# [GPT-6-Sol] Audit — CV-01 — security

## Verdict

FAIL

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| 1 | major | [agent.sh](../../scripts/mac/agent.sh:177) | A recorded label is trusted without checking that it belongs to the named task. | If `logs/A.label` is accidentally copied from `logs/B.label`, `stop A` signals B’s process group and boots out B’s job (lines 490–503). `reap` can also boot out the label read from the wrong file (lines 185–190). | Validate the label’s prefix and embedded task name before any `print`, kill, or bootout; refuse a mismatch. |
| 2 | minor | [agent.sh](../../scripts/mac/agent.sh:162) | The four absolute-path `Read` deny rules contain an extra slash. | The read-only dry run produced `Read(//Users/bal7hazar/.claude-b7r/**)`, while the intended path begins `/Users/`. The tests check the tilde rule, not these absolute rules. Whether Claude normalizes the double slash was not verified. | Remove the added `/` before `$HOME` and assert the resulting rules in the stub’s argv. |
| 3 | major | [test.sh](../../scripts/mac/test.sh:59) | Test cleanup can lose track of a detached job when a launch is interrupted. | The test records a task and label only **after** the launcher returns (for example, lines 178–180). If interrupted after `launchctl bootstrap` but before `record`, the cleanup arrays are empty; cleanup then removes the test home while the job can remain loaded. AC-11 checks only normal completion. | Record the task before launching, recover exact labels from this run’s files during cleanup, trap interruption signals, and verify bootout before removing the home. |
| 4 | minor | [test.sh](../../scripts/mac/test.sh:244) | The budget test does not exercise the launch race. | AC-5 launches two stubs sequentially and then attempts a third. It never starts two launchers concurrently for the last free slot. The code appears to hold the launch lock through `slots-acquired`, but the test does not demonstrate that case. | Add a concurrent stub test that starts two launchers with one slot free and confirms only one acquires it. |

## Coverage

Reviewed the three requested files against the CV-01 brief, `OPERATIONS.md` §§2–4 and 7, the ORCH mandate on `origin/main`, the VPS launcher, and all three profiles. `bash -n` and `shellcheck` passed. A permitted dry run confirmed the malformed `Read` rules. The local `lockf(1)` manual confirms its descriptor form uses `flock(2)`.

Static review found that the launchd command begins with `/usr/bin/env -i`, the Claude account check precedes launcher-created files and locks, arguments are passed as arrays into XML-escaped plist strings, and the slot lock spans the agent command. The test-home check resolves symlinks to a physical path. I found no path for a calling-session secret variable or `--dangerously-skip-permissions` to reach an agent through the constructed job. I did not run `scripts/mac/test.sh`, start an agent, or verify live launchd behavior, as instructed.

# [GPT-6-Sol] Audit — CV-01 — security (second pass)

## Verdict

FAIL

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| 1 | major | [test.sh](../../scripts/mac/test.sh:89) | Cleanup can still finish while a background launcher is creating a job. | The race test starts two launchers in the background (lines 315–318). If the runner receives SIGINT or SIGTERM while waiting, its trap can scan and verify labels before either launcher writes its label or plist. A launcher can then bootstrap after that scan. `cleaned=1` prevents a second cleanup pass. The new unrecorded-job test covers a job **already running** before cleanup, not this in-flight case. | Stop and wait for the exact in-flight launcher PIDs before the final label scan; then recover, stop, and verify their jobs. Add an interruption test while both launchers are in flight. |
| 2 | minor | [test.sh](../../scripts/mac/test.sh:86) | The cleanup wait checks a cached job state. | `"$(job_state "$l")"` is evaluated once before `wait_for` starts, so its retries cannot observe a later bootout. The final scan may still succeed, but this wait does not do what its comment says. | Have `wait_for` call a function that queries `job_state` on each retry. |
| 3 | minor | [test.sh](../../scripts/mac/test.sh:173) | The new production `test.` task-name refusal lacks an automated test. | [agent.sh](../../scripts/mac/agent.sh:182) implements it, and my read-only `--dry-run test.CV01 …` returned exit 2. The suite tests neither that production refusal nor test-mode acceptance. | Add dry-run assertions for both modes. |

## Coverage

The copied-label finding is fixed and tested: `task_label` validates the mode prefix, task name, and six-digit suffix before stop, wait, status, launch, or resume acts on the label. The concurrent-launch test now starts two launchers for one free slot and checks exits `{0, 4}`. I withdraw my earlier `Read(//…)` finding in light of the orchestrator’s permission-rule clarification; the new test checks the exact arguments.

I reviewed commit `8fbb632`, “Resume 1” in `REPORT.md`, and the changed launcher, tests, and README. `bash -n`, `shellcheck`, and `git diff --check` passed. I did not run `scripts/mac/test.sh` or launch a job. The implementer’s reported passing test run and three SIGINT checks do not cover interruption while the concurrent launchers are still in flight.

# [GPT-6-Sol] Audit — CV-01 — security (third pass)

## Verdict

FAIL

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| 1 | major | [test.sh](../../scripts/mac/test.sh:81) | Cleanup still does not prove that an in-flight child has finished before removing the test home. | `stop_inflight` ignores a failed `wait_for 30 pid_gone "$c"` (line 90) and clears `inflight`. `drain` then checks only labels currently visible (lines 137–141). If a delayed `launchctl bootstrap` child is still alive at 30 seconds, it can load a job after that check. The reported timed tests do not exercise the timeout. | Treat any child timeout as a drain failure and keep the home. Confirm the launcher has stopped before enumerating its children, then scan labels only after every child that could bootstrap has exited. |
| 2 | major | [test.sh](../../scripts/mac/test.sh:381) | An interrupted race can signal a PID that is no longer the test’s launcher. | After waiting for the first launcher, its PID remains in `inflight` until the second wait finishes. If a signal interrupts that second wait and the first PID has been reused, `stop_inflight` sends STOP and TERM to the reused PID (lines 83–86). No deliberate action by that process is needed. | Remove each PID from `inflight` as soon as it is reaped. Signal only PIDs that remain unreaped children of the test runner. |

## Coverage

The other two accepted findings are fixed and tested: `label_absent` queries launchd on every retry, and the new dry-run cases cover the production `test.` refusal and test-mode acceptance. The eight-delay drain test and reported SIGINT run exercise ordinary in-flight cleanup, but do not cover a child exceeding 30 seconds or interruption after the first race launcher has been reaped. Ignoring a second INT or TERM during cleanup addresses the previously identified re-entry path.

I reviewed the `7a5b075` diff, the “Resume 2” report, and the changed test and README. `bash -n`, `shellcheck`, and `git diff --check` passed. I did not run `scripts/mac/test.sh` or launch anything.

# [GPT-6-Sol] Audit — CV-01 — security (fourth pass)

## Verdict

PASS

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| — | — | — | No open finding within this pass’s scope. | — | — |

## Coverage

Both accepted findings are fixed and tested. A child still alive after the 30-second bound remains pending; `drain` fails before scanning labels, and cleanup keeps the test home. The stand-in child test covers that timeout and a later successful drain. `reap_bg` removes each launcher PID from `inflight` when it is reaped; the race and eight drain cases check the resulting list.

I reviewed commit `d541de0`, “Resume 3” in `REPORT.md`, and the changed test harness. I found no new blocker in the diff. `bash -n`, `shellcheck`, and `git diff --check` passed. The harness run is evidenced by the implementer’s reported output; I did not rerun it or launch anything.