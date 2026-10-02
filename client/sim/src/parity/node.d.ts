// The two functions of `node:fs` the harness's reader uses, declared here rather than adding
// `@types/node` to the package: `client/sim` runs in a browser too, and only the reader, run by
// the tests in Node, reads a file (mandate §6: no I/O elsewhere in `src`).
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

declare module "node:fs" {
  export function existsSync(path: URL): boolean;
  export function readFileSync(path: URL, encoding: "utf8"): string;
}
