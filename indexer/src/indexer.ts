// The follow loop (D-130; SPK-11 §4, rules R1 and R6). Each step:
// 1. reads the node's tip, then checks the stored tip against the node's block at that height, by
//    hash AND commitments. If they differ, the state is `rewinding`: the fork point is the highest
//    stored block the node still has, and every table goes back to it in one transaction;
// 2. checks, the same way, every block applied since the last check (a block is served only once
//    it has been seen again, unchanged, after it was applied; on devnet a replacement block keeps
//    the replaced block's hash, so the parent hash of the next block does not prove its parent);
//    the highest checked block is the served one, and the state is `ok`;
// 3. applies the next blocks, up to a batch, each with the events of both contracts in block order,
//    each in one transaction; a block whose parent is not the stored tip waits for the next step;
// 4. once blocks are checked, forgets the history below the kept depth (never above them).
// It halts (state `halted`, for good; the reason in the log and in every answer) on an event of
// the two contracts it cannot decode, a gap in the lot or trade ids (store.ts), a close of a lot or
// trade that is not open, or a node that went back below the kept history. Pre-confirmed blocks are
// never read: the node's tip is its latest accepted block.
import { Chain, sameBlock, type Header } from "./chain.ts";
import { DecodeError, decode } from "./events.ts";
import { Halt, Store, type Applied, type Config } from "./store.ts";

export type Status = "loading" | "ok" | "rewinding" | "halted";

/** How much history is kept: a number of blocks below the tip, or down to the last L1-accepted block. */
export type Depth = number | "l1";

export type Options = {
  chain: Chain;
  store: Store;
  config: Config;
  depth: Depth;
  /** Blocks applied in one step before the tip is checked again. */
  batch?: number;
  log?: (message: string) => void;
};

export type Rewind = { from: number; to: number; ms: number };

const short = (hash: string) => `${hash.slice(0, 10)}…`;

export class Indexer {
  status: Status = "loading";
  reason = "";
  /** The block every answer is read at (R6): the highest block checked after it was applied. */
  served: Header | null = null;
  chainTip = -1;
  blocksApplied = 0;
  eventsApplied = 0;
  readonly rewinds: Rewind[] = [];
  readonly chain: Chain;
  readonly store: Store;
  private readonly config: Config;
  private readonly depth: Depth;
  private readonly batch: number;
  private readonly log: (message: string) => void;

  constructor(options: Options) {
    this.chain = options.chain;
    this.store = options.store;
    this.config = options.config;
    this.depth = options.depth;
    this.batch = options.batch ?? 100;
    this.log = options.log ?? (() => {});
    this.store.open(this.config);
  }

  private setStatus(next: Status, reason = "") {
    if (this.status === next && this.reason === reason) return;
    this.status = next;
    this.reason = reason;
    this.log(`status ${next}${reason ? `: ${reason}` : ""}`);
  }

  /** Stops following for good: every answer is `halted`, with the reason. */
  halt(reason: string) {
    this.setStatus("halted", reason);
  }

  /** The highest stored block at or below `start` that the node still has, or the start's parent. */
  private async forkPoint(start: number): Promise<number> {
    for (let number = start; ; number--) {
      const stored = this.store.block(number);
      if (!stored) break;
      const onChain = await this.chain.header(number);
      if (onChain && sameBlock(onChain, stored)) return number;
    }
    const lowest = this.store.lowest();
    if (!lowest || lowest.number <= this.config.from)
      return this.config.from - 1;
    throw new Halt(
      `the node went back below the kept history: block ${lowest.number} ${short(lowest.hash)} is not the node's`,
    );
  }

  private async rewind(divergent: Header, why: string) {
    this.setStatus("rewinding", why);
    this.served = null;
    const fork = await this.forkPoint(divergent.number - 1);
    const tip = this.store.tip()?.number ?? fork;
    const started = performance.now();
    this.store.rewind(fork);
    const ms = performance.now() - started;
    this.rewinds.push({ from: tip, to: fork, ms });
    this.log(`rewind from ${tip} to ${fork} (${why}) in ${ms.toFixed(1)} ms`);
  }

  /** One step; true when there is more to do right away. */
  async step(): Promise<boolean> {
    if (this.status === "halted") return false;
    const chainTip = await this.chain.tip();
    this.chainTip = chainTip.number;
    const stored = this.store.tip();
    if (stored) {
      const onChain = await this.chain.header(stored.number);
      if (!onChain || !sameBlock(onChain, stored)) {
        await this.rewind(
          stored,
          `block ${stored.number} ${short(stored.hash)} is no longer the node's`,
        );
        return true;
      }
      const lowest = this.store.lowest()?.number ?? stored.number;
      const first = Math.max(lowest, this.store.checked() + 1);
      for (let number = first; number < stored.number; number++) {
        const block = this.store.block(number);
        if (!block) continue;
        const now = await this.chain.header(number);
        if (!now || !sameBlock(now, block)) {
          await this.rewind(
            block,
            `block ${number} ${short(block.hash)} changed after it was applied`,
          );
          return true;
        }
      }
      if (this.store.checked() < stored.number) {
        this.store.setChecked(stored.number);
        await this.prune(chainTip.number);
      }
      if (!this.served || !sameBlock(this.served, stored)) {
        this.served = stored;
        this.setStatus("ok");
      }
    }
    let next = stored ? stored.number + 1 : this.config.from;
    if (next > chainTip.number) return false;
    const last = Math.min(chainTip.number, next + this.batch - 1);
    for (; next <= last; next++) {
      const block = await this.chain.header(next);
      if (!block) break;
      const below = this.store.tip();
      if (below && block.parent !== below.hash) break; // the next step's checks rewind
      const events = (await this.chain.events(block)).map((raw): Applied => {
        try {
          return { raw, event: decode(raw.source, raw.keys, raw.data) };
        } catch (error) {
          if (!(error instanceof DecodeError)) throw error;
          throw new Halt(
            `undecodable event of ${raw.source} in block ${block.number} (transaction ${raw.transactionIndex}, event ${raw.eventIndex}): ${error.message}`,
          );
        }
      });
      this.store.apply(block, events);
      this.blocksApplied++;
      this.eventsApplied += events.length;
    }
    return true;
  }

  private async prune(chainTip: number) {
    const stored = this.store.tip();
    const lowest = this.store.lowest();
    if (!stored || !lowest) return;
    let floor: number | null;
    if (this.depth === "l1") floor = await this.chain.l1Accepted();
    else floor = chainTip - this.depth;
    if (floor === null) return; // nothing final yet: everything is kept
    // Never above the checked blocks: a block is checked before its history may be forgotten.
    floor = Math.min(floor, stored.number, this.store.checked());
    if (floor > lowest.number) this.store.prune(floor);
  }

  /** Steps until halted or `signal` aborts; waits `pollMs` when idle or after a failed step. */
  async run(pollMs: number, signal: AbortSignal) {
    while (!signal.aborted && this.status !== "halted") {
      let more = false;
      try {
        more = await this.step();
      } catch (error) {
        if (error instanceof Halt) {
          this.halt(error.message);
          break;
        }
        this.log(`step failed: ${(error as Error).message}`);
      }
      if (!more) await sleep(pollMs, signal);
    }
  }
}

function sleep(ms: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve) => {
    if (signal.aborted) return resolve();
    const timer = setTimeout(done, ms);
    function done() {
      clearTimeout(timer);
      signal.removeEventListener("abort", done);
      resolve();
    }
    signal.addEventListener("abort", done);
  });
}
