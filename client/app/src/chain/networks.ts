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

/** OPS-02's deployment on Starknet Sepolia (#502, #505, #519, #525). */
export const SEPOLIA: Network = {
  chainId: "SN_SEPOLIA",
  commit: "a1b1d16200165c251a498180647a548d1d27f089",
  record: "deployments/sepolia/2026-10-15-a1b1d16.json",
  contracts: {
    registry: {
      address: "0x079e5f1d3f8282094facd7383c383adb2bfde44dff4c8450671f2f76bc093096",
      classHash: "0x20c55b5148abd888553f58623e4cad9b8374e75fe2b8b250ff1a3203c6ab47c",
    },
    tx_hash_fate: {
      address: "0x04b5a50ca5028952cabadad0d945685275191946b62ef4f375093ea7c04d5e2f",
      classHash: "0x31edd698a1f20d5bb78d2c1028154038568fe564d2c823b9440269db45c1135",
    },
    hub: {
      address: "0x0254db60da143e867334d8b18e59bd82f7e02e251ead6f37340ad71ad1df7729",
      classHash: "0x40cfc88c33788fc851f6ae0b750c645c5c6e82bb9d9b19bf88107592a50abad",
    },
    instances: {
      address: "0x04a0dedded9572449c855ae70b107f76ee07c856e71d85707f9a3ef077105f09",
      classHash: "0x1b50a902623cf68503ecb4e1b5911096cd490fdc0c8c0dc07eda64c862a27bb",
    },
  },
};

/** The four contracts, in the record's order. */
export const CONTRACT_NAMES = ["registry", "tx_hash_fate", "hub", "instances"] as const;
