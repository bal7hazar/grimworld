// A fake Starknet node for the unit tests: no network. It answers the read methods the indexer
// uses (JSON-RPC 0.10 shapes, as starknet-devnet 0.10.0 answers them) from blocks held in memory,
// and it can mine, reorganise (with devnet's quirk: a replacement block keeps the replaced block's
// hash, its commitments differ) and move the last L1-accepted block.
import { RpcError, type Rpc } from "../chain.ts";
import { SELECTORS, type EventName, type Source } from "../events.ts";

export const HUB = "0x1111";
export const MARKET = "0x2222";

export type FakeEvent = { source: Source; keys: string[]; data: string[] };
/** A transaction: its events, in order. */
export type FakeTransaction = FakeEvent[];

type Block = {
  number: number;
  hash: string;
  parent: string;
  commitment: string;
  transactions: { hash: string; events: FakeEvent[] }[];
};

const hex = (value: bigint | number) => `0x${BigInt(value).toString(16)}`;

/** The raw keys and data of an event, as a node reports them. */
export function raw(
  source: Source,
  name: EventName,
  keys: (bigint | number)[],
  data: (bigint | number)[],
): FakeEvent {
  return {
    source,
    keys: [SELECTORS[name], ...keys.map(hex)],
    data: data.map(hex),
  };
}

export const ev = {
  located: (hub: number, adventurer: number) =>
    raw("hub", "AdventurerLocated", [hub], [adventurer]),
  title: (adventurer: number, title: number, tier: number) =>
    raw("hub", "TitleDisplayed", [adventurer], [title, tier]),
  trial: (adventurer: number, rank: number, first: boolean) =>
    raw("hub", "TrialPassed", [adventurer], [rank, first ? 1 : 0]),
  cleared: (adventurer: number, dungeon: number) =>
    raw("hub", "DungeonCleared", [adventurer], [dungeon]),
  rank: (adventurer: number, rank: number) =>
    raw("hub", "RankReached", [adventurer], [rank]),
  posted: (
    lot: bigint | number,
    options: {
      key?: bigint;
      size?: number;
      price?: bigint;
      expiry?: bigint;
      equipment?: number;
      modifiers?: bigint;
    } = {},
  ) =>
    raw(
      "market",
      "LotPosted",
      [options.key ?? 7n, options.size ?? 1],
      [
        lot,
        options.price ?? 100n,
        options.expiry ?? 1000n,
        options.equipment ?? 0,
        options.modifiers ?? 0n,
      ],
    ),
  closed: (lot: bigint | number, sold: boolean) =>
    raw("market", "LotClosed", [lot], [sold ? 1 : 0]),
  opened: (trade: bigint | number, invited: number, inviter: number) =>
    raw("market", "TradeOpened", [invited], [trade, inviter]),
  tradeClosed: (trade: bigint | number, outcome: number) =>
    raw("market", "TradeClosed", [trade], [outcome]),
};

export class FakeNode {
  blocks: Block[] = [];
  l1Accepted: number | null = null;
  readonly calls: string[] = [];
  /** Called before each answer: a test injects a reorg between two calls of a step. */
  beforeCall: ((method: string) => void) | null = null;
  private salt = 0;

  constructor(emptyBlocks = 1) {
    for (let i = 0; i < emptyBlocks; i++) this.mine();
  }

  get tip(): number {
    return this.blocks.length - 1;
  }

  /** Mines one block holding these transactions; its number. */
  mine(...transactions: FakeTransaction[]): number {
    const number = this.blocks.length;
    const parent = number === 0 ? "0x0" : this.blocks[number - 1]!.hash;
    const salt = ++this.salt;
    this.blocks.push({
      number,
      hash: hex(0xb000000n + BigInt(number) * 0x1000n + BigInt(salt)),
      parent,
      commitment: hex(0xc000000n + BigInt(salt)),
      transactions: transactions.map((events, index) => ({
        hash: hex(0x7000000n + BigInt(salt) * 0x100n + BigInt(index)),
        events,
      })),
    });
    return number;
  }

  /**
   * Aborts the last `depth` blocks and mines `replacements` (one list of transactions per block).
   * `sameHash`: devnet's quirk, each replacement at a height keeps the aborted block's hash.
   */
  reorg(
    depth: number,
    replacements: FakeTransaction[][] = [],
    sameHash = false,
  ) {
    const aborted = this.blocks.splice(this.blocks.length - depth, depth);
    for (const [index, transactions] of replacements.entries()) {
      this.mine(...transactions);
      const block = this.blocks[this.blocks.length - 1]!;
      const old = aborted[index];
      if (sameHash && old) {
        block.hash = old.hash;
        block.parent = this.blocks[block.number - 1]?.hash ?? "0x0";
      }
    }
  }

  private header(block: Block) {
    return {
      status: "ACCEPTED_ON_L2",
      block_hash: block.hash,
      parent_hash: block.parent,
      block_number: block.number,
      transaction_commitment: block.commitment,
      event_commitment: block.commitment,
      receipt_commitment: block.commitment,
      state_diff_commitment: block.commitment,
      transactions: block.transactions.map((transaction) => transaction.hash),
    };
  }

  readonly rpc: Rpc = async (method, params) => {
    this.calls.push(method);
    this.beforeCall?.(method);
    const p = params as Record<string, unknown>;
    switch (method) {
      case "starknet_blockHashAndNumber": {
        const block = this.blocks[this.tip]!;
        return { block_hash: block.hash, block_number: block.number };
      }
      case "starknet_getBlockWithTxHashes": {
        const id = p.block_id as { block_number: number } | string;
        if (id === "l1_accepted") {
          if (this.l1Accepted === null)
            throw new RpcError(method, {
              code: 24,
              message: "Block not found",
            });
          return this.header(this.blocks[this.l1Accepted]!);
        }
        if (id === "pre_confirmed")
          return { block_number: this.tip + 1, transactions: [] };
        const block =
          typeof id === "object" ? this.blocks[id.block_number] : undefined;
        if (!block)
          throw new RpcError(method, { code: 24, message: "Block not found" });
        return this.header(block);
      }
      case "starknet_getEvents": {
        const filter = p.filter as {
          from_block: { block_hash: string };
          address: string;
          chunk_size: number;
          continuation_token?: string;
        };
        // By hash, as devnet: the highest block with that hash (a replacement shares it).
        const block = [...this.blocks]
          .reverse()
          .find((b) => b.hash === filter.from_block.block_hash);
        if (!block)
          throw new RpcError(method, { code: 24, message: "Block not found" });
        const source =
          BigInt(filter.address) === BigInt(HUB) ? "hub" : "market";
        const all = block.transactions.flatMap(
          (transaction, transactionIndex) =>
            transaction.events.flatMap((event, eventIndex) =>
              event.source === source
                ? [
                    {
                      transaction_hash: transaction.hash,
                      transaction_index: transactionIndex,
                      event_index: eventIndex,
                      block_hash: block.hash,
                      block_number: block.number,
                      from_address: source === "hub" ? HUB : MARKET,
                      keys: event.keys,
                      data: event.data,
                    },
                  ]
                : [],
            ),
        );
        const start = Number(filter.continuation_token ?? 0);
        const end = start + filter.chunk_size;
        return {
          events: all.slice(start, end),
          ...(end < all.length ? { continuation_token: String(end) } : {}),
        };
      }
      default:
        throw new RpcError(method, {
          code: -32601,
          message: "Method not found",
        });
    }
  };
}
