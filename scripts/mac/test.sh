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
wait_for() { # <seconds> <condition…>
  local n=$(($1 * 10)); shift
  while [ "$n" -gt 0 ]; do "$@" && return 0; sleep 0.1; n=$((n - 1)); done
  return 1
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
  wait_for 5 test "$(job_state "$l")" = absent
}
cleaned=0 CLEAN_LEFT=""
cleanup() {
  [ "$cleaned" = 0 ] || return 0
  cleaned=1
  local t l
  rm -f "$run"/hold.* "$run/test-hang"
  for t in "${tasks[@]}"; do agent stop "$t" > /dev/null 2>&1; done
  for l in $(run_labels); do
    labels+=("$l")
    [ "$(job_state "$l")" = absent ] || stop_label "$l"
  done
  # The home is removed only when every label is verified gone; otherwise it is kept, and said.
  CLEAN_LEFT=""
  for l in $(run_labels); do [ "$(job_state "$l")" = absent ] || CLEAN_LEFT="$CLEAN_LEFT $l"; done
  if [ -n "$CLEAN_LEFT" ]; then
    echo "FAIL cleanup: still loaded:$CLEAN_LEFT; the test home $run is kept" >&2
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
agent slots-init > /dev/null 2>&1
check "slots-init: cv-1, cv-2, directory read-only" \
  test -f "$run/orchestrator/slots/cv-1" -a -f "$run/orchestrator/slots/cv-2" -a "$(stat -f %Lp "$run/orchestrator/slots" 2> /dev/null)" = 555

# --- AC-9: refusals.
agent --with-sepolia "$id-X" claude opus new "hello" implement > /dev/null 2>&1
check "AC-9 --with-sepolia refused (exit 2)" test $? = 2
agent "$id-X" claude opus-4 new "hello" implement > /dev/null 2>&1
check "AC-9 unknown model refused (exit 2)" test $? = 2
agent "$id-X" codex gpt-5 new "hello" audit > /dev/null 2>&1
check "AC-9 unknown codex model refused (exit 2)" test $? = 2
echo 11.5 > "$run/test-load5"
agent thresholds > /dev/null 2>&1; rc=$?
agent --branch "cv/$id-X" "$id-X" claude opus new "hello" implement > /dev/null 2>&1; rc2=$?
check "AC-9 load above 10 refuses (thresholds and launch: exit 4, no worktree)" test "$rc" = 4 -a "$rc2" = 4 -a ! -e "$W/cli-$id-X"
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

# --- AC-5: the budget of 2, counted by locks.
t5a=$id-B5a t5b=$id-B5b t5c=$id-B5c
touch "$run/hold.$t5a" "$run/hold.$t5b"
record "$t5a"; agent --branch "cv/$t5a" "$t5a" claude opus new "a" implement > /dev/null 2>&1; ra=$?
record "$t5b"; agent --branch "cv/$t5b" "$t5b" codex gpt-6-sol new "b" > /dev/null 2>&1; rb=$?
check "AC-5 two stubs run (a claude, a codex)" test "$ra" = 0 -a "$rb" = 0
checkx "AC-5 both slots are held" 'test "$(agent slots | grep -c " held ")" = 2'
agent --branch "cv/$t5c" "$t5c" claude opus new "c" implement > "$run/out" 2>&1; rc=$?
check "AC-5 a third launch refuses (exit 4) before any worktree or job" \
  bash -c 'test "$1" = 4 && test ! -e "$2" && test ! -e "$3" && ! launchctl list | grep -qF "$4"' _ "$rc" "$W/cli-$t5c" "$L/$t5c.label" "grimworld.cv.test.$t5c"
rm -f "$run/hold.$t5a"
wait_for 10 grep -q '^ended' "$L/$t5a.run"
agent thresholds > /dev/null 2>&1
check "AC-5 when a stub ends its slot is free again, without any cleanup step" test $? = 0
checkx "AC-5 codex ran -s read-only and its model was read" \
  'grep -qx read-only "$run/argv.$t5b" && test "$(agent model "$t5b")" = gpt-6-sol'

# --- AC-5, the race: exactly one slot free (t5b holds the other), two launchers started together.
# The two launchers run concurrently inside this one foreground command, and both are waited for.
r1=$id-Ra r2=$id-Rb
touch "$run/hold.$r1" "$run/hold.$r2"
record "$r1"; record "$r2"
agent --branch "cv/$r1" "$r1" claude opus new "race 1" implement > "$run/out.$r1" 2>&1 & p1=$!
agent --branch "cv/$r2" "$r2" claude opus new "race 2" implement > "$run/out.$r2" 2>&1 & p2=$!
wait "$p1"; x1=$?
wait "$p2"; x2=$?
if [ "$x1" = 0 ]; then win=$r1 lose=$r2; else win=$r2 lose=$r1; fi
check "AC-5 race: exactly one launcher took the free slot (exit 0), the other refused (exit 4) [$x1, $x2]" \
  test "$(printf '%s\n' "$x1" "$x2" | sort | tr '\n' ' ')" = "0 4 "
check "AC-5 race: the refused launcher created no worktree, no record, no job" \
  bash -c 'test ! -e "$1" && test ! -e "$2" && test ! -e "$3" && ! launchctl list | grep -qF "$4"' \
  _ "$W/cli-$lose" "$L/$lose.label" "$L/$lose.log" "grimworld.cv.test.$lose."
checkx "AC-5 race: the winner runs, both slots are held" \
  'test "$(job_state "$(cat "$L/$win.label")")" = running && test "$(agent slots | grep -c " held ")" = 2'

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

rm -f "$run/hold.$t5b" "$run/hold.$win"
agent wait "$t5a" > /dev/null 2>&1; agent wait "$t5b" > /dev/null 2>&1; agent wait "$win" > /dev/null 2>&1

# --- AC-6: a job that never writes slots-acquired is stopped by its label, and reported.
t6=$id-H6
touch "$run/test-hang"; echo 3 > "$run/test-deadline"
record "$t6"
agent --branch "cv/$t6" "$t6" claude opus new "hang" implement > "$run/out" 2>&1; rc=$?
rm -f "$run/test-hang" "$run/test-deadline"
l6=$(cat "$L/$t6.label" 2> /dev/null)
check "AC-6 a job that never reports: exit 2, stopped by its label, verified" \
  bash -c 'test "$1" = 2 && grep -q "its job $2 is stopped and booted out, and slot cv-[12] is free (verified)" "$3"' _ "$rc" "$l6" "$run/out"
checkx "AC-6 its label is gone from launchd and both slots are free" \
  'test "$(job_state "$l6")" = absent && test "$(agent slots | grep -c " free")" = 2'

# --- stop: the task's own job, by its label.
t9=$id-S9
touch "$run/hold.$t9"
record "$t9"; agent --branch "cv/$t9" "$t9" claude opus new "stop me" implement > /dev/null 2>&1
l9=$(cat "$L/$t9.label")
# shellcheck disable=SC2034 # read by checkx
p9=$(job_pid "$l9")
agent stop "$t9" > "$run/out" 2>&1; rc=$?
checkx "stop: the job is stopped, booted out, verified; its process is gone; its slot free" \
  'test "$rc" = 0 && grep -q "(verified)" "$run/out" && test "$(job_state "$l9")" = absent && ! kill -0 "${p9:-0}" 2> /dev/null && test "$(agent slots | grep -c " free")" = 2'
rm -f "$run/hold.$t9"

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
check "AC-11 the cleanup verified every label gone (${#labels[@]} labels recovered from the run's files)" test "$rc" = 0 -a "$gone" = 1
check "AC-11 the unrecorded job was recovered and booted out" \
  bash -c 'printf "%s\n" "${@:2}" | grep -qxF "$1" && ! launchctl print "gui/$(id -u)/$1" > /dev/null 2>&1' _ "$lu" "${labels[@]}"
check "AC-11 launchctl list holds no label of $PREFIX*" test -z "$left"
check "AC-11 the test home is removed" test ! -e "$run"
check "AC-11 no process of the stubs is left" bash -c '! pgrep -f "$1" > /dev/null' _ "$run/bin/"

if [ "$fails" = 0 ]; then echo "all passed"; else echo "$fails failed"; fi
[ "$fails" = 0 ]
