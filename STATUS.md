# Status

**2026-09-28 14:25 UTC** — written by the game orchestrator `[Opus 5.5] Orchestrateur Grim World (jeu)`.

## Where we are

**Phase 0 — Foundations.** The game orchestrator is running (mandate:
[docs/briefs/ORCH-game.md](docs/briefs/ORCH-game.md)). Its first task, **FND-03 agent
tooling**, is in its pull request, awaiting the `[GPT-6-Sol]` audit (lenses S and Q) before
merge. No sub-agent of the game can be launched before it merges.

## What moved

| | |
|---|---|
| FND-03 | `scripts/agent.sh` launcher: transient systemd user units `grimworld-<task>-<hhmmss>` whose description carries the model tag, `status`, `wait`, `sid`, `--dry-run`, `--with-assets`, `--branch`; resume with context. Three committed profiles (`scripts/profiles/research`, `audit`, `implement`) instead of `--dangerously-skip-permissions`. Build lock `scripts/lock.sh` (project lock, then the machine-wide heavy lock). `docs/briefs/COMMON.md`. CI `tooling`: shellcheck, launcher dry-run, no asset file |
| Launcher verified | A trivial `[Sonnet 5]` research task ran as a systemd unit, listed by `status`, log ending `exit=0`, `REPORT.md` written. An `implement` probe: `git status` and `scripts/lock.sh pnpm --version` allowed; force-push, the stash, `gh pr merge`, `ls ~/.local/bin`, `rm -rf ../…` refused; a write outside the worktree refused, not prompted |
| Concurrency measured | Empty Dojo 1.8.0 project: `scarb build` peaks at 1.4 GB, 11 s. A `claude` agent holds about 0.3 GB. Budget kept at 3 (OPERATIONS §3) |

## Agents

| Agent | Unit | State |
|---|---|---|
| Game | none | FND-03 is executed by the orchestrator itself |
| Map library | `hexmap-LIB-02-*` `[Opus 5.5] LIB-02 hexx analysis` | Running (library orchestrator's) |

Machine at 14:19 UTC: load 3.5 on 8 vCPU; 26 GB of 31 available; four units of the owner's
other programmes and one of the library. Budget: 3 Grim World agents at a time (D-118), 2
for the game in wave 1.

## Next

1. `[GPT-6-Sol]` audit of FND-03, fixes, merge.
2. Briefs of **SPK-5** (toolchain pins; also writes `scripts/with-katana.sh`) and **ART-00**
   (asset pipeline outside git, the only wave-1 task with `--with-assets`), launched in
   parallel on Sonnet 5.
3. Then FND-01 → FND-02 → FND-06 on Sonnet 5; SPK-2 on Opus 5.5 as soon as SPK-5 is merged.

## Blocked

| What | By |
|---|---|
| Every game sub-agent | FND-03's merge (today) |
| SPK-1, deployments | Sepolia credentials, Phase 1 |
| SPK-6 | Real phones: the owner runs the protocol the orchestrator writes |
| Mainnet | An explicit go from the owner, each time (D-116) |

## Decisions needed

None today from the game orchestrator.

## Open on the owner's side (not blocking)

Q-12 Arcanist sprite or Cleric (Phase 2); reaction to the lore premise (DES-14); Q-08
registry writers and Q-03 defeat severity (Phase 1).

## MVP and version 1

The MVP is a test version: burner accounts, randomness from the transaction hash, test
networks only, nothing of value, progress may be wiped. Version 1 replaces both providers
behind their interfaces and goes through the hardening phase.

## Design coverage

Written: 19 design documents, the lore premise, 6 ADRs. Still to write before the phases that
need them: effect catalogue, remaining skills, caste sheets, curves, content lists
([PLAN.md](PLAN.md#design-backlog)).

## Verified on the machine

- `claude` CLI on claude-b7r (2.1.283); `codex` 0.155.1; `gh` on bal7hazar.
- SSH access to the private `tiny-swords` repository works: `--with-assets` can initialise
  the submodule in a task worktree.
- scarb 2.19.4 compiles a Dojo 1.8.0 project (dependency from scarbs.xyz, prebuilt
  `dojo_cairo_macros`); `sozo`, `katana`, `torii` are still absent (SPK-5).
- `shellcheck` is not installed on the VPS: it runs in CI.
- **codex's read-only sandbox does not work in a systemd user unit** on this VPS
  (`bwrap: loopback: Failed RTM_NEWADDR`, then `setting up uid map: Permission denied`): the
  kernel restricts unprivileged user namespaces through AppArmor, and only the desktop app's
  profile allows them. The launcher therefore detaches codex with `setsid` inside the app's
  cgroup, keeping the sandbox (OPERATIONS §3); an app restart kills a running audit, which is
  then resumed. A root change (an AppArmor profile for `bwrap`) would let codex run as a unit;
  not needed today.

## Not verified

- Latency and cost on mainnet: public data only, no transaction of ours.
- `origami_hexmap` costs: the library's own benchmarks.
- Phone battery and heat: no measurement exists for any candidate engine.
