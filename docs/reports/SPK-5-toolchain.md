# [Sonnet 5] SPK-5 — Toolchain pins

## Summary
The repository now pins a toolchain that runs together and proves it. Model run: Sonnet 5, as the brief names.

- **Pins**: Scarb 2.13.1, snforge 0.51.2, sozo 1.8.7, Katana 1.7.1, Torii 1.8.16, Node 24.21.0, pnpm 12.5.1, `dojo` Cairo package 1.8.0, dojo.js 2.0.0 (starknet.js 10.0.2).
- **The machine's global Scarb 2.19.4 / snforge 0.61.0 cannot be used for Dojo 1.8** (Sierra 1.9.3 vs the Cairo 2.13 of sozo; `dojo_snf_test 1.8.0` needs `snforge_std 0.51.2`, which snforge 0.61 rejects and snforge 0.51.2 cannot run on Scarb 2.19 Sierra). The repo therefore pins Cairo 2.13 through a local `.tool-versions`; the global `~/.tool-versions` is untouched.
- `scripts/setup-toolchain.sh` (asdf for everything, incl. sozo/katana/torii through their separate plugins; sha256 of their binaries pinned and re-verified on every run — see Fix loop 1), `scripts/with-katana.sh [--torii --world <addr>] <cmd>`, the throwaway world `spikes/SPK-5/`, and the research file.
- End to end works: build, test, migrate to Katana, Torii indexes, dojo.js reads `spk5-Marker { value: 42 }`; nothing left running.
- Hosted indexer: **Slot's managed Katana/Torii hosting was sunset** (cartridge-gg/docs#257, merged 2026-04-29; the revert #260 is open, unmerged); Torii is self-hosted. Detail and sources in the research file §6.
- Pull request: https://github.com/bal7hazar/grimworld/pull/14 — CI `tooling` green.

## Files changed
- `.tool-versions` — scarb 2.13.1, starknet-foundry 0.51.2, sozo 1.8.7, katana 1.7.1, torii 1.8.16, nodejs 24.21.0, pnpm 12.5.1.
- `scripts/setup-toolchain.sh` — idempotent installer over `.tool-versions`, pinned binary hashes, exact version checks, incident check.
- `scripts/with-katana.sh` — Katana (and Torii) for the lifetime of a foreground command, free ports, trap and process-group cleanup, logs in `./.with-katana/`.
- `spikes/SPK-5/Scarb.toml`, `Scarb.lock`, `dojo_dev.toml`, `src/{lib,models,systems}.cairo`, `tests/test_mark.cairo` — the throwaway world (model `Marker`, system `mark`, one test).
- `spikes/SPK-5/package.json`, `pnpm-lock.yaml`, `pnpm-workspace.yaml`, `read-model.ts`, `run.sh`, `.gitignore` — dojo.js side and the migrate-then-read driver.
- `docs/research/SPK-5-toolchain.md` — pins with sources, constraints, failures, commands, timings, hosted-indexer answer, open questions.

## Commands run
(Outputs trimmed; the full ones are in the research file §5.)

Global versions before and after (read with the Read tool, `cat` outside the worktree is refused to agents):
```
~/.tool-versions before:  starknet-foundry 0.61.0 / scarb 2.19.4
~/.tool-versions after:   identical (the file was not modified since my first read; asdf `set` was never used)
asdf list:  scarb *2.13.1 2.19.4 · starknet-foundry *0.51.2 0.61.0 · nodejs *24.21.0 · pnpm *12.5.1   (* = the repo's local pin)
```

```
$ scripts/setup-toolchain.sh && scripts/setup-toolchain.sh     # both runs, second one nothing installed
version 24.21.0 of nodejs is already installed
version 12.5.1 of pnpm is already installed
version 2.13.1 of scarb is already installed
version 0.51.2 of starknet-foundry is already installed
scarb              scarb 2.13.1 (a76aed717 2025-10-30)
snforge            snforge 0.51.2
node               v24.21.0
pnpm               12.5.1
sozo               sozo 1.8.7
katana             katana 1.7.1 (7882660)
torii              torii 1.8.16 (main fe3ed0f)

# Clean machine simulation (ASDF_DATA_DIR, GRIMWORLD_TOOLS, GRIMWORLD_BIN_DIR empty, under /tmp): plugins added,
# Node/Scarb/snforge installed, sozo/katana/torii downloaded and sha256-checked, same 7 lines, exit 0 (879 MB).

$ scripts/lock.sh sozo build --manifest-path spikes/SPK-5/Scarb.toml
    Finished `dev` profile target(s) in 16 seconds
$ scripts/lock.sh sozo test --manifest-path spikes/SPK-5/Scarb.toml
[PASS] spk5_integrationtest::test_mark::test_mark_writes_the_model (l1_gas: ~0, l1_data_gas: ~3072, l2_gas: ~4862269)
Tests: 1 passed, 0 failed, 0 ignored, 0 filtered out

$ scripts/with-katana.sh --torii --world 0x042f7321b765bf46d69dbc620cc63f56fd1d2d9008a6337f4b8167d57684a277 bash spikes/SPK-5/run.sh 42
   World deployed at block 2 and at address 0x042f7321b765bf46d69dbc620cc63f56fd1d2d9008a6337f4b8167d57684a277
Migration successful with world at address 0x042f7321b765bf46d69dbc620cc63f56fd1d2d9008a6337f4b8167d57684a277
Transaction hash: 0x021f60590c16b1464f84cb810ed9060f74ffd88246f5cabbb4cf4d9cefd2f9cc
spk5-Marker { owner: 0x0127fd5f1fe78a71f8bcd1fec63e3fe2f0486b6ecd5c86a0466c3a21fa5cfcec, value: 42 }

$ pgrep -a katana; pgrep -a torii          # nothing
$ scripts/with-katana.sh --torii --world … sh -c 'exit 3'      # exit 3 (status forwarded)
$ timeout 5 scripts/with-katana.sh … bash -c 'sleep 61.5 & sleep 61.6'   # killed: no katana, torii or sleep left

shellcheck 0.9.0.6 (CI's) and 0.11.0.1 on scripts/*.sh and spikes/SPK-5/run.sh: no finding.
gh pr checks 14: tooling pass
```

## Cost
Throwaway world (one model, one system, one test), clean `target/`, through `scripts/lock.sh`. Peak memory = largest resident set among the command's processes. No gas benchmark (not the brief's).

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---|---|---|---|
| `scarb build` (time / peak memory) | — | 15.8 s / 1025 MB | — | run from `spikes/SPK-5` |
| `sozo build` (time / peak memory) | — | 21.2 s / 1050 MB | — | |
| `sozo test`, compile + run (time / peak memory) | — | 27.6 s / 1187 MB | — | a first run took 356 s: waiting for the build lock behind another agent |
| test `test_mark_writes_the_model`, l2_gas | — | 4 862 269 | 5 105 383 (`ceil(1.05 ×)`) | l1_data_gas ~3072 |

## Acceptance criteria
- [x] AC-1 — `.tool-versions` pins the four asdf tools; the research file §1 lists every pin (including dojo.js, `dojo` Cairo package, sozo/katana/torii) with its source.
- [x] AC-2 — setup run twice: identical output, nothing installed the second time (and on a simulated clean machine); global `~/.tool-versions` unchanged (above).
- [x] AC-3 — `scripts/lock.sh sozo build` and `sozo test --manifest-path spikes/SPK-5/Scarb.toml` pass.
- [x] AC-4 — `scripts/with-katana.sh --torii --world … bash spikes/SPK-5/run.sh` migrates, executes the system, dojo.js prints the model (`value: 42`); `pgrep -a katana; pgrep -a torii` shows nothing.
- [x] AC-5 — both scripts pass shellcheck 0.9.0.6 (the CI's version; the first CI run failed on SC2317, fixed in `9a9dc95`) and 0.11.0.1; CI green.
- [x] AC-6 — research file §6, with sources.

## Deviations from the brief
- **The pins are not the machine's versions** (brief: prefer them when compatible): they are not (constraint chain, research §2). Scarb 2.13.1 and snforge 0.51.2 are pinned instead; the global 2.19.4 / 0.61.0 stay.
- ~~`sozo`, `katana`, `torii` as release binaries~~: superseded by Fix loop 1 (F4): they are asdf-managed through the separate plugins and pinned in `.tool-versions`.
- **`scripts/with-katana.sh --torii` needs `--world <address>`** (or `DOJO_WORLD_ADDRESS`), which the brief's interface does not mention: Torii cannot start without it. The address is deterministic, so it works before the migration. It also exports `KATANA_URL`, `STARKNET_RPC_URL`, `TORII_URL`, `TORII_GRPC_URL` and picks free ports.
- **The dojo.js script uses `@dojoengine/grpc`, not `@dojoengine/sdk/node`**: the SDK's Node entry cannot load (`torii-wasm@1.8.2` packaging bug). `@dojoengine/sdk` 2.0.0 is still a dependency.
- The `dojo` asdf plugin was added on this machine (empty, no version installed): agents cannot remove it.
- I ran `pip install --target /tmp/…` for `shellcheck-py` (not installed on the machine) to lint locally; nothing else outside the worktree was installed except asdf versions listed above and the three binaries.

## Escalations
Shared files that need a change (none edited):
- **Root `.gitignore`**: add `.with-katana/` (node logs of `with-katana.sh`, written under the current directory).
- **`scripts/agent.sh` / profiles**: nothing required today; the binaries rely on `~/.cargo/bin` staying on the agents' PATH.
- **`CONTEXT.md` §4 / `docs/CAIRO.md`**: should state Cairo 2.13 / Scarb 2.13.1 / snforge 0.51.2 (research §7 item 5); newer Cairo idioms are not available.
- **ADR-0003 (consequence on hosted indexer)** and **ADR-0001 (option B, Slot)**: confirmed by this spike, may be updated by the orchestrator.

## Open questions
See research file §7; the main ones:
1. Cartridge Controller (SPK-9) and dojo.js both pin `starknet` exactly: can the two coexist in the web client? dojo.js 2.0.0's browser entry and its wasm were not run here.
2. vRNG survives the Slot sunset (Cartridge services): confirm it serves without a Slot chain, for `fate(domain)` (ADR-0002).
3. Katana 1.8.0 is still a release candidate (rc.9): re-run the spike when it is stable (only version and sha256 change).
4. `scripts/lock.sh` refuses `scarb build --manifest-path` and does not wrap `sozo execute`/`init`: check against the real workspace in FND-01.

## Fix loop 1

CI after the fix: `tooling` pass (run 36446029496). Commit `a5434e2`. shellcheck 0.9.0.6 (the CI's) and 0.11.0.1 on `scripts/*.sh` and `spikes/SPK-5/run.sh`: no finding.

| Finding | Fix | Evidence |
|---|---|---|
| **F1** `with-katana.sh` forgot the command's process group after `wait` | The group id (`setsid` makes it the pid) is kept for the whole run; `cleanup` always does `kill -TERM -- -pgid`, waits up to 5 s, then `kill -KILL -- -pgid`, whether or not the leader has exited. Katana and Torii are stopped after it. | `sh -c 'sleep <marker> & exit 0'` under the **old** script (from `HEAD`): `left running: 2343753 sleep 71.11`. Under the new one: `left running: nothing`. Earlier checks kept: status forwarded (`exit 3`), SIGTERM (`timeout 5 …`) leaves nothing. |
| **F2** `install_release` replaced any symlink in `~/.cargo/bin` | Moot by F4: no binary is linked any more. The script now only removes a `~/.cargo/bin/{sozo,katana,torii}` link that points inside `$GRIMWORLD_TOOLS` (left by my first version, i.e. ours) and leaves any other link or file alone, saying so. No project bin directory was needed, nothing outside my allowlist changed. | Real machine: the three links from loop 0 were removed on the first run (`removing … linked by an earlier version of this script`). Test with a temp bin dir holding an own link, a foreign link (`/usr/bin/true`) and a regular file: own link removed, foreign link and file untouched, exit 0. |
| **F3** binary not re-verified; version check was a substring and ignored failure | sha256 of each extracted sozo/katana/torii binary (amd64 and arm64) is pinned in the script and checked on every run against `asdf where <tool> <version>`/bin/<tool>; a version with no pinned hash is refused. `check_version` requires exit 0 and that the first version-shaped word of the output equals the pinned version exactly (`v` prefix stripped for node; pnpm's "Downloading…" line skipped). Versions are read from `.tool-versions`. | Second run prints `sha256 f76a5a49…` / `7ccdcbac…` / `cbf88d6b…`. Three negative tests on copies of the script, each exit 1: tampered hash (`sha256 of …/sozo is f76a… , expected 000…`), truncated version (`torii: expected version 1.8.1 … output: torii 1.8.16` — the old substring test would have passed), failing command printing the right version (`exit 7`). |
| **F4** the claim "asdf cannot provide sozo/katana/torii" rested on the combined plugin | Tested the separate plugins in an isolated `ASDF_DATA_DIR` (no machine-wide shim from the test): `asdf-sozo` 1.8.7, `asdf-katana` 1.7.1, `asdf-torii` 1.8.16 all install; binaries byte-identical to the release archives. So they are pinned in `.tool-versions` and installed by asdf; the release-archive installer is deleted. Research file §1, §4 failure 1 and §5 rewritten, including that my first conclusion was wrong. | Research §4 failure 1 (commands and results). Clean-machine simulation (empty `ASDF_DATA_DIR`): 7 plugins, 7 versions, all checks, exit 0. Full flow re-run with the asdf binaries: `spk5-Marker { … value: 42 }`; `scripts/lock.sh sozo test` pass. |
| **F5** `free_port` ran in `$(…)` (no memory of ports, race before bind) | `pick_port` sets `PORT` in the parent shell and records it in `taken`, so no port repeats in a run. A node is "started" only if it is alive, its own log says it serves that port, and the port answers (HTTP/JSON-RPC, and a TCP connect for gRPC). A node that dies at startup is restarted on new ports, up to five attempts; a hang still fails after 60 s. | A stand-in `katana` on the PATH that fails once with "Address already in use": output `katana attempt 1 failed, trying other ports`, then `answered on http://127.0.0.1:36464`, exit 0. Ports of one run were distinct (Katana 31687, Torii 30622, gRPC 38996). |
| **F6** `.with-katana/` not ignored at the root | Nothing done, as instructed (the orchestrator adds it after the merge). | — |
| **Incident** node/pnpm shims | `setup-toolchain.sh` ends by running `node --version` and `pnpm --version` from `/tmp`; if one fails it prints a warning naming `docs/reports/INC-2026-09-28-asdf-node-shims.md` and its pending remedy (`nodejs system`, `pnpm system` in `~/.tool-versions`). It never edits `~/.tool-versions`. | On this machine the warning is printed for both (the remedy is still pending); `~/.tool-versions` still reads `starknet-foundry 0.61.0` / `scarb 2.19.4`, unchanged. |

Other changes in this loop, found by the re-run:
- `spikes/SPK-5/run.sh` now runs `sozo build` before `sozo migrate`. The world address depends on the artifacts in `target/`: those left by `sozo test` give another address (`0x0081…0990`), so Torii indexed the wrong world and the read-back failed. The pinned address `0x042f…a277` is the one from `sozo build` artifacts (recorded in the research file §5).
- Machine-wide effect of F4, for the orchestrator: three new asdf plugins (`sozo`, `katana`, `torii`) and their shims in `~/.asdf/shims`; nothing existed under those names before, so nothing is hidden. The combined, empty `dojo` plugin from loop 0 remains added (agents cannot remove it). The `~/.grimworld/tools/` directory from loop 0 still holds the three unused binaries (about 100 MB); agents are not allowed to delete outside the worktree, remove it when convenient.
- The pnpm/Node shim incident is not resolved by this task: the owner's decision on `nodejs system` / `pnpm system` is pending.

## Fix loop 2

CI after the fix: `tooling` pass (run 36447059354). Commit `120bf2a`. shellcheck 0.9.0.6 (the CI's) and 0.11.0.1 on `scripts/*.sh` and `spikes/SPK-5/run.sh`: no finding (0.9 first flagged an `A && B || C` as SC2015 in the new code; rewritten as an `if`).

| Finding | Fix | Evidence |
|---|---|---|
| **F3** `check_version` ran sozo/katana/torii before `check_hash` verified them | For each of the three, `check_hash` runs first; if it fails the script prints `<tool> not run: its hash was not verified` and never executes the binary. The other four tools cannot be pinned simply: the script header and research §1 ("Integrity of the other tools") state, from the plugin sources I read, what each does: `asdf-scarb` and `asdf-starknet-foundry` download a GitHub release tarball over HTTPS with no checksum (the second also pipes `universal-sierra-compiler`'s `install.sh` to `sh`); `asdf-nodejs` uses node-build, which verifies a precomputed sha256 per release; `asdf-pnpm` downloads the npm tarball with no checksum; the system node and pnpm are covered by the distribution's package signature, not by the script. Trusted, not verified; pinning `scarb`/`snforge` binaries (about nine per archive, two architectures) is left as an owner's option. | Test with tampered hashes and stand-in `sozo`/`katana`/`torii` first on the PATH that log `EXECUTED <tool>` before delegating to the real shim: exit 1, three `not run` lines, **fake log empty**. Same test with the true hashes: exit 0, log `EXECUTED sozo \| katana \| torii`, each after its `sha256` line. |
| **N1** the plugins `nodejs`/`pnpm` hide the system node/pnpm | Per tool, before touching asdf: find the first `node`/`pnpm` on the PATH outside `${ASDF_DATA_DIR:-~/.asdf}/shims`; if `--version` is exactly the pin, use it and do **not** add the plugin (and do not `asdf install` it). Otherwise: an already added plugin just installs the pin; an absent plugin is added only if the global `~/.tool-versions` already has `<tool> system` (read-only `grep`), else the script exits 1 with the incident's remedy and adds nothing. `nodejs` and `pnpm` stay in the repo's `.tool-versions`; the research file explains that on this machine (plugins added in loop 0) the local pin is what makes node work in the worktrees until the owner applies the remedy, and is simply unused on a clean machine. `~/.tool-versions` never written, no plugin removed. `asdf install` is now per tool and reads `.tool-versions` on fd 3 so it cannot eat the loop's stdin. | Real machine: `using the system /usr/bin/node … asdf plugin not needed` (24.21.0), same for `/usr/bin/pnpm` (12.5.1); checks pass. Stand-in `asdf` that hides the two plugins and records `plugin add`/`install`, with the pin forced to 99.0.0 and `HOME` pointing to a temp dir: **(C)** no global fallback → exit 1, remedy printed, log empty; **(D)** `nodejs system`/`pnpm system` in that `HOME/.tool-versions` → `adding the plugin is safe`, log `FAKE plugin add nodejs \| FAKE plugin add pnpm`; **(E)** system matches, plugin absent → system used, log has no `plugin add`. The test file was unchanged afterwards; the real `~/.tool-versions` still reads `starknet-foundry 0.61.0` / `scarb 2.19.4`. (In D/E the scarb/snforge checks fail only because the test changes `HOME`, hence `~/.asdf`.) Clean-machine simulation (empty `ASDF_DATA_DIR`): plugins added = scarb, starknet-foundry, sozo, katana, torii; **no** nodejs/pnpm; `node --version` works from `/tmp`; no warning; exit 0. |
| **N2** header and research said nothing is written outside asdf's directory | Both now say what is: (1) the one-time removal of the symlinks `~/.cargo/bin/sozo`, `~/.cargo/bin/katana`, `~/.cargo/bin/torii` (`/home/claude/.cargo/bin/…`) when each points into `~/.grimworld/tools/` (`/home/claude/.grimworld/tools/<tool>/<version>/<tool>`); anything else there is left alone; the directory `~/.grimworld/tools` is not touched; already done in loop 1, a no-op now. (2) Side effects of the third-party plugins, checked: node-build logs in `/tmp`; the starknet-foundry plugin's installer places `universal-sierra-compiler` in `~/.local/bin`, where the owner's copy (2.10.1, dated 2026-09-21) already was and its date did not change after my installs and simulations. (3) `~/.tool-versions` is only read. | Script header (top of `scripts/setup-toolchain.sh`) and research §1, "What is written outside asdf's directory". `stat` of `~/.local/bin/universal-sierra-compiler` before/after the simulations: `Mon Sep 21 09:40:33 2026` both times. |

Notes for the orchestrator:
- On this machine the incident is unchanged by this loop: the `nodejs`/`pnpm` shims exist since loop 0, so the script's final warning still fires. The remedy is the owner's.
- `~/.grimworld/tools/` (about 100 MB of unused binaries from my first version) is still there for someone with delete rights.

## Fix loop 3

CI after the fix: `tooling` pass (run 36447727982). Commit `767bd18`. shellcheck 0.9.0.6 (the CI's) and 0.11.0.1 on `scripts/*.sh` and `spikes/SPK-5/run.sh`: no finding. Changed: `scripts/setup-toolchain.sh`, plus two sentences in the research file (§1) that described the old behaviour. F3 and N1-a were not touched, as decided.

| Finding | Fix | Evidence |
|---|---|---|
| **N3** the legacy `~/.cargo/bin` link removal ran before the node/pnpm preflight, so a failing setup could remove the links before the asdf replacements were verified | The block moved to the very end of the script, after every install and every check, inside `if [ "$status" = 0 ]`. Any earlier `exit` (the preflight refusal, `die`) or any failed check (`status=1`) never reaches it. The removal rule itself is unchanged (only a link pointing into `$GRIMWORLD_TOOLS`); the header says "only at the very end of a run in which every tool was installed and verified". | Copies of the script run against a temp `GRIMWORLD_BIN_DIR` holding a legacy link into a temp `GRIMWORLD_TOOLS`: preflight refusal (exit 1) → **link kept**; tampered sozo hash (exit 1) → **link kept**; full success (exit 0) → `removing …/bin/sozo (linked by an earlier version of this task)`, link gone. On the real machine the links were already removed in loop 1, so the real run is a no-op. |
| **N1-b** a global `nodejs system` / `pnpm system` line was accepted as a safe fallback even with no system executable | The fallback branch now requires `[ -n "$sys" ] && global_system_fallback`, where `$sys` is the executable found outside asdf's shims directory. Otherwise the script refuses as before, and if the global file does have the line it adds: `~/.tool-versions has '<tool> system', but no system <binary> exists outside asdf's shims: that fallback would fail.` | Stand-in `asdf` hiding the plugins, pin forced to 99.0.0, test `HOME` whose `.tool-versions` says `nodejs system` / `pnpm system`: with a PATH holding no node or pnpm outside the shims → exit 1, the message above, no `plugin add`; control with the real PATH (system node present) → `adding the plugin is safe`, `plugin add nodejs`, `plugin add pnpm` recorded. The real `~/.tool-versions` was not touched (still `starknet-foundry 0.61.0` / `scarb 2.19.4`). |

The real run after the change is identical to before (system node and pnpm used, sha256 lines before the versions of sozo, katana and torii, the same two warnings from `/tmp`).
