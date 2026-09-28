# Status

**2026-09-28 15:36 UTC** — written by the game orchestrator `[Opus 5.5] Orchestrateur Grim World (jeu)`.

## Where we are

**Phase 0 — Foundations.** FND-03 merged. Wave 1: **SPK-5** (toolchain pins) is in its first
audit fix loop; **ART-00** (asset pipeline) is done except its PixiJS check, which needs the
`pnpm` SPK-5 pins. FND-01 and SPK-2 are briefed and launch when SPK-5 merges.

## What moved

| | |
|---|---|
| FND-03 merged | [#8](https://github.com/bal7hazar/grimworld/pull/8). Report: [docs/reports/FND-03-agent-tooling.md](docs/reports/FND-03-agent-tooling.md); audit `[GPT-6-Sol]` PASS WITH FINDINGS after three fix loops |
| Launcher thresholds merged | [#11](https://github.com/bal7hazar/grimworld/pull/11): the launcher refuses to start or resume an agent above a 5-minute load of 12 or under 8 GB available; codex runs through the system `node`; `implement` denies direct agent-launch commands. Audit `[GPT-6-Sol]` PASS after two fix loops |
| SPK-5 | [#14](https://github.com/bal7hazar/grimworld/pull/14), `[Sonnet 5]`: Scarb 2.13.1, snforge 0.51.2, sozo 1.8.7, Katana 1.7.1, Torii 1.8.16, Node 24.21.0, pnpm 12.5.1, `dojo` 1.8.0, dojo.js 2.0.0. **The game stays on Cairo 2.13** (Dojo 1.8's own chain; the machine's global Scarb 2.19.4 cannot build it). End to end proven: migrate, index, read back with dojo.js. **Slot hosting is retired: Torii is self-hosted.** Audit `[GPT-6-Sol]` FAIL (5 majors on the scripts: process cleanup, ports, symlink ownership, binary integrity, asdf plugins untested), all verified; fix loop 1 running |
| ART-00 | [#12](https://github.com/bal7hazar/grimworld/pull/12), `[Sonnet 5]`: 8 sprites cleaned, renamed and packed outside git; IP check by the orchestrator clean (no image, no name from the manga, the generated folder resolved in code). AC-4 (PixiJS load) pending: `pnpm` could not run in the agent's worktree (no pinned version before SPK-5) |
| Incident | [INC-2026-09-28](docs/reports/INC-2026-09-28-asdf-node-shims.md): SPK-5's asdf `nodejs`/`pnpm` plugins created machine-wide shims; `node`, `pnpm`, `codex` fail outside pinned directories. Cause: the orchestrator's brief. Remedy with the owner |
| Briefs | [FND-01](docs/briefs/FND-01-scaffold.md) (proves `origami_hexmap` 1.8.0 builds on Cairo 2.13), [SPK-2](docs/briefs/SPK-2-cost.md) (5 Rifts a day per D-101, not PLAN's 10) |

## Orchestrators and agents

| Orchestrator | Session | Model (verified) | State |
|---|---|---|---|
| Game | `[Opus 5.5] Orchestrateur Grim World (jeu)` | `claude-opus-5-5` | SPK-5 fix loop 1; ART-00 waiting for SPK-5 |
| Map library (track LIB) | `[Fable 5.1] Orchestrateur hexmap (lib)`, repository `bal7hazar/hexx-cairo` | `claude-fable-5-1` | Gate L-G1 decided by the owner (D-119: `hexx` in full, in `hexx-cairo`). LIB-03 porting plan running on Fable 5.1; next stop: gate L-G2 |

| Game agent | Unit | Model asked / ran | Profile | State |
|---|---|---|---|---|
| SPK-5 toolchain pins | `grimworld-SPK-5-153325` (resumed) | `claude-sonnet-5` / `claude-sonnet-5` | implement | Fix loop 1 |
| ART-00 asset pipeline | — | `claude-sonnet-5` / `claude-sonnet-5` | implement | Stopped, PR open, to resume after SPK-5 |

Budget: 3 Grim World agents at a time (D-118): 2 for the game (1 in use), 1 for the library
(LIB-03). Machine at 15:33 UTC: load 8.6, 22 GB available.

Models that actually ran, read from the CLIs' own records (2026-09-28): LIB-02 on
`claude-opus-5-5`; the FND-03 audits on `gpt-6-sol`, effort high, read-only; launcher smoke
tests on `claude-sonnet-5`. One in-session research agent of the game orchestrator was titled
`[Opus 5.5]` and ran on `claude-haiku-4-5`: corrected. The launcher now records the model each
CLI reports (`model=` in the log, `ran=` in `scripts/agent.sh status`).

## Decided today by the owner

| | |
|---|---|
| D-119 | `hexx` ported in full in `bal7hazar/hexx-cairo`; `origami_hexmap` decommissioned at the end ([file](docs/decisions/2026-09-28-L-G1-hexx-port.md)) |
| D-120 | The window follows the adventurer, 15 × 16, not stored; fallback sight 5 on 13 × 14 ([file](docs/decisions/2026-09-28-window-follows.md)); ADR-0006, design/02, design/18, CONTEXT, PLAN v0.16 and docs/needs/hexmap.md corrected |

## Waiting for the owner

| What | Where | Recommendation |
|---|---|---|
| **Incident**: restore `node`, `pnpm`, `codex` on the machine (two lines in the global `~/.tool-versions`) | [docs/reports/INC-2026-09-28-asdf-node-shims.md](docs/reports/INC-2026-09-28-asdf-node-shims.md) | Apply |
| G-1: protect `main` on both repositories | [docs/decisions/PENDING-G-1.md](docs/decisions/PENDING-G-1.md) | Yes, two steps |

## Next

1. SPK-5: fix loop 1, re-audit, merge; then add `.with-katana/` to the root `.gitignore`.
2. Then, in parallel: **FND-01** (Sonnet 5) and **SPK-2** (Opus 5.5); ART-00 resumed for its
   PixiJS check when a slot frees.
3. Then FND-02 → FND-06 on Sonnet 5; FND-05 (with a `[GPT-6-Astra]` audit), SPK-4, SPK-8 on
   Opus 5.5; SPK-7 after them.

## Open questions from wave 1 (not blocking)

| # | Question | From | For |
|---|---|---|---|
| ART-1 | Display scale: the generated goblins are drawn about twice as large as the pack's units; nothing is resampled. Which on-screen size per caste? | ART-00 | Owner (art direction), before CLI-03 |
| ART-2 | Slinger placeholder: the Torch Goblin stands in (the pack's slinger is a gnome) | ART-00 | Owner, at the first commission (ART-01) |
| TC-1 | `CONTEXT.md` §4 and `docs/CAIRO.md` should name Cairo 2.13 / Scarb 2.13.1 / snforge 0.51.2; ADR-0001 option B and ADR-0003's indexer consequence are confirmed by SPK-5 (Slot retired) | SPK-5 | Project manager (documents it owns) |

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
