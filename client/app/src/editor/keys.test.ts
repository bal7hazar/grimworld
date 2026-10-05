import { describe, expect, it } from "vitest";
import { BINDINGS, type KeyLike } from "../input/keys";
import { EDITOR_BINDINGS, editorCommand } from "./keys";

const press = (code: string, key: string, extra: Partial<KeyLike> = {}): KeyLike => ({
  code,
  key,
  shiftKey: false,
  ctrlKey: false,
  metaKey: false,
  altKey: false,
  repeat: false,
  isComposing: false,
  ...extra,
});

/**
 * What each layout types on a physical key (`event.code` → `event.key`), for the keys the tests
 * press. On AZERTY, A/Q, Z/W and M move; the tool letters stay.
 */
const QWERTY: Record<string, string> = { KeyA: "a", KeyQ: "q", KeyW: "w", KeyZ: "z", KeySemicolon: ";", KeyM: "m" };
const AZERTY: Record<string, string> = { KeyA: "q", KeyQ: "a", KeyW: "z", KeyZ: "w", KeySemicolon: "m", KeyM: "," };

/** §3: the letters at the same place with the same label on AZERTY and QWERTY. */
const SAME_PLACE = "BCDEFGHIJKLNOPRSTUVXY".split("");

const toolCodes = EDITOR_BINDINGS.flatMap((b) => b.matches)
  .filter((m) => m.command.kind === "tool")
  .map((m) => m.code!);

describe("the editor's keys (§3, AC-5)", () => {
  it("tool letters are read by position and arm the same tool on AZERTY and QWERTY", () => {
    expect(toolCodes.sort()).toEqual(["KeyB", "KeyG", "KeyI", "KeyN", "KeyT"]);
    for (const code of toolCodes) {
      const letter = code.slice(3).toLowerCase();
      // Both layouts print the same letter there: the same key, the same command.
      const qwerty = editorCommand(press(code, letter));
      const azerty = editorCommand(press(code, letter));
      expect(qwerty).not.toBeNull();
      expect(azerty).toEqual(qwerty);
      // Read by position: a layout that printed another character there arms the same tool.
      expect(editorCommand(press(code, "é"))).toEqual(qwerty);
    }
    expect(editorCommand(press("KeyB", "b"))).toEqual({ kind: "tool", tool: "paint" });
    expect(editorCommand(press("KeyT", "t"))).toEqual({ kind: "tool", tool: "outline" });
  });

  it("every tool letter is one of the keys at the same place with the same label on both layouts", () => {
    for (const code of toolCodes) expect(SAME_PLACE).toContain(code.slice(3));
  });

  it("A, Q, W, Z and M arm nothing on either layout", () => {
    for (const code of ["KeyA", "KeyQ", "KeyW", "KeyZ", "KeyM", "KeySemicolon"]) {
      expect(editorCommand(press(code, QWERTY[code]!)), `QWERTY ${code}`).toBeNull();
      expect(editorCommand(press(code, AZERTY[code]!)), `AZERTY ${code}`).toBeNull();
    }
  });

  it("no editor key by position is a code the game binds or reserves", () => {
    const game = new Set(BINDINGS.flatMap((b) => b.matches).flatMap((m) => (m.code ? [m.code] : [])));
    const editor = EDITOR_BINDINGS.flatMap((b) => b.matches)
      .filter((m) => m.code && m.command.kind === "tool")
      .map((m) => m.code!);
    for (const code of editor) expect(game.has(code), code).toBe(false);
    // J, K and the tool letters: none of the game's.
    for (const code of ["KeyJ", "KeyK"]) expect(game.has(code), code).toBe(false);
  });

  it("Ctrl/Cmd shortcuts are read by character: Ctrl+Z is the key labelled Z on both layouts", () => {
    // QWERTY: Z is KeyZ. AZERTY: the key labelled Z is KeyW.
    expect(editorCommand(press("KeyZ", "z", { ctrlKey: true }))).toEqual({ kind: "undo" });
    expect(editorCommand(press("KeyW", "z", { ctrlKey: true }))).toEqual({ kind: "undo" });
    expect(editorCommand(press("KeyW", "z", { metaKey: true }))).toEqual({ kind: "undo" });
    // AZERTY's KeyZ with Ctrl types w: not undo.
    expect(editorCommand(press("KeyZ", "w", { ctrlKey: true }))).toBeNull();
    expect(editorCommand(press("KeyW", "Z", { ctrlKey: true, shiftKey: true }))).toEqual({
      kind: "redo",
    });
    expect(editorCommand(press("KeyY", "y", { ctrlKey: true }))).toEqual({ kind: "redo" });
    expect(editorCommand(press("KeyS", "s", { ctrlKey: true }))).toEqual({ kind: "save" });
    expect(editorCommand(press("KeyO", "o", { metaKey: true }))).toEqual({ kind: "open" });
    // A plain Z or S does nothing.
    expect(editorCommand(press("KeyW", "z"))).toBeNull();
    expect(editorCommand(press("KeyS", "s"))).toBeNull();
    // AltGr (Ctrl+Alt on Windows) is no shortcut.
    expect(editorCommand(press("KeyS", "s", { ctrlKey: true, altKey: true }))).toBeNull();
  });

  it("symbols are read by character: zoom, brush (AltGr on AZERTY), help", () => {
    expect(editorCommand(press("Equal", "+", { shiftKey: true }))).toEqual({ kind: "zoom", by: 1 });
    // AZERTY's = and - (Digit6).
    expect(editorCommand(press("Slash", "="))).toEqual({ kind: "zoom", by: 1 });
    expect(editorCommand(press("Digit6", "-"))).toEqual({ kind: "zoom", by: -1 });
    expect(editorCommand(press("BracketLeft", "["))).toEqual({ kind: "brush", by: -1 });
    // AZERTY: AltGr+5 types [ (Ctrl+Alt on Windows).
    expect(editorCommand(press("Digit5", "[", { ctrlKey: true, altKey: true }))).toEqual({
      kind: "brush",
      by: -1,
    });
    expect(editorCommand(press("Minus", "]", { altKey: true }))).toEqual({ kind: "brush", by: 1 });
    expect(editorCommand(press("Comma", "?", { shiftKey: true }))).toEqual({ kind: "help" });
    // Ctrl with + is the browser's zoom.
    expect(editorCommand(press("Equal", "+", { ctrlKey: true }))).toBeNull();
  });

  it("0 fits the map, the arrows pan and repeat, other keys ignore their repeat", () => {
    expect(editorCommand(press("Digit0", "à"))).toEqual({ kind: "fit" });
    expect(editorCommand(press("ArrowLeft", "ArrowLeft", { repeat: true }))).toEqual({
      kind: "pan",
      dx: -1,
      dy: 0,
    });
    expect(editorCommand(press("KeyB", "b", { repeat: true }))).toBeNull();
    expect(editorCommand(press("KeyK", "K", { shiftKey: true }))).toEqual({ kind: "layerToggle" });
    expect(editorCommand(press("KeyK", "k"))).toEqual({ kind: "layerFocus" });
    expect(editorCommand(press("KeyB", "b", { isComposing: true }))).toBeNull();
  });
});
