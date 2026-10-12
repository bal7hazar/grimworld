import type { AccountProvider, ExecutionId, ExecutionStatus } from "../account/types";
import type { PlayAction } from "../preview/actions";
import { type PlayTarget, previewCalls } from "../preview/calls";
import { assembleContent } from "../preview/content";
import { type MirrorState, featuresAround } from "../preview/mirror";
import type { BlockId, Reader } from "../preview/read";
import {
  type ParityLog,
  type Predict,
  type Reconciliation,
  consoleParityLog,
  reconcile,
} from "../preview/reconcile";
import { createRpc } from "../preview/rpc";
import { type ChainOutcome, type InvokeTrace, TraceError, extractOutcome } from "../preview/trace";
import type { InstanceView } from "../preview/view";

/**
 * The sent batch and the state read back (CLI-11 §5 stage 3, §6.1). The execution makes the
 * preview's own two calls, `[play, instance_state]` (D-274: accepted for devnet), and its result is
 * read from the transaction's trace by the same `extractOutcome`, then reconciled with the same
 * prediction. The state after is that trace's `instance_state`: the state of that very execution.
 * The region is read once it succeeded, pinned to the receipt's block hash, and so is the content
 * version of the next batch.
 *
 * The account provider and the chain check are injected (§2.3): `assertChain` is awaited before
 * every `execute`, so the refusal of a mainnet chain id holds whoever built the provider. Nothing
 * here imports the chain library, and no key passes through it.
 */

/** What a batch runs on: where `play` is sent, and the mirror's inputs. */
export interface ChainState {
  readonly target: PlayTarget;
  readonly mirror: MirrorState;
}

/** The ids `readState` reads by. */
export interface StateIds {
  readonly instances: string;
  readonly registry: string;
  readonly instanceId: bigint;
  readonly adventurerId: number;
}

/**
 * The state a batch runs on, read through `reader` (pinned to one block, or a tag): the view, the
 * controlled member, the region, the content version and the batch's content. `known` skips the
 * reads of what the caller already holds (the view a trace gave, the member, which no batch
 * changes). A content the Registry cannot complete (a trap skill it lacks) is left out: the mirror
 * then says what it cannot predict, the simulation still tells.
 */
export async function readState(
  reader: Reader,
  ids: StateIds,
  known: { view?: InstanceView; member?: number } = {},
): Promise<ChainState> {
  const [view, member, region, version] = await Promise.all([
    known.view ?? reader.instanceState(ids.instances, ids.instanceId),
    known.member ??
      reader.placement(ids.instances, ids.adventurerId).then((placement) => placement.member),
    reader.region(ids.instances, ids.instanceId),
    reader.contentVersion(ids.registry),
  ]);
  let content: MirrorState["content"];
  try {
    const ground = featuresAround({ view, member, region });
    content = (
      await assembleContent(view, (kind, id) => reader.record(ids.registry, kind, id), ground)
    ).content;
  } catch (error) {
    if (!(error instanceof Error && error.name === "NotMirrored")) throw error;
  }
  return {
    target: {
      instances: ids.instances,
      instanceId: ids.instanceId,
      adventurerId: ids.adventurerId,
      sequence: view.header.sequence,
      version,
    },
    mirror: { view, member, region, ...(content === undefined ? {} : { content }) },
  };
}

/** What the sender reads of a sent execution, beyond the provider's `status`. */
export interface SentReads {
  /** `starknet_traceTransaction`. */
  trace(id: ExecutionId): Promise<InvokeTrace>;
  /** The block hash of the execution's receipt (`starknet_getTransactionReceipt`). */
  blockOf(id: ExecutionId): Promise<string>;
}

/** `SentReads` over a node's JSON-RPC; the execution id is the transaction hash (the burner's). */
export function createSentReads(nodeUrl: string, fetchImpl?: typeof fetch): SentReads {
  const rpc = createRpc(String(nodeUrl), fetchImpl ?? globalThis.fetch.bind(globalThis));
  return {
    async trace(id) {
      const trace = (await rpc("starknet_traceTransaction", { transaction_hash: id })) as
        | InvokeTrace
        | undefined;
      if (trace?.execute_invocation === undefined) {
        throw new TraceError("the node returned no invoke trace");
      }
      return trace;
    },
    async blockOf(id) {
      const receipt = (await rpc("starknet_getTransactionReceipt", { transaction_hash: id })) as {
        block_hash?: unknown;
      };
      if (typeof receipt.block_hash !== "string") {
        throw new TraceError("the receipt names no block");
      }
      return receipt.block_hash;
    },
  };
}

/** The sent outcome differs from the simulated one: something moved between the two. */
export type SentRecord = {
  kind: "grimworld.sent-differs";
  actions: readonly PlayAction[];
  /** The fields that differ, as paths (`batch.played`, `view.members.0.state`). */
  fields: string[];
  simulated: ChainOutcome;
  sent: ChainOutcome;
};

export type SentLog = (record: SentRecord) => void;

export const consoleSentLog: SentLog = (record) => console.warn(record.kind, record);

export interface SendDeps {
  readonly account: Pick<AccountProvider, "execute" | "status">;
  /** The refusal of any chain but a test one (CLI-11a's `assertTestChain`), awaited first. */
  readonly assertChain: () => Promise<void>;
  readonly reads: SentReads;
  /** A reader pinned to `block`: the region and the content version after the batch. */
  readonly readerAt: (block: BlockId) => Reader;
  readonly registry: string;
  readonly log?: ParityLog;
  readonly sentLog?: SentLog;
  /** Between two `status` questions, in milliseconds (100 by default). */
  readonly poll?: number;
  /** The questions asked before giving up on a settled status (600 by default: one minute). */
  readonly polls?: number;
}

export interface SendInput {
  readonly state: ChainState;
  readonly actions: readonly PlayAction[];
  /** The prediction the preview made on `state`, reconciled again with the sent outcome. */
  readonly predict?: Predict;
  /** The simulated outcome of the same batch, which the preview showed. */
  readonly simulated: ChainOutcome;
}

export type Sent =
  /** Nothing was sent: the chain check refused, or the provider refused the execution. */
  | { kind: "refused"; reason: string }
  /** Sent, and it did not succeed: `failed` (reverted), `unknown` (dropped) or still `pending`. */
  | { kind: "unsettled"; id: ExecutionId; status: Exclude<ExecutionStatus, "succeeded"> }
  /** Sent and settled: the chain's outcome, reconciled, and the state after. */
  | ({
      kind: "sent";
      id: ExecutionId;
      blockHash: string;
      /** The fields where the sent outcome differs from the simulated one (none, usually). */
      differs: string[];
      after: ChainState;
    } & Reconciliation);

export const NO_FUNDS = "no funds";

/** RPC errors of a fee the account cannot pay: `INSUFFICIENT_RESOURCES_FOR_VALIDATE`, `…_BALANCE`. */
const FEE_CODES = new Set([53, 54]);

/**
 * Why the provider refused an execution, in one line of the panel: "no funds" for a fee the burner
 * cannot pay (§3.3), the provider's own neutral message otherwise. The cause is not shown.
 */
function refusalOf(error: unknown): string {
  const cause = (error as { cause?: { code?: unknown; message?: unknown } } | undefined)?.cause;
  const code = typeof cause?.code === "number" ? cause.code : undefined;
  const message = typeof cause?.message === "string" ? cause.message : "";
  if ((code !== undefined && FEE_CODES.has(code)) || /insufficient|balance|max fee/i.test(message)) {
    return NO_FUNDS;
  }
  return error instanceof Error ? error.message : String(error);
}

/** Every leaf where `a` and `b` differ, as a dotted path; bigints and numbers compared as they are. */
export function differences(a: unknown, b: unknown, path = ""): string[] {
  if (Object.is(a, b)) return [];
  if (typeof a !== "object" || typeof b !== "object" || a === null || b === null) {
    return [path === "" ? "(outcome)" : path];
  }
  if (Array.isArray(a) !== Array.isArray(b)) return [path];
  const keys = [...new Set([...Object.keys(a), ...Object.keys(b)])];
  return keys.flatMap((key) =>
    differences(
      (a as Record<string, unknown>)[key],
      (b as Record<string, unknown>)[key],
      path === "" ? key : `${path}.${key}`,
    ),
  );
}

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Sends the batch, waits until it settles, and reads its outcome and the state after. The chain
 * check runs before `execute`; a refusal sends nothing. The node's or the provider's failures past
 * the send (an unreadable trace, a node that went away) throw.
 */
export async function sendBatch(input: SendInput, deps: SendDeps): Promise<Sent> {
  const calls = previewCalls(input.state.target, input.actions);
  if (calls === undefined) return { kind: "refused", reason: "the batch does not encode" };
  try {
    await deps.assertChain();
  } catch (error) {
    return { kind: "refused", reason: error instanceof Error ? error.message : String(error) };
  }
  let id: ExecutionId;
  try {
    id = await deps.account.execute(calls);
  } catch (error) {
    return { kind: "refused", reason: refusalOf(error) };
  }
  let status: ExecutionStatus = "pending";
  for (let asked = 0; asked < (deps.polls ?? 600); asked++) {
    status = await deps.account.status(id);
    if (status === "succeeded" || status === "failed") break;
    await wait(deps.poll ?? 100);
  }
  if (status !== "succeeded") return { kind: "unsettled", id, status };
  const [trace, blockHash] = await Promise.all([deps.reads.trace(id), deps.reads.blockOf(id)]);
  const outcome = extractOutcome(trace);
  const reconciliation = reconcile(
    outcome,
    input.actions,
    input.predict,
    deps.log ?? consoleParityLog,
  );
  const differs = differences(input.simulated, outcome);
  if (differs.length > 0) {
    (deps.sentLog ?? consoleSentLog)({
      kind: "grimworld.sent-differs",
      actions: input.actions,
      fields: differs,
      simulated: input.simulated,
      sent: outcome,
    });
  }
  const { target, mirror } = input.state;
  const ids = { ...target, registry: deps.registry };
  const after =
    outcome.kind === "played"
      ? await readState(deps.readerAt({ blockHash }), ids, {
          view: outcome.view,
          member: mirror.member,
        })
      : await readState(deps.readerAt({ blockHash }), ids, { member: mirror.member });
  return { kind: "sent", id, blockHash, differs, after, ...reconciliation };
}
