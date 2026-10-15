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

/** OPS-02's deployment on Starknet Sepolia (#502, #505, #519). */
export const SEPOLIA: Network = {
  chainId: "SN_SEPOLIA",
  commit: "c25a426f047ef4347ab8538d7c82672ecc91dcfc",
  record: "deployments/sepolia/2026-10-15-c25a426.json",
  contracts: {
    registry: {
      address: "0x06210c8153a06f22071d1232c8a7f1aee92539087381689ad6ab9ee7b9e6154d",
      classHash: "0x77ca0772f4e4e042b4e9b0a9014fb946fcaed6ff3820c7899f52672d992959c",
    },
    tx_hash_fate: {
      address: "0x077c34bdbff7caabb491029ee8539d1fa86c6b1e426366b49e0787a7ecb41912",
      classHash: "0x31edd698a1f20d5bb78d2c1028154038568fe564d2c823b9440269db45c1135",
    },
    hub: {
      address: "0x0121c0c347e0ebbd7c908892a89d4ccb54ff5e74fbdd2adc63a1bb5e406045ff",
      classHash: "0x40cfc88c33788fc851f6ae0b750c645c5c6e82bb9d9b19bf88107592a50abad",
    },
    instances: {
      address: "0x06860ef05644a4c8890f09187f3726653969782f923847c66274db9ceefc0691",
      classHash: "0x1b50a902623cf68503ecb4e1b5911096cd490fdc0c8c0dc07eda64c862a27bb",
    },
  },
};

/** The four contracts, in the record's order. */
export const CONTRACT_NAMES = ["registry", "tx_hash_fate", "hub", "instances"] as const;
