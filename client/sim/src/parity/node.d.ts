// The functions of `node:fs` the harness uses, declared here rather than adding `@types/node` to
// the package: `client/sim` runs in a browser too, and only the reader and the mutation check, run
// by the tests in Node, touch a file (mandate §6: no I/O elsewhere in `src`).
// With `lib` ES2023 alone (no DOM, no Node), the reader's `URL` and `import.meta.url` are declared
// here as well, as much as it uses of them.
interface ImportMeta {
  readonly url: string;
}

declare class URL {
  constructor(url: string, base?: string | URL);
  readonly href: string;
  readonly pathname: string;
}

// The mutation check and the measurements (`bench/`) print their tables for the report, timed by
// the measurements alone.
declare const console: { log(...data: unknown[]): void };
declare const performance: { now(): number };

declare module "node:fs" {
  export function existsSync(path: URL): boolean;
  export function readFileSync(path: URL, encoding: "utf8"): string;
  export function readdirSync(path: URL, options: { recursive: true }): string[];
}

// The mutation check's pool of workers (`mutants.test.ts`) and the worker's module hooks
// (`mutate.ts`), as much as they use.
declare module "node:os" {
  export function availableParallelism(): number;
}

declare module "node:worker_threads" {
  export class Worker {
    constructor(url: URL);
    postMessage(value: unknown): void;
    on(event: "message", listener: (value: never) => void): this;
    on(event: "error", listener: (error: Error) => void): this;
    terminate(): Promise<number>;
  }
  export const parentPort: {
    on(event: "message", listener: (value: never) => void): void;
    postMessage(value: unknown): void;
  } | null;
}

declare module "node:module" {
  type Resolved = { url: string; format?: string; shortCircuit?: boolean };
  type Loaded = { format: string; source?: string; shortCircuit?: boolean };
  export function registerHooks(hooks: {
    resolve(
      specifier: string,
      context: { parentURL?: string },
      nextResolve: (specifier: string, context: { parentURL?: string }) => Resolved,
    ): Resolved;
    load(url: string, context: object, nextLoad: (url: string, context: object) => Loaded): Loaded;
  }): void;
  export function stripTypeScriptTypes(
    code: string,
    options: { mode: "strip" | "transform"; sourceUrl?: string },
  ): string;
}
