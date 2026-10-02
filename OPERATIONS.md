# Operating procedures

What is specific to Grim World, **added to the standard roles of Nexus** (the owner's transition
of 2026-09-30, D-162). The standard holds the rest: the rules everyone inherits, the acts reserved
for the owner, the rules of a session in Claude Desktop (titles, messages, deciding, check-ins,
handover), and the roles of the Overseer, of the project manager, of the orchestrators and of the
agents of tasks. This file never restates it; where it would contradict it, the standard wins.

[CONTEXT.md](CONTEXT.md) says *what* we build and why, [PLAN.md](PLAN.md) *in which order*; this
file says *how, here*.

## 1. The project in the organisation

```
owner
  └─ Overseer
       └─ project manager of grimworld                 PLAN, PROGRAMME, CONTEXT, the decision log
            ├─ orchestrator of the game                bal7hazar/grimworld: contracts, client, content
            ├─ orchestrator of the map library (LIB)   bal7hazar/hexx-cairo
            ├─ orchestrator of quiver (ARC)            bal7hazar/quiver
            └─ orchestrator of the client visual (CV)  bal7hazar/grimworld, on the owner's Mac
                 └─ agents of tasks: implementers, auditors, reviewers
```

| | |
|---|---|
| Documents the project manager owns | `PLAN.md`, `PROGRAMME.md`, `CONTEXT.md` (§6, the decision log), `docs/decisions/`, the orchestrators' mandates `docs/briefs/ORCH-*.md` |
| The live state of a track | Its `STATUS.md` (the game: `STATUS.md`; track CV: `docs/status/client-visual.md`; the library and `quiver`: their own `STATUS.md`), dated, rewritten by its orchestrator at every check-in; nobody else writes it |
| Decisions | `D-nn`, one file each in `docs/decisions/`, a row in CONTEXT §6. The owner decides vision, scope, design and releases; the project manager decides the rest by its own recommendation (D-128) and the owner reverses. `PENDING-*.md` holds a question for the owner or the project manager |
| Cross-track needs | Through the project manager, never sideways: the game writes `docs/needs/hexmap.md` and `docs/needs/arcade.md`; a track answers by releases and a changelog |
| The owner's other programmes | Not this project's: relay the owner's instructions only |

An orchestrator never implements anything large itself. A sub-agent owns one task, one worktree,
one branch, one pull request, one `REPORT.md`; it never merges and never touches a shared file: it
escalates in its report. An agent that meets an ambiguity in the design stops and reports it; it
does not invent a rule. **Separation of duties**: the agent that wrote something never audits or
reviews it; auditors receive the deliverable and the specification, not the implementer's
reasoning.

## 2. Models by kind of task

| Kind of task | Model | Notes |
|---|---|---|
| Mechanical, well-framed implementation (seed data, bindings, scaffolding, tables) | **Sonnet 5.5** | The project's default implementer in Nexus |
| Design, game logic, algorithms, debugging, contracts | **Opus 5.5** | |
| The hardest problems | **Fable 5.1** | The brief says why |
| Security of what holds or moves value; randomness; access control | `[GPT-6-Astra]`, high or xhigh | Codex, always |
| Determinism and parity; cost of an algorithm; a contested design decision | `[GPT-6-Astra]`, high | Codex |
| Routine review of a lot; code quality; the organisation lens (CAIRO.md §8); the launcher | `[GPT-6-Sol]`, medium or high | Codex |
| Content validation; consistency of documents | `[GPT-6-Luna]`, medium | Codex |
| Design conformance | Opus 5.5 | `claude`, fresh context, a different agent from the implementer |
| The review of every pull request before its merge | Codex, the project's reviewer; **Claude Sonnet while Codex has no quota** (D-175) | `nexus review` (§6) |
| Any audit while Codex has no quota | **Claude Opus 5.5** (D-175): nobody waits for Codex; Nexus falls back by itself (R2) | `nexus audit` |

The project's registry in Nexus (`projects/grimworld.json` of `bal7hazar/nexus`) names the provider
and the model of each role and lens; this table agrees with it, and the registry is changed first
when the table must change. **Every orchestrator session runs on Opus 5.5** (owner, 2026-10-01: only
the project managers and the Overseer stay on Fable 5.1, to save Fable's quota); a chip proposing
an orchestrator says Opus 5.5 in its title.

Model ids for the `claude` CLI: `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-fable-5-1` (or the
aliases `opus`, `sonnet`, `fable`). An agent already running keeps the model it started on until its
task closes; the model that ran is read from the log or from `nexus status`, never assumed.

## 3. The machines and the budgets

Implementation runs on the VPS (8 vCPU, 31 GB, shared with the owner's other projects) and, for what
needs a browser or the Mac, on the owner's Mac (12 cores, 64 GB). Nexus reads both
(`nexus resources`, `nexus accounts`).

| | VPS | Mac |
|---|---|---|
| Grim World agents at a time, audits and reviews included | **3** (D-118), whichever launcher started them | **5** (owner, 2026-09-29) |
| Caps per track, inside the total | game 2, map library 1, `quiver` 1: the caps add to 4, **the game comes first** through `~/orchestrator/waiting/game` (touched by the game orchestrator while it has launches ready and fewer than 2 running; the other tracks launch nothing while it is under 30 minutes old) | track CV and the tasks lent to it (D-149) |
| Load thresholds before a launch | no new agent while the 5-minute load is above 12 (1.5 × the cores) or available memory is under 8 GB | the same at 18 and 8 GB |
| Heavy builds | one at a time: `scripts/lock.sh` takes `/tmp/grimworld-build.lock` then the machine-wide `~/orchestrator/heavy-build.lock`; `scarb` and `snforge` on PATH are the machine's shims, which take the latter by themselves | Nexus's `--class heavy`, one per machine |
| Accounts | agents on **claude-b7r** (`claude auth status` before a launcher's first launch); Nexus chooses the account of what it starts | the app's configuration stays the owner's; agents on `~/.claude-b7r` (`CLAUDE_CONFIG_DIR`) |

**Toolchain versions are the agents' to install** (owner, 2026-10-01): a task that needs a Scarb,
starknet-foundry or other version installs it with `asdf install`, user-local, without moving the
machine's default (`.tool-versions` selects per repository), and says so in its report; nobody asks
the owner. New Scarb and starknet-foundry releases are watched (the Overseer's watch, D-180) and each
lands as a migration task per repository, with its budgets and snapshots re-measured.

**Pins are generated and checked on Linux only** (project manager, 2026-10-02, after SPK-13's review in
#252): every committed pin of a hash, of class bytes or of a size (gas snapshots, class sizes, class
hashes, checksums) is generated and checked on Linux, the VPS or CI, never on the Mac. A build
single-threaded (D-176) gave `grimworld_persistent_Registry` the same CASM but a different Sierra text
and class hash on the Mac and on the VPS, each machine stable. The Mac still runs the tests. A
difference between the Mac and Linux is reported with both figures and is not treated as a regression.
The rule is reversed when track CV finds the cause of the cross-machine difference and it is fixed
upstream or in our builds. The programme Slingfall holds the same rule, so both read their pins alike.

A running agent is never stopped for load. The budget was measured by FND-03 (memory does not bind;
CPU and the shared heavy lock do) and is measured again when the contracts' test build passes 6 GB
or when a phase runs client and contract agents together. Nexus and the project's launcher do not
count each other's agents: before any launch, read `nexus resources` and `scripts/agent.sh slots`.

## 4. Starting the agents of a task

**Which launcher.** Until this file names `nexus` for a track, the implementers of the VPS tracks
(game, LIB, ARC) are started by the project's launcher, `scripts/agent.sh` (copied in the library
and in `quiver`, synced from the commit the CHANGELOG marks as "launcher reference"). **Reviews,
audits and every agent of track CV go through `nexus`** (`nexus review`, `nexus audit`,
`nexus run --require browser`; skill `nexus-agents`). Never the same task by both.

The contract is the standard's: a committed brief in `docs/briefs/<ID>-<slug>.md` with
[docs/briefs/COMMON.md](docs/briefs/COMMON.md) for the rules every brief inherits, a fresh worktree on
a branch cut from `origin/main`, a log, a `REPORT.md` at the worktree root, a pull request opened by
the agent with its checks green, never merged by the agent, resumed and never relaunched. Task ids and
briefs follow the [brief template](docs/briefs/COMMON.md) (agent title with its model, goal, context,
scope with its **allowlist**, interfaces, acceptance criteria, verification, report).

**The launcher** (`scripts/agent.sh`, ported from the owner's `glam-cairo` launcher by FND-03):

| step | how |
|---|---|
| launch | `scripts/agent.sh [--with-assets] [--branch <branch>] <task> <claude\|codex> <model> new "Read docs/briefs/<ID>-<slug>.md and docs/briefs/COMMON.md, then execute the task." <profile>` |
| status, slots | `scripts/agent.sh status`, `scripts/agent.sh slots`; log `.claude/worktrees/logs/<task>.log`, each run ending with `exit=<status>` |
| wait | `scripts/agent.sh wait <task>`, a background command titled with the agent's model, one per agent |
| resume | `scripts/agent.sh <task> claude <model> resume "<follow-up>"`; codex: `… resume "<follow-up>" audit "$(scripts/agent.sh sid <task>)"` |
| close | read `REPORT.md` and the log; review the pull request; the audits of §6 and the Codex review; merge (§7); archive the report in `docs/reports/`; `git worktree remove --force`; delete the branch; update `PLAN.md`, `STATUS.md`, the changelog |

- Each `claude` agent is a transient systemd user unit `grimworld-<task>-<hhmmss>` outside the
  session's cgroup, its description carrying the model tag; **without a systemd user manager nothing
  is launched**. If a launch fails with "no systemd user manager" while the manager runs, the
  session's bus lost it: `export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus` at the top
  of the launch queue. `codex` auditors are detached with `setsid` inside the app's cgroup (their
  sandbox needs an unprivileged user namespace the kernel refuses to user units); an app restart kills
  a running audit, which is then resumed.
- **Foreground only**: a headless agent dies when its turn ends with a background command; every
  prompt says so (Sonnet needs it repeated; expect to resume a Sonnet agent once).
- **Local checks are package-scoped; the pull-request CI is the full gate.** Agents never run the
  whole workspace locally.
- The budget is held **as slots**: files in `~/orchestrator/slots/` (`total-1`…`total-3`, `game-1`,
  `game-2`, `lib-1`, `quiver-1`), locked by the agent's own shell (`flock`), freed by the kernel when it
  ends; the directory is read-only and `scripts/agent.sh slots-init` creates missing slot files once on
  a new machine. A launch waits until the agent holds its slots, under `~/orchestrator/agent-launch.lock`.
- `--with-assets` initialises the `assets` submodule in the task's worktree; by default it is not.
- **Profiles**, committed in `scripts/profiles/<profile>.txt`, passed as `--permission-mode acceptEdits
  --allowedTools … --disallowedTools …`; `--dangerously-skip-permissions` is never used. They are
  guard-rails against mistakes, not a sandbox: an interpreter or a project script an agent runs can do
  what the user can. What holds whatever an agent runs: no secret in the agent's environment (the
  launcher empties the Sepolia account and the registry token unless §7 grants them), the CI checks,
  the protection of `main` when it comes (D-121: not for now).

  | Profile | Grants | For |
  |---|---|---|
  | `research` | Read, search, the web, read-only shell, `gh pr view`; writes in the worktree | Spikes that only read and report |
  | `audit` | `research`, plus builds and tests through `scripts/lock.sh` | Auditors that reproduce a finding or a figure |
  | `implement` | `audit`, plus the toolchain (`scarb`, `snforge`, `pnpm`, `asdf install`), `scripts/`, `tools/`, `spikes/`, Rust builds with the installed toolchains, `sncast` against the local node only, `starknet-devnet`, `git`, `git push -u origin HEAD`, `gh pr create`. Denied as commands: rebase, `--no-verify`, `gh pr merge`, `git submodule`, `git add assets`, the stash, `git config`, global toolchain changes, deletion outside the worktree, the launcher, `claude`, `codex`, `systemd-run`, `scarb publish` | Implementation tasks |

  Codex runs only with `audit`, in its `read-only` sandbox; its report is saved in
  `.claude/worktrees/logs/<task>.last.md`.

- **The launcher is frozen** (project manager, 2026-09-29) until the gate of Phase 0 (FND-07): it
  changes only for a finding that lets an agent over-launch, publish, spend or read a secret, or a task
  that cannot run without it. Its scope: it guards against **accidental** over-launch and fails closed;
  it does not guard against a deliberate act of the same Unix user (a finding that needs one is a note).
  Every audit of the launcher is briefed with this scope; its passing `[GPT-6-Sol]` audit marks the
  commit "launcher reference" in the CHANGELOG.
- **Residuals accepted by the owner**: the agents run as the same Unix user, so its credential files
  (`gh`, `codex`, `claude`, the Scarb registry token in `~/.claude/settings.json`, mode 600) are
  readable by code an agent runs; test networks only and nothing of value in the MVP keep it small.

## 5. Sources of truth

| Subject | Source of truth | If the code disagrees |
|---|---|---|
| Game rules | `docs/design/*` | The code is wrong, or a design change is proposed first |
| Technical decisions | `docs/architecture/ADR-*` | Same |
| Decisions and their history | `docs/decisions/`, indexed in `CONTEXT.md` §6 | — |
| Scope, order | `PLAN.md` | — |
| Live state of a track | Its `STATUS.md` | — |
| State of the programme | `PROGRAMME.md` | — |
| Research | `docs/research/` | — |
| Numbers (balance) | Registries' seed data | Design docs give initial values; seed data wins once it exists |
| Cairo engineering rules, the organisation of Cairo code (D-143) | [docs/CAIRO.md](docs/CAIRO.md) | The code is wrong |
| Cost budgets | [docs/architecture/cost-budget.md](docs/architecture/cost-budget.md), `docs/BUDGETS.md` from the gas figures of the tests; the expedition's running estimate in `STATUS.md` (D-158) | A lot exceeding a budget does not merge without a decision (D-144: the orchestrator up to +10 %, the project manager beyond or on the expedition's path) |

**Design changes are made in the document first**, in the same pull request as the code that needs
them. **Game results are API**: a change that alters the outcome of any action for the same state
and input moves the shared test vectors, is announced in the changelog, and the client simulation is
updated in the same lot.

## 6. The review, and the few audits

**The routine gate of a lot is its review**: the checks of the pull request, green, and `nexus
review` (Codex; Claude Sonnet while Codex has no quota, D-175), read by the one who merges. **An
audit is the exception** (owner, 2026-10-01, D-177): it is run when a large feature or a large
refactoring lands, or when the tests alone do not give the confidence needed, and only for the kinds
of tasks below. Every pull request says in one line why an audit was asked, or that none was needed.

| Kind of task | Audit required | Lens and model |
|---|---|---|
| Anything that holds or moves value: trade, auction house, inventory settlement, the funder, a payment | Yes | Security, `[GPT-6-Astra]` (Opus 5.5 while Codex has no quota) |
| Access control, ownership, upgrades, the administrator's writes | Yes | Security, `[GPT-6-Astra]` |
| Randomness and its providers; chunk reveal and the simulation window | Yes | Security and determinism, `[GPT-6-Astra]` |
| A published interface: a package version on scarbs.xyz, a change of a frozen interface after a deployment, an event the indexer reads | Yes, once before the publication or the deployment | The organisation lens (CAIRO.md §8) and cost, `[GPT-6-Sol]` and `[GPT-6-Astra]` |
| A cost or a determinism that only a measurement proves: a lot on the expedition's path whose budget rests on a measured worst case, the parity of the client's mirror | Yes, when the tests do not carry the measurement | Cost or determinism, `[GPT-6-Astra]` |
| A large refactoring (ENG-R1's lots, a package rewritten) | Yes, one | The organisation lens, `[GPT-6-Sol]`; the owner reads the lot when they asked to |
| A lot the owner asked to see | As the owner says | |
| Everything else: a rule as pure code with its tests, seed data validated by the content suite, documentation, tooling, a spike, a fix loop, a lot the design covers by tests | **No** | The review |

A phase gate is audited on the whole phase (security and design lenses, both providers); an
external audit precedes mainnet. The lenses keep their questions (design conformance: the documented
rules, all of them and only them, M-1…M-6, the two domains; security: can a player gain what the
rules do not allow; determinism and parity: chain and client compute the same result; cost: the
budget and the worst case; organisation: CAIRO.md §7–§8; content: the data is playable) for the
auditor's brief, when one is asked.

### The review by Codex

> **While Codex has no quota** (owner, 2026-10-01, D-175): the review is made by Claude Sonnet and
> every audit by Claude Opus 5.5, through the same `nexus review` and `nexus audit`, which fall back by
> themselves; nothing below waits for Codex's reset.

**Every pull request is reviewed by Codex before it is merged** (owner, 2026-09-29): `nexus review`
when the checks are green, read by the one who merges. The two cases of a merge without a review are
the standard's (Codex unavailable; nothing that runs changed, or a few lines of one's own covered by
the checks), never for a change touching value, access, secrets, a published interface or a result
others depend on; such a merge is recorded in the changelog with `Codex review: none — <reason>`.

### Severity, evidence, fix loops

| Severity | Meaning | Blocks the merge |
|---|---|---|
| `blocker` | Exploit, loss of state, rule broken, build broken | Yes |
| `major` | Wrong behaviour in a reachable case; acceptance criterion without a test | Yes |
| `minor` | Quality, clarity, non-critical cost | Yes, unless deferred by the orchestrator with a PLAN entry |
| `note` | Observation | No |

A finding needs **evidence**: a failing scenario, a test, or a quoted rule; the orchestrator verifies
it before sending it to a fix. The fix is done by **resuming the implementer**. After **three fix
loops** on the same lot the orchestrator stops and escalates to the project manager, who decides (a
last loop limited to named findings, a merge with the findings carried as open points, or a
restructured task) and reports to the owner; never a merge with a known major in anything that will be
published. Audit reports follow the template of COMMON.md (`# [<Model>] Audit — <TASK-ID> — <lens>`,
verdict, findings table, coverage).

## 7. Merge, release, publication

- **A task's pull request merges** on: every check completed and green (`gh pr checks <n>`, the
  number always named, chained on `&&`); the orchestrator's review of `REPORT.md`; the audits §6 requires, if any,
  without open `blocker` or `major`; the Codex review; the file list of the pull request inside the
  task's allowlist. **Squash merge by the orchestrator**, `gh pr merge <n> --squash`, never a bare
  `gh pr merge`. `main` is not protected (D-121), so nothing else stops a merge on pending checks.
- Branches: `<type>/<task-id>-<slug>` for tasks, `orch/` for an orchestrator's own, `pm/` for the
  project manager's, `cv/` for track CV. One pull request per task; a pull request that cannot be
  reviewed in one sitting is split at the brief stage. Conventional commits; trailer
  `Co-Authored-By: Claude <Model> <noreply@anthropic.com>` with the model's display name.
- Tasks run in parallel only if their **allowlists do not overlap**; interfaces shared by parallel
  tasks are frozen first in a dedicated task. CI stays under about 10 minutes.
- **Never**: force-push on shared branches; commit secrets or keys; skip hooks; commit any asset file or
  anything derived from one **in this repository** (D-73: the pack lives in the private repository
  `tiny-swords`, the submodule `assets`; agents never commit in it nor move its pointer; the CI refuses
  a pull request that moves it; nothing of the pack, screenshots included, is posted on GitHub).
- **Deployments**: the orchestrator deploys to **Sepolia** autonomously with the owner's account, the
  variables `STARKNET_NETWORK`, `STARKNET_RPC_URL`, `STARKNET_ACCOUNT_ADDRESS`, `STARKNET_PRIVATE_KEY`
  of the machine's user-level settings, used by name. The launcher empties them unless the task is
  launched with `--with-sepolia`, which it refuses unless the brief, as committed on `origin/main`,
  holds `> Sepolia account: granted (launch with `--with-sepolia`).` and names the profile. A task that
  sends transactions measures instead of looping, reports how many it sent and their cost, and every
  script that sends one **first asks the RPC for its chain id and stops unless it is `SN_SEPOLIA`**.
  Every release goes to Sepolia first; every deployment records the class hash it declared and the
  commit (D-154), the CI checkout root it was built at and the CI artefact (run URL and name,
  `contract-classes-<sha>`, with its `build-root.json`) the declared class files came from (FND-12), the artefact of a push to
  `main` (the commit on `main`), never of a pull request's run. Mainnet is the owner's (D-116).
- **Publications on scarbs.xyz are delegated to the project manager, in the owner's name** (D-132).
  No sub-agent publishes, ever. The orchestrator asks with a committed
  `docs/decisions/PENDING-publish-<package>-<version>.md` (package, version, commit, what changed,
  what the consumer must do). The project manager checks, **itself, in a clean clone**: the commit on
  `main` with every check completed and green; the audits and the Codex review closed without blocker
  or major; the changelog and the version agree; the gas tables are those of the commit; `scarb
  package` from a clean checkout and its sha256; the name and the version free on the registry; no test
  dependency as a regular one; a change of numeric results at least a minor version, announced. The go
  is written in the file with the commit it holds for. The orchestrator's session publishes from a
  clean checkout, tags and releases after the registry shows the version; the project manager reads
  the registry, records the publication in `docs/decisions/` and reports to the owner. A release
  candidate is a publication; a refusal says what is missing.

## 8. Phase gates and the definition of done

A phase closes when all its tasks are merged; its exit criterion (PLAN) is **demonstrated, not
asserted**; a cross-cutting audit (security and design lenses) has run on the whole phase; documents
are reconciled; the owner has signed off.

A task is done when its acceptance criteria are met, each covered by a test; CI is green; the
required audits and the Codex review have no open `blocker` or `major` and deferred `minor` have a
PLAN entry; the documents are updated in the same pull request; `REPORT.md` is archived; `PLAN.md`
and `STATUS.md` are updated.

## 9. The project manager's report

The progress report to the owner and to the Overseer is the standard's table (task or group, state,
who with its model, since, next), built from `nexus progress --project grimworld` and the plan, with
what is blocked and what the reader must decide below it; `PROGRAMME.md` holds it between check-ins.
The owner is addressed in French; everything committed is in English.
