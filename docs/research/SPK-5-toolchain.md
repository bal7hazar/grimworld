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
| Dojo (`sozo`) | **1.8.7** | release binary, `scripts/setup-toolchain.sh` | latest of the `sozo/v1.8.x` releases of `dojoengine/dojo` (2026-05-06) |
| Katana | **1.7.1** | release binary, `scripts/setup-toolchain.sh` | latest **stable** release of `dojoengine/katana` (2026-01-29); 1.8.0 exists only as `-rc.N` (latest `rc.9`, 2026-07-20), not pinned |
| Torii | **1.8.16** | release binary, `scripts/setup-toolchain.sh` | latest release of `dojoengine/torii` (2026-05-20) |
| Node.js | **24.21.0** | asdf, `.tool-versions` | the version already on the machine; dojo.js declares `engines.node >=22` |
| pnpm | **12.5.1** | asdf, `.tool-versions` | the version already on the machine (12.8.0 exists; not needed) |
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

### Where the release binaries go

`sozo`, `katana` and `torii` are not installable through asdf (§4, failure 1). The script installs
each archive after checking its sha256 (the digest GitHub publishes on the release asset; the six
hashes are in the script) under `~/.grimworld/tools/<tool>/<version>/`, and links it into
`~/.cargo/bin`, which is on the PATH of the machine and of the agents. It refuses to replace a
file there that is not one of its own symlinks. `GRIMWORLD_TOOLS` and `GRIMWORLD_BIN_DIR` override
both places.

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

1. **The asdf `dojo` plugin cannot install Dojo 1.8.** `asdf install` of `dojo 1.8.0` ran
   `dojoup`, installed `sozo`, then: `installing torii — No compatible version found for torii
   / Version v for torii does not exist.` (Katana and Torii release from `dojoengine/katana` and
   `dojoengine/torii`; the `dojo` GitHub release `v1.8.0` holds a single `sozo` binary.) The plugin removes the whole
   install on failure: nothing installed. Hence the release binaries. (The plugin stays added on
   this machine, empty; `asdf plugin remove` is denied to agents.)
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
10. `shellcheck` is not installed on the machine; the two scripts and `run.sh` were checked with
    `shellcheck-py` 0.11.0.1 (pip, in an ignored folder of the worktree): no finding. The CI
    installs its own.

## 5. Commands run (real output, trimmed)

### The pins, on the machine and on a clean one

```
$ scripts/setup-toolchain.sh            # second run: nothing installed, nothing changed
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
```

Clean machine, simulated with an empty `ASDF_DATA_DIR`, `GRIMWORLD_TOOLS` and
`GRIMWORLD_BIN_DIR` under `/tmp/spk5-clean` (no root, network only): plugins added, Node, Scarb,
snforge installed, then the three binaries downloaded and verified, then the same seven lines,
exit 0. 879 MB on disk.

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

The world address is the same on every run (same class hashes, seed and deployer: account 0 of
`katana --dev`), so Torii can start **before** the migration: `with-katana.sh --torii` needs the
address up front and it works with a world that does not exist yet. Run with the value `7`, the
script printed `value: 7`; with a failing command (`sh -c 'exit 3'`) the wrapper exited 3; after
`timeout 5 scripts/with-katana.sh --torii … sleep 60` (killed by SIGTERM) and after a command
that had started a child of its own (`bash -c 'sleep 61.5 & sleep 61.6'`), `pgrep -a
"katana|torii|sleep 61"` printed nothing.

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

1. **PATH of the agents.** The three release binaries are linked in `~/.cargo/bin`. `scripts/lock.sh`
   and every Cairo brief call `sozo`/`katana`/`torii` bare, so that directory must stay on the
   PATH `scripts/agent.sh` gives them (it is today). If the orchestrator prefers another
   directory, set `GRIMWORLD_BIN_DIR` for the setup script.
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
   simulation of §5: Node, Scarb, snforge and the three binaries).
9. `dojo_dev.toml` of the throwaway world carries account 0 of `katana --dev` (a well-known,
   public dev key). Real worlds must never commit a key; FND-01 should read the account from the
   environment (`DOJO_ACCOUNT_ADDRESS`, `DOJO_PRIVATE_KEY`).
