# SPK-13 — Builds of the same sources that differ (Scarb 2.19.4)

> D-154 and D-164 (`docs/decisions/2026-09-29-compiler-determinism.md`). A diagnostic spike, lent to
> track CV (ORCH-client-visual §8): it reproduces, diffs and minimises; it changes nothing in the
> contracts or the library. **Filing an upstream issue is the owner's go**: the spike prepares it as
> a file.

## Agent
Title: `[Opus 5.5] SPK-13 compiler determinism` · Profile: implement · Branch: `spike/spk-13-compiler-determinism`
· Machine: the Mac (`nexus run --require browser`), arm64; the VPS run (x86_64) is the orchestrator's
with the spike's script after the pull request (see *Scope* 5).

## Goal
After this spike the project manager knows **why two builds of one commit give two Sierra programs**
(and so two class hashes and two gas figures), whether it is **our code, our cache, the toolchain or
the platform**, and holds a **minimal program** that shows it and a **draft issue** the owner can
file. D-164's narrow exception (two recorded builds of one class) is lifted when the cause is known.

## Context
- **The facts, the library's** (`bal7hazar/hexx-cairo`, read from a clone **at commit `310b5f1`**,
  `origin/main` on 2026-10-01; never a copy of its code into this repository, never a write in it):
  - `docs/reports/LIB-05-M1-T1c-REPORT.md`, *Fix loop 1* and after: four builds of the same sources
    gave four hashes of the compiled test files; one measured 0.22–0.62 % more gas on 42 tests, all
    through `Digger::dig` (`crates/hexx/src/generators/digger.cairo`); in CI +0.5 to +1.3 % three
    times.
  - `docs/reports/LIB-05-M1-T2-REPORT.md`, *Orchestrator's note, the class size of HexxGenerators*
    and `gas/bytecode.builds`: CI (`ubuntu-latest`, `software-mansion/setup-scarb` v1.6.2, Scarb
    2.19.4) **always** builds `HexxGenerators` of `crates/consumer` at **27,101** Sierra felts
    (1,396,211 bytes); clean local builds on the VPS (asdf, Scarb 2.19.4) **always** give **27,092**
    (1,395,788 bytes); CASM 49,375 both times. **D-164's fact**: the value follows the build
    environment, not chance. The library's CI keeps per-run artefacts (`artifacts-<run>.sha256`,
    `versions.txt` with the Sierra compiler's version: `.github/workflows/ci.yml` of the library).
- **The game's contracts**: `contracts/` (the workspace: `persistent`, `ephemeral`, `logic`, `seed`),
  built by `scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build`;
  `contracts/tools/class_sizes.py` prints each class's Sierra bytes and felts and CASM felts from
  `contracts/target/dev/*.starknet_artifacts.json`; the CI's `class sizes` step prints the same
  table in the log of the `contracts` job of every pull request (yours included: a second
  environment to compare, read with `gh pr checks` and the run's log, or asked of the orchestrator).
  D-154 §4: deployments record class hash and commit.
- **The toolchain**: `.tool-versions` (Scarb 2.19.4, starknet-foundry 0.61.0),
  `scripts/setup-toolchain.sh` (asdf, pinned sha256 of the release archives); the library's
  `.tool-versions` says the same. `[cairo] sierra-replace-ids = true` in the spikes' manifests;
  check what the library's and the game's manifests set (`sierra-replace-ids`, `inlining-strategy`,
  profiles) and what differs between a `dev` build and a test build.
- **Hypotheses to tell apart** (each with the experiment that settles it): the compiler binary
  (same release archive on both? its sha256, `scarb --version`, the Cairo compiler and Sierra
  versions it reports), the platform (arm64 against x86_64: the Mac against the VPS and CI), the
  cache (`~/.cache/scarb`: the registry's and git dependencies' checkouts, `Scarb.lock`, the
  corelib copy), the sources' order on disk or an unordered iteration in the compiler (then it
  would vary between runs in one environment, which D-164's fact denies), inlining or
  optimisation heuristics that read something of the environment (threads, memory, the path
  length), a dependency resolved differently (`Scarb.lock` present or not, `scarb update`).
- COMMON.md; CAIRO.md §2 for the spike's own tests; the machine rules of OPERATIONS §3 (heavy
  builds through the lock; the Mac is the owner's, delete only what you created).

## Scope
- In, under `spikes/SPK-13/`:
  1. **Reproduce.** A script `builds.sh` that, N times (N = 10 to start with), builds a target
     from a clean state (`scarb clean`, and a run with the Scarb cache pointed at a fresh folder
     inside the worktree through `SCARB_CACHE` or the equivalent, as a separate series), records
     for every Sierra class and every compiled test file: the sha256 of the JSON, the Sierra felt
     count, the CASM felt count, and the class hash (`starkli class-hash` if present, otherwise a
     Python computation over the Sierra class, named), with the environment (`scarb --version`,
     the binary's sha256 and path, `uname -a`, the cache folder, `Scarb.lock`'s hash). Its output is
     a table committed as text (`builds-mac.txt`). Targets: `crates/consumer` and `crates/hexx`'s
     tests of the library at `310b5f1` (a clone inside the worktree, ignored), and the game's
     `contracts/` at this branch's base commit.
  2. **Diff.** Keep one Sierra program of each value observed (committed only if under a few
     hundred kilobytes; otherwise its diff), diff the two (`sierra-replace-ids` on, then the
     function names, libfunc declarations, statements), and name **what differs**: which functions,
     which statements, which libfuncs; whether the CASM differs; whether the difference is an
     inlining decision, an ordering, a dead-function elimination, or something else.
  3. **Minimise.** Reduce to **a small program** (one package, as few lines as possible) that still
     builds to two values across the environments where the difference shows, with the procedure
     used (the function kept, what removed it). If the difference shows **only** across
     environments and never within one, say so and minimise on the two environments you have
     (the Mac's local build against your pull request's CI log, which prints the game's class
     sizes; the library's CI figures as recorded).
  4. **Cause.** The hypothesis the experiments support, with the experiments that refute the
     others; whether it is our code or our cache (then a fix is proposed, not made), the toolchain
     (then the draft issue), or the platform. If it cannot be settled on the Mac alone, say what the
     VPS run (5) must show to settle it.
  5. **The VPS run**: `builds.sh` is written so that the orchestrator runs it unchanged on the VPS
     (x86_64, asdf's Scarb 2.19.4, `scripts/lock.sh` for the builds) and commits its output as
     `builds-vps.txt` after the pull request; the README leaves the comparison's slot. CI's figures
     are a third environment.
  6. **The draft issue**: `issue-draft.md`, as a file for `starkware-libs/cairo` (or `software-
     mansion/scarb` if the cause is Scarb's): title, versions, the minimal program, the two outputs,
     the environments, the steps to reproduce; nothing about the game, nothing that names the
     owner's private repositories.
  7. **The README**: the facts, the method, the table, the diff's reading, the cause, what lifts
     D-164's exception, what the game should do meanwhile (what to record at a deployment, how a
     gate should treat the two values).
- Out: any change to `contracts/`, to the library, to the CI or to a `.tool-versions`; filing any
  issue; installing or changing a toolchain (the pinned Scarb only; `starkli` only if already
  present); no Sepolia.
- Allowlist: `spikes/SPK-13/**`, `REPORT.md`. Anything else is an escalation. The library's clone
  lives in an ignored folder of the spike, is read at `310b5f1`, and is never pushed.

## Acceptance criteria
- [ ] AC-1 The reproduction table on the Mac for the three targets, N builds each, two cache
      states; every environment field filled from real output.
- [ ] AC-2 The diff of the two Sierra programs read and named (functions, statements, libfuncs;
      CASM equal or not).
- [ ] AC-3 A minimal program, or the written reason why minimisation stops where it does.
- [ ] AC-4 The cause stated with its evidence, the refuted hypotheses listed with their
      experiment; what the VPS run must show if the Mac alone does not settle it.
- [ ] AC-5 `builds.sh` runs unchanged on the VPS (paths relative to the worktree, the build lock
      used, no absolute home paths); `issue-draft.md`; the README; CI green; nothing outside the
      allowlist.

## Audits
`[GPT-6-Sol]` reviews the minimisation and the method (D-154 §2; through `nexus audit`, queued for
Codex's reset on 2026-10-04 13:36 UTC); a Claude-side lens may run before it (D-170). The review of
the pull request by `nexus review`.

## Verification
```
spikes/SPK-13/builds.sh --help
spikes/SPK-13/builds.sh --target contracts --n 2 --out /tmp/check   # a smoke run, under the lock
```
and the spike's own tests if it has a Cairo package.

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the table, the diff's reading, the minimal program, the
cause and its evidence, the draft issue's path, the slot left for the VPS run, the commands with
their real output.
