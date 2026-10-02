#!/usr/bin/env bash
# SPK-13b: builds the game's contracts/ at one commit, on one thread, from a copy placed at a chosen
# absolute path, and records every artefact with SPK-13's collect.py (file and text sha256, sizes,
# class hash). The path is the variable under test: the copy is `git archive` of the commit, so
# only the place on disk changes between two runs.
#
#   spikes/SPK-13b/build_at.sh <dir> [--commit C] [--label L] [--out DIR] [--keep-target]
#
# <dir> must not exist; contracts/ lands in <dir>/contracts. Builds go through scripts/lock.sh
# (RAYON_NUM_THREADS=1 is set here, so the lock's default of 4 does not apply). Rows are appended
# to <out>/rows.tsv (default spikes/SPK-13b/.work/out) with the series `path:<L>`; the distinct
# programs are kept in <out>/kept. The copy is removed afterwards unless --keep-target.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/../.." && pwd)
spk13=$root/spikes/SPK-13

commit=90b4974f out=$here/.work/out label="" keep=0
[ $# -ge 1 ] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
dir=$1; shift
while [ $# -gt 0 ]; do
  case "$1" in
    --commit) commit=$2; shift 2 ;;
    --label) label=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --keep-target) keep=1; shift ;;
    *) echo "build_at.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ ! -e "$dir" ] || { echo "build_at.sh: $dir exists" >&2; exit 2; }
[ -n "$label" ] || label=$(printf '%s' "$dir" | wc -c | tr -d ' ')
mkdir -p "$dir" "$out"
dir=$(cd "$dir" && pwd)
echo "build_at.sh: contracts/ at $commit in $dir (path length ${#dir}, label $label)" >&2

git -C "$root" archive "$commit" contracts | tar -x -C "$dir"
manifest=$dir/contracts/Scarb.toml
# Light, and the VPS shim reads its first argument: subcommand first, the manifest's folder as cwd.
(cd "$(dirname "$manifest")" && scarb clean)
export RAYON_NUM_THREADS=1
log=$out/build-$label.log
{ "$root/scripts/lock.sh" scarb --manifest-path "$manifest" build --workspace &&
  "$root/scripts/lock.sh" scarb --manifest-path "$manifest" build --test --workspace; } > "$log" 2>&1 ||
  { tail -40 "$log" >&2; exit 1; }
python3 "$spk13/collect.py" rows "$dir/contracts/target/dev" "$out/rows.tsv" contracts "path:$label" 1 1 \
  --keep "$out/kept"
printf '%s\t%s\t%s\n' "$label" "${#dir}" "$dir" >> "$out/paths.tsv"
[ "$keep" = 1 ] || rm -rf "$dir"
