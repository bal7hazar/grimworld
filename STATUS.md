# Status

**2026-09-28 15:01 UTC** — written by the game orchestrator `[Opus 5.5] Orchestrateur Grim World (jeu)`.

## Where we are

**Phase 0 — Foundations.** FND-03 (agent tooling) is **merged**; wave 1 is running:
**SPK-5** (toolchain pins) and **ART-00** (asset pipeline), both on Sonnet 5, in parallel
(allowlists do not overlap).

## What moved

| | |
|---|---|
| FND-03 merged | [#8](https://github.com/bal7hazar/grimworld/pull/8): `scripts/agent.sh` (claude agents as systemd units, codex detached with its sandbox, model actually run recorded), profiles `research` / `audit` / `implement` (never `--dangerously-skip-permissions`), `scripts/lock.sh`, `docs/briefs/COMMON.md`, CI `tooling`. Report: [docs/reports/FND-03-agent-tooling.md](docs/reports/FND-03-agent-tooling.md) |
| FND-03 audit | `[GPT-6-Sol]`, lenses S and Q: FAIL, three fix loops, then **PASS WITH FINDINGS** (all notes): [docs/reports/FND-03-audit-gpt-6-sol.md](docs/reports/FND-03-audit-gpt-6-sol.md). One finding disproved by a real run; the inherent one (an interpreter runs anything) documented, with G-1 below |
| Concurrency measured | Empty Dojo 1.8.0 project: `scarb build` 1.4 GB peak, 11 s; a `claude` agent about 0.3 GB. Budget kept at 3 (OPERATIONS §3) |
| Wave-1 briefs | [SPK-5](docs/briefs/SPK-5-toolchain.md), [ART-00](docs/briefs/ART-00-asset-pipeline.md) |
| Changelog | [CHANGELOG.md](CHANGELOG.md) started |

## Orchestrators and agents

| Orchestrator | Session | Model (verified) | State |
|---|---|---|---|
| Game | `[Opus 5.5] Orchestrateur Grim World (jeu)` | `claude-opus-5-5` | FND-03 done. SPK-5 and ART-00 running |
| Map library (track LIB) | `[Fable 5.1] Orchestrateur hexmap (lib)`, repository `bal7hazar/hexx-cairo` | `claude-fable-5-1` | Gate L-G1 decided by the owner (D-119: `hexx` in full, in `hexx-cairo`). LIB-03 porting plan running on Fable 5.1; next stop: gate L-G2 |

| Game agent | Unit | Model asked / ran | Profile | Started |
|---|---|---|---|---|
| SPK-5 toolchain pins | `grimworld-SPK-5-150017` | `claude-sonnet-5` / `claude-sonnet-5` | implement | 15:00 UTC |
| ART-00 asset pipeline | `grimworld-ART-00-150022` (`--with-assets`) | `claude-sonnet-5` / checked at close | implement | 15:00 UTC |

Budget: 3 Grim World agents at a time (D-118): 2 for the game (both in use), 1 for the
library (idle at L-G1). Machine at 15:00 UTC: load 11.7 on 8 vCPU (five units of the owner's
other programmes), 22 GB of 31 available.

Models that actually ran, read from the CLIs' own records (2026-09-28): LIB-02 on
`claude-opus-5-5`; the FND-03 audits on `gpt-6-sol`, effort high, read-only; launcher smoke
tests on `claude-sonnet-5`. One in-session research agent of the game orchestrator was titled
`[Opus 5.5]` and ran on `claude-haiku-4-5`: corrected. The launcher now records the model each
CLI reports (`model=` in the log, `ran=` in `scripts/agent.sh status`).

## Waiting for the owner

| What | Where | Recommendation |
|---|---|---|
| **Incident**: restore `node`, `pnpm`, `codex` on the machine (two lines in the global `~/.tool-versions`) | [docs/reports/INC-2026-09-28-asdf-node-shims.md](docs/reports/INC-2026-09-28-asdf-node-shims.md) | Apply |
| G-1: protect `main` on both repositories | [docs/decisions/PENDING-G-1.md](docs/decisions/PENDING-G-1.md) | Yes, two steps |
| Sight and the window: the window follows the adventurer | [docs/decisions/PENDING-window-follows.md](docs/decisions/PENDING-window-follows.md) | Yes, cost measured by SPK-7 |

## Next

1. Close SPK-5 and ART-00 (review, audits: Q for SPK-5, IP check for ART-00, merge).
2. Then FND-01 → FND-02 → FND-06 on Sonnet 5; SPK-2 on Opus 5.5 as soon as SPK-5 is merged.
3. Then FND-05 (with a `[GPT-6-Astra]` audit), SPK-4, SPK-8 on Opus 5.5; SPK-7 after them.

## Blocked

| What | By |
|---|---|
| FND-01, SPK-2, and every task that builds Cairo | SPK-5 (running) |
| SPK-1, deployments | Sepolia credentials, Phase 1 |
| SPK-6 | Real phones: the owner runs the protocol the orchestrator writes |
| Mainnet | An explicit go from the owner, each time (D-116) |

## Decisions needed

| # | Decision | Why | Recommendation |
|---|---|---|---|
| G-1 | **Protect `main` on GitHub** (repository settings, the owner's or the project manager's act): no force-push, no deletion. Optionally require the `tooling` check on pull requests, with administrators allowed to bypass so that the orchestrator's bookkeeping pushes still work | The `[GPT-6-Sol]` audit of FND-03 showed that command allowlists cannot stop an agent's interpreter or test from pushing with the `gh` credentials of the machine; only the server can refuse a force-push to `main` whatever runs it | Yes, force-push and deletion blocked now; the required check when FND-02 lands |

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
  not needed today. No system setting was changed.
- `sozo`, `katana` and `torii` are still absent (SPK-5); Sepolia credentials are not in the
  environment and not needed before Phase 1; the `assets` submodule is not initialised in the
  main checkout (an independent clone of `tiny-swords` is in `~/projects/assets`).

## Not verified

- Latency and cost on mainnet: public data only, no transaction of ours.
- `origami_hexmap` costs: the library's own benchmarks.
- Phone battery and heat: no measurement exists for any candidate engine.
