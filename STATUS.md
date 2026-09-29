# Status — game track

**2026-09-29 00:35 UTC** — written by the game orchestrator `[Opus 5.5] Orchestrateur Grim World (jeu)`.
The live state of the game track only. The programme, the decisions and what waits for the owner
are in [PROGRAMME.md](PROGRAMME.md), written by the project manager.

## Where we are

**Phase 0 — Foundations, native Starknet (ADR-0007).** Done: FND-01, FND-01b, FND-02, FND-03, FND-06,
ART-00, SPK-1, **SPK-1b**, SPK-2, SPK-5, SPK-5b, **SPK-7**, SPK-11, **DES-21**, **DOC-01**. Running:
**FND-04** (the cost budget ENG-01 designs to; slots read from the Sepolia traces). Next: **ENG-01**
(brief written), FND-05, SPK-4.

## What moved

| | |
|---|---|
| **D-133 and batches** | DES-21 ([#49](https://github.com/bal7hazar/grimworld/pull/49)): fights played on the client and sent in batches; merged after four fix loops with OP-1 open, then answered by D-136 (an unrevealed chunk is wall in the window; the client never waits for a chunk). DOC-01 ([#63](https://github.com/bal7hazar/grimworld/pull/63)) wrote the accepted ADR, glossary and design amendments |
| **SPK-1b** | [#51](https://github.com/bal7hazar/grimworld/pull/51): the burner's fixed part 717,435 L2 gas (1.52× smaller than the owner's account); paymasters cost more; D-133 stands. Expedition under batches of 10, estimated: **$0.73 (S1), $0.54 (S2)**. 76.19 test STRK spent by SPK-1 and SPK-1b. Its sending code is retired. Merged after four fix loops (exception) |
| **SPK-7** | [#50](https://github.com/bal7hazar/grimworld/pull/50): the chunked map adds 720,000 L2 gas per tick with goblins; D-134 (void chunks around locations, corners always wall) |
| **Launcher** | The budget is now **slot locks** ([#60](https://github.com/bal7hazar/grimworld/pull/60), [#66](https://github.com/bal7hazar/grimworld/pull/66)): `~/orchestrator/slots`, kernel locks held while an agent lives, caps per track (game 2, library 1, quiver 1), read-only slot directory. The library and quiver use the same launcher. Re-audit of 033043a running; the CHANGELOG reference follows its pass |
| **Shared machine** | Profiles deny `rm` under `/tmp`, `pkill`, `killall`, `git worktree prune` ([#62](https://github.com/bal7hazar/grimworld/pull/62)); COMMON: sending lives in one module and ends with the task ([#64](https://github.com/bal7hazar/grimworld/pull/64)) |
| Process | My errors tonight, reported: a merge on pending CI (#49, then green); a squash that reverted the project manager's D-136 files (#60, restored by [#65](https://github.com/bal7hazar/grimworld/pull/65)); a `rm -rf /tmp/tmp.*` on the shared machine (no damage found); a sending script run from a session holding the key (nothing sent). Each is a rule in memory and, where it applies, in OPERATIONS or COMMON |

## Orchestrators and agents

| Game agent | Model (ran) | State |
|---|---|---|
| AUD-60, re-audit of the launcher at 033043a | `gpt-6-sol` | running |
| FND-04 budgets | `claude-opus-5-5` | queued, launches in the game's second slot |

Budget: slots in `~/orchestrator/slots` (`scripts/agent.sh slots`), 3 in total, game 2.

## Next

1. FND-04: review, `[GPT-6-Astra]` audit, merge.
2. ENG-01 on FND-04's budgets ([brief](docs/briefs/ENG-01-core-interfaces.md)).
3. The launcher's CHANGELOG reference after the re-audit passes.
4. FND-05 (with `[GPT-6-Astra]`), SPK-4.

## Decisions needed

None open. Answered tonight: D-133 (batches), D-134 (chunk borders), D-135 (quests), D-136 (unrevealed
chunks), the slot locks and their transition, the exceptions for PR 48, DES-21 and SPK-1b.

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
