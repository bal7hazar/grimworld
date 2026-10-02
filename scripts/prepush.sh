#!/usr/bin/env bash
# The checks of CI that a local run can stop before a push (FND-13). It decides from the diff against
# the upstream branch (origin/main when there is none) plus the working tree what to run; --all runs
# every check. Every step runs; the summary lists the failures and the exit status is 1 if any failed.
# CI stays the gate: this script weakens nothing there. Heavy builds go through scripts/lock.sh.
#
#   scripts/prepush.sh [--all]
set -uo pipefail

root=$(git rev-parse --show-toplevel) || exit 2
cd "$root" || exit 2

all=0
case "${1:-}" in
  "") ;;
  --all) all=1 ;;
  *)
    echo "usage: scripts/prepush.sh [--all]" >&2
    exit 2
    ;;
esac

base=$(git rev-parse --verify -q '@{upstream}' 2> /dev/null || git rev-parse --verify -q origin/main 2> /dev/null || true)
if [ -n "$base" ]; then
  base=$(git merge-base "$base" HEAD 2> /dev/null || echo "$base")
fi
changed=$(
  {
    if [ -n "$base" ]; then git diff --no-renames --name-only "$base" HEAD; fi
    git diff --no-renames --name-only HEAD
    git ls-files --others --exclude-standard
  } | sort -u
)
if [ -z "$base" ]; then
  echo "prepush: no upstream and no origin/main: running every check" >&2
  all=1
fi
echo "prepush: base ${base:-none}; $(grep -c . <<< "$changed" || true) changed file(s)"

# touched <ere>: some changed file matches (always true with --all).
touched() { [ "$all" = 1 ] || grep -Eq "$1" <<< "$changed"; }

failed=()
# step <name> <command...>: run it, print its time, record a failure.
step() {
  local name=$1 start end rc
  shift
  echo "::: $name"
  start=$(date +%s.%N)
  "$@"
  rc=$?
  end=$(date +%s.%N)
  printf '::: %s: %s in %.1fs\n' "$name" "$([ "$rc" = 0 ] && echo ok || echo "FAILED ($rc)")" "$(awk -v a="$start" -v b="$end" 'BEGIN { print b - a }')"
  [ "$rc" = 0 ] || failed+=("$name")
  return 0
}

total_start=$(date +%s.%N)

# pkg <dir> <command...>: run a command from a package's own folder, so that asdf picks the package's
# own .tool-versions (some spikes pin older Scarb versions), as CI does.
pkg() {
  local dir=$1
  shift
  (cd "$root/$dir" && "$@")
}

# Cairo packages: the nearest Scarb.toml of each touched Cairo file (the contracts workspace is one
# package: contracts). A change of .tool-versions, or --all, takes every tracked one.
cairo_inputs='(\.cairo|(^|/)Scarb\.toml|(^|/)Scarb\.lock|(^|/)\.tool-versions)$'
if [ "$all" = 1 ] || grep -Eq '^\.tool-versions$' <<< "$changed"; then
  files=$(git ls-files '*Scarb.toml')
else
  files=$(grep -E "$cairo_inputs" <<< "$changed" || true)
fi
packages=$(
  while read -r f; do
    [ -n "$f" ] || continue
    d=$(dirname "$f")
    while [ "$d" != . ] && [ ! -f "$d/Scarb.toml" ]; do d=$(dirname "$d"); done
    [ -f "$d/Scarb.toml" ] || continue
    case "$d" in contracts | contracts/*) d=contracts ;; esac
    echo "$d"
  done <<< "$files" | sort -u
)

# Always: the format of the contracts workspace and of every package touched, as CI's cairo job.
# shellcheck disable=SC2086 # $packages is a newline-separated list of paths without spaces
fmt_dirs=$(printf '%s\n' contracts $packages | sort -u)
for d in $fmt_dirs; do
  step "scarb fmt --check ($d)" pkg "$d" scarb fmt --check --workspace
done
step "gas_budgets.py --self-test" python3 scripts/gas_budgets.py --self-test
if touched '^tools/art/'; then
  step "tools/art tests" python3 -m unittest discover -s tools/art/tests
fi

# Builds always go through the machine's heavy lock (lock.sh --heavy, the subcommand first), never
# around it: a build waits for its turn like any other.
built=0
for d in $packages; do
  if [ "$d" = contracts ]; then
    step "build contracts" pkg contracts "$root/scripts/lock.sh" --heavy scarb build --workspace
    built=1
  else
    step "build $d" pkg "$d" "$root/scripts/lock.sh" --heavy scarb build
  fi
done

# Generated artefacts, only when their inputs changed.
if [ "$built" = 1 ] || touched '^docs/BUDGETS\.md$|^contracts/.*/GAS\.md$|^scripts/gas_budgets\.py$'; then
  step "gas_budgets.py --check" python3 scripts/gas_budgets.py --check
fi
if [ "$built" = 1 ]; then
  step "class_sizes.py" python3 contracts/tools/class_sizes.py
fi
if touched '^contracts/logic/(src/|vectors/|Scarb\.toml$|Scarb\.lock$)|^contracts/Scarb\.(toml|lock)$|^\.tool-versions$'; then
  step "vectors check.py" python3 contracts/logic/vectors/check.py
fi
if touched '^contracts/tools/exp2_table\.py$|^contracts/logic/src/helpers/exp2_table\.cairo$|^client/sim/src/exp2\.ts$'; then
  step "exp2_table.py --check" python3 contracts/tools/exp2_table.py --check
fi

# The client (CI's client job).
if touched '^(client|indexer|services)/|(^|/)package\.json$|^pnpm-(lock|workspace)\.yaml$|^\.tool-versions$'; then
  if [ ! -d node_modules ] || touched '(^|/)package\.json$|^pnpm-(lock|workspace)\.yaml$'; then
    step "pnpm install" scripts/lock.sh pnpm install --frozen-lockfile
  fi
  step "pnpm lint" scripts/lock.sh pnpm lint
  step "pnpm typecheck" scripts/lock.sh pnpm typecheck
  step "pnpm test" scripts/lock.sh pnpm test
  step "prettier" pnpm exec prettier --check client indexer
fi

printf 'prepush: total %.1fs\n' "$(awk -v a="$total_start" -v b="$(date +%s.%N)" 'BEGIN { print b - a }')"
if [ "${#failed[@]}" -gt 0 ]; then
  echo "prepush: FAILED: ${failed[*]}" >&2
  exit 1
fi
echo "prepush: all checks passed"
