#!/usr/bin/env bash
# SPK-5b: runs a build or test command of the throwaway package through the build lock, from the
# package's own folder. Scarb 2.19 takes --manifest-path before the subcommand
# (`scarb --manifest-path … build`), which scripts/lock.sh refuses (the subcommand must come
# first), so the package is selected by the working directory instead.
#   spikes/SPK-5b/locked.sh scarb build
#   spikes/SPK-5b/locked.sh snforge test
# Run from the repository root.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root/spikes/SPK-5b"
exec "$root/scripts/lock.sh" "$@"
