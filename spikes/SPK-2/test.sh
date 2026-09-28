#!/usr/bin/env bash
# SPK-2 part 1 (the Dojo baseline): build and test with this folder's pins, under the build locks.
# From the repository root:
#   spikes/SPK-2/test.sh > spikes/SPK-2/sozo-test-output.txt
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
scarb --version | head -1
./locked.sh sozo build --manifest-path Scarb.toml
./locked.sh sozo test --manifest-path Scarb.toml
