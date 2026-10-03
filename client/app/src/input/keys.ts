import type { Facing } from "../render/view";

/**
 * Keys to commands (CLI-03k): the desktop's keyboard for zones and hubs, one table (`BINDINGS`)
 * that the key map reads and the key help lists. A command is not a result: the screen turns it
 * into the intent of the tap it stands for (a map `Intent` through the controller, or a
 * `LoopIntent` through the screen's dispatch). No DOM, React or PixiJS here.
 *
 * Positions are read from `event.code` (the physical key: an AZERTY keyboard gets the same block
 * and its digits without Shift), symbols from `event.key`. A digit by position yields to a zoom
 * character: where the key printed `-` is `Digit6` (AZERTY), it zooms out, not service 6. A key held with Ctrl, Meta or Alt is
 * the browser's; an auto-repeat or a composition is nothing (one press, one hex).
 */

/** One hex in a direction of the grid, or the facing side's upper or lower hex (↑ / ↓). */
export type StepKey = { readonly direction: Facing } | { readonly vertical: "up" | "down" };

export type KeyCommand =
  | ({ readonly kind: "step" } & StepKey)
  | { readonly kind: "cycle"; readonly by: 1 | -1 }
  /** Enter on the selected place. */
  | { readonly kind: "go" }
  /** A button of a hub's service row, from 0. */
  | { readonly kind: "service"; readonly index: number }
  /** The Leave control of a zone (D-148). */
  | { readonly kind: "leave" }
  | { readonly kind: "escape" }
  /** One wheel notch in (1) or out (−1), around the map's centre. */
  | { readonly kind: "zoom"; readonly by: 1 | -1 }
  | { readonly kind: "recentre" }
  | { readonly kind: "help" };

/** What the key map reads of a `KeyboardEvent`. */
export interface KeyLike {
  readonly code: string;
  readonly key: string;
  readonly shiftKey: boolean;
  readonly ctrlKey: boolean;
  readonly metaKey: boolean;
  readonly altKey: boolean;
  readonly repeat: boolean;
  readonly isComposing: boolean;
}

/** The loop's screens; a room outside the loop (`?fixture=`) is an instance. */
export type KeyScreen = "hub" | "instance" | "service" | "gate" | "entry" | "report";

/**
 * One key of a binding: by physical key (`code`, Shift as `shift` says) or by character (`key`,
 * Shift ignored: it is part of the character). `command` null: reserved for a later lot.
 */
export interface KeyMatch {
  readonly code?: string;
  readonly key?: string;
  readonly shift?: boolean;
  readonly command: KeyCommand | null;
}

export interface Binding {
  /** The keys as the help shows them. */
  readonly keys: string;
  readonly label: string;
  readonly screens: readonly KeyScreen[];
  readonly matches: readonly KeyMatch[];
  /** Reserved for a later lot (design/11 *Desktop*'s combat keys): bound to nothing yet. */
  readonly reserved?: boolean;
}

const MAP: readonly KeyScreen[] = ["hub", "instance"];
const EVERY: readonly KeyScreen[] = ["hub", "instance", "service", "gate", "entry", "report"];

const step = (code: string, direction: Facing, keys: string, label: string): Binding => ({
  keys,
  label,
  screens: MAP,
  matches: [{ code, command: { kind: "step", direction } }],
});

const digits = (from: number, to: number) =>
  Array.from({ length: to - from + 1 }, (_, i) => from + i);

/**
 * The one table. The direction ring (§2, decided, reversible by one row): `Q W E / A S D` read as
 * a ring around its centre, each key toward the grid's direction nearest its angle.
 */
export const BINDINGS: readonly Binding[] = [
  step("KeyQ", 3, "Q", "Step West"),
  step("KeyW", 2, "W", "Step North-West"),
  step("KeyE", 1, "E", "Step North-East"),
  step("KeyD", 0, "D", "Step East"),
  step("KeyS", 5, "S", "Step South-East"),
  step("KeyA", 4, "A", "Step South-West"),
  {
    keys: "← →",
    label: "Step West, East",
    screens: MAP,
    matches: [
      { code: "ArrowLeft", command: { kind: "step", direction: 3 } },
      { code: "ArrowRight", command: { kind: "step", direction: 0 } },
    ],
  },
  {
    keys: "↑ ↓",
    label: "Step up, down, on the side faced",
    screens: MAP,
    matches: [
      { code: "ArrowUp", command: { kind: "step", vertical: "up" } },
      { code: "ArrowDown", command: { kind: "step", vertical: "down" } },
    ],
  },
  {
    keys: "F / Shift+F",
    label: "Select the next, previous place",
    screens: MAP,
    matches: [
      { code: "KeyF", command: { kind: "cycle", by: 1 } },
      { code: "KeyF", shift: true, command: { kind: "cycle", by: -1 } },
    ],
  },
  {
    keys: "Enter",
    label: "Go to the selected place",
    screens: MAP,
    matches: [
      { code: "Enter", command: { kind: "go" } },
      { code: "NumpadEnter", command: { kind: "go" } },
    ],
  },
  {
    keys: "1–9",
    label: "Open a service, in the row's order",
    screens: ["hub"],
    matches: digits(1, 9).flatMap((n) => [
      { code: `Digit${n}`, command: { kind: "service", index: n - 1 } as const },
      { code: `Numpad${n}`, command: { kind: "service", index: n - 1 } as const },
    ]),
  },
  {
    keys: "L",
    label: "Leave by the gate under you",
    screens: ["instance"],
    matches: [{ code: "KeyL", command: { kind: "leave" } }],
  },
  {
    keys: "Esc",
    label: "Close, cancel the walk, clear, back",
    screens: EVERY,
    matches: [{ code: "Escape", command: { kind: "escape" } }],
  },
  {
    keys: "0",
    label: "Back to the adventurer",
    screens: MAP,
    matches: [
      { code: "Digit0", command: { kind: "recentre" } },
      { code: "Numpad0", command: { kind: "recentre" } },
    ],
  },
  {
    keys: "+ / −",
    label: "Zoom in, out",
    screens: MAP,
    matches: [
      { key: "+", command: { kind: "zoom", by: 1 } },
      { key: "=", command: { kind: "zoom", by: 1 } },
      { code: "NumpadAdd", command: { kind: "zoom", by: 1 } },
      { key: "-", command: { kind: "zoom", by: -1 } },
      { code: "NumpadSubtract", command: { kind: "zoom", by: -1 } },
    ],
  },
  {
    keys: "?",
    label: "These keys",
    screens: EVERY,
    matches: [{ key: "?", command: { kind: "help" } }],
  },
  // design/11 *Desktop*'s combat keys: the HUD lots (CLI-05, CLI-08) bind them in this table.
  {
    keys: "1–8",
    label: "Skills",
    screens: ["instance"],
    reserved: true,
    matches: digits(1, 8).map((n) => ({ code: `Digit${n}`, command: null })),
  },
  {
    keys: "Z X C V",
    label: "Belt",
    screens: ["instance"],
    reserved: true,
    matches: ["KeyZ", "KeyX", "KeyC", "KeyV"].map((code) => ({ code, command: null })),
  },
  {
    keys: "Space",
    label: "Wait",
    screens: ["instance"],
    reserved: true,
    matches: [{ code: "Space", command: null }],
  },
  {
    keys: "R",
    label: "Turn",
    screens: ["instance"],
    reserved: true,
    matches: [{ code: "KeyR", command: null }],
  },
];

/** The characters that zoom: they win over a digit read by position (AZERTY's `-` is `Digit6`). */
const ZOOM_CHARS = ["+", "-", "="];

function matches(match: KeyMatch, event: KeyLike): boolean {
  if (match.key !== undefined) return match.key === event.key;
  if (match.code?.startsWith("Digit") && ZOOM_CHARS.includes(event.key)) return false;
  return match.code === event.code && event.shiftKey === (match.shift ?? false);
}

/** The command of a key press on a screen, or null: the key is left to the page. */
export function keyCommand(event: KeyLike, screen: KeyScreen): KeyCommand | null {
  if (event.ctrlKey || event.metaKey || event.altKey) return null;
  if (event.repeat || event.isComposing) return null;
  for (const binding of BINDINGS) {
    if (!binding.screens.includes(screen)) continue;
    for (const match of binding.matches) {
      if (matches(match, event)) return match.command;
    }
  }
  return null;
}

/** The bindings the help lists on a screen, the reserved ones last. */
export function bindingsOf(screen: KeyScreen): Binding[] {
  const on = BINDINGS.filter((b) => b.screens.includes(screen));
  return [...on.filter((b) => !b.reserved), ...on.filter((b) => b.reserved)];
}

/**
 * ↑ / ↓ on a pointy-top grid, which has no straight up or down: the upper or lower hex on the side
 * the adventurer faces (East, North-East, South-East: the East side; the others: the West side).
 */
export function verticalDirection(facing: Facing, vertical: "up" | "down"): Facing {
  const east = facing === 0 || facing === 1 || facing === 5;
  if (vertical === "up") return east ? 1 : 2;
  return east ? 5 : 4;
}
