# Status

**2026-09-28 17:20 UTC** — written by the game orchestrator `[Opus 5.5] Orchestrateur Grim World (jeu)`.

## Where we are

**Phase 0 — Foundations, native Starknet (ADR-0007, D-123).** Merged: FND-03, SPK-5, FND-01,
ART-00, the launcher thresholds (#11), the profile for Rust and native tools (#20). Running:
**SPK-5b** (toolchain without Dojo, audit fix loop 1). Waiting for SPK-5b: FND-01b, SPK-2's
native re-measure, FND-02's resume.

## What moved

| | |
|---|---|
| **SPK-2, Dojo baseline** | [#25](https://github.com/bal7hazar/grimworld/pull/25), `[Opus 5.5]`, open until its native follow-up. **On Dojo 1.8, ADR-0001's threshold fails at today's prices**: a 300-action expedition costs **$1.73 to $2.69** (3.5× to 5.4× the $0.50 threshold), **$0.97 to $1.08** with the goblins packed by hand. Storage through the Dojo world is **72 %** of the worst-case tick (the world tick in memory: 1.25M of 13.2M L2 gas). Budget per action at today's prices: 1.9M L2 gas; break-even L2 gas price 5.2 to 11.0 Gfri (17.8 to 30.4 over two weeks). **D-52 kept** (+1.6 %). Detail: `docs/research/SPK-2-cost.md` in the PR |
| **SPK-5b** | [#24](https://github.com/bal7hazar/grimworld/pull/24), `[Sonnet 5]`: Scarb 2.19.4, snforge/sncast 0.61.0, **starknet-devnet 0.10.0** as the local node (**NS-1: Katana 1.7.1 and 1.8.0-rc.9 both refuse a Cairo 2.19 class**, Sierra 1.9.3 against their 1.7.0 compiler), starknet.js 10.8.0; declare, deploy, invoke, call, event proven. Audit `[GPT-6-Sol]` FAIL (5 majors verified: key file unignored, Dojo baseline not runnable, plugin rule partial, setup edge case, research profile); fix loop 1 running |
| PR #20 merged | `implement` allows Rust builds confined to the worktree, `sncast` against a local node only, `starknet-devnet`. Audit PASS WITH FINDINGS after three fix loops. **Process slip**: merged while its last CI run was pending (it passed, on the merged head); every merge now waits for the checks to complete |
| FND-02 | [#21](https://github.com/bal7hazar/grimworld/pull/21) green: CI per Cairo package with the toolchain of its nearest `.tool-versions`, no Dojo tool; audit and merge after SPK-5b |
| Briefs | ADR-0007 applied: [SPK-5b](docs/briefs/SPK-5b-toolchain-native.md), [FND-01b](docs/briefs/FND-01b-scaffold-native.md) new; FND-05, SPK-4, SPK-7 rewritten; SPK-8 dropped (D-124) |

## Orchestrators and agents

| Orchestrator | Session | Model (verified) | State |
|---|---|---|---|
| Game | `[Opus 5.5] Orchestrateur Grim World (jeu)` | `claude-opus-5-5` | SPK-5b fix loop 1 |
| Map library (track LIB) | `[Fable 5.1] Orchestrateur hexmap (lib)`, repository `bal7hazar/hexx-cairo` | `claude-fable-5-1` | LIB-03 porting plan; next stop: gate L-G2 |

| Game agent | Unit | Model asked / ran | Profile | State |
|---|---|---|---|---|
| SPK-5b toolchain without Dojo | `grimworld-SPK-5b-171026` (resumed) | `claude-sonnet-5` / `claude-sonnet-5` | implement | Fix loop 1 |
| SPK-2 cost spike | — | `claude-opus-5-5` / `claude-opus-5-5` | implement | Baseline done; resumed for the native measure after SPK-5b |

Budget: 3 Grim World agents at a time (D-118): 2 for the game (1 in use: the next launches all
depend on SPK-5b), 1 for the library. Machine at 17:10 UTC: load 6.3, 21 GB available.

## Waiting for the owner

Nothing blocks the game today. **ARC-00**: the name of the single repository of track ARC (D-125: one repository of separate Scarb packages, CI by affected package; in time the home of the other `*-cairo` libraries). Open without urgency: Q-12 (Arcanist sprite or Cleric, Phase 2), the owner's reaction to the lore premise.

## Next

1. SPK-5b: re-audit, merge; then the follow-ups it escalated (COMMON: `with-node.sh`).
2. In parallel: **FND-01b** (Sonnet 5) and **SPK-2 resumed for the native measure** (Opus 5.5,
   the priority: the figure the owner's decision rests on); FND-02 resumed on the new toolchain.
3. Then SPK-11 (indexer), SPK-7, FND-05 (with `[GPT-6-Astra]`), SPK-4; FND-06 after FND-02.

## For the project manager (from SPK-2, not blocking)

| # | Point | Recommendation |
|---|---|---|
| C-1 | **R-2 materialises on Dojo**: ADR-0001's threshold (300 actions ≤ $0.50) fails 1.9× to 5.4× at today's prices. The owner's call on option B or on restating the threshold should wait for SPK-2's **native** figures, which come next | Decide on the native figures |
| C-2 | PLAN's SPK-2 row says "10 Rifts"; D-101 says 5 a day per account (5 was used) | Correct the row |
| C-3 | Flood rule (a) (docs/needs/hexmap.md point 5): on the occupancy frozen at the start of the tick, a goblin can be walled off behind its own pack; observed: it detours and leaves the window within 7 ticks. A design question for design/04 *Goblin AI* | To the owner or the design backlog |

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
