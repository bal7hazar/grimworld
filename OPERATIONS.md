# Operating procedures

Binding for every session and agent working on Grim World. [CONTEXT.md](CONTEXT.md) says
*what* we build and why, [PLAN.md](PLAN.md) *in which order*; this file says *how*.

Conventions are those of the owner's other programmes (provable-physics stack), adapted to
a single repository. What differs is said explicitly.

## 1. Roles and the chain of command

```
owner (bal7hazar)
  └─ orchestrator session (this, Claude Desktop, Fable/Opus)    owns the plan, briefs, reviews, merges, status
       └─ sub-agents: claude CLI, Opus 5.5 / Sonnet 5; codex CLI for audits only
```

- The **owner** decides on vision, scope, design decisions (`D-xx`), releases and
  deployments to public networks. Speaks French.
- The **orchestrator** owns the repository: `PLAN.md`, `STATUS.md`, briefs, worktrees,
  reviews, merges, the decision log. It **never implements anything large itself**. It
  prepares the owner's decisions and records the answers.
- A **sub-agent** owns one task, one worktree, one branch, one pull request, one
  `REPORT.md`. It never merges and never touches a shared file: it escalates in its report
  instead. A sub-agent that meets an ambiguity in the design stops and reports it; it does
  not invent a rule.
- **Separation of duties.** The agent that wrote something never audits it. Auditors
  receive the deliverable and the specification, not the implementer's reasoning.

If the project later splits into several repositories (contracts, client, content), each
gets its own orchestrator session and this session becomes the project manager, as in the
owner's other programmes.

## 2. Model and account policy

| level | runs on | models |
|---|---|---|
| orchestrator | Claude Desktop session | Fable 5.1 or Opus 5.5 |
| sub-agents (execution) | `claude -p …` launched by the orchestrator through the launcher (§4) | **Opus 5.5** for design, game logic, numerics, debugging; **Sonnet 5** for mechanical, well-framed tasks (seed data, bindings, scaffolding); **Fable 5.1 only marginally**, for a genuinely hard problem, and the brief says why |
| audits, second opinions **only** | `codex exec …` | `gpt-5.5` / `gpt-5.6-sol`; **never for implementation**. Small quota: spend it on security and determinism audits of merged lots and on cross-checks of design decisions |

- **Never use the in-session Agent tool for implementation work**: it burns the session's
  own quota. Short read-only research through the Agent tool is fine.
- Model ids for the CLI: `--model claude-opus-5-5`, `--model sonnet`,
  `--model claude-fable-5-1`.
- The `claude` CLI must be logged in as **claude-b7r** on whichever machine runs the
  agents, so that sub-agents do not spend the session's quota: check with
  `claude auth status` before the first launch, and stop if it shows another account.

### Task titles carry the model (owner's rule)

Every background task, monitor or agent launch is described with **the model actually
used as a prefix, in square brackets**:

```
[Opus 5.5] ENG-05 room generator
[Sonnet 5] CNT-01 seed data
[gpt-5.6-sol] Audit ENG-07 security
[Fable 5.1] Wait until ENG-05's CI is green        (a task not tied to an agent carries the session's model)
```

The same prefix is used in launcher log lines, in the header of `REPORT.md` and in the
audit verdicts listed in the pull request, so that any result can be traced to the model
that produced it. The tag is never omitted and never guessed.

## 3. The machine: what every launch must respect

Ideation happened on the owner's Mac. **Implementation runs on the VPS**, from a new
project-manager session (account bal7hazar) bootstrapped with
[docs/briefs/PM-vps-bootstrap.md](docs/briefs/PM-vps-bootstrap.md). Task FND-03 ports the
launcher and the build locks of the owner's other programmes. The rules:

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
domains (persistent / ephemeral), the glossary.

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
| Cost budgets | `docs/BUDGETS.md` (from Phase 0) | A lot exceeding a budget does not merge without an owner decision |

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
| **Cost** | Does it fit the budget? | Worst case per entrypoint (8 awake goblins, longest queue); storage writes per action; packing |
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

## 10. The orchestrator's check-in loop

At every check-in (owner's request or scheduled wake-up), without spending more than a few
minutes of context:

1. `git fetch -q && git log --oneline origin/main -5`, `gh pr list`, `gh issue list`: what
   moved.
2. Running agents and machine load.
3. Rewrite `STATUS.md` (dated); update `docs/decisions/PENDING-*`.
4. Decide what to launch next within the concurrency budget.
5. Report to the owner **in French**: what moved, what is blocked, what they must decide.

Owner decisions are **batched**: the orchestrator asks in chat when a decision blocks a
wave, and records the answer in `docs/decisions/` and in the documents concerned.

## 11. Language

Chat with the owner in French; every document, brief, commit and pull request in English.
