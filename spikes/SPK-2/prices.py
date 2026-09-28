#!/usr/bin/env python3
"""Read the current gas prices of Starknet mainnet and Sepolia from public JSON-RPC endpoints
(read-only: `starknet_getBlockWithTxHashes` on the latest block, no account, no transaction),
and the STRK price in USD from public sources. Prints raw figures with their time and source.

    python3 spikes/SPK-2/prices.py
"""
import datetime
import json
import urllib.request

ENDPOINTS = {
    "mainnet": [
        "https://api.cartridge.gg/x/starknet/mainnet",
        "https://starknet-rpc.publicnode.com",
        "https://1rpc.io/starknet",
        "https://starknet.drpc.org",
        "https://rpc.starknet.lava.build",
    ],
    "sepolia": [
        "https://api.cartridge.gg/x/starknet/sepolia",
        "https://starknet-sepolia-rpc.publicnode.com",
        "https://starknet-sepolia.drpc.org",
        "https://rpc.starknet-testnet.lava.build",
    ],
}
PRICES = [
    ("coingecko", "https://api.coingecko.com/api/v3/simple/price?ids=starknet&vs_currencies=usd"),
    ("binance", "https://api.binance.com/api/v3/ticker/price?symbol=STRKUSDT"),
    ("coinbase", "https://api.coinbase.com/v2/prices/STRK-USD/spot"),
    ("kraken", "https://api.kraken.com/0/public/Ticker?pair=STRKUSD"),
]


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def post(url, method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    request = urllib.request.Request(
        url, data=body, headers={"content-type": "application/json", "user-agent": "spk2"}
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def get(url):
    request = urllib.request.Request(url, headers={"user-agent": "spk2"})
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def fri(price):
    return int(price["price_in_fri"], 16)


for network, urls in ENDPOINTS.items():
    for url in urls:
        try:
            block = post(url, "starknet_getBlockWithTxHashes", ["latest"])["result"]
            print(
                json.dumps(
                    {
                        "network": network,
                        "source": url,
                        "read_at": now(),
                        "block_number": block["block_number"],
                        "block_timestamp": datetime.datetime.fromtimestamp(
                            block["timestamp"], datetime.timezone.utc
                        ).strftime("%Y-%m-%dT%H:%M:%SZ"),
                        "starknet_version": block.get("starknet_version"),
                        "l2_gas_fri": fri(block["l2_gas_price"]),
                        "l1_gas_fri": fri(block["l1_gas_price"]),
                        "l1_data_gas_fri": fri(block["l1_data_gas_price"]),
                    }
                )
            )
        except Exception as error:  # noqa: BLE001 - report and try the next endpoint
            detail = str(error)
            if hasattr(error, "read"):
                detail += " " + error.read()[:200].decode(errors="replace")
            print(json.dumps({"network": network, "source": url, "read_at": now(), "error": detail}))

# History: the L2 gas price of past mainnet blocks, from the first endpoint that answered.
HISTORY = [1_000, 10_000, 50_000, 100_000, 200_000, 400_000, 800_000]
try:
    url = ENDPOINTS["mainnet"][0]
    latest = post(url, "starknet_getBlockWithTxHashes", ["latest"])["result"]["block_number"]
    for back in HISTORY:
        block = post(url, "starknet_getBlockWithTxHashes", [{"block_number": latest - back}])["result"]
        print(
            json.dumps(
                {
                    "history": "mainnet",
                    "source": url,
                    "block_number": block["block_number"],
                    "block_timestamp": datetime.datetime.fromtimestamp(
                        block["timestamp"], datetime.timezone.utc
                    ).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "l2_gas_fri": fri(block["l2_gas_price"]),
                    "l1_data_gas_fri": fri(block["l1_data_gas_price"]),
                }
            )
        )
except Exception as error:  # noqa: BLE001
    print(json.dumps({"history": "mainnet", "error": str(error)}))

for name, url in PRICES:
    try:
        print(json.dumps({"strk_usd_source": name, "url": url, "read_at": now(), "raw": get(url)}))
    except Exception as error:  # noqa: BLE001
        print(json.dumps({"strk_usd_source": name, "url": url, "read_at": now(), "error": str(error)}))
