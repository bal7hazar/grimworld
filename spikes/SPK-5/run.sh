#!/usr/bin/env bash
# SPK-5: migrate the world to the local Katana, write the model through the system, read it back
# from Torii with dojo.js. Meant to run under the nodes of this folder's with-katana.sh:
#   spikes/SPK-5/with-katana.sh --torii --world <address> bash run.sh [value]
# The Dojo baseline: it runs with this folder's .tool-versions (scarb 2.13.1, sozo 1.8.7, katana
# 1.7.1, torii 1.8.16; asdf install them from here), not with the root's native set, and calls sozo
# directly (scripts/lock.sh no longer wraps it, ADR-0007).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

manifest=Scarb.toml
value=${1:-42}

# The world address depends on the artifacts in target/: always migrate what `sozo build` just made
# (the artifacts left by `sozo test` give another world address, so Torii would index the wrong one).
sozo build --manifest-path "$manifest"
sozo migrate --manifest-path "$manifest"
sozo execute --manifest-path "$manifest" --wait spk5-mark mark "$value"
node read-model.ts "$value"
