// SPK-11: the game client's side of the indexer: one query (the cheapest open lots of an item), the
// hub presence count, and the subscription to lots (posted, closed, rewound), over server-sent
// events. A browser would use `EventSource`; Node reads the same stream with `fetch`.
export type Head = { number: number; hash: string } | null;
export type Lot = { lot: number; item: number; quantity: number; price: string; block: number };
export type LotEvent =
  | { type: "head"; data: Head }
  | { type: "posted"; data: Lot }
  | { type: "closed"; data: { lot: number; item: number; sold: boolean; block: number } }
  | { type: "rewind"; data: { to: number; head: Head; retracted: number[] } };

export class IndexerClient {
  readonly url: string;
  constructor(url: string) {
    this.url = url;
  }

  async head(): Promise<Head> {
    return (await this.get("/head")).head;
  }

  /** The cheapest open lots of `item`, cheapest first, ties by lot id; with the head they were read at. */
  async cheapest(item: number, limit = 1): Promise<{ head: Head; lots: Lot[] }> {
    return this.get(`/lots/cheapest?item=${item}&limit=${limit}`);
  }

  async presence(hub: number): Promise<{ head: Head; count: number }> {
    return this.get(`/hubs/presence?hub=${hub}`);
  }

  async stats(): Promise<any> {
    return this.get("/stats");
  }

  /** Calls `onEvent` for every event of the stream until `signal` aborts. */
  async subscribe(onEvent: (event: LotEvent) => void, signal: AbortSignal): Promise<void> {
    const response = await fetch(`${this.url}/lots/subscribe`, { signal });
    if (!response.ok || !response.body) throw new Error(`subscribe: ${response.status}`);
    const decoder = new TextDecoder();
    let buffer = "";
    try {
      for await (const chunk of response.body) {
        buffer += decoder.decode(chunk, { stream: true });
        let end: number;
        while ((end = buffer.indexOf("\n\n")) >= 0) {
          const frame = buffer.slice(0, end);
          buffer = buffer.slice(end + 2);
          const type = /^event: (.*)$/m.exec(frame)?.[1];
          const data = /^data: (.*)$/m.exec(frame)?.[1];
          if (type && data) onEvent({ type, data: JSON.parse(data) } as LotEvent);
        }
      }
    } catch (error) {
      if (!signal.aborted) throw error;
    }
  }

  private async get(path: string): Promise<any> {
    const response = await fetch(`${this.url}${path}`);
    if (!response.ok) throw new Error(`${path}: ${response.status}`);
    return response.json();
  }
}
