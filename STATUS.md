# Status

**2026-09-28 16:05 UTC** — written by the game orchestrator `[Opus 5.5] Orchestrateur Grim World (jeu)`.

## Where we are

**Phase 0 — Foundations.** FND-03 and SPK-5 merged. Running: **FND-01** (repository
scaffold, Sonnet 5) and **SPK-2** (cost spike, Opus 5.5). ART-00 is done except its PixiJS
check and resumes when a game slot frees.

## What moved

| | |
|---|---|
| SPK-5 merged | [#14](https://github.com/bal7hazar/grimworld/pull/14), `[Sonnet 5]`: **the game is on Cairo 2.13** (Scarb 2.13.1, snforge 0.51.2) and Dojo 1.8 (sozo 1.8.7, Katana 1.7.1, Torii 1.8.16, `dojo` 1.8.0), Node 24.21.0, pnpm 12.5.1, dojo.js 2.0.0; `scripts/setup-toolchain.sh`, `scripts/with-katana.sh`; Slot retired, Torii self-hosted. Audit `[GPT-6-Sol]` PASS WITH FINDINGS after three fix loops; checksums of asdf-plugin downloads deferred as HRD-10. [Report](docs/reports/SPK-5-toolchain.md), [audit](docs/reports/SPK-5-audit-gpt-6-sol.md) |
| Launcher thresholds merged | [#11](https://github.com/bal7hazar/grimworld/pull/11): no agent starts above a 5-minute load of 12 or under 8 GB available |
| Owner decisions applied to briefs | D-120 (window 15 × 16, follows the adventurer, not stored) in [SPK-2](docs/briefs/SPK-2-cost.md); [SPK-7](docs/briefs/SPK-7-chunked-maps.md) written from PLAN v0.16; D-119 (`origami_hexmap` 1.8.0 until `hexx-cairo` is published) in FND-01 and SPK-7 |
| ART-00 | [#12](https://github.com/bal7hazar/grimworld/pull/12) open: IP check clean; AC-4 (PixiJS load) pending, now possible with the pinned pnpm |
| Incident | [INC-2026-09-28](docs/reports/INC-2026-09-28-asdf-node-shims.md) still open (owner). `setup-toolchain.sh` no longer adds the Node or pnpm plugin when the system versions match the pins |

## Orchestrators and agents

| Orchestrator | Session | Model (verified) | State |
|---|---|---|---|
| Game | `[Opus 5.5] Orchestrateur Grim World (jeu)` | `claude-opus-5-5` | FND-01 and SPK-2 running; ART-00 waiting for a slot |
| Map library (track LIB) | `[Fable 5.1] Orchestrateur hexmap (lib)`, repository `bal7hazar/hexx-cairo` | `claude-fable-5-1` | Gate L-G1 decided (D-119). LIB-03 porting plan; next stop: gate L-G2 |

| Game agent | Unit | Model asked | Profile | Started |
|---|---|---|---|---|
| FND-01 repository scaffold | `grimworld-FND-01-160350` | `claude-sonnet-5` | implement | 16:03 UTC |
| SPK-2 cost spike | `grimworld-SPK-2-160353` | `claude-opus-5-5` | implement | 16:03 UTC |

Budget: 3 Grim World agents at a time (D-118): 2 for the game (both in use), 1 for the
library. Machine at 16:03 UTC: load 3.9, 26 GB available.

Models that actually ran, read from the CLIs' own records (2026-09-28): LIB-02 on
`claude-opus-5-5`; the FND-03 audits on `gpt-6-sol`, effort high, read-only; launcher smoke
tests on `claude-sonnet-5`. One in-session research agent of the game orchestrator was titled
`[Opus 5.5]` and ran on `claude-haiku-4-5`: corrected. The launcher now records the model each
CLI reports (`model=` in the log, `ran=` in `scripts/agent.sh status`).

## Decided today by the owner

| | |
|---|---|
| D-119 | `hexx` ported in full in `bal7hazar/hexx-cairo`; `origami_hexmap` decommissioned at the end ([file](docs/decisions/2026-09-28-L-G1-hexx-port.md)) |
| D-121 | `main` is **not** protected for now: the owner keeps full freedom during the kick-start ([file](docs/decisions/2026-09-28-G-1-main-protection.md)); raised again at the gate of Phase 0 |
| D-120 | The window follows the adventurer, 15 × 16, not stored; fallback sight 5 on 13 × 14 ([file](docs/decisions/2026-09-28-window-follows.md)); ADR-0006, design/02, design/18, CONTEXT, PLAN v0.16 and docs/needs/hexmap.md corrected |

## Incident closed

| | |
|---|---|
| asdf shims broke `node`, `pnpm`, `codex` machine-wide (15:05 UTC) | **Fixed on 2026-09-28 by the project manager, on the owner's order**: `nodejs system` and `pnpm system` added to the global `~/.tool-versions` (backup `~/.tool-versions.bak`). Verified from `/tmp`: `node` v24.21.0, `pnpm` 12.5.1, `codex-cli` 0.155.1, exit 0; the SPK-5 worktree keeps its pins. Residual: `npm`, `npx` and `corepack` work but print one asdf warning on stderr ("No version is set for nodejs"). [Report](docs/reports/INC-2026-09-28-asdf-node-shims.md) |

## Cross-track finding

| | |
|---|---|
| N-9 | The game cannot build `origami_hexmap` 1.8.0: Dojo 1.8 imposes Cairo 2.13, the library asks 2.19. Arbitrated by the project manager ([file](docs/decisions/2026-09-28-N-9-compiler-target.md)): SPK-7 runs standalone on 2.19; LIB-03 studies the compiler floor; the owner decides at L-G2 |

## Waiting for the owner

Nothing blocks. Open without urgency: Q-12 (Arcanist sprite or Cleric, Phase 2), the owner's reaction to the lore premise.

## Next

1. Close FND-01 and SPK-2 (audits: Q for FND-01, C for SPK-2).
2. Resume ART-00 for its PixiJS check when a slot frees; then its merge.
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
| SPK-1, deployments | Sepolia credentials, Phase 1 |
| SPK-6 | Real phones: the owner runs the protocol the orchestrator writes |
| Mainnet | An explicit go from the owner, each time (D-116) |

## Decisions needed

None from the game orchestrator. G-1 was answered by the owner (D-121: `main` not protected
for now; the residual of the FND-03 audit's finding F4 is accepted until the gate of Phase 0).

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
