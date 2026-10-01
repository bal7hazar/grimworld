#!/usr/bin/env bash
# SPK-13: clone the map library (public, bal7hazar/hexx-cairo) at the commit the brief names, into
# the spike's ignored folder. Read only: nothing is ever committed or pushed from the clone.
#
#   spikes/SPK-13/fetch-library.sh [commit]     (default 310b5f1)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
commit=${1:-310b5f1}
dest="$here/.work/hexx-cairo"
if [ ! -d "$dest/.git" ]; then
  mkdir -p "$here/.work"
  git clone --quiet https://github.com/bal7hazar/hexx-cairo.git "$dest"
fi
cd "$dest"
git fetch --quiet origin
git checkout --quiet --detach "$commit"
git log -1 --format='%H %cs %s'
