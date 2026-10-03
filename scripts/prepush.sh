#!/usr/bin/env bash
# The checks of CI that a local run can stop before a push (FND-13). It decides from the files the push
# brings that differ from main (FND-21, see compute_changed) plus the working tree what to run; --all runs
# every check. Every step runs; the summary lists the failures and the exit status is 1 if any failed.
# CI stays the gate: this script weakens nothing there.
#
# The build lock (VPS): every build goes through scripts/lock.sh --heavy, never around it, and waits at
# most PREPUSH_LOCK_WAIT seconds (default 90) for it. If the lock stays busy, the Cairo compile and the
# checks that build are skipped, one line says so, and that part exits 0 (CI compiles); fmt, the scripts'
# tests and every other failure still make the exit status 1. Where there is no flock (the Mac has no
# build lock, as scripts/lock.sh itself needs flock) the builds run directly and the full check runs.
#
#   scripts/prepush.sh [--all | --self-test]
set -uo pipefail

# No step inherits git's repository variables (FND-17: a hook in a linked worktree gets GIT_DIR, and a
# test's fixture `git init` then rewrote the shared repository): the repository is found from the folder.
# shellcheck disable=SC2046 # one variable name per word
unset $(git rev-parse --local-env-vars) $(compgen -v | grep '^GIT_CONFIG')

lock_wait=${PREPUSH_LOCK_WAIT:-90}
have_flock=0
if command -v flock > /dev/null 2>&1; then have_flock=1; fi

root=$(git rev-parse --show-toplevel) || exit 2
cd "$root" || exit 2

# compute_changed: sets `base` (what the push is measured against, empty when origin/main cannot be
# resolved) and `changed`. FND-21: the files the push brings (@{upstream}..HEAD, or all of the branch
# when there is no upstream) that ALSO differ from main (origin/main...HEAD, the branch's own changes
# against its merge base with main), plus the working tree. A file that main brought in through a merge
# and the branch did not change is not in the set. Origin/main unresolved: no base, every check runs.
compute_changed() {
  local main up pushed own
  main=$(git rev-parse --verify -q origin/main 2> /dev/null || true)
  up=$(git rev-parse --verify -q '@{upstream}' 2> /dev/null || true)
  base=
  own=
  if [ -n "$main" ]; then
    base=$(git merge-base "${up:-$main}" HEAD 2> /dev/null || echo "${up:-$main}")
    own=$(git diff --no-renames --name-only "$main"...HEAD 2> /dev/null || true)
    pushed=$(git diff --no-renames --name-only "$base" HEAD)
    # the pushed files that are also the branch's own
    pushed=$(comm -12 <(sort -u <<< "$pushed") <(sort -u <<< "$own"))
  else
    pushed=
  fi
  changed=$(
    {
      printf '%s\n' "$pushed"
      git diff --no-renames --name-only HEAD
      git ls-files --others --exclude-standard
    } | grep . | sort -u || true
  )
}

# --self-test (FND-21): scratch repositories with main moving under a branch that merges it. The git
# environment is sanitised as above, each repository lives in its own temporary directory.
self_test() {
  local work rc=0 g
  work=$(mktemp -d) || exit 2
  g() { git -c user.name=t -c user.email=t@t "$@"; }
  expect() { # <label> <expected files, space separated>
    local got
    got=$(tr '\n' ' ' <<< "$changed")
    if [ "$got" != "$2 " ] && [ "$got" != "$2" ]; then
      echo "self-test FAILED: $1: expected [$2], got [$got]" >&2
      rc=1
    else
      echo "self-test ok: $1"
    fi
  }
  (
    set -e
    git init -q --bare "$work/remote.git"
    git init -q -b main "$work/r"
    cd "$work/r"
    echo a > a.txt; echo b > b.txt; g add -A; g commit -q -m base
    git remote add origin "$work/remote.git"
    git push -q origin main; git fetch -q origin
    g checkout -q -b feature
    echo f1 > own1.txt; g add -A; g commit -q -m own1
    git push -q -u origin feature
    echo f2 > own2.txt; g add -A; g commit -q -m own2
    # main moves under the branch, the branch merges it
    g checkout -q main; echo m > from_main.txt; echo a2 > a.txt; g add -A; g commit -q -m main-moves
    git push -q origin main; git fetch -q origin
    g checkout -q feature; g merge -q --no-edit origin/main
    echo doc > doc.md; g add -A; g commit -q -m doc
    compute_changed; expect "upstream set, main merged" "doc.md own2.txt"
    git branch -q --unset-upstream
    compute_changed; expect "no upstream: all of the branch's own files" "doc.md own1.txt own2.txt"
    echo dirty >> own1.txt; echo new > untracked.txt
    compute_changed; expect "working tree added" "doc.md own1.txt own2.txt untracked.txt"
    git remote remove origin
    compute_changed; [ -z "$base" ] && echo "self-test ok: no origin/main: no base (every check runs)" \
      || { echo "self-test FAILED: no origin/main kept a base" >&2; exit 1; }
  ) || rc=1
  rm -rf "$work"
  exit "$rc"
}

all=0
case "${1:-}" in
  "") ;;
  --all) all=1 ;;
  --self-test) self_test ;;
  *)
    echo "usage: scripts/prepush.sh [--all | --self-test]" >&2
    exit 2
    ;;
esac

compute_changed
if [ -z "$base" ]; then
  echo "prepush: no origin/main: running every check" >&2
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
if touched '^scripts/prepush\.sh$'; then
  step "prepush.sh --self-test" scripts/prepush.sh --self-test
fi
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
