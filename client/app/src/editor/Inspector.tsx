import { useEffect, useState } from "react";
import type { Tile } from "../render/view";
import { type Fitted, chunkAt } from "./fit";
import {
  BIOMES,
  type Biome,
  FLOOR,
  GROUND_KINDS,
  type MapDocument,
  NAME_MAX,
  WALL,
  groundOfCell,
  isOutside,
  keyOf,
  objectsAt,
  terrainOf,
  tileOfKey,
} from "./model";
import {
  type MapObject,
  OBJECT_NAMES,
  QUOTA_KINDS,
  QUOTA_NAMES,
  type QuotaKind,
  kindOf,
} from "./objects";
import type { EditorSession } from "./session";
import { QUOTAS_MAX, WALKABLE_SHARE } from "./validate";

/**
 * The inspector (CLI-09b, brief §2.4): what the selection holds, each field editable in place, one
 * step of the undo history per edit. One hex, one object, a group; nothing selected, the map's
 * properties.
 */

/** A whole number typed in place: written on Enter or when the field is left. */
function NumberField({
  label,
  value,
  min = 0,
  onCommit,
  name,
}: {
  label: string;
  value: number;
  min?: number;
  onCommit: (value: number) => void;
  name: string;
}) {
  const [text, setText] = useState(String(value));
  useEffect(() => setText(String(value)), [value]);
  const commit = () => {
    const n = Number(text);
    if (Number.isInteger(n) && n >= min) onCommit(n);
    else setText(String(value));
  };
  return (
    <label className="ed-field">
      <span>{label}</span>
      <input
        name={name}
        inputMode="numeric"
        size={6}
        value={text}
        onChange={(e) => setText(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => {
          if (e.key === "Enter") {
            commit();
            e.currentTarget.blur();
          }
        }}
      />
    </label>
  );
}

function Choice<T extends string>({
  label,
  value,
  options,
  names,
  onChange,
  name,
}: {
  label: string;
  value: T;
  options: readonly T[];
  names?: Readonly<Record<string, string>>;
  onChange: (value: T) => void;
  name: string;
}) {
  return (
    <label className="ed-field">
      <span>{label}</span>
      <select
        name={name}
        value={value}
        onChange={(e) => {
          onChange(e.target.value as T);
          // A focused field takes every key (`ignoredTarget`): give the keys back.
          e.currentTarget.blur();
        }}
      >
        {options.map((o) => (
          <option key={o} value={o}>
            {names?.[o] ?? o}
          </option>
        ))}
      </select>
    </label>
  );
}

const cap = (s: string) => s[0]!.toUpperCase() + s.slice(1);

/** One object's fields (§2.4, §4.2, §4.3), as its kind's row lists them (`KINDS`). */
function ObjectFields({
  session,
  id,
  object,
}: {
  session: EditorSession;
  id: number;
  object: MapObject;
}) {
  const spec = kindOf(object);
  const values = object as unknown as Readonly<Record<string, unknown>>;
  const edit = (key: string, value: unknown) =>
    session.editObject(id, { ...object, [key]: value } as MapObject);
  return (
    <div data-object={object.kind}>
      <div>
        <strong>{spec.name}</strong> at ({object.at.x}, {object.at.y})
      </div>
      {spec.fields.map((field) => {
        const name = `${object.kind}-${field.key}`;
        const value = values[field.key];
        switch (field.type) {
          case "number":
            return (
              <NumberField
                key={field.key}
                name={name}
                label={field.label}
                value={value as number}
                onCommit={(v) => edit(field.key, v)}
              />
            );
          case "toggle":
            return (
              <label key={field.key} className="ed-field">
                <span>{field.label}</span>
                <input
                  type="checkbox"
                  name={name}
                  checked={value as boolean}
                  onChange={(e) => {
                    edit(field.key, e.target.checked);
                    e.currentTarget.blur();
                  }}
                />
              </label>
            );
          case "choice": {
            const options = field.options(session.doc.meta, object);
            const current = String(value);
            // A value the list lacks (a file's) stays shown, as it is.
            const all = options.some(([v]) => v === current)
              ? options
              : [[current, current] as const, ...options];
            return (
              <Choice
                key={field.key}
                name={name}
                label={field.label}
                value={current}
                options={all.map(([v]) => v)}
                names={Object.fromEntries(all)}
                onChange={(v) => edit(field.key, field.numeric ? Number(v) : v)}
              />
            );
          }
        }
      })}
      {spec.note && <div className="ed-dim">{spec.note}</div>}
      <button type="button" data-delete="" onClick={() => session.deleteSelection()}>
        Delete
      </button>
    </div>
  );
}

/** A hex's fields (§2.4): its place in the fitted map, terrain, ground, outline, objects. */
function HexFields({
  session,
  tile,
  fit,
}: {
  session: EditorSession;
  tile: Tile;
  fit: Fitted | null;
}) {
  const doc = session.doc;
  const cell = doc.hexes.get(keyOf(tile));
  const at = fit ? chunkAt(tile, fit) : null;
  const one = () => session.select({ hexes: new Set([keyOf(tile)]), objects: new Set() }, tile);
  return (
    <div data-hex="">
      <div>
        <strong>
          Hex ({tile.x}, {tile.y})
        </strong>
      </div>
      <div className="ed-dim">
        {at
          ? `global (${at.x}, ${at.y}) · chunk ${at.chunk} (${at.cx},${at.cy}) · tile ${at.tile}`
          : "no chunk grid yet"}
      </div>
      {cell === undefined ? (
        <div className="ed-dim">Not painted (void)</div>
      ) : (
        <>
          <Choice
            name="hex-terrain"
            label="Terrain"
            value={terrainOf(cell) === WALL ? "wall" : "floor"}
            options={["floor", "wall"] as const}
            names={{ floor: "Floor", wall: "Wall" }}
            onChange={(v) => {
              one();
              session.paintSelection({ layer: "terrain", value: v === "wall" ? WALL : FLOOR });
            }}
          />
          <Choice
            name="hex-ground"
            label="Ground"
            value={GROUND_KINDS[groundOfCell(cell)]!}
            options={GROUND_KINDS}
            onChange={(g) => {
              one();
              session.paintSelection({ layer: "ground", value: GROUND_KINDS.indexOf(g) });
            }}
          />
          <div>Obstacle: {doc.obstacles.get(keyOf(tile)) ?? "auto"}</div>
          {session.zone && <div>Outline: {isOutside(cell) ? "outside" : "inside"}</div>}
        </>
      )}
      <div>
        Objects:{" "}
        {objectsAt(doc, tile)
          .map((id) => OBJECT_NAMES[doc.objects.get(id)!.kind])
          .join(", ") || "none"}
      </div>
    </div>
  );
}

/** A group (§2.4): counts by kind; Delete; Set terrain, Set ground. */
function GroupFields({ session }: { session: EditorSession }) {
  const { hexes, objects } = session.selection;
  const counts = new Map<string, number>();
  for (const id of objects) {
    const kind = session.doc.objects.get(id)?.kind;
    if (kind) counts.set(OBJECT_NAMES[kind], (counts.get(OBJECT_NAMES[kind]) ?? 0) + 1);
  }
  return (
    <div data-group="">
      <div>
        <strong>{hexes.size} hexes</strong>
        {[...counts].map(([name, n]) => `, ${n} × ${name}`).join("")}
      </div>
      <div className="ed-row">
        <button type="button" data-delete="" onClick={() => session.deleteSelection()}>
          Delete
        </button>
        <button type="button" onClick={() => session.mirror()}>
          Mirror
        </button>
      </div>
      {hexes.size > 0 && (
        <>
          <div className="ed-row">
            Set terrain to{" "}
            <button
              type="button"
              data-set-terrain="floor"
              onClick={() => session.paintSelection({ layer: "terrain", value: FLOOR })}
            >
              Floor
            </button>
            <button
              type="button"
              data-set-terrain="wall"
              onClick={() => session.paintSelection({ layer: "terrain", value: WALL })}
            >
              Wall
            </button>
          </div>
          <div className="ed-row">
            Set ground to{" "}
            {GROUND_KINDS.map((g, value) => (
              <button
                key={g}
                type="button"
                onClick={() => session.paintSelection({ layer: "ground", value })}
              >
                {cap(g)}
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

/** Nothing selected (§2.4): the map's properties, and for a zone its quotas and walkable share. */
function MapFields({ session }: { session: EditorSession }) {
  const doc = session.doc;
  const meta = doc.meta;
  const [name, setName] = useState(meta.name);
  useEffect(() => setName(meta.name), [meta.name]);
  const quotas = meta.quotas;
  return (
    <div data-map-fields="">
      <label className="ed-field">
        <span>Name</span>
        <input
          name="map-name"
          value={name}
          maxLength={NAME_MAX}
          onChange={(e) => setName(e.target.value)}
          onBlur={() => {
            const trimmed = name.trim();
            if (trimmed.length > 0) session.editMeta({ ...meta, name: trimmed });
            else setName(meta.name);
          }}
        />
      </label>
      <NumberField
        name="map-location"
        label="Location id"
        value={meta.location}
        onCommit={(location) => session.editMeta({ ...meta, location })}
      />
      <NumberField
        name="map-region"
        label="Region id"
        value={meta.region}
        onCommit={(region) => session.editMeta({ ...meta, region })}
      />
      {session.zone && (
        <>
          <Choice
            name="map-biome"
            label="Biome"
            value={meta.biome ?? "meadow"}
            options={BIOMES}
            names={Object.fromEntries(BIOMES.map((b) => [b, cap(b)]))}
            onChange={(biome: Biome) => session.editMeta({ ...meta, biome })}
          />
          <NumberField
            name="map-level-min"
            label="Level min"
            value={meta.levelMin}
            onCommit={(levelMin) => session.editMeta({ ...meta, levelMin })}
          />
          <NumberField
            name="map-level-max"
            label="Level max"
            value={meta.levelMax}
            onCommit={(levelMax) => session.editMeta({ ...meta, levelMax })}
          />
          <NumberField
            name="map-rank"
            label="Rank required"
            value={meta.rank}
            onCommit={(rank) => session.editMeta({ ...meta, rank })}
          />
          <NumberField
            name="map-spawn-table"
            label="Spawn table"
            value={meta.spawnTable}
            onCommit={(spawnTable) => session.editMeta({ ...meta, spawnTable })}
          />
          <div className="ed-heading">
            Quotas ({quotas.length} of {QUOTAS_MAX})
          </div>
          {quotas.map((q, i) => {
            const candidates = [...doc.objects.values()].filter(
              (o) => o.kind === "candidate" && o.quota === i,
            ).length;
            const set = (next: Partial<typeof q>) =>
              session.editMeta({
                ...meta,
                quotas: quotas.map((x, j) => (j === i ? { ...x, ...next } : x)),
              });
            return (
              <div key={i} className="ed-quota" data-quota={i}>
                <div>
                  <strong>Q{i + 1}</strong> · {candidates} candidate places{" "}
                  <button type="button" onClick={() => session.removeQuota(i)}>
                    Remove
                  </button>
                </div>
                <Choice
                  name={`quota-${i}-kind`}
                  label="Kind"
                  value={q.kind}
                  options={QUOTA_KINDS}
                  names={QUOTA_NAMES}
                  onChange={(kind: QuotaKind) => set({ kind })}
                />
                <NumberField
                  name={`quota-${i}-param`}
                  label="Parameter"
                  value={q.param}
                  onCommit={(param) => set({ param })}
                />
                <NumberField
                  name={`quota-${i}-count`}
                  label="Count"
                  value={q.count}
                  onCommit={(count) => set({ count })}
                />
              </div>
            );
          })}
          <button
            type="button"
            data-add-quota=""
            onClick={() =>
              session.editMeta({
                ...meta,
                quotas: [...quotas, { kind: "exit", param: 0, count: 1 }],
              })
            }
          >
            + Quota
          </button>
          <WalkableShare doc={doc} />
        </>
      )}
    </div>
  );
}

/** The walkable share of the outline against design/18's range (a hint, never an error). */
function WalkableShare({ doc }: { doc: MapDocument }) {
  let inside = 0;
  let floor = 0;
  for (const cell of doc.hexes.values()) {
    if (isOutside(cell)) continue;
    inside += 1;
    if (terrainOf(cell) === FLOOR) floor += 1;
  }
  const range = doc.meta.biome ? WALKABLE_SHARE[doc.meta.biome] : undefined;
  if (!range || inside === 0) return null;
  return (
    <div className="ed-dim" data-walkable-share="">
      Walkable share {Math.round((100 * floor) / inside)} % ({doc.meta.biome} {range[0]}–{range[1]}{" "}
      %)
    </div>
  );
}

/** The selection's panel, or the map's properties. */
export function SelectionPanel({ session, fit }: { session: EditorSession; fit: Fitted | null }) {
  const { hexes, objects } = session.selection;
  const total = hexes.size + objects.size;
  if (objects.size === 1 && hexes.size === 0) {
    const id = [...objects][0]!;
    const object = session.doc.objects.get(id);
    if (object) return <ObjectFields key={id} session={session} id={id} object={object} />;
  }
  if (total > 1) return <GroupFields session={session} />;
  const tile = hexes.size === 1 ? tileOfKey([...hexes][0]!) : session.inspected;
  if (tile) return <HexFields session={session} tile={tile} fit={fit} />;
  return <MapFields session={session} />;
}
