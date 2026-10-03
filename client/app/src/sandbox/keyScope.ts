import { type CSSProperties, createContext, useContext, useEffect, useRef } from "react";
import { type KeyCommand, type KeyLike, type KeyScreen, keyCommand } from "../input/keys";
import type { Tile } from "../render/view";
import type { SandboxController } from "./controller";

/**
 * Who hears the keyboard (CLI-03k): one listener on the document, and a stack of layers. The
 * screen pushes its layer; an open dialog or the key help pushes one on top; only the top layer
 * receives the key, read with its screen's bindings. A layer that handles the key says so, and the
 * page's default is prevented; any other key is left to the page.
 */

export interface KeyLayer {
  /** Whose bindings the key is read with. */
  readonly screen: KeyScreen;
  /** The key's command on that screen (null: none), and the raw key. True when handled. */
  handle(command: KeyCommand | null, event: KeyLike): boolean;
}

export class KeyScope {
  private readonly layers: KeyLayer[] = [];

  /** Puts a layer on top; the returned function takes it off, wherever it is then. */
  push(layer: KeyLayer): () => void {
    this.layers.push(layer);
    return () => {
      const i = this.layers.lastIndexOf(layer);
      if (i >= 0) this.layers.splice(i, 1);
    };
  }

  top(): KeyLayer | null {
    return this.layers.at(-1) ?? null;
  }

  /** A key pressed: to the top layer only. True when it was handled. */
  press(event: KeyLike): boolean {
    const top = this.top();
    if (!top) return false;
    return top.handle(keyCommand(event, top.screen), event);
  }
}

/** What `ignoredTarget` reads of the element that has the focus. */
export interface TargetLike {
  readonly tagName?: string;
  readonly isContentEditable?: boolean;
}

/**
 * Whether a key is left to the page because of where it was typed: a text field, a list or an
 * editable element takes every key; a button or a link takes Enter (the browser presses it).
 */
export function ignoredTarget(target: TargetLike | null, event: Pick<KeyLike, "code">): boolean {
  if (!target) return false;
  const tag = (target.tagName ?? "").toUpperCase();
  if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return true;
  if (target.isContentEditable) return true;
  const enter = event.code === "Enter" || event.code === "NumpadEnter";
  return enter && (tag === "BUTTON" || tag === "A");
}

/** The page's one scope. */
export const keyScope = new KeyScope();

let listeners = 0;
let removeListener: (() => void) | null = null;

/**
 * Listens to the document's keys for `keyScope` (the loop, or a room outside it). Counted: two
 * installs share one listener; the last uninstall removes it.
 */
export function installKeys(target: Document = document): () => void {
  if (listeners === 0) {
    const onKey = (event: KeyboardEvent) => {
      if (event.defaultPrevented) return;
      if (ignoredTarget(event.target as Element | null, event)) return;
      if (keyScope.press(event)) event.preventDefault();
    };
    target.addEventListener("keydown", onKey);
    removeListener = () => target.removeEventListener("keydown", onKey);
  }
  listeners += 1;
  let removed = false;
  return () => {
    if (removed) return;
    removed = true;
    listeners -= 1;
    if (listeners === 0) {
      removeListener?.();
      removeListener = null;
    }
  };
}

/** The loop's key help, opened or closed by `?` from any screen (null outside the loop). */
export const KeyHelpToggle = createContext<(() => void) | null>(null);

/**
 * A screen's or a dialog's layer, on top while mounted and `active`. `?` toggles the loop's key
 * help before the layer sees it.
 */
export function useKeyLayer(
  screen: KeyScreen,
  handle: (command: KeyCommand | null, event: KeyLike) => boolean,
  active = true,
): void {
  const help = useContext(KeyHelpToggle);
  const latest = useRef({ handle, help });
  latest.current = { handle, help };
  useEffect(() => {
    if (!active) return;
    return keyScope.push({
      screen,
      handle: (command, event) => {
        const { handle: own, help: toggle } = latest.current;
        if (command?.kind === "help" && toggle) {
          toggle();
          return true;
        }
        return own(command, event);
      },
    });
  }, [screen, active]);
}

/**
 * A screen's root, focused when the screen opens (`tabIndex={-1}`, no ring: it is no control), so
 * that no button of the screen before sits armed under Enter.
 */
export function useScreenFocus<T extends HTMLElement = HTMLDivElement>() {
  const root = useRef<T>(null);
  useEffect(() => {
    root.current?.focus({ preventScroll: true });
  }, []);
  return root;
}

/** Whether a tile's centre is outside the map's box (or within `margin` px of its edge). */
export function offScreen(
  controller: SandboxController,
  tile: Tile,
  box: HTMLElement | null,
  margin = 32,
): boolean {
  if (!box) return false;
  const { x, y } = controller.tileOnScreen(tile);
  return (
    x < margin || y < margin || x > box.clientWidth - margin || y > box.clientHeight - margin
  );
}

/** The keyboard's marks: the focus ring's colours live in `chrome.css` (`.gw-key-marker`). */
export const keyUi: Record<string, CSSProperties> = {
  /** A screen's root takes the focus but shows no ring. */
  root: { outline: "none" },
  /** The ring on a selected place's door or gate's hex, placed after each frame. */
  marker: {
    position: "absolute",
    left: 0,
    top: 0,
    borderRadius: "50%",
    visibility: "hidden",
    pointerEvents: "none",
  },
  /** Read by a screen reader, not shown. */
  hidden: {
    position: "absolute",
    width: 1,
    height: 1,
    overflow: "hidden",
    clipPath: "inset(50%)",
    whiteSpace: "nowrap",
  },
};
