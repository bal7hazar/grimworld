// Starts the indexer (src/main.ts, run by Node as it is) as a child process of the scenario, and
// stops it by its own pid. The child's environment is INDEXER_RPC_URL and nothing else: the
// scenario's environment holds the node account's key, which the indexer never sees.
import { spawn, type ChildProcess } from "node:child_process";

export type RunningIndexer = {
  url: string;
  logs: string[];
  pid: number;
  stop: () => Promise<number | null>;
};

const MAIN = new URL("../src/main.ts", import.meta.url).pathname;

export async function startIndexer(options: {
  command: "run" | "rebuild";
  rpcUrl: string;
  hub: string;
  market: string;
  from: number;
  db: string;
  poll?: number;
  depth?: number | "l1";
  /** More options of `run` (the subscriptions' caps). */
  extra?: string[];
}): Promise<RunningIndexer> {
  const child: ChildProcess = spawn(
    process.execPath,
    [
      MAIN,
      options.command,
      "--hub",
      options.hub,
      "--market",
      options.market,
      "--from",
      String(options.from),
      "--db",
      options.db,
      "--poll",
      String(options.poll ?? 50),
      "--depth",
      String(options.depth ?? 100_000),
      ...(options.extra ?? []),
    ],
    {
      stdio: ["ignore", "pipe", "pipe"],
      env: { INDEXER_RPC_URL: options.rpcUrl },
    },
  );
  const logs: string[] = [];
  const url = await new Promise<string>((resolve, reject) => {
    let buffer = "";
    const read = (chunk: Buffer) => {
      const text = String(chunk);
      logs.push(...text.split("\n").filter(Boolean));
      buffer += text;
      const match = /serving on (http:\/\/127\.0\.0\.1:\d+)/.exec(buffer);
      if (match) resolve(match[1]!);
    };
    child.stdout!.on("data", read);
    child.stderr!.on("data", read);
    child.once("exit", (code) =>
      reject(new Error(`indexer exited with ${code}: ${logs.join("\n")}`)),
    );
  });
  const stop = () =>
    new Promise<number | null>((resolve) => {
      if (child.exitCode !== null) return resolve(child.exitCode);
      child.once("exit", (code) => resolve(code));
      child.kill("SIGTERM");
    });
  return { url, logs, pid: child.pid!, stop };
}

export type Answer = { code: number; body: Record<string, unknown> };

export async function get(url: string, path: string): Promise<Answer> {
  const response = await fetch(`${url}${path}`);
  return {
    code: response.status,
    body: (await response.json()) as Record<string, unknown>,
  };
}
