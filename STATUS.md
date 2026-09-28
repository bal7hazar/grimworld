# Status

**2026-09-28 18:06 UTC** — written by the game orchestrator `[Opus 5.5] Orchestrateur Grim World (jeu)`.

## Where we are

**Phase 0 — Foundations, native Starknet (ADR-0007).** Merged since the last check-in:
SPK-5b (toolchain without Dojo; local node starknet-devnet 0.10.0) and FND-01b (native
scaffold; `origami_hexmap` 1.8.0 now builds in the game). Running: **SPK-2** (cost fix loop 1)
and **FND-02** (CI fix loop 1). Next: SPK-11 (indexer), then SPK-7, FND-05, SPK-4.

## What moved

| | |
|---|---|
| **SPK-2, native measure — provisional** | [#25](https://github.com/bal7hazar/grimworld/pull/25). The agent's first native figures: a 300-action expedition **$0.72 to $2.08** natively against $1.15 to $2.86 on Dojo (same prices). **Not decision-grade yet**: the `[GPT-6-Astra]` cost audit found the headline comparison unfair (the native per-goblin layout used 11 storage slots against Dojo's 1; with equal packing the native tick is about **0.28×** Dojo's, not 0.70×), the devnet account metering misread (an old account class meters the whole transaction in VM resources), and the flood's "worst case" a property of the fixture (12 layers; a valid board needs 45). Fix loop 1 running; the figures go to the owner after it |
| SPK-5b merged | [#24](https://github.com/bal7hazar/grimworld/pull/24): Cairo 2.19, snforge and sncast 0.61.0, **starknet-devnet 0.10.0** (Katana refuses Cairo 2.19 classes), starknet.js 10.8.0; `scripts/with-node.sh`; the Dojo spikes keep their own pins, wrapper and locks. Audit `[GPT-6-Sol]` PASS WITH FINDINGS after two fix loops |
| FND-01b merged | [#27](https://github.com/bal7hazar/grimworld/pull/27): `contracts/` workspace (`grimworld_logic` pure with `origami_hexmap` 1.8.0, `Persistent`, `Ephemeral`), client on starknet.js. Audit PASS WITH FINDINGS; checks reproduced by the orchestrator |
| FND-02 | [#21](https://github.com/bal7hazar/grimworld/pull/21) resumed on the native layout, green (6 checks, about 2.5 min); audit `[GPT-6-Sol]` FAIL (4 majors verified: workspace members, versions validated before download, a transitively unpinned action, the failing-test demonstration); fix loop 1 running |
| Briefs | [SPK-11](docs/briefs/SPK-11-indexer.md) (indexer; devnet can abort blocks to simulate a reorg); SPK-2 part 2; COMMON follows the native toolchain |

## Orchestrators and agents

| Orchestrator | Session | Model (verified) | State |
|---|---|---|---|
| Game | `[Opus 5.5] Orchestrateur Grim World (jeu)` | `claude-opus-5-5` | SPK-2 and FND-02 in fix loops |
| Map library (track LIB) | `[Fable 5.1] Orchestrateur hexmap (lib)`, repository `bal7hazar/hexx-cairo` | `claude-fable-5-1` | LIB-03; next stop gate L-G2 |

| Game agent | Unit | Model asked / ran | Profile | State |
|---|---|---|---|---|
| SPK-2 cost spike | `grimworld-SPK-2-180513` (resumed) | `claude-opus-5-5` / `claude-opus-5-5` | implement | Cost fix loop 1 |
| FND-02 continuous integration | `grimworld-FND-02-175911` (resumed) | `claude-sonnet-5` / `claude-sonnet-5` | implement | Fix loop 1 |

Budget (OPERATIONS §3, d9b2c3c): 3 Grim World agents at a time, audits included, across the
game, the map library and quiver: **1 slot of the game's own, 1 shared**. The game holds 2 now
(SPK-2, SPK-11); the first slot freed goes once to quiver's ARC-01, then the shared slot is the
game's first. Before each launch: count every running `grimworld-*`, `hexmap-*`, `quiver-*` unit
and codex audit. Machine at 18:05 UTC: load 5.5, 13 GB available.

## Decided by the owner, gate L-G2

| | |
|---|---|
| D-126 | The porting plan of `hexx` is accepted; package named `hexx`; the tick is measured first; nothing published without a go ([file](docs/decisions/2026-09-28-L-G2-porting-plan.md)) |
| D-127 | The flood of the tick stops at 15 layers; a goblin beyond holds its position (design/02, design/04, ADR-0006) |

## Waiting for the owner

| What | Why only the owner |
|---|---|
| **The registry token reaches every sub-agent.** `SCARB_REGISTRY_AUTH_TOKEN` is in the user-level settings of the machine; the claude CLI injects it into every agent's shell, whatever the launcher does (measured by the library's orchestrator, names only). Profiles deny `scarb publish` as a typed command but cannot stop a program an agent runs. Remedy: take the token out of `~/.claude/settings.json` and keep it where a publication happens (a secret of a GitHub environment with a required reviewer, or a file the owner's own shell reads at release time) | A secret of the owner, used by the owner's other programmes too (D-128). Until then every implement agent is treated as able to publish: small tasks, audited |
| **The Sepolia credentials in the environment of the sessions**: they are not in `~/.claude/settings.json` of the VPS, which defines the registry token only | Secrets are provided by the owner (D-128). Blocks SPK-1 and, through it, the decision on the cost of an expedition (D-129) |

Open without urgency: Q-12, the lore premise.

## Next

1. SPK-2: re-audit by `[GPT-6-Astra]`, merge; then its decision-grade native figures to the
   project manager for the owner (R-2, C-1 below).
2. FND-02: re-audit, merge. Then SPK-11, SPK-7, FND-05 (with `[GPT-6-Astra]`), SPK-4; FND-06.

## For the project manager

C-1 to C-4 answered on 2026-09-28 (#34): C-1 the owner decides on SPK-2's audited native
figures (they follow); C-2 PLAN corrected; C-3 DES-20 (before CBT-06); C-4
[docs/decisions/2026-09-28-indexer-scope.md](docs/decisions/2026-09-28-indexer-scope.md), an
input of SPK-11 and ENG-01.

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
