import type { LoopIntent, ServiceId } from "../../input/intent";
import type { Tile } from "../../render/view";
import { HUB_VIEWS } from "../fixtures/hubs";
import { BIOME_NAMES, GATES, type GateRecord, gateOf, locationOf } from "../fixtures/region";
import { type ExpeditionEnd, entryThrough, hubAfter, hubGateAt } from "../placeholders";

/**
 * The loop's screens (CLI-03c): hub, service, Gate screen, entry, instance, closing report. A
 * small state machine driven by intents (`input/intent.ts`) and answered by the fixed data and
 * `placeholders.ts`; CLI-03 answers them with `client/sim` and the chain. Pure: no clock, no
 * randomness; the entry's wait is the screen's timer, which sends the answer `entry drawn`.
 */

export type Screen =
  | { readonly kind: "hub"; readonly hub: number; readonly inspected: number | null }
  | { readonly kind: "service"; readonly hub: number; readonly service: ServiceId }
  | { readonly kind: "gate"; readonly hub: number }
  /** The entry moment: the entry draw, a Fate action sent alone, awaited (design/02). */
  | { readonly kind: "entry"; readonly hub: number; readonly gate: number }
  | {
      readonly kind: "instance";
      readonly location: number;
      /** The gate entered by, and the tile it put the adventurer on. */
      readonly gate: number;
      readonly entry: Tile;
      /** Where the adventurer stands now, as the room reports it. */
      readonly tile: Tile;
      /**
       * The adventurer has stood off a hub gate's anchor since arriving (true at once when the
       * entry tile is no anchor). The room offers to leave by a gate only then (CLI-03d).
       */
      readonly left: boolean;
    }
  | {
      readonly kind: "report";
      readonly outcome: "returned" | "defeated";
      readonly how: ExpeditionEnd["how"];
      /** The hub the report closes on (design/02's table). */
      readonly hub: number;
    };

export interface LoopState {
  readonly screen: Screen;
  /** The last hub visited: where defeat and travelling back lead (design/02). */
  readonly lastHub: number;
  /** One line on what the last event did, for the log. */
  readonly said: string;
}

/** What the fixed data, or the room, answers: not a tap. */
export type LoopAnswer =
  /** The entry draw is made: the instance opens on its entry chunk. */
  | { readonly kind: "entry drawn" }
  /** The adventurer stands on a tile of the instance (after each step of the room). */
  | { readonly kind: "moved"; readonly tile: Tile };

export type LoopEvent = LoopIntent | LoopAnswer;

export function hubState(hub: number): LoopState {
  if (!HUB_VIEWS.has(hub)) throw new Error(`no hub ${hub} in the fixed data`);
  return {
    screen: { kind: "hub", hub, inspected: null },
    lastHub: hub,
    said: `at ${hubName(hub)}`,
  };
}

export function hubName(hub: number): string {
  return HUB_VIEWS.get(hub)?.name ?? `location ${hub}`;
}

/** The gates out of a hub, from the fixed data (the Gate screen's list), lowest id first. */
export function gatesFrom(hub: number): readonly GateRecord[] {
  return GATES.filter((g) => g.source === hub).sort((a, b) => a.id - b.id);
}

/** The hub gate under the adventurer in the instance, if any (D-148: standing on its anchor). */
export function gateHere(state: LoopState): GateRecord | null {
  const { screen } = state;
  if (screen.kind !== "instance") return null;
  return hubGateAt(GATES, screen.location, screen.tile);
}

/**
 * The hub gate the room offers to leave by on its own: the adventurer stands on its anchor after
 * having left an anchor, never on arrival (CLI-03d). The Leave control uses `gateHere` instead.
 */
export function leaveOffer(state: LoopState): GateRecord | null {
  const { screen } = state;
  if (screen.kind !== "instance" || !screen.left) return null;
  return gateHere(state);
}

/** The I-5 confirmation's text for leaving by `gate` (design/11), or the travel-back one. */
export function leaveQuestion(gate: GateRecord | null): string {
  return gate
    ? `Leave the instance for ${hubName(gate.destination)}? The goblins will be back next time.`
    : "Travel back to the last hub visited? The instance closes.";
}

function ignored(state: LoopState, event: LoopEvent): LoopState {
  return { ...state, said: `${event.kind}: nothing to do on the ${state.screen.kind} screen` };
}

function end(state: LoopState, end: ExpeditionEnd): LoopState {
  const hub = hubAfter(end, state.lastHub);
  const outcome = end.how === "defeat" ? "defeated" : "returned";
  return {
    ...state,
    screen: { kind: "report", outcome, how: end.how, hub },
    said: `${end.how}: ${outcome}, report, then ${hubName(hub)}`,
  };
}

/** The next state for an event; an event the screen does not take changes only the log line. */
export function step(state: LoopState, event: LoopEvent): LoopState {
  const { screen } = state;
  switch (screen.kind) {
    case "hub":
      switch (event.kind) {
        case "open service":
          return {
            ...state,
            screen: { kind: "service", hub: screen.hub, service: event.service },
            said: `open ${event.service}`,
          };
        case "open gate screen":
          return { ...state, screen: { kind: "gate", hub: screen.hub }, said: "open the Gate" };
        case "inspect adventurer": {
          const figure = HUB_VIEWS.get(screen.hub)?.figures.find((f) => f.id === event.adventurer);
          if (!figure) return ignored(state, event);
          return {
            ...state,
            screen: { ...screen, inspected: figure.id },
            said: `inspect ${figure.name}, ${figure.profession} level ${figure.level}`,
          };
        }
        case "back":
          return { ...state, screen: { ...screen, inspected: null }, said: "inspection closed" };
        default:
          return ignored(state, event);
      }
    case "service":
      if (event.kind !== "back") return ignored(state, event);
      return { ...state, screen: { kind: "hub", hub: screen.hub, inspected: null }, said: "back" };
    case "gate":
      if (event.kind === "back") {
        return {
          ...state,
          screen: { kind: "hub", hub: screen.hub, inspected: null },
          said: "back",
        };
      }
      if (event.kind === "enter gate") {
        const gate = gatesFrom(screen.hub).find((g) => g.id === event.gate);
        if (!gate) return ignored(state, event);
        return {
          ...state,
          screen: { kind: "entry", hub: screen.hub, gate: gate.id },
          said: `enter gate ${gate.id}: the entry draw`,
        };
      }
      return ignored(state, event);
    case "entry": {
      if (event.kind !== "entry drawn" && event.kind !== "skip entry") return ignored(state, event);
      const gate = gateOf(screen.gate);
      if (!gate) return ignored(state, event);
      const { location, tile } = entryThrough(gate);
      return {
        ...state,
        screen: {
          kind: "instance",
          location,
          gate: gate.id,
          entry: tile,
          tile,
          left: hubGateAt(GATES, location, tile) === null,
        },
        said: `${event.kind}: ${locationName(location)} at (${tile.x}, ${tile.y})`,
      };
    }
    case "instance":
      switch (event.kind) {
        case "moved":
          return {
            ...state,
            screen: {
              ...screen,
              tile: event.tile,
              left: screen.left || hubGateAt(GATES, screen.location, event.tile) === null,
            },
          };
        case "leave": {
          // Only through the gate asked about, and only from its anchor (D-148): a walk may have moved on.
          const gate = gateHere(state);
          return gate?.id === event.gate ? end(state, { how: "gate", gate }) : ignored(state, event);
        }
        case "travel back":
          return end(state, { how: "travel back" });
        case "defeat now":
          return end(state, { how: "defeat" });
        default:
          return ignored(state, event);
      }
    case "report":
      if (event.kind !== "close report") return ignored(state, event);
      return { ...hubState(screen.hub), said: `report closed: ${hubName(screen.hub)}` };
  }
}

export function locationName(location: number): string {
  if (HUB_VIEWS.has(location)) return hubName(location);
  const record = locationOf(location);
  if (!record) return `location ${location}`;
  const biome = BIOME_NAMES[record.biome] ?? "unknown";
  return `the ${biome} zone (levels ${record.level_min}–${record.level_max})`;
}
