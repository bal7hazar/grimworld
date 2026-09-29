import ts from "typescript";
import { describe, expect, it } from "vitest";

// ADR-0005 §1: no vendor library outside the module, and no vendor type out of it.
const sources = import.meta.glob<string>(["./*.ts", "!./*.test.ts"], {
  query: "?raw",
  import: "default",
  eager: true,
});
const app = import.meta.glob<string>(["../**/*.{ts,tsx}", "!../account/**", "!../**/*.test.ts"], {
  query: "?raw",
  import: "default",
  eager: true,
});

const IMPORTS_STARKNET = /from\s+["'](starknet|@starknet-io\/[^"']*)["']/;
const VENDOR_FILE =
  /node_modules\/(\.pnpm\/[^/]+\/node_modules\/)?(starknet|@starknet-io|@noble|@scure)\//;
const HERE = new URL(".", import.meta.url).pathname;

const OPTIONS: ts.CompilerOptions = {
  target: ts.ScriptTarget.ES2023,
  module: ts.ModuleKind.ESNext,
  moduleResolution: ts.ModuleResolutionKind.Bundler,
  lib: ["lib.es2023.d.ts", "lib.dom.d.ts"],
  types: [],
  strict: true,
  skipLibCheck: true,
  noEmit: true,
};

/** A program over real files and, for the fixtures, files that exist only in memory. */
function program(roots: string[], virtual: Record<string, string> = {}): ts.Program {
  const host = ts.createCompilerHost(OPTIONS);
  const { getSourceFile, fileExists, readFile } = host;
  host.getSourceFile = (name, language, ...rest) =>
    name in virtual
      ? ts.createSourceFile(name, virtual[name]!, language)
      : getSourceFile.call(host, name, language, ...rest);
  host.fileExists = (name) => name in virtual || fileExists.call(host, name);
  host.readFile = (name) => virtual[name] ?? readFile.call(host, name);
  return ts.createProgram([...roots, ...Object.keys(virtual)], OPTIONS, host);
}

function diagnostics(p: ts.Program): string[] {
  return ts
    .getPreEmitDiagnostics(p)
    .map((d) => ts.flattenDiagnosticMessageText(d.messageText, "\n"));
}

/**
 * Every declaration of a vendor's library that a type reaches: through members, index signatures,
 * call and construct signatures, unions and intersections, and type arguments, as deep as they go.
 * A type declared by a library (the vendor's or TypeScript's own) is not entered: a vendor's is
 * reported, a standard one (`Promise`, `Error`) is seen through its type arguments only.
 */
function vendorOrigins(
  checker: ts.TypeChecker,
  type: ts.Type,
  seen = new Set<ts.Type>(),
): string[] {
  if (seen.has(type)) return [];
  seen.add(type);
  const found: string[] = [];
  const declared = [type.getSymbol(), type.aliasSymbol].flatMap((symbol) =>
    (symbol?.getDeclarations() ?? []).map((d) => ({
      symbol: symbol!,
      file: d.getSourceFile().fileName,
    })),
  );
  for (const { symbol, file } of declared) {
    if (VENDOR_FILE.test(file)) found.push(`${symbol.getName()} (${file})`);
  }
  if (found.length > 0) return found;
  const walk = (inner: ts.Type | undefined) => {
    if (inner) found.push(...vendorOrigins(checker, inner, seen));
  };
  // A generic parameter carries its constraint and its default (fix loop 2, F-4).
  if (type.flags & ts.TypeFlags.TypeParameter) {
    walk(type.getConstraint());
    walk(type.getDefault());
  }
  type.aliasTypeArguments?.forEach(walk);
  if (type.isUnionOrIntersection()) type.types.forEach(walk);
  if (type.flags & ts.TypeFlags.Object) {
    if ((type as ts.ObjectType).objectFlags & ts.ObjectFlags.Reference) {
      checker.getTypeArguments(type as ts.TypeReference).forEach(walk);
    }
    const ours = declared.every(({ file }) => !file.includes("node_modules"));
    if (ours) {
      for (const member of type.getProperties()) walk(checker.getTypeOfSymbol(member));
      for (const info of checker.getIndexInfosOfType(type)) {
        walk(info.keyType);
        walk(info.type);
      }
      for (const signature of [...type.getCallSignatures(), ...type.getConstructSignatures()]) {
        signature.getTypeParameters()?.forEach(walk);
        walk(signature.getReturnType());
        for (const parameter of signature.getParameters()) walk(checker.getTypeOfSymbol(parameter));
      }
    }
  }
  return found;
}

/** What each export of a file reaches of a vendor's types, as `export: origin`. */
function leaks(p: ts.Program, file: string): string[] {
  const checker = p.getTypeChecker();
  const module = checker.getSymbolAtLocation(p.getSourceFile(file)!);
  if (!module) throw new Error(`${file} is not a module`);
  const found: string[] = [];
  for (const alias of checker.getExportsOfModule(module)) {
    const symbol = alias.flags & ts.SymbolFlags.Alias ? checker.getAliasedSymbol(alias) : alias;
    const declaration = symbol.getDeclarations()![0]!;
    const types: ts.Type[] = [];
    if (
      symbol.flags &
      (ts.SymbolFlags.Interface | ts.SymbolFlags.TypeAlias | ts.SymbolFlags.Class)
    ) {
      types.push(checker.getDeclaredTypeOfSymbol(symbol));
    }
    if (symbol.flags & ts.SymbolFlags.Value) {
      types.push(checker.getTypeOfSymbolAtLocation(symbol, declaration));
    }
    // The generic parameters of the exported declarations themselves (an interface, an alias, a
    // class, a function): their constraints and defaults.
    for (const node of symbol.getDeclarations() ?? []) {
      for (const parameter of ts.getEffectiveTypeParameterDeclarations(
        node as ts.DeclarationWithTypeParameters,
      )) {
        types.push(checker.getTypeAtLocation(parameter));
      }
    }
    const seen = new Set<ts.Type>();
    for (const type of types) {
      found.push(...vendorOrigins(checker, type, seen).map((o) => `${alias.getName()}: ${o}`));
    }
  }
  return found;
}

describe("the vendor stays inside", () => {
  it("only starknet.ts imports the chain library", () => {
    const importers = Object.entries(sources)
      .filter(([, text]) => IMPORTS_STARKNET.test(text))
      .map(([path]) => path);
    expect(importers).toEqual(["./starknet.ts"]);
  });

  it("nothing else in the app imports it but the chain door of NS-1", () => {
    const importers = Object.entries(app)
      .filter(([, text]) => IMPORTS_STARKNET.test(text))
      .map(([path]) => path);
    expect(importers).toEqual(["../chain.ts"]);
  });

  it("no type the module exports reaches a type of the library", () => {
    const index = `${HERE}index.ts`;
    const p = program([index]);
    // An unresolved import would turn a vendor type into `any` and hide it: none is allowed.
    expect(diagnostics(p)).toEqual([]);
    const names = p
      .getTypeChecker()
      .getExportsOfModule(p.getTypeChecker().getSymbolAtLocation(p.getSourceFile(index)!)!)
      .map((s) => s.getName());
    expect(names).toEqual(expect.arrayContaining(["createStarknetChain", "AccountProvider"]));
    expect(leaks(p, index)).toEqual([]);
  }, 30_000);

  // Negative fixtures (fix loop 1, F-4): each hides a vendor type in one of the ways a type can
  // carry another; the traversal must find every one, and must find nothing in the clean one.
  it("finds a vendor type however an exported type carries it", () => {
    const fixture = (name: string, body: string) => ({
      [`${HERE}__fixture_${name}.ts`]: `import type { Account } from "starknet";\n${body}\n`,
    });
    const fixtures = {
      ...fixture("direct", "export interface Direct { account: Account }"),
      ...fixture("index", "export interface Indexed { [name: string]: Account }"),
      ...fixture("number", "export type Listed = { readonly [i: number]: Account };"),
      ...fixture("construct", "export interface Constructed { new (): Account }"),
      ...fixture("parameter", "export interface Takes { new (account: Account): object }"),
      ...fixture("class", "export class Built { constructor(account: Account) { void account; } }"),
      ...fixture("promise", "export function later(): Promise<Account> { throw 0; }"),
      ...fixture("deep", "export type Deep = { outer: { inner: [string, Account | null] } };"),
      // Fix loop 2, F-4: generic parameters' constraints and defaults (the audit's two first).
      ...fixture("constraint", "export interface Leak { <T extends Account>(account: T): T }"),
      ...fixture("default", "export type Leak<T = Account> = { value: T };"),
      ...fixture("unused_constraint", "export interface Holder<T extends Account> { n: number }"),
      ...fixture("unused_default", "export class Box<T = Account> { n = 0; }"),
      ...fixture("function", "export function f<T extends Account>(): void {}"),
      ...fixture("method", "export type Runner = { run<T extends Account | string>(): void };"),
      ...fixture("nested", "export type Outer<U extends { inner: Account }> = U[];"),
      [`${HERE}__fixture_clean.ts`]:
        "export interface Clean { a: string; [k: string]: string; }\n" +
        "export interface Made { new (x: number): Clean }\n" +
        "export function later(): Promise<Clean> { throw 0; }\n" +
        'export type Ok<T extends string = "a"> = { v: T; f<U extends Clean>(u: U): U };\n',
    };
    const p = program([], fixtures);
    expect(diagnostics(p)).toEqual([]);
    const clean = `${HERE}__fixture_clean.ts`;
    expect(leaks(p, clean)).toEqual([]);
    // Every leaking fixture must be detected; the misses are listed together.
    const missed = Object.keys(fixtures)
      .filter((file) => file !== clean && leaks(p, file).length === 0)
      .map((file) => file.slice(HERE.length));
    expect(missed).toEqual([]);
  }, 30_000);

  it("a fixture that does not compile fails the check", () => {
    const p = program([], {
      [`${HERE}__fixture_broken.ts`]:
        'import type { Missing } from "starknet";\nexport interface X { m: Missing }\n',
    });
    expect(diagnostics(p).length).toBeGreaterThan(0);
  }, 30_000);
});
