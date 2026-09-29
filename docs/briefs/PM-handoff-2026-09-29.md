# PM-handoff — 2026-09-29, 09:40 UTC

From the project-manager session `[Fable 5.1 → Opus 5.5] Chef de projet Grim World`
(local_2bdc85ae), whose context was full, to its successor. Everything the programme knows is
in the repositories; this file says where to look and what is in flight.

## Read first, in this order

1. [PROGRAMME.md](../../PROGRAMME.md): the three tracks, the decisions of the last two days,
   what waits for the owner, the risks.
2. [CONTEXT.md](../../CONTEXT.md) §6: the decision log (D-01 to D-145), each row pointing
   at its file in [docs/decisions/](../decisions/).
3. [OPERATIONS.md](../../OPERATIONS.md): roles (§1), models (§2), the machine and the budget
   (§3), audits (§6), merges and **publications** (§7), how the project manager decides (§10).
4. [docs/CAIRO.md](../CAIRO.md), **§7 and §8**: the owner's rule on the organisation of
   Cairo code (D-143), the newest and the one the owner watches most.
5. [PLAN.md](../../PLAN.md), then [docs/architecture/cost-budget.md](../architecture/cost-budget.md).

The session's memory (loaded automatically in this repository) holds the lessons that are
not in the documents.

## The owner's rules on how the project manager works

| | |
|---|---|
| Language | Chat in French; documents, briefs, commits, pull requests in English |
| Decide (D-128) | Follow your own recommendation, write it in `docs/decisions/` and CONTEXT §6, report afterwards with the reason and what would reverse it. Do not ask first |
| Still the owner's | Mainnet, store submissions, deleting a repository, money, accounts and secrets |
| Publications (D-132) | Yours to decide in the owner's name, after running the checklist of OPERATIONS §7 **yourself**, in a clean clone: CI completed and green on the commit, audits closed, **no source changed after the last audited commit**, changelog and version, `scarb package` sha256 equal to the request, name free, no test dependency as a regular one; then read the registry and consume the version from a fresh project. Two precedents: [quiver_quest](../decisions/2026-09-29-publish-quiver_quest-0.1.0.md), [quiver_achievement](../decisions/2026-09-29-publish-quiver_achievement-0.1.0.md) |
| **Code review by the owner** | Until the owner has nothing left to say, **show the owner the next iterations of code on the pattern of D-143**: ARC-06's reference model first, then the first lots of ARC-07 and ENG-R1, with the paths of the files to read. After that, check the organisation lens yourself |
| Merges of your own pull requests | Yours (OPERATIONS §1). Branches `pm/<topic>`; `gh pr merge <number> --squash` only after `gh pr checks <number>` shows every check completed and passed; never a bare `gh pr merge` |
| Titles | Every session, task and report carries the model that actually ran, verified |
| Orchestrators | Created as session suggestions (a chip) that the owner starts; talk to them with `send_message` to their session id; `STATUS.md` of a track belongs to its orchestrator, `PROGRAMME.md` to you |

## Sessions

| Session | Id | Model | Repository |
|---|---|---|---|
| `[Opus 5.5] Orchestrateur Grim World (jeu)` | local_06f24ad6-10d6-46c3-8277-f68f4019e3e7 | Opus 5.5 | `bal7hazar/grimworld` |
| `[Opus 5.5] Orchestrateur hexmap (lib)` | local_2e7bf177-2551-4b59-9f0e-cae0e5103d34 | Opus 5.5 (Fable until 2026-09-29) | `bal7hazar/hexx-cairo` |
| `[Opus 5.5] Orchestrateur quiver (packages)` | local_a86e4778-208c-4719-ae35-861b3b6b1f6f | Opus 5.5 | `bal7hazar/quiver` |
| Other programmes of the owner | "Angry Birds Cairo orchestration" (their project manager), rapier, nalgebra | — | Not yours: relay the owner's instructions only |

## In flight at 09:40 UTC

| Track | What | Next for you |
|---|---|---|
| quiver | **ARC-06** (#19): the pattern of D-143 on one model, its audits running | When the orchestrator sends the path of the reference model: **show it to the owner** (French summary + file paths), record the owner's verdict, then let ARC-07 (both packages as 0.2.0) start |
| Game | ENG-02a, ENG-03, ENG-04 done; ENG-06's brief in review (#115); ENG-01b done | Answer the orchestrator's escalations under D-128; ENG-R1 waits for the owner's review of ARC-06 |
| Map library | LIB-05, M1-T1b (#34), the take-over's equality tests | Nothing; the first release candidate of `hexx` 0.1.0 will be a publication request (its orchestrator will first ask the owner to confirm D-132 in its own session) |

Budget: 3 Grim World agents across the three tracks (caps game 2, library 1, quiver 1; the
game first through `~/orchestrator/waiting/game`), held by slot locks of the launcher
(reference `5d14d89`, frozen: changes only for a finding that lets an agent over-launch,
publish, spend or read a secret). The owner allowed **nalgebra up to 5 agents** during its
transition (2026-09-29); relayed to it and to its programme's project manager.

## Quota

On 2026-09-29 at 09:40 UTC the app's account was at **87 % of its weekly quota for all models
(Fable 99 %)**, reset **2026-09-30 14:00 UTC**. The orchestrators were told to save the
sessions' quota (one background wait per agent, short messages, no in-session research, no
Fable sub-agent). Do the same: check `get_usage` at your first check-in; keep your own turns
short.

## Watch

| | |
|---|---|
| Cost of an expedition (R-2) | $0.556 estimated in the worst case against $0.50; decided on ENG-07's measure of a tick inside a batch; levers listed in [the ENG-01 decision](../decisions/2026-09-29-eng-01-escalations.md) |
| Fix loops | The rule of three loops is applied by you: a fourth loop limited to named findings, or a merge with the findings carried; not a merge with a known major in anything that will be published |
| Secrets | `~/.claude/settings.json` (mode 600) holds the registry token and the Sepolia account (test network only, controls nothing on mainnet, owner's confirmation); the launchers empty them in agents; residual accepted |
| Shared machine | Delete and kill only what you created, by exact path and pid (OPERATIONS §3) |
