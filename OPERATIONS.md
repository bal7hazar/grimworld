# Operating procedures

Binding for every session and agent working on Grim World. [CONTEXT.md](CONTEXT.md) says
*what* we build and why, [PLAN.md](PLAN.md) *in which order*; this file says *how*.

Conventions are those of the owner's other programmes (provable-physics stack), adapted to
a single repository. What differs is said explicitly.

## 1. Roles and the chain of command

```
owner (bal7hazar)
  └─ project-manager session (Claude App, Fable/Opus)       owns the plan, status, decisions, arbitration
       └─ orchestrator session(s) (Claude App, Opus or Fable, by the project manager's judgement)
            │                                               own briefs, worktrees, reviews, merges
            ├─ sub-agents: claude CLI (Opus 5.5 / Sonnet 5 / Fable 5.1, by difficulty)   execution
            └─ auditors:   codex CLI (gpt-5.6-sol, astra, …, by kind of task)            audits, when needed
```

- The **owner** decides on vision, scope, design decisions (`D-xx`), releases and
  mainnet. Speaks French.
- The **project manager** owns `PLAN.md`, `STATUS.md`, `CONTEXT.md` and the decision log.
  It **creates the orchestrator sessions** in the Claude App and chooses their model
  (Opus or Fable) according to the difficulty of what they will orchestrate. It gives
  them their objectives, answers their questions, arbitrates, prepares the owner's
  decisions and records the answers. It never implements and never merges.
- An **orchestrator** answers to the project manager. It turns objectives into briefs,
  launches and resumes sub-agents, reviews their reports and pull requests, orders audits,
  merges. It **never implements anything large itself**.
- A **sub-agent** owns one task, one worktree, one branch, one pull request, one
  `REPORT.md`. It never merges and never touches a shared file: it escalates in its report
  instead. A sub-agent that meets an ambiguity in the design stops and reports it; it does
  not invent a rule.
- **Separation of duties.** The agent that wrote something never audits it. Auditors
  receive the deliverable and the specification, not the implementer's reasoning.

One orchestrator is enough to start. The project manager opens others when tracks run in
parallel with separate write sets (contracts, client, content), one per track.

### Project manager and orchestrators

| | |
|---|---|
| Creating an orchestrator | The project manager opens a session in the Claude App on the repository, with a first message that names the track, the objectives, the documents to read and the model policy |
| Talking to it | Cross-session messages: first line = the subject; body = the path of a file in the repository and the decision or result expected. Anything longer than a few lines is a committed file, not a message |
| Hearing from it | The repository is the interface: merged pull requests, `STATUS.md`, archived reports. A message back only when a decision is needed |
| Silence is not agreement | The project manager checks the repository at its next check-in |
| Titles | Session titles and every background task carry the model in brackets |

## 2. Model and account policy

| level | runs on | models |
|---|---|---|
| project manager | Claude App session | Fable 5.1 or Opus 5.5 |
| orchestrator | Claude App session, created by the project manager | **Opus 5.5 or Fable 5.1**, chosen by the project manager |
| sub-agents (execution) | `claude -p …` launched by an orchestrator through the launcher (§4) | **Sonnet 5** for mechanical, well-framed tasks (seed data, bindings, scaffolding); **Opus 5.5** for design, game logic, algorithms, debugging; **Fable 5.1** for the hardest problems. The brief states the model and, for Fable, why |
| audits and second opinions | `codex exec …`, **when needed** | `gpt-6-astra`, `gpt-6-sol`, `gpt-6-luna`, chosen **by the kind of task** (table below); **never for implementation** |

### Models, as verified

Verified on 2026-09-28 on the owner's Mac, from the CLIs themselves (`codex-cli` 0.156.1,
its model list fetched that day; `claude` 2.1.281). **To verify again on the VPS before
the first launch**: a model list belongs to an account and a date.

| CLI | Model id | Described by the CLI as | Reasoning levels |
|---|---|---|---|
| codex | `gpt-6-astra` | Frontier intelligence for the most demanding work | low … ultra |
| codex | `gpt-6-sol` | Workhorse model for coding and everyday work | low … ultra |
| codex | `gpt-6-luna` | Fast and affordable model for easier tasks | low … max |
| codex | `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna` | Older models | — |
| codex | `gpt-5.5` | Legacy | low … xhigh |
| claude | `fable`, `opus`, `sonnet` (aliases), or a full name | — | — |

| Kind of audit | Model | Reasoning |
|---|---|---|
| Security of what holds or moves value; randomness; access control | `gpt-6-astra` | high or xhigh |
| Determinism and parity; cost of an algorithm; a contested design decision | `gpt-6-astra` | high |
| Routine review of a merged lot; code quality | `gpt-6-sol` | medium or high |
| Content validation, consistency of documents | `gpt-6-luna` | medium |

Launch form: `codex exec -m <model> -c model_reasoning_effort=<level> -s read-only "<prompt pointing at the brief>"`.
An auditor never needs to write in the repository: its report is its answer, saved by the
launcher.

Title prefixes use the display name: `[GPT-6-Astra]`, `[GPT-6-Sol]`, `[GPT-6-Luna]`.

When an audit by codex is needed:

| Always | When the orchestrator judges it useful | Not needed |
|---|---|---|
| Anything that holds or moves value: trade, auction house, inventory settlement | A contested design or numeric decision | Documentation |
| Randomness and its providers | An algorithm whose gas figure looks too good or too bad | Seed data, once validated by the content suite |
| Access control and ownership | A lot that went through three fix loops | Interface work |
| Chunk reveal and the simulation window (determinism, cost) | | |

- **Never use the in-session Agent tool for implementation work**: it burns the session's
  own quota. Short read-only research through the Agent tool is fine.
- Model ids for the `claude` CLI: `--model claude-opus-5-5`, `--model sonnet`,
  `--model claude-fable-5-1`, or the aliases `opus`, `sonnet`, `fable`.
- The `claude` CLI must be logged in as **claude-b7r** on whichever machine runs the
  agents, so that sub-agents do not spend the session's quota: check with
  `claude auth status` before the first launch, and stop if it shows another account.
  On 2026-09-28 the CLI of the owner's Mac was logged in as **bal7hazar**, not claude-b7r:
  no sub-agent is to be launched from that machine until this is changed.

### Task titles carry the model (owner's rule)

Every background task, monitor or agent launch is described with **the model actually
used as a prefix, in square brackets**:

```
[Opus 5.5] ENG-05 room generator
[Sonnet 5] CNT-01 seed data
[GPT-6-Astra] Audit ENG-07 security
[Fable 5.1] Wait until ENG-05's CI is green        (a task not tied to an agent carries the session's model)
```

The same prefix is used in launcher log lines, in the header of `REPORT.md` and in the
audit verdicts listed in the pull request, so that any result can be traced to the model
that produced it. The tag is never omitted and never guessed.

## 3. The machine: what every launch must respect

Ideation happened on the owner's Mac. **Implementation runs on the VPS**: a new
project-manager session (account bal7hazar) is bootstrapped with
[docs/briefs/PM-vps-bootstrap.md](docs/briefs/PM-vps-bootstrap.md) and creates the first
orchestrator. Task FND-03 ports the launcher and the build locks of the owner's other
programmes. The rules:

- **Agents do not run as children of the session.** A restart of the desktop app must not
  kill them (transient systemd user units on Linux; an equivalent detached launch on
  macOS).
- **Foreground only.** A headless agent dies when its turn ends with a background command:
  every launch prompt says "foreground only; your turn ends when `REPORT.md` is written".
  Sonnet needs it repeated in the prompt itself; expect to resume a Sonnet agent once.
- **Never relaunch from scratch** an interrupted agent (out of memory, 529, rate limit, end
  of turn): resume it with its context (`claude --continue -p "<follow-up>"` in the same
  worktree, or `codex exec resume <session-id>`); uncommitted work is in the worktree.
- **Local checks are package-scoped; the pull-request CI is the full gate.** Agents run
  the tests of what they touched, push early and fix from CI. They never run the whole
  workspace locally.
- **Concurrency budget**: set by FND-03 from the machine's memory and CPU. Until measured:
  2 agents at a time.
- **Heavy builds are serialised** through a lock, following the per-project model of the
  owner's other programmes (one fast build per project, one heavy build shared).

## 4. Launching, monitoring and closing a sub-agent

The contract, identical to the owner's other repositories: a **committed brief** in
`docs/briefs/`, a **fresh worktree** on a branch cut from `origin/main`, a **log file**, a
**`REPORT.md`** at the worktree root, a **pull request opened by the agent with CI green**,
never merged by the agent.

| step | how |
|---|---|
| brief | `docs/briefs/<ID>-<slug>.md`, with `docs/briefs/COMMON.md` for the rules shared by all briefs |
| worktree | `git worktree add .claude/worktrees/cli-<task> -b <branch> origin/main` |
| launch | `scripts/agent.sh <task> <claude\|codex> <model> new "<one-line prompt pointing at the brief>"` |
| status | `scripts/agent.sh status`; log `.claude/worktrees/logs/<task>.log` |
| wait | `scripts/agent.sh wait <task>`, as a background command titled with the model |
| resume | `scripts/agent.sh <task> <claude\|codex> <model> resume "<follow-up>"` |
| close | read `REPORT.md` and the log; review the pull request (scope = allowlist, deviations, cost table); run the required audits (§6); `gh pr merge --squash` (no `--delete-branch`); archive the report in `docs/reports/`; `git worktree remove --force`; delete the branch; update `PLAN.md`, `STATUS.md` and the changelog on `main` |

`scripts/agent.sh` does not exist yet: it is task FND-03, ported from the owner's
`glam-cairo` launcher.

A launch with `--dangerously-skip-permissions` is not used. Profiles grant an explicit
tool allowlist (`--permission-mode acceptEdits --allowedTools …`): `research` (read,
search, web, write a report), `implement` (plus build and test commands, git, `gh pr`),
`audit` (read-only plus write a report).

### Brief template

```markdown
# <TASK-ID> — <title>

## Agent
Title: `[<Model>] <TASK-ID> <short description>` · Profile: research | implement | audit

## Goal
One paragraph: what exists after this task that did not exist before.

## Context
- Design references: docs/design/<file>#<section>
- ADRs: …
- Depends on: <TASK-IDs already merged>

## Scope
- In: …
- Out: … (name the tempting adjacent work that is not part of this task)
- Allowlist: the files and folders this task may write. Anything else is an escalation.

## Interfaces
Models, entrypoints, events or components this task creates or changes, with signatures.

## Acceptance criteria
- [ ] AC-1 … (observable and testable)

## Verification
Exact commands to run and what they must show.

## Report
`REPORT.md`: summary, files changed, commands run with their real output, cost table,
deviations from the brief, escalations, open questions.
```

`COMMON.md` carries what every brief inherits: foreground only, package-scoped checks,
conventional commits, the multiplayer constraints M-1…M-6, the determinism rules, the two
domains (persistent / ephemeral), the glossary, and for every Cairo task the engineering
rules of [docs/CAIRO.md](docs/CAIRO.md).

## 5. Sources of truth

| Subject | Source of truth | If the code disagrees |
|---|---|---|
| Game rules | `docs/design/*` | The code is wrong, or a design change is proposed first |
| Technical decisions | `docs/architecture/ADR-*` | Same |
| Decisions and their history | `docs/decisions/` (one file per decision; `PENDING-*.md` for the owner's open questions), indexed in `CONTEXT.md` | — |
| Scope, order | `PLAN.md` | — |
| Live state | `STATUS.md`, dated, rewritten at every check-in | — |
| Research | `docs/research/` | — |
| Numbers (balance) | Registries' seed data | Design docs give initial values; seed data wins once it exists |
| Cairo engineering rules | [docs/CAIRO.md](docs/CAIRO.md) | The code is wrong |
| Cost budgets | `docs/BUDGETS.md` (from Phase 0), fed by the gas figures of the tests | A lot exceeding a budget does not merge without an owner decision |

**Design changes are made in the document first**, in the same pull request as the code
that needs them.

## 6. Audits

### Required lenses per task type

| Task type | Design | Security | Determinism & parity | Cost | Quality | Content |
|---|---|---|---|---|---|---|
| Contract: system / model | ● | ● | ● | ● | ● | |
| Contract: registry / seed data | ● | | | | ● | ● |
| Client: simulation (mirrors chain logic) | ● | | ● | | ● | |
| Client: interface | ● | | | | ● | |
| Tooling / CI | | ● | | | ● | |
| Documentation / design | ● | | | | | |

### Lenses

| Lens | Question | Key checks |
|---|---|---|
| **Design conformance** | Does it implement the documented rules, all of them and only them? | Every rule maps to code and to a test; no undocumented behaviour; M-1…M-6; two domains |
| **Security** | Can a player gain something the rules do not allow? | Access control; ownership; state machine cannot be skipped (act in a hub, loot twice, act in a closed instance); overflow; randomness cannot be predicted, replayed or re-rolled; registry permissions |
| **Determinism & parity** | Do chain and client compute the same result? | No block data inside an instance; fixed iteration and tie-break orders; shared vectors pass on both sides |
| **Cost** | Does it fit the budget, and is it as cheap as it can be? | Gas of every test against its budget; worst case per entrypoint (8 awake goblins, longest queue); storage writes per action; packing; the order of preference of `docs/CAIRO.md` (arithmetic, then bitwise, then loops); no `u256` without a written reason |
| **Code quality** | Would the next agent understand and extend it? | Repository patterns; no dead code; meaningful tests; glossary names |
| **Content validation** | Is the data playable? | Gates reachable; tables non-empty; ranges consistent; recipes ≤ pairs per signature; ids never reused |

### Who audits

| Audit | Executor |
|---|---|
| Design, quality, content, cost | `claude` CLI, a different agent from the implementer, fresh context |
| **Security, determinism** | `claude` CLI **and**, for lots that touch value or randomness, `codex` CLI as an independent second opinion on another vendor's model |
| Phase gate, pre-mainnet | Both, on the whole phase; plus an **external audit** before mainnet |

### Severity

| Severity | Meaning | Blocks the merge |
|---|---|---|
| `blocker` | Exploit, loss of state, rule broken, build broken | Yes |
| `major` | Wrong behaviour in a reachable case; acceptance criterion without a test | Yes |
| `minor` | Quality, clarity, non-critical cost | Yes, unless deferred by the orchestrator with a PLAN entry |
| `note` | Observation | No |

A finding needs **evidence**: a failing scenario, a test, or a quoted rule. The
orchestrator verifies a finding before sending it to a fix; auditors can be wrong. The fix
is done by **resuming the implementer**, not by a new agent. After three fix loops on the
same lot, escalate to the owner.

### Audit report template

```markdown
# [<Model>] Audit — <TASK-ID> — <lens>

## Verdict
PASS | PASS WITH FINDINGS | FAIL

## Findings
| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |

## Coverage
What was reviewed, what was not, and why.
```

## 7. Merge, release and quality rules

- Merge only on **green CI** plus the orchestrator's review of `REPORT.md` and the
  required audits without open `blocker` or `major`. Squash merge, by the orchestrator.
- Conventional commits; trailer `Co-Authored-By: Claude <model> <noreply@anthropic.com>`.
- Branch name `<type>/<task-id>-<slug>`. One pull request per task. A pull request that
  cannot be reviewed in one sitting is split at the brief stage.
- **Game results are API.** A change that alters the outcome of any action for the same
  state and input moves the shared test vectors; it is announced in the changelog and the
  client simulation is updated in the same lot.
- **Deployments**: the orchestrator deploys to **Sepolia autonomously**, with the
  credentials found in the session's settings environment; they are never printed, copied
  into a file or passed to a sub-agent's brief. Every release goes to Sepolia first.
  Mainnet deployments and mainnet registry writes: an explicit go from the owner each time
  is recommended and awaits confirmation (Q-17).
- CI stays under ~10 minutes: split test packages before they grow.
- Never: force-push on shared branches; commit secrets or keys; skip hooks; commit
  anything from `assets/` or derived from it (D-73).
- Tasks run in parallel only if their **allowlists do not overlap**. Interfaces shared by
  parallel tasks are frozen first in a dedicated task.

## 8. Phase gates

A phase closes when: all its tasks are merged; its exit criterion (PLAN) is
**demonstrated, not asserted**; a cross-cutting audit (security and design lenses) has run
on the whole phase; documents are reconciled; the owner has signed off.

## 9. Definition of done

- [ ] Acceptance criteria met, each covered by a test.
- [ ] CI green.
- [ ] Required audits: no open `blocker` or `major`; deferred `minor` have a PLAN entry.
- [ ] Documents updated in the same pull request.
- [ ] `REPORT.md` archived; `PLAN.md` and `STATUS.md` updated.

## 10. The check-in loop (project manager and orchestrators)

At every check-in (owner's request or scheduled wake-up), without spending more than a few
minutes of context:

1. `git fetch -q && git log --oneline origin/main -5`, `gh pr list`, `gh issue list`: what
   moved.
2. Running agents and machine load.
3. Rewrite `STATUS.md` (dated); update `docs/decisions/PENDING-*`.
4. Decide what to launch next within the concurrency budget.
5. Orchestrators report to the project manager through the repository; the project manager
   reports to the owner **in French**: what moved, what is blocked, what they must decide.

Owner decisions are **batched**: the project manager asks in chat when a decision blocks a
wave, and records the answer in `docs/decisions/` and in the documents concerned.

## 11. Language

Chat with the owner in French; every document, brief, commit and pull request in English.
