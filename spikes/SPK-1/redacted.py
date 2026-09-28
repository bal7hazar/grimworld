#!/usr/bin/env python3
"""SPK-1: run a command and write its output with the Sepolia account's values redacted. The
command's stdout and stderr are captured in memory and redacted before anything reaches a file
or the terminal, so no unredacted byte is ever written. Used for SPK-2's price reader, which polls
public endpoints and may name the owner's (SPK-2's files stay untouched):

    python3 spikes/SPK-1/redacted.py spikes/SPK-1/prices-output.txt -- python3 spikes/SPK-2/prices.py

Redacted: STARKNET_RPC_URL (the whole value, and its host), STARKNET_ACCOUNT_ADDRESS and
STARKNET_PRIVATE_KEY (the literal value; for a hex felt also every hex form with or without
leading zeros, and its decimal form). STARKNET_NETWORK names the network (for example `sepolia`)
and is not redacted. A malformed value is redacted as a literal, and every message here is
value-free. With a variable unset there is nothing of it to redact, and the script says so.
"""
import os
import re
import subprocess
import sys
from urllib.parse import urlparse

FELT = re.compile(r"0x[0-9a-fA-F]{1,64}")


def patterns():
    out = []
    for name, label in (("STARKNET_RPC_URL", "<STARKNET_RPC_URL>"),
                        ("STARKNET_ACCOUNT_ADDRESS", "<ACCOUNT>"),
                        ("STARKNET_PRIVATE_KEY", "<KEY>")):
        value = os.environ.get(name, "")
        if not value:
            print(f"redacted.py: {name} is not set, nothing of it to redact", file=sys.stderr)
            continue
        out.append((re.compile(re.escape(value)), label))
        if name == "STARKNET_RPC_URL":
            try:
                host = urlparse(value).netloc
            except ValueError:
                host = ""
            if host:
                out.append((re.compile(re.escape(host), re.I), "<RPC_HOST>"))
        elif FELT.fullmatch(value):
            n = int(value, 16)
            out.append((re.compile(f"0x0*{n:x}", re.I), label))
            out.append((re.compile(rf"(?<![0-9]){n}(?![0-9])"), label))
    return out


def redact(text, rules):
    for pattern, label in rules:
        text = pattern.sub(label, text)
    return text


def main():
    if len(sys.argv) < 4 or sys.argv[2] != "--":
        print("usage: redacted.py OUTPUT -- COMMAND [ARGS...]", file=sys.stderr)
        return 2
    output, command = sys.argv[1], sys.argv[3:]
    rules = patterns()
    run = subprocess.run(command, capture_output=True, text=True)
    with open(output, "w") as f:
        f.write(redact(run.stdout, rules))
    sys.stderr.write(redact(run.stderr, rules))
    print(f"redacted.py: {len(rules)} redaction rules; output written to {output}; exit {run.returncode}",
          file=sys.stderr)
    return run.returncode


sys.exit(main())
