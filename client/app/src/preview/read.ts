import { selector as callSelector } from "./calls";
import { createRpc } from "./rpc";
import {
  Felts,
  type InstanceView,
  type RegionChunk,
  decodeInstanceView,
  decodeRegion,
} from "./view";

/**
 * The views the preview and the mirror read, over JSON-RPC (`starknet_call`), as the simulator
 * speaks it: `Instances.instance_state`, `Instances.instance_region`, `Instances.placement` and the
 * Registry's `content_version` and `record` (contracts/persistent/src/systems/registry.cairo :160,
 * :185). The location's extent is the view's now (VIEW-01), no longer read from `record`.
 */

/** Selectors (`sn_keccak` of the names), held to starknet.js's by `calls.test.ts`. */
export const readSelector = {
  content_version: 0x173c0c4da76a0c02bfcddc342900b401823b98a52802d3e79a44cab1defe316n,
  record: 0x295dc3dc464c3e16e47c379993b869b853c777a241ee7fb9755e2a09f32dadbn,
  placement: 0xc3c6a7639329ef1475a5e4c5ca679d480db6bfd8ef470574140863ec12d8f1n,
  instance_region: 0xf27dd0d6b3404ddd7330bfcf3c343171a549e2d9563505b163802e2f9700cen,
} as const;

/** `content::LOCATION`, the Registry's kind of a location record. */
export const LOCATION = 2;
/** `types::REGION_PAGE`: the chunks `instance_region` answers at most at once. */
const REGION_PAGE = 16;
const CHUNKS = 225;

/**
 * A block a read is pinned to: a tag (`pre_confirmed`, `latest`, …), or one block by its hash, as a
 * receipt names it (CLI-11b: the region after a sent batch, read at the batch's own block).
 */
export type BlockId = string | { readonly blockHash: string };

export interface ReaderConfig {
  nodeUrl: string;
  /** The block read; `pre_confirmed`, as the simulator's, by default. */
  block?: BlockId;
  fetch?: typeof fetch;
}

export interface Reader {
  call(to: string, entry: bigint, calldata: readonly bigint[]): Promise<bigint[]>;
  instanceState(instances: string, instanceId: bigint): Promise<InstanceView>;
  /** Every chunk of the instance, in order (`instance_region`, page by page). */
  region(instances: string, instanceId: bigint): Promise<RegionChunk[]>;
  /**
   * Where an adventurer stands (`Instances.placement`, instances.cairo :221): the instance, the
   * member slot it controls (`placement.member`, which `play` centres its area on, play.cairo
   * :186-187) and whether it is inside. The instance id is 0 for an adventurer placed nowhere.
   */
  placement(
    instances: string,
    adventurerId: number,
  ): Promise<{ instanceId: bigint; member: number; inside: boolean }>;
  contentVersion(registry: string): Promise<number>;
  /** The parts of a Registry record (the content's, for CLI-10d; the location's are the view's). */
  record(registry: string, kind: number, id: number): Promise<bigint[]>;
}

const hex = (value: bigint): string => `0x${value.toString(16)}`;

/** The JSON-RPC `block_id` of a block: the tag as it is, a hash as `{ block_hash }`. */
export function blockId(block: BlockId): string | { block_hash: string } {
  return typeof block === "string" ? block : { block_hash: hex(BigInt(block.blockHash)) };
}

export function createReader(config: ReaderConfig): Reader {
  const block = blockId(config.block ?? "pre_confirmed");
  const rpc = createRpc(String(config.nodeUrl), config.fetch ?? globalThis.fetch.bind(globalThis));
  const call = async (to: string, entry: bigint, calldata: readonly bigint[]) => {
    const result = await rpc("starknet_call", {
      request: {
        contract_address: hex(BigInt(to)),
        entry_point_selector: hex(entry),
        calldata: calldata.map(hex),
      },
      block_id: block,
    });
    if (!Array.isArray(result)) throw new TypeError("starknet_call: not a list of felts");
    return result.map((felt) => BigInt(String(felt)));
  };
  return {
    call,
    async instanceState(instances, instanceId) {
      return decodeInstanceView(await call(instances, callSelector.instance_state, [instanceId]));
    },
    async region(instances, instanceId) {
      const chunks: RegionChunk[] = [];
      for (let first = 0; first < CHUNKS; first += REGION_PAGE) {
        const page = await call(instances, readSelector.instance_region, [
          instanceId,
          BigInt(first),
          BigInt(REGION_PAGE),
        ]);
        chunks.push(...decodeRegion(page));
      }
      return chunks;
    },
    async contentVersion(registry) {
      const [version] = await call(registry, readSelector.content_version, []);
      if (version === undefined || version >= 1n << 32n) {
        throw new RangeError("content_version: not a u32");
      }
      return Number(version);
    },
    async record(registry, kind, id) {
      const felts = await call(registry, readSelector.record, [BigInt(kind), BigInt(id)]);
      // A `Span<felt252>`: its length, then its parts
      const [length, ...parts] = felts;
      if (length === undefined || Number(length) !== parts.length) {
        throw new RangeError("record: not a span");
      }
      return parts;
    },
    async placement(instances, adventurerId) {
      const felts = await call(instances, readSelector.placement, [BigInt(adventurerId)]);
      const r = new Felts(felts);
      const placement = { instanceId: r.u64(), member: r.uint(8), inside: r.bool() };
      r.end();
      return placement;
    },
  };
}
