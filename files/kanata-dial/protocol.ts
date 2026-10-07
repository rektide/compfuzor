/** Kanata 2f84d17 server messages are newline-delimited UTF-8 JSON. */
export class JsonLines {
  public pending: Buffer = Buffer.alloc(0);

  public constructor(public limit: number = 64 * 1024) {}

  public push(chunk: Buffer): unknown[] {
    const data = Buffer.concat([this.pending, chunk]);
    const messages: unknown[] = [];
    let start = 0;
    for (let end = data.indexOf(10); end !== -1; end = data.indexOf(10, start)) {
      if (end - start > this.limit) throw new Error("Kanata frame exceeds limit");
      const line = data.subarray(start, end).toString("utf8");
      if (!line.trim()) throw new Error("Empty Kanata frame");
      messages.push(JSON.parse(line));
      start = end + 1;
    }
    if (data.length - start > this.limit) throw new Error("Kanata frame exceeds limit");
    this.pending = Buffer.from(data.subarray(start));
    return messages;
  }
}

export function object(value: unknown): Record<string, unknown> | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

export function layerName(value: unknown): string | undefined {
  const message = object(value);
  const layer = object(message?.LayerChange);
  const current = object(message?.CurrentLayerName);
  const name = layer?.new ?? current?.name;
  return typeof name === "string" ? name : undefined;
}

export function fakeKey(name: string, held: boolean): string {
  return JSON.stringify({ ActOnFakeKey: { name, action: held ? "Press" : "Release" } }) + "\n";
}
