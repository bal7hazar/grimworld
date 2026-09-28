// SPK-11: starts indexer.ts as a child process and waits until it serves; stops it.
import { spawn } from "node:child_process";
import { IndexerClient } from "./client.ts";

export type RunningIndexer = { client: IndexerClient; stop: () => Promise<void>; startedAt: number };

export async function startIndexer(options: { address: string; db: string; from: number; poll?: number; quiet?: boolean }): Promise<RunningIndexer> {
  const startedAt = performance.now();
  const child = spawn(
    process.execPath,
    [
      new URL("./indexer.ts", import.meta.url).pathname,
      "--rpc", process.env.NODE_URL!,
      "--address", options.address,
      "--db", options.db,
      "--from", String(options.from),
      "--poll", String(options.poll ?? 100),
    ],
    { stdio: ["ignore", "pipe", "inherit"] },
  );
  const url = await new Promise<string>((resolve, reject) => {
    let buffer = "";
    child.stdout.on("data", (chunk) => {
      const text = String(chunk);
      if (!options.quiet || /failed|rewind/.test(text)) process.stdout.write(text);
      buffer += text;
      const match = /serving on (http:\/\/127\.0\.0\.1:\d+)/.exec(buffer);
      if (match) resolve(match[1]);
    });
    child.on("exit", (code) => reject(new Error(`indexer exited with ${code}`)));
  });
  const stop = () =>
    new Promise<void>((resolve) => {
      child.once("exit", () => resolve());
      child.kill("SIGTERM");
    });
  return { client: new IndexerClient(url), stop, startedAt };
}
