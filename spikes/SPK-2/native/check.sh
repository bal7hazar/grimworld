#!/usr/bin/env bash
# SPK-2 part 2: the pure logic of part 1 is copied, not rewritten (symbolic links would need
# approval in the agents' profile). Check the copies are still byte for byte identical.
#   spikes/SPK-2/native/check.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
status=0
for module in alchemy board fate fixtures rules tables; do
  if cmp -s "../src/$module.cairo" "src/$module.cairo"; then
    echo "same: src/$module.cairo"
  else
    echo "DIFFERENT: src/$module.cairo" >&2
    status=1
  fi
done
exit "$status"
