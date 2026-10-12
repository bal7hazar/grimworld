/**
 * The recording wrapper of the classes a segment calls (CLI-05 brief §7.2): each `TickLibrary::ticks`
 * call's input (`TicksCall`: words, content, board, level, ground, `n`) and output, and each
 * `ActionLibrary::act` call's, kept in call order, the classes' results passed through unchanged. A
 * call's inputs are already copies (`run` passes each class a copy of the words and the ground,
 * `segment/classes.ts`), so keeping them keeps the state the call met.
 */

import {
  type ActCall,
  type Classes,
  type Ground,
  type Ran,
  type Segment,
  type TicksCall,
  type Words,
  runSegment,
} from "@grimworld/sim";

/** A `ticks` call and what it returned. */
export interface TicksRecord {
  readonly call: TicksCall;
  readonly out: { readonly words: Words; readonly ground: Ground };
}

/** An `act` call (its input words are the state before the action). */
export interface ActRecord {
  readonly call: ActCall;
}

export interface Recording {
  readonly classes: Classes;
  readonly ticks: TicksRecord[];
  readonly acts: ActRecord[];
}

/** `classes`, each `ticks` and `act` call recorded in order. */
export function recording(classes: Classes): Recording {
  const ticks: TicksRecord[] = [];
  const acts: ActRecord[] = [];
  return {
    ticks,
    acts,
    classes: {
      ticks(call) {
        const out = classes.ticks(call);
        ticks.push({ call, out });
        return out;
      },
      act(call) {
        acts.push({ call });
        return classes.act(call);
      },
      trigger: (call) => classes.trigger(call),
    },
  };
}

/** A segment's run with its calls recorded. */
export interface RecordedRun extends Ran {
  readonly ticks: readonly TicksRecord[];
  readonly acts: readonly ActRecord[];
}

/** `runSegment` on `segment` through recorded `classes`. */
export function runRecorded(segment: Segment, classes: Classes): RecordedRun {
  const rec = recording(classes);
  const ran = runSegment(segment, rec.classes);
  return { ...ran, ticks: rec.ticks, acts: rec.acts };
}
