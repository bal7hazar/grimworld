import { useEffect, useMemo, useRef, useState } from "react";
import { type KeyLike, bindingsOf, keyCommand } from "../input/keys";
import type { Tile } from "../render/view";
import { keyScope } from "../sandbox/keyScope";
import { type MapDocument, isZone } from "./model";
import { WalkCanvas } from "./walk";
import { type Frame, toFrame, walkWorld } from "./walkWorld";

/** Where the walk starts (§2.8): the entry (a zone) or the arrival (a town), a gate, the selected hex. */
export interface WalkStart {
  readonly label: string;
  readonly tile: Tile;
}

/**
 * The preview walk (CLI-09b, brief §2.8): the game's view of the map, the panels folded to a thin
 * bar. Only the game's `BINDINGS` are live (the instance screen's set, or the hub screen's in a
 * town), plus `P` to leave. The walk changes nothing in the map.
 */
export function WalkScreen({
  doc,
  frame,
  starts,
  onLeave,
}: {
  doc: MapDocument;
  frame: Frame;
  starts: readonly WalkStart[];
  onLeave: () => void;
}) {
  const host = useRef<HTMLDivElement>(null);
  const canvas = useRef<WalkCanvas | null>(null);
  const [start, setStart] = useState(0);
  const [fog, setFog] = useState(false);
  const [said, setSaid] = useState("");
  const [help, setHelp] = useState(false);
  const zone = isZone(doc);
  const screen = zone ? "instance" : "hub";
  const from = starts[start] ?? starts[0];
  const world = useMemo(
    () => (from ? walkWorld(doc, frame, { start: from.tile, fog }) : null),
    [doc, frame, from, fog],
  );

  useEffect(() => {
    const element = host.current;
    if (!element || !world) return;
    let gone = false;
    let mounted: WalkCanvas | null = null;
    void WalkCanvas.mount(element, world, fog, () =>
      setSaid(mounted?.session.state.said ?? ""),
    ).then((made) => {
      if (gone) {
        made.destroy();
        return;
      }
      mounted = made;
      canvas.current = made;
      // The browser check reads where the walker stands.
      (window as unknown as { __editorWalk?: WalkCanvas }).__editorWalk = made;
    });
    return () => {
      gone = true;
      mounted?.destroy();
      canvas.current = null;
      delete (window as unknown as { __editorWalk?: WalkCanvas }).__editorWalk;
    };
  }, [world, fog]);

  // The game's keys, and P to leave: one key layer over the editor's (which is off meanwhile).
  useEffect(
    () =>
      keyScope.push({
        screen,
        handle: (_command, event: KeyLike) => {
          if (event.code === "KeyP" && !event.ctrlKey && !event.metaKey && !event.altKey) {
            onLeave();
            return true;
          }
          const command = keyCommand(event, screen);
          const c = canvas.current;
          if (!command) return false;
          switch (command.kind) {
            case "step":
              c?.step(command);
              return true;
            case "zoom":
              c?.zoomBy(command.by);
              return true;
            case "recentre":
              c?.recentre();
              return true;
            case "escape":
              if (help) setHelp(false);
              else c?.cancel();
              return true;
            case "help":
              setHelp((h) => !h);
              return true;
            default:
              // Places, services and leaving are the hub's and the instance's screens', not the map's.
              return true;
          }
        },
      }),
    [screen, onLeave, help],
  );

  return (
    <div className="ed-walk" data-walk="" data-walk-fog={fog ? "on" : "off"}>
      <header className="ed-bar">
        <strong>Walking · {doc.meta.name} (preview)</strong>
        <span className="ed-dim">Keys: the game&apos;s (Q W E A S D, arrows, 0, + −, Esc, ?)</span>
        <span className="ed-spacer" />
        <button type="button" data-leave-walk="" onClick={onLeave}>
          [P] ◂ Edit
        </button>
      </header>
      <div className="ed-canvas" ref={host} data-walk-canvas="" />
      <footer className="ed-bar ed-bottom">
        <span>Start:</span>
        {starts.map((s, i) => (
          <label key={s.label}>
            <input
              type="radio"
              name="walk-start"
              data-walk-start={s.label}
              checked={i === start}
              onChange={(e) => {
                setStart(i);
                e.currentTarget.blur();
              }}
            />{" "}
            {s.label}
          </label>
        ))}
        <span className="ed-spacer" />
        {zone && (
          <label>
            <input
              type="checkbox"
              data-walk-fog=""
              checked={fog}
              onChange={(e) => {
                setFog(e.target.checked);
                e.currentTarget.blur();
              }}
            />{" "}
            Fog (sight of radius 6)
          </label>
        )}
        <span className="ed-dim" data-walk-said="">
          {said}
        </span>
        {from && (
          <span className="ed-dim">
            start ({toFrame(frame, from.tile).x}, {toFrame(frame, from.tile).y}) in the fitted map
          </span>
        )}
      </footer>
      {help && (
        <div className="ed-walk-help" role="dialog" aria-label="Keys">
          <table className="ed-table" style={{ minWidth: 0 }}>
            <tbody>
              {bindingsOf(screen)
                .filter((b) => !b.reserved)
                .map((b) => (
                  <tr key={b.keys}>
                    <td>
                      <kbd>{b.keys}</kbd>
                    </td>
                    <td>{b.label}</td>
                  </tr>
                ))}
              <tr>
                <td>
                  <kbd>P</kbd>
                </td>
                <td>Back to editing</td>
              </tr>
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
