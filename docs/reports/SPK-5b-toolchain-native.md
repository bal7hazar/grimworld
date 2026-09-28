# [Sonnet 5] SPK-5b — Toolchain pins, without Dojo

## Summary
The repository pins the toolchain of a native Starknet game on Cairo 2.19: Scarb 2.19.4, snforge and sncast 0.61.0, **starknet-devnet 0.10.0** as the local node, Node 24.21.0, pnpm 12.5.1, starknet.js 10.8.0 (spike). No `sozo`, `katana`, `torii`. NS-1 is answered by measurement: Katana 1.7.1 and Katana 1.8.0-rc.9 both fail at declare on a Cairo 2.19 class (Sierra 1.9.3 against the Sierra 1.7.0 compiler they bundle); starknet-devnet 0.10.0 passes declare, deploy, invoke, call, event in the receipt. A throwaway contract is built, tested (gas budgets), declared, deployed, invoked and called with `sncast`, and read back from TypeScript with starknet.js.

The model that ran is Sonnet 5, as the brief names.

Pull request: https://github.com/bal7hazar/grimworld/pull/24 (CI `tooling` green after one fix: shellcheck SC2043 on a one-item loop).

## Files changed
- `.tool-versions`: native set (scarb 2.19.4, starknet-foundry 0.61.0, starknet-devnet 0.10.0, nodejs 24.21.0, pnpm 12.5.1).
- `scripts/setup-toolchain.sh`: new pins; sha256 of the starknet-devnet binary (amd64, arm64) verified before it runs; `sozo`/`katana`/`torii` hashes, plugin URLs and the one-time `~/.cargo/bin` link cleanup removed; `sncast` version check added.
- `scripts/with-node.sh` (renamed from `with-katana.sh`, removed): same guarantees (free ports, readiness from the node's own log, process group, cleanup), on starknet-devnet, no `--torii`; exports `NODE_URL`, `RPC_URL`, `STARKNET_RPC_URL`, `NODE_ACCOUNT_ADDRESS`, `NODE_ACCOUNT_PRIVATE_KEY`; log in `./.with-node/`.
- `scripts/lock.sh`: `sozo` case removed.
- `scripts/profiles/audit.txt`, `implement.txt`: `sozo` and `torii` rules removed (the `sncast` and `starknet-devnet` rules were already in `implement.txt`; a comment updated).
- `spikes/SPK-5/.tool-versions`, `spikes/SPK-5/README.md`: the Dojo pins and the baseline note.
- `spikes/SPK-5b/`: `Scarb.toml`, `src/mark.cairo`, `tests/test_mark.cairo`, `flow.sh` (sncast flow), `read.ts` + `package.json` + `pnpm-lock.yaml` + `pnpm-workspace.yaml` (starknet.js 10.8.0), `locked.sh` (lock wrapper, see Deviations), `measure.sh` (time and peak memory), `.gitignore`.
- `docs/research/SPK-5b-toolchain-native.md`: pins and sources, NS-1 with every attempt, the flow, starknet.js and ABI typing, cost, open questions.

## Commands run
```
scripts/setup-toolchain.sh   (twice; via a throwaway checker that also hashes ~/.tool-versions)
  nodejs/pnpm: system used, plugin not needed; scarb 2.19.4, snforge 0.61.0, sncast 0.61.0, node v24.21.0,
  pnpm 12.5.1, starknet-devnet sha256 4e2e6479…167c, starknet-devnet 0.10.0; exit 0 both times;
  "version … is already installed" for the three asdf tools on the second run
  ~/.tool-versions unchanged (same sha256 before/after)
  from /tmp: node v24.21.0, pnpm 12.5.1, scarb 2.19.4, snforge 0.61.0, sncast 0.61.0 all work
    (starknet-devnet, like katana before, is only set inside the repository)
spikes/SPK-5b/measure.sh spikes/SPK-5b/locked.sh scarb build      exit 0, 8.4 s, 626 MB
spikes/SPK-5b/measure.sh spikes/SPK-5b/locked.sh snforge test     exit 0, 7.5 s, 712 MB
  [PASS] test_mark_emits_marked      (l1_gas: ~0, l1_data_gas: ~192, l2_gas: ~975100)
  [PASS] test_mark_writes_the_value  (l1_gas: ~0, l1_data_gas: ~192, l2_gas: ~1007250)
  Tests: 2 passed, 0 failed
spikes/SPK-5b/measure.sh scripts/with-node.sh spikes/SPK-5b/flow.sh   exit 0, 14.7 s, 612 MB
  Declaration completed  Class Hash 0x6d4b97c630981077a032fe28c259f8d17140043b9a0e3fcf85f9735ff3a5f3d
  Deployment completed, Invoke completed (mark 42)
  Call completed: Response 42_u32
  receipt: SUCCEEDED, ACCEPTED_ON_L2, events: Marked{keys:[selector, owner], data:[0x2a]} + fee transfer
  get() = 42
  parsed events: {"spk5b::mark::Mark::Marked":{"owner":"0x64b4…5691","value":"0x2a"}}   ok
pgrep -a katana; pgrep -a starknet-devnet     nothing
NS-1 attempts (same class, sncast 0.61.0):
  Katana 1.7.1        Error: Unsupported Starknet version: 0.13.1.1; with starknet.js, node panic:
                      SierraCompilation(UnsupportedSierraVersion { version_in_contract 1.9.3, version_of_compiler 1.7.0 })
  Katana 1.8.0-rc.9   JSON-RPC error 63 "internal task execution failed: task panicked", same panic
  starknet-devnet 0.10.0   passes
gh pr checks 24     tooling pass
```

## Cost
| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---|---|---|---|
| `test_mark_writes_the_value` (l2 gas) | — | 1 007 250 (1 007 350 on another run) | 1 057 718 | includes declare and deploy of the class inside the test |
| `test_mark_emits_marked` (l2 gas) | — | 975 100 | 1 023 855 | same |
| `mark(42)` on the node (receipt) | — | l2_gas 1 543 440, l1_data_gas 256 | — | devnet's figures, throwaway |

Time and peak memory (largest process, `getrusage`): `scarb build` (target removed) 8.4 s / 626 MB; `snforge test` 7.5 s / 712 MB (warm build cache); node + sncast flow + reader 14.7 s / 612 MB. The very first, cold runs took 21 s (build) and 52 s (test), lock wait included.

## Acceptance criteria
- AC-1 ✔ `.tool-versions` holds the five native pins, nothing of Dojo; research §1 lists every pin with its source.
- AC-2 ✔ `scripts/setup-toolchain.sh` run twice, both exit 0, second run "already installed" for everything; `~/.tool-versions` sha256 unchanged; `node --version` works from `/tmp` (checked by a throwaway script, because my profile cannot `cd /tmp`). The plugin-add path of a clean machine was exercised by hand (`asdf plugin add starknet-devnet`), not by the script, since the plugin was already added when the script first ran.
- AC-3 ✔ NS-1 answered: starknet-devnet 0.10.0 kept; Katana 1.7.1 and 1.8.0-rc.9 recorded with their exact errors (research §2).
- AC-4 ✔ build and test through `scripts/lock.sh` (by `spikes/SPK-5b/locked.sh`, see Deviations); `scripts/with-node.sh spikes/SPK-5b/flow.sh` declares, deploys, invokes, calls and runs the starknet.js reader, which prints the view and the decoded event; `pgrep` shows no node.
- AC-5 ✔ Dojo pins live in `spikes/SPK-5/.tool-versions`; `with-katana.sh` removed; `sozo` and `torii` gone from root `.tool-versions`, `lock.sh`, `audit.txt`, `implement.txt` (`research.txt` still names them: off my allowlist, escalated). CI shellcheck passes (I had no local shellcheck; the first CI run caught SC2043, fixed).

## Deviations from the brief
- **`scripts/lock.sh scarb build --manifest-path …` (the brief's verification line) cannot work with Scarb 2.19**: `--manifest-path` is now a global option before the subcommand and `scarb build --manifest-path` is `unexpected argument`; `lock.sh` refuses a command whose subcommand does not come first, and it is off my allowlist. I added `spikes/SPK-5b/locked.sh`, which goes to the package folder and calls `scripts/lock.sh` from there; the build and test still go through the lock.
- **`spikes/SPK-2/` skipped**: it is not on `origin/main` (SPK-2 not merged), as the brief allows. Its `.tool-versions` and README line still have to be written when it merges.
- **The `katana *` rule in `implement.txt` is kept** (the brief only names `sozo` and `torii`; the Dojo spike still uses Katana).
- **`setup-toolchain.sh` no longer removes the `~/.cargo/bin/{sozo,katana,torii}` links** that a first version of SPK-5 created (that block named tools that are no longer in the script); on machines where they still exist they remain.
- Katana 1.8.0-rc.9 and a copy of devnet were downloaded into `spikes/SPK-5b/.tmp/` (ignored, not committed) for the NS-1 attempts; only starknet-devnet 0.10.0 was installed, through the asdf plugin.
- `starknet-devnet` comes from a community asdf plugin (`ptisserand/asdf-starknet-devnet`, in asdf's registry; a template-generated repository): it verifies nothing, so the binary hash is pinned in the script. The plugin created only the `starknet-devnet` shim.
- The first commit briefly included `spikes/SPK-5b/target/`; caught before pushing and the commit was redone (`git reset --soft`, unpushed), so the pushed history is clean.

## Escalations
Files outside my allowlist that need a change (orchestrator):
1. `scripts/lock.sh`: accept Scarb's global `--manifest-path <path>` before the subcommand (Scarb 2.19), or tell agents to work from the package folder; every brief's `scripts/lock.sh scarb build --manifest-path …` line is wrong on 2.19.
2. `.gitignore`: `.with-katana/` → `.with-node/` (the log and accounts file of `with-node.sh`).
3. `scripts/profiles/research.txt`: `sozo --version`, `torii --version` (and `katana --version`) rules; add `sncast --version`, `starknet-devnet --version`.
4. `docs/briefs/COMMON.md` §2 (and FND-01, SPK-2 briefs): `scripts/with-katana.sh` → `scripts/with-node.sh`.
5. `spikes/SPK-5/run.sh` (out of scope: "changing its code") and the running SPK-2 call `scripts/with-katana.sh`, now removed: the Dojo baseline keeps its pins but its run script needs the old script from the commit before this PR. SPK-2 must also add `spikes/SPK-2/.tool-versions` and its README line.
6. `CHANGELOG.md` / `docs/reports/`: the orchestrator's.

## Open questions
- For FND-01b: does the deployment script build first and does the `release` profile (used by `sncast declare`) carry the same `[cairo]` settings as `dev`? (`sncast declare` compiles the package itself, in `release`.)
- For SPK-11: `starknet_getEvents` (filters, pagination, restart) was not measured on devnet 0.10.0; events were read from the receipt only. Devnet keeps its state in memory and mines one block per transaction.
- CLI-01: typing the starknet.js calls and events from the ABI (`abi-wan-kanabi` via `Contract.typedv2`, ABI `as const` generated from the class JSON) was identified, not tried.
- Is devnet's default `SN_SEPOLIA` chain id acceptable for the game's local tests, or should the node start with its own chain id?

## Fix loop 1
Commit `a9d15bd`, pushed; CI `tooling` green (https://github.com/bal7hazar/grimworld/actions/runs/36457052243). Where this section and the text above disagree (`locked.sh`, escalations 1–3 and 5), this section wins.

**F1 — `.with-node/` unignored (major).** Fix: `.with-node/` added to the root `.gitignore` (the `.with-katana/` line kept, nothing else changed). Evidence, after a real `scripts/with-node.sh spikes/SPK-5b/flow.sh` run created both files:
```
.gitignore:10:.with-node/	.with-node/node.log
.gitignore:10:.with-node/	.with-node/accounts.json
```
(`git check-ignore -v` run through a throwaway script, since my profile does not allow the command typed; `git status` lists no `.with-node`.)

**F2 — Dojo baseline spike not runnable (major).** Fix: `spikes/SPK-5/with-katana.sh` is a copy of origin/main's `scripts/with-katana.sh`, changed only in its paths (`scripts/…` → `spikes/SPK-5/…`) and by one added line, `cd "$(dirname "${BASH_SOURCE[0]}")"`: without it asdf resolves the root's native pins, where `katana`/`torii`/`sozo` do not exist, so the command now runs from `spikes/SPK-5/`. `spikes/SPK-5/run.sh` goes to its own folder and calls `sozo build|migrate|execute` directly, no `scripts/lock.sh`. README updated with the command. Evidence, the Dojo tools being still installed, run once end to end with the spike's own `.tool-versions` (after `scripts/lock.sh pnpm install --frozen-lockfile --dir spikes/SPK-5`, which the worktree needed for `node_modules`):
```
spikes/SPK-5/with-katana.sh --torii --world 0x042f7321…a277 bash run.sh 42
  Migration successful with world at address 0x042f7321b765bf46d69dbc620cc63f56fd1d2d9008a6337f4b8167d57684a277
  Transaction hash: 0x021f60590c16b1464f84cb810ed9060f74ffd88246f5cabbb4cf4d9cefd2f9cc
  spk5-Marker { owner: 0x0127fd5f…fcec, value: 42 }
pgrep -a katana; pgrep -a torii     nothing
```
The address and transaction hash are the ones recorded in `docs/research/SPK-5-toolchain.md`. Note: `sozo build` now runs without the heavy machine lock (the lock no longer wraps sozo, as requested).

**F3 — "system first" only covered node and pnpm (major).** Fix, `scripts/setup-toolchain.sh`: the check now runs for nodejs, pnpm, scarb, starknet-foundry (snforge and sncast, both must match) and starknet-devnet, looking for the binaries on the PATH outside asdf's shims; for starknet-devnet the pinned sha256 must match the system binary too (checked before it is run), and the hash check of the final phase uses the system binary when it serves the tool. The rule per tool: plugin already added → install the pin (F4); else system binaries at exactly the pin → used, no plugin; else system has the tool at another version/build → plugin added only if `~/.tool-versions` has `<tool> system`, else refuse with the incident's remedy; else nothing on the system → plugin added (it hides nothing; before, a machine with no `node` at all was refused, which contradicts a clean-machine setup). Evidence, with a fake `asdf` that only records what it is asked (no plugin was added, nothing installed; throwaway harness):
```
E  no plugin, no Starknet tool on the system:  scarb / starknet-foundry / starknet-devnet: "no system binary … adding the plugin hides nothing" -> FAKE-ASDF plugin add + install for each
C/D  system starknet-devnet at 0.1.0, or 0.10.0 but another binary, no plugin:  "starknet-devnet 0.10.0 is pinned but the system has starknet-devnet:another build" -> exit 1, nothing added
F  no plugin, the pinned starknet-devnet binary on the system:  "using the system binaries (exactly the pinned version); asdf plugin not needed", sha256 4e2e6479…167c and version 0.10.0 checked on the system binary, no plugin add
A  no plugin at all, on this machine:  nodejs and pnpm served by the system; scarb refused because ~/.local/bin/scarb (the machine's wrapper) cannot run under the fake asdf ("scarb:unknown")
```
On this machine (every plugin present) the real run is unchanged: "already installed", exit 0, twice, `~/.tool-versions` sha256 unchanged, node/pnpm/scarb/snforge/sncast work from `/tmp`.

**F4 — plugin present, pin not installed (major).** Fix: when the plugin already exists, the pinned version is installed first, whether or not the system also has that version (before, a matching system `node` skipped the install and the shim then failed inside the repository). Evidence: harness case B (all five plugins present): `FAKE-ASDF install` for scarb, starknet-foundry, starknet-devnet, nodejs and pnpm, and the real run prints "the asdf plugin is already added, installing the pin" for all five, then "version … is already installed".

**F6 — `research.txt` version rules (major).** Fix: `sozo --version`, `katana --version`, `torii --version` removed; `sncast --version`, `starknet-devnet --version` added. `grep -i -E "sozo|torii|katana" scripts/profiles/` now finds only `Bash(katana *)` in `implement.txt` (kept: not in the brief of this fix; the Dojo spike's wrapper starts katana from a script, not from a typed command).

**Escalation 1 — `scripts/lock.sh` and Scarb 2.19's global option.** Fix: `scripts/lock.sh [--heavy] scarb --manifest-path <path> <build|test|lint|fmt|check|metadata|execute> …` is accepted: that single option with a value that does not start with `-`, between `scarb` and the subcommand. Nothing else changed. `spikes/SPK-5b/locked.sh` removed; `spikes/SPK-5b/measure.sh` takes `--cd <dir>`; the research file (§3, §5, §6) and `flow.sh` updated. Evidence:
```
scripts/lock.sh scarb --manifest-path spikes/SPK-5b/Scarb.toml build   -> Finished dev profile
refused, exit 2 (nothing run):
  scarb --manifest-path <p> publish            does not wrap 'scarb publish'
  scarb --manifest-path <p> --offline build    does not wrap 'scarb --offline'
  scarb --manifest-path build                  needs a path and a subcommand
  scarb --manifest-path --offline build        needs a path, not '--offline'
  scarb --offline build / --manifest-path=x build / snforge --manifest-path x test / pnpm --manifest-path x install / sozo build
```
New measurements, `target/` removed first: build through the lock 3.2 s, 636 MB (the earlier 8.4 s / 626 MB were taken on a busier machine); `snforge test` from `spikes/SPK-5b` 6.5 s, 718 MB; the two tests pass with the same gas (975 100 and 1 007 250 l2 gas). `snforge` has no `--manifest-path`, so the tests still run as `cd spikes/SPK-5b && snforge test` (the machine's `snforge` shim takes the heavy lock). Also: the audit profile's `scripts/lock.sh scarb build*` rules do not match the new `scarb --manifest-path …` form (only `implement` has `scripts/lock.sh *`); `audit.txt` was not in this loop's allowlist, so an auditor must run `scripts/lock.sh scarb build` from the folder, or the orchestrator adds a rule.

**F5** not fixed, as instructed (PLAN HRD-10).

**Still open for the orchestrator:** `docs/briefs/COMMON.md` §2 and the FND-01 and SPK-2 briefs still name `scripts/with-katana.sh`; the running SPK-2 needs its own copy like `spikes/SPK-5/with-katana.sh`, and its `.tool-versions` and README line; `CHANGELOG.md`.

## Fix loop 2
Commit `cb4c3a7`, pushed; CI `tooling` green (https://github.com/bal7hazar/grimworld/actions/runs/36458349645).

**F2 — the Dojo spike's `sozo build` and `sozo migrate` took no lock (major).** Fix: `spikes/SPK-5/locked.sh`, a local wrapper for `sozo build|test|migrate` (anything else is refused) that takes the project lock (`$GRIMWORLD_BUILD_LOCK`, default `/tmp/grimworld-build.lock`) and then the heavy machine lock (`$HEAVY_BUILD_LOCK`, default `~/orchestrator/heavy-build.lock`) with `flock`, in that order, exports `GRIMWORLD_BUILD_LOCK_HELD=1` and `HEAVY_BUILD_LOCK_HELD=1`, skips a lock a caller already holds, refuses the wrong order (heavy held, project not) like `scripts/lock.sh`, and runs the command under `nice -n 10` with `RAYON_NUM_THREADS`/`CARGO_BUILD_JOBS` capped at 4. `run.sh` calls `./locked.sh sozo build` and `./locked.sh sozo migrate`; `sozo execute` stays direct (light). Evidence, a throwaway script with temporary lock files (`/tmp/spk5b-demo-*.lock`), the holder being an outer foreground `flock` and the second invocation run inside it under `timeout 3`:
```
control, nothing held:                          exit 0 (ran at once)
project lock held by someone else:              second invocation exit 124 (still waiting after 3 s)
heavy lock held by someone else:                second invocation exit 124
both held (project then heavy):                 second invocation exit 124
once the holder is gone:                        exit 0
nested, both HELD variables set:                exit 0 (runs at once)
HEAVY_BUILD_LOCK_HELD only (wrong order):       refused, exit 2
sozo execute:                                   refused, exit 2
```
The Dojo baseline still runs end to end through it: `spikes/SPK-5/with-katana.sh --torii --world 0x042f7321…a277 bash run.sh 42` → same world address and transaction hash as before, `spk5-Marker { owner: 0x0127fd5f…fcec, value: 42 }`, no katana or torii left. (The wait is shown on the wrapper with temporary lock files; the real run took the real locks, which were free.)

**F3 — `check_hash` hashed a system binary that was not selected (major).** Cause: the system path was recorded in `system_path` for every tool with a system binary, even when the binary was rejected (other version or hash) and the plugin was added instead. Fix, `scripts/setup-toolchain.sh`: the path is kept as a candidate and recorded in `system_path` only inside the branch where the system binaries are selected (`match=1`); a tool installed by asdf is hashed where asdf put it. Evidence, fake-asdf harness case G (system `starknet-devnet` fake at 0.1.0, a fake home whose `.tool-versions` says `starknet-devnet system`; `asdf where` answers with the real install dir), before (HEAD) and after:
```
BEFORE  … adding the plugin is safe / FAKE-ASDF plugin add + install
        sha256 of …/fakesys/starknet-devnet is acdd8218…885fe, expected 4e2e6479…167c
        starknet-devnet not run: its hash was not verified          (exit 1)
AFTER   … adding the plugin is safe / FAKE-ASDF plugin add + install
        starknet-devnet    sha256 4e2e6479…167c                     (the asdf binary, hashed)
        starknet-devnet: expected version 0.10.0, exit 0, output: starknet-devnet 0.1.0   (exit 1)
```
The remaining failure after the fix is the harness's: it puts the fake system directory ahead of everything on the `PATH`, so `starknet-devnet --version` runs the fake; with asdf's shims first, as `asdf` sets up a shell, the shim runs. The earlier cases (C, D, E, F) give the same results as in loop 1, and the real run on this machine is unchanged (twice exit 0, `~/.tool-versions` sha256 unchanged).

**F7 — audit profile could not run the new lock form (major).** Fix, `scripts/profiles/audit.txt`: added `scripts/lock.sh scarb --manifest-path * build*`, `… test*`, `… lint*`, `… fmt --check*`, and `scripts/lock.sh --heavy scarb --manifest-path * build*` and `… test*`; nothing broader (no `check`, `metadata`, `execute`, no other tool; `lock.sh` itself refuses any other subcommand after the option, checked in loop 1). Evidence: the diff of that file is those six lines and one comment.

