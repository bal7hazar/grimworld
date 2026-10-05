import { type ReactNode, useEffect, useMemo, useReducer, useRef } from "react";
import type { Kind } from "./kinds";
import { CATEGORIES, INITIAL_PALETTE, type PaletteState, kindsMatching, paletteStep } from "./menu";
import { type ThumbLookup, drawThumb, thumbOf } from "./thumbs";
import "./palette.css";

/** A thumbnail's box, in CSS px. */
export const THUMB_BOX = 48;

export interface PaletteProps {
  /** The atlas's frames, or null without an atlas (labels only). */
  readonly thumbs: ThumbLookup | null;
  /** Called with the selected kind, or null when the selection is cleared. */
  readonly onSelect: (kind: Kind | null) => void;
  readonly initial?: PaletteState;
}

/**
 * The palette (CLI-09e): one menu per category (props, buildings, NPCs, bridges), a filter, and a
 * grid of kinds with their thumbnails; one kind selected at a time. Part 2 places it in the
 * editor's side panel and places the selected kind on the map.
 */
export function Palette({ thumbs, onSelect, initial = INITIAL_PALETTE }: PaletteProps): ReactNode {
  const [state, dispatch] = useReducer(
    (s: PaletteState, a: Parameters<typeof paletteStep>[1]) => paletteStep(s, a),
    initial,
  );
  const shown = kindsMatching(state.category, state.filter);
  const choose = (kind: Kind) => {
    const next = paletteStep(state, { type: "select", id: kind.id });
    dispatch({ type: "select", id: kind.id });
    onSelect(next.selected === null ? null : kind);
  };
  return (
    <div className="ed-palette" data-palette="">
      <div className="ed-palette-menus">
        {CATEGORIES.map(({ id, label }) => (
          <button
            key={id}
            type="button"
            aria-pressed={state.category === id}
            data-category={id}
            onClick={() => dispatch({ type: "open", category: id })}
          >
            {label}
          </button>
        ))}
      </div>
      <input
        type="search"
        placeholder="Filter"
        aria-label="Filter the kinds"
        value={state.filter}
        onChange={(e) => dispatch({ type: "filter", filter: e.target.value })}
      />
      <div className="ed-palette-grid" data-menu={state.category}>
        {shown.map((kind) => (
          <button
            key={kind.id}
            type="button"
            aria-pressed={state.selected === kind.id}
            data-kind={kind.id}
            title={kind.label}
            onClick={() => choose(kind)}
          >
            <Thumb kind={kind} thumbs={thumbs} />
            <span>{kind.label}</span>
          </button>
        ))}
        {shown.length === 0 && <p className="ed-dim">No {state.category} matches.</p>}
      </div>
    </div>
  );
}

/** A kind's frame from the atlas on a small canvas, or nothing without one. */
function Thumb({ kind, thumbs }: { kind: Kind; thumbs: ThumbLookup | null }): ReactNode {
  const canvas = useRef<HTMLCanvasElement>(null);
  const { sprite, animation, frame } = thumbOf(kind);
  const art = useMemo(
    () => thumbs?.(sprite, animation, frame) ?? null,
    [thumbs, sprite, animation, frame],
  );
  // Drawn again only when the frame changes, not on every render of the palette.
  useEffect(() => {
    const ctx = canvas.current?.getContext("2d");
    if (ctx && art) drawThumb(ctx, art, THUMB_BOX);
  }, [art]);
  if (!art) return <span className="ed-palette-none" aria-hidden="true" />;
  return <canvas ref={canvas} width={THUMB_BOX} height={THUMB_BOX} aria-hidden="true" />;
}
