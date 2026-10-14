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

/** OPS-02's deployment on Starknet Sepolia (#502, #505). */
export const SEPOLIA: Network = {
  chainId: "SN_SEPOLIA",
  commit: "e58876360629ab1b4b496fa700a03c7ecb747a00",
  record: "deployments/sepolia/2026-10-14-e588763.json",
  contracts: {
    registry: {
      address: "0x055c36a0658ed2c74a76e6ed1ae9cb6416457d1db78782ce3fc178197dbcfc0d",
      classHash: "0x5b51ae81d64a249491bcc16f27a3525ee3bbbeb8210c0eefc2482968f37c764",
    },
    tx_hash_fate: {
      address: "0x013989c8c08960fa4694f407b856c3f6ef68bfeb3e05ca14fbd263664b5e9bed",
      classHash: "0x31edd698a1f20d5bb78d2c1028154038568fe564d2c823b9440269db45c1135",
    },
    hub: {
      address: "0x06a7418b34e96fdf37ef2434dcbc2d66843a3999e57d8988ac996c4637faafe1",
      classHash: "0x40cfc88c33788fc851f6ae0b750c645c5c6e82bb9d9b19bf88107592a50abad",
    },
    instances: {
      address: "0x007903c84f7fd00e71bcc602e624e26561c115d59feb4f23c42a1812b37bc630",
      classHash: "0x1b50a902623cf68503ecb4e1b5911096cd490fdc0c8c0dc07eda64c862a27bb",
    },
  },
};

/** The four contracts, in the record's order. */
export const CONTRACT_NAMES = ["registry", "tx_hash_fate", "hub", "instances"] as const;
