import { ChainRefused } from "./network";

/**
 * The credit of the burner's adventurer (CLI-11d3): the app's side of the development server's
 * `/devnet/credit` (`src/dev/credit.ts`), which runs track game's `devnet_deploy.py --credit-only`
 * node-side. The app sends the adventurer's id and nothing else; account 0's calls are the
 * script's alone. The node test reaches the same runner without HTTP (`CreditRequest`).
 */

/** The credits on the node: `running` while one runs, `unusable` once one was killed. */
export interface CreditStatus {
  readonly state: "idle" | "running" | "unusable";
  /** Credits started so far: a change between two reads means one ran in between. */
  readonly credits: number;
}

export interface Credit {
  /** Credits SEED-02's gold and pack to the adventurer, inside an instance; resolves once done. */
  credit(adventurerId: number): Promise<void>;
  status(): Promise<CreditStatus>;
  /** Refuses (`ChainRefused`) once the devnet was left mid-credit (caveat c). */
  assertUsable(): Promise<void>;
}

/** One request to the endpoint: its method and body, the answer's status and body. */
export type CreditRequest = (
  method: "GET" | "POST",
  body?: string,
) => Promise<{ readonly status: number; readonly body: string }>;

/** The credit did not run: the endpoint's line (the script's last `devnet_deploy:` line). */
export class CreditFailed extends Error {
  constructor(readonly line: string) {
    super(`credit: ${line}`);
    this.name = "CreditFailed";
  }
}

/** The development server's endpoint, through `fetch`. */
export function httpCreditRequest(
  fetchImpl: typeof fetch = globalThis.fetch.bind(globalThis),
  url = "/devnet/credit",
): CreditRequest {
  return async (method, body) => {
    const response = await fetchImpl(url, {
      method,
      headers: { "content-type": "application/json", accept: "application/json" },
      ...(body === undefined ? {} : { body }),
    });
    return { status: response.status, body: await response.text() };
  };
}

const errorOf = (body: string): string => {
  try {
    const { error } = JSON.parse(body) as { error?: unknown };
    if (typeof error === "string") return error;
  } catch {
    // not the endpoint's JSON
  }
  return "no credit endpoint";
};

export function createCredit(request: CreditRequest): Credit {
  async function status(): Promise<CreditStatus> {
    const answer = await request("GET");
    if (answer.status !== 200) throw new CreditFailed(errorOf(answer.body));
    let parsed: unknown;
    try {
      parsed = JSON.parse(answer.body);
    } catch {
      throw new CreditFailed("no credit endpoint");
    }
    const { state, credits } = (parsed ?? {}) as { state?: unknown; credits?: unknown };
    if (
      (state !== "idle" && state !== "running" && state !== "unusable") ||
      typeof credits !== "number" ||
      !Number.isSafeInteger(credits)
    ) {
      throw new CreditFailed("no credit endpoint");
    }
    return { state, credits };
  }
  return {
    async credit(adventurerId) {
      const answer = await request("POST", JSON.stringify({ adventurer: adventurerId }));
      if (answer.status === 409) throw new ChainRefused("devnet left mid-credit: redeploy");
      if (answer.status !== 200) throw new CreditFailed(errorOf(answer.body));
    },
    status,
    async assertUsable() {
      if ((await status()).state === "unusable") {
        throw new ChainRefused("devnet left mid-credit: redeploy");
      }
    },
  };
}
