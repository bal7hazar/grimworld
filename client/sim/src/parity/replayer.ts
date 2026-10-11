// TEST SCAFFOLDING (CLI-02g-A, D-254, D-255): the classes of a `segment2.jsonl` row replayed from
// the calls it recorded, so that `run`'s own logic is held equal to Cairo's before the classes are
// ported. Never exported by `src/index.ts`: a preview predicts batches nobody recorded, and needs
// the ports that lots D to F put behind the same seam, class by class.
//
// At each call `run` makes, the replayer takes the next recorded one: it checks the kind and the
// digest of the inputs `run` computed (`segment/classes.ts`), then returns the recorded words and
// ground, which `run` loads as `SegmentTrait::reload` does. A call of another kind, other inputs,
// a call past the recording or a recorded call never made fails the row, naming the call.

import type { ActCall, Classes, TicksCall, TriggerCall } from "../segment/classes";
import { digest } from "../segment/classes";
import type { Call } from "../segment/serde";

/** The recorded calls as `Classes`, and `end`, which fails when a recorded call was not made. */
export function replayer(calls: readonly Call[]): Classes & { end(): void } {
  let next = 0;
  function take<K extends Call["kind"]>(kind: K, inputs: bigint): Extract<Call, { kind: K }> {
    const at = next++;
    const call = calls[at];
    if (call === undefined) {
      throw new Error(`call ${at} (${kind}): ${calls.length} calls recorded, run made more`);
    }
    if (call.kind !== kind) {
      throw new Error(`call ${at} (${kind}): Cairo made a ${call.kind} call`);
    }
    if (call.digest !== inputs) {
      throw new Error(
        `call ${at} (${kind}): digest 0x${inputs.toString(16)}, Cairo 0x${call.digest.toString(16)}`,
      );
    }
    return call as Extract<Call, { kind: K }>;
  }
  return {
    ticks(c: TicksCall) {
      const { words, ground } = take("ticks", digest.ticks(c));
      return { words, ground };
    },
    act(c: ActCall) {
      const { words, ground, outcome } = take("act", digest.act(c));
      return { words, ground, outcome };
    },
    trigger(c: TriggerCall) {
      const { words, ground, triggered } = take("trigger", digest.trigger(c));
      return { words, ground, triggered };
    },
    end() {
      if (next !== calls.length) {
        throw new Error(`call ${next} (${calls[next]!.kind}): recorded, run did not make it`);
      }
    },
  };
}
