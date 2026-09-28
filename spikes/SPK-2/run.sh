#!/usr/bin/env bash
# SPK-2 part 1 (the Dojo baseline): migrate the world to the local Katana and send the measured
# actions as transactions; prints one JSON line per transaction (resources and fee from the
# receipt). Runs under this folder's with-katana.sh, from the repository root:
#   spikes/SPK-2/with-katana.sh bash run.sh
# It uses this folder's .tool-versions (scarb 2.13.1, sozo 1.8.7, katana 1.7.1), not the root's
# native set, and calls sozo through ./locked.sh (scripts/lock.sh no longer wraps sozo, ADR-0007).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

katana --version
./locked.sh sozo build --manifest-path Scarb.toml > /dev/null
./locked.sh sozo migrate --manifest-path Scarb.toml > /dev/null
python3 katana.py
