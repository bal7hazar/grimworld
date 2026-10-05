import { loadMap, saveMap } from "./file";
import { fitted } from "./fit";
import { type MapDocument, type MapKind, cloneMap } from "./model";
import { tally, validate } from "./validate";

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
  /** Painted hexes (D-216); absent in an entry written by CLI-09a. */
  readonly hexes?: number;
  /** The fitted chunk set's size, null before a fit; absent in an entry written by CLI-09a. */
  readonly chunks?: number | null;
  readonly location: number;
  /** The validation's counts when it was written (CLI-09b); absent in an older entry. */
  readonly problems?: { readonly errors: number; readonly warnings: number };
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

  /**
   * Writes a draft; false when the storage refused it (full, blocked). `problems` are the
   * validation's counts, when the caller already holds them (the editor's screen).
   */
  put(
    id: string,
    doc: MapDocument,
    now = new Date(),
    problems: { readonly errors: number; readonly warnings: number } = tally(validate(doc)),
  ): boolean {
    const fit = fitted(doc);
    const entry: DraftEntry = {
      id,
      kind: doc.meta.kind,
      name: doc.meta.name,
      hexes: doc.hexes.size,
      chunks: typeof fit === "string" ? null : fit.chunks,
      location: doc.meta.location,
      problems,
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

  /** A draft's map, or why it cannot be read. A format 1 draft is converted (`loadMap`). */
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

  /** "Duplicate" on the map list: a copy under a new id; why it failed, or null. */
  duplicate(id: string, newId = newDraftId()): string | null {
    const doc = this.get(id);
    if (typeof doc === "string") return doc;
    return this.put(newId, cloneMap(doc))
      ? null
      : "Not duplicated: this browser refused the draft.";
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

/** What the draft writer needs of the window's timers. */
export interface Timers {
  setTimeout(run: () => void, ms: number): number;
  clearTimeout(id: number): void;
}

/**
 * The draft written a moment after each change (§6), and at once when the editor's screen goes
 * away or the tab is closed (`flush`, on unmount and `pagehide`): a closed tab loses nothing (O-5).
 */
export class DraftWriter {
  private timer: number | null = null;

  constructor(
    private readonly write: () => void,
    private readonly delay: number,
    private readonly timers: Timers,
  ) {}

  get pending(): boolean {
    return this.timer !== null;
  }

  /** A change: the write is (re)scheduled. */
  changed(): void {
    if (this.timer !== null) this.timers.clearTimeout(this.timer);
    this.timer = this.timers.setTimeout(() => {
      this.timer = null;
      this.write();
    }, this.delay);
  }

  /** The pending write, now; nothing when none is pending. */
  flush(): void {
    if (this.timer !== null) this.now();
  }

  /** A write now (Save), the pending one cancelled. */
  now(): void {
    if (this.timer !== null) this.timers.clearTimeout(this.timer);
    this.timer = null;
    this.write();
  }
}
