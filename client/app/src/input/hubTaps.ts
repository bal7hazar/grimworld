import type { HubFigure, HubTarget } from "../render/hubView";
import type { LoopIntent } from "./intent";

/**
 * What a tap on a hub's place or present adventurer means (CLI-03c): an intent, never a result.
 * Since CLI-03f the taps reach the hub through the zone's canvas (`sandbox/fixtures/hubWorld.ts`
 * says which hex is what); the service row under the map sends the same intents at once.
 */

/** A building's tap and its service entry: the same intent, so the same screen. */
export function targetIntent(target: HubTarget): LoopIntent {
  return target.kind === "gate"
    ? { kind: "open gate screen" }
    : { kind: "open service", service: target.service };
}

export function figureIntent(figure: HubFigure): LoopIntent {
  return { kind: "inspect adventurer", adventurer: figure.id };
}
