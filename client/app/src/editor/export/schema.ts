import kindsText from "./kinds.json?raw";
import schemaText from "./schema.json?raw";
import { Refused } from "./records";

/**
 * ENG-08's schema (`grimworld-export` v1) and kind table, as track game publishes them under
 * `spikes/SPK-16-authored-zone/map-format/` (then `tools/map-format/`). The two JSON files beside
 * this one are copies, never edited here: `export.test.ts` holds them equal to track game's.
 *
 * `validate` is a port of `map-format/schema_check.py`: the JSON Schema subset the schema uses, the
 * same verdict and the same refusal code (`export: schema`).
 */

type Schema = Readonly<Record<string, unknown>>;

export const SCHEMA = JSON.parse(schemaText) as Schema;

/** The kind table (`kinds.json`): props with `blocks`, buildings, NPCs, bridges. */
export interface KindTable {
  readonly props: Readonly<Record<string, { variants: number; blocks: boolean; turn: string }>>;
  readonly buildings: readonly string[];
  readonly npcs: readonly string[];
  readonly bridges: Readonly<Record<string, { deck: number }>>;
}

export const KIND_TABLE = JSON.parse(kindsText) as KindTable;

const isDict = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const isInt = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v);

function typeOk(value: unknown, kind: string): boolean {
  switch (kind) {
    case "integer":
      return isInt(value);
    case "null":
      return value === null;
    case "object":
      return isDict(value);
    case "array":
      return Array.isArray(value);
    case "string":
      return typeof value === "string";
    case "boolean":
      return typeof value === "boolean";
    default:
      return false;
  }
}

const show = (v: unknown) => JSON.stringify(v);
const fail = (detail: string): never => {
  throw new Refused("export: schema", detail);
};

/** Throws `Refused("export: schema", …)` at the first place `value` breaks `schema`. */
export function validate(value: unknown, schema: Schema = SCHEMA, root = schema, path = "$"): void {
  if (typeof schema.$ref === "string") {
    const name = schema.$ref.split("/").pop()!;
    const defs = root.$defs as Record<string, Schema>;
    validate(value, defs[name]!, root, path);
    return;
  }
  if (Array.isArray(schema.oneOf)) {
    const errors: string[] = [];
    for (const option of schema.oneOf as Schema[]) {
      try {
        validate(value, option, root, path);
        return;
      } catch (e) {
        if (!(e instanceof Refused)) throw e;
        errors.push(e.detail);
      }
    }
    fail(`${path}: no form matches (${errors[0]})`);
  }
  const kind = schema.type as string | string[] | undefined;
  if (kind !== undefined) {
    const kinds = Array.isArray(kind) ? kind : [kind];
    if (!kinds.some((k) => typeOk(value, k))) fail(`${path}: not ${show(kind)}`);
  }
  if ("const" in schema && value !== schema.const) fail(`${path}: not ${show(schema.const)}`);
  if (Array.isArray(schema.enum) && !schema.enum.includes(value)) {
    fail(`${path}: ${show(value)} not in ${show(schema.enum)}`);
  }
  if (isInt(value)) {
    if (typeof schema.minimum === "number" && value < schema.minimum) {
      fail(`${path}: below ${schema.minimum}`);
    }
    if (typeof schema.maximum === "number" && value > schema.maximum) {
      fail(`${path}: above ${schema.maximum}`);
    }
  }
  if (typeof value === "string") {
    // Python's `len` counts code points, as `[...value]` does.
    const length = [...value].length;
    if (typeof schema.minLength === "number" && length < schema.minLength) {
      fail(`${path}: shorter than ${schema.minLength}`);
    }
    if (typeof schema.maxLength === "number" && length > schema.maxLength) {
      fail(`${path}: longer than ${schema.maxLength}`);
    }
    // JSON Schema's `pattern` is a search, not a full match: the schema anchors its patterns.
    if (typeof schema.pattern === "string" && !new RegExp(schema.pattern, "u").test(value)) {
      fail(`${path}: does not match ${schema.pattern}`);
    }
  }
  if (isDict(value)) {
    for (const key of (schema.required as string[] | undefined) ?? []) {
      if (!(key in value)) fail(`${path}: ${key} missing`);
    }
    const props = (schema.properties ?? {}) as Record<string, Schema>;
    for (const [key, item] of Object.entries(value)) {
      if (Object.hasOwn(props, key)) validate(item, props[key]!, root, `${path}.${key}`);
      else if (schema.additionalProperties === false) fail(`${path}: unknown key ${key}`);
    }
  }
  if (Array.isArray(value)) {
    if (typeof schema.minItems === "number" && value.length < schema.minItems) {
      fail(`${path}: fewer than ${schema.minItems} items`);
    }
    if (typeof schema.maxItems === "number" && value.length > schema.maxItems) {
      fail(`${path}: more than ${schema.maxItems} items`);
    }
    if (isDict(schema.items)) {
      value.forEach((item, i) => validate(item, schema.items as Schema, root, `${path}[${i}]`));
    }
  }
}
