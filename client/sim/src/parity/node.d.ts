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

// The mutation check prints its table for the report.
declare const console: { log(...data: unknown[]): void };

declare module "node:fs" {
  export function existsSync(path: URL): boolean;
  export function readFileSync(path: URL, encoding: "utf8"): string;
  export function writeFileSync(path: URL, data: string): void;
  export function mkdirSync(path: URL, options: { recursive: true }): void;
  export function readdirSync(path: URL, options: { recursive: true }): string[];
  export function rmSync(path: URL, options: { recursive: true; force: true }): void;
}
