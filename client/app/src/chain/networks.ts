/**
 * The public networks the chain mode knows (CLI-11e, §2.4): Sepolia's deployment, copied from
 * track game's OPS-02 record (D-154: the commit its classes were built from, and each class hash).
 * Its addresses and class hashes are public; no key, no account address and no node URL is here.
 * `networks.test.ts` reads the record named by `record` and checks this entry equals it, so a new
 * record fails the test until the entry follows.
 *
 * This module imports nothing: the probe (`probe-sepolia.mjs`) loads it under plain Node.
 */

/** One of the four contracts the mode reads: its address and the class hash recorded for it. */
export interface NetworkContract {
  readonly address: string;
  readonly classHash: string;
}

export interface Network {
  /** As `starknet_chainId` names it (the record's `chain_id`). */
  readonly chainId: string;
  /** The commit of `main` the classes were built from. */
  readonly commit: string;
  /** The record this entry is copied from, from the repository's root. */
  readonly record: string;
  readonly contracts: {
    readonly registry: NetworkContract;
    readonly tx_hash_fate: NetworkContract;
    readonly hub: NetworkContract;
    readonly instances: NetworkContract;
  };
}

/** OPS-02's deployment on Starknet Sepolia (#502, #505, #519, #525, #535). */
export const SEPOLIA: Network = {
  chainId: "SN_SEPOLIA",
  commit: "cf6ddbb8c78831de5d5b490579c6dc792972daea",
  record: "deployments/sepolia/2026-10-16-cf6ddbb.json",
  contracts: {
    registry: {
      address: "0x00a0494e32587c44950e7d0e6220274f4079c53f995c146a71267caee605a9f1",
      classHash: "0x25de0b40c8405858f4f054443bdb27b008c356c2189308bf0cb0347a1899fb7",
    },
    tx_hash_fate: {
      address: "0x033d06c38c6fbe00a1b2b6c6b7860ec3e07bf2c757ea8c8764df8160ed487355",
      classHash: "0x31edd698a1f20d5bb78d2c1028154038568fe564d2c823b9440269db45c1135",
    },
    hub: {
      address: "0x076c5bd9fea636e06d06de7690bba7987aabeacbc2adf800c9859197a755b384",
      classHash: "0xbde254c64038bd8f6a461d2198adb8de332122e3c17895035134998b04bec9",
    },
    instances: {
      address: "0x07e1f9c353ce5f92769781ecfbbb3bd2ff7a691008e7c98a59a668dea6971f85",
      classHash: "0x7ca128431ea8a54ccb164610a9dd38106d79a46a75c3e17fe7928708e4a2725",
    },
  },
};

/** The four contracts, in the record's order. */
export const CONTRACT_NAMES = ["registry", "tx_hash_fate", "hub", "instances"] as const;
