import { type ReactNode, useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { KeyLike } from "../input/keys";
import { loadAtlas } from "../render/atlas";
import type { SpriteLibrary } from "../render/sprites";
import type { Tile } from "../render/view";
import { installKeys, keyScope } from "../sandbox/keyScope";
import { type AtlasState, EditorCanvas } from "./canvas";
import { type DraftEntry, DraftWriter, Drafts, browserStorage, newDraftId } from "./drafts";
import { fileName, loadMap, saveMap } from "./file";
import { type Fitted, chunkAt, fitted } from "./fit";
import { SelectionPanel } from "./Inspector";
import { ValidationLight, ValidationPanel } from "./ValidationPanel";
import { type WalkStart, WalkScreen } from "./WalkScreen";
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
  WALL,
  cellAt,
  createMap,
  isOutside,
  keyOf,
  newMapProblem,
  paintedBox,
  tileOfKey,
} from "./model";
import {
  DEFAULT_BUILDING,
  FEATURE_KINDS,
  FEATURE_NAMES,
  OBJECT_NAMES,
  type PlaceChoice,
  QUOTA_NAMES,
  newObject,
  objectLabel,
  servicesOf,
} from "./objects";
import { PACK_KIND_OF, isPack, placementOf } from "./pack";
import { drawSprites, spritesFromLibrary } from "./packDraw";
import {
  Palette,
  drawPreview,
  kindOf as packKindOf,
  previewOf,
  thumbsFromLibrary,
} from "./palette";
import { type Marker, outlineSegments, outsideMask, seamSegments } from "./overlay";
import { EditorSession, NOTHING } from "./session";
import { type Finding, tally, validate } from "./validate";
import { type Manifest, convert, recordsFile } from "./export/convert";
import { fromExport, isExportText, readManifest, toExport } from "./export/document";
import { Refused } from "./export/records";
import { footprintOf, frameOf } from "./walkWorld";
import { listenSpaceRelease } from "./spaceHold";
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
  /** What a file's load says beside the map: a format 1 file's conversion. */
  const [note, setNote] = useState("");
  const fileInput = useRef<HTMLInputElement>(null);
  /** The content manifest the export and the import name records by (CLI-09c), for this page. */
  const [manifest, setManifest] = useState<{ name: string; value: Manifest } | null>(null);
  const manifestInput = useRef<HTMLInputElement>(null);

  useEffect(() => installKeys(), []);

  const openText = useCallback(
    (text: string) => {
      let raw: unknown = null;
      try {
        raw = JSON.parse(text);
      } catch {
        // `loadMap` says so.
      }
      // An export for the chain (ENG-08's `grimworld-export`) opens through the manifest.
      const read = !isExportText(raw)
        ? loadMap(text)
        : manifest
          ? fromExport(raw, manifest.value)
          : {
              problem:
                "This is an export for the chain: it names its records. Load its content manifest first (Manifest…).",
            };
      if ("problem" in read) {
        // The open map is not touched (§2.7).
        setProblem(read.problem);
        return;
      }
      setProblem("");
      setNote(read.notes.join(" "));
      const id = newDraftId();
      drafts.put(id, read.doc);
      setOpen({ id, doc: read.doc });
    },
    [drafts, manifest],
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
  const pickManifest = () => manifestInput.current?.click();
  const loadManifest = (file: File | undefined) => {
    if (!file) return;
    file
      .text()
      .then((text) => {
        const read = readManifest(text);
        if (typeof read === "string") setProblem(read);
        else {
          setProblem("");
          setManifest({ name: file.name, value: read });
        }
      })
      .catch(() => setProblem("The manifest cannot be read."));
  };

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
      <input
        ref={manifestInput}
        type="file"
        accept=".json,application/json"
        hidden
        data-manifest-file=""
        onChange={(e) => {
          loadManifest(e.target.files?.[0]);
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
          note={note}
          onBack={() => {
            setProblem("");
            setNote("");
            setOpen(null);
          }}
          onOpenFile={pickFile}
          manifest={manifest}
          onLoadManifest={pickManifest}
        />
      ) : (
        <MapList
          drafts={drafts}
          problem={problem}
          onProblem={setProblem}
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
          manifest={manifest?.name ?? null}
          onLoadManifest={pickManifest}
        />
      )}
    </div>
  );
}

// --- the map list (§2.1) -----------------------------------------------------------------------

function MapList({
  drafts,
  problem,
  onProblem,
  onOpen,
  onCreate,
  onOpenFile,
  manifest,
  onLoadManifest,
}: {
  drafts: Drafts;
  problem: string;
  onProblem: (problem: string) => void;
  onOpen: (id: string) => void;
  onCreate: (doc: MapDocument) => void;
  onOpenFile: () => void;
  manifest: string | null;
  onLoadManifest: () => void;
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
        <ManifestButton name={manifest} onLoad={onLoadManifest} />
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
                <th>Hexes</th>
                <th>Chunks (fitted)</th>
                <th>Location id</th>
                <th>Edited</th>
                <th>Problems (errors · warnings)</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {entries.map((e) => (
                <tr key={e.id} data-draft={e.id}>
                  <td>{KIND_NAMES[e.kind]}</td>
                  <td>{e.name}</td>
                  <td>{e.hexes ?? "—"}</td>
                  <td>{e.chunks ?? "—"}</td>
                  <td>{e.location}</td>
                  <td>{stamp(e.edited)}</td>
                  <td
                    data-problems=""
                    className={e.problems?.errors ? "ed-problem" : "ed-dim"}
                    title="Errors, warnings (§5)"
                  >
                    {e.problems ? `${e.problems.errors} · ${e.problems.warnings}` : "—"}
                  </td>
                  <td>
                    <button type="button" onClick={() => onOpen(e.id)}>
                      Open
                    </button>{" "}
                    <button
                      type="button"
                      onClick={() => {
                        // A refused copy says why (CLI-09a's review): the storage may be full.
                        onProblem(drafts.duplicate(e.id) ?? "");
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
  const [biome, setBiome] = useState<Biome>("meadow");
  const fields = { kind, name, location: Number(location), biome };
  const problem = newMapProblem(fields);
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
      </div>
      <p className="ed-dim">
        The map has no size: paint it anywhere, then fit the chunks to it (D-216).
      </p>
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
            <td>Erase with a brush tool; outside with Outline; cancel a paste</td>
          </tr>
          <tr>
            <td>Alt+click</td>
            <td>Pick</td>
          </tr>
          <tr>
            <td>Right click</td>
            <td>Inspect the hex, with Select or Place</td>
          </tr>
          <tr>
            <td>Drag (Select)</td>
            <td>A box; on a selected object, move it. Shift+click adds</td>
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
  { tool: "select", key: "U", label: "Select" },
  { tool: "place", key: "O", label: "Place" },
  { tool: "outline", key: "T", label: "Outline" },
];

const LAYER_LABELS: Readonly<Record<keyof Layers, string>> = {
  ground: "Ground",
  obstacles: "Obstacles",
  objects: "Objects",
  outline: "Outline",
  seams: "Fitted chunks",
  grid: "Grid",
};

/** How long after a change the draft is written (§6). */
const DRAFT_DELAY_MS = 400;
/** How long after a change the checks run again (§2.6: on every change, debounced). */
const VALIDATE_DELAY_MS = 250;

/** The palette's objects (§2.3): a zone's, or a town's pieces. */
function objectSwatches(doc: MapDocument): { label: string; choice: PlaceChoice; id: string }[] {
  if (doc.meta.kind === "zone") {
    return [
      { label: "E Entry", choice: { kind: "entry" }, id: "entry" },
      { label: "G Gate", choice: { kind: "gate" }, id: "gate" },
      ...doc.meta.quotas.map((q, i) => ({
        label: `${objectLabel({ kind: "candidate", at: { x: 0, y: 0 }, quota: i }, 0, doc.meta.quotas)} Q${i + 1} ${QUOTA_NAMES[q.kind]} place`,
        choice: { kind: "candidate", quota: i } as PlaceChoice,
        id: `candidate-${i}`,
      })),
      ...FEATURE_KINDS.map((feature) => ({
        label: `${objectLabel({ kind: "feature", at: { x: 0, y: 0 }, feature, param: 0 }, 0, [])} ${FEATURE_NAMES[feature]}`,
        choice: { kind: "feature", feature } as PlaceChoice,
        id: `feature-${feature}`,
      })),
      { label: "P Spawn point", choice: { kind: "spawn" }, id: "spawn" },
    ];
  }
  const services = servicesOf(doc.meta.kind);
  return [
    ...[...services, "gate" as const].map((target) => ({
      label: `${objectLabel({ kind: "place", at: { x: 0, y: 0 }, target, building: DEFAULT_BUILDING[target], depth: 1, mirror: false }, 0, [])} ${target[0]!.toUpperCase()}${target.slice(1)}`,
      choice: { kind: "place", target } as PlaceChoice,
      id: `place-${target}`,
    })),
    { label: "D Decor building", choice: { kind: "decor" }, id: "decor" },
    { label: "p Prop", choice: { kind: "prop" }, id: "prop" },
    { label: "A Figure spot", choice: { kind: "figure" }, id: "figure" },
    { label: "In Arrival", choice: { kind: "arrival" }, id: "arrival" },
  ];
}

const sameChoice = (a: PlaceChoice, b: PlaceChoice) => JSON.stringify(a) === JSON.stringify(b);

function EditorScreen({
  id,
  doc,
  drafts,
  problem,
  note,
  onBack,
  onOpenFile,
  manifest,
  onLoadManifest,
}: {
  id: string;
  doc: MapDocument;
  drafts: Drafts;
  problem: string;
  note: string;
  onBack: () => void;
  onOpenFile: () => void;
  manifest: { name: string; value: Manifest } | null;
  onLoadManifest: () => void;
}) {
  const [, setTick] = useState(0);
  const rerender = useCallback(() => setTick((t) => t + 1), []);
  const session = useMemo(() => new EditorSession(doc, rerender), [doc, rerender]);
  const host = useRef<HTMLDivElement>(null);
  const canvas = useRef<EditorCanvas | null>(null);
  const [atlas, setAtlas] = useState<AtlasState>("loading");
  // The atlas's library for the palette's thumbnails and the overlay's pack art: the pages the
  // canvas already loaded (PixiJS's `Assets` keeps them; nothing is fetched twice).
  const [library, setLibrary] = useState<SpriteLibrary | null>(null);
  const [hover, setHover] = useState<Tile | null>(null);
  const [across, setAcross] = useState(0);
  const [saved, setSaved] = useState<{ at: Date | null; failed: boolean }>({
    at: null,
    failed: false,
  });
  const [dirty, setDirty] = useState(false);
  const [help, setHelp] = useState(false);
  const [panel, setPanel] = useState(false);
  const [walking, setWalking] = useState(false);
  const [exporting, setExporting] = useState(false);
  const checked = manifest?.value ?? null;
  const [findings, setFindings] = useState<Finding[]>(() => validate(doc, checked));
  const findingsRef = useRef(findings);
  findingsRef.current = findings;
  const meta = doc.meta;
  const { revision, layers } = session;

  // The canvas: mounted once per map. The renderer is sent the tiles around the view only.
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
      made.setPainted(paintedBox(doc));
      made.setViewSource((window) => editorView(doc, session.layers, window));
      made.fit();
      setAtlas(made.atlas);
      setAcross(made.across());
      // The browser check reads the canvas and the session.
      (window as unknown as Record<string, unknown>).__editor = { canvas: made, session };
      rerender();
    });
    return () => {
      gone = true;
      mounted?.destroy();
      canvas.current = null;
      delete (window as unknown as Record<string, unknown>).__editor;
    };
  }, [doc, session, rerender]);

  useEffect(() => {
    if (atlas !== "loaded") return;
    let gone = false;
    void loadAtlas().then((made) => {
      if (!gone) setLibrary(made);
    });
    return () => {
      gone = true;
    };
  }, [atlas]);
  const thumbs = useMemo(() => (library ? thumbsFromLibrary(library) : null), [library]);
  const sprites = useMemo(() => (library ? spritesFromLibrary(library) : null), [library]);

  // The view: rebuilt when the document or the layers change, at most once a display frame.
  useEffect(() => {
    const frame = window.requestAnimationFrame(() => {
      canvas.current?.setPainted(paintedBox(doc));
      canvas.current?.refreshView();
    });
    return () => window.cancelAnimationFrame(frame);
  }, [doc, revision, layers]);

  // The checks, on every change, debounced (§2.6).
  useEffect(() => {
    if (revision === 0) return;
    const timer = window.setTimeout(() => setFindings(validate(doc, checked)), VALIDATE_DELAY_MS);
    return () => window.clearTimeout(timer);
  }, [doc, revision, checked]);
  // A manifest loaded runs the converter's checks at once.
  useEffect(() => setFindings(validate(doc, checked)), [doc, checked]);

  // The hexes are edited in place and the origin set on the document: the revision says when.
  const fit = useMemo(() => fitted(doc), [doc, revision]);
  const fit_ = typeof fit === "string" ? null : fit;
  const seams = useMemo(() => (fit_ ? seamSegments(fit_) : null), [fit_]);
  const outlineEdges = useMemo(
    () => (session.zone ? outlineSegments(doc) : null),
    [doc, session, revision],
  );
  const mask = useMemo(() => outsideMask(doc), [doc, revision]);

  // The objects' markers, a town's footprints, the hexes a finding names.
  const faults = useMemo(
    () => new Set(findings.filter((f) => f.severity === "error").flatMap((f) => f.objects)),
    [findings],
  );
  const { markers, footprints } = useMemo(() => {
    const markers: Marker[] = [];
    const footprints: Tile[] = [];
    let gate = 0;
    for (const [oid, object] of [...doc.objects].sort(([a], [b]) => a - b)) {
      if (object.kind === "gate") gate += 1;
      markers.push({
        tile: object.at,
        label: objectLabel(object, gate, doc.meta.quotas),
        tone: faults.has(oid) ? "fault" : session.zone ? "zone" : "town",
      });
      // A building's footprint, its door apart (the door is marked).
      footprints.push(
        ...footprintOf(object).filter((t) => t.x !== object.at.x || t.y !== object.at.y),
      );
    }
    return { markers, footprints };
  }, [doc, revision, faults, session]);

  // The overlays.
  const brush = hover && !walking ? session.footprint(hover) : [];
  const selected: Tile[] = [
    ...[...session.selection.hexes].map(tileOfKey),
    ...[...session.selection.objects].flatMap((oid) => {
      const o = doc.objects.get(oid);
      return o ? [o.at] : [];
    }),
  ];
  const ghost: Tile[] = [];
  const offset = session.moveOffset();
  if (offset) {
    for (const oid of session.selection.objects) {
      const o = doc.objects.get(oid);
      if (o) ghost.push({ x: o.at.x + offset.x, y: o.at.y + offset.y });
    }
  } else if (session.pasting && session.clip && hover) {
    const at = session.pasteOrigin(hover);
    for (const c of [...session.clip.cells, ...session.clip.objects]) {
      ghost.push({ x: at.x + c.dx, y: at.y + c.dy });
    }
  }
  // The placement's preview: the renderer draws the pack's objects placed (CLI-09e part 3).
  const preview = useMemo(() => {
    if (!hover || walking || session.tool !== "place" || !session.placing.type) return null;
    const object = newObject(session.placing, hover);
    if (!isPack(object)) return null;
    const look = previewOf(placementOf(object));
    return { look, object };
  }, [hover, walking, session.tool, session.placing]);
  useEffect(() => {
    canvas.current?.setScene({
      outside:
        session.zone && layers.outline
          ? (t) => {
              const cell = doc.hexes.get(keyOf(t));
              return cell !== undefined && isOutside(cell);
            }
          : null,
      outsideMask: session.zone && layers.outline ? mask : null,
      outlineEdges: layers.outline ? outlineEdges : null,
      seams: layers.seams ? seams : null,
      grid: layers.grid,
      brush,
      hover,
      markers: layers.objects ? markers : [],
      footprints: layers.objects ? footprints : [],
      selected,
      box: session.box,
      ghost,
      over: preview
        ? (ctx, camera, viewport) => {
            drawPreview(ctx, camera, viewport, preview.look);
            const { look, object } = preview;
            if (sprites && look.sprite && !look.problem) {
              const animation = object.kind === "npc" ? "idle" : "still";
              drawSprites(
                ctx,
                camera,
                viewport,
                [{ sprite: look.sprite, animation, at: object.at, mirror: look.mirrored }],
                sprites,
                0.6,
              );
            }
          }
        : null,
    });
  });

  // The draft, written a moment after each change, and at once when the screen goes or the tab
  // is closed (§6, O-5).
  const writer = useMemo(
    () =>
      new DraftWriter(
        () => {
          // The screen's latest checks: the draft is written after them (400 ms against 250).
          const ok = drafts.put(id, doc, new Date(), tally(findingsRef.current));
          setSaved({ at: ok ? new Date() : null, failed: !ok });
          setDirty(false);
        },
        DRAFT_DELAY_MS,
        {
          setTimeout: (run, ms) => window.setTimeout(run, ms),
          clearTimeout: (timer) => window.clearTimeout(timer),
        },
      ),
    [drafts, id, doc],
  );
  useEffect(() => {
    if (revision === 0) return;
    setDirty(true);
    writer.changed();
  }, [revision, writer]);
  useEffect(() => {
    const flush = () => writer.flush();
    window.addEventListener("pagehide", flush);
    return () => {
      window.removeEventListener("pagehide", flush);
      writer.flush();
    };
  }, [writer]);

  const save = () => {
    writer.now();
    download(fileName(meta), saveMap(doc));
  };

  const validateNow = () => {
    setFindings(validate(doc, checked));
    setPanel(true);
  };

  /** Show (§2.6): the hexes and objects at fault selected, the camera on the first. */
  const show = (finding: Finding) => {
    const hexes = new Set(finding.hexes.map(keyOf));
    // An object's hex is shown by its marker: select the object, not the hex under it.
    for (const oid of finding.objects) {
      const o = doc.objects.get(oid);
      if (o) hexes.delete(keyOf(o.at));
    }
    session.select({ hexes, objects: new Set(finding.objects.filter((o) => doc.objects.has(o))) });
    const first = finding.hexes[0] ?? doc.objects.get(finding.objects[0] ?? -1)?.at;
    if (first) canvas.current?.showTile(first);
  };

  // The walk's world: the fitted map, or the best fit when none was chosen.
  const frame = useMemo(() => frameOf(doc), [doc, revision]);
  const starts = useMemo((): WalkStart[] => {
    const out: WalkStart[] = [];
    const objects = [...doc.objects].sort(([a], [b]) => a - b).map(([, o]) => o);
    const home = objects.find((o) => o.kind === (session.zone ? "entry" : "arrival"));
    if (home) out.push({ label: session.zone ? "the entry" : "the arrival", tile: home.at });
    objects
      .filter((o) => o.kind === "gate")
      .forEach((g, i) => out.push({ label: `gate G${i + 1}`, tile: g.at }));
    const picked =
      session.selection.hexes.size === 1
        ? tileOfKey([...session.selection.hexes][0]!)
        : session.inspected;
    if (picked) out.push({ label: "the selected hex", tile: picked });
    return out;
  }, [doc, revision, session, session.selection, session.inspected]);

  const toggleWalk = () => {
    if (walking) {
      setWalking(false);
      return;
    }
    if (!frame) {
      session.said = "Nothing to walk: paint the map first.";
      rerender();
      return;
    }
    if (starts.length === 0) {
      session.said = `Nothing to start from: place ${session.zone ? "an entry" : "an arrival"} or select a hex.`;
      rerender();
      return;
    }
    session.strokeEnd();
    setWalking(true);
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
      case "fitChunks":
        session.fitChunks();
        return true;
      case "nudge":
        session.nudgeOrigin(command.dx, command.dy);
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
        session.escape();
        return true;
      case "help":
        setHelp(true);
        return true;
      case "delete":
        session.deleteSelection();
        return true;
      case "cut":
        session.cut();
        return true;
      case "copy":
        session.copy();
        return true;
      case "paste":
        session.paste();
        return true;
      case "mirror":
        session.mirror();
        return true;
      case "turn":
        session.turn();
        return true;
      case "validate":
        validateNow();
        return true;
      case "walk":
        toggleWalk();
        return true;
    }
  };

  useEditorKeys(
    (event) => {
      if (event.code === "Space" && !event.ctrlKey && !event.metaKey) {
        // Space held: a left drag pans (§3); its release, a blur or a hidden page end it.
        canvas.current?.setSpace(true);
        return true;
      }
      const command = editorCommand(event);
      return command ? run(command) : false;
    },
    !help && !walking && !exporting,
  );
  useEffect(() => listenSpaceRelease(window, document, () => canvas.current?.setSpace(false)), []);

  const cell = hover ? cellAt(doc, hover) : null;
  const at = hover && fit_ ? chunkAt(hover, fit_) : null;
  const state = dirty
    ? "Unsaved changes"
    : saved.failed
      ? "Not saved: this browser refused the draft"
      : saved.at
        ? `Saved ${saved.at.toTimeString().slice(0, 5)} (draft)`
        : "Draft";
  const fillLabel = session.tool === "fill" && session.fillOutline ? "outline" : null;
  const swatches = objectSwatches(doc);
  const swatch = swatches.find((s) => sameChoice(s.choice, session.placing));
  const armed = session.pasting
    ? "Paste: click to land, right click or Esc to cancel"
    : session.tool === "paint"
      ? `Paint: ${session.group === "terrain" ? (session.terrain === WALL ? "Wall" : "Floor") : GROUND_KINDS[session.ground]}`
      : session.tool === "fill"
        ? `Fill: ${fillLabel ?? (session.group === "terrain" ? (session.terrain === WALL ? "Wall" : "Floor") : GROUND_KINDS[session.ground])}`
        : session.tool === "place"
          ? `Place: ${packKindOf(session.placing.type ?? "")?.label ?? swatch?.label ?? OBJECT_NAMES[session.placing.kind]}`
          : TOOLS.find((t) => t.tool === session.tool)!.label;
  const box = paintedBox(doc);

  return (
    <>
      <header className="ed-bar" data-topbar="" hidden={walking}>
        <button type="button" onClick={onBack}>
          ◂ Maps
        </button>
        <span>
          <strong data-map-name="">{meta.name}</strong> · {KIND_NAMES[meta.kind]} · {doc.hexes.size}{" "}
          hexes · loc {meta.location}
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
        <ValidationLight findings={findings} onOpen={validateNow} />
        <span className="ed-spacer" />
        {problem && (
          <span className="ed-problem" role="alert">
            {problem}
          </span>
        )}
        {note && (
          <span className="ed-dim" data-note="">
            {note}
          </span>
        )}
        <button type="button" onClick={onOpenFile}>
          Open file…
        </button>
        <button type="button" data-save="" onClick={save}>
          Save
        </button>
        {session.zone && (
          <button type="button" data-export="" onClick={() => setExporting(true)}>
            Export for the chain…
          </button>
        )}
        <button type="button" aria-label="Keys" onClick={() => setHelp(true)}>
          ?
        </button>
      </header>
      <div className="ed-main" data-walking={walking ? "" : undefined}>
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
                aria-pressed={
                  session.tool === "paint" &&
                  session.group === "terrain" &&
                  session.terrain === value
                }
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
                aria-pressed={
                  session.tool === "paint" && session.group === "ground" && session.ground === value
                }
                onClick={() => session.choose("ground", value)}
              >
                <span className="ed-swatch" style={{ background: GROUND_COLOURS[g] }} />
                {g[0]!.toUpperCase() + g.slice(1)}
              </button>
            ))}
          </div>
          <div className="ed-heading">{session.zone ? "Objects" : "Town pieces"}</div>
          <div className="ed-column" data-palette-objects="">
            {swatches.map((s) => (
              <button
                key={s.id}
                type="button"
                data-swatch={`object-${s.id}`}
                aria-pressed={session.tool === "place" && sameChoice(session.placing, s.choice)}
                onClick={() => session.choosePlace(s.choice)}
              >
                {s.label}
              </button>
            ))}
            {session.zone && meta.quotas.length === 0 && (
              <span className="ed-dim">
                Add a quota in the map&apos;s properties to mark its places.
              </span>
            )}
          </div>
          <div className="ed-heading">The pack</div>
          <Palette
            thumbs={thumbs}
            armed={session.tool === "place" ? (session.placing.type ?? null) : null}
            onSelect={(kind) => {
              if (kind) session.choosePlace({ kind: PACK_KIND_OF[kind.category], type: kind.id });
            }}
          />
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
        {panel ? (
          <ValidationPanel findings={findings} onShow={show} onClose={() => setPanel(false)} />
        ) : (
          <aside className="ed-inspector" data-inspector="">
            <div className="ed-heading">
              {session.selection.hexes.size + session.selection.objects.size > 0 ||
              session.inspected
                ? "Selection"
                : "Map"}
            </div>
            <div data-selection="">
              <SelectionPanel session={session} fit={fit_} />
            </div>
            {(session.selection.hexes.size + session.selection.objects.size > 0 ||
              session.inspected) && (
              <>
                <div className="ed-heading">Map</div>
                <div>
                  {KIND_NAMES[meta.kind]} “{meta.name}”, location {meta.location}{" "}
                  <button
                    type="button"
                    data-map-properties=""
                    onClick={() => session.select(NOTHING)}
                  >
                    Properties
                  </button>
                </div>
              </>
            )}
            <div data-painted="">
              {doc.hexes.size} hexes painted
              {box ? `, ${box.x1 - box.x0 + 1} × ${box.y1 - box.y0 + 1} across` : ""}
            </div>
            <ChunksPanel session={session} fit={fit} />
            {session.zone && (
              <>
                <div className="ed-heading">Outline</div>
                {session.tool === "outline" && (
                  <button
                    type="button"
                    data-outline-from-floor=""
                    onClick={() => {
                      const entry = [...doc.objects.values()].find((o) => o.kind === "entry");
                      session.outlineFromFloor(entry?.at ?? null);
                    }}
                  >
                    Outline from floor
                  </button>
                )}
                <div className="ed-dim" data-chunk-set="">
                  {fit_
                    ? `${fit_.chunkSet.length} chunks in the set, ${fit_.masks.size} on the border`
                    : "Fit chunks to derive the chunk set."}
                </div>
              </>
            )}
          </aside>
        )}
      </div>
      <footer className="ed-bar ed-bottom" data-status="" hidden={walking}>
        {hover ? (
          <span>
            x {hover.x} y {hover.y}
            {at ? ` · chunk (${at.cx},${at.cy}) tile ${at.tile}` : ""}
            {cell === null ? " · void" : ""}
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
        <button type="button" data-walk-button="" onClick={toggleWalk}>
          [P] Walk ▸
        </button>
      </footer>
      {walking && frame && (
        <WalkScreen
          doc={doc}
          frame={frame}
          starts={starts}
          editCanvas={canvas}
          onLeave={() => setWalking(false)}
        />
      )}
      {help && <HelpDialog onClose={() => setHelp(false)} />}
      {exporting && (
        <ExportDialog
          doc={doc}
          manifest={manifest}
          findings={validate(doc, checked)}
          onLoadManifest={onLoadManifest}
          onClose={() => setExporting(false)}
        />
      )}
    </>
  );
}

/** The content manifest loaded, by its file's name, and the button that loads one (CLI-09c). */
function ManifestButton({ name, onLoad }: { name: string | null; onLoad: () => void }) {
  return (
    <button type="button" data-load-manifest="" onClick={onLoad} title="The content manifest">
      {name ? `Manifest: ${name}` : "Manifest…"}
    </button>
  );
}

/**
 * Export for the chain (§2.7, CLI-09c): the zone's Registry records as packed felts, written as the
 * converter writes them (`grimworld-records`: one `set_record(kind, id, record)` call per write, in
 * order, a multicall's calls). ENG-08's `grimworld-export` JSON is offered beside it. Both need the
 * content manifest; the records need a map the editor's checks and the converter's accept.
 */
function ExportDialog({
  doc,
  manifest,
  findings,
  onLoadManifest,
  onClose,
}: {
  doc: MapDocument;
  manifest: { name: string; value: Manifest } | null;
  findings: readonly Finding[];
  onLoadManifest: () => void;
  onClose: () => void;
}) {
  const base = fileName(doc.meta).replace(/\.grimmap\.json$/, "");
  const file = manifest ? toExport(doc, manifest.value) : null;
  const out = file && "file" in file ? convert(file.file, manifest!.value) : null;
  const { errors, warnings } = tally(findings);
  const ready = out !== null && !(out instanceof Refused) && errors === 0;
  const verdict = !manifest
    ? "Load the content manifest: the export names its records through it."
    : file && "problem" in file
      ? file.problem
      : out instanceof Refused
        ? `The converter refuses it: ${out.message}.`
        : out
          ? `${out.writes.length} records, in their order of writing.`
          : "";
  return (
    <Dialog
      title={`Export for the chain · ${doc.meta.name}`}
      confirm="Download"
      disabled={!ready}
      onCancel={onClose}
      onConfirm={() => {
        if (!ready || !file || !("file" in file)) return;
        download(`${base}.records.json`, recordsFile(out.writes, `${base}.json`));
        onClose();
      }}
    >
      <div className="ed-export" data-dialog="export">
        <p>
          Writes the zone&apos;s Registry records as packed felts: a <strong>multicall file</strong>{" "}
          (ENG-08&apos;s <code>grimworld-records</code>), one{" "}
          <code>set_record(kind, id, record)</code> call per record, in order. The content pipeline
          sends it; the editor never does.
        </p>
        <p>
          Content manifest: <ManifestButton name={manifest?.name ?? null} onLoad={onLoadManifest} />
        </p>
        <p data-export-validation="">
          Validation: {errors} errors · {warnings} warnings
        </p>
        <p data-export-verdict="" className={ready ? undefined : "ed-problem"}>
          {verdict}
        </p>
        <p>
          <button
            type="button"
            data-export-json=""
            disabled={!file || !("file" in file)}
            onClick={() => {
              if (file && "file" in file) {
                download(`${base}.json`, `${JSON.stringify(file.file, null, 1)}\n`);
              }
            }}
          >
            Download the grimworld-export JSON
          </button>
        </p>
      </div>
    </Dialog>
  );
}

/**
 * The chunks (D-216): "Fit chunks", the origin and its nudge, the counts, and the fitted rectangle
 * as a small grid of chunk cells (§2.5): whole, border, or outside.
 */
function ChunksPanel({ session, fit }: { session: EditorSession; fit: ReturnType<typeof fitted> }) {
  const origin = session.doc.origin;
  const nudge = (label: string, title: string, dx: -1 | 0 | 1, dy: -1 | 0 | 1) => (
    <button
      type="button"
      data-nudge={label}
      title={title}
      disabled={!origin}
      onClick={() => session.nudgeOrigin(dx, dy)}
    >
      {label}
    </button>
  );
  return (
    <>
      <div className="ed-heading">Chunks</div>
      <button type="button" data-fit-chunks="" onClick={() => session.fitChunks()}>
        Fit chunks [Shift+0]
      </button>
      <div data-origin="">
        {origin ? `Origin (${origin.x}, ${origin.y}), ${origin.how}` : "No chunk grid yet."}
      </div>
      <div>
        Nudge {nudge("◂", "West (Shift+←)", 1, 0)} {nudge("▸", "East (Shift+→)", -1, 0)}{" "}
        {nudge("▴", "North (Shift+↑)", 0, 1)} {nudge("▾", "South (Shift+↓)", 0, -1)}
      </div>
      {typeof fit !== "string" ? (
        <>
          <div data-fit="">
            {fit.chunks} chunks, {fit.partial} partly filled
          </div>
          <div className="ed-dim">
            {fit.width} × {fit.height} chunks from global (0, 0) at ({fit.x0}, {fit.y0})
            {fit.lowRow ? "; an empty chunk row at the foot keeps the rows' parity" : ""}
          </div>
          {session.paintedSinceOrigin && (
            <div className="ed-dim" data-fit-stale="">
              Painted since: Fit chunks again to check the best origin.
            </div>
          )}
          {fit.problems.map((p) => (
            <div key={p} className="ed-problem" data-fit-problem="">
              {p}
            </div>
          ))}
          <ChunkCells fit={fit} />
        </>
      ) : fit === "wide" ? (
        <div className="ed-problem">The painted hexes span more than 1000 hexes.</div>
      ) : null}
    </>
  );
}

/** The fitted rectangle's chunk cells: whole, border, or outside the chunk set. */
function ChunkCells({ fit }: { fit: Fitted }) {
  if (fit.width > CHUNK || fit.height > CHUNK) return null;
  const inSet = new Set(fit.chunkSet);
  const cells: ReactNode[] = [];
  // Drawn as the map: x grows West (to the left), y North (up).
  for (let cy = CHUNK - 1; cy >= 0; cy--) {
    for (let cx = CHUNK - 1; cx >= 0; cx--) {
      const chunk = CHUNK * cy + cx;
      const inside = cx < fit.width && cy < fit.height;
      const cell = !inside
        ? undefined
        : !inSet.has(chunk)
          ? "outside"
          : fit.masks.has(chunk)
            ? "border"
            : "whole";
      cells.push(
        <span key={chunk} data-cell={cell} title={inside ? `chunk ${chunk}` : undefined} />,
      );
    }
  }
  return <div className="ed-chunks">{cells}</div>;
}
