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
    if [ -n "$base" ]; then git diff --name-only "$base" HEAD; fi
    git diff --name-only HEAD
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

# Always.
step "scarb fmt --check" bash -c 'cd contracts && scarb fmt --check --workspace'
step "gas_budgets.py --self-test" python3 scripts/gas_budgets.py --self-test
if touched '^tools/art/'; then
  step "tools/art tests" python3 -m unittest discover -s tools/art/tests
fi

# Cairo: the packages touched; no Cairo source, manifest, lock or .tool-versions changed: no compile. The contracts workspace is one build (CI: `scarb build --workspace`).
cairo_inputs='(\.cairo|/Scarb\.toml|/Scarb\.lock)$|^\.tool-versions$'
contracts_inputs='^contracts/(.*/)?(Scarb\.toml|Scarb\.lock)$|^contracts/.*\.cairo$|^\.tool-versions$'
built=0
if touched "$contracts_inputs"; then
  step "build contracts" scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build --workspace
  built=1
fi
# Any other package (a spike, the emitter): the nearest Scarb.toml of each touched Cairo file.
others=$(
  if [ "$all" = 1 ]; then
    git ls-files '*Scarb.toml'
  else
    grep -E "$cairo_inputs" <<< "$changed" | while read -r f; do
      d=$(dirname "$f")
      while [ "$d" != . ] && [ ! -f "$d/Scarb.toml" ]; do d=$(dirname "$d"); done
      [ -f "$d/Scarb.toml" ] && echo "$d/Scarb.toml"
    done
  fi | grep -Ev '^contracts/|^Scarb\.toml$' | sort -u
)
for m in $others; do
  step "build $(dirname "$m")" scripts/lock.sh scarb --manifest-path "$m" build
done

# Generated artefacts, only when their inputs changed.
if [ "$built" = 1 ]; then
  step "gas_budgets.py --check" python3 scripts/gas_budgets.py --check
  step "class_sizes.py" python3 contracts/tools/class_sizes.py
fi
if touched '^contracts/logic/src/|^contracts/logic/vectors/'; then
  step "vectors check.py" python3 contracts/logic/vectors/check.py
fi
if touched '^contracts/tools/exp2_table\.py$|^contracts/logic/src/helpers/exp2_table\.cairo$|^client/sim/src/exp2\.ts$'; then
  step "exp2_table.py --check" python3 contracts/tools/exp2_table.py --check
fi

# The client (CI's `client` job).
if touched '^(client|indexer)/|^package\.json$|^pnpm-(lock|workspace)\.yaml$|^\.tool-versions$'; then
  if [ ! -d node_modules ]; then
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
