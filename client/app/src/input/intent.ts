import type { Tile } from "../render/view";

/**
 * What a gesture on the map means: a target, never a result (ORCH-client-visual §6.4). Whoever
 * holds the rules decides what a tap on a tile does.
 */
export type Intent =
  /** A tap on a tile (design/11 *Acting*: move, attack, select). */
  | { readonly kind: "tile"; readonly tile: Tile }
  /** A long press, or a right click on a desktop: inspect what is on the tile. */
  | { readonly kind: "inspect"; readonly tile: Tile };

/** A hub's services (design/11 *Hubs*); the Gate is not one of them, it has its own screen. */
export type ServiceId =
  "guild" | "trainer" | "smith" | "armorer" | "enchanter" | "alchemist" | "market" | "vault";

/**
 * What a tap means between screens (CLI-03c): hubs, their services, the Gate screen, the entry,
 * leaving an instance, the closing report. A target, never a result: the fixed data answers it
 * (`sandbox/loop/machine.ts`), and CLI-03 hands it to `client/sim` and the chain.
 */
export type LoopIntent =
  /** A building or a service entry of the hub: the service's screen. */
  | { readonly kind: "open service"; readonly service: ServiceId }
  /** The Gate, a building or its service entry: the Gate screen. */
  | { readonly kind: "open gate screen" }
  /** "Leave" on the Gate screen: enter the instance behind gate `gate`. */
  | { readonly kind: "enter gate"; readonly gate: number }
  /** Confirmed on a hub gate's anchor (D-148): leave the instance through it. */
  | { readonly kind: "leave" }
  /** Confirmed (design/11 I-5): travel back to a hub. */
  | { readonly kind: "travel back" }
  /** The closing report read: on to the hub. */
  | { readonly kind: "close report" }
  /** A present adventurer tapped: who it is. */
  | { readonly kind: "inspect adventurer"; readonly adventurer: number }
  /** Back from a service or the Gate screen, or a closed inspection: the hub. */
  | { readonly kind: "back" }
  /** The entry moment skipped: the instance as soon as the entry is drawn. */
  | { readonly kind: "skip entry" }
  /** A debug control of the sandbox: health reaches 0 now (design/02, *Defeated*). */
  | { readonly kind: "defeat now" };
