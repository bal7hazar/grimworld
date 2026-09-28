#!/usr/bin/env python3
"""SPK-1 fix loop 1, finding 1: no value in stdout or stderr, even at startup with a malformed
value. Only SYNTHETIC values, set here for the child processes; nothing is sent to any network
(every case below stops at validation, or runs a local command).

    python3 spikes/SPK-1/test_redaction.py
"""
import os
import re
import subprocess
import sys
import tempfile

URL = "https://synthetic-rpc.invalid/v1/SYNTHETICPATHc0ffee"
ADDRESS = "0x05a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5"
KEY = "0x7e57000000000000000000000000000000000000000000000000000000c0ffee"


def forms(value):
    """Every form a leak could take: the literal, its lower-case, and for felts hex and decimal."""
    out = {value, value.lower()}
    if re.fullmatch(r"0x[0-9a-fA-F]+", value):
        n = int(value, 16)
        out |= {f"{n:x}", str(n)}
    else:
        out |= {part for part in re.split(r"[^A-Za-z0-9]", value) if "SYNTHETIC" in part.upper()}
    if value.startswith("https://"):
        out.add(value.split("/")[2])
    return out


def run(env, command):
    full = dict(os.environ, STARKNET_NETWORK="sepolia", **env)
    return subprocess.run(command, capture_output=True, text=True, env=full)


def leaks(text, values):
    return sum(text.lower().count(f.lower()) for v in values for f in forms(v))


failures = 0


def case(name, env, command, expect_code, extra_check=None):
    global failures
    r = run(env, command)
    values = [v for name, v in env.items() if v and name.startswith("STARKNET_")]
    n = leaks(r.stdout + r.stderr, values)
    ok = r.returncode == expect_code and n == 0 and (extra_check is None or extra_check(r))
    failures += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}: exit {r.returncode} (expected {expect_code}), "
          f"synthetic value occurrences in stdout+stderr: {n}")
    for stream, text in (("stdout", r.stdout), ("stderr", r.stderr)):
        for line in text.strip().splitlines()[:4]:
            print(f"    {stream}: {line[:160]}")


BAD_KEY = "0xSYNTHETIC_BAD_KEY_zz"
BAD_URL = "not a url SYNTHETICBADURL"
BAD_ADDRESS = "SYNTHETIC_BAD_ADDRESS"
PROBE = ["node", "spikes/SPK-1/probe.mjs"]
CHECK = ["python3", "spikes/SPK-1/check_secrets.py", "--log", "/dev/null"]

for tool, command in (("probe.mjs (lib.mjs configure)", PROBE), ("check_secrets.py", CHECK)):
    case(f"{tool}, malformed key", {"STARKNET_RPC_URL": URL, "STARKNET_ACCOUNT_ADDRESS": ADDRESS,
                                    "STARKNET_PRIVATE_KEY": BAD_KEY}, command, 2)
    case(f"{tool}, malformed address", {"STARKNET_RPC_URL": URL, "STARKNET_ACCOUNT_ADDRESS": BAD_ADDRESS,
                                        "STARKNET_PRIVATE_KEY": KEY}, command, 2)
    case(f"{tool}, malformed URL", {"STARKNET_RPC_URL": BAD_URL, "STARKNET_ACCOUNT_ADDRESS": ADDRESS,
                                    "STARKNET_PRIVATE_KEY": KEY}, command, 2)

# The price wrapper: a local command that prints every synthetic value in every form, to stdout
# and stderr. Nothing unredacted may reach the output file, stdout or stderr.
def printer(key):
    """A local command printing every value of the case, in every form, to stdout and stderr."""
    n = int(ADDRESS, 16)
    lines = [URL, f"host {URL.split('/')[2]}", ADDRESS, f"0x{n:x}", str(n), key]
    if key == KEY:
        lines.append(str(int(KEY, 16)))
    return ("import sys\n"
            f"lines = {lines!r}\n"
            "print('\\n'.join(lines)); print('\\n'.join(lines), file=sys.stderr)\n")


with tempfile.TemporaryDirectory() as tmp:
    out = os.path.join(tmp, "prices-output.txt")
    for label, key in (("well-formed values", KEY), ("malformed key", BAD_KEY)):
        env = {"STARKNET_RPC_URL": URL, "STARKNET_ACCOUNT_ADDRESS": ADDRESS, "STARKNET_PRIVATE_KEY": key}
        PRINTER = printer(key)
        command = ["python3", "spikes/SPK-1/redacted.py", out, "--", "python3", "-c", PRINTER]

        def file_clean(r, env=env):
            text = open(out).read()
            print(f"    file: {len(text.splitlines())} lines, synthetic value occurrences: "
                  f"{leaks(text, list(env.values()))}; placeholders: "
                  f"{sorted(set(re.findall(r'<[A-Z_]+>', text)))}")
            return leaks(text, list(env.values())) == 0

        case(f"redacted.py, {label}", env, command, 0, file_clean)

    # check_secrets.py (finding 5): a value in the log is found; a missing required input fails;
    # a git failure fails. Well-formed synthetic values, a synthetic log.
    env = {"STARKNET_RPC_URL": URL, "STARKNET_ACCOUNT_ADDRESS": ADDRESS, "STARKNET_PRIVATE_KEY": KEY}
    log = os.path.join(tmp, "agent.log")
    with open(log, "w") as f:
        f.write(f"a leaked key {int(KEY, 16)} and an address 0x{int(ADDRESS, 16):x}\n")
    case("check_secrets.py, values in the log", env,
         ["python3", "spikes/SPK-1/check_secrets.py", "--log", log, "--report", "spikes/SPK-1/README.md"], 1,
         lambda r: "FOUND STARKNET_PRIVATE_KEY in " + log in r.stdout
         and "FOUND STARKNET_ACCOUNT_ADDRESS in " + log in r.stdout)
    case("check_secrets.py, missing required inputs", env,
         ["python3", "spikes/SPK-1/check_secrets.py", "--log", os.path.join(tmp, "absent.log"),
          "--report", os.path.join(tmp, "absent-REPORT.md")], 1,
         lambda r: r.stdout.count("MISSING required input") == 2)
    case("check_secrets.py, git fails (GIT_DIR points nowhere)", dict(env, GIT_DIR=os.path.join(tmp, "no-repo")),
         ["python3", "spikes/SPK-1/check_secrets.py", "--log", log], 1,
         lambda r: "git log -p --all failed" in r.stdout)

print(f"{'all passed' if failures == 0 else f'{failures} failed'}")
sys.exit(1 if failures else 0)
