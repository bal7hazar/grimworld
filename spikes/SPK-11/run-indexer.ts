// SPK-11: starts indexer.ts as a child process and waits until it serves; stops it.
// The child gets an explicit environment: INDEXER_RPC_URL and nothing else. The scenarios' own
// environment holds the node's pre-funded account key (NODE_ACCOUNT_PRIVATE_KEY): the indexer
// never sees it. The RPC URL goes through the environment, not argv (visible in `ps`).
import { spawn } from "node:child_process";
import { IndexerClient } from "./client.ts";

export type RunningIndexer = { client: IndexerClient; stop: () => Promise<void>; logs: string[] };

export async function startIndexer(options: {
  address: string;
  db: string;
  from: number;
  rpcUrl?: string;
  poll?: number;
  rpcDelay?: number;
  quiet?: boolean;
}): Promise<RunningIndexer> {
  const child = spawn(
    process.execPath,
    [
      new URL("./indexer.ts", import.meta.url).pathname,
      "--address", options.address,
      "--db", options.db,
      "--from", String(options.from),
      "--poll", String(options.poll ?? 100),
      "--rpc-delay", String(options.rpcDelay ?? 0),
    ],
    { stdio: ["ignore", "pipe", "pipe"], env: { INDEXER_RPC_URL: options.rpcUrl ?? process.env.NODE_URL! } },
  );
  const logs: string[] = [];
  const url = await new Promise<string>((resolve, reject) => {
    let buffer = "";
    const read = (chunk: Buffer) => {
      const text = String(chunk);
      logs.push(...text.split("\n").filter(Boolean));
      if (!options.quiet || /failed|rewind|status|environment|serving/.test(text)) process.stdout.write(text);
      buffer += text;
      const match = /serving on (http:\/\/127\.0\.0\.1:\d+)/.exec(buffer);
      if (match) resolve(match[1]);
    };
    child.stdout.on("data", read);
    child.stderr.on("data", read);
    child.on("exit", (code) => reject(new Error(`indexer exited with ${code}`)));
  });
  const stop = () =>
    new Promise<void>((resolve) => {
      if (child.exitCode !== null) return resolve();
      child.once("exit", () => resolve());
      child.kill("SIGTERM");
    });
  return { client: new IndexerClient(url, process.env.NODE_URL!), stop, logs };
}
