#!/usr/bin/env python3
"""SPK-1b fix loop 1: check_secrets.py against burner inventories that must fail, with synthetic
values only, in a throwaway git repository (nothing of this repository's secrets is read).

    python3 spikes/SPK-1b/test_check_secrets.py
"""
import json
import os
import subprocess
import sys
import tempfile

# An argument runs the cases against another version of the check (the one before fix loop 1)
CHECK = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "check_secrets.py")
KEY = "0x" + "5eed1234abcd".rjust(64, "0")
ENV = {
    **os.environ,
    "STARKNET_RPC_URL": "https://rpc.invalid.example/v0_10/synthetic",
    "STARKNET_ACCOUNT_ADDRESS": "0x" + "abc123".rjust(64, "0"),
    "STARKNET_PRIVATE_KEY": "0x" + "def456".rjust(64, "0"),
}
GIT = ["git", "-c", "user.name=test", "-c", "user.email=test@invalid.example", "-c", "commit.gpgsign=false"]


def repo():
    root = tempfile.mkdtemp(prefix="spk1b-check-")
    subprocess.run(GIT + ["init", "-q", root], check=True)
    os.makedirs(os.path.join(root, "spikes/SPK-1b"))
    os.makedirs(os.path.join(root, "docs/research"))
    files = {".gitignore": "spikes/SPK-1b/burners.secret.json\n", "spikes/SPK-1b/README.md": "clean\n",
             "docs/research/SPK-1b-fixed-part.md": "clean\n", "REPORT.md": "clean\n", "agent.log": "clean\n"}
    for path, text in files.items():
        with open(os.path.join(root, path), "w") as f:
            f.write(text)
    subprocess.run(GIT + ["-C", root, "add", "-A"], check=True)
    subprocess.run(GIT + ["-C", root, "commit", "-qm", "init"], check=True)
    return root


def run(inventory, setup=None):
    root = repo()
    with open(os.path.join(root, "spikes/SPK-1b/burners.secret.json"), "w") as f:
        f.write(inventory if isinstance(inventory, str) else json.dumps(inventory))
    if setup:
        setup(root)
    done = subprocess.run([sys.executable, CHECK, "--log", "agent.log", "--report", "REPORT.md"], cwd=root, env=ENV,
                          capture_output=True, text=True)
    return done.returncode, done.stdout + done.stderr


def leak(root):
    with open(os.path.join(root, "spikes/SPK-1b/notes.txt"), "w") as f:
        f.write(f"oops {KEY}\n")


def track(root):
    subprocess.run(GIT + ["-C", root, "add", "-f", "spikes/SPK-1b/burners.secret.json"], check=True)


CASES = [
    ("a valid inventory, nothing leaked", {"oz": {"private_key": KEY}}, None, 0),
    ("an empty inventory", {}, None, 2),
    ("the expected burner missing", {"other": {"private_key": KEY}}, None, 2),
    ("an entry without private_key", {"oz": {}}, None, 2),
    ("an entry with an extra field", {"oz": {"private_key": KEY, "note": "x"}}, None, 2),
    ("a key that is not a felt", {"oz": {"private_key": "nope"}}, None, 2),
    ("a zero key", {"oz": {"private_key": "0x0"}}, None, 2),
    ("a list, not an object", [{"private_key": KEY}], None, 2),
    ("not JSON", '{"oz": {"private_key": "' + KEY + '"', None, 2),
    ("a valid inventory, the key leaked in the spike folder", {"oz": {"private_key": KEY}}, leak, 1),
    ("a valid inventory, the key file tracked by git", {"oz": {"private_key": KEY}}, track, 1),
]

failures = 0
for name, inventory, setup, expected in CASES:
    code, output = run(inventory, setup)
    n = int(KEY, 16)
    clean = KEY[2:].lstrip("0") not in output.lower() and str(n) not in output
    ok = code == expected and clean
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}: exit {code} (expected {expected}), key {'not shown' if clean else 'SHOWN'}")
print(f"{failures} failed" if failures else "all passed")
sys.exit(1 if failures else 0)
