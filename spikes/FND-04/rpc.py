"""A read-only JSON-RPC client for Starknet: an explicit list of read methods, nothing else.

No account, no key, no signing, no `starknet_add*`: this task sends nothing (COMMON §4).
"""
import json
import urllib.request

# The public Sepolia endpoints already listed in spikes/SPK-2/prices.py.
SEPOLIA_ENDPOINTS = [
    "https://api.cartridge.gg/x/starknet/sepolia",
    "https://starknet-sepolia-rpc.publicnode.com",
    "https://starknet-sepolia.drpc.org",
    "https://rpc.starknet-testnet.lava.build",
]

READ_METHODS = frozenset(
    {
        "starknet_specVersion",
        "starknet_chainId",
        "starknet_traceTransaction",
        "starknet_getTransactionReceipt",
        "starknet_getTransactionByHash",
        "starknet_getClassHashAt",
        "starknet_getStorageAt",
        "starknet_blockNumber",
        "starknet_getBlockWithTxHashes",
    }
)

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) grimworld-fnd04-read-only"


class RpcError(Exception):
    pass


class Rpc:
    def __init__(self, url, timeout=60):
        self.url = url
        self.timeout = timeout

    def call(self, method, params):
        if method not in READ_METHODS:
            raise PermissionError(f"refused: {method} is not a read method of this task")
        body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
        req = urllib.request.Request(
            self.url,
            data=body,
            headers={"content-type": "application/json", "user-agent": USER_AGENT},
        )
        with urllib.request.urlopen(req, timeout=self.timeout) as resp:
            data = json.load(resp)
        if "error" in data:
            raise RpcError(json.dumps(data["error"])[:500])
        return data["result"]
