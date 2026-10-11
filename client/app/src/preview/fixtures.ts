import { selector } from "./calls";
import { type FunctionInvocation, type InvokeTrace, type TraceEvent, eventSelector } from "./trace";
import { type InstanceView, encodeInstanceView, unpackHeader } from "./view";

/**
 * Traces shaped by starknet-specs v0.8 (`INVOKE_TXN_TRACE`), for the tests: the account's
 * `__execute__` calling `play` (whose body and events sit in a nested library call, as
 * `PlayLibrary`'s do) and `instance_state`. Part 2 replaces them with a recorded trace.
 */

const hex = (value: bigint | number): string => `0x${BigInt(value).toString(16)}`;
const LIVE = 1n << 250n;

export const INSTANCES = "0x0123";
export const INSTANCE_ID = (7n << 32n) | 3n;

/** A stored header word (`LIVE` set) with these fields, the rest 0. */
export function headerWord(fields: { generation?: number; sequence?: number; clock?: number }) {
  return (
    BigInt(fields.generation ?? 0) +
    (BigInt(fields.sequence ?? 0) << 32n) +
    (BigInt(fields.clock ?? 0) << 64n) +
    LIVE
  );
}

/** A view of one member and two goblins, after a batch at `clock`. */
export function view(clock = 12, sequence = 3): InstanceView {
  const word = headerWord({ generation: 7, sequence, clock });
  return {
    instanceId: INSTANCE_ID,
    headerWord: word,
    header: unpackHeader(word),
    entropy: 0xabcn,
    revealed: 0b11n,
    quotas: LIVE + 1n,
    tasks: [LIVE + 2n],
    members: [
      {
        state: LIVE + 0x10n,
        timers: LIVE + 0x11n,
        effects: LIVE + 0x12n,
        recharges: LIVE + 0x13n,
        stats: LIVE + 0x14n,
        bar: LIVE + 0x15n,
        kit: LIVE + 0x16n,
        controller: 0xacc0n,
      },
    ],
    roster: [],
    goblins: [
      { entity: 24, derived: false, state: LIVE + 0x20n, timers: LIVE + 0x21n },
      { entity: 25, derived: true, state: 0x30n, timers: 0x31n },
    ],
    chunks: [
      { chunk: 0, kind: 2, terrain: 0x40n, features: 0x41n, goblins: [] },
      {
        chunk: 1,
        kind: 2,
        terrain: 0x42n,
        features: 0x43n,
        goblins: [{ entity: 24, derived: false, state: LIVE + 0x20n, timers: LIVE + 0x21n }],
      },
    ],
  };
}

export type Played = {
  played: number;
  stop: number;
  sequence: number;
  clock: number;
  killed?: { entity: number; caste: number; tile: number; by: number }[];
  revealed?: number[];
  defeated?: boolean;
  closed?: number;
};

const key = (name: keyof typeof eventSelector) => [hex(eventSelector[name]), hex(INSTANCE_ID)];

function invocation(
  partial: Partial<FunctionInvocation> & Pick<FunctionInvocation, "result">,
): FunctionInvocation {
  return { calls: [], events: [], ...partial };
}

/** The trace of a batch that ran: its events spread over `play` and its library call. */
export function playedTrace(batch: Played, after: InstanceView = view(batch.clock)): InvokeTrace {
  let order = 0;
  const library: TraceEvent[] = [
    ...(batch.killed ?? []).map((k) => ({
      order: order++,
      keys: key("GoblinKilled"),
      data: [k.entity, k.caste, k.tile, k.by].map(hex),
    })),
    ...(batch.revealed ?? []).map((chunk) => ({
      order: order++,
      keys: key("ChunkRevealed"),
      data: [hex(chunk)],
    })),
    ...(batch.defeated ? [{ order: order++, keys: key("Defeated"), data: [hex(41)] }] : []),
    {
      order: order++,
      keys: key("BatchPlayed"),
      // adventurer, from, played, stop, sequence, clock, version
      data: [
        41,
        batch.sequence - batch.played,
        batch.played,
        batch.stop,
        batch.sequence,
        batch.clock,
        1,
      ].map(hex),
    },
  ];
  const own: TraceEvent[] =
    batch.closed === undefined
      ? []
      : [{ order: order++, keys: key("InstanceClosed"), data: [hex(batch.closed)] }];
  return {
    type: "INVOKE",
    execute_invocation: invocation({
      result: [],
      calls: [
        invocation({
          contract_address: INSTANCES,
          entry_point_selector: hex(selector.play),
          result: [],
          events: own,
          calls: [invocation({ result: ["0x0"], events: library })],
        }),
        invocation({
          contract_address: INSTANCES,
          entry_point_selector: hex(selector.instance_state),
          result: encodeInstanceView(after).map(hex),
        }),
      ],
    }),
  };
}

/** A node's reason for a `play` that panicked with `message`, framed as blockifier frames it. */
export function revertedTrace(message: string): InvokeTrace {
  const short = (text: string) =>
    `${hex([...new TextEncoder().encode(text)].reduce((felt, byte) => felt * 256n + BigInt(byte), 0n))} ('${text}')`;
  return {
    type: "INVOKE",
    execute_invocation: {
      revert_reason:
        "Transaction execution has failed:\n" +
        "0: Error in the called contract (contract address: 0x0abc, class hash: 0x0def, selector: 0x015d40a3d6ca2ac30f4031e42be28da9b056fef9bb7357ac5e85627ee876e5ad):\n" +
        `Execution failed. Failure reason:\n(${short(message)}, ${short("ENTRYPOINT_FAILED")}, ${short("ENTRYPOINT_FAILED")}).\n`,
    },
  };
}
