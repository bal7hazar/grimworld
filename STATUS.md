# Status

**2026-09-28 20:55 UTC** — written by the game orchestrator `[Opus 5.5] Orchestrateur Grim World (jeu)`.

## Where we are

**Phase 0 — Foundations, native Starknet (ADR-0007).** Done: FND-03, SPK-5, SPK-5b, FND-01,
FND-01b, FND-02, ART-00, **SPK-2** (cost), **SPK-11** (indexer). Running: **FND-06** (gas tooling,
Sonnet 5.5). **SPK-1 unblocked** (the owner's Sepolia account, 20:21 UTC): first at the next free
slot, with `--with-sepolia`; the budget of 3 is full (FND-06, hexmap LIB-04, quiver ARC-02). Then
the `[GPT-6-Sol]` audit of #43, SPK-7, FND-05, SPK-4.

## What moved

| | |
|---|---|
| **SPK-2 merged** | [#25](https://github.com/bal7hazar/grimworld/pull/25): native worst tick under D-127 **5.16M L2 gas** (0.27× Dojo); a 300-action expedition **$0.69 to $0.93** natively ($1.21 to $2.83 on Dojo): ADR-0001's $0.50 does not hold on the local node's figures. `[GPT-6-Astra]` PASS WITH FINDINGS after three fix loops. Decided by the project manager: **D-129**, the threshold stays the target, SPK-1 on Sepolia first |
| **SPK-11 merged** | [#31](https://github.com/bal7hazar/grimworld/pull/31): our own indexer, reorg-safe (no stale answer on restart, live or mid-read), nine events for ENG-01. `[GPT-6-Sol]` PASS after two fix loops. Decided: **D-130**, our own indexer (IDX-01, IDX-02) |
| Sonnet 5.5 | [#33](https://github.com/bal7hazar/grimworld/pull/33): `sonnet` launches `[Sonnet 5.5]`; a resume needs its launch record and the same model; `new` needs a closed task |
| Secrets | [#38](https://github.com/bal7hazar/grimworld/pull/38): every agent runs with the registry token emptied; reading `~/.claude`, printing it, `env`, `scarb publish` denied. Residual (an interpreter can read the same user's settings file) sent to the project manager for the owner |
| Sepolia account | [#43](https://github.com/bal7hazar/grimworld/pull/43): the launcher empties the account's variables for every agent unless launched with `--with-sepolia` (the claude CLI would otherwise hand them to all). [SPK-1 brief](docs/briefs/SPK-1-sepolia.md): the agent deploys and measures with the account, by name only, chain id checked before sending, at most 70 measured transactions |
| D-131 | quiver gate A-G1: an instance snapshots up to 16 task ids at entry and reports them in one aggregated call; an ENG-01 input (PLAN row) |
| Process | A `gh pr checks … \| tail -1` chain went on after a failed check (no merge followed); every merged PR was verified green; checks are now read by their exit code |

## Orchestrators and agents

| Orchestrator | Session | Model (verified) | State |
|---|---|---|---|
| Game | `[Opus 5.5] Orchestrateur Grim World (jeu)` | `claude-opus-5-5` | FND-06 running |
| Map library (track LIB) | `[Fable 5.1] Orchestrateur hexmap (lib)` | `claude-fable-5-1` | LIB-04 running |

| Game agent | Unit | Model asked | Profile | Started |
|---|---|---|---|---|
| FND-06 gas tooling | `grimworld-FND-06-202925` | `claude-sonnet-5-5` | implement | 20:29 UTC |

Budget (OPERATIONS §3): 3 Grim World agents at a time, audits included, across the game, the
map library and quiver: 1 slot of the game's own, 1 shared. At 20:29 UTC: LIB-04, a quiver
audit, FND-06. Load 3.9, 22 GB available.

## Waiting for the owner

| What | Why only the owner |
|---|---|
| **The registry token reaches every sub-agent.** `SCARB_REGISTRY_AUTH_TOKEN` is in the user-level settings of the machine; the claude CLI injects it into every agent's shell, whatever the launcher does (measured by the library's orchestrator, names only). Profiles deny `scarb publish` as a typed command but cannot stop a program an agent runs. Remedy: take the token out of `~/.claude/settings.json` and keep it where a publication happens (a secret of a GitHub environment with a required reviewer, or a file the owner's own shell reads at release time) | A secret of the owner, used by the owner's other programmes too (D-128). Until then every implement agent is treated as able to publish: small tasks, audited |
| **Secrets reach every sub-agent of every programme on the machine**: since 20:21 UTC the user-level settings hold the Sepolia account's private key beside the registry token and another programme's API key, (the file itself is restricted to its owner since 2026-09-28, mode 600, done by the owner). The owner confirmed on 2026-09-28 that the Sepolia key controls nothing on mainnet: that residual is accepted. Still asked of the owner: where the registry token lives | Secrets and settings of the machine are the owner's (D-128). Nothing is blocked: SPK-1 is unblocked |

Open without urgency: Q-12, the lore premise.

## Next

1. FND-06: audit, merge.
2. SPK-7 (Opus 5.5, flood at 10/15/20 layers and unlimited, D-127), FND-05 (with
   `[GPT-6-Astra]`), SPK-4; one at a time within the budget.
3. SPK-1 when the owner provides the Sepolia credentials.

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
