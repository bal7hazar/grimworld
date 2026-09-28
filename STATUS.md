# Status

**2026-09-28 16:30 UTC** — written by the game orchestrator `[Opus 5.5] Orchestrateur Grim World (jeu)`.

## Where we are

**Phase 0 — Foundations. HOLD on new launches (2026-09-28, 16:30 UTC)**: the owner has decided
that the game drops Dojo and is built as native Starknet contracts (reasons: the gas spent in
Dojo's layer, and the Cairo 2.13 pin Dojo's tools impose, N-9). The project manager is writing
ADR-0007 and the corrections; the game orchestrator launches nothing new until they are merged.

| | During the hold |
|---|---|
| SPK-2 (running) | Finishes; its figures on Dojo 1.8 become the baseline for the native contracts, measured again natively in a follow-up |
| FND-02 (running) | Finishes its turn; its pull request is **not merged** while its CI installs `sozo`, `katana` or `torii`; resumed later with the new toolchain |
| FND-05, SPK-4, SPK-8 | Briefed on Dojo; **waiting** for the corrected documents, to be rewritten |
| SPK-7 | Briefed as a standalone Cairo 2.19 package (D-122); to be checked against ADR-0007 before launch |
| PR [#20](https://github.com/bal7hazar/grimworld/pull/20) (Rust rules in the `implement` profile) | Open; its audit waits for the end of the hold |

## What moved

| | |
|---|---|
| FND-01 merged | [#18](https://github.com/bal7hazar/grimworld/pull/18): `contracts/` (two namespaces, layering), `client/` (`sim` apart from `app`, PixiJS on demand). Audit `[GPT-6-Sol]` PASS WITH FINDINGS. **Found N-9**: `origami_hexmap` 1.8.0 cannot build on Cairo 2.13; arbitrated by the project manager (D-122) |
| ART-00 merged | [#12](https://github.com/bal7hazar/grimworld/pull/12): 8 sprites cleaned and packed outside git; PixiJS 8 parses every animation; [IP check](docs/reports/ART-00-ip-check.md) PASS |
| SPK-5 merged | [#14](https://github.com/bal7hazar/grimworld/pull/14): Cairo 2.13, Dojo 1.8, Node 24.21, pnpm 12.5.1; Torii self-hosted |
| Incident closed | [INC-2026-09-28](docs/reports/INC-2026-09-28-asdf-node-shims.md): remedy applied on the owner's order; rule added to COMMON |
| Briefs | [FND-02](docs/briefs/FND-02-ci.md) (per-package toolchains), [SPK-7](docs/briefs/SPK-7-chunked-maps.md) (standalone on Cairo 2.19, D-122) |

## Orchestrators and agents

| Orchestrator | Session | Model (verified) | State |
|---|---|---|---|
| Game | `[Opus 5.5] Orchestrateur Grim World (jeu)` | `claude-opus-5-5` | SPK-2 and FND-02 running |
| Map library (track LIB) | `[Fable 5.1] Orchestrateur hexmap (lib)`, repository `bal7hazar/hexx-cairo` | `claude-fable-5-1` | LIB-03 porting plan, now also the compiler target (D-122); next stop: gate L-G2 |

| Game agent | Unit | Model asked / ran | Profile | Started |
|---|---|---|---|---|
| SPK-2 cost spike | `grimworld-SPK-2-160353` | `claude-opus-5-5` / `claude-opus-5-5` | implement | 16:03 UTC |
| FND-02 continuous integration | `grimworld-FND-02-162135` | `claude-sonnet-5` / at close | implement | 16:21 UTC |

Budget: 3 Grim World agents at a time (D-118): 2 for the game (both in use), 1 for the
library. Machine at 16:21 UTC: load 7.5, 20 GB available.

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

## Change of stack

| | |
|---|---|
| D-123 | **Native Starknet contracts, without Dojo** (owner, 2026-09-28; [ADR-0007](docs/architecture/ADR-0007-native-starknet.md)). Cairo 2.19 for the game; probably an indexer of our own (SPK-11); quests and titles written in the game. N-9 and D-122 are void. Work built on Dojo today: the pins of SPK-5 and the scaffold of FND-01 are reworked by SPK-5b and FND-01b; SPK-2 keeps its Dojo figures as the baseline |

## Decided today by the owner (continued)

| | |
|---|---|
| D-124 | The Arcade packages are rewritten natively, one new repository each, pure Starknet components and pure Cairo. PLAN track ARC; needs in [docs/needs/arcade.md](docs/needs/arcade.md) |

## Waiting for the owner

Nothing blocks the game today. **ARC-00**: names and visibility of the repositories of `quest` and `achievement`, and whether the project manager creates them. Open without urgency: Q-12 (Arcanist sprite or Cleric, Phase 2), the owner's reaction to the lore premise.

## Next

1. Close SPK-2 (audit C) and FND-02 (audits S Q).
2. Briefs of FND-05 (provider interfaces, `[GPT-6-Astra]` audit), SPK-4 (parity), SPK-8 (Arcade
   packages) on Opus 5.5; then SPK-7; FND-06 after FND-02.

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
