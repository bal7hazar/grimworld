#!/usr/bin/env bash
# Runs a command against a local Starknet node that lives only as long as the command: start the
# node, wait until it answers, run the command in the foreground, stop the node, exit with the
# command's status. This is how an agent runs anything that needs a node without a background
# command (docs/briefs/COMMON.md §2).
#
#   scripts/with-node.sh [--full-archive] <command> [args...]
#
# --full-archive starts the node with `--state-archive-capacity full` (`starknet-devnet --help`, 0.10.0): it
# keeps the state of every block, so a read at an older block answers (the indexer needs it, IDX-01).
# Without it the node is started as before.
#
# The node is starknet-devnet (the Rust devnet of 0xSpaceShard, pinned in .tool-versions): the one
# of the candidates that accepts the classes of Cairo 2.19 (docs/research/SPK-5b-toolchain-native.md, NS-1).
# Ports are picked free at each run, so parallel agents never collide; a node that fails to bind
# (another process took the port in between) is restarted on new ports, up to five times, and a
# node counts as started only when its own log says it serves the port and the port answers.
# The command gets:
#   NODE_URL         http://127.0.0.1:<port>          (JSON-RPC; also RPC_URL and STARKNET_RPC_URL)
#   NODE_ACCOUNT_ADDRESS, NODE_ACCOUNT_PRIVATE_KEY     the first pre-funded account (seed 0)
# The command runs in its own process group (`setsid`; where there is none, macOS, a `perl` one-liner that
# calls setsid(2) and execs the command: the same system call, the same pid, so the same group).
# On every way out (the command ends, fails, or this script is interrupted) the whole group is
# stopped, so nothing the command started survives it, even when the command itself exited first;
# then the node.
# Logs: $WITH_NODE_LOG_DIR (default ./.with-node/) node.log, overwritten each run.
#
# A process group id cannot be handed to another group while a member is alive, so signalling the
# group is safe as long as the command's leader has been reaped by this script (it has: `wait`).
# The functions below are called by the trap and through wait_for: shellcheck 0.9 reports them as
# unreachable (SC2317), 0.10 and later as never invoked (SC2329).
# shellcheck disable=SC2317,SC2329
set -uo pipefail

usage() {
  echo "usage: scripts/with-node.sh [--full-archive] <command> [args...]" >&2
  exit 2
}

node_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --full-archive) node_args+=(--state-archive-capacity full) ;;
    --) shift; break ;;
    -*) echo "with-node: unknown option $1" >&2; usage ;;
    *) break ;;
  esac
  shift
done
[ $# -ge 1 ] || usage
command -v starknet-devnet > /dev/null || { echo "with-node: starknet-devnet not found (scripts/setup-toolchain.sh)" >&2; exit 127; }

# The command's own session. `setsid` where the system has it; else perl (on macOS by default) calls the
# same setsid(2) and execs, so the pid stays the command's and is the group id, exactly as with setsid:
# the group holds the command and what it starts, and nothing else. A failed setsid(2) or exec stops
# the command (127), never runs it in this script's own group, which the cleanup would then signal.
if command -v setsid > /dev/null; then
  new_session=(setsid)
elif command -v perl > /dev/null; then
  new_session=(perl -e 'use POSIX (); POSIX::setsid() != -1 or die "with-node: setsid: $!\n"; exec { $ARGV[0] } @ARGV; print STDERR "with-node: $ARGV[0]: $!\n"; exit 127' --)
else
  echo "with-node: neither setsid nor perl found: cannot run the command in its own process group" >&2
  exit 127
fi

log_dir=${WITH_NODE_LOG_DIR:-$PWD/.with-node}
mkdir -p "$log_dir"

node_pid='' cmd_pgid=''

# --- ports ---------------------------------------------------------------------------------------
# pick_port sets PORT (never runs in a command substitution: `taken` must live in this shell): a
# port nobody listens on, not handed out earlier in this run.
taken=" "
PORT=''
pick_port() {
  local p
  while :; do
    p=$((RANDOM % 20000 + 20000))
    case "$taken" in *" $p "*) continue ;; esac
    if ! (exec 3<> "/dev/tcp/127.0.0.1/$p") 2> /dev/null; then
      taken="$taken$p "
      PORT=$p
      return
    fi
  done
}

# --- stopping ------------------------------------------------------------------------------------
stop() { # <pid>: TERM, then KILL after five seconds
  local pid=$1
  [ -n "$pid" ] && kill -0 "$pid" 2> /dev/null || return 0
  kill "$pid" 2> /dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$pid" 2> /dev/null || break
    sleep 0.5
  done
  kill -9 "$pid" 2> /dev/null
  wait "$pid" 2> /dev/null
  return 0
}

group_alive() { kill -0 -- "-$1" 2> /dev/null; }

stop_group() { # <pgid>: TERM the whole group, then KILL after five seconds, whoever is left in it
  local pgid=$1
  group_alive "$pgid" || return 0
  kill -TERM -- "-$pgid" 2> /dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    group_alive "$pgid" || return 0
    sleep 0.5
  done
  kill -KILL -- "-$pgid" 2> /dev/null
  return 0
}

cleanup() {
  trap '' EXIT INT TERM HUP
  [ -z "$cmd_pgid" ] || stop_group "$cmd_pgid"
  stop "$node_pid"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# --- starting the node ---------------------------------------------------------------------------
# wait_for <label> <pid> <log> <ready function>: 0 when ready; 1 when the process died (a bind
# failure is retried by the caller); 2 when it neither died nor became ready within 60 s.
wait_for() {
  local label=$1 pid=$2 log=$3 ready=$4
  for _ in $(seq 1 120); do
    if ! kill -0 "$pid" 2> /dev/null; then
      echo "with-node: $label exited during startup; see $log" >&2
      tail -n 5 "$log" >&2
      return 1
    fi
    if "$ready" > /dev/null 2>&1; then return 0; fi
    sleep 0.5
  done
  echo "with-node: $label did not answer within 60 s; see $log" >&2
  return 2
}

# Ready = the node's own log says it serves the port AND the port answers: a stranger that took
# the port after the probe cannot pass for the node.
node_ready() {
  grep -q -E "Devnet listening on.*127\.0\.0\.1:$node_port" "$log_dir/node.log" &&
    curl -sf -X POST -H 'content-type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"starknet_chainId","params":[]}' "http://127.0.0.1:$node_port"
}

start_node() {
  local attempt status
  for attempt in 1 2 3 4 5; do
    pick_port
    node_port=$PORT
    starknet-devnet --seed 0 ${node_args[@]+"${node_args[@]}"} --port "$node_port" > "$log_dir/node.log" 2>&1 &
    node_pid=$!
    wait_for node "$node_pid" "$log_dir/node.log" node_ready
    status=$?
    [ "$status" = 0 ] && return 0
    stop "$node_pid"
    node_pid=''
    [ "$status" = 1 ] || return 1
    echo "with-node: node attempt $attempt failed, trying other ports" >&2
  done
  return 1
}

node_port=''
start_node || { echo "with-node: the node did not start" >&2; exit 1; }
node_url=http://127.0.0.1:$node_port
export NODE_URL=$node_url RPC_URL=$node_url STARKNET_RPC_URL=$node_url
# First pre-funded account, from the banner of the node's log.
NODE_ACCOUNT_ADDRESS=$(awk '/Account address/ { print $(NF); exit }' "$log_dir/node.log")
NODE_ACCOUNT_PRIVATE_KEY=$(awk '/Private key/ { print $(NF); exit }' "$log_dir/node.log")
export NODE_ACCOUNT_ADDRESS NODE_ACCOUNT_PRIVATE_KEY

# In its own session, hence its own process group (setsid and the perl fallback exec: this shell's
# background job is never a group leader), so that the group id is the pid and stays known after
# the leader exits.
"${new_session[@]}" "$@" <&0 &
cmd_pgid=$!
wait "$cmd_pgid"
exit $?
