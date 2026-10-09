import type { KeyLike } from "../input/keys";

/**
 * The editor's keys in edit mode (brief §3), one table that the key map reads and the help lists.
 * No DOM, React or PixiJS here.
 *
 * - Tool letters are read by **position** (`event.code`), among the keys that sit at the same place
 *   and carry the same letter on AZERTY and QWERTY, so the mnemonic holds on both; A, Q, W, Z and M
 *   move between the layouts and arm nothing. None is a code the game binds or reserves.
 * - Symbols (`+ − = ? [ ]`) are read by **character** (`event.key`), as CLI-03k reads its zoom.
 *   On AZERTY `[` and `]` need AltGr (Ctrl+Alt on Windows): a symbol is read whatever the
 *   modifiers.
 * - Shortcuts with Ctrl or Cmd are read by **character**, as browsers do: Ctrl+Z is the key
 *   labelled Z on both layouts.
 * - One action per press: auto-repeat is ignored but for the arrows, which pan.
 */

export type EditorTool =
  "paint" | "erase" | "fill" | "pick" | "outline" | "select" | "place" | "footprint";

export type EditorCommand =
  | { readonly kind: "tool"; readonly tool: EditorTool }
  | { readonly kind: "pan"; readonly dx: -1 | 0 | 1; readonly dy: -1 | 0 | 1 }
  | { readonly kind: "zoom"; readonly by: 1 | -1 }
  | { readonly kind: "fit" }
  | { readonly kind: "fitChunks" }
  | { readonly kind: "nudge"; readonly dx: -1 | 0 | 1; readonly dy: -1 | 0 | 1 }
  | { readonly kind: "brush"; readonly by: 1 | -1 }
  | { readonly kind: "undo" }
  | { readonly kind: "redo" }
  | { readonly kind: "save" }
  | { readonly kind: "open" }
  | { readonly kind: "grid" }
  | { readonly kind: "layerFocus" }
  | { readonly kind: "layerToggle" }
  | { readonly kind: "escape" }
  | { readonly kind: "help" }
  | { readonly kind: "delete" }
  | { readonly kind: "cut" }
  | { readonly kind: "copy" }
  | { readonly kind: "paste" }
  | { readonly kind: "mirror" }
  | { readonly kind: "turn" }
  | { readonly kind: "footprint" }
  | { readonly kind: "validate" }
  | { readonly kind: "walk" };

/** One key: by position (`code`, Shift as `shift` says), by character (`key`), with Ctrl/Cmd or not. */
export interface EditorMatch {
  readonly code?: string;
  readonly key?: string;
  readonly shift?: boolean;
  /** Ctrl (Cmd on macOS) held: a shortcut, read by character. */
  readonly mod?: boolean;
  /** Repeats while held (the arrows). */
  readonly repeat?: boolean;
  readonly command: EditorCommand;
}

export interface EditorBinding {
  readonly keys: string;
  readonly label: string;
  readonly matches: readonly EditorMatch[];
}

const tool = (code: string, t: EditorTool, keys: string, label: string): EditorBinding => ({
  keys,
  label,
  matches: [{ code, command: { kind: "tool", tool: t } }],
});

const arrow = (code: string, dx: -1 | 0 | 1, dy: -1 | 0 | 1): EditorMatch => ({
  code,
  repeat: true,
  command: { kind: "pan", dx, dy },
});

/** Shift + an arrow nudges the chunk origin one hex that way on screen: `x` grows West, `y` North. */
const nudgeArrow = (code: string, dx: -1 | 0 | 1, dy: -1 | 0 | 1): EditorMatch => ({
  code,
  shift: true,
  repeat: true,
  command: { kind: "nudge", dx, dy },
});

/**
 * The one table (CLI-09a's rows of §3, CLI-09a2's Fit chunks and nudge, CLI-09b's Select, Place,
 * Cut, Copy, Paste, Delete, Mirror, Validate and Walk).
 */
export const EDITOR_BINDINGS: readonly EditorBinding[] = [
  tool("KeyB", "paint", "B", "Paint"),
  tool("KeyN", "erase", "N", "Erase"),
  tool("KeyG", "fill", "G", "Fill"),
  tool("KeyI", "pick", "I", "Pick"),
  tool("KeyU", "select", "U", "Select; drag a selected object to move it"),
  tool("KeyO", "place", "O", "Place the palette's object"),
  tool("KeyT", "outline", "T", "Outline (zones)"),
  // Not a tool letter: every letter at the same place on both layouts is a tool's or the game's.
  {
    keys: "F",
    label: "Footprint: paint or remove the selected pack building's hexes (its door stays)",
    matches: [{ code: "KeyF", command: { kind: "footprint" } }],
  },
  {
    keys: "← → ↑ ↓",
    label: "Pan",
    matches: [
      arrow("ArrowLeft", -1, 0),
      arrow("ArrowRight", 1, 0),
      arrow("ArrowUp", 0, -1),
      arrow("ArrowDown", 0, 1),
    ],
  },
  {
    keys: "+ / −",
    label: "Zoom in, out",
    matches: [
      { key: "+", command: { kind: "zoom", by: 1 } },
      { key: "=", command: { kind: "zoom", by: 1 } },
      { code: "NumpadAdd", command: { kind: "zoom", by: 1 } },
      { key: "-", command: { kind: "zoom", by: -1 } },
      { code: "NumpadSubtract", command: { kind: "zoom", by: -1 } },
    ],
  },
  {
    keys: "0",
    label: "Fit the painted map in the view",
    matches: [
      { code: "Digit0", command: { kind: "fit" } },
      { code: "Numpad0", command: { kind: "fit" } },
    ],
  },
  {
    keys: "Shift+0",
    label: "Fit chunks: the chunk grid with the fewest chunks (D-216)",
    matches: [{ code: "Digit0", shift: true, command: { kind: "fitChunks" } }],
  },
  {
    keys: "Shift+← → ↑ ↓",
    label: "Nudge the chunk origin by one hex",
    matches: [
      nudgeArrow("ArrowLeft", 1, 0),
      nudgeArrow("ArrowRight", -1, 0),
      nudgeArrow("ArrowUp", 0, 1),
      nudgeArrow("ArrowDown", 0, -1),
    ],
  },
  {
    keys: "[ / ]",
    label: "Brush smaller, larger (also Shift+wheel)",
    matches: [
      { key: "[", command: { kind: "brush", by: -1 } },
      { key: "]", command: { kind: "brush", by: 1 } },
    ],
  },
  {
    keys: "Ctrl/Cmd+Z",
    label: "Undo",
    matches: [{ key: "z", mod: true, command: { kind: "undo" } }],
  },
  {
    keys: "Ctrl/Cmd+Shift+Z, Ctrl+Y",
    label: "Redo",
    matches: [
      { key: "z", mod: true, shift: true, command: { kind: "redo" } },
      { key: "y", mod: true, command: { kind: "redo" } },
    ],
  },
  {
    keys: "Ctrl/Cmd+S",
    label: "Save: the draft, and download the file",
    matches: [{ key: "s", mod: true, command: { kind: "save" } }],
  },
  {
    keys: "Ctrl/Cmd+O",
    label: "Open a file",
    matches: [{ key: "o", mod: true, command: { kind: "open" } }],
  },
  {
    keys: "Ctrl/Cmd+X, C, V",
    label: "Cut, copy, paste the selection (a paste follows the pointer until a click)",
    matches: [
      { key: "x", mod: true, command: { kind: "cut" } },
      { key: "c", mod: true, command: { kind: "copy" } },
      { key: "v", mod: true, command: { kind: "paste" } },
    ],
  },
  {
    keys: "Delete, Backspace",
    label: "Delete the selection: objects removed, hexes unpainted",
    matches: [
      { code: "Delete", command: { kind: "delete" } },
      { code: "Backspace", command: { kind: "delete" } },
    ],
  },
  {
    keys: "H",
    label: "Mirror the selected buildings and props (towns)",
    matches: [{ code: "KeyH", command: { kind: "mirror" } }],
  },
  {
    keys: "R",
    label:
      "Turn the selected characters and cannons; next variant of a prop, next door of a building",
    matches: [{ code: "KeyR", command: { kind: "turn" } }],
  },
  {
    keys: "Y",
    label: "Validate now and open the panel",
    matches: [{ code: "KeyY", command: { kind: "validate" } }],
  },
  {
    keys: "P",
    label: "Walk the map (the preview); P again to edit",
    matches: [{ code: "KeyP", command: { kind: "walk" } }],
  },
  {
    keys: "J",
    label: "Toggle the grid",
    matches: [{ code: "KeyJ", command: { kind: "grid" } }],
  },
  {
    keys: "K / Shift+K",
    label: "Next layer in the layers bar; toggle it",
    matches: [
      { code: "KeyK", command: { kind: "layerFocus" } },
      { code: "KeyK", shift: true, command: { kind: "layerToggle" } },
    ],
  },
  {
    keys: "Esc",
    label: "End a stroke, a paste, a box; clear the selection; close a dialog",
    matches: [{ code: "Escape", command: { kind: "escape" } }],
  },
  {
    keys: "?",
    label: "These keys",
    matches: [{ key: "?", command: { kind: "help" } }],
  },
];

/** The keys typed by character that a shortcut reads lower-case (Shift gives `Z`). */
const lower = (key: string) => (key.length === 1 ? key.toLowerCase() : key);

function matches(match: EditorMatch, event: KeyLike): boolean {
  const mod = event.ctrlKey || event.metaKey;
  if (match.mod) {
    // AltGr is Ctrl+Alt on Windows: never a shortcut.
    if (!mod || event.altKey) return false;
    return lower(event.key) === match.key && event.shiftKey === (match.shift ?? false);
  }
  // A symbol: with AltGr (Ctrl+Alt) too, but Ctrl or Cmd alone is the browser's (its zoom).
  if (match.key !== undefined) return event.key === match.key && !(mod && !event.altKey);
  if (mod || event.altKey) return false;
  return match.code === event.code && event.shiftKey === (match.shift ?? false);
}

/** The command of a key press in edit mode, or null: the key is left to the page. */
export function editorCommand(event: KeyLike): EditorCommand | null {
  if (event.isComposing) return null;
  for (const binding of EDITOR_BINDINGS) {
    for (const match of binding.matches) {
      if (!matches(match, event)) continue;
      if (event.repeat && !match.repeat) return null;
      return match.command;
    }
  }
  return null;
}
