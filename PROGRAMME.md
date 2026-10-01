# Programme

**2026-09-29, 19:40 UTC: PAUSED** by the owner for the app account's weekly quota (95 %; reset
**2026-09-30 14:00 UTC**). Written by the project manager `[Opus 5.5] Chef de projet Grim World`
(session `local_3ab2583a`), which took over at 09:45 UTC ([handoff](docs/briefs/PM-handoff-2026-09-29.md)).
The live state of each track is in its own status file, each rewritten at the pause with a
section *Pause 2026-09-29* (every open task: branch, pull request, commit, state, resume command,
next step). This file says where the programme is, what was decided and what waits for the owner.

## The pause

Each orchestrator launches nothing new, lets its running agents and audits finish, writes its
*Pause* section, merges it and ends its turn. Nothing resumes before the owner's or the project
manager's message after the reset.

**The project manager's first steps at the reset**
1. `get_usage`; `git fetch`; read the four status files' *Pause* sections and `gh pr list` of the
   three repositories; the machine (`systemctl --user list-units`, load).
2. Wake the orchestrators (one message each, their session ids in the handoff; track CV through the
   owner) with the next step their *Pause* section names.
3. Ask the owner again what waits for the owner (below).

## Tracks

| Track | Repository | Orchestrator (model verified) | Where it is at the pause | Next |
|---|---|---|---|---|
| Game | `bal7hazar/grimworld` | `[Opus 5.5]` `local_06f24ad6` | Phase 1. Merged today: ENG-06, DES-04, CBT-01, FND-08, FND-09, CBT-08a, DES-06's decisions (D-148 to D-160). **CBT-02** (the tick) running or in audit, its cost escalated (D-161). S1 estimated at **$0.585** before the tick | CBT-02's merge, then **CBT-02b**; DES-06's last pass; ENG-02 on `hexx` rc.1, ENG-05 on rc.2; ENG-R1 after ARC-07 |
| Map library (LIB) | `bal7hazar/hexx-cairo` | `[Opus 5.5]` `local_2e7bf177` | L-M1: N-3, N-8 merged and measured (1.06M to 1.11M of a worst tick). M1-T4b (N-4) running | M1-T2 → M1-T3 → M1-T6 → **rc.1** (ENG-02) → M1-T7 → M1-T8 → **rc.2** (ENG-05) → M1-T5 → 0.1.0; each candidate a publication request (D-132; the owner confirms the delegation in that session first) |
| Packages (ARC) | `bal7hazar/quiver` | `[Opus 5.5]` `local_a86e4778` | ARC-07a merged: `quiver_quest` 0.2.0 on the pattern (no `logic/`, tracking chosen by the consumer) | **The owner's verdict on ARC-07a**, then ARC-07b (`quiver_achievement` 0.2.0) |
| Client visual (CV) | `bal7hazar/grimworld` (`client/app`, `tools/art`, lent tasks) | A local orchestrator on the owner's Mac (D-146), relayed by the owner | ART-02, CLI-03a, SPK-6a, CV-01 (launcher), IDX-01a (unblocked by #148); lent: IDX-01, SPK-13 (non-reproducible builds, D-154), SPK-12 (client-side proving, D-161) | Its `docs/status/client-visual.md` |

Budget: 3 agents at a time across the three tracks, audits included (D-118); caps: game 2,
map library 1, `quiver` 1; the game comes first through a waiting marker (OPERATIONS §3).
The three tracks hold their slots through the launchers' locks.

The three launchers hold their agents by slot locks and are on the same reference, commit
`2628b21` of the game's launcher, audited by `[GPT-6-Sol]`. Its scope is stated: it guards
against accidental over-launch and fails closed; it does not guard against a deliberate act
of the same Unix user.

## Decided on 2026-09-28 and 2026-09-29

| # | Decision | By |
|---|---|---|
| D-119 | `hexx` ported in full in `hexx-cairo`; `origami_hexmap` decommissioned at the end | Owner |
| D-120 | The window follows the adventurer, 15 × 16, not stored | Owner |
| D-121 | `main` is not protected for now | Owner |
| D-123 | Native Starknet contracts, without Dojo (ADR-0007). Measured since: native costs 0.26× to 0.58× Dojo | Owner |
| D-124, D-125 | The Arcade packages rewritten natively in one repository, `quiver` | Owner |
| D-126, D-127 | The porting plan of `hexx` accepted; the flood of the tick stops at 15 layers | Owner |
| D-128 | The project manager goes ahead with its own recommendations and reports | Owner |
| D-132 | Publications on scarbs.xyz are decided by the project manager in the owner's name | Owner |
| D-129, D-133 | The threshold of $0.50 for 300 actions stays the target; it does not hold with one action per transaction ($0.69 to $0.87 on Sepolia); played actions are sent in batches | Project manager |
| D-130 | The indexer is our own | Project manager |
| D-138 | **First publication**: `quiver_quest` 0.1.0 on scarbs.xyz, after the project manager's own checks; the registry lists it with the checksum of the go | Project manager, in the owner's name |
| D-179 | Five readings of one hit confirmed; a sleeping target neither blocks nor evades its first hit | Project manager |
| D-178 | CLI-03c: hubs and transitions on fixed data, for the owner's eye | Project manager, at the owner's request |
| D-177 | An audit is the exception; the review is the routine gate; OPERATIONS §6 names the few kinds that need one | Owner |
| D-176 | The compile drift explained (rayon thread order moves `withdraw_gas` in a cycle): measured and declared builds single-threaded; the upstream issue at the owner's go | Project manager |
| D-175 | Nobody waits for Codex: reviews on Sonnet, audits on Opus while it has no quota | Owner |
| D-174 | CAIRO.md's bitmaps on `hexx`; ENG-02's geometry edges (a wall at either end blocks sight) | Project manager |
| D-173 | `hexx` 0.1.0-rc.1 published (ENG-02's content); ENG-02 unblocked | Project manager, in the owner's name |
| D-172 | The tick's engineering levers decided; a batch stops before a heavy tick; the design levers and the per-tick budget put to the owner | Project manager |
| D-171 | SPK-15: the tick's levers before CBT-05; the worst tick 6.51M, R-2 in front of the owner | Project manager |
| D-170 | CBT-04 and CBT-03a while Codex is out; merged after ENG-R1a | Project manager |
| D-169 | A snapshot stales on a rules epoch or a flattening-input change, not on any content update (CBT-02f) | Project manager |
| D-168 | The snapshot flattened once at `set_build` and stored with the adventurer (CBT-02e); `enter` copies it | Project manager |
| D-167 | `quiver_quest` 0.2.0 accepted by the owner; unit tests beside their code, every Cairo library | Owner |
| D-166 | The flattening's bounds checked at registration (CBT-02c); CBT-02d's levers before ENG-07; the batch's weight from the proved worst tick | Project manager |
| D-165 | Hexagonal chunks of 251 tiles studied (SPK-14); **the chunks stay 15 × 15**, cost efficiency first | Owner |
| D-164 | The compile drift: a gate with the two observed builds, exact; no red merge | Project manager |
| D-163 | CBT-02 merged, its cost-bound findings carried to CBT-02b | Project manager |
| D-162 | The standard roles of Nexus: OPERATIONS.md reduced to the project's specifics; Codex reviews every pull request; track CV on `nexus` | Owner |
| D-161 | The worst tick is above its target (about 2.1M to 2.5M against 1.47M): CBT-02b now; SPK-12 on client-side proving, on the Mac | Project manager |
| D-160 | DES-06's 33 questions decided; strength capped by level | Project manager |
| D-159 | CBT-02 next with the tick's cost as its budget; DES-06 beside it. S1 at $0.585 (E) | Project manager |
| D-158 | `set_build` reads less (item data copied at creation); the belt's worst case accepted (+$0.002 on S1) | Project manager |
| D-157 | CBT-01's open questions decided; statistics' bounds to DES-06 | Project manager |
| D-156 | The funder's caps for Sepolia playtests (test tokens); mainnet caps stay the owner's | Project manager |
| D-155 | DES-04's 43 combat rules accepted; a last narrow pass, then CBT-01 | Project manager |
| D-154 | Non-reproducible Cairo builds: SPK-13 on the Mac, N-3 first on the library's slot | Project manager |
| D-153 | The indexer's needs from the game (a `[lib]` target, first) and its CI; the market key: strict rarity | Owner |
| D-152 | Android dropped for now; phone tests and the Capacitor shell moved to the end; CLI-01 for the browser first | Owner |
| D-151 | SPK-6 in two steps; the Capacitor shell in track CV; the owner's phones and thresholds | Owner |
| D-150 | The game's slots while the engine chain waits: DES-04 then CBT-01; FND-08, the funder | Project manager |
| D-149 | The Mac takes tasks of the game without Sepolia, under track CV's orchestrator: IDX-01 first; 5 agents on the Mac (owner) | Project manager; budget by the owner |
| D-148 | ENG-06: three measured budgets on the lifecycle; a gate is used by standing on its anchor tile; armor flat until BAL-01 | Project manager |
| D-147 | The owner's review of ARC-06: no `logic/` folder; tracking a model is optional, chosen by the consumer | Owner |
| D-146 | **Track CV** on the owner's Mac: the client's visual work; ART-1 answered provisionally | Project manager |
| D-143 | **The owner's rule on the organisation of Cairo code**: Arcade's layering, functions scoped in traits, models with their storage and their event, the store emitting on write | Owner |
| D-142 | **Second publication**: `quiver_achievement` 0.1.0, event mode only; the registry lists it with the checksum of the go; both packages consumed together by a fresh project | Project manager, in the owner's name |
| D-141 | ENG-01 merged; its design escalations decided (caps of a batch, belt credited back on defeat, nothing carries through a gate, content version) | Project manager |
| D-140 | A rule never panics on a legal action; percent modifiers of damage are summed, not multiplied; the client mirrors the rules in TypeScript, checked by vectors from the Cairo code | Project manager |
| D-139 | `quiver_achievement` 0.1.0 in event mode only: its storage mode would cost about 200M gas in the worst call | Project manager |
| D-137 | The MVP's burners send directly, funded by the game; no paymaster before version 1 | Project manager |
| D-136 | An unrevealed chunk is wall in the window; the ADR amendments of DES-21 (played batches) accepted | Project manager |
| D-134 | Void chunks around every location; chunk corners are wall. SPK-7 measured the chunked map at +720k gas per tick with goblins (+14 %) | Project manager |
| D-131 | The API of `quiver_quest` and `quiver_achievement` accepted | Project manager |
| D-135 | `quiver_quest` bounds what a player holds (4 quests), not what a task reaches: worst call about 5.6M gas instead of 704M | Project manager |
| — | LIB-03 and LIB-04 merged after more than three fix loops, their open findings carried as tasks | Project manager |

Every decision has its file in [docs/decisions/](docs/decisions/) and its row in
[CONTEXT.md](CONTEXT.md) §6.

## Waiting for the owner

**At the pause**:
0a. **The expedition's cost (SPK-15, D-172)**: a worst tick everything counted is 22.8M, 16.4M with the engineering levers, about 11.8M with the design levers too, against 1.47M; the design levers (fewer awake goblins, a bomb's targets) recommended *not now*, judged on ENG-07's representative fight tick; the threshold of $0.50 on L2 alone is not reachable for a fight-heavy expedition: SPK-12 (client-side proving) is the structural answer, and reopening ADR-0001 or restating the threshold with the business model is the owner's.
1. ~~The verdict on `quiver_quest` 0.2.0~~ given (D-167); next: the mapping Arcade → quiver to read, then ENG-R1's first lot and ARC-07b.
2. **D-152 confirmed**: the phone tests at the end, no Android for now (a text sent later said the contrary, the one of D-151; D-152 is kept).
3. On SPK-12's report: whether ADR-0001 (L2 only) is reopened for client-side proving.
4. **The go to file the compiler issue** at `starkware-libs/cairo`: SPK-13 has the cause and a minimal case (`spikes/SPK-13/issue-draft.md`, #252), D-176.

**The owner's review of the next iterations of code on the pattern of D-143**: the reference model of ARC-06, then the first lots of ARC-07 and ENG-R1, until nothing is left to say; autonomy after that.

| Open, without urgency | Needed by |
|---|---|
| Q-12: the Arcanist needs a sprite to commission, or the Cleric takes its place in the MVP | Phase 2 |
| The owner's reaction to the lore premise | LORE-01 |
| The business model (Q-10): an active player costs the game about $3.5 to $4.7 a day at today's figures, before batches | Before mainnet |
| Art: the size of goblins on screen (ART-1), the slinger's sprite (ART-2) | CLI-03, ART-01 |

## Risks watched

| Risk | State |
|---|---|
| The cost of an expedition (R-2) | **Likely, worsening** (D-171): the worst tick about 6.51M with conditions and damage (4.43× the 1.47M target), before the executor; S1 above $0.585. Engineering levers measured by SPK-15 (D-171) and ENG-07's batch; the design levers and the threshold itself are the owner's; SPK-12 (client-side proving) on the Mac is the other answer |
| Sessions and agents share one machine and one user with the owner's other programmes | Incident of 2026-09-29, 00:02 UTC: a wildcard deletion in `/tmp` by the game orchestrator; no damage found. Rule in OPERATIONS §3: delete and kill only what you created, by exact path and pid |
| Secrets reach every agent of the machine | The launchers empty them in their agents; the settings file is restricted to its owner; the residual is accepted |
| Audits that need four passes (LIB-03, LIB-04, SPK-2) | Tasks cut smaller; the rule of three loops applied by the project manager |
| The game waits for the library (R-18) | SPK-7 runs on `origami_hexmap` 1.8.0; LIB-05 starts with what the tick needs |
