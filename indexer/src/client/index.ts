// The indexer's client library (IDX-01b), `@grimworld/indexer/client`: the queries through the
// freshness rule (R3), and the subscriptions' caches (R4). It runs in a browser: nothing in this
// folder imports a `node:` module or anything outside it, and it holds no key.
export {
  IndexerClient,
  parseFrame,
  type Checked,
  type ClientOptions,
} from "./client.ts";
export {
  InvitationCache,
  LotCache,
  PresenceCache,
  StreamCache,
  byPriceThenLot,
} from "./caches.ts";
export { jsonRpcReader, type NodeBlock, type NodeReader } from "./reader.ts";
export * from "./protocol.ts";
