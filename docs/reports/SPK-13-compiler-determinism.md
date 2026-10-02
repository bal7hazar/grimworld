# [Opus 5.5] SPK-13 — Builds of the same sources that differ

Archived by the CV orchestrator (thread run on Sonnet 5.5) from the spike's README and tables. The
spike ran on the Mac as Opus 5.5 (`claude-opus-5-5`); the VPS series were run by the previous CV
orchestrator. Every figure is from [spikes/SPK-13/README.md](../../spikes/SPK-13/README.md) or its
tables ([builds-mac.txt](../../spikes/SPK-13/builds-mac.txt),
[builds-vps.txt](../../spikes/SPK-13/builds-vps.txt),
[minimal-vps.txt](../../spikes/SPK-13/minimal-vps.txt)); where this text and those files differ,
the files win. Brief: [SPK-13](../briefs/SPK-13-compiler-determinism.md). Pull request #252.

## Summary

**The toolchain, not our code or our cache; the platform plays no part in the race.** Cairo 2.19.4 (Scarb 2.19.4) places the
`withdraw_gas` check of a recursive call cycle on the function chosen as the cycle's
representative: the lowest salsa intern id (`lowered_scc_representative`). The feedback set, and
so `needs_withdraw_gas`, follow from that choice. With more than one rayon thread the compiler
warms its database up in parallel (one task per module), so the order of the intern ids is a race.
A different winner puts the check in another function of the cycle: another Sierra program, other
CASM, another class hash, other gas. With `RAYON_NUM_THREADS=1` the warm-up is skipped and every
build was the same.

**The remedy is the single-thread pin (D-176)**: every measured or declared build runs with
`RAYON_NUM_THREADS=1`. It makes a build stable *per machine*; reproducibility of a game class hash across machines is not shown (fact (a)). Scarb 2.20.1 (Cairo 2.20.0, D-180) does not fix it: the drift remains, and
the representative and the warm-up are the same at the tags v2.20.0 and v2.19.6. The issue for
`starkware-libs/cairo` is drafted ([issue-draft.md](../../spikes/SPK-13/issue-draft.md)) and **not filed**: it waits for the owner.

### The two facts for the project manager

**(a) The game's contracts are not affected today.** 23 clean builds of `contracts/` on the Mac
(each Starknet class and each compiled test file) gave one program per artefact, and 10 more on
the VPS (5 at 4 threads, 5 at 1) gave one text and one class hash for each of the 51 artefacts.
CI on x86_64 printed the same Sierra and CASM felts as the Mac for all ten game classes (sizes, not hashes). **But the game's Registry class hash differs between the Mac and the VPS**: Mac `0x04e885bd251a` (text `dc86e41df9bb`, `builds-mac.txt` l.117, l.229), VPS `0x0001621259ac` (text `654665be9dce`, `builds-vps.txt` l.73, l.156), each stable on its machine, with equal Sierra size (10,665), CASM felts (24,611) and CASM sha256 (`9eaca75f52b3`), the same commit, lock and Scarb version. In all, 7 of the 51 artefacts differ on one thread, in two groups: (a) the Registry class, its two copies in the test builds, the `grimworld_persistent` program and the two compiled test files of that package (`persistent_unittest.test`, `persistent_integrationtest.test`), whose class lists in the tables include a Registry class; (b) `grimworld_logic_integrationtest.test` (Mac `f77be9a5c282`, VPS `02764e4e3ffb`), which differs although its build holds no Registry (only `FlattenLibrary` and `TickLibrary`, equal on both machines) and its package does not depend on `grimworld_persistent`, while `logic_unittest.test` and the `grimworld_logic` program are equal. So the difference has at least two independent sources, both open; the other 44 match. The class hashes come from different tools (starkli on the Mac, `class_hash.py` on the VPS), but the Sierra text sha256 differs too, so the hash tool does not explain it (other classes match across the two tools). This is not the race, its cause is open and was not investigated here, and cross-machine reproducibility of a game class hash is **not shown**. Whether
the game's code has a cross-module recursive cycle was not inspected: the builds show that no
current class is affected. A contract that later calls the map generator (`Digger` has such a
cycle, ENG-05) would be exposed.

**(b) D-164's premise of "one value per environment" does not hold.** On the Mac the same binary,
cache and sources gave 27,092, 27,101 and a third value (27,101 Sierra felts / 49,427 CASM) from
one clean build to the next; the library's CI recorded both 27,092 and 27,101. The values are the
possible placements of a gas check in a cycle, and nothing bounds them at two. The pin is therefore
the remedy, not the record of two accepted values: every one-thread build of the targets run (the
library's consumer, on the Mac and the VPS) gave 27,092 (the committed snapshot), so the snapshot can
return to one exact value. What explains CI always giving 27,101 is open: CI has 4 vCPUs and the Mac at
4 threads gave 27,092 in 10 builds out of 10, so the thread count alone does not explain it. The library's gate and CI are
its orchestrator's decision, taken through the project manager.

## The measurements

The Mac: aarch64-apple-darwin, 12 CPUs, Scarb 2.19.4, binary sha256 `e74277a0…7e63be`. The VPS:
x86_64, 8 CPUs, Scarb 2.19.4, binary sha256 `f9561cae…4184`. Library `bal7hazar/hexx-cairo` at
`310b5f1`; the game's `contracts/` at `90b4974`. Each build starts from `scarb clean`.

### The Mac ([builds-mac.txt](../../spikes/SPK-13/builds-mac.txt))

| Target | Series (threads) | Builds | What varied |
|---|---|--:|---|
| library `consumer`, release | clean (12) | 10 | `HexxGenerators`: 27,101 / CASM 49,375 (6 builds), 27,092 / 49,375 (3), 27,101 / 49,427 (1); 3 class hashes. The 8 other classes: 1 each |
| | fresh-cache (12) | 10 | 27,092 (5), 27,101 (5) |
| | clean (4), clean (8) | 10 each | none: 27,092 in all 10 |
| | one-thread | 10 | none: 27,092, one file byte for byte |
| game `contracts/` | clean, fresh-cache (12), one-thread | 10, 10, 3 | no program varied across 51 artefacts; the files of 8 differ in id numbers only, one text each |
| minimal program | clean (12) | 20 | 2 programs (11 and 9 builds) |
| | one-thread | 10 | none, one file |

The library's four metrics for the class, computed on the Mac's kept files, match its records:
27,092 / 49,375 / 1,395,788 / 997,126 is `gas/bytecode.size` (the VPS's builds) and
27,101 / 49,375 / 1,396,211 / 997,304 is `gas/bytecode.builds` (CI's). The third value
(27,101 / 49,427 / 1,396,259 / 998,243) had not been recorded before.

### The VPS ([builds-vps.txt](../../spikes/SPK-13/builds-vps.txt), [minimal-vps.txt](../../spikes/SPK-13/minimal-vps.txt))

| Target | Series (threads) | Builds | Result |
|---|---|--:|---|
| library `consumer`, release | clean, fresh-cache (4, the lock's default) | 10 each | 9 classes, one program each: `HexxGenerators` 27,092 / 49,375, class hash `0x018c238f1c99…` |
| | one-thread | 10 | the same: 4 threads give what 1 thread gives |
| game `contracts/` | clean (4), one-thread | 5 each | one text and one class hash per artefact, 51 artefacts |
| minimal, 2.19.4 | default (8) | 20 | check in `ping` 11, in `b::pong` 9 |
| | one thread | 6 | one file `12ec3e1650a18599` |
| minimal, 2.20.1 | default (8) | 20 | `ping` 12, `b::pong` 8 |
| | one thread | 6 | one file `ecdb2df475027c55` |

Across platforms, on one thread: the VPS's `HexxGenerators` class hash and text sha256 are the
Mac's, and the minimal program's one-thread files have the same sha256 on arm64 and x86_64 on both
Scarb versions: **the platform plays no part in the race**, shown for those two artefacts only. For
the game's `grimworld_persistent_Registry` the two machines differ (fact (a)); that is open. The VPS
never saw 27,101: its builds ran at 4 threads (the lock's default) and 1, where the Mac gave 27,092
as well; that is consistent with the thread count but CI (4 vCPUs, always 27,101) is not explained by
it. No 8-thread series was run on the VPS.

### The diff and the minimal program

The three `HexxGenerators` programs have equal types, libfuncs and declarations; one function
differs per pair. In the 27,092 program the cycle `DiggerInternal::iter → branch → visit → iter`
gets checks in `iter` and the `inward` loop; 27,101 adds one in `visit::<SouthWestHeading>`
(791 → 811 statements); 27,101 / 49,427 adds one in `branch::<SouthWestHeading, SouthEastHeading,
EastHeading>` (1,016 → 1,035). It is a placement decided by an ordering, not inlining or dead-code
elimination. The minimal program ([minimal/](../../spikes/SPK-13/minimal/), 15 lines, no
dependency: `ping` in the root module and `pong` in `mod b`) reproduces it; the two functions must
be in different modules because the warm-up runs one task per module.

What D-154 saw as "four builds, four hashes of the compiled test files" is two effects: the
numeric ids a compiled test file writes change its sha256 on almost every build with the program
unchanged, and some builds really change the program through the race, which alone changes gas.

### Hypotheses refuted

The compiler binary, the cache (a new empty cache every build still varies), the
incremental cache, `Scarb.lock`, the sources' order and the path (for the race), inlining and our code (the
minimal program has neither the game's nor the library's) are each refuted by an experiment in the
README's table. The platform and the path are excluded for the race only; the Registry difference leaves them open. The thread count is the variable: 1 thread gives one program; 4 and 8 gave one
value in 10 builds each on the Mac; 12 gave three.

## Remedy, and what the game does meanwhile

- **Now**: build gates and gas snapshots with `RAYON_NUM_THREADS=1` (D-176), and a deployment
  build is a one-thread build from a clean `target/`.
- **At every deployment** record the commit, the class hash, the Sierra and CASM felts,
  `scarb --version` and the build's `RAYON_NUM_THREADS` (D-154 §4, extended).
- **For good**: the compiler fix (the issue draft, not filed). The pin moves when a Scarb release
  carries it; 2.20.1 does not.

## Differences between the files, and what was not measured

- The README's plan for the VPS run listed an 8-thread series and the minimal program through
  `builds.sh`; the run log shows neither (the minimal program went through `reproduce.sh`). The
  README now says so.
- The README counts 23 builds of `contracts/` for the Mac; the VPS's 10 are counted separately
  above, not added to it.
- Not measured: the hexx test target on the VPS; an 8-thread VPS series; whether the game's code
  has a cross-module cycle.

## Files changed
- `spikes/SPK-13/`: the spike (tools, minimal program, diffs, README, Mac and VPS tables, draft
  issue).
- `docs/reports/SPK-13-compiler-determinism.md`: this archive.
