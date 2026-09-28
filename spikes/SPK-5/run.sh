#!/usr/bin/env bash
# SPK-5: migrate the world to the local Katana, write the model through the system, read it back
# from Torii with dojo.js. Meant to run under the nodes of scripts/with-katana.sh:
#   scripts/with-katana.sh --torii --world <address> bash spikes/SPK-5/run.sh
# Run from the repository root (the lock and the scripts are called as scripts/…).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

manifest=spikes/SPK-5/Scarb.toml
value=${1:-42}

scripts/lock.sh sozo migrate --manifest-path "$manifest"
sozo execute --manifest-path "$manifest" --wait spk5-mark mark "$value"
node spikes/SPK-5/read-model.ts "$value"
