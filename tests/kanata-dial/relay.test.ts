import { createServer, type Server, type Socket } from "node:net";
import { spawn } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";
import { afterEach, describe, expect, it } from "vitest";
import { fakeKey, JsonLines, layerName, object } from "../../files/kanata-dial/protocol.ts";
import { PrecisionRelay, resetTarget, type Endpoint } from "../../files/kanata-dial/relay.ts";

async function eventually(check: () => boolean): Promise<void> {
  for (let i = 0; i < 200; i++) {
    if (check()) return;
    await delay(5);
  }
  throw new Error("Condition did not become true");
}

class Peer {
  public server: Server;
  public sockets: Set<Socket> = new Set();
  public commands: unknown[] = [];
  public actions: string[] = [];
  public layer: string = "base";
  public held: boolean = false;
  public answer: boolean = true;
  public names: string[] = ["precision-hold"];
  public processDelay: number = 0;
  public queries: string[] = [];
  public constructor(_role: "source" | "target") {
    this.server = createServer((socket) => {
      this.sockets.add(socket);
      socket.on("error", () => {});
      socket.on("close", () => this.sockets.delete(socket));
      socket.write(JSON.stringify({ LayerChange: { new: this.layer } }) + "\n");
      const frames = new JsonLines();
      socket.on("data", (chunk: Buffer) => {
        for (const value of frames.push(chunk)) {
          this.commands.push(value);
          const message = object(value)!;
          const key = object(message.ActOnFakeKey);
          if (key) {
            this.actions.push(String(key.action));
            this.held = key.action === "Press";
            const held = this.held;
            setTimeout(() => {
              this.layer = held ? "precision" : "base";
            }, this.processDelay).unref();
          }
          if (!this.answer) continue;
          if (message.RequestCurrentLayerName) {
            this.queries.push(this.layer);
            socket.write(JSON.stringify({ CurrentLayerName: { name: this.layer } }) + "\n");
          }
          if (message.RequestFakeKeyNames)
            socket.write(JSON.stringify({ FakeKeyNames: { names: this.names } }) + "\n");
        }
      });
    });
  }
  public async listen(): Promise<Endpoint> {
    await new Promise<void>((resolve) => this.server.listen(0, "127.0.0.1", resolve));
    const address = this.server.address();
    if (!address || typeof address === "string") throw new Error("No TCP address");
    return { host: "127.0.0.1", port: address.port };
  }
  public send(value: unknown): void {
    for (const socket of this.sockets) socket.write(JSON.stringify(value) + "\n");
  }
  public change(layer: string): void {
    this.layer = layer;
    this.send({ LayerChange: { new: layer } });
  }
  public disconnect(): void {
    for (const socket of this.sockets) socket.destroy();
  }
  public async close(): Promise<void> {
    this.disconnect();
    await new Promise<void>((resolve) => this.server.close(() => resolve()));
  }
}

const cleanup: (() => Promise<void>)[] = [];
afterEach(async () => {
  for (const close of cleanup.reverse()) await close();
  cleanup.length = 0;
});

async function fixture(layer: string = "base"): Promise<{
  source: Peer;
  target: Peer;
  relay: PrecisionRelay;
}> {
  const source = new Peer("source");
  const target = new Peer("target");
  source.layer = layer;
  const sourceEndpoint = await source.listen();
  const targetEndpoint = await target.listen();
  cleanup.push(
    () => source.close(),
    () => target.close(),
  );
  const relay = new PrecisionRelay({
    source: sourceEndpoint,
    target: targetEndpoint,
    retryMs: 20,
    timeoutMs: 100,
    pollMs: 30,
  });
  cleanup.push(() => relay.stop());
  relay.start();
  await eventually(() => target.actions.length > 0);
  return { source, target, relay };
}

describe("bounded Kanata framing", () => {
  it("handles fragmented/multiple frames and exact protocol spelling", () => {
    const frames = new JsonLines();
    expect(frames.push(Buffer.from('{"LayerChange":{"new":"dial-'))).toEqual([]);
    const messages = frames.push(
      Buffer.from('precision"}}\n{"CurrentLayerName":{"name":"base"}}\n'),
    );
    expect(messages.map(layerName)).toEqual(["dial-precision", "base"]);
    expect(fakeKey("precision-hold", true)).toBe(
      '{"ActOnFakeKey":{"name":"precision-hold","action":"Press"}}\n',
    );
  });
  it("rejects oversized complete and incomplete frames, bad JSON and empty lines", () => {
    expect(() => new JsonLines(8).push(Buffer.from("123456789"))).toThrow("limit");
    expect(() => new JsonLines(8).push(Buffer.from("123456789\n"))).toThrow("limit");
    expect(() => new JsonLines().push(Buffer.from("bad\n"))).toThrow();
    expect(() => new JsonLines().push(Buffer.from("\n"))).toThrow("Empty");
  });
});

describe("precision relay mock TCP lifecycle", () => {
  it("rejects a relay pointed at one instance and invalid layer names", async () => {
    const endpoint = { host: "127.0.0.1", port: 5828 };
    expect(() => new PrecisionRelay({ source: endpoint, target: endpoint })).toThrow("distinct");
    await expect(resetTarget(endpoint, "precision-hold", 100, "bad layer")).rejects.toThrow(
      "Invalid",
    );
  });
  it("waits for delayed fallback processing and rejects a target stuck on another layer", async () => {
    const target = new Peer("target");
    const endpoint = await target.listen();
    cleanup.push(() => target.close());
    target.layer = "precision";
    target.held = true;
    target.processDelay = 60;
    await resetTarget(endpoint, "precision-hold", 300);
    expect(target.queries[0]).toBe("precision");
    expect(target.queries.at(-1)).toBe("base");
    target.layer = "precision";
    target.processDelay = 1000;
    await expect(resetTarget(endpoint, "precision-hold", 70)).rejects.toThrow("timeout");
  });
  it("runs the actual system Node native-TS CLI against a mock reset endpoint", async () => {
    const target = new Peer("target");
    const endpoint = await target.listen();
    cleanup.push(() => target.close());
    const child = spawn("/usr/bin/node", ["files/kanata-dial/cli.ts", "--reset"], {
      env: { ...process.env, KANATA_DIAL_PORT: String(endpoint.port) },
    });
    let error = "";
    child.stderr.on("data", (chunk: Buffer) => {
      error += chunk.toString();
    });
    const code = await new Promise<number | null>((resolve, reject) => {
      child.on("error", reject);
      child.on("exit", resolve);
    });
    expect(error).toBe("");
    expect(code).toBe(0);
    expect(target.actions).toEqual(["Release"]);
  });
  it("resets before applying the initial held snapshot; duplicate updates do not press twice", async () => {
    const { source, target } = await fixture("dial-precision");
    await eventually(() => target.held);
    expect(target.actions.slice(0, 2)).toEqual(["Release", "Press"]);
    source.change("dial-precision");
    source.change("dial-precision");
    await delay(60);
    expect(target.actions).toEqual(["Release", "Press"]);
    source.change("base");
    await eventually(() => !target.held);
    expect(target.actions).toEqual(["Release", "Press", "Release"]);
  });
  it("releases on source loss and reapplies the fresh reconnect snapshot", async () => {
    const { source, target } = await fixture("dial-precision");
    await eventually(() => target.held);
    source.disconnect();
    await eventually(() => target.actions.includes("Release", 2));
    await eventually(() => target.actions.length >= 4);
    expect(target.actions.slice(0, 4)).toEqual(["Release", "Press", "Release", "Press"]);
  });
  it("resets stale target hold on reconnect even if source remains held", async () => {
    const { target } = await fixture("dial-precision");
    await eventually(() => target.held);
    target.disconnect(); // mock deliberately retains held fake-key state
    await eventually(() => target.actions.length >= 4);
    expect(target.actions.slice(0, 4)).toEqual(["Release", "Press", "Release", "Press"]);
  });
  it("fails closed on unknown layer and malformed source framing", async () => {
    const { source, target } = await fixture("dial-precision");
    await eventually(() => target.held);
    source.change("other-layer");
    await eventually(() => !target.held);
    source.change("dial-precision");
    await eventually(() => target.held);
    source.layer = "base";
    for (const socket of source.sockets) socket.write("invalid\n");
    await eventually(() => !target.held);
  });
  it("detects an unresponsive source through bounded poll deadlines", async () => {
    const { source, target, relay } = await fixture("dial-precision");
    await eventually(() => target.held);
    source.answer = false;
    source.layer = "base";
    await eventually(() => !target.held);
    expect(relay.sourceHeld).toBe(false);
    source.answer = true;
  });
  it("releases cleanly on shutdown and has a separate reset dispatch barrier", async () => {
    const { target, relay } = await fixture("dial-precision");
    await eventually(() => target.held);
    await relay.stop();
    expect(target.held).toBe(false);
    const commands = target.commands.map((message) => Object.keys(object(message)!)[0]);
    expect(commands.at(-1)).toBe("RequestCurrentLayerName");
    expect(commands.lastIndexOf("ActOnFakeKey")).toBeGreaterThan(
      commands.lastIndexOf("RequestFakeKeyNames"),
    );
  });
  it("reset rejects absent key, socket loss and timeout instead of claiming safe OFF", async () => {
    const target = new Peer("target");
    const endpoint = await target.listen();
    cleanup.push(() => target.close());
    target.names = [];
    await expect(resetTarget(endpoint, "precision-hold", 100)).rejects.toThrow("does not define");
    target.names = ["precision-hold"];
    target.answer = false;
    await expect(resetTarget(endpoint, "precision-hold", 30)).rejects.toThrow("timeout");
    await eventually(() => target.sockets.size === 0);
    const pending = resetTarget(endpoint, "precision-hold", 100);
    await eventually(() => target.sockets.size > 0);
    target.disconnect();
    await expect(pending).rejects.toThrow("closed");
  });
});
