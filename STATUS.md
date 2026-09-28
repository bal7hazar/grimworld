# Status — game track

**2026-09-28 22:45 UTC** — written by the game orchestrator `[Opus 5.5] Orchestrateur Grim World (jeu)`.
The live state of the game track only. The programme, the decisions and what waits for the owner
are in [PROGRAMME.md](PROGRAMME.md), written by the project manager.

## Where we are

**Phase 0 — Foundations, native Starknet (ADR-0007).** Done: FND-03, SPK-5, SPK-5b, FND-01,
FND-01b, FND-02, FND-06, ART-00, SPK-2, SPK-11, SPK-1. In review: **DES-21** (played batches,
D-133), **SPK-7** (chunked maps), **SPK-1b** (fixed part of a transaction), launcher PR #48. Next:
FND-05, SPK-4, then ENG-01 once DES-21 and SPK-7 are merged.

## What moved

| | |
|---|---|
| **D-133** | The project manager accepted the three points: fights played on the client and sent in batches (DES-21), SPK-1b added, $0.50 kept as the target |
| DES-21 | [#49](https://github.com/bal7hazar/grimworld/pull/49): design/02 and design/11 say what a batch is, its size (weight 10, 40M L2 gas as a target ENG-01 proves), when it leaves, unsent actions, reorgs and reverted transactions, reconciliation by views at the receipt's block, the entrypoint `play(instance_id, adventurer_id, sequence, actions[1..10])`, and the ENG-01 and CLI-03 lists. `[GPT-6-Astra]` FAIL (6 majors) → fix loop 1 done; re-audit running |
| SPK-7 | [#50](https://github.com/bal7hazar/grimworld/pull/50): the chunked map adds **760,000 L2 gas** to the worst tick (+14.7 %); reveal of 3 chunks 5.84M; R-12 partly realised, not a blocker. `[GPT-6-Astra]` FAIL (a Python/Cairo flood mismatch with no targets; the fallback unmeasured) → fix loop 1 running; the fallback stays unmeasured by scope amendment (D-133 takes the cost) |
| SPK-1b | [#51](https://github.com/bal7hazar/grimworld/pull/51): an OpenZeppelin burner's fixed part is 717k L2 gas against 1.09M for the owner's account (1.5×); the fee transfer (455k) bounds any account at about 2.2×; paymasters cost more (1.77× our relayer, 3.35× AVNU's). **D-133's reversal condition is not met.** 44 transactions. Audit queued |
| Launcher | [#48](https://github.com/bal7hazar/grimworld/pull/48): Sepolia grant bound to the committed brief, the agent count fails closed and runs under a shared launch lock. Past three fix loops: merge escalated to the project manager |
| Process | Two misses of mine, both without harm: a fourth agent for one minute (now refused by the launcher), and a queue run from a worktree I had switched (launches now run from `orch-launcher`, a worktree on main) |

## Orchestrators and agents

| Game agent | Unit | Model (ran) | State |
|---|---|---|---|
| SPK-7 fix loop 1 | `grimworld-SPK-7-223327` | `claude-opus-5-5` | running |
| DES-21 re-audit | codex, detached | `gpt-6-astra` | running |
| SPK-1b audit | codex, detached | `gpt-6-astra` | queued |

Budget (OPERATIONS §3): 3 Grim World agents at a time, enforced by the launcher. At 22:45 UTC:
SPK-7, AUD-49, quiver ARC-03b. Load 5.6, 20 GB available.

## Next

1. DES-21 and SPK-1b audits, SPK-7's fix loop and re-audit; merge each on a passing audit.
2. #48 on the project manager's answer.
3. FND-05 (with `[GPT-6-Astra]`), SPK-4; ENG-01's brief once DES-21 and SPK-7 are merged.

## Decisions needed

| # | What | Sent |
|---|---|---|
| 1 | Merge launcher PR #48 now and re-audit after, or hold it for a fourth re-audit ([report](docs/reports/PR-43-46-48-launcher-audit-gpt-6-sol.md)) | 2026-09-28 22:40 |
| 2 | The other tracks' launchers take `~/orchestrator/agent-launch.lock` around count and start | same message |

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
