import { loadMap, saveMap } from "./file";
import type { MapDocument, MapKind } from "./model";

/**
 * Drafts (O-5, decided): the open map kept in this browser's local storage after each change, so
 * that a closed tab loses nothing. One browser's convenience: every read and write is guarded, and
 * the editor works without the storage.
 */

/** What the map list shows of a draft. */
export interface DraftEntry {
  readonly id: string;
  readonly kind: MapKind;
  readonly name: string;
  readonly width: number;
  readonly height: number;
  readonly location: number;
  /** When it was last written, ISO 8601. */
  readonly edited: string;
}

/** What the drafts need of `localStorage`. */
export type DraftStorage = Pick<Storage, "getItem" | "setItem" | "removeItem">;

const INDEX = "grimworld.editor.drafts";
const DRAFT = (id: string) => `grimworld.editor.draft.${id}`;

/** The browser's storage, or null when reading it throws (a private window, a blocked site). */
export function browserStorage(): DraftStorage | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

export class Drafts {
  constructor(private readonly storage: DraftStorage | null) {}

  /** The drafts, last edited first; none when the storage cannot be read. */
  list(): DraftEntry[] {
    try {
      const raw = this.storage?.getItem(INDEX);
      const entries = raw ? (JSON.parse(raw) as unknown) : [];
      if (!Array.isArray(entries)) return [];
      return (entries as DraftEntry[])
        .filter((e) => typeof e?.id === "string")
        .sort((a, b) => b.edited.localeCompare(a.edited));
    } catch {
      return [];
    }
  }

  /** Writes a draft; false when the storage refused it (full, blocked). */
  put(id: string, doc: MapDocument, now = new Date()): boolean {
    const entry: DraftEntry = {
      id,
      kind: doc.meta.kind,
      name: doc.meta.name,
      width: doc.meta.width,
      height: doc.meta.height,
      location: doc.meta.location,
      edited: now.toISOString(),
    };
    try {
      if (!this.storage) return false;
      this.storage.setItem(DRAFT(id), saveMap(doc));
      this.storage.setItem(
        INDEX,
        JSON.stringify([entry, ...this.list().filter((e) => e.id !== id)]),
      );
      return true;
    } catch {
      return false;
    }
  }

  /** A draft's map, or why it cannot be read. */
  get(id: string): MapDocument | string {
    let text: string | null | undefined;
    try {
      text = this.storage?.getItem(DRAFT(id));
    } catch {
      return "This browser's storage cannot be read.";
    }
    if (!text) return "The draft is gone from this browser.";
    const read = loadMap(text);
    return "problem" in read ? read.problem : read.doc;
  }

  /** The draft's text as saved, for a download from the list. */
  text(id: string): string | null {
    try {
      return this.storage?.getItem(DRAFT(id)) ?? null;
    } catch {
      return null;
    }
  }

  forget(id: string): void {
    try {
      this.storage?.removeItem(DRAFT(id));
      this.storage?.setItem(INDEX, JSON.stringify(this.list().filter((e) => e.id !== id)));
    } catch {
      // Nothing to do: the storage is gone.
    }
  }
}

/** A new draft's id: unique in this browser. */
export function newDraftId(now = Date.now(), salt = Math.random()): string {
  return `${now.toString(36)}-${Math.floor(salt * 36 ** 4).toString(36)}`;
}
