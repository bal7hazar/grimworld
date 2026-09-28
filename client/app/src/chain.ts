import { RpcProvider } from "starknet";

/**
 * The client's only door to the chain (ADR-0007): a starknet.js provider on a node URL. Nothing
 * calls it yet; providers and calls arrive with FND-05 and CLI-01. Building one does not touch
 * the network.
 */
export function createProvider(nodeUrl: string): RpcProvider {
  return new RpcProvider({ nodeUrl });
}
