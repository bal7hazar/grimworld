// TEST SCAFFOLDING (FND-MUT): the worker thread that runs mutants for the mutation check
// (`mutants.test.ts`), loaded by Node itself, not by vitest. No mutant is written to disk: a module
// hook serves each mutant's sources from memory. A module that does not import the mutated file,
// directly or through others, behaves the same in every mutant, so it is loaded once per worker and
// shared; the mutated file and the modules that import it are loaded again for each mutant, under
// the URL query `?mutant=<index>`. Node transforms the TypeScript (type stripping, in its
// `transform` mode for the parameter properties), each source once per worker. A worker runs at
// most a few dozen mutants, then exits: the modules of a realm cannot be unloaded, so a worker's
// memory grows with each mutant, and the pool (`mutants.test.ts`) bounds it by starting fresh ones.
//
// The worker imports nothing of `src/` itself, so that it is never one of the modules it mutates.

import { readFileSync, readdirSync } from "node:fs";
import { registerHooks, stripTypeScriptTypes } from "node:module";
import { parentPort } from "node:worker_threads";

/** A mutant as the worker receives it: one replacement of `from` by `to` in `file`. */
export type Job = {
  index: number;
  file: string;
  from: string;
  to: string;
  /** The unit tests' cases that must kill it, besides the tables that must not. */
  kind?: "refusal" | "seam" | "trap";
};

/** What killed a mutant: the case, and whether the copy crashed rather than diverged. */
export type Kill = { by: string; crash: boolean };

/** A worker's answer for one job. */
export type Verdict = {
  index: number;
  /** The first divergence of the tables, or `null` when they all replay. */
  tables: Kill | null;
  /** The first case of the job's `kind` the mutant no longer holds; `null` when it holds them all. */
  unit: Kill | null;
  /** The mutant could not be loaded at all (a bad import, a syntax error): no verdict. */
  load?: string;
};

const SRC = new URL("../", import.meta.url).href;

/** Every module of `src/` the mutants may load, by its path under `src/`. */
const SOURCES = new Map<string, string>(
  readdirSync(new URL(SRC), { recursive: true })
    .filter((path) => path.endsWith(".ts") && !path.endsWith(".test.ts") && !path.endsWith(".d.ts"))
    .map((path) => [path, readFileSync(new URL(path, SRC), "utf8")]),
);

/** The path under `src/` of a module's URL, its query dropped. */
const pathOf = (url: string): string => url.slice(SRC.length).split("?")[0]!;

/** The module a relative specifier of `parent` names: `x.ts`, `x/index.ts`, or `x` as written. */
function target(specifier: string, parent: string): string {
  const url = new URL(specifier, parent.split("?")[0]).href;
  for (const candidate of [`${url}.ts`, `${url}/index.ts`, url]) {
    if (SOURCES.has(pathOf(candidate))) return candidate;
  }
  throw new Error(`mutate: ${specifier} from ${pathOf(parent)}: no such module of src/`);
}

/** The modules of `src/` each module imports (its `import … from` and `export … from`). */
const IMPORTS = new Map<string, string[]>(
  [...SOURCES].map(([path, text]) => [
    path,
    [...text.matchAll(/\bfrom\s+"(\.{1,2}\/[^"]*)"/g)].map((m) =>
      pathOf(target(m[1]!, new URL(path, SRC).href)),
    ),
  ]),
);

/** The mutated file and every module that imports it, directly or not: what a mutant reloads. */
function closure(file: string): Set<string> {
  const reached = new Set([file]);
  for (let grew = true; grew;) {
    grew = false;
    for (const [path, imports] of IMPORTS) {
      if (!reached.has(path) && imports.some((i) => reached.has(i))) {
        reached.add(path);
        grew = true;
      }
    }
  }
  return reached;
}

const jobs = new Map<string, { job: Job; reloads: Set<string> }>();
const compiled = new Map<string, string>();

/** A source as JavaScript; an unmutated source is transformed once per worker. */
function compile(path: string, text: string, mutated: boolean): string {
  const cached = mutated ? undefined : compiled.get(path);
  if (cached !== undefined) return cached;
  const js = stripTypeScriptTypes(text, { mode: "transform", sourceUrl: path });
  if (!mutated) compiled.set(path, js);
  return js;
}

registerHooks({
  resolve(specifier, context, nextResolve) {
    const parent = context.parentURL;
    if (parent === undefined || !parent.startsWith(SRC) || !specifier.startsWith(".")) {
      return nextResolve(specifier, context);
    }
    const url = target(specifier, parent);
    const query = parent.includes("?") ? parent.slice(parent.indexOf("?")) : "";
    const tagged = query !== "" && jobs.get(query)!.reloads.has(pathOf(url));
    return { url: tagged ? url + query : url, format: "module", shortCircuit: true };
  },
  load(url, context, nextLoad) {
    if (!url.startsWith(SRC)) return nextLoad(url, context);
    const path = pathOf(url);
    const text = SOURCES.get(path);
    if (text === undefined) return nextLoad(url, context);
    const query = url.includes("?") ? url.slice(url.indexOf("?")) : "";
    const job = query === "" ? undefined : jobs.get(query)!.job;
    const mutated = job !== undefined && job.file === path;
    const source = mutated ? text.replace(job.from, job.to) : text;
    return { format: "module", source: compile(path, source, mutated), shortCircuit: true };
  },
});

/** The case a thrown error names, and whether it is a crash: a TypeError, a ReferenceError, a
 * SyntaxError, on its own or as the cause of the replay's report. A RangeError is the mirror's
 * own refusal of a value (`felt.ts`), a divergence like a Cairo panic. */
function kill(by: string, error: unknown): Kill {
  let crash = false;
  for (let e: unknown = error; e instanceof Error; e = e.cause) {
    if (e instanceof TypeError || e instanceof ReferenceError || e instanceof SyntaxError) {
      crash = true;
    }
  }
  // A report that prints a whole ground or words is cut: its start names the case
  return { by: by.length > 240 ? `${by.slice(0, 240)}…` : by, crash };
}

const message = (error: unknown): string =>
  error instanceof Error ? error.message : `threw ${String(error)}`;

type Check = { name: string; run: () => void };

/** The modules a mutant runs: the harness of `parity/`, reloaded where the mutant reaches it. */
type Parity = {
  replay: (entry: unknown, vectors: unknown) => unknown;
  readTable: (file: string) => unknown;
  TABLES: readonly { file: string }[];
  refusals: { REFUSALS: readonly unknown[]; refused: (refusal: unknown) => void };
  seam: { CHECKS: readonly Check[]; holds: (check: Check) => void };
  trapcases: { CHECKS: readonly Check[]; holds: (check: Check) => void };
};

async function load(job: Job): Promise<Parity> {
  const query = `?mutant=${job.index}`;
  const text = SOURCES.get(job.file);
  if (text === undefined || text.split(job.from).length !== 2) {
    throw new Error(`"${job.from}" is not once in ${job.file}`);
  }
  jobs.set(query, { job, reloads: closure(job.file) });
  const entry = (name: string) => {
    const path = `parity/${name}.ts`;
    return import(new URL(path, SRC).href + (jobs.get(query)!.reloads.has(path) ? query : ""));
  };
  const [replay, table, tables, refusals, seam, trapcases] = await Promise.all(
    ["replay", "table", "tables", "refusals", "seam", "trapcases"].map(entry),
  );
  return {
    replay: replay.replay,
    readTable: table.readTable,
    TABLES: tables.TABLES,
    refusals,
    seam,
    trapcases,
  };
}

/** The first divergence the vectors find, or `null` when the mutant survives. */
function killer(parity: Parity): Kill | null {
  for (const entry of parity.TABLES) {
    try {
      parity.replay(entry, parity.readTable(entry.file));
    } catch (error) {
      return kill(message(error).split(": case")[0]!.split(": threw")[0]!, error);
    }
  }
  return null;
}

/** The first refusal of `parity/refusals.ts` the copy no longer makes, or `null`. */
function refusalKiller(parity: Parity): Kill | null {
  for (const refusal of parity.refusals.REFUSALS) {
    try {
      parity.refusals.refused(refusal);
    } catch (error) {
      return kill(`refusals: ${message(error)}`, error);
    }
  }
  return null;
}

/** The first case of a list of checks (`parity/seam.ts`, `parity/trapcases.ts`) the copy no longer
 * holds, or `null`: its name, then what failed, as the check reports it. */
function checkKiller(kind: string, list: Parity["seam"]): Kill | null {
  for (const check of list.CHECKS) {
    try {
      list.holds(check);
    } catch (error) {
      const text = message(error);
      return kill(
        `${kind}: ${text.startsWith(check.name) ? text : `${check.name}: ${text}`}`,
        error,
      );
    }
  }
  return null;
}

async function run(job: Job): Promise<Verdict> {
  let parity: Parity;
  try {
    parity = await load(job);
  } catch (error) {
    return { index: job.index, tables: null, unit: null, load: String(error) };
  }
  const unit =
    job.kind === "trap"
      ? checkKiller("trap", parity.trapcases)
      : job.kind === "seam"
        ? checkKiller("seam", parity.seam)
        : job.kind === "refusal"
          ? refusalKiller(parity)
          : null;
  return { index: job.index, tables: killer(parity), unit };
}

// One mutant at a time, in the order received: the pool sends a worker its whole batch at once
let queue = Promise.resolve();
parentPort?.on("message", (job: Job) => {
  queue = queue.then(() => run(job)).then((verdict) => parentPort!.postMessage(verdict));
});
