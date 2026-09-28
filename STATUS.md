# Status

**2026-09-28 21:30 UTC** — written by the game orchestrator `[Opus 5.5] Orchestrateur Grim World (jeu)`.

## Where we are

**Phase 0 — Foundations, native Starknet (ADR-0007).** Done: FND-03, SPK-5, SPK-5b, FND-01,
FND-01b, FND-02, ART-00, SPK-2 (cost), SPK-11 (indexer), **FND-06** (gas tooling), **SPK-1**
(Sepolia). Running: **SPK-7** (chunked maps, Opus 5.5). **Decision requested** of the project
manager on the cost threshold (D-129 point 4). Launcher hardening (#48) in re-audit.

## What moved

| | |
|---|---|
| **SPK-1 merged** | [#45](https://github.com/bal7hazar/grimworld/pull/45): SPK-2's native contracts deployed on Sepolia and measured from the owner's account, 105 transactions, 72.22 test STRK. Expedition **$0.874 / $0.685** at today's mainnet prices: **$0.50 does not hold**; about 1.09M L2 gas of every transaction is account and protocol, more than S1's whole fight budget. p95 to pre-confirmed 2.8 s (met), p50 not decided. `[GPT-6-Astra]` PASS WITH FINDINGS after one fix loop; the two remaining minors fixed by the orchestrator. Secret scan: 0 occurrences of the key or the address anywhere |
| **Cost decision** | [docs/decisions/2026-09-28-sepolia-verdict.md](docs/decisions/2026-09-28-sepolia-verdict.md), sent to the project manager: recommend reopening the queue in fights (DES, before ENG-01), a narrow SPK-1b on the burner class and a paymaster, and no restated threshold yet |
| **FND-06 merged** | [#42](https://github.com/bal7hazar/grimworld/pull/42): `scripts/gas_budgets.py` generates `docs/BUDGETS.md` and per-package `GAS.md`; CI fails on a test without budget, a loose budget, an unreasoned raise, a stale file. `[GPT-6-Sol]` PASS WITH FINDINGS after two fix loops. CAIRO §2: one budget per fuzz or parameterized test (the most expensive case); raises agreed by the orchestrator at review |
| Sepolia account scoped | [#43](https://github.com/bal7hazar/grimworld/pull/43): agents get the account only with `--with-sepolia`; [#48](https://github.com/bal7hazar/grimworld/pull/48) binds it to the brief (in re-audit) |
| Agent budget enforced | [#46](https://github.com/bal7hazar/grimworld/pull/46): the launcher refuses a launch at 3 agents, after I ran a fourth for one minute (FND-06, stopped and resumed). The audit found gaps (a count that failed open, races between orchestrators): #48 fails closed and serialises count and start under `~/orchestrator/agent-launch.lock`, **which the other tracks' launchers should take too** |
| D-132 | No sub-agent publishes; COMMON §4 says so |

## Orchestrators and agents

| Orchestrator | Session | Model (verified) | State |
|---|---|---|---|
| Game | `[Opus 5.5] Orchestrateur Grim World (jeu)` | `claude-opus-5-5` | SPK-7 running; #48 re-audit queued |
| Map library (track LIB) | `[Fable 5.1] Orchestrateur hexmap (lib)` | `claude-fable-5-1` | LIB-04 running |

| Game agent | Unit | Model (ran) | Profile | Started |
|---|---|---|---|---|
| SPK-7 chunked maps | `grimworld-SPK-7-212404` | `claude-opus-5-5` | implement | 21:24 UTC |

Budget (OPERATIONS §3): 3 Grim World agents at a time, audits included. At 21:29 UTC: SPK-7,
hexmap LIB-04, quiver ARC-03a. Load 7.0, 18 GB available.

## Waiting for the owner

| What | State |
|---|---|
| **The registry token reaches every sub-agent.** `SCARB_REGISTRY_AUTH_TOKEN` is in the user-level settings of the machine; the claude CLI injects it into every agent's shell, whatever the launcher does (measured by the library's orchestrator, names only). Profiles deny `scarb publish` as a typed command but cannot stop a program an agent runs. Remedy: take the token out of `~/.claude/settings.json` and keep it where a publication happens (a secret of a GitHub environment with a required reviewer, or a file the owner's own shell reads at release time) | A secret of the owner, used by the owner's other programmes too (D-128). Until then every implement agent is treated as able to publish: small tasks, audited |
| **Secrets reach every sub-agent of every programme on the machine**: since 20:21 UTC the user-level settings hold the Sepolia account's private key beside the registry token and another programme's API key, (the file itself is restricted to its owner since 2026-09-28, mode 600, done by the owner). The owner confirmed on 2026-09-28 that the Sepolia key controls nothing on mainnet: that residual is accepted. The registry token stays in the settings of the machine: publications are decided by the project manager in the owner's name (D-132), no sub-agent publishes, the launchers empty the token in their agents; the residual (a program an agent runs can read the file) is accepted | Secrets and settings of the machine are the owner's (D-128). Nothing is blocked: SPK-1 is unblocked |

Open without urgency: Q-12, the lore premise.

## Next

1. #48: re-audit `[GPT-6-Sol]`, merge.
2. SPK-7: review, audit, merge.
3. FND-05 (with `[GPT-6-Astra]`), SPK-4; then what the project manager decides on the cost
   threshold (a DES on the queue in fights, SPK-1b).

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
| SPK-6 | Real phones: the owner runs the protocol the orchestrator writes |
| Mainnet | An explicit go from the owner, each time (D-116) |

## Decisions needed

**D-129 point 4**, the cost threshold on Sepolia's figures: sent to the project manager
([request](docs/decisions/2026-09-28-sepolia-verdict.md)). G-1 was answered by the owner (D-121: `main` not protected
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
- `sozo`, `katana` and `torii` are still absent (SPK-5); the Sepolia account is in the
  machine's settings since 20:21 UTC (checked by name), given to agents only with
  `--with-sepolia`; the `assets` submodule is not initialised in the
  main checkout (an independent clone of `tiny-swords` is in `~/projects/assets`).

## Not verified

- Latency and cost on mainnet: public data and Sepolia only, no mainnet transaction of ours.
- `origami_hexmap` costs: the library's own benchmarks.
- Phone battery and heat: no measurement exists for any candidate engine.
