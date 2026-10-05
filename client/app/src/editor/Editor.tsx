import { type ReactNode, useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { KeyLike } from "../input/keys";
import type { Tile } from "../render/view";
import { installKeys, keyScope } from "../sandbox/keyScope";
import { type AtlasState, EditorCanvas } from "./canvas";
import { type DraftEntry, Drafts, browserStorage, newDraftId } from "./drafts";
import { fileName, loadMap, saveMap } from "./file";
import { EDITOR_BINDINGS, type EditorCommand, type EditorTool, editorCommand } from "./keys";
import {
  BIOMES,
  type Biome,
  CHUNK,
  FLOOR,
  GROUND_KINDS,
  MAP_KINDS,
  type MapDocument,
  type MapKind,
  NAME_MAX,
  SIZE_MAX,
  type StartFill,
  WALL,
  chunkOf,
  cloneMap,
  createMap,
  inMap,
  indexOf,
  newMapProblem,
  outlineRecords,
  tilesHigh,
  tilesWide,
} from "./model";
import { outlineSegments, seamSegments } from "./overlay";
import { EditorSession } from "./session";
import { LAYER_NAMES, type Layers, editorView } from "./view";

/**
 * The map editor (CLI-09a, brief §2): the map list, the new map dialog and the editor's screen, in
 * the plain chrome (O-4), on a desktop only (O-3). Its own page (`editor.html`, O-1).
 */

/**
 * The editor's key layer on CLI-03k's stack (`keyScope`): the raw key is read with the editor's
 * table (`editorCommand`), so the layer's screen is never read; "report" is the game's screen with
 * the fewest bindings.
 */
function useEditorKeys(handle: (event: KeyLike) => boolean, active = true): void {
  const latest = useRef(handle);
  latest.current = handle;
  useEffect(() => {
    if (!active) return;
    return keyScope.push({ screen: "report", handle: (_command, event) => latest.current(event) });
  }, [active]);
}

const KIND_NAMES: Readonly<Record<MapKind, string>> = {
  zone: "Zone",
  town: "Town",
  outpost: "Outpost",
};

const TERRAIN_COLOURS = { floor: "#7da35a", wall: "#4a4a52" } as const;
const GROUND_COLOURS: Readonly<Record<string, string>> = {
  grass: "#6fa04c",
  earth: "#a07a4c",
  water: "#3d7fb8",
};

function download(name: string, text: string): void {
  const url = URL.createObjectURL(new Blob([text], { type: "application/json" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function stamp(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const two = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${two(d.getMonth() + 1)}-${two(d.getDate())} ${two(d.getHours())}:${two(d.getMinutes())}`;
}

/** The page's root. */
export function EditorApp() {
  const drafts = useMemo(() => new Drafts(browserStorage()), []);
  const [open, setOpen] = useState<{ id: string; doc: MapDocument } | null>(null);
  const [problem, setProblem] = useState("");
  const fileInput = useRef<HTMLInputElement>(null);

  useEffect(() => installKeys(), []);

  const openText = useCallback(
    (text: string) => {
      const read = loadMap(text);
      if ("problem" in read) {
        // The open map is not touched (§2.7).
        setProblem(read.problem);
        return;
      }
      setProblem("");
      const id = newDraftId();
      drafts.put(id, read.doc);
      setOpen({ id, doc: read.doc });
    },
    [drafts],
  );

  const openFile = useCallback(
    (file: File | undefined) => {
      if (!file) return;
      file
        .text()
        .then(openText)
        .catch(() => setProblem("The file cannot be read."));
    },
    [openText],
  );

  // A file dropped anywhere on the page opens.
  useEffect(() => {
    const over = (e: DragEvent) => e.preventDefault();
    const drop = (e: DragEvent) => {
      e.preventDefault();
      openFile(e.dataTransfer?.files[0]);
    };
    window.addEventListener("dragover", over);
    window.addEventListener("drop", drop);
    return () => {
      window.removeEventListener("dragover", over);
      window.removeEventListener("drop", drop);
    };
  }, [openFile]);

  const pickFile = () => fileInput.current?.click();

  return (
    <div className="ed-root" data-chrome="plain" data-editor={open ? "map" : "list"}>
      <p className="ed-narrow">The map editor needs a desktop window.</p>
      <input
        ref={fileInput}
        type="file"
        accept=".json,application/json"
        hidden
        data-open-file=""
        onChange={(e) => {
          openFile(e.target.files?.[0]);
          e.target.value = "";
        }}
      />
      {open ? (
        <EditorScreen
          key={open.id}
          id={open.id}
          doc={open.doc}
          drafts={drafts}
          problem={problem}
          onBack={() => {
            setProblem("");
            setOpen(null);
          }}
          onOpenFile={pickFile}
        />
      ) : (
        <MapList
          drafts={drafts}
          problem={problem}
          onOpen={(id) => {
            const doc = drafts.get(id);
            if (typeof doc === "string") setProblem(doc);
            else {
              setProblem("");
              setOpen({ id, doc });
            }
          }}
          onCreate={(doc) => {
            const id = newDraftId();
            drafts.put(id, doc);
            setProblem("");
            setOpen({ id, doc });
          }}
          onOpenFile={pickFile}
        />
      )}
    </div>
  );
}

// --- the map list (§2.1) -----------------------------------------------------------------------

function MapList({
  drafts,
  problem,
  onOpen,
  onCreate,
  onOpenFile,
}: {
  drafts: Drafts;
  problem: string;
  onOpen: (id: string) => void;
  onCreate: (doc: MapDocument) => void;
  onOpenFile: () => void;
}) {
  const [entries, setEntries] = useState<DraftEntry[]>(() => drafts.list());
  const [creating, setCreating] = useState(false);
  const [forgetting, setForgetting] = useState<DraftEntry | null>(null);
  const [help, setHelp] = useState(false);
  const refresh = () => setEntries(drafts.list());

  useEditorKeys(
    (event) => {
      const command = editorCommand(event);
      if (command?.kind === "open") {
        onOpenFile();
        return true;
      }
      if (command?.kind === "help") {
        setHelp(true);
        return true;
      }
      return false;
    },
    !creating && !forgetting && !help,
  );

  return (
    <>
      <header className="ed-bar">
        <strong>Grim World — Map editor</strong>
        <span className="ed-spacer" />
        <button type="button" onClick={onOpenFile}>
          Open file…
        </button>
        <button type="button" aria-label="Keys" onClick={() => setHelp(true)}>
          ?
        </button>
      </header>
      <main className="ed-page" data-screen="list">
        <button type="button" data-new-map="" onClick={() => setCreating(true)}>
          + New map
        </button>
        {problem && (
          <p className="ed-problem" role="alert">
            {problem}
          </p>
        )}
        <h2 className="ed-heading">Drafts in this browser</h2>
        {entries.length === 0 ? (
          <p className="ed-dim">No draft yet.</p>
        ) : (
          <table className="ed-table">
            <thead>
              <tr>
                <th>Kind</th>
                <th>Name</th>
                <th>Size (chunks)</th>
                <th>Location id</th>
                <th>Edited</th>
                <th>Problems</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {entries.map((e) => (
                <tr key={e.id} data-draft={e.id}>
                  <td>{KIND_NAMES[e.kind]}</td>
                  <td>{e.name}</td>
                  <td>
                    {e.width} × {e.height}
                  </td>
                  <td>{e.location}</td>
                  <td>{stamp(e.edited)}</td>
                  <td className="ed-dim" title="Validation comes with CLI-09b">
                    —
                  </td>
                  <td>
                    <button type="button" onClick={() => onOpen(e.id)}>
                      Open
                    </button>{" "}
                    <button
                      type="button"
                      onClick={() => {
                        const doc = drafts.get(e.id);
                        if (typeof doc === "string") return;
                        drafts.put(newDraftId(), cloneMap(doc));
                        refresh();
                      }}
                    >
                      Duplicate
                    </button>{" "}
                    <button
                      type="button"
                      onClick={() => {
                        const text = drafts.text(e.id);
                        if (text) download(fileName(e), text);
                      }}
                    >
                      Download
                    </button>{" "}
                    <button type="button" onClick={() => setForgetting(e)}>
                      Forget
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        <p className="ed-dim">Drafts live in this browser only. Download a map to keep it.</p>
      </main>
      {creating && <NewMapDialog onCancel={() => setCreating(false)} onCreate={onCreate} />}
      {forgetting && (
        <Dialog
          title="Forget this draft?"
          confirm="Forget"
          onCancel={() => setForgetting(null)}
          onConfirm={() => {
            drafts.forget(forgetting.id);
            setForgetting(null);
            refresh();
          }}
        >
          <p>“{forgetting.name}” is removed from this browser. A file downloaded before is kept.</p>
        </Dialog>
      )}
      {help && <HelpDialog onClose={() => setHelp(false)} />}
    </>
  );
}

// --- dialogs -----------------------------------------------------------------------------------

/** A dialog: its own key layer, where Escape closes it and Enter confirms (§3). */
function Dialog({
  title,
  confirm,
  disabled = false,
  onCancel,
  onConfirm,
  children,
}: {
  title: string;
  confirm?: string;
  disabled?: boolean;
  onCancel: () => void;
  onConfirm?: () => void;
  children: ReactNode;
}) {
  useEditorKeys((event) => {
    if (event.code === "Escape") {
      onCancel();
      return true;
    }
    if ((event.code === "Enter" || event.code === "NumpadEnter") && onConfirm && !disabled) {
      onConfirm();
      return true;
    }
    return false;
  });
  return (
    <div className="ed-dialog-back" onMouseDown={(e) => e.target === e.currentTarget && onCancel()}>
      <div className="ed-dialog" role="dialog" aria-modal="true" aria-label={title}>
        <h2>{title}</h2>
        {children}
        <div className="ed-actions">
          <button type="button" onClick={onCancel}>
            {onConfirm ? "Cancel" : "Close"}
          </button>
          {onConfirm && (
            <button type="button" disabled={disabled} onClick={onConfirm} data-confirm="">
              {confirm}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

function NewMapDialog({
  onCancel,
  onCreate,
}: {
  onCancel: () => void;
  onCreate: (doc: MapDocument) => void;
}) {
  const [kind, setKind] = useState<MapKind>("zone");
  const [name, setName] = useState("");
  const [location, setLocation] = useState("2");
  const [width, setWidth] = useState("3");
  const [height, setHeight] = useState("2");
  const [biome, setBiome] = useState<Biome>("meadow");
  const [start, setStart] = useState<StartFill>("wall");
  const fields = {
    kind,
    name,
    location: Number(location),
    width: Number(width),
    height: Number(height),
    biome,
    start,
  };
  const problem = newMapProblem(fields);
  const max = SIZE_MAX[kind];
  return (
    <Dialog
      title="New map"
      confirm="Create"
      disabled={problem !== null}
      onCancel={onCancel}
      onConfirm={() => onCreate(createMap(fields))}
    >
      <div className="ed-form" data-dialog="new-map">
        <span>Kind</span>
        <span>
          {MAP_KINDS.map((k) => (
            <label key={k} style={{ marginRight: 14 }}>
              <input
                type="radio"
                name="kind"
                value={k}
                checked={kind === k}
                onChange={() => setKind(k)}
              />{" "}
              {KIND_NAMES[k]}
            </label>
          ))}
        </span>
        <label htmlFor="ed-name">Name</label>
        <span>
          <input
            id="ed-name"
            name="name"
            value={name}
            maxLength={NAME_MAX}
            autoFocus
            onChange={(e) => setName(e.target.value)}
          />{" "}
          <span className="ed-dim">≤ {NAME_MAX} characters</span>
        </span>
        <label htmlFor="ed-location">Location</label>
        <span>
          <input
            id="ed-location"
            name="location"
            inputMode="numeric"
            size={5}
            value={location}
            onChange={(e) => setLocation(e.target.value)}
          />{" "}
          <span className="ed-dim">the LOCATION id it will be</span>
        </span>
        <span>Size</span>
        <span>
          width{" "}
          <input
            name="width"
            inputMode="numeric"
            size={3}
            value={width}
            onChange={(e) => setWidth(e.target.value)}
          />{" "}
          × height{" "}
          <input
            name="height"
            inputMode="numeric"
            size={3}
            value={height}
            onChange={(e) => setHeight(e.target.value)}
          />{" "}
          chunks{" "}
          <span className="ed-dim">
            (1–{max}) = {Number(width) * CHUNK || 0} × {Number(height) * CHUNK || 0} tiles
          </span>
        </span>
        <label htmlFor="ed-biome">Biome</label>
        <span>
          <select
            id="ed-biome"
            name="biome"
            value={biome}
            disabled={kind !== "zone"}
            onChange={(e) => setBiome(e.target.value as Biome)}
          >
            {BIOMES.map((b) => (
              <option key={b} value={b}>
                {b[0]!.toUpperCase() + b.slice(1)}
              </option>
            ))}
          </select>{" "}
          <span className="ed-dim">(zone only)</span>
        </span>
        <span>Start as</span>
        <span>
          {(["wall", "floor"] as const).map((s) => (
            <label key={s} style={{ marginRight: 14 }}>
              <input
                type="radio"
                name="start"
                value={s}
                checked={start === s}
                onChange={() => setStart(s)}
              />{" "}
              All {s}
            </label>
          ))}
        </span>
      </div>
      {problem && <p className="ed-problem">{problem}</p>}
    </Dialog>
  );
}

function HelpDialog({ onClose }: { onClose: () => void }) {
  return (
    <Dialog title="Keys" onCancel={onClose}>
      <table className="ed-table" style={{ minWidth: 0 }}>
        <tbody>
          {EDITOR_BINDINGS.map((b) => (
            <tr key={b.keys}>
              <td>
                <kbd>{b.keys}</kbd>
              </td>
              <td>{b.label}</td>
            </tr>
          ))}
          <tr>
            <td>Right drag</td>
            <td>Erase with a brush tool; outside with Outline</td>
          </tr>
          <tr>
            <td>Alt+click</td>
            <td>Pick</td>
          </tr>
          <tr>
            <td>Middle drag, Space+drag</td>
            <td>Pan</td>
          </tr>
          <tr>
            <td>Wheel, Shift+wheel</td>
            <td>Zoom at the pointer; brush size</td>
          </tr>
        </tbody>
      </table>
    </Dialog>
  );
}

// --- the editor's screen (§2.3) -----------------------------------------------------------------

const TOOLS: readonly { tool: EditorTool; key: string; label: string }[] = [
  { tool: "paint", key: "B", label: "Paint" },
  { tool: "erase", key: "N", label: "Erase" },
  { tool: "fill", key: "G", label: "Fill" },
  { tool: "pick", key: "I", label: "Pick" },
  { tool: "outline", key: "T", label: "Outline" },
];

const LAYER_LABELS: Readonly<Record<keyof Layers, string>> = {
  ground: "Ground",
  obstacles: "Obstacles",
  objects: "Objects",
  outline: "Outline",
  seams: "Chunk seams",
  grid: "Grid",
};

/** How long after a change the draft is written (§6). */
const DRAFT_DELAY_MS = 400;

function EditorScreen({
  id,
  doc,
  drafts,
  problem,
  onBack,
  onOpenFile,
}: {
  id: string;
  doc: MapDocument;
  drafts: Drafts;
  problem: string;
  onBack: () => void;
  onOpenFile: () => void;
}) {
  const [, setTick] = useState(0);
  const rerender = useCallback(() => setTick((t) => t + 1), []);
  const session = useMemo(() => new EditorSession(doc, rerender), [doc, rerender]);
  const host = useRef<HTMLDivElement>(null);
  const canvas = useRef<EditorCanvas | null>(null);
  const [atlas, setAtlas] = useState<AtlasState>("loading");
  const [hover, setHover] = useState<Tile | null>(null);
  const [across, setAcross] = useState(0);
  const [saved, setSaved] = useState<{ at: Date | null; failed: boolean }>({
    at: null,
    failed: false,
  });
  const [dirty, setDirty] = useState(false);
  const [help, setHelp] = useState(false);
  const meta = doc.meta;
  const columns = tilesWide(meta);
  const rows = tilesHigh(meta);
  const seams = useMemo(() => seamSegments(columns, rows), [columns, rows]);

  // The canvas: mounted once per map.
  useEffect(() => {
    const element = host.current;
    if (!element) return;
    let mounted: EditorCanvas | null = null;
    let gone = false;
    void EditorCanvas.mount(element, {
      strokeStart: (tile, how) => session.strokeStart(tile, how),
      strokeMove: (tiles) => session.strokeMove(tiles),
      strokeEnd: () => session.strokeEnd(),
      hover: (tile) => setHover(tile),
      brush: (by) => session.setBrush(session.brush + by),
      changed: () => {
        if (!mounted) return;
        setAtlas(mounted.atlas);
        setAcross(mounted.across());
      },
    }).then((made) => {
      if (gone) {
        made.destroy();
        return;
      }
      mounted = made;
      canvas.current = made;
      made.setView(editorView(doc, session.layers));
      made.setMapSize(columns, rows);
      setAtlas(made.atlas);
      setAcross(made.across());
      rerender();
    });
    return () => {
      gone = true;
      mounted?.destroy();
      canvas.current = null;
    };
  }, [doc, session, columns, rows, rerender]);

  // The view: rebuilt when the document or the layers change, at most once a display frame.
  const { revision, layers } = session;
  useEffect(() => {
    const frame = window.requestAnimationFrame(() =>
      canvas.current?.setView(editorView(doc, layers)),
    );
    return () => window.cancelAnimationFrame(frame);
  }, [doc, revision, layers]);

  const outlineEdges = useMemo(
    () => (doc.outline ? outlineSegments(columns, rows, doc.outline) : null),
    // The outline is edited in place: the revision says when.
    [doc, columns, rows, revision],
  );
  const records = useMemo(() => (doc.outline ? outlineRecords(doc) : null), [doc, revision]);

  // The overlays.
  const brush = hover && inMap(doc, hover) ? session.footprint(hover) : [];
  useEffect(() => {
    canvas.current?.setScene({
      width: columns,
      height: rows,
      outline: doc.outline && layers.outline ? doc.outline : null,
      outlineEdges: layers.outline ? outlineEdges : null,
      seams: layers.seams ? seams : null,
      grid: layers.grid,
      brush,
      hover,
    });
  });

  // The draft, written a moment after each change (§6).
  useEffect(() => {
    if (revision === 0) return;
    setDirty(true);
    const timer = window.setTimeout(() => {
      const ok = drafts.put(id, doc);
      setSaved({ at: ok ? new Date() : null, failed: !ok });
      setDirty(false);
    }, DRAFT_DELAY_MS);
    return () => window.clearTimeout(timer);
  }, [revision, drafts, id, doc]);

  const save = () => {
    const ok = drafts.put(id, doc);
    setSaved({ at: ok ? new Date() : null, failed: !ok });
    setDirty(false);
    download(fileName(meta), saveMap(doc));
  };

  const run = (command: EditorCommand): boolean => {
    const c = canvas.current;
    switch (command.kind) {
      case "tool":
        session.armTool(command.tool);
        return true;
      case "pan":
        c?.panBy(command.dx, command.dy);
        return true;
      case "zoom":
        c?.zoomBy(command.by);
        return true;
      case "fit":
        c?.fit();
        return true;
      case "brush":
        session.setBrush(session.brush + command.by);
        return true;
      case "undo":
        session.undo();
        return true;
      case "redo":
        session.redo();
        return true;
      case "save":
        save();
        return true;
      case "open":
        onOpenFile();
        return true;
      case "grid":
        session.toggleLayer("grid");
        return true;
      case "layerFocus":
        session.focusNextLayer();
        return true;
      case "layerToggle":
        session.toggleLayer(LAYER_NAMES[session.layerFocus]!);
        return true;
      case "escape":
        session.strokeEnd();
        return true;
      case "help":
        setHelp(true);
        return true;
    }
  };

  useEditorKeys((event) => {
    if (event.code === "Space" && !event.ctrlKey && !event.metaKey) {
      // Space held: a left drag pans (§3); its release is heard below.
      canvas.current?.setSpace(true);
      return true;
    }
    const command = editorCommand(event);
    return command ? run(command) : false;
  }, !help);
  useEffect(() => {
    const up = (e: KeyboardEvent) => e.code === "Space" && canvas.current?.setSpace(false);
    window.addEventListener("keyup", up);
    return () => window.removeEventListener("keyup", up);
  }, []);

  const hovered = hover && inMap(doc, hover) ? hover : null;
  const at = hovered ? chunkOf(hovered) : null;
  const hoverIndex = hovered ? indexOf(doc, hovered) : -1;
  const state = dirty
    ? "Unsaved changes"
    : saved.failed
      ? "Not saved: this browser refused the draft"
      : saved.at
        ? `Saved ${saved.at.toTimeString().slice(0, 5)} (draft)`
        : "Draft";
  const fillLabel = session.tool === "fill" && session.fillOutline ? "outline" : null;
  const armed =
    session.tool === "paint"
      ? `Paint: ${session.group === "terrain" ? (session.terrain === WALL ? "Wall" : "Floor") : GROUND_KINDS[session.ground]}`
      : session.tool === "fill"
        ? `Fill: ${fillLabel ?? (session.group === "terrain" ? (session.terrain === WALL ? "Wall" : "Floor") : GROUND_KINDS[session.ground])}`
        : TOOLS.find((t) => t.tool === session.tool)!.label;

  return (
    <>
      <header className="ed-bar" data-topbar="">
        <button type="button" onClick={onBack}>
          ◂ Maps
        </button>
        <span>
          <strong data-map-name="">{meta.name}</strong> · {KIND_NAMES[meta.kind]} · {meta.width}×
          {meta.height} chunks · loc {meta.location}
        </span>
        <span className="ed-dim" data-save-state="">
          {state}
        </span>
        <span>
          <button
            type="button"
            aria-label="Undo"
            disabled={!session.history.canUndo()}
            onClick={() => session.undo()}
          >
            ⟲
          </button>{" "}
          <button
            type="button"
            aria-label="Redo"
            disabled={!session.history.canRedo()}
            onClick={() => session.redo()}
          >
            ⟳
          </button>
        </span>
        <span className="ed-spacer" />
        {problem && (
          <span className="ed-problem" role="alert">
            {problem}
          </span>
        )}
        <button type="button" onClick={onOpenFile}>
          Open file…
        </button>
        <button type="button" data-save="" onClick={save}>
          Save
        </button>
        <button type="button" aria-label="Keys" onClick={() => setHelp(true)}>
          ?
        </button>
      </header>
      <div className="ed-main">
        <aside className="ed-tools">
          <div className="ed-heading">Tools</div>
          <div className="ed-column">
            {TOOLS.map((t) => (
              <button
                key={t.tool}
                type="button"
                data-tool={t.tool}
                aria-pressed={session.tool === t.tool}
                disabled={t.tool === "outline" && !session.zone}
                onClick={() => session.armTool(t.tool)}
              >
                [{t.key}] {t.label}
              </button>
            ))}
          </div>
          <div className="ed-heading">Terrain</div>
          <div className="ed-column">
            {(
              [
                ["floor", FLOOR],
                ["wall", WALL],
              ] as const
            ).map(([label, value]) => (
              <button
                key={label}
                type="button"
                data-swatch={`terrain-${label}`}
                aria-pressed={session.group === "terrain" && session.terrain === value}
                onClick={() => session.choose("terrain", value)}
              >
                <span className="ed-swatch" style={{ background: TERRAIN_COLOURS[label] }} />
                {label[0]!.toUpperCase() + label.slice(1)}
              </button>
            ))}
          </div>
          <div className="ed-heading">Ground</div>
          <div className="ed-column">
            {GROUND_KINDS.map((g, value) => (
              <button
                key={g}
                type="button"
                data-swatch={`ground-${g}`}
                aria-pressed={session.group === "ground" && session.ground === value}
                onClick={() => session.choose("ground", value)}
              >
                <span className="ed-swatch" style={{ background: GROUND_COLOURS[g] }} />
                {g[0]!.toUpperCase() + g.slice(1)}
              </button>
            ))}
          </div>
          <div className="ed-heading">Brush</div>
          <div>
            {[0, 1, 2, 3].map((r) => (
              <button
                key={r}
                type="button"
                data-brush={r}
                aria-pressed={session.brush === r}
                onClick={() => session.setBrush(r)}
                style={{ marginRight: 4 }}
              >
                {r + 1}
              </button>
            ))}
          </div>
          <p className="ed-dim">
            Radius {session.brush}: {[1, 7, 19, 37][session.brush]} hexes. [ ] or Shift+wheel.
          </p>
        </aside>
        <div className="ed-centre">
          <div className="ed-canvas" ref={host} data-canvas="" data-atlas={atlas} />
          <div className="ed-layers" data-layers="">
            Layers:
            {LAYER_NAMES.map((name, i) => (
              <label key={name} data-focused={session.layerFocus === i ? "" : undefined}>
                <input
                  type="checkbox"
                  data-layer={name}
                  checked={session.layers[name]}
                  disabled={name === "outline" && !session.zone}
                  onChange={(e) => {
                    session.toggleLayer(name);
                    // A focused input takes every key (`ignoredTarget`): give the keys back.
                    e.currentTarget.blur();
                  }}
                />{" "}
                {LAYER_LABELS[name]}
              </label>
            ))}
          </div>
        </div>
        <aside className="ed-inspector" data-inspector="">
          <div className="ed-heading">Hex</div>
          {hovered && at ? (
            <div data-hex="">
              <div>
                ({hovered.x}, {hovered.y})
              </div>
              <div className="ed-dim">
                chunk {at.chunk} ({at.cx},{at.cy}) · tile {at.tile}
              </div>
              <div>Terrain: {doc.terrain[hoverIndex] === WALL ? "Wall" : "Floor"}</div>
              <div>Ground: {GROUND_KINDS[doc.ground[hoverIndex]!]}</div>
              <div>Obstacle: {doc.obstacles.get(hoverIndex) ?? "auto"}</div>
              {doc.outline && <div>Outline: {doc.outline[hoverIndex] ? "inside" : "outside"}</div>}
            </div>
          ) : (
            <div className="ed-dim">Point at a hex.</div>
          )}
          <div className="ed-heading">Map</div>
          <div>
            {KIND_NAMES[meta.kind]} “{meta.name}”, location {meta.location}
          </div>
          <div>
            {meta.width} × {meta.height} chunks = {columns} × {rows} tiles
          </div>
          {meta.biome && <div>Biome: {meta.biome}</div>}
          <div>Start fill: {meta.start}</div>
          {records && (
            <>
              <div className="ed-heading">Outline</div>
              {session.tool === "outline" && (
                <button
                  type="button"
                  data-outline-from-floor=""
                  onClick={() => session.outlineFromFloor(null)}
                >
                  Outline from floor
                </button>
              )}
              <ChunkCells meta={meta} records={records} />
              <div className="ed-dim" data-chunk-set="">
                {records.chunks.length} chunks in the set, {records.masks.size} on the border
              </div>
            </>
          )}
        </aside>
      </div>
      <footer className="ed-bar ed-bottom" data-status="">
        {hovered && at ? (
          <span>
            x {hovered.x} y {hovered.y} · chunk ({at.cx},{at.cy}) tile {at.tile}
          </span>
        ) : (
          <span className="ed-dim">—</span>
        )}
        <span>· zoom {Math.round(across)} across</span>
        <span data-armed="">
          · {armed} · brush {session.brush + 1}
        </span>
        {session.said && <span className="ed-problem">{session.said}</span>}
        <span className="ed-spacer" />
        <span className="ed-dim">
          Art: {atlas === "loaded" ? "atlas" : atlas === "loading" ? "loading" : "shapes"}
        </span>
      </footer>
      {help && <HelpDialog onClose={() => setHelp(false)} />}
    </>
  );
}

/** The chunk set as a small grid of chunk cells (§2.5): whole, border, or outside. */
function ChunkCells({
  meta,
  records,
}: {
  meta: MapDocument["meta"];
  records: ReturnType<typeof outlineRecords>;
}) {
  const inSet = new Set(records.chunks);
  const cells: ReactNode[] = [];
  // Drawn as the map: x grows West (to the left), y North (up).
  for (let cy = CHUNK - 1; cy >= 0; cy--) {
    for (let cx = CHUNK - 1; cx >= 0; cx--) {
      const chunk = CHUNK * cy + cx;
      const inside = cx < meta.width && cy < meta.height;
      const cell = !inside
        ? undefined
        : !inSet.has(chunk)
          ? "outside"
          : records.masks.has(chunk)
            ? "border"
            : "whole";
      cells.push(
        <span key={chunk} data-cell={cell} title={inside ? `chunk ${chunk}` : undefined} />,
      );
    }
  }
  return <div className="ed-chunks">{cells}</div>;
}
