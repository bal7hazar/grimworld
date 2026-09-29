/**
 * The account module (ADR-0005 §1): what the game may import. Every type here is the module's own;
 * the chain library stays inside `starknet.ts`.
 */
export type {
  AccountErrorCode,
  AccountHandle,
  AccountProvider,
  Call,
  ExecutionId,
  ExecutionStatus,
  KeyStorage,
} from "./types";
export { AccountError } from "./types";
export type { BurnerChain, Funder } from "./burner";
export { STORAGE_KEY, createBurnerProvider } from "./burner";
export { LOCAL_ACCOUNT_CLASS, STRK, createNodeFunder, createStarknetChain } from "./starknet";
export type { ChainConfig, NodeFunderConfig } from "./starknet";
