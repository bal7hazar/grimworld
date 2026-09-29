#!/usr/bin/env bash
# Builds option (b): the runner natively and to WebAssembly, then the bindings.
# Run from the worktree root: spikes/SPK-4/vm/build.sh
# Toolchain: 1.89.0 (vm/runner/rust-toolchain.toml; the one with the wasm32 target on the machine).
# wasm-bindgen-cli must equal the lockfile's wasm-bindgen (0.2.129); it is installed under vm/tools:
#   cargo install --root spikes/SPK-4/vm/tools wasm-bindgen-cli --version 0.2.129 --locked -j 4
set -euo pipefail
vm=spikes/SPK-4/vm
(cd "$vm/runner" && cargo build --release --bin spk4-run -j 4)
(cd "$vm/runner" && cargo build --release --lib --target wasm32-unknown-unknown -j 4)
wasm="$vm/runner/target/wasm32-unknown-unknown/release/spk4_runner.wasm"
"$vm/tools/bin/wasm-bindgen" --target web --out-dir "$vm/pkg-web" "$wasm"
ls -l "$vm/pkg-web/spk4_runner_bg.wasm"
