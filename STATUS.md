# Status — game track

**2026-09-29 05:45 UTC** — written by the game orchestrator `[Opus 5.5] Orchestrateur Grim World (jeu)`.
The live state of the game track only. The programme, the decisions and what waits for the owner
are in [PROGRAMME.md](PROGRAMME.md), written by the project manager.

## Where we are

**Phase 0 — Foundations, native Starknet (ADR-0007).** Done: FND-01, FND-01b, FND-02, FND-03,
**FND-04**, FND-06, ART-00, SPK-1, SPK-1b, SPK-2, **SPK-4**, SPK-5, SPK-5b, SPK-7, SPK-11, DES-21,
DOC-01. **ENG-01** waits for the project manager's decision on its merge, after three fix loops.
Next: FND-05 (after ENG-01 merges: both touch the randomness seam in `contracts/`).

## What moved

| | |
|---|---|
| **ENG-01** | [#81](https://github.com/bal7hazar/grimworld/pull/81), CI green at `4a1ba2b`: five contracts frozen as compiling code (`Instances`, `Hub`, `Market`, `Registry`, `TxHashFate`), layouts, events, the batch codec, every entrypoint priced from the union of its storage keys. Instance slots are reused and records never zeroed (zero-then-rewrite costs as new, measured). The final `[GPT-6-Astra]` re-audit resolves F-1 and F-5 to F-14 and finds no security finding; **two majors remain in the cost accounting only** (F-3, F-4). Estimated S1: **$0.556**, against the $0.50 target; the answer turns on ENG-07's measure of a tick inside a batch |
| **SPK-4** | [#82](https://github.com/bal7hazar/grimworld/pull/82): the client's simulation is a TypeScript mirror checked by vectors; the damage edges decided (D-140) |
| **FND-04** | [#71](https://github.com/bal7hazar/grimworld/pull/71): the cost budget, a new slot about 453,500 L2 gas, an overwrite 32,000 |
| **Launcher** | Reference `5d14d89`, **frozen** until the gate of Phase 0 (FND-07 holds M1, N1–N4, L-3) |

## Orchestrators and agents

| Game agent | Model (ran) | State |
|---|---|---|
| — | | none running |

Budget: slots in `~/orchestrator/slots` (`scripts/agent.sh slots`), 3 in total, game 2.

## Next

1. ENG-01: merge on the project manager's decision; a follow-up ENG-01b if option (a) is taken.
2. FND-05 (Opus 5.5, `[GPT-6-Astra]`), after ENG-01 merges.
3. ENG-02 to ENG-04 once ENG-01 is on main.

## Decisions needed

| Decision | File |
|---|---|
| ENG-01's merge with two accounting majors open (recommended: merge, close them in ENG-01b), and its design escalations (E-1, E-2, E-5, E-7/E-8, E-15, E-16, E-18, E-20, E-21) | [docs/decisions/2026-09-29-eng-01-escalations.md](docs/decisions/2026-09-29-eng-01-escalations.md) |

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
| ART-1 | Display scale: the generated goblins are drawn about twice as large as the pack's units; nothing is resampled. Which on-screen size per caste? | ART-00 | Owner (art direction), before CLI-03 |
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
