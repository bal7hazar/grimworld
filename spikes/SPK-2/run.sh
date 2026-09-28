#!/usr/bin/env bash
# SPK-2: migrate the world to the local Katana and send the measured actions as transactions;
# prints one JSON line per transaction (resources and fee from the receipt). Meant to run under
# scripts/with-katana.sh, from the repository root:
#   scripts/with-katana.sh bash spikes/SPK-2/run.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

manifest=spikes/SPK-2/Scarb.toml
katana --version
scripts/lock.sh sozo build --manifest-path "$manifest" > /dev/null
scripts/lock.sh sozo migrate --manifest-path "$manifest" > /dev/null
python3 spikes/SPK-2/katana.py
