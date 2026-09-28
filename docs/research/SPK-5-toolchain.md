# SPK-5 — Toolchain pins

Measured on 2026-09-28, on the VPS (8 vCPU, 31 GB, Linux x86_64), by `[Sonnet 5]`. Every version
below was run, not only read: the throwaway world in `spikes/SPK-5/` builds, tests, migrates to a
local Katana, is indexed by Torii and is read back by a dojo.js script
(`scripts/with-katana.sh --torii --world <address> bash spikes/SPK-5/run.sh`).

## 1. The pins

| Tool | Pin | Managed by | Source of the choice |
|---|---|---|---|
| Cairo / Scarb | **2.13.1** (Cairo 2.13.1, Sierra 1.7.0) | asdf, `.tool-versions` | Dojo's own `.tool-versions` at `sozo/v1.8.7` (`scarb 2.13.1`); the only 2.13.x on asdf; constraint chain in §2 |
| starknet-foundry (`snforge`) | **0.51.2** | asdf, `.tool-versions` | `dojo_snf_test 1.8.0` depends on `snforge_std =0.51.2` (scarbs.xyz index); Dojo's own pin is `0.51.0` |
| Dojo (`sozo`) | **1.8.7** | asdf plugin `asdf-sozo`, `.tool-versions` | latest of the `sozo/v1.8.x` releases of `dojoengine/dojo` (2026-05-06) |
| Katana | **1.7.1** | asdf plugin `asdf-katana`, `.tool-versions` | latest **stable** release of `dojoengine/katana` (2026-01-29); 1.8.0 exists only as `-rc.N` (latest `rc.9`, 2026-07-20), not pinned |
| Torii | **1.8.16** | asdf plugin `asdf-torii`, `.tool-versions` | latest release of `dojoengine/torii` (2026-05-20) |
| Node.js | **24.21.0** | the system first (`/usr/bin/node`), else asdf; pinned in `.tool-versions` | the version already on the machine, from the system; dojo.js declares `engines.node >=22` |
| pnpm | **12.5.1** | the system first (`/usr/bin/pnpm`), else asdf; pinned in `.tool-versions` | the version already on the machine, from the system (12.8.0 exists; not needed) |
| `dojo` Cairo package | **1.8.0** (`dojo = "1.8.0"`, `dojo_cairo_macros ^1.8.0`) | scarbs.xyz, `Scarb.toml` | the newest on the registry: `1.7.0, 1.7.1, 1.7.2, 1.8.0`. Sozo 1.8.7 works with it |
| `dojo_snf_test` (Cairo dev-dependency) | **1.8.0** | scarbs.xyz | the newest on the registry; provides `spawn_test_world` for snforge |
| `snforge_std` (Cairo dev-dependency) | **0.51** (resolves to 0.51.2) | scarbs.xyz | forced by `dojo_snf_test 1.8.0` |
| dojo.js | **`@dojoengine/grpc` 2.0.0** (used by the script), `@dojoengine/sdk` 2.0.0 (installed, see §5) | pnpm, `spikes/SPK-5/package.json` + `pnpm-lock.yaml` | latest on npm (2026-07-11) |
| starknet.js | **10.0.2** | pnpm | exact peer/dependency of `@dojoengine/*` 2.0.0 |

Machine's global versions, **not changed**: `scarb 2.19.4`, `starknet-foundry 0.61.0`
(`~/.tool-versions`). They are **not usable for a Dojo 1.8 project** (§2), which is why the
repository pins different ones. asdf resolves `.tool-versions` from the repository upwards, so the
global versions stay in force everywhere else.

Not pinned here, by the brief: Cartridge Controller (SPK-9). Not needed: `cairo-profiler` (Dojo
pins 0.9.0 for its own gas work; FND-06 decides).

### How sozo, katana and torii are installed

Through the **separate** asdf plugins `github.com/dojoengine/asdf-sozo`, `asdf-katana` and
`asdf-torii` (added by URL, they are not in asdf's registry), each of which installs its pinned
version (§4, failure 1 and the test recorded there). They download the same release archives as
GitHub's. The sha256 of each **extracted binary** (amd64 and arm64) is pinned in
`scripts/setup-toolchain.sh` and verified on **every** run against
`asdf where <tool> <version>`/bin/<tool>, **before the binary is run at all** (a mismatch stops
the script before `--version` is executed; tested with tampered hashes and stand-in binaries that
record their own execution: none ran); a version without a pinned hash is refused. The amd64
hashes were computed on the installed binaries and equal those of the release archives; the arm64
hashes come from extracting the arm64 archives (whose own sha256 equals the digest GitHub
publishes) and were not run on arm hardware.

### Integrity of the other tools (sources read on 2026-09-28)

| Tool | Provider | What checks the download | Pinned here? |
|---|---|---|---|
| scarb 2.13.1 | `asdf-scarb` (`bin/download`, `lib/utils.bash`) | nothing but HTTPS: `curl` of the `github.com/software-mansion/scarb` release tarball, extract, test that `bin/scarb` is executable. No checksum, no signature | No. The install holds about nine binaries per architecture; a hash of one would leave the rest unchecked, and arm64 was not run. Documented instead |
| snforge 0.51.2 | `asdf-starknet-foundry` (`bin/download`, `lib/utils.bash`) | the same, and `download_universal_sierra_compiler` does `curl -L …/universal-sierra-compiler/master/scripts/install.sh \| sh`: an unpinned remote script executed | No, same reason. That script installs `universal-sierra-compiler` into `~/.local/bin` (see below) |
| node 24.21.0 | the system package (`/usr/bin/node`); else `asdf-nodejs` | system: the distribution's package signature, checked when it was installed (not by this script). asdf-nodejs delegates to `node-build`, which keeps a sha256 per release in its definitions and verifies the download (asdf-nodejs README: "checks integrity by precomputing checksums ahead of time and versioning them together with the instructions"); the definitions are refreshed from github.com at install time | No |
| pnpm 12.5.1 | the system package (`/usr/bin/pnpm`); else `asdf-pnpm` (`bin/download`) | system: as above. asdf-pnpm: `curl` of the npm registry tarball over HTTPS, no checksum; pnpm 12 then downloads its platform binary at first use | No |
| sozo, katana, torii | `asdf-sozo`, `-katana`, `-torii` | nothing in the plugins | **Yes**, sha256 of the extracted binary |

For the four unpinned tools, HTTPS to github.com, the npm registry and nodejs.org is the whole
guarantee, and `--version` runs the binary before anything vouches for it. They are trusted, not
verified; the script header says so. A pin of `bin/scarb` and `bin/snforge` (and the other
binaries of each archive, both architectures) is the natural next step if the owner wants it.

### What is written outside asdf's directory

Not "nothing". (1) **One-time exception of the script**: it removes the symlinks
`~/.cargo/bin/sozo`, `~/.cargo/bin/katana`, `~/.cargo/bin/torii` (`/home/claude/.cargo/bin/…` on
this machine) that the first version of this task created, and only when each points into
`~/.grimworld/tools/`, and only at the very end of a run in which every tool was installed and verified (a run that stops or fails earlier leaves the links where they are) (`/home/claude/.grimworld/tools/<tool>/<version>/<tool>`); a link pointing
elsewhere, or a regular file, is left alone. They were removed on this machine in fix loop 1; on
any other machine the step does nothing. The directory `~/.grimworld/tools/` is not touched.
(2) **Side effects of the third-party plugins**, not of the script: `asdf-nodejs` writes node-build
logs to `/tmp/node-build.*.log`; `asdf-starknet-foundry` pipes `universal-sierra-compiler`'s
installer to `sh`, which puts `universal-sierra-compiler` 2.10.1 in `~/.local/bin` on a machine
that lacks it. On this machine that file is dated 2026-09-21, before this task, and its date did
not change after this task's installs and clean-machine simulations. (3) The script reads, and
never writes, `~/.tool-versions`.

### Node and pnpm: the system first, and why `.tool-versions` still names them

Adding the asdf plugins `nodejs` and `pnpm` puts shims in `~/.asdf/shims`, ahead of `/usr/bin`,
that answer "No version is set" wherever no `.tool-versions` names them
(`docs/reports/INC-2026-09-28-asdf-node-shims.md`). So `scripts/setup-toolchain.sh` decides per
tool, before touching asdf:

1. The first `node` / `pnpm` on the PATH outside asdf's shims directory is run with `--version`.
   If it is **exactly** the pinned version, the system binary is used and the plugin is **not**
   added (tested with a stand-in `asdf` that hides those plugins: no `plugin add`).
2. If it differs and the plugin is already added, the script installs the pinned version through
   it (the shim already exists; nothing new is hidden).
3. If it differs and the plugin is absent, the script adds it only when the global
   `~/.tool-versions` already contains `<tool> system` (a read-only check) **and** a system
   executable of that tool exists outside asdf's shims directory (a `system` line with nothing
   behind it would fail); otherwise it **exits 1**
   with the remedy of the incident file and adds nothing.
The script never edits `~/.tool-versions` and never removes a plugin.

`nodejs` and `pnpm` stay in the repository's `.tool-versions`. On this machine the plugins were
added by the first version of this task (the incident): the shims exist, and in a directory
without that pin `node` fails. The local pin is what makes `node` and `pnpm` work in the worktrees
until the owner applies the remedy (`nodejs system`, `pnpm system` in `~/.tool-versions`). On a
clean machine whose system node and pnpm match, the pin is simply unused: no plugin, no shim, the
system binaries answer everywhere (clean-machine simulation: the plugin list holds only scarb,
starknet-foundry, sozo, katana, torii; `node --version` works from `/tmp`; no warning).

**Machine-wide effect of the other plugins.** The shims of `sozo`, `katana` and `torii`
(`~/.asdf/shims`) hide nothing: those names did not exist before. `scripts/setup-toolchain.sh`
ends by running `node --version` and `pnpm --version` from `/tmp` and warns, naming the incident's
pending remedy, when they fail (today, on this machine, they do); it never edits `~/.tool-versions`.

## 2. Compatibility constraints found

The chain that fixes Cairo 2.13, each link shown by a failure in §4:

1. `sozo` 1.8.x runs the `scarb` on the PATH (its error text names `$SCARB`) and then compiles the
   Sierra it finds to CASM with its own **Cairo 2.13** libraries (inferred from the message
   below). With Scarb 2.19.4,
   `sozo build` succeeds but `sozo migrate` stops: `Cannot compile Sierra version 1.9.3 with the
   current compiler (sierra version: 1.7.0)`. **Sozo 1.8 needs Scarb 2.13.x.**
2. The `dojo` Cairo package 1.8.0 declares `starknet ^2.13`, which Scarb 2.19 also satisfies
   (measured by the orchestrator: an empty project builds). It is the *runtime* tools, not the
   dependency graph, that pin 2.13.
3. `dojo_snf_test 1.8.0` (the Dojo test harness for snforge: `spawn_test_world`) depends on
   `snforge_std >=0.51.2, <0.51.3`, so tests must run under **snforge 0.51.x**.
4. snforge 0.51.2 links Cairo 2.13 too: it cannot run the Sierra of Scarb 2.19.4 (`libfunc
   get_execution_info_v3_syscall` unknown). And snforge 0.61 refuses `snforge_std` 0.51.2. Both
   directions fail, so the pair is **Scarb 2.13.1 + snforge 0.51.2**.
5. Katana and Torii release from their own repositories and talk to sozo over JSON-RPC only. Sozo
   1.8.7 warns instead of failing on a Starknet RPC spec other than 0.9.0 (release notes,
   PR #3402); Katana 1.7.1 answers `0.9.0`. Torii 1.8.16 indexed a world deployed by sozo 1.8.7 on
   Katana 1.7.1.
6. dojo.js 2.0.0 requires `starknet` **10.0.2** exactly, Node ≥ 22, and pulls
   `@dojoengine/torii-client`/`torii-wasm` 1.8.2. Its gRPC client read Torii 1.8.16 without
   trouble.
7. `allow-prebuilt-plugins = ["dojo_cairo_macros", "snforge_std"]` in `Scarb.toml` avoids
   compiling the Dojo macros from source, which would need a Rust toolchain on the machine.

**Consequence for the project**: the whole game stays on Cairo 2.13 (Scarb 2.13.1, snforge 0.51.2)
for as long as it uses Dojo 1.8. A Cairo upgrade waits for a Dojo release that moves its runtime
and `dojo_snf_test`. Dojo's newest Cairo package (1.8.0) dates from October 2025: nothing newer
exists to move to, whatever sozo's patch number says.

## 3. What runs, with measured cost

`scarb build` and `sozo build` and the test, each from a clean `target/`, warm package caches,
through `scripts/lock.sh`, on the throwaway world (one model, one system, one test). "Peak
memory" is the largest resident set among the processes of the command (`getrusage` of the
children), not their sum.

| Command | Wall time | Peak memory |
|---|---|---|
| `scripts/lock.sh scarb build` (in `spikes/SPK-5`) | 15.8 s | 1025 MB |
| `scripts/lock.sh sozo build --manifest-path spikes/SPK-5/Scarb.toml` | 21.2 s | 1050 MB |
| `scripts/lock.sh sozo test --manifest-path spikes/SPK-5/Scarb.toml` (compile + run) | 27.6 s | 1187 MB |

A first `sozo test` measured 356 s: the wait for the build lock behind another agent, included in
the wall time (the same command ran in 27.6 s once the lock was free). The test itself:
`l2_gas ~4 862 269, l1_data_gas ~3072`; its `#[available_gas]` is 5 105 383 (`ceil(1.05 ×)`).
`scripts/lock.sh scarb build` refuses `--manifest-path` (Scarb takes it before the subcommand and
the lock needs the subcommand first): run it from the package folder, or use `sozo build`.

## 4. What failed, and why

1. **The combined asdf `dojo` plugin cannot install Dojo 1.8; the separate plugins can.**
   `asdf install` of `dojo 1.8.0` ran `dojoup`, installed `sozo`, then: `installing torii — No
   compatible version found for torii / Version v for torii does not exist.` (Katana and Torii
   release from `dojoengine/katana` and `dojoengine/torii`; the `dojo` GitHub release `v1.8.0`
   holds a single `sozo` binary.) The plugin removes the whole install on failure. My first
   version of this file concluded from it that asdf cannot provide the three tools, and shipped
   release-archive binaries: **that was wrong**, the audit caught it. Test of the separate plugins,
   in an isolated `ASDF_DATA_DIR=/tmp/spk5-plugtest/asdf` so that no shim reached the machine:
   ```
   asdf plugin add sozo   https://github.com/dojoengine/asdf-sozo.git   -> 0; list all: … 1.8.6, 1.8.7
   asdf install sozo 1.8.7                                              -> sozo 1.8.7 installation was successful!
   asdf plugin add katana https://github.com/dojoengine/asdf-katana.git -> 0; list all: … 1.7.0, 1.7.1
   asdf install katana 1.7.1                                            -> katana 1.7.1 installation was successful!
   asdf plugin add torii  https://github.com/dojoengine/asdf-torii.git  -> 0; list all: … 1.8.15, 1.8.16
   asdf install torii 1.8.16                                            -> torii 1.8.16 installation was successful!
   ```
   All three repositories are active (last push 2026-06-22). The installed binaries are
   byte-identical to the ones extracted from the release archives (same sha256). Hence
   `.tool-versions` pins them and the release-archive installer is gone. (The combined `dojo`
   plugin stays added on this machine, empty; `asdf plugin remove` is denied to agents.)
2. **snforge 0.61 (the machine's) with `snforge_std` 0.51**:
   `Reading from buffer failed, this can be caused by calling starknet::testing::cheatcode with
   invalid arguments. Probably snforge_std/sncast_std version is incompatible` and the warning
   `Package snforge_std version does not meet the recommended version requirement ^0.61.0`.
   Overriding `snforge_std` to 0.61 (dev-dependency, or `[patch.scarbs-xyz]`) fails at
   resolution: `dojo_snf_test 1.8.0 depends on snforge_std >=0.51.2, <0.51.3`.
3. **snforge 0.51.2 with Scarb 2.19.4**: `Error during libfunc specialization of [1503514]: Could
   not specialize libfunc get_execution_info_v3_syscall ... Could not find the requested
   extension`.
4. **`sozo migrate` with artifacts built by Scarb 2.19.4**: `Cannot compile Sierra version 1.9.3
   with the current compiler (sierra version: 1.7.0)`.
5. **`sozo migrate` panics when `[env]` of `dojo_dev.toml` has no `rpc_url`** even though
   `STARKNET_RPC_URL` is set: `thread 'main' panicked at
   crates/dojo/world/src/local/artifact_to_local.rs:59:38: called Option::unwrap() on a None
   value` (the blake2s auto-detection unwraps the file's `rpc_url`). Workaround: keep an
   `rpc_url` in the file; the environment variable still overrides it. Present in sozo 1.8.7.
6. **`@dojoengine/sdk/node` does not load**: it imports `@dojoengine/torii-wasm@1.8.2`, whose
   `node.mjs` requires `./pkg/node/dojo_c.js`; the package ships `pkg/node/dojo_wasm.js`
   (`Error: Cannot find module './pkg/node/dojo_c.js'`). A packaging bug of torii-wasm 1.8.2, which
   `@dojoengine/sdk` 2.0.0 pins exactly. The script uses `@dojoengine/grpc` (`ToriiGrpcClient`),
   which does not depend on the wasm package. The browser entry of the SDK (`.`) is not exercised
   here: FND-01/SPK-8 must test it in the real client.
7. **pnpm 12 refuses to install with unreviewed build scripts**
   (`ERR_PNPM_IGNORED_BUILDS: msgpackr-extract, protobufjs`). Settled in
   `spikes/SPK-5/pnpm-workspace.yaml` (`allowBuilds: false` for both, optional accelerators).
8. **`asdf install` of pnpm 12.5.1 reports `failed to run download callback`** in a first run
   with several plugins, yet pnpm works (its shim downloads the binary at first use and prints
   `Downloading the pnpm 12.5.1 binary for linux-x64...` once). A fresh asdf data directory
   installed everything with exit 0 (§6); the script tolerates a non-zero `asdf install` and
   decides on the version check.
9. `starknet@10.0.2` is flagged deprecated on npm (`Superseded. Upgrade to starknet@10.8.0 or
   later`), but `@dojoengine/*` 2.0.0 pin it exactly; a newer starknet.js is not usable with them.
10. `shellcheck` is not installed on the machine; all of `scripts/*.sh` and `run.sh` were checked
    with `shellcheck-py` 0.9.0.6 (the version of the CI's `ubuntu-latest`) and 0.11.0.1 (pip, in
    `/tmp`): no finding. The first CI run failed on 0.9.0 with SC2317 ("unreachable") for the
    functions called from a `trap` and through `wait_for`, which 0.11 reports as SC2329; both are
    disabled file-wide in `with-katana.sh`.

## 5. Commands run (real output, trimmed)

### The pins, on the machine and on a clean one

```
$ scripts/setup-toolchain.sh            # any run after the first: nothing installed, nothing changed
setup-toolchain: nodejs 24.21.0: using the system /usr/bin/node (exactly the pinned version); asdf plugin not needed
setup-toolchain: pnpm 12.5.1: using the system /usr/bin/pnpm (exactly the pinned version); asdf plugin not needed
version 2.13.1 of scarb is already installed
version 0.51.2 of starknet-foundry is already installed
version 1.8.7 of sozo is already installed
version 1.7.1 of katana is already installed
version 1.8.16 of torii is already installed
scarb              scarb 2.13.1 (a76aed717 2025-10-30)
snforge            snforge 0.51.2
node               v24.21.0
pnpm               12.5.1
sozo               sha256 f76a5a49b6ef6401595eae43859f936621799204d7ff52781c0be854f735ae63
sozo               sozo 1.8.7
katana             sha256 7ccdcbacd0de309d476470ba40bda832edc650daeacab0c672bc5f09c15c6b71
katana             katana 1.7.1 (7882660)
torii              sha256 cbf88d6b23bd742508f9d6b74c27b78375532ce6bb57f8e5b0fbd3ed91ff14b6
torii              torii 1.8.16 (main fe3ed0f)
setup-toolchain: WARNING: 'node --version' fails in /tmp, outside a pinned directory. […]
setup-toolchain: WARNING: 'pnpm --version' fails in /tmp, outside a pinned directory. […]
```

Clean machine, simulated with an empty `ASDF_DATA_DIR` under `/tmp/spk5-clean` (no root, network
only): five plugins added (node and pnpm are served by the system), five versions installed, the
same checks, no warning, exit 0.

### Build, test

```
$ scripts/lock.sh sozo build --manifest-path spikes/SPK-5/Scarb.toml
   Compiling spk5 v0.1.0 (…/spikes/SPK-5/Scarb.toml)
    Finished `dev` profile target(s) in 16 seconds

$ scripts/lock.sh sozo test --manifest-path spikes/SPK-5/Scarb.toml
     Running test spk5 (snforge test)
    Finished `dev` profile target(s) in 18 seconds
Collected 1 test(s) from spk5 package
Running 1 test(s) from tests/
[PASS] spk5_integrationtest::test_mark::test_mark_writes_the_model (l1_gas: ~0, l1_data_gas: ~3072, l2_gas: ~4862269)
Tests: 1 passed, 0 failed, 0 ignored, 0 filtered out
```

### Migrate, execute, index, read back

```
$ scripts/with-katana.sh --torii --world 0x042f7321b765bf46d69dbc620cc63f56fd1d2d9008a6337f4b8167d57684a277 bash spikes/SPK-5/run.sh 42
 profile | chain_id | rpc_url
 dev     | KATANA   | http://127.0.0.1:32460/
   World deployed at block 2 and at address 0x042f7321b765bf46d69dbc620cc63f56fd1d2d9008a6337f4b8167d57684a277
      Classes declared. / Resources registered. / Permissions synced. / Contracts initialized.
Migration successful with world at address 0x042f7321b765bf46d69dbc620cc63f56fd1d2d9008a6337f4b8167d57684a277
Transaction hash: 0x021f60590c16b1464f84cb810ed9060f74ffd88246f5cabbb4cf4d9cefd2f9cc
spk5-Marker { owner: 0x0127fd5f1fe78a71f8bcd1fec63e3fe2f0486b6ecd5c86a0466c3a21fa5cfcec, value: 42 }
```

The world address is the same on every run **for the same artifacts of `sozo build`** (same class
hashes, seed and deployer: account 0 of `katana --dev`); the artifacts left by `sozo test` give
another address (`0x0081…0990`), so `run.sh` always builds first. Hence Torii can start **before**
the migration: `with-katana.sh --torii` needs the
address up front and it works with a world that does not exist yet. Run with the value `7`, the
script printed `value: 7`; with a failing command (`sh -c 'exit 3'`) the wrapper exited 3; after
`timeout 5 scripts/with-katana.sh --torii … sleep 60` (killed by SIGTERM) and after a command
that had started a child of its own (`bash -c 'sleep 61.5 & sleep 61.6'`), `pgrep -a
"katana|torii|sleep 61"` printed nothing.

**Process group of the command (fix loop 1).** `scripts/with-katana.sh` runs the command in its own
process group, keeps the group id for the whole run and, on every way out, stops the group even
if its leader exited first. Test: `sh -c 'sleep <marker> & exit 0'` (a command that starts a child
and exits). The previous version of the script left `sleep 71.11` running (`pgrep -af` showed
it); the current one leaves nothing (`left running: nothing`). Ports are picked in the parent
shell (never twice in a run); a node counts as started only when its own log says it serves that
port and the port answers; a node that dies at startup (a bind failure) is restarted on new
ports up to five times: with a stand-in `katana` that fails once with "Address already in use",
the run printed `katana attempt 1 failed, trying other ports` and then succeeded.


## 6. Answer on the hosted indexer (ADR-0003, AC-6)

**Confirmed: Cartridge retired Slot's managed Katana/Torii hosting.** Sources:

- `cartridge-gg/docs`, pull request **#257**, "docs: sunset Slot product, migrate
  Paymaster/RPC/vRNG to /services", **merged 2026-04-29**. Its description: "Slot's managed
  deployment product (Katana/Torii hosting, billing, scale, observability) is being sunset […]
  Surviving capabilities — Paymaster, RPC, vRNG — move to a new top-level `/services` section […]
  Torii-hosting guidance now points at upstream Dojo docs for self-hosting." It deletes the
  `slot-deploy`, `slot-scale` and `slot-teams` agent skills.
- Pull request **#260** (2026-05-07) proposes to revert it; **still open, not merged** on
  2026-09-28. On that date `docs.cartridge.gg/llms.txt` has no Slot section, and
  `src/pages/slot/*` does not exist on `main`.
- `cartridge-gg/slot` (the CLI) is not archived; its last release is v0.58.3 (2026-04-28), the
  day before the sunset commit.
- What survives, per the same pull request, is what matters for this project: **Paymaster, RPC and
  vRNG** (the last one is the natural provider behind `fate(domain)` of ADR-0002; SPK-9 and the
  randomness spike must confirm it is served without Slot chains — the vRNG deep-dive is at
  `docs.cartridge.gg/services/vrng`).
- Caveat: `dojoengine.org/llms.txt` (Dojo's own book) still lists the Slot deployment tutorials on
  2026-09-28; it looks stale rather than contradictory, but it was not compared page by page.

**Consequence: Torii is self-hosted**, exactly what the pins above install. The stack of the
throwaway world is the deployment shape: one Katana (or the settlement chain's RPC) and one Torii
per environment, run by us. It adds an operations task (a service unit, its database volume, TLS
and CORS in front of Torii's HTTP and gRPC ports, monitoring, snapshot/backups of Torii's SQLite
database), and it removes the Slot cost line of ADR-0001 option B (`$50–200 / month per service`):
the owner should be told the L3 option B is not available as a hosted offer either. Torii 1.8.16
has what a self-host needs (`--db-dir`, `--http.tls_cert_path`, `--http.cors_origins`,
`--grpc.*`, `--metrics`, `--snapshot.url`): no hosted service is required by the client design.

## 7. Open questions for FND-01 (and others)

1. **Shims.** `sozo`, `katana`, `torii` (and `node`, `pnpm`) now resolve through `~/.asdf/shims`,
   so they work in a directory that pins them (every Grim World worktree) and answer "No version
   is set" elsewhere. The owner's decision on the incident file (`nodejs system`, `pnpm system`)
   is still pending.
2. **The agent profiles**: `implement` allows `sozo *`, `katana *`, `torii *`, `pnpm *`, `node *`,
   but neither `bash spikes/…` nor a `run.sh` outside `scripts/`: the migrate-and-read command of a
   spike has to start with `scripts/with-katana.sh … bash spikes/SPK-5/run.sh` (it does). FND-01
   should give the real world's end-to-end command the same shape.
3. **`.gitignore` at the root** should list `.with-katana/` (the node logs of
   `scripts/with-katana.sh`, written under the current directory): it is a shared file, not in
   this brief's allowlist.
4. **`scripts/lock.sh`** wraps `sozo build|test|migrate|inspect` but not `sozo execute` or `sozo
   init`, and `scarb build` cannot take `--manifest-path` behind it. FND-01 will have a root
   `Scarb.toml` (workspace), where `-p <package>` replaces `--manifest-path`; check it then.
5. **Cairo 2.13 for the whole game** (§2): `docs/CAIRO.md` and CONTEXT §4 should say Cairo 2.13,
   Scarb 2.13.1, snforge 0.51.2 (they do not name a version today); the machine's global 2.19.4 /
   0.61.0 must not leak into the repository through a `.tool-versions` copy. Features of newer
   Cairo (2.14+) are not available: check the design's Cairo idioms against 2.13.
6. **Katana 1.8.0** is a release candidate (rc.9, 2026-07-20). ADR-0001 already treats it as
   immature; pinning 1.7.1 keeps to a stable release. Re-run `scripts/with-katana.sh` against the
   stable 1.8.0 when it ships (only the version and the sha256 in the setup script change).
7. **Web client**: dojo.js 2.0.0's browser entry and its `torii-wasm` were not run (no browser in
   this task). SPK-8 or FND-01 must, along with the `starknet` 10.0.2 pin (deprecated on npm) and
   Cartridge Controller's own `starknet` requirement (SPK-9): two exact pins can conflict.
8. **CI**: the `shellcheck` job (FND-02) should cover `scripts/*.sh` and `spikes/**/run.sh`. A CI
   that runs `scripts/setup-toolchain.sh` installs about 880 MB (measured on the clean-machine
   simulation of §5: the seven asdf versions).
9. `dojo_dev.toml` of the throwaway world carries account 0 of `katana --dev` (a well-known,
   public dev key). Real worlds must never commit a key; FND-01 should read the account from the
   environment (`DOJO_ACCOUNT_ADDRESS`, `DOJO_PRIVATE_KEY`).
