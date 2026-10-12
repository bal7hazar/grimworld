import { type CSSProperties, useEffect, useState } from "react";
import { AccountError } from "../account";
import { Sandbox } from "../sandbox/Sandbox";
import { ChainRefused, fetchDeployment, openChain } from "./network";
import { type ChainParam, type ChainRefusal, logRefusal, refusalLine } from "./params";
import { type Player, SetupFailed, restore } from "./setup";

/**
 * The chain mode's screen (CLI-11a): minimal in this lot. It loads the deployment, opens the node
 * (the checks of §2.2 and §2.3), restores or makes the burner's player (§3.4), and says "adventurer
 * N in instance M". A refusal leaves the sandbox on screen with one line over it, and one
 * `grimworld.chain-refused` record in the console. The map and the batch come with CLI-11c.
 *
 * Loaded by `App.tsx` with a dynamic `import()` only, so the sandbox's bundle does not carry
 * starknet.js.
 */

type Shown =
  | { readonly kind: "opening" }
  | { readonly kind: "refused"; readonly reason: ChainRefusal }
  | { readonly kind: "failed"; readonly what: string }
  | { readonly kind: "ready"; readonly player: Player };

/**
 * What failed, in words that carry no value of the node or the key: a setup step and its status,
 * an account error's code, or the error's class.
 */
function failure(error: unknown): string {
  if (error instanceof SetupFailed) return `${error.step} ${error.status}`;
  if (error instanceof AccountError) return error.code;
  return error instanceof Error ? error.name : "unknown";
}

/**
 * One start per node URL for the page's life: React's development double effect must not register
 * or enter twice.
 */
const started = new Map<string, Promise<Shown>>();

function start(nodeUrl: string): Promise<Shown> {
  let opening = started.get(nodeUrl);
  if (opening === undefined) {
    opening = (async (): Promise<Shown> => {
      try {
        const deployment = await fetchDeployment();
        const { provider, reader } = await openChain(nodeUrl, deployment);
        const player = await restore({ provider, reader, ...deployment.contracts });
        return { kind: "ready", player };
      } catch (error) {
        // A refusal before a send or a funding reaches here inside the account's error
        const refused = error instanceof AccountError ? error.cause : error;
        if (refused instanceof ChainRefused) return { kind: "refused", reason: refused.reason };
        return { kind: "failed", what: failure(error) };
      }
    })();
    started.set(nodeUrl, opening);
  }
  return opening;
}

export default function ChainScreen({ param }: { param: Exclude<ChainParam, { kind: "none" }> }) {
  const [shown, setShown] = useState<Shown>(() =>
    param.kind === "refused" ? { kind: "refused", reason: param.reason } : { kind: "opening" },
  );

  useEffect(() => {
    if (param.kind !== "chain") return;
    let alive = true;
    void start(param.nodeUrl).then((next) => {
      if (alive) setShown(next);
    });
    return () => {
      alive = false;
    };
  }, [param]);

  const refused = shown.kind === "refused" ? shown.reason : null;
  useEffect(() => {
    if (refused !== null) logRefusal(refused);
  }, [refused]);

  if (shown.kind === "refused") {
    return (
      <>
        <Sandbox />
        <div style={styles.line} data-chain="refused">
          {refusalLine(shown.reason)}
        </div>
      </>
    );
  }
  return (
    <div style={styles.page}>
      <div style={styles.line} data-chain={shown.kind}>
        {shown.kind === "opening" && "chain mode: opening…"}
        {shown.kind === "failed" && `chain mode: setup failed (${shown.what})`}
        {shown.kind === "ready" &&
          `adventurer ${shown.player.adventurerId} in instance ${shown.player.instanceId}`}
      </div>
    </div>
  );
}

const styles: Record<string, CSSProperties> = {
  page: { position: "fixed", inset: 0, background: "#1b1b1f" },
  line: {
    position: "fixed",
    right: 8,
    top: 8,
    maxWidth: "calc(100vw - 16px)",
    padding: "6px 10px",
    borderRadius: 6,
    border: "1px dashed #ff6b6b",
    font: "0.75rem ui-monospace, monospace",
    color: "#eee",
    background: "rgba(0,0,0,0.78)",
    zIndex: 10,
  },
};
