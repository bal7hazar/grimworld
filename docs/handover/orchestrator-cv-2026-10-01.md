# Handover — orchestrator of track CV, 2026-10-01

Written at **15:40 UTC on 2026-10-01**, updated at 15:55 UTC after SPK-13 ended and at 16:10 UTC after SPK-12's fix loop ended, by `[Opus 5.5] Orchestrateur CV (client visuel)`, under the
owner's **soft stop** of 2026-10-01 (through the Overseer and the project manager). The session ran on
Fable 5.1 until about 14:00 UTC, then on Opus 5.5 under the owner's rule for orchestrators. Its context
is not full. The note exists because the owner stopped the day: the successor takes over when the
owner resumes.

## Who you are

| | |
|---|---|
| Role | The orchestrator of **track CV** of project `grimworld`: the client's visual work and the tasks the game lends to the Mac (D-146, D-149). Mandate: [ORCH-client-visual](../briefs/ORCH-client-visual.md) |
| Above | `[Fable 5.1] Chef de projet Grim World`, session `local_3ab2583a-0d2b-469d-872e-cffdf357185d` in Claude Desktop. A message goes up only for a decision or a block. The status is the interface |
| This session | `[Opus 5.5] Orchestrateur CV (client visuel)`, session `local_50f3309e-eeb5-403e-aa14-cd352b4d4e92`, a VPS session. It stays on standby after this note, as the soft stop asks |
| Below | The agents of tasks, all through `nexus` on the Mac (below). No other session |
| Status you own | [docs/status/client-visual.md](../status/client-visual.md), rewritten at each check-in |
| Branches | `cv/` for your own documents; tasks on the branch their brief names |

## State at 16:10 UTC: no agent of the track runs

`nexus progress --project grimworld` for this track:

| Agent | State | Machine, model | Since |
|---|---|---|---|
| `grimworld/impl-spk-13` | **succeeded**, report written (job `job_0mupoddhpf8f302a727`); #252 CI green at `58af26d` | Mac, claude-opus-5-5 | ended 15:40:04 |
| `grimworld/impl-spk-12` | **succeeded** (job `job_0mupm5sha900295fef8`): fix loop 1 of #257, all five findings fixed in `903c38f`, none disputed; #257 CI green at `903c38f` | Mac, claude-opus-5-5 | 15:40:06 → 16:06:39 |
| `grimworld/impl-cli-03c` | succeeded, merged | Mac, claude-opus-5-5 | 15:16:09 |
| `grimworld/impl-cli-03a` | succeeded (the browser check) | Mac, claude-opus-5-5 | 08:34:44 |
| `grimworld/review-spk-12` | succeeded, PASS WITH FINDINGS (four minors, one note) | VPS, claude-sonnet-5-5 | 14:12:14 |
| `grimworld/review-cli-03c` | succeeded, PASS WITH FINDINGS (three notes) | VPS, claude-sonnet-5-5 | 15:17:37 |

**Under the soft stop, these are allowed to end and nothing else is started, resumed or merged.**
SPK-12's queued job was asked before the stop, and the project manager counts it among the agents
allowed to end.

### Open pull requests of the track

| PR | Branch | Head | State |
|---|---|---|---|
| [#252](https://github.com/bal7hazar/grimworld/pull/252) SPK-13 | `spike/spk-13-compiler-determinism` | `58af26d` | **Open, not merged** (soft stop). The agent has ended, its report is written and CI is green. Its review has not been asked |
| [#257](https://github.com/bal7hazar/grimworld/pull/257) SPK-12 | `spike/spk-12-client-proving` | `903c38f` (fix loop 1; `24832b9` was reviewed) | **Open, not merged** (soft stop). Fix loop 1 done, CI green; the review of the new head has not been asked |
| [#272](https://github.com/bal7hazar/grimworld/pull/272) status and CLI-03c's archived reports | `cv/close-cli-03c` | — | **Merged** as `65d1ebd` (documents; armed before the stop) |

## Each open task

### SPK-13 — builds of the same sources that differ (D-154, D-164, D-176, D-180)

- **Brief**: [SPK-13-compiler-determinism](../briefs/SPK-13-compiler-determinism.md).
- **Branch and PR**: `spike/spk-13-compiler-determinism`, #252, head `58af26d`.
- **Cause, found**: the two Sierra programs of one commit differ only in which function of a
  call-graph cycle gets the `withdraw_gas` check.
  - The compiler picks the cycle's representative by the lowest salsa intern id
    (`lowered_scc_representative`).
  - The parallel warm-up assigns those ids in thread order.
  - On `RAYON_NUM_THREADS=1` every build is identical.
  - D-176 takes it: every measured or declared build runs single-threaded.
- **Scarb 2.20.1** (Cairo 2.20.0), D-180: **the drift remains**.
  - Commit `58af26d` holds the agent's run on the Mac.
  - The orchestrator's run on the VPS (x86_64, 8 CPUs), minimal case, 20 clean builds on default
    threads:
    - 2.19.4: the check in `ping` 11 times and `b::pong` 9 times, 20 distinct files.
    - 2.20.1: 12 and 8, 20 distinct files.
    - On 1 thread: 6 of 6 identical on both versions.
- **The VPS cross-check on 2.19.4, done by the orchestrator** (12:26–12:59 UTC, `builds.sh` at
  `97b6494`):
  - `consumer`: 10 builds in each of three series.
  - `contracts`: 5 builds in each of two series.
  - Every class was identical in every build. `HexxGenerators` was 27,092 Sierra felts, CASM 49,375,
    at 4 threads as at 1.
  - The programs of `contracts` differ between builds only by the numbers of their ids.
  - So the single-thread value is 27,092, the committed snapshot. CI's 27,101 is what D-176's pin
    removes.
- **Where the VPS tables are**, on the VPS:
  `/home/claude/projects/grimworld/.claude/worktrees/cv-spk-13-vps/spikes/SPK-13/.work/out-vps/`
  - `builds.txt`: the table, to commit as `spikes/SPK-13/builds-vps.txt`.
  - `minimal-vps.txt`: the minimal case on both versions.
  - `builds-run.log`.
  - That worktree was created by this orchestrator (detached at the branch). Remove it with
    `git worktree remove --force` once the tables are in #252.
- **The issue draft** (`spikes/SPK-13/issue-draft.md`): its placeholders are filled (`3ec437d`).
  **It is not filed.** It waits for the owner's go (D-154 §3, D-180). It names both versions tested.
- **The agent's report** (`nexus report grimworld/impl-spk-13`, ended 15:40:04), two facts beyond the above:
  - **The game's contracts are not affected today**: 23 builds of `contracts/` gave one program per
    artefact (10 classes, 33 test classes, 2 Sierra programs, 6 compiled test files), and CI matches
    the Mac's class sizes.
  - **D-164's premise of "one value per environment" does not hold**: the Mac gave both values of
    `HexxGenerators` and a **third** (27,101 Sierra / 49,427 CASM felts) from one binary and one cache;
    the library's own record shows CI giving both. The single-thread pin (D-176) is the remedy, not a
    record of two values. Tell the project manager with the report.
  - On 2.20.1 on the Mac, 12 builds put the check 6 times in `ping` and 6 in `pong`, 12 distinct
    files; on 1 thread identical. The draft names both versions and stays for the owner.
- **To close it**:
  1. Read the report whole (`nexus report grimworld/impl-spk-13`) and archive it in `docs/reports/`.
  2. Commit the VPS tables to #252, as the orchestrator, after the agent's last push.
  3. `nexus review` (it falls back to Claude Sonnet while Codex has no quota). No audit (D-177: the
     measurements and the pin carry it).
  4. Merge on a clean review and green checks.
  5. Archive the report and the review in `docs/reports/`.
- **To resume** (after the soft stop is lifted): `nexus continue grimworld/impl-spk-13 "<what to do>"`.

### SPK-12 — client-side proving against L2 batches (D-161, D-172)

- **Brief**: [SPK-12-client-proving](../briefs/SPK-12-client-proving.md).
- **Branch and PR**: `spike/spk-12-client-proving`, #257, head `903c38f` after fix loop 1. CI green.
- **Report**: read, not yet archived (`nexus report grimworld/impl-spk-12`).
- **Result**:
  - **Keep the L2 batches.** A mixed design (proofs for heavy segments) comes only after a SNIP-36
    virtual transaction has been proved on a phone.
  - A proved segment costs about 79.5 M L2 gas, $0.070. Almost all of it is the protocol's flat 75 M.
  - For S1, proofs cost $0.44 / **$0.95** / $1.82 against **$0.58** batched.
  - Fight-heavy: $0.95 proved against $9.54–$12.14 batched.
  - The tick was proved on the Mac, two runs, verified, byte-identical: a worst tick in 23–26 s,
    3.7 GiB; a floor of about 14 s and 3.6 GiB.
  - On a phone the prover as built does not fit (E).
  - No SNIP-36 prover answers today.
- **Six questions for the owner** (Q1–Q6, note §7). One touches design/02: may the instance state on
  chain be a hash?
- **Review** (Claude Sonnet 5.5, PASS WITH FINDINGS): four minors and one note, all in the note's
  arithmetic and presentation, none changing the recommendation.
  - They were sent to the implementer at 14:12 as fix loop 1. It ran 15:40:06–16:06:39 and fixed all five in `903c38f`: the break-even is now **39** ticks a segment (37 was a lower bound), the phone floor 19–42 s, the slope 11–14 s per million steps, the fight-heavy battery **12–32 %** against SPK-6's 8 %; the recommendation unchanged.
  - The findings: the pointer to a never-committed `REPORT.md` (name
    `docs/reports/SPK-12-client-proving.md`, state the D-64 → D-111 deviation in the note); the
    37-tick break-even including Fate and gate transactions; the phone-time formula; the slope
    11–14 s per million steps; the fight-heavy battery total of about 12–30 %.
- **To close it**:
  1. Ask a **new** review on `903c38f` (fix loop 1 is done).
  2. Merge on a clean review.
  3. Archive the report and the reviews.
  4. Send the project manager the result for the owner's decision on ADR-0001 (D-161 §3).
- **Trap**: SPK-12 is `--class heavy`. It takes the Mac's whole offer, so nothing else runs beside it.
- **To resume**: `nexus continue grimworld/impl-spk-12 "<what to do>"`.

### CLI-03c — hubs and transitions on fixed data (D-178)

- **Done**: merged as #270 (`8b4e3a4`). Brief [CLI-03c-hubs](../briefs/CLI-03c-hubs.md).
- **The ID**: D-178 and PLAN said CLI-03b. That ID is the merged sandbox-path lot #163, so the task
  ran as CLI-03c. The project manager was told, so check that PLAN's row reads CLI-03c.
- **The owner tests it**: `pnpm --filter @grimworld/app dev`, `/?hub=town`, `/?hub=outpost`,
  `&entry=0`.
  - Buildings from the atlas need `tools/art/build.py` in the Mac's checkout with the pack.
- **Follow-up, after the owner's test** (a new lot, CLI-03d proposed):
  1. The owner's choices on the **five points** design/11 *Hubs* marks "proposed, the owner's eye":
     - the outpost's services (Guild, Trainer, Vault, Gate);
     - the entry moment (1.2 s, Skip);
     - the closing report's content;
     - adventurers standing still as decor;
     - where the buildings stand.
  2. **The arrival rule** (project manager, 2026-10-01): the client offers to leave only when the
     adventurer steps onto a gate tile after having left it, or through the Gate button, **never on
     arrival**. Arriving on the return gate's anchor is the design (D-148). **No seed change.** It
     becomes one line of design/11 if the owner agrees.
  3. The review's notes (`docs/reports/CLI-03c-review-sonnet.md`, in #272), none blocking:
     - the one-line regex of the imports test;
     - no test that the strips' atlas output is unchanged by the stills;
     - the arrival case, which item 2 rewrites.
  4. The agent's open question: commit `client/app/verify-cli03c.mjs` with `playwright-core` as a
     named development dependency, or keep it local. It stays untracked on the Mac's worktree.

### ART-02 and IDX-01b

Both are merged (#134, #154), and their questions from the pause remain:

- **ART-02's Linux fingerprint**: the atlas's pixel fingerprint was never compared on Linux. It needs
  the pack, which the VPS has at `~/projects/assets` but no grimworld worktree has as a submodule.
  - A VPS agent (or the orchestrator) builds `tools/art` there and compares it with the Mac's.
  - Since CLI-03c the manifest also has eight stills, so the fingerprint changes.
- **IDX-01b**:
  - [PENDING-cv-market-queries](../decisions/PENDING-cv-market-queries.md) waits for the project
    manager: the category of a balance is not in the market key, and the unit of a lot's expiry.
  - The `indexer-node` CI trigger paths, narrower than the job's dependencies (both audits of
    IDX-01a), wait for the project manager.

## Decisions

Taken in this context (all recorded in the status or a merged document):

| Decision | What would reverse it |
|---|---|
| D-178's task runs as **CLI-03c**, the ID CLI-03b being taken | — |
| CLI-03c's allowlist includes `tools/art/**` (in the mandate) for the stills | — |
| SPK-12's and SPK-13's planned audits dropped under D-177; the review is their gate | The owner asking to see either |
| CLI-03c merged on a clean review before the owner's test; the design lines stay "proposed" | The project manager agreed |
| SPK-12's review findings fixed rather than deferred | — |

Pending, with this orchestrator's recommendation:

| For | Question | Recommendation |
|---|---|---|
| The owner | SPK-13's issue draft: file it upstream? | Yes: the drift remains on 2.20.1, the minimal case is small and names nothing of ours |
| The owner | SPK-12's Q1–Q6 and ADR-0001 | The note's own: keep L2 batches; a phone SNIP-36 spike before any mixed design |
| The owner | CLI-03c's five proposed points and the arrival rule | The owner's eye; then CLI-03d |
| The project manager | `verify-cli03c.mjs` as a committed dev script? | Yes, as a named dev dependency: each visual lot needs one, and three runs have rewritten it |

## What waits for the owner

- Lifting the soft stop.
- Testing CLI-03c; the five points.
- The go on SPK-13's issue.
- SPK-12's six questions (after its merge).
- [2026-10-02-cv-integer-scale](../decisions/2026-10-02-cv-integer-scale.md), the sandbox's scale, still
  open since the pause.

## Next, in order, when the owner resumes

1. Check-in: `nexus progress --project grimworld`, `nexus resources`, `nexus accounts`, `gh pr list`.
2. SPK-13: archive its report, the VPS tables into #252, review, merge; the two facts above to the project manager.
3. SPK-12: a new review on `903c38f`, merge, archive, the result to the project manager.
4. CLI-03d after the owner's test of CLI-03c.
5. ART-02's Linux fingerprint.
6. CLI-02 when lent (after ENG-02), and the Capacitor shell before Phase 6.

## Rules of the day to carry

- **Audits are the exception (D-177)**: only for value, access control, randomness, a published
  interface, a cost or determinism only a measurement proves, a large refactoring, or a lot the owner
  asks to see. Each pull request says why an audit was asked or that none was needed.
- **While Codex has no quota** (D-175): reviews on Claude Sonnet, audits on Claude Opus 5.5. Nexus
  applies it by itself: `nexus review` prints `on claude sonnet: Codex has no usable account`.
- **Orchestrators run on Opus 5.5**. Only the project managers and the Overseer stay on Fable.
- **Agents install the toolchain versions they need themselves** (OPERATIONS, #269).
- **Every repository migrates to Scarb 2.20.1 with the single-thread pin** (D-176, D-180). For the
  game it is FND-11 (the game's orchestrator). Nothing of it is track CV's beyond SPK-13.

## Traps learnt in this context

- **The Mac's classes.**
  - The Mac offers 8 CPU and 45 GB since the owner raised it on 2026-10-01.
  - `--class heavy` asks 8 CPU, so it takes the whole offer: a heavy job and any other job never run
    together. Before the raise, a heavy job never fit, and Nexus showed the misleading wait
    `no_provider` (nexus #36, #39).
  - Use `--class build` unless proving or a workspace build needs heavy, so that `--class browser`
    jobs run beside it.
- **Nexus's job limit**: a job is interrupted at **4 hours** of wall clock (`limit: wall clock limit
  reached`).
  - SPK-13 lost one turn that way, with no report.
  - Brief long spikes to commit and report early, and resume with "finish and report first".
- **Pending messages**: `nexus continue` on a running agent queues an inbox item. Every pending item
  is delivered **together, as one prompt, in order** when the job ends (`composeBatch` in Nexus's
  `core.ts`).
  - To correct a queued instruction, queue a correction that says it overrides the previous item.
  - `nexus stop` on a *queued* job withdraws the inbox. `nexus retire` is the owner's.
- **`nexus wait` can end with `fetch failed`** when the control plane blinks. The agent is fine:
  re-arm the wait.
- **`gh pr checks <n> --watch` can return before every check has started.** Merge only when a count
  of not-passed checks is 0 after the checks exist, and re-arm otherwise.
- **The art pack (D-73)**: nothing of the pack leaves the Mac. That covers an image, an atlas, and a
  screenshot showing the art, in a commit, a PR, an issue or a comment.
  - Agents' Playwright screenshots stay in their worktree's untracked `.verify-out/`.
  - An agent's worktree has no `assets` submodule, so the atlas paths are tested on synthetic images
    only.
- **Playwright on the Mac**: no Playwright is in the workspace. Agents add `playwright-core` for the
  run and revert it.
  - Their profile refuses compound commands, `ls` outside the worktree, `lsof`, `sysctl`, and
    `gh api -X PATCH`. `gh pr edit` fails on GitHub's Projects (classic) deprecation.
- **`scripts/gas_budgets.py` needs `flock`**, which macOS lacks. Cairo spikes on the Mac report their
  gas from snforge's output.
