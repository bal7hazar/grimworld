import { type Change, type MapDocument, apply } from "./model";

/** Undo depth (O-7, decided): 200 steps, in memory, lost on reload. */
export const UNDO_DEPTH = 200;

/**
 * Undo and redo (§3): one step is one stroke (press to release), a fill, or one command. A step
 * is the hexes it changed, before and after, so that a 225 × 225 map keeps 200 steps cheaply.
 * Past `depth` steps the oldest is dropped.
 */
export class History {
  private readonly done: (readonly Change[])[] = [];
  private readonly undone: (readonly Change[])[] = [];
  /** The stroke being drawn: its changes, merged on release. */
  private open: Change[] | null = null;

  constructor(private readonly depth = UNDO_DEPTH) {}

  /** A stroke starts: what is applied until `end` is one step. */
  begin(): void {
    this.open ??= [];
  }

  /** Applies changes to the document and records them (in the open stroke, or as one step). */
  record(doc: MapDocument, changes: readonly Change[]): void {
    if (changes.length === 0) return;
    apply(doc, changes);
    if (this.open) {
      this.open.push(...changes);
      return;
    }
    this.push(changes);
  }

  /** The stroke ends: one step, if it changed anything. */
  end(): void {
    const open = this.open;
    this.open = null;
    if (open && open.length > 0) this.push(open);
  }

  get stroking(): boolean {
    return this.open !== null;
  }

  private push(changes: readonly Change[]): void {
    this.done.push(changes);
    if (this.done.length > this.depth) this.done.splice(0, this.done.length - this.depth);
    this.undone.length = 0;
  }

  canUndo(): boolean {
    return this.done.length > 0;
  }

  canRedo(): boolean {
    return this.undone.length > 0;
  }

  /** The number of steps that can be undone. */
  get steps(): number {
    return this.done.length;
  }

  /** Undoes the last step (a stroke in progress ends first). True when something was undone. */
  undo(doc: MapDocument): boolean {
    this.end();
    const step = this.done.pop();
    if (!step) return false;
    apply(doc, step, true);
    this.undone.push(step);
    return true;
  }

  redo(doc: MapDocument): boolean {
    this.end();
    const step = this.undone.pop();
    if (!step) return false;
    apply(doc, step);
    this.done.push(step);
    return true;
  }

  clear(): void {
    this.done.length = 0;
    this.undone.length = 0;
    this.open = null;
  }
}
