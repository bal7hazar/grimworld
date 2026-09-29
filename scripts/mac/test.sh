#!/opt/homebrew/bin/bash
# Tests of scripts/mac/agent.sh, on the Mac, with stub CLIs: they never start a real agent and never
# spend a token. Everything they create lives in one test home, scripts/mac/test/run.<id> (the
# launcher's test mode: its slots, launch lock, repository, logs and stubs), and in launchd jobs
# labelled grimworld.cv.test.<task>.<hhmmss>, whose task names carry <id>. The cleanup stops each job
# by its task (scripts/mac/agent.sh stop), boots out every label it recorded, by exact label, removes
# the test home by its exact path, and checks that nothing is left (AC-11).
# Prints one `ok` or `FAIL` line per case; exits 1 if any case fails.
# The conditions are code in single quotes on purpose, expanded by `bash -c` or by checkx's eval.
# shellcheck disable=SC2016
if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 5 ]; then
  echo "scripts/mac/test.sh: needs bash 5 (/opt/homebrew/bin/bash)" >&2
  exit 2
fi
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
A=$here/agent.sh
DOMAIN=gui/$(id -u)
mkdir -p "$here/test"
run=$(mktemp -d "$here/test/run.XXXXXX") || exit 2
id=${run##*/run.}
touch "$run/.grimworld-mac-test"
fails=0 labels=() tasks=()

ok() { echo "ok   $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { # <name> <command…>
  local name=$1; shift
  if "$@"; then ok "$name"; else fail "$name"; fi
}
checkx() { # <name> <code, evaluated in this shell (its functions and variables)>
  if eval "$2"; then ok "$1"; else fail "$1"; fi
}
# The launcher, in the test home, with decoy secrets in the caller's environment (AC-3).
agent() {
  HOME=$run STARKNET_PRIVATE_KEY=decoy ANTHROPIC_BASE_URL=decoy CLAUDE_CODE_OAUTH_TOKEN=decoy \
    ATLANTIC_API_KEY=decoy GH_TOKEN=decoy SCARB_REGISTRY_AUTH_TOKEN=decoy OPENAI_API_KEY=decoy \
    "$A" "$@"
}
W=$run/repo/.claude/worktrees
L=$W/logs
# Every task of this run is named <id>-<case>, so every label it can create starts with PREFIX; the
# cleanup never acts on a label outside it.
PREFIX=grimworld.cv.test.$id-
record() { # <task>: remember the task BEFORE launching it, so that an interruption cannot lose it
  tasks+=("$1")
}
job_state() { # <label> -> running | not-running | absent
  local out
  out=$(launchctl print "$DOMAIN/$1" 2> /dev/null) || { echo absent; return; }
  if grep -qE $'^\tstate = running$' <<< "$out"; then echo running; else echo not-running; fi
}
job_pid() { launchctl print "$DOMAIN/$1" 2> /dev/null | sed -nE $'s/^\tpid = ([0-9]+)$/\\1/p' | head -1; }
# wait_for runs its condition again on every try: pass a command or a function, never a value
# computed once by the caller (`test "$(…)" = x` would be evaluated before the first try).
wait_for() { # <seconds> <condition command…>
  local n=$(($1 * 10)); shift
  while [ "$n" -gt 0 ]; do "$@" && return 0; sleep 0.1; n=$((n - 1)); done
  return 1
}
label_absent() { [ "$(job_state "$1")" = absent ]; }   # queries launchd on every call
nothing_runs_for() { ! pgrep -f -- "$1" > /dev/null; }  # a read: no process names the task (<id>-…)
pid_gone() { ! kill -0 "$1" 2> /dev/null; }

# Launchers started in the background (the race, the drain test): their exact pids, so that a
# cleanup can stop them before it scans the labels. A pid is in `inflight` only while it is an
# unreaped child of this runner: reap_bg removes it the moment it is waited for, so no signal can
# ever reach a pid the system has reused.
inflight=()
track_bg() { # <command…>: run it in the background as the tracked process itself
  (exec "$@") &
  inflight+=("$!")
}
agent_bg() { # <output file> <launcher arguments…>: the launcher itself is the background process
  local out=$1; shift
  track_bg env HOME="$run" STARKNET_PRIVATE_KEY=decoy ANTHROPIC_BASE_URL=decoy CLAUDE_CODE_OAUTH_TOKEN=decoy \
    ATLANTIC_API_KEY=decoy GH_TOKEN=decoy "$A" "$@" > "$out" 2>&1
}
reap_bg() { # <pid>: wait for one tracked process, remove it from `inflight` at once; returns its status
  local rc=0 q keep=()
  wait "$1" 2> /dev/null || rc=$?
  for q in "${inflight[@]}"; do [ "$q" = "$1" ] || keep+=("$q"); done
  inflight=("${keep[@]}")
  return "$rc"
}
in_inflight() { local q; for q in "${inflight[@]}"; do [ "$q" = "$1" ] && return 0; done; return 1; }
# Stop the in-flight launchers by their exact pids: each is frozen (SIGSTOP, so that it cannot start
# a new command), its direct children are listed by parent pid (pgrep -P, never a name pattern),
# then it gets TERM and CONT. Each launcher is reaped (and leaves `inflight`), then every child it
# had must exit within KID_BOUND seconds: a `launchctl bootstrap` under way must end before the labels
# are scanned. Children are waited for, not signalled. A child still alive past the bound stays in
# `kids_pending` (a later drain waits for it again) and makes this fail: the labels are not scanned.
KID_BOUND=30
kids_pending=()
INFLIGHT_RC=""   # the exit statuses of the launchers stopped last (143: stopped by the TERM)
stop_inflight() {
  local p c rc alive=()
  for p in "${inflight[@]}"; do
    kill -STOP "$p" 2> /dev/null || continue
    while read -r c; do [ -n "$c" ] && kids_pending+=("$c"); done < <(pgrep -P "$p" 2> /dev/null)
    kill -TERM "$p" 2> /dev/null; kill -CONT "$p" 2> /dev/null
  done
  INFLIGHT_RC=""
  while [ "${#inflight[@]}" -gt 0 ]; do
    p=${inflight[0]}; rc=0; reap_bg "$p" || rc=$?; INFLIGHT_RC="$INFLIGHT_RC $rc"
  done
  for c in "${kids_pending[@]}"; do wait_for "$KID_BOUND" pid_gone "$c" || alive+=("$c"); done
  kids_pending=("${alive[@]}")
  [ "${#kids_pending[@]}" = 0 ]
}

# Every exact label this run may have created, recovered from its own files: the label files
# (logs/*.label) and the job definitions the launcher wrote (logs/<label>.plist), whatever the test
# managed to record. Only labels of this run's prefix, and of the launcher's form, are kept.
run_labels() {
  local f l
  shopt -s nullglob
  {
    for f in "$L"/*.label; do cat "$f"; echo; done
    for f in "$L"/*.plist; do f=${f##*/}; echo "${f%.plist}"; done
  } | while IFS= read -r l; do
    case $l in "$PREFIX"*) [[ ${l#"$PREFIX"} =~ ^[A-Za-z0-9]+\.[0-9]{6}$ ]] && echo "$l" ;; esac
  done | sort -u
  shopt -u nullglob
}
# Stop and boot out one job of this run by its exact label: its process group first (launchd makes
# the job a group leader; AbandonProcessGroup keeps a bootout from reaching the stub), then bootout.
stop_label() { # <label>
  local l=$1 pid pgid
  case $l in "$PREFIX"*) ;; *) return 1 ;; esac
  pid=$(job_pid "$l")
  if [ -n "$pid" ]; then
    pgid=$(ps -o pgid= -p "$pid" 2> /dev/null | tr -d ' ')
    if [ "$pgid" = "$pid" ]; then kill -TERM -- "-$pid" 2> /dev/null; else kill -TERM "$pid" 2> /dev/null; fi
  fi
  launchctl bootout "$DOMAIN/$l" 2> /dev/null
  wait_for 5 label_absent "$l"
}
# drain: nothing of this run stays loaded. First the in-flight launchers (above), then the tasks
# (agent.sh stop), then every label recovered from the run's files; then a check, after a pause, of
# the recovered labels and of launchd's list for this run's prefix (a check only: nothing is ever
# done to a label that is not recovered from this run's files). Returns 1 and sets DRAIN_LEFT if any
# is still loaded.
DRAIN_LEFT=""
drain() {
  local t l
  DRAIN_LEFT=""
  if ! stop_inflight; then
    DRAIN_LEFT=" children of stopped launchers still alive after ${KID_BOUND} s: ${kids_pending[*]} (labels not scanned)"
    return 1
  fi
  rm -f "$run"/hold.* "$run/test-hang"
  for t in "${tasks[@]}"; do agent stop "$t" > /dev/null 2>&1; done
  for l in $(run_labels); do
    labels+=("$l")
    label_absent "$l" || stop_label "$l"
  done
  sleep 0.5
  DRAIN_LEFT=""
  for l in $(run_labels); do label_absent "$l" || DRAIN_LEFT="$DRAIN_LEFT $l"; done
  l=$(launchctl list | awk '{ print $3 }' | grep -F "$PREFIX" || true)
  [ -z "$l" ] || DRAIN_LEFT="$DRAIN_LEFT $(echo "$l" | tr '\n' ' ')"
  [ -z "$DRAIN_LEFT" ]
}
cleaned=0
cleanup() {
  [ "$cleaned" = 0 ] || return 0
  cleaned=1
  trap '' INT TERM   # a second signal must not cut the cleanup short
  # The home is removed only when every label is verified gone; otherwise it is kept, and said.
  if ! drain; then
    echo "FAIL cleanup: still loaded:$DRAIN_LEFT; the test home $run is kept" >&2
    return 1
  fi
  [ ! -d "$run/orchestrator/slots" ] || chmod 755 "$run/orchestrator/slots"   # read-only by design
  rm -rf "$run"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# --- The stubs: they print what they were given and hold while $HOME/hold.<task> exists (60 s at most).
mkdir -p "$run/bin"
cat > "$run/bin/claude" << 'EOF'
#!/bin/bash
if [ "$1 $2" = "auth status" ]; then cat "$HOME/stub-auth.json"; exit 0; fi
t=${GW_TASK:-none}
printf '%s\n' "$@" > "$HOME/argv.$t"
printf '%s\n' "$0" > "$HOME/argv0.$t"
/usr/bin/perl -e 'print "$_\n" for sort keys %ENV' > "$HOME/env.$t"
printf 'CLAUDE_CONFIG_DIR=%s\nTMPDIR=%s\nPATH=%s\n' "$CLAUDE_CONFIG_DIR" "$TMPDIR" "$PATH" > "$HOME/vals.$t"
dir=$HOME/.claude-b7r/projects/$(printf '%s' "$PWD" | sed 's#[/.]#-#g')
mkdir -p "$dir"
echo '{"type":"assistant","message":{"model":"claude-opus-5-5"}}' | sed 's/ //g' > "$dir/stub.jsonl"
echo "stub claude ran in $PWD"
for _ in $(seq 1 600); do [ -f "$HOME/hold.$t" ] || break; sleep 0.1; done
exit 0
EOF
cat > "$run/bin/codex" << 'EOF'
#!/bin/bash
if [ "$1 $2" = "login status" ]; then echo "Logged in using ChatGPT"; exit 0; fi
t=${GW_TASK:-none}
printf '%s\n' "$@" > "$HOME/argv.$t"
/usr/bin/perl -e 'print "$_\n" for sort keys %ENV' > "$HOME/env.$t"
echo "model: gpt-6-sol"
for _ in $(seq 1 600); do [ -f "$HOME/hold.$t" ] || break; sleep 0.1; done
exit 0
EOF
chmod +x "$run/bin/claude" "$run/bin/codex"

# --- A repository of the test home, with its own origin, from which worktrees are cut.
(
  export HOME=$run GIT_CONFIG_NOSYSTEM=1
  g=(git -c user.name=test -c user.email=test@invalid -c init.defaultBranch=main)
  "${g[@]}" init -q --bare "$run/origin.git" &&
    "${g[@]}" init -q "$run/seed" && echo seed > "$run/seed/README" &&
    "${g[@]}" -C "$run/seed" add README && "${g[@]}" -C "$run/seed" commit -q -m seed &&
    "${g[@]}" -C "$run/seed" push -q "$run/origin.git" main &&
    "${g[@]}" clone -q "$run/origin.git" "$run/repo"
) || { echo "FAIL setup: the test repository"; exit 1; }

good_auth='{"loggedIn": true, "authMethod": "claude.ai", "email": "claude-b7r@proton.me"}'

# --- AC-1: the account check refuses before anything is created.
for variant in '{"loggedIn": true, "email": "bal7hazar@example.com"}' \
  '{"loggedIn": false, "email": "claude-b7r@proton.me"}' \
  'loggedIn: true email: claude-b7r@proton.me' \
  '{"loggedIn": true, "email": "x"} {"loggedIn": true, "email": "claude-b7r@proton.me"}'; do
  printf '%s\n' "$variant" > "$run/stub-auth.json"
  t=$id-A1
  agent --branch "cv/$t" "$t" claude opus new "hello" implement > "$run/out" 2>&1; rc=$?
  check "AC-1 account refused ($variant): exit 5, no worktree, log, lock or job" \
    test "$rc" = 5 -a ! -e "$W/cli-$t" -a ! -e "$L/$t.log" -a ! -e "$L/$t.label" -a ! -e "$run/orchestrator"
done
check "AC-1 no job was created for A1" bash -c "! launchctl list | grep -qF 'grimworld.cv.test.$id-A1'"
printf '%s\n' "$good_auth" > "$run/stub-auth.json"

# --- The slots of the test home.
SL=$run/orchestrator/slots
mkdir -p "$SL" && : > "$SL/cv-1" && : > "$SL/cv-2" && chmod 555 "$SL"   # a Mac as CV-01 left it: two free slots
# shellcheck disable=SC2034 # read by checkx
ino1=$(stat -f %i "$SL/cv-1")
# shellcheck disable=SC2034 # read by checkx
ino2=$(stat -f %i "$SL/cv-2")
agent slots-init > /dev/null 2>&1; rc=$?
checkx "AC-1 slots-init on a directory holding cv-1 and cv-2 (free): adds cv-3, cv-4, cv-5, keeps cv-1 and cv-2 (same files), directory read-only" \
  'test "$rc" = 0 && test -f "$SL/cv-3" -a -f "$SL/cv-4" -a -f "$SL/cv-5" && test ! -e "$SL/cv-6" &&
   test "$(stat -f %i "$SL/cv-1")" = "$ino1" -a "$(stat -f %i "$SL/cv-2")" = "$ino2" && test "$(stat -f %Lp "$SL")" = 555'
checkx "AC-1 slots lists the five slots, all free" 'test "$(agent slots | grep -c " free")" = 5'

# --- AC-9: refusals.
agent --with-sepolia "$id-X" claude opus new "hello" implement > /dev/null 2>&1
check "AC-9 --with-sepolia refused (exit 2)" test $? = 2
agent "$id-X" claude opus-4 new "hello" implement > /dev/null 2>&1
check "AC-9 unknown model refused (exit 2)" test $? = 2
agent "$id-X" codex gpt-5 new "hello" audit > /dev/null 2>&1
check "AC-9 unknown codex model refused (exit 2)" test $? = 2
echo 18.01 > "$run/test-load5"
agent thresholds > /dev/null 2>&1; rc=$?
agent --branch "cv/$id-X" "$id-X" claude opus new "hello" implement > /dev/null 2>&1; rc2=$?
check "AC-3 load above 18 refuses (thresholds and launch: exit 4, no worktree)" test "$rc" = 4 -a "$rc2" = 4 -a ! -e "$W/cli-$id-X"
echo 18 > "$run/test-load5"
agent thresholds > /dev/null 2>&1
check "AC-3 load of exactly 18 is accepted (exit 0)" test $? = 0
echo 11.5 > "$run/test-load5"
agent thresholds > /dev/null 2>&1
check "AC-3 load of 11.5, above the former 10, is accepted (exit 0)" test $? = 0
rm -f "$run/test-load5"; echo 7 > "$run/test-mem-gb"
agent thresholds > /dev/null 2>&1
check "AC-9 memory under 8 GB refuses (exit 4)" test $? = 4
rm -f "$run/test-mem-gb"
agent thresholds > /dev/null 2>&1
check "thresholds pass with the machine's own values" test $? = 0
HOME=$here "$A" status > /dev/null 2>&1
check "a HOME that is neither the user's nor a test home is refused" test $? = 2

# --- AC-4: the built command (dry run).
t=$id-D4
out=$(agent --dry-run "$t" claude opus new "hello" implement 2>&1)
line=$(grep -v '^#' <<< "$out" | head -1)
eval "argv=($line)"
has() { local a; for a in "${argv[@]}"; do [ "$a" = "$1" ] && return 0; done; return 1; }
has_all() { local r; for r in "$@"; do has "$r" || { echo "  missing: $r"; return 1; }; done; }
check "AC-4 dry run: profile rules, Mac deny rules, --settings, --name" has_all \
  --permission-mode acceptEdits 'Bash(git commit *)' 'Bash(git rebase*)' 'Bash(launchctl*)' \
  'Bash(* launchctl*)' 'Bash(open *)' 'Bash(osascript*)' 'Bash(caffeinate*)' 'Bash(security *)' \
  'Bash(scripts/mac/agent.sh*)' 'Bash(./scripts/mac/agent.sh*)' 'Bash(bash scripts/mac/agent.sh*)' \
  'Read(~/.claude-b7r/**)' 'Read(~/.codex/**)' 'Read(~/.config/gh/**)' 'Bash(* ~/.claude-b7r*)' \
  'Bash(* $HOME/.claude-b7r*)' --settings \
  '{"env":{"SCARB_REGISTRY_AUTH_TOKEN":"","STARKNET_NETWORK":"","STARKNET_RPC_URL":"","STARKNET_RPC":"","STARKNET_ACCOUNT_ADDRESS":"","STARKNET_PRIVATE_KEY":"","ATLANTIC_API_KEY":""}}' \
  --name "[Opus 5.5] $t" --model claude-opus-5-5
check "AC-4 dry run: never --dangerously-skip-permissions" bash -c "! grep -q -- dangerously <<< \"\$1\"" _ "$out"
check "AC-4 dry run: the foreground rule ends the prompt" \
  bash -c 'grep -qF "Foreground only: never run a command in the background and never end your turn waiting for one; in headless mode that ends the session. Your turn ends when REPORT.md is written." <<< "$1"' _ "${argv[2]}"
out=$(agent --dry-run "$id-C4" codex gpt-6-sol new "audit" 2>&1)
line=$(grep -v '^#' <<< "$out" | head -1); eval "argv=($line)"
check "AC-4 dry run codex: exec -s read-only, profile audit" has_all exec -s read-only -m gpt-6-sol
check "AC-4 dry run codex: header [GPT-6-Sol] … (audit)" bash -c 'grep -qF "# [GPT-6-Sol] $2-C4 new (audit)" <<< "$1"' _ "$out" "$id"
agent --dry-run "$id-C4" codex gpt-6-sol new "audit" implement > /dev/null 2>&1
check "AC-4 codex with another profile than audit is refused" test $? = 2

# --- CV-02, AC-4: the CLIs by absolute path, from the table (a dry run in the user's real home
# launches and checks nothing), and a missing or non-executable binary refuses.
real_home=$(/usr/bin/perl -e 'print((getpwuid($<))[7])')
out=$("$A" --dry-run "$id-D6" claude opus new "hello" implement 2>&1)
line=$(grep -v '^#' <<< "$out" | head -1); eval "argv=($line)"
checkx "AC-4 the real table: claude is $real_home/.asdf/installs/nodejs/22.22.2/bin/claude" \
  'test "${argv[0]}" = "$real_home/.asdf/installs/nodejs/22.22.2/bin/claude"'
checkx "AC-6 the dry run shows the new PATH, the shims first, no nodejs/22.22.2" \
  'pl=$(grep "^# PATH " <<< "$out") && test "$pl" = "# PATH $real_home/.asdf/shims:$real_home/go/bin:$real_home/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" && ! grep -q "nodejs/22.22.2" <<< "$pl"'
out=$("$A" --dry-run "$id-D6" codex gpt-6-sol new "audit" 2>&1)
line=$(grep -v '^#' <<< "$out" | head -1); eval "argv=($line)"
checkx "AC-4 the real table: codex is $real_home/.local/bin/codex" 'test "${argv[0]}" = "$real_home/.local/bin/codex"'
out=$(agent --dry-run "$id-D6" claude opus new "hello" implement 2>&1)
line=$(grep -v '^#' <<< "$out" | head -1); eval "argv=($line)"
checkx "AC-4 test mode: the stub table stands in, claude is $run/bin/claude" 'test "${argv[0]}" = "$run/bin/claude"'
for cli in claude codex; do
  m=opus; [ "$cli" = claude ] || m=gpt-6-sol
  mv "$run/bin/$cli" "$run/bin/$cli.away"
  agent --branch "cv/$id-M4" "$id-M4" "$cli" "$m" new "hello" > "$run/out" 2>&1; rc=$?
  checkx "AC-4 $cli binary missing: refused (exit 2) before the account check, nothing created" \
    'test "$rc" = 2 && grep -q "missing or not executable" "$run/out" && test ! -e "$W/cli-$id-M4" -a ! -e "$L/$id-M4.log" -a ! -e "$L/$id-M4.label"'
  mv "$run/bin/$cli.away" "$run/bin/$cli"
  chmod -x "$run/bin/$cli"
  agent --branch "cv/$id-M4" "$id-M4" "$cli" "$m" new "hello" > "$run/out" 2>&1; rc=$?
  checkx "AC-4 $cli binary not executable: refused (exit 2), nothing created" \
    'test "$rc" = 2 && grep -q "missing or not executable" "$run/out" && test ! -e "$W/cli-$id-M4" -a ! -e "$L/$id-M4.log"'
  chmod +x "$run/bin/$cli"
done

# --- Audit 2, A3: task names starting with `test.`. Outside test mode (the user's real home, a dry
# run: nothing is created, nothing is run) they are refused, so that no real label reads as a test
# label; an ordinary name is accepted there. In test mode such a name is accepted.
out=$("$A" --dry-run "test.$id-D5" claude opus new "hello" implement 2>&1); rc=$?
checkx "A3 outside test mode, a task named test.<…> is refused (exit 2)" \
  'test "$rc" = 2 && grep -qF "test.$id-D5" <<< "$out" && grep -qF "starts the labels of the tests only" <<< "$out"'
out=$("$A" --dry-run "$id-D5" claude opus new "hello" implement 2>&1); rc=$?
checkx "A3 outside test mode, an ordinary name is accepted, with a real label grimworld.cv.<task>.<hhmmss>" \
  'test "$rc" = 0 && grep -qE "launchd job gui/[0-9]+/grimworld\.cv\.$id-D5\.[0-9]{6} " <<< "$out"'
out=$(agent --dry-run "test.$id-D5" claude opus new "hello" implement 2>&1); rc=$?
checkx "A3 in test mode, test.<…> is accepted, with a test label grimworld.cv.test.test.<task>.<hhmmss>" \
  'test "$rc" = 0 && grep -qE "launchd job gui/[0-9]+/grimworld\.cv\.test\.test\.$id-D5\.[0-9]{6} " <<< "$out"'
out=$(agent --dry-run "$id-D5" claude opus new "hello" implement 2>&1); rc=$?
checkx "A3 in test mode, the run's own names (<id>-<case>) are accepted, with the prefix $PREFIX" \
  'test "$rc" = 0 && grep -qE "launchd job gui/[0-9]+/${PREFIX//./\\.}D5\.[0-9]{6} " <<< "$out"'

# --- AC-2, AC-3, AC-4, AC-8: a real launch of the claude stub.
t=$id-T2
touch "$run/hold.$t"
record "$t"
bash -c 'HOME="$1" STARKNET_PRIVATE_KEY=decoy ANTHROPIC_BASE_URL=decoy CLAUDE_CODE_OAUTH_TOKEN=decoy ATLANTIC_API_KEY=decoy GH_TOKEN=decoy "$2" --branch "cv/$3" "$3" claude opus new "hello" implement; exit $?' \
  _ "$run" "$A" "$t" > "$run/out" 2>&1; rc=$?
check "launch of $t: exit 0, holds a slot" bash -c 'test "$1" = 0 && grep -q "holds slot cv-" "$2"' _ "$rc" "$run/out"
label=$(cat "$L/$t.label" 2> /dev/null)
check "AC-8 the label is grimworld.cv.test.$t.<hhmmss>" bash -c '[[ $1 =~ ^grimworld\.cv\.test\.'"$t"'\.[0-9]{6}$ ]]' _ "$label"
pid=$(job_pid "$label")
check "AC-2 the job's process is alive after the launching shell exited" kill -0 "${pid:-0}"
check "AC-2 the job's parent is launchd (pid 1)" test "$(ps -o ppid= -p "${pid:-0}" | tr -d ' ')" = 1
check "AC-2 the job runs at nice 10" test "$(ps -o nice= -p "${pid:-0}" | tr -d ' ')" = 10
check "AC-2 caffeinate asserts on behalf of the job" bash -c 'pmset -g assertions | grep -q "on behalf of .*(pid $1)"' _ "${pid:-0}"
check "AC-2 the plist says RunAtLoad true, KeepAlive false, AbandonProcessGroup true" bash -c '
  p=$1; [ "$(plutil -extract RunAtLoad raw -o - "$p")" = true ] && [ "$(plutil -extract KeepAlive raw -o - "$p")" = false ] &&
  [ "$(plutil -extract AbandonProcessGroup raw -o - "$p")" = true ]' _ "$L/$label.plist"
wait_for 10 test -s "$run/env.$t"
allowed="BASH_DEFAULT_TIMEOUT_MS BASH_MAX_TIMEOUT_MS CLAUDE_CONFIG_DIR HOME LANG LOGNAME PATH SHELL TMPDIR USER GW_AGENT_SH GW_RUN_FILE GW_SLOT GW_SLOT_NAME GW_TASK"
shell_added="PWD SHLVL _ OLDPWD __CF_USER_TEXT_ENCODING"
env_ok() {
  local n bad=0
  for n in $allowed; do grep -qx "$n" "$run/env.$t" || { echo "  missing: $n"; bad=1; }; done
  while read -r n; do
    case " $allowed $shell_added " in *" $n "*) ;; *) echo "  not whitelisted: $n"; bad=1 ;; esac
    case $n in STARKNET_* | SCARB_* | ATLANTIC_* | ANTHROPIC_* | CLAUDE_CODE_* | GH_* | GITHUB_* | OPENAI_* | CODEX_*) echo "  forbidden: $n"; bad=1 ;; esac
  done < "$run/env.$t"
  return $bad
}
check "AC-3 the stub's environment is exactly the whitelist (decoys set in the caller)" env_ok
check "AC-3 CLAUDE_CONFIG_DIR is the test home's .claude-b7r, TMPDIR the task's" \
  bash -c 'grep -qx "CLAUDE_CONFIG_DIR=$1/.claude-b7r" "$2" && grep -qx "TMPDIR=$3/tmp-$4/" "$2"' _ "$run" "$run/vals.$t" "$L" "$t"
checkx "AC-4 the agent's PATH begins with \$HOME/.asdf/shims and holds no nodejs/22.22.2 (nor the stubs' folder)" \
  'p=$(grep "^PATH=" "$run/vals.$t") && case $p in "PATH=$run/.asdf/shims:"*) ;; *) false ;; esac &&
   ! grep -q "nodejs/22.22.2" <<< "$p" && ! grep -qF "$run/bin" <<< "$p"'
check "AC-4 the CLI was started by its absolute path (argv[0] is $run/bin/claude)" \
  test "$(cat "$run/argv0.$t")" = "$run/bin/claude"
mapfile -t argv < "$run/argv.$t"
check "AC-4 the stub's argv: profile rules, Mac deny rules, --settings, --name" has_all \
  --permission-mode acceptEdits 'Bash(git commit *)' 'Bash(git rebase*)' 'Bash(launchctl*)' \
  'Read(~/.claude-b7r/**)' 'Bash(* $HOME/.claude-b7r*)' --settings --name "[Opus 5.5] $t"
# The absolute Read rules are `Read(//<absolute path>/**)`: `//` is absolute in Claude Code rules,
# `/` would be relative to the project. Both forms, `~` and `//$HOME`, exactly.
check "AC-4 the stub's argv: the Read denies, exactly, in the ~ and //\$HOME forms" has_all \
  'Read(~/.claude-b7r/**)' 'Read(~/.codex/**)' 'Read(~/.config/gh/**)' \
  "Read(//${run#/}/.claude-b7r/**)" "Read(//${run#/}/.claude/**)" "Read(//${run#/}/.codex/**)" "Read(//${run#/}/.config/gh/**)"
check "AC-4 the stub's argv: no absolute Read rule with a single slash" \
  bash -c '! grep -qE "^Read\(/[^/]" "$1"' _ "$run/argv.$t"
check "AC-4 the stub's argv: never --dangerously-skip-permissions" bash -c '! grep -q dangerously "$1"' _ "$run/argv.$t"
check "AC-4 the plist: never --dangerously-skip-permissions" bash -c '! grep -q dangerously "$1"' _ "$L/$label.plist"
checkx "AC-7 a new launch refuses while the task's worktree exists with a record" \
  'agent --branch "cv/$t" "$t" claude opus new "again" implement > /dev/null 2>&1; test $? = 2'
rm -f "$run/hold.$t"
agent wait "$t" > "$run/out" 2>&1
check "AC-8 wait returns the exit and the model" bash -c 'grep -q "^exit=0 " "$1" && grep -q "^model=claude-opus-5-5$" "$1"' _ "$run/out"
check "AC-8 the log has the header, model= and exit=" bash -c '
  grep -qE "^--- [0-9T:-]+Z \[Opus 5\.5\] $2 new \(implement\) claude claude-opus-5-5 label=$3 account=claude-b7r@proton\.me$" "$1" &&
  grep -q "^model=claude-opus-5-5$" "$1" && grep -qE "^exit=0 [0-9]{4}-" "$1"' _ "$L/$t.log" "$t" "$label"
check "AC-8 the job is booted out: launchctl print $DOMAIN/$label finds nothing" test "$(job_state "$label")" = absent
checkx "AC-8 status shows the task stopped, implement, ran=claude-opus-5-5" \
  'agent status > "$run/status" 2>&1; grep -qE "^$t +stopped +implement +ran=claude-opus-5-5 " "$run/status"'
tn=$id-N5
echo "--- a log without its .cli" > "$L/$tn.log"
agent status > "$run/status.out" 2> "$run/status.err"; rc=$?
checkx "AC-5 status of a task without .cli: exit 0, nothing on stderr, listed with ran=unknown" \
  'test "$rc" = 0 && test ! -s "$run/status.err" && grep -qE "^$tn +stopped +- +ran=unknown " "$run/status.out"'
rm -f "$L/$tn.log"

# --- AC-7: resume.
t7=$id-R7
agent "$t7" claude opus resume "go on" > /dev/null 2>&1
check "AC-7 resume without a record is refused" test $? = 2
agent "$t" claude sonnet resume "go on" > /dev/null 2>&1
check "AC-7 resume with another model is refused" test $? = 2
agent "$t" claude opus resume "go on" research > /dev/null 2>&1
check "AC-7 resume with another profile is refused" test $? = 2
agent "$t" claude opus resume "go on" > "$run/out" 2>&1; rc=$?
agent wait "$t" > /dev/null 2>&1
mapfile -t argv < "$run/argv.$t"
check "AC-7 resume runs claude --continue, keeps the profile implement" \
  bash -c 'test "$1" = 0 && test "$(cat "$2")" = implement' _ "$rc" "$L/$t.profile"
checkx "AC-7 resume argv: --continue and the implement rules, no --name" \
  'has_all --continue "Bash(git commit *)" && ! has --name'
check "AC-7 the resumed run has its own header and exit=" \
  bash -c 'test "$(grep -c "^--- .* $2 resume (implement) " "$1")" = 1 && test "$(grep -c "^exit=0 " "$1")" = 2' _ "$L/$t.log" "$t"

# --- AC-2: the budget of 5, counted by locks.
t5a=$id-B5a t5b=$id-B5b t5c=$id-B5c t5d=$id-B5d t5e=$id-B5e t5f=$id-B5f
touch "$run/hold.$t5a" "$run/hold.$t5b" "$run/hold.$t5c" "$run/hold.$t5d" "$run/hold.$t5e"
record "$t5a"; agent --branch "cv/$t5a" "$t5a" claude opus new "a" implement > /dev/null 2>&1; ra=$?
record "$t5b"; agent --branch "cv/$t5b" "$t5b" codex gpt-6-sol new "b" > /dev/null 2>&1; rb=$?
record "$t5c"; agent --branch "cv/$t5c" "$t5c" claude opus new "c" implement > /dev/null 2>&1; rc3=$?
record "$t5d"; agent --branch "cv/$t5d" "$t5d" claude opus new "d" implement > /dev/null 2>&1; rd=$?
record "$t5e"; agent --branch "cv/$t5e" "$t5e" claude opus new "e" implement > /dev/null 2>&1; re=$?
check "AC-2 five stubs run at once (four claude, a codex)" test "$ra" = 0 -a "$rb" = 0 -a "$rc3" = 0 -a "$rd" = 0 -a "$re" = 0
checkx "AC-2 the five slots are held" 'test "$(agent slots | grep -c " held ")" = 5'
agent --branch "cv/$t5f" "$t5f" claude opus new "f" implement > "$run/out" 2>&1; rc=$?
check "AC-2 a sixth launch refuses (exit 4) before any worktree or job" \
  bash -c 'test "$1" = 4 && test ! -e "$2" && test ! -e "$3" && ! launchctl list | grep -qF "$4"' _ "$rc" "$W/cli-$t5f" "$L/$t5f.label" "grimworld.cv.test.$t5f"
rm -f "$run/hold.$t5a"
wait_for 10 grep -q '^ended' "$L/$t5a.run"
agent thresholds > /dev/null 2>&1
check "AC-2 when a stub ends its slot is free again, without any cleanup step" test $? = 0
checkx "AC-2 codex ran -s read-only and its model was read" \
  'grep -qx read-only "$run/argv.$t5b" && test "$(agent model "$t5b")" = gpt-6-sol'

# --- AC-2, the race: exactly one slot free out of five (t5b to t5e hold the others), two launchers started together.
# The two launchers run concurrently inside this one foreground command, and both are waited for;
# their pids are in `inflight` meanwhile, so that an interruption stops them before the cleanup scans.
r1=$id-Ra r2=$id-Rb
touch "$run/hold.$r1" "$run/hold.$r2"
record "$r1"; record "$r2"
agent_bg "$run/out.$r1" --branch "cv/$r1" "$r1" claude opus new "race 1" implement
agent_bg "$run/out.$r2" --branch "cv/$r2" "$r2" claude opus new "race 2" implement
p1=${inflight[0]} p2=${inflight[1]}
reap_bg "$p1"; x1=$?
# shellcheck disable=SC2034 # read by checkx
after1=$(in_inflight "$p1" && echo kept || echo removed)
reap_bg "$p2"; x2=$?
checkx "A2(3) race: each launcher leaves inflight as soon as it is reaped (first: $after1, then ${#inflight[@]} left)" \
  'test "$after1" = removed && test "${#inflight[@]}" = 0'
if [ "$x1" = 0 ]; then win=$r1 lose=$r2; else win=$r2 lose=$r1; fi
check "AC-2 race: exactly one launcher took the free slot (exit 0), the other refused (exit 4) [$x1, $x2]" \
  test "$(printf '%s\n' "$x1" "$x2" | sort | tr '\n' ' ')" = "0 4 "
check "AC-2 race: the refused launcher created no worktree, no record, no job" \
  bash -c 'test ! -e "$1" && test ! -e "$2" && test ! -e "$3" && ! launchctl list | grep -qF "$4"' \
  _ "$W/cli-$lose" "$L/$lose.label" "$L/$lose.log" "grimworld.cv.test.$lose."
checkx "AC-2 race: the winner runs, the five slots are held" \
  'test "$(job_state "$(cat "$L/$win.label")")" = running && test "$(agent slots | grep -c " held ")" = 5'

# --- Audit A1: a label file that is not the task's is refused, never acted on. The winner's label
# is copied into the file of t5a (ended); every command on t5a must leave the winner running.
# shellcheck disable=SC2034 # read by checkx
lw=$(cat "$L/$win.label")
cp "$L/$t5a.label" "$run/label.$t5a.saved"
cp "$L/$win.label" "$L/$t5a.label"
agent stop "$t5a" > "$run/out" 2>&1; rc=$?
checkx "A1 stop of a task whose label file holds another task's label: refused (exit 2), the other job still runs" \
  'test "$rc" = 2 && grep -q "not a label of $t5a" "$run/out" && test "$(job_state "$lw")" = running'
agent wait "$t5a" > "$run/out" 2>&1; rc=$?
checkx "A1 wait on it: refused at once (exit 2), the other job still runs" \
  'test "$rc" = 2 && grep -q "not a label of $t5a" "$run/out" && test "$(job_state "$lw")" = running'
agent status > "$run/out" 2>&1; rc=$?
checkx "A1 status: lists it as refused and leaves the other job running" \
  'test "$rc" = 0 && grep -qE "^$t5a +refused " "$run/out" && grep -qE "^$win +running " "$run/out" && test "$(job_state "$lw")" = running'
agent --branch "cv/$t5a" "$t5a" claude opus new "again" implement > "$run/out" 2>&1; rc=$?
checkx "A1 a new launch of it (whose reap reads the label): refused (exit 2), the other job still runs" \
  'test "$rc" = 2 && grep -q "not a label of $t5a" "$run/out" && test "$(job_state "$lw")" = running'
agent "$t5a" claude opus resume "again" > "$run/out" 2>&1; rc=$?
checkx "A1 a resume of it: refused (exit 2), the other job still runs" \
  'test "$rc" = 2 && grep -q "not a label of $t5a" "$run/out" && test "$(job_state "$lw")" = running'
echo "grimworld.cv.$t5a.101010" > "$L/$t5a.label"   # the real prefix, in test mode
agent stop "$t5a" > "$run/out" 2>&1; rc=$?
check "A1 a label of the other mode's prefix is refused too (exit 2)" test "$rc" = 2
cp "$run/label.$t5a.saved" "$L/$t5a.label"

rm -f "$run/hold.$t5b" "$run/hold.$t5c" "$run/hold.$t5d" "$run/hold.$t5e" "$run/hold.$win"
for w in "$t5a" "$t5b" "$t5c" "$t5d" "$t5e" "$win"; do agent wait "$w" > /dev/null 2>&1; done

# --- AC-6: a job that never writes slots-acquired is stopped by its label, and reported.
t6=$id-H6
touch "$run/test-hang"; echo 3 > "$run/test-deadline"
record "$t6"
agent --branch "cv/$t6" "$t6" claude opus new "hang" implement > "$run/out" 2>&1; rc=$?
rm -f "$run/test-hang" "$run/test-deadline"
l6=$(cat "$L/$t6.label" 2> /dev/null)
check "AC-6 a job that never reports: exit 2, stopped by its label, verified" \
  bash -c 'test "$1" = 2 && grep -q "its job $2 is stopped and booted out, and slot cv-[1-5] is free (verified)" "$3"' _ "$rc" "$l6" "$run/out"
checkx "AC-6 its label is gone from launchd and all five slots are free" \
  'test "$(job_state "$l6")" = absent && test "$(agent slots | grep -c " free")" = 5'

# --- stop: the task's own job, by its label.
t9=$id-S9
touch "$run/hold.$t9"
record "$t9"; agent --branch "cv/$t9" "$t9" claude opus new "stop me" implement > /dev/null 2>&1
l9=$(cat "$L/$t9.label")
# shellcheck disable=SC2034 # read by checkx
p9=$(job_pid "$l9")
agent stop "$t9" > "$run/out" 2>&1; rc=$?
checkx "stop: the job is stopped, booted out, verified; its process is gone; its slot free" \
  'test "$rc" = 0 && grep -q "(verified)" "$run/out" && test "$(job_state "$l9")" = absent && ! kill -0 "${p9:-0}" 2> /dev/null && test "$(agent slots | grep -c " free")" = 5'
rm -f "$run/hold.$t9"

# --- Audit 2, A1: an interruption while two launchers are in flight. Both slots are free; two
# launchers start in the background and, after a delay that lands them in different phases (account
# check, launch lock, worktree, bootstrap, wait for the slot), `drain` runs as the cleanup's first
# step does. Nothing of this run may stay loaded, and no stub may keep running. The same drain is what
# the INT and TERM traps run.
for delay in 0.1 0.3 0.6 1.0 1.5 2.0 2.5 3.5; do
  d=${delay/./}
  i1=$id-I${d}a i2=$id-I${d}b
  touch "$run/hold.$i1" "$run/hold.$i2"
  record "$i1"; record "$i2"
  agent_bg "$run/out.$i1" --branch "cv/$i1" "$i1" claude opus new "in flight 1" implement
  agent_bg "$run/out.$i2" --branch "cv/$i2" "$i2" claude opus new "in flight 2" implement
  # shellcheck disable=SC2034 # read by checkx
  ip1=${inflight[0]} ip2=${inflight[1]}
  sleep "$delay"
  # shellcheck disable=SC2034 # read by checkx
  inflight_before=${#inflight[@]}
  drain; rc=$?
  phase="launchers exit${INFLIGHT_RC}; labels written: $(cat "$L/$i1.label" "$L/$i2.label" 2> /dev/null | wc -l | tr -d ' ')"
  checkx "A1(2) drain $delay s after starting two launchers ($phase): they are stopped first, nothing of the run is loaded" \
    'test "$inflight_before" = 2 && test "$rc" = 0 && test "${#inflight[@]}" = 0'
  checkx "A2(3) after that drain, inflight holds no reaped pid" '! in_inflight "$ip1" && ! in_inflight "$ip2"'
  checkx "A1(2) after that drain: no stub of $i1 or $i2 runs, all five slots are free" \
    'wait_for 5 nothing_runs_for "$i1" && wait_for 5 nothing_runs_for "$i2" && test "$(agent slots | grep -c " free")" = 5'
done

# --- Audit 3, A1: a child of a stopped launcher that outlives the bound. A stand-in launcher (a
# shell whose child sleeps 6 s) is tracked like a launcher; with the bound shortened to 1 s (a
# variable of this test script only), the drain must fail, name the child, and scan no label; the
# cleanup, run in a subshell, must keep the test home and say so. Once the child has exited, a drain
# passes again.
KID_BOUND=1
track_bg /opt/homebrew/bin/bash -c 'sleep 6 & wait'
fake=${inflight[${#inflight[@]} - 1]}
has_child() { pgrep -P "$1" > /dev/null; }
wait_for 5 has_child "$fake"
# shellcheck disable=SC2034 # read by checkx
nlabels=${#labels[@]}
drain; rc=$?
kid=${kids_pending[0]:-}
checkx "A1(3) a child alive past the bound: the drain fails and names it, scans no label, the stand-in is reaped [$DRAIN_LEFT]" \
  'test "$rc" = 1 && test -n "$kid" && grep -qw "$kid" <<< "$DRAIN_LEFT" && test "${#labels[@]}" = "$nlabels" && ! in_inflight "$fake" && ! pid_gone "$kid"'
(cleanup) 2> "$run/cleanup.err"; rc=$?
checkx "A1(3) the cleanup then keeps the test home and says so" \
  'test "$rc" = 1 && test -d "$run" && grep -qF "the test home $run is kept" "$run/cleanup.err" && grep -qw "$kid" "$run/cleanup.err"'
wait_for 10 pid_gone "$kid"
KID_BOUND=30
drain; rc=$?
checkx "A1(3) once the child has exited, a drain passes again and nothing is pending" \
  'test "$rc" = 0 && test "${#kids_pending[@]}" = 0'

# --- AC-10: syntax and shellcheck.
check "AC-10 bash -n" /opt/homebrew/bin/bash -n "$here/agent.sh" "$here/test.sh"
check "AC-10 shellcheck scripts/mac/*.sh" /opt/homebrew/bin/shellcheck "$here"/*.sh
check "AC-10 /bin/bash 3.2 is refused by the launcher" bash -c '/bin/bash "$1" status > /dev/null 2>&1; test $? = 2' _ "$A"

# --- AC-11: nothing left behind. One job is launched and deliberately not recorded (as if the test
# had been interrupted between the launcher's bootstrap and `record`): the cleanup must recover its
# label from this run's files and boot it out.
tu=$id-U1
touch "$run/hold.$tu"
agent --branch "cv/$tu" "$tu" claude opus new "unrecorded" implement > /dev/null 2>&1
lu=$(cat "$L/$tu.label" 2> /dev/null)
check "AC-11 an unrecorded job runs before the cleanup" test "$(job_state "$lu")" = running
trap - EXIT INT TERM
cleanup; rc=$?
left=$(launchctl list | awk '{ print $3 }' | grep -F "$PREFIX" || true)
gone=1; for l in "${labels[@]}"; do [ "$(job_state "$l")" = absent ] || gone=0; done
check "AC-11 the cleanup verified every label gone ($(printf '%s\n' "${labels[@]}" | sort -u | wc -l | tr -d ' ') labels recovered from the run's files)" test "$rc" = 0 -a "$gone" = 1
check "AC-11 the unrecorded job was recovered and booted out" \
  bash -c 'printf "%s\n" "${@:2}" | grep -qxF "$1" && ! launchctl print "gui/$(id -u)/$1" > /dev/null 2>&1' _ "$lu" "${labels[@]}"
check "AC-11 launchctl list holds no label of $PREFIX*" test -z "$left"
check "AC-11 the test home is removed" test ! -e "$run"
check "AC-11 no process of the stubs is left" bash -c '! pgrep -f "$1" > /dev/null' _ "$run/bin/"

if [ "$fails" = 0 ]; then echo "all passed"; else echo "$fails failed"; fi
[ "$fails" = 0 ]
