# Status — game track

**2026-09-29 17:30 UTC** — written by the game orchestrator `[Opus 5.5] Orchestrateur Grim World (jeu)`.
The live state of the game track only. The programme, the decisions and what waits for the owner
are in [PROGRAMME.md](PROGRAMME.md), written by the project manager.

## Where we are

**Phase 0 done** (the gate items are FND-07's). **Phase 1**: ENG-01, ENG-01b, ENG-02a, ENG-03, ENG-04,
ENG-06 done; ENG-05 and ENG-02 (line of sight) wait for the map library's release; ENG-07 after
ENG-05; ENG-R1 (D-143, D-147) after ARC-07. **Pulled forward while the engine chain waits (D-150)**:
DES-04 (design/19), CBT-01 (the combat interfaces), CBT-08a (`set_build`), FND-08 (the funding
service), FND-09 (`with-node.sh` on macOS) all done. **No game agent runs**; the next lot is for the
project manager to choose (see *Next*).

**S1's running estimate** (300 actions, D-129's $0.50; D-158 asks it kept here):

| Since | Change | S1 |
|---|---|---:|
| ENG-01 §10.2 | the design as frozen | 631.1 M ≈ **$0.556** |
| ENG-03 (D-145) | content reads, 36,000 a slot: about 10 records a batch × 30 batches | +30 M |
| ENG-06 (D-148) | `enter`, `leave`, `travel_back` as measured | +0.7 M |
| CBT-01, CBT-08a (D-158) | the larger snapshot and the belt's worst case, once an expedition | +2.2 M |
| **Now** | | **≈ 664 M ≈ $0.585** (E), before ENG-07 measures a tick inside a batch (CB-2, R-2) |

**A tick against its budget** (1,469,435 L2 gas on average, what S1 needs for $0.50): the map library's
part of a worst tick is **1.06–1.11 M** (window, flood at 15 layers, 8 walkers; LIB-05 M1-T9b), which
leaves about 0.4 M for the game's logic and storage; CBT-02's pipeline measures **1.01 M representative,
1.39 M worst** (content included). A worst tick is about 2.5 M before the executor, the AI and the
writes. S1 above does not yet count this: it rests on ENG-01's per-tick estimate. The levers are for
decision ([file](docs/decisions/2026-09-29-cbt-02-tick-cost.md)).

## What moved

| | |
|---|---|
| **CBT-08a** | [#170](https://github.com/bal7hazar/grimworld/pull/170): `set_build`; items carry their base's slot and hands; worst case about 3.80M, its target (D-158) |
| **CBT-01** | [#165](https://github.com/bal7hazar/grimworld/pull/165): design/19's data frozen as code; questions A–I decided (D-157) |
| **DES-04** | [#139](https://github.com/bal7hazar/grimworld/pull/139): design/19, the effect catalogue and resolution order (D-155) |
| **FND-08, FND-09** | [#141](https://github.com/bal7hazar/grimworld/pull/141) the funding service, caps decided (D-156); [#152](https://github.com/bal7hazar/grimworld/pull/152) `with-node.sh` on macOS |
| **Events** | **No event of ENG-01 has changed** (D-149: the indexer, lent to track CV, reads them) |
| **Launcher** | Reference `5d14d89`, frozen until the gate of Phase 0 (FND-07). Queues export the systemd user bus (a session's own D-Bus lost systemd at 15:02; nothing on the machine changed) |

## Orchestrators and agents

| Game agent | Model (ran) | State |
|---|---|---|
| — | | none running |

Budget: slots in `~/orchestrator/slots` (`scripts/agent.sh slots`), 3 in total, game 2.

## Next

1. The project manager chooses the next lot. The orchestrator's recommendation: **CBT-02** (the world tick's
   pipeline, regeneration, durations, recharges) as pure rules in a library class (ENG-01 §1.3), from
   design/19 and CBT-01, with CBT-9 and D-157 E; ENG-07 and CLI-02 build on it.
2. ENG-05 and ENG-02 when the map library releases `hexx` (LIB-05).

## Decisions needed

None open. Answered today: D-141 to D-158.

## Build notes (D-154)

Scarb 2.19.4 builds of the same sources can differ in gas (+0.2 to +1.3 %) and Sierra size: a gas
budget that flakes in CI is recorded here with its run ids, not raised.

| When | What | Where |
|---|---|---|
| 2026-09-29, CBT-08a | `set_build`'s belt case on the local node measured +160,000 on an unchanged path between two runs | [report](docs/reports/CBT-08a-set-build.md), fix loop 1 |

## Launcher: for its next change (not before a finding or a task needs one)

L-1 and L-2 of the previous status were done by #58 and #60.

| # | What | Source |
|---|---|---|
| L-3 | Moved to PLAN FND-07 (at the gate of Phase 0) | |

## Blocked

| What | By |
|---|---|
| SPK-6 | Real phones: the owner runs the protocol the orchestrator writes |
| Mainnet | An explicit go from the owner, each time (D-116) |

## Open questions from wave 1 (not blocking)

| # | Question | From | For |
|---|---|---|---|
| ART-1 | **Answered by the owner** (D-146 corrected, #137): the pack's hand-drawn units keep their height; only the generated goblin sheets are reduced (runt about 67–70 px, shaman about 87, hobgoblin about 119), final sizes by eye on CLI-03a; track CV, ART-02 | ART-00 | — |
| ART-2 | Slinger placeholder: the Torch Goblin stands in (the pack's slinger is a gnome) | ART-00 | Owner, at the first commission (ART-01) |
| TC-1 | `CONTEXT.md` §4 and `docs/CAIRO.md` should name Cairo 2.13 / Scarb 2.13.1 / snforge 0.51.2; ADR-0001 option B and ADR-0003's indexer consequence are confirmed by SPK-5 (Slot retired) | SPK-5 | Project manager (documents it owns) |

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
- `sozo`, `katana` and `torii` are still absent (SPK-5); the Sepolia account is in the
  machine's settings since 20:21 UTC (checked by name), given to agents only with
  `--with-sepolia`; the `assets` submodule is not initialised in the
  main checkout (an independent clone of `tiny-swords` is in `~/projects/assets`).

## Not verified

- Latency and cost on mainnet: public data and Sepolia only, no mainnet transaction of ours.
- `origami_hexmap` costs: the library's own benchmarks.
- Phone battery and heat: no measurement exists for any candidate engine.
