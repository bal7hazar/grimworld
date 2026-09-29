# Status — game track

**2026-09-29 06:30 UTC** — written by the game orchestrator `[Opus 5.5] Orchestrateur Grim World (jeu)`.
The live state of the game track only. The programme, the decisions and what waits for the owner
are in [PROGRAMME.md](PROGRAMME.md), written by the project manager.

## Where we are

**Phase 0 — Foundations, native Starknet (ADR-0007).** Done: FND-01, FND-01b, FND-02, FND-03,
FND-04, FND-06, ART-00, SPK-1, SPK-1b, SPK-2, SPK-4, SPK-5, SPK-5b, SPK-7, SPK-11, DES-21, DOC-01,
**ENG-01**. Running: **FND-05** (providers, on ENG-01's `IFate`) and **ENG-01b** (the accounting's
three open findings and the content version). Next: ENG-02 to ENG-04 on ENG-01's interfaces.

## What moved

| | |
|---|---|
| **ENG-01** | [#81](https://github.com/bal7hazar/grimworld/pull/81) merged: five contracts frozen as compiling code, layouts, events, batch codec, per-branch budgets. Instance slots reused, records never zeroed. Merged by the project manager's decision (D-141) with three accounting findings carried to ENG-01b; no security finding. S1 estimated at **$0.556** against $0.50, pending ENG-07's measure of a tick inside a batch |
| **D-141** | ENG-01's escalations decided and written in design/02, 07, 17, 18 and cost-budget.md: 16 goblins an invocation, a goblin's first record weighs 1, an unsplittable action runs, a content version, the belt back on defeat, nothing carried through a gate (reversible by the owner), the full roster keeps goblins in their chunk, `mine` alone |
| **SPK-4** | [#82](https://github.com/bal7hazar/grimworld/pull/82): the client's simulation is a TypeScript mirror checked by vectors; damage edges decided (D-140) |
| **Launcher** | Reference `5d14d89`, **frozen** until the gate of Phase 0 (FND-07 holds M1, N1–N4, L-3) |

## Orchestrators and agents

| Game agent | Model (ran) | State |
|---|---|---|
| FND-05 providers | `claude-opus-5-5` | launching |
| ENG-01b accounting | `claude-sonnet-5-5` | launching |

Budget: slots in `~/orchestrator/slots` (`scripts/agent.sh slots`), 3 in total, game 2.

## Next

1. FND-05 and ENG-01b: review, `[GPT-6-Astra]` audits, merge.
2. ENG-02 (helpers, D-140's table), ENG-03 (registries, the content version measured), ENG-04.

## Decisions needed

None open. Answered: D-141 (ENG-01's merge and escalations).

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
