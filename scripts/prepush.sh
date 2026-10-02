#!/usr/bin/env bash
# The checks of CI that a local run can stop before a push (FND-13). It decides from the diff against
# the upstream branch (origin/main when there is none) plus the working tree what to run; --all runs
# every check. Every step runs; the summary lists the failures and the exit status is 1 if any failed.
# CI stays the gate: this script weakens nothing there.
#
# The build lock (VPS): every build goes through scripts/lock.sh --heavy, never around it, and waits at
# most PREPUSH_LOCK_WAIT seconds (default 90) for it. If the lock stays busy, the Cairo compile and the
# checks that build are skipped, one line says so, and that part exits 0 (CI compiles); fmt, the scripts'
# tests and every other failure still make the exit status 1. Where there is no flock (the Mac has no
# build lock, as scripts/lock.sh itself needs flock) the builds run directly and the full check runs.
#
#   scripts/prepush.sh [--all]
set -uo pipefail

lock_wait=${PREPUSH_LOCK_WAIT:-90}
have_flock=0
if command -v flock > /dev/null 2>&1; then have_flock=1; fi

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
skipped=()
lock_busy=0
# step <name> <command...>: run it, print its time, record a failure. A command that stopped because
# the build lock stayed busy (scripts/lock.sh's line) is a skip, not a failure.
step() {
  local name=$1 start end rc out status
  shift
  echo "::: $name"
  out=$(mktemp)
  start=$(date +%s.%N)
  "$@" 2>&1 | tee "$out"
  rc=${PIPESTATUS[0]}
  end=$(date +%s.%N)
  if [ "$rc" = 0 ]; then
    status=ok
  elif grep -q 'build lock busy for' "$out"; then
    status="SKIPPED (build lock busy for $lock_wait s)"
    lock_busy=1
    skipped+=("$name")
  else
    status="FAILED ($rc)"
    failed+=("$name")
  fi
  rm -f "$out"
  printf '::: %s: %s in %.1fs\n' "$name" "$status" "$(awk -v a="$start" -v b="$end" 'BEGIN { print b - a }')"
  last_rc=$rc
  return 0
}
# skip <name>: a step not run because the lock stayed busy.
skip() {
  echo "::: $1: skipped (build lock busy)"
  skipped+=("$1")
}

total_start=$(date +%s.%N)

# pkg <dir> <command...>: run a command from a package's own folder, so that asdf picks the package's
# own .tool-versions (some spikes pin older Scarb versions), as CI does.
pkg() {
  local dir=$1
  shift
  (cd "$root/$dir" && "$@")
}
# lockrun <command...>: through the machine's heavy lock, waiting at most lock_wait seconds; directly
# where there is no flock.
lockrun() {
  if [ "$have_flock" = 1 ]; then "$root/scripts/lock.sh" --heavy --wait "$lock_wait" "$@"; else "$@"; fi
}
# gas_check: gas_budgets.py takes the lock through lock.sh, which reads GRIMWORLD_LOCK_WAIT.
gas_check() {
  if [ "$have_flock" = 1 ]; then
    GRIMWORLD_LOCK_WAIT=$lock_wait python3 scripts/gas_budgets.py --check
  else
    python3 scripts/gas_budgets.py --check --no-lock
  fi
}
# pnpmrun <command...>: through the project lock where there is flock, waiting at most lock_wait seconds.
pnpmrun() {
  if [ "$have_flock" = 1 ]; then scripts/lock.sh --wait "$lock_wait" pnpm "$@"; else pnpm "$@"; fi
}
# vectors/check.py takes the lock through scripts/lock.sh when GRIMWORLD_LOCK_WAIT is set.
vectors_check() {
  if [ "$have_flock" = 1 ]; then
    GRIMWORLD_LOCK_WAIT=$lock_wait python3 contracts/logic/vectors/check.py
  else
    python3 contracts/logic/vectors/check.py
  fi
}

gas_docs_re='^docs/BUDGETS\.md$|^contracts/.*/GAS\.md$|^scripts/gas_budgets\.py$'
vectors_re='^contracts/logic/(src/|vectors/|Scarb\.toml$|Scarb\.lock$)|^contracts/Scarb\.(toml|lock)$|^\.tool-versions$'

# Cairo packages: the nearest Scarb.toml of each touched Cairo file (the contracts workspace is one
# package: contracts). A change of the root .tool-versions, or --all, takes every tracked one.
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
# vectors/check.py runs snforge: the contracts build is its probe of the lock.
if touched "$vectors_re" && ! grep -qx contracts <<< "$packages"; then
  packages=$(printf '%s\n' "$packages" contracts | grep . | sort -u)
fi

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
# around it: a build waits its turn, at most lock_wait seconds, then it is skipped.
built=0
for d in $packages; do
  if [ "$lock_busy" = 1 ]; then
    skip "build $d"
    continue
  fi
  if [ "$d" = contracts ]; then
    step "build contracts" pkg contracts lockrun scarb build --workspace
    if [ "$last_rc" = 0 ]; then built=1; fi
  else
    step "build $d" pkg "$d" lockrun scarb build
  fi
done

# Generated artefacts, only when their inputs changed.
if [ "$built" = 1 ] || { [ "$lock_busy" = 0 ] && touched "$gas_docs_re"; }; then
  step "gas_budgets.py --check" gas_check
elif [ "$lock_busy" = 1 ] && { touched '^contracts/' || touched "$gas_docs_re"; }; then
  skip "gas_budgets.py --check"
fi
if [ "$built" = 1 ]; then
  step "class_sizes.py" python3 contracts/tools/class_sizes.py
fi
if touched "$vectors_re"; then
  if [ "$built" = 1 ] && [ "$lock_busy" = 0 ]; then
    step "vectors check.py" vectors_check
  elif [ "$lock_busy" = 1 ]; then
    skip "vectors check.py"
  fi
fi
if touched '^contracts/tools/exp2_table\.py$|^contracts/logic/src/helpers/exp2_table\.cairo$|^client/sim/src/exp2\.ts$'; then
  step "exp2_table.py --check" python3 contracts/tools/exp2_table.py --check
fi

# The client (CI's client job).
if touched '^(client|indexer|services)/|(^|/)package\.json$|^pnpm-(lock|workspace)\.yaml$|^\.tool-versions$'; then
  if [ ! -d node_modules ] || touched '(^|/)package\.json$|^pnpm-(lock|workspace)\.yaml$'; then
    step "pnpm install" pnpmrun install --frozen-lockfile
  fi
  step "pnpm lint" pnpmrun lint
  step "pnpm typecheck" pnpmrun typecheck
  step "pnpm test" pnpmrun test
  step "prettier" pnpm exec prettier --check client indexer
fi

printf 'prepush: total %.1fs\n' "$(awk -v a="$total_start" -v b="$(date +%s.%N)" 'BEGIN { print b - a }')"
if [ "${#skipped[@]}" -gt 0 ]; then
  echo "prepush: build lock busy for $lock_wait s; Cairo compile skipped, CI will compile (skipped: ${skipped[*]})"
fi
if [ "${#failed[@]}" -gt 0 ]; then
  echo "prepush: FAILED: ${failed[*]}" >&2
  exit 1
fi
echo "prepush: all checks passed"
