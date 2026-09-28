# SPK-5b — Toolchain pins, without Dojo

Measured on 2026-09-28, on the VPS (8 vCPU, 31 GB, Linux x86_64), by `[Sonnet 5]`. A throwaway
contract (`spikes/SPK-5b/`) is built and tested with Scarb 2.19.4 and snforge 0.61.0, declared,
deployed, invoked and called on a local node with `sncast`, its event is read from the receipt, and
a starknet.js script calls the view and decodes the event. ADR-0007 (D-123): no Dojo world, no
`sozo`, no Torii, no dojo.js.

## 1. The pins

| Tool | Pin | Managed by | Source of the choice |
|---|---|---|---|
| Cairo / Scarb | **2.19.4** (Cairo 2.19.4, Sierra 1.9.3) | asdf, `.tool-versions` | ADR-0007 (Cairo 2.19); the machine's global version, already installed. asdf-scarb downloads the release tarball from github.com over HTTPS, no checksum |
| starknet-foundry (`snforge`, `sncast`) | **0.61.0** | asdf, `.tool-versions` | the machine's global version, and the one whose `snforge_std 0.61` matches Scarb 2.19. asdf-starknet-foundry (`foundry-rs`), no checksum; it pipes `universal-sierra-compiler`'s installer to `sh` |
| Local node: `starknet-devnet` | **0.10.0** (Rust; JSON-RPC 0.10.2) | asdf plugin `starknet-devnet` (`ptisserand/asdf-starknet-devnet`, in asdf's registry), `.tool-versions` | NS-1 (§2): the only candidate that accepts a Cairo 2.19 class. Latest stable release of `0xSpaceShard/starknet-devnet` (2026-09-03) |
| Node.js | **24.21.0** | the system first (`/usr/bin/node`), else asdf; pinned in `.tool-versions` | the system's version, unchanged from SPK-5 |
| pnpm | **12.5.1** | the system first (`/usr/bin/pnpm`), else asdf; pinned in `.tool-versions` | the system's version, unchanged from SPK-5 |
| `snforge_std` (Cairo dev-dependency) | **0.61** | scarbs.xyz, `Scarb.toml` | matches snforge 0.61.0 |
| `assert_macros` (Cairo dev-dependency) | **2.19** | scarbs.xyz | matches Cairo 2.19 |
| starknet.js | **10.8.0**, exact | pnpm, `spikes/SPK-5b/package.json` + `pnpm-lock.yaml` | `latest` dist-tag on npm on 2026-09-28 (published 2026-09-22). `next` is 11.0.2 (`beta`: 11.0.0-beta.14), not used |

Not in the set any more: `sozo`, `katana`, `torii`. They stay pinned, unchanged, in
`spikes/SPK-5/.tool-versions` (scarb 2.13.1, starknet-foundry 0.51.2, sozo 1.8.7, katana 1.7.1,
torii 1.8.16): the Dojo baseline, not installed by `scripts/setup-toolchain.sh`.
`spikes/SPK-2/` is not on `origin/main` yet (SPK-2 not merged), so its `.tool-versions` and README
line are not written; SPK-2 must add them (§5).

### Integrity

`starknet-devnet`: the plugin downloads
`https://github.com/0xSpaceShard/starknet-devnet/releases/download/v0.10.0/starknet-devnet-<arch>.tar.gz`
with curl and checks nothing. The sha256 of the **extracted binary** is pinned in
`scripts/setup-toolchain.sh` and verified before the binary is run, on every run:

| Arch | Release asset (GitHub's published digest, matched by our download) | Binary |
|---|---|---|
| amd64 (`x86_64-unknown-linux-gnu`) | `0d27863ec959dc74ec6de985c3ec8eb093d6670bacd7672b51dc71ec8528969b` | `4e2e6479fa9502f2952ed26740d5cc8ebeb3695c16e752edcc560f6e736b167c` |
| arm64 (`aarch64-unknown-linux-gnu`) | `63c10e289143fde9332cec086129a18e91ff45e789ecd949c62b659188b4cdad` | `fe08fbe940e4e2efde9af3a199b6902e926822efb53207c79c81eb5b6b050111` |

The amd64 binary installed by asdf matches the pinned hash (checked by `setup-toolchain.sh`). The
arm64 hash comes from the release asset, downloaded and extracted here, not from an arm64 machine.
The `starknet-devnet` plugin is a repository generated from asdf's plugin template (its
`lib/utils.bash` still carries the template's `TODO` comments); it only downloads the release
tarball, which is why the hash matters. Adding it created the shim `starknet-devnet` only; `node`,
`pnpm`, `scarb`, `snforge` and `sncast` were checked from `/tmp` afterwards and work (the system
provides no `starknet-devnet`, so the rule of the incident INC-2026-09-28 is respected).

## 2. NS-1: which local node accepts a Cairo 2.19 class

Class under test: `Mark`, compiled by Scarb 2.19.4 (Sierra 1.9.3, class hash
`0x6d4b97c630981077a032fe28c259f8d17140043b9a0e3fcf85f9735ff3a5f3d`). Test: `sncast` 0.61.0
declare, deploy, invoke, call, then the receipt's events (`spikes/SPK-5b/flow.sh`), in the order the
brief gives.

| # | Node | Result | Exact error |
|---|---|---|---|
| 1 | Katana **1.7.1** (asdf, installed before), JSON-RPC 0.9.0 | **fails at declare** | `sncast`: `[WARNING] RPC node … uses incompatible version 0.9.0. Expected version: 0.10.0`, then `Error: Unsupported Starknet version: 0.13.1.1`. Sent with starknet.js (`Account.declare`, `starknet_estimateFee`) to see past `sncast`: `63: An unexpected error occurred: {"reason":"internal task execution failed: task panicked"}`, and the node's log: `panicked at crates/executor/src/implementation/blockifier/utils.rs:633:36: called Result::unwrap() on an Err value: SierraCompilation(UnsupportedSierraVersion { version_in_contract: VersionId { major: 1, minor: 9, patch: 3 }, version_of_compiler: VersionId { major: 1, minor: 7, patch: 0 } })` |
| 2 | Katana **1.8.0-rc.9** (newest release candidate, 2026-07-20; `linux_amd64` archive, sha256 `6769cf4e842d45d2550f1ebda632b6e737d5f82e635c2e6939b7bd2913ee2caf` from the release's `checksums.txt`, binary `b3ec9a22715a565633232b4ef6e6f8610cd7cdc1c46e720a7029d97c2c577276`; not in asdf's list, which ends at 1.7.1; installed by hand under `spikes/SPK-5b/.tmp/`, not committed) | **fails at declare** | `sncast`: `Error: Unknown RPC error: JSON-RPC error: code=63, message="An unexpected error occurred", data={"reason":"internal task execution failed: task panicked"}`; node log: `panicked at crates/executor/src/blockifier/utils.rs:664:36: … SierraCompilation(UnsupportedSierraVersion { version_in_contract: VersionId { major: 1, minor: 9, patch: 3 }, version_of_compiler: VersionId { major: 1, minor: 7, patch: 0 } })`. It speaks JSON-RPC 0.10 (no version warning) |
| 3 | **`starknet-devnet` 0.10.0** (Rust), JSON-RPC 0.10.2 | **passes everything** | none. Declare, deploy, invoke and call succeed with `sncast`; the receipt holds the `Marked` event (`keys`: selector, `owner`; `data`: `value`); starknet.js 10.8.0 calls `get()` and parses the event |

Both Katana builds bundle a Sierra compiler of 1.7.0 (Cairo 2.13, Dojo's baseline) and refuse Sierra
1.9.3; the newest Katana release (a candidate) has the same limit. The first passing node is kept: **`starknet-devnet` 0.10.0**, and the two Katana builds are not.

What was checked on devnet (`scripts/with-node.sh spikes/SPK-5b/flow.sh`, run several times, the
same class hash each time): declare, deploy, invoke `mark(42)`, `call get` returns `42_u32`
(`Response Raw: [0x2a]`), the receipt (`starknet_getTransactionReceipt`) is `SUCCEEDED`,
`ACCEPTED_ON_L2`, with two events (the `Marked` event and the fee token's transfer), and the
starknet.js reader prints `get() = 42` and the decoded event
`{"spk5b::mark::Mark::Marked":{"owner":"0x64b4…5691","value":"0x2a"}}`. Each transaction is mined in
its own block (declare block 1, deploy 2, invoke 3), so there is nothing to wait for.

Devnet particulars seen: seed 0 gives the same ten pre-funded accounts on every start (the first is
`0x064b48806902a367c8598f4f95c305e8c1a1acba5f082d294a43793113115691`); the default chain id is
`SN_SEPOLIA`, so `sncast` prints voyager Sepolia links after each command (a local node, nothing is
sent anywhere); the receipt's `execution_resources` of the invoke: `l2_gas 1543440`,
`l1_data_gas 256`.

## 3. The deployment flow

`sncast` 0.61.0 (from starknet-foundry 0.61.0). `scripts/with-node.sh` starts the node on a free
port, exports `NODE_URL`, `RPC_URL`, `STARKNET_RPC_URL` and the first pre-funded account
(`NODE_ACCOUNT_ADDRESS`, `NODE_ACCOUNT_PRIVATE_KEY`, read from the node's banner), runs its
command and stops the node. `spikes/SPK-5b/flow.sh` is that command:

1. `sncast --accounts-file <file> account import --url $NODE_URL --name dev --type oz --address … --private-key …`
2. `sncast … --account dev declare --url $NODE_URL --contract-name Mark`, which builds the package
   itself (Scarb `release` profile) and prints `Class Hash:`.
3. `sncast … deploy --url $NODE_URL --class-hash <hash>`: prints `Contract Address:`.
4. `sncast … invoke --url $NODE_URL --contract-address <address> --function mark --calldata 42`:
   prints `Transaction Hash:`.
5. `sncast … call --url $NODE_URL --contract-address <address> --function get`: `Response: 42_u32`.
6. The receipt by `curl` on `starknet_getTransactionReceipt`, then `node spikes/SPK-5b/read.ts`.

Things to know: `sncast` reads `Scarb.toml` in its **working directory** (`Error: Path to Scarb.toml
manifest does not exist` otherwise), so the script runs it from the package's folder (`--package`
picks a member of a workspace); the account file is passed with `--accounts-file`, outside the
default `~/.starknet_accounts`, so nothing is written to the home; the implement profile allows
`sncast` only with `--url http://127.0.0.1:<port>` or `http://localhost:<port>`, on every call, which
`flow.sh` does. `sncast declare` builds by itself: run the build (through the lock) first, then it is
a no-op check (`Finished release profile in 0 seconds` on a second run).

**Scarb 2.19 moved `--manifest-path`** to a global option before the subcommand (`scarb
--manifest-path <path> build`; `scarb build --manifest-path` is `unexpected argument`), which
`scripts/lock.sh` used to refuse (the subcommand must come first). The brief's verification line
`scripts/lock.sh scarb build --manifest-path spikes/SPK-5b/Scarb.toml` therefore fails on 2.19.
Fixed in fix loop 1: `scripts/lock.sh scarb --manifest-path <path> <build|test|…>` is accepted
(that one option, with its value, between `scarb` and the subcommand; everything else is still
refused). `snforge` has no such option: it selects the package by the working directory, so the
tests run as `cd spikes/SPK-5b && snforge test` (the machine's `snforge` shim takes the heavy lock
by itself).

## 4. starknet.js and typed bindings

starknet.js **10.8.0** works against devnet 0.10.0 (JSON-RPC 0.10.2) with `RpcProvider` and
`Contract`, on Node 24 running the `.ts` file directly (type stripping; no build step).
`spikes/SPK-5b/read.ts`:

- `new Contract({ abi, address, providerOrAccount: provider })`, with `abi` read from the compiled
  class `target/dev/spk5b_Mark.contract_class.json`; `await contract.get()` returns the `u32`;
- `provider.waitForTransaction(hash)` then `contract.parseEvents(receipt)`, which returns
  `[{ transaction_hash, block_hash, block_number, "spk5b::mark::Mark::Marked": { owner, value } }]`:
  the event is found by its full Cairo path (`<package>::<module>::<Contract>::<Event>`), the
  address as a hex string and the `u32` as a `0x…` string in `JSON.stringify` (BigInt values are
  used in the script). `read.ts` matches the key by its `::Marked` suffix.

Typing from the ABI, for CLI-01, **not tried here** (only the untyped path above is measured):
starknet.js 10.8.0 depends on `abi-wan-kanabi 2.2.4` and its `Contract` declares `typedv2`, which
types calls and events from an ABI given `as const`. A JSON file imported at run time is not
`as const`, so the two ways are (a) generate a `.ts` file from the class JSON at build time
(`export const markAbi = [...] as const`), or (b) generate the types and the ABI together from
`target/<profile>/*.contract_class.json`. Both start from the artefact `scarb build` already
writes; CLI-01 measures which is lighter to maintain.

## 5. Cost

Measured with `spikes/SPK-5b/measure.sh` (wall time, and `getrusage` peak resident memory of the
largest process), on a quiet lock, Scarb 2.19.4 and snforge 0.61.0:

| Command | Wall | Peak RSS (largest process) |
|---|---|---|
| `scripts/lock.sh scarb --manifest-path spikes/SPK-5b/Scarb.toml build` (`target/` removed first) | 3.2 s (8.4 s in the first measurement) | 636 MB (626 MB) |
| `snforge test` from `spikes/SPK-5b` (2 tests, build cache warm) | 6.5 s (7.5 s) | 718 MB (712 MB) |
| `scripts/with-node.sh spikes/SPK-5b/flow.sh` (node start, sncast × 5, reader) | 14.7 s | 612 MB |

The figures in parentheses are the first measurement, taken while the machine was busier (the
spread is the machine's, not the code's). The very first runs, with cold caches (dependencies,
`snforge_std`), took 21 s and 52 s; that figure includes any wait on the shared locks, which cannot
be separated. Test gas (l2 gas, measured;
`l1_data_gas` ~192 in both), budgets `ceil(1.05 × measured)`: `test_mark_writes_the_value` 1 007 250
to 1 007 350 between runs (budget 1 057 718), `test_mark_emits_marked` 975 100 (budget 1 023 855).
Both include declare and deploy of the class inside the test, so they are not the cost of `mark`
itself.

## 6. Open questions

For **FND-01b** (the game's scaffold):
- `scripts/lock.sh` now wraps `scarb --manifest-path <path> <subcommand>` (§3), but `snforge` still
  selects the package by the working directory (`-p <package>` from a workspace root works).
- `sncast declare` compiles the package itself in the `release` profile; the scaffold must decide
  whether the deployment script builds first (as `flow.sh` does) and whether the `release` profile
  carries the same `[cairo]` settings as `dev` (`sierra-replace-ids`, inlining).
- The log (its banner holds the pre-funded accounts' private keys) and the accounts file of
  `with-node.sh` / `flow.sh` go to `./.with-node/`, ignored by the root `.gitignore` since fix loop 1.
- `sncast` accounts are imported by private key from the node's banner: the deployment script of
  the game needs a policy for accounts on a node other than the local one (out of scope, ADR-0007
  says deployments to Sepolia are the orchestrator's).

For **SPK-11** (the indexer):
- Events were read from the receipt only. `starknet_getEvents` (filters, pagination, the block
  range, behaviour after a node restart) was not measured on devnet 0.10.0; SPK-11 must, since the
  indexer reads events from the node.
- Devnet mines each transaction in its own block by default and keeps its state in memory: an
  indexer test that restarts the node starts again from block 0.
- Devnet's default chain id is `SN_SEPOLIA` and its accounts are of its own class; whether the
  indexer needs anything from them is open.
- The throughput of devnet, for an indexer stress test, was not measured.

For the owner / orchestrator:
- `spikes/SPK-2/.tool-versions` and its README line are missing until SPK-2 is merged.
- `docs/briefs/SPK-2-cost.md` (and a running SPK-2) call `scripts/with-katana.sh`, which no longer
  exists. `spikes/SPK-5/` has its own copy since fix loop 1 (`spikes/SPK-5/with-katana.sh`);
  SPK-2 can do the same.
