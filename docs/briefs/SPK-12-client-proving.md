# SPK-12 — Client-side proving against L2 batches

> D-161 §3 (`docs/decisions/2026-09-29-cbt-02-tick-cost.md`) and D-172 §3
> (`docs/decisions/2026-10-01-spk-15-levers.md`): the one lever that changes the order of magnitude
> of the expedition's cost. A spike, lent to track CV (ORCH-client-visual §8): nothing of it merges
> into the contracts or the client. **Reopening ADR-0001 is the owner's decision, on this report.**

## Agent
Title: `[Opus 5.5] SPK-12 client-side proving` · Profile: implement · Branch: `spike/spk-12-client-proving`
· Machine: the Mac (`nexus run --require browser`; the proving is measured on its 12 cores and 64 GB)

## Goal
After this spike the owner can decide, on figures, whether the expedition stays **L2 batches as
designed** (ADR-0001 option A, D-133: played actions sent in batches of 10 ticks) or moves to
**proving the deterministic segments on the client and settling one proof a segment** (ADR-0001
option D, SNIP-36), with randomness (entry, reveal, loot, brewing: the Fate actions of ADR-0002 and
design/02) staying as L2 transactions. The comparison is made **on our figures**, and every number
is marked M (measured), D (derived) or E (estimated), as cost-budget.md does.

## Context
- **The question's figures.** S1 (300 actions, D-129's $0.50 threshold = 567.8 M L2 gas, 1M L2 gas =
  $0.000881) now runs at **≈ 663 M L2 gas ≈ $0.584 (E)** on ENG-01's per-tick estimate
  (`STATUS.md`, *S1's running estimate*); the per-tick target is 1,469,435 L2 gas inside a batch.
  SPK-15 (`docs/decisions/2026-10-01-spk-15-levers.md`, `spikes/SPK-15/README.md`) measured the
  **worst tick, everything counted, at 22.8 M (15.5×) as it stands and 16.4 M with every
  engineering lever**; the representative tick (no hit, no application) 1,065,651; the map library's
  share of a worst tick 1.06–1.11 M. ENG-07 will define a representative *fight* tick; until then,
  take CBT-02's representative and worst ticks and SPK-15's table as the two ends. CBT-02d's
  re-proved bound 3,447,872 a tick inside a batch (`docs/reports/CBT-02d-tick-levers.md`).
- **The design of batches**: design/02 §*Planned queues and played batches* (D-133): a batch of 10
  ticks a transaction, a Fate action sent alone after the batch before it is confirmed, gates and
  travelling back alone; the sequence number; reorgs. ADR-0002 for Fate; D-50 (randomness only at
  reveal moments); D-64 (every chunk generated at reveal from a fresh random word); D-80 (co-op:
  every action of any member ticks the world); design/08's M-1…M-6.
- **The reference that proves today**: the owner's `slingfall` (`github.com/bal7hazar/slingfall`,
  a clone on the Mac beside the project's clones; read it at its `main`, name the commit, **never
  write in it**). Read `docs/proving.md` in full: the local Stwo proving of a standalone executable
  (`tools/prove/`, stwo-cairo at `467d5c6`, `canonical_small`, the two patches, the measurements
  P1: steps, wall time, peak RSS, proof bytes), the SNIP-36 tier (contract v3, `submit_chunk`,
  `finalize`, the protocol's facts), and its **cost sheets** (W3, B6): the protocol's flat
  **75,000,000 L2 gas a proof** on any Invoke carrying proof facts, `submit_chunk` 0.84–1.20 M a
  link, `finalize` 7–9 M, a virtual transaction budgeted at 1.0e9 L2 gas (about 111–150 L2 gas a
  Cairo step), no prover answering PROOF2 today, hence the proving time of a virtual transaction
  **not measured by anyone**. Also `docs/research/07-split-game-step.md` (the chain of virtual
  transactions) and `docs/contract-v3.md`.
- **ADR-0001** (`docs/architecture/ADR-0001-execution-layer.md`): option D as priced in September
  (~75 M L2 gas a 500 KB proof, "seconds per proof on phones for a trivial benchmark", no same-
  transaction VRF), the owner's concern (no decentralised randomness). **ADR-0003** (the client:
  mobile first, rendered on demand, the power rules of design/11). **SPK-4**
  (`docs/research/SPK-4-parity.md`): option (b), the Cairo code run in the client through cairo-vm
  compiled to WebAssembly, kept as the vector oracle; what proving on the client would reuse of it.
- **The tick's code**: `contracts/logic` (`TickLibrary`, CBT-02 to CBT-02f; CBT-04 and CBT-03a are
  on their branches, not merged); ENG-01's interfaces (`docs/architecture/ENG-01-interfaces.md`,
  §9.2 the per-tick budget); `docs/architecture/cost-budget.md` for the prices of a transaction.
- COMMON.md; CAIRO.md §2 for the spike's own tests; D-154 (every figure from two clean runs).

## Scope
- In, under `spikes/SPK-12/` and a research note `docs/research/SPK-12-client-proving.md`:
  1. **The model of an expedition in segments.** From design/02, cut S1 (300 actions; design/02's
     count of batches, Fate actions, gates, reveals) into deterministic segments bounded by the
     Fate actions and the gates: how many segments, how many ticks each (a distribution, from the
     same assumptions as ENG-01 §10.2 and S1's table, stated), what each boundary needs from L2
     (the fresh word of a reveal, D-64; the entry draw; loot). The same for a co-op expedition (D-80:
     several members' actions tick one world; who proves what).
  2. **The cost side by side (D or E, from M).** For S1 and for a fight-heavy expedition (SPK-15's
     worst tick): L2 batches as designed (STATUS's figures), against proofs: the number of proofs
     × 75 M + the links + `finalize`-like settlement + the L2 Fate transactions, at mainnet's
     prices of cost-budget §1. The lever is the number of proofs: what a proof of a whole segment
     holds (the 1.1e9 L2 gas cap of a virtual transaction, slingfall's measured ~111–150 L2 gas a
     step), and so how many proofs a segment really needs when its ticks are counted in Cairo
     steps (step 3). State the break-even: at how many ticks a segment do proofs beat batches.
  3. **Proving time measured on the Mac (M).** A standalone executable of the tick (an
     `[executable]` package in the spike, calling `grimworld_logic` by path as SPK-15 does, on
     fixture content and states copied from CBT-02's tests with the source file and commit named)
     run with `scarb execute`, then proved with Stwo's `run_and_prove` as slingfall does
     (`canonical_small`, binary proofs, `--verify`): steps, wall time, peak RSS, proof bytes, for
     one representative tick, one worst tick, and a batch of 10 and of as many ticks as fit the
     memory of the machine. Two clean runs each. Reuse slingfall's built binaries if
     `tools/prove/vendor/` holds them on this machine; otherwise vendor stwo-cairo at the same rev
     with the same two patches **inside the spike's worktree** (an ignored folder) and build it
     there; `rustup` may install the nightly toolchain stwo-cairo pins (a per-user toolchain that
     slingfall already uses on this machine); nothing else is installed. If the standalone proof
     cannot be made (the executable target, a builtin, the range-check limit), say exactly where
     it stops and measure the steps and the execution instead.
  4. **A phone, estimated (E).** From the Mac's figures and slingfall's P1 (4 vCPU, 16 GB: peak RSS
     6–15 GiB), the proving time and memory a phone would need, with the assumption stated (the
     ratio of a phone's core to the Mac's, the memory a mobile app may take); what proof size the
     phone uploads; what this means against ADR-0003's power rules and SPK-6's thresholds. A
     prover in the browser or in a Capacitor shell: what exists (Stwo's WebAssembly or native
     targets, as found and dated), nothing assumed.
  5. **Verification on the chain (D).** What the chain verifies and at what cost (slingfall's
     `submit_chunk` and `finalize`, the facts of SN1 §4), what the game's contracts would have to
     become: the tick's library as the proved program, the batch's results as the proof's public
     output through the results interface (ADR-0001's two domains), the program's hash pinned,
     the binding between segments (slingfall's chunk binding), what ENG-01's `play` keeps.
  6. **What it does to the design**: co-op (D-80: one proof per member, or one per world; who pays;
     a member's segment interleaved with another's), the fresh word of each reveal (D-64: the
     proof's inputs must include a word the proof could not choose; the ordering of proof,
     reveal and the next segment; latency between them), the client (SPK-4 option b: the same
     Cairo code executed, then proved; what the client needs beyond the mirror), cheating (what a
     proof prevents, what it does not: choosing inputs, replaying, withholding a segment,
     grinding a Fate draw across proofs, the sequence number).
  7. **A recommendation** for the owner: keep L2 batches, move to proofs, or a mixed design (which
     segments are proved), with what would reverse it and what the next step would be (a spike
     that proves on a phone; a design change; a contract lot), and the questions only the owner
     can answer.
- Out: any change to `contracts/`, `client/`, a design document or an ADR (proposals go in the
  note); no Sepolia, no prover service, no transaction sent anywhere; no Atlantic or hosted prover
  account (the owner's).
- Allowlist: `spikes/SPK-12/**`, `docs/research/SPK-12-*`, `REPORT.md`. Anything else is an
  escalation.

## Acceptance criteria
- [ ] AC-1 The segment model of S1 and of a co-op expedition, with its assumptions stated and
      traced to design/02 and S1's table.
- [ ] AC-2 The cost table, batches against proofs, for S1 and for a fight-heavy expedition, every
      figure M, D or E with its source; the break-even in ticks a segment.
- [ ] AC-3 The tick proved on the Mac: steps, wall time, peak RSS, proof bytes, two clean runs each,
      verified; or the exact point where proving stops, with the steps measured.
- [ ] AC-4 The phone estimate, the verification side, the design consequences (6) answered one by
      one, each with what is known and what is assumed.
- [ ] AC-5 The recommendation, its reversal condition, the owner's questions; the note in
      `docs/research/SPK-12-client-proving.md`; CI green; nothing outside the allowlist.

## Audits
`[GPT-6-Astra]` on the report (cost and a contested design decision, OPERATIONS §6; through
`nexus audit`, queued for Codex's reset on 2026-10-04 13:36 UTC); a Claude-side lens may run
before it (D-170). The review of the pull request by `nexus review`.

## Verification
```
scarb --manifest-path spikes/SPK-12/Scarb.toml build
(cd spikes/SPK-12 && snforge test)
```
plus the spike's own `prove.sh` or `prove.py`, whose output is committed as text (never a proof file).

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the segment model, the cost table, the proving
measurements with their commands and real output, the answers of (4) to (6), the recommendation;
the research note holds the same for the archive.
