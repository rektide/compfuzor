import { createConnection, type Socket } from "node:net";
import { setTimeout as delay } from "node:timers/promises";
import { fakeKey, JsonLines, layerName, object } from "./protocol.ts";

export interface Endpoint {
  host: string;
  port: number;
}

export interface RelayOptions {
  source: Endpoint;
  target: Endpoint;
  precisionLayer?: string;
  virtualKey?: string;
  retryMs?: number;
  timeoutMs?: number;
  pollMs?: number;
  log?: (message: string) => void;
}

/** One writer owns precision-hold. TCP disconnect is NOT a fake-key lease. */
export class PrecisionRelay {
  public controller: AbortController = new AbortController();
  public sockets: Set<Socket> = new Set();
  public target: Socket | undefined;
  public sourceHeld: boolean = false;
  public sentHeld: boolean = false;
  public tasks: Promise<void>[] = [];
  public stopping: boolean = false;
  public precisionLayer: string;
  public virtualKey: string;
  public retryMs: number;
  public timeoutMs: number;
  public pollMs: number;
  public log: (message: string) => void;

  public constructor(public options: RelayOptions) {
    this.precisionLayer = options.precisionLayer ?? "dial-precision";
    this.virtualKey = options.virtualKey ?? "precision-hold";
    this.retryMs = options.retryMs ?? 500;
    this.timeoutMs = options.timeoutMs ?? 5000;
    this.pollMs = options.pollMs ?? 2000;
    this.log = options.log ?? (() => {});
    if (this.retryMs <= 0 || this.timeoutMs <= 0 || this.pollMs <= 0)
      throw new Error("Relay timing values must be positive");
  }

  public start(): void {
    if (this.tasks.length || this.stopping) throw new Error("Relay cannot be started twice");
    this.tasks = [this.follow("source"), this.follow("target")];
  }

  public write(socket: Socket, message: string): boolean {
    if (socket.destroyed || !socket.writable) return false;
    // Never accumulate an unbounded write queue. Reconnect resets uncertain state.
    if (!socket.write(message)) {
      socket.destroy(new Error("Kanata write backpressure"));
      return false;
    }
    return true;
  }

  public apply(): void {
    const held = !this.stopping && this.sourceHeld;
    if (this.target && held !== this.sentHeld) {
      if (this.write(this.target, fakeKey(this.virtualKey, held))) this.sentHeld = held;
    }
  }

  public async follow(role: "source" | "target"): Promise<void> {
    while (!this.controller.signal.aborted) {
      await this.session(role);
      if (this.controller.signal.aborted) break;
      await delay(this.retryMs, undefined, { signal: this.controller.signal }).catch(() => {});
    }
  }

  public session(role: "source" | "target"): Promise<void> {
    return new Promise((resolve) => {
      const socket = createConnection(this.options[role]);
      this.sockets.add(socket);
      const frames = new JsonLines();
      let ready = false;
      let awaiting = true;
      let deadline = Date.now() + this.timeoutMs;
      let nextPoll = Date.now() + this.pollMs;
      const timer = setInterval(
        () => {
          const now = Date.now();
          if (awaiting && now >= deadline) socket.destroy(new Error(`${role} response timeout`));
          else if (ready && !awaiting && now >= nextPoll) {
            awaiting = true;
            deadline = now + this.timeoutMs;
            this.write(socket, '{"RequestCurrentLayerName":{}}\n');
          }
        },
        Math.min(this.pollMs, this.timeoutMs, 100),
      );
      socket.on("connect", () => {
        socket.setNoDelay(true);
        if (role === "target") this.write(socket, '{"RequestFakeKeyNames":{}}\n');
        else this.write(socket, '{"RequestCurrentLayerName":{}}\n');
      });
      socket.on("data", (chunk: Buffer) => {
        try {
          for (const value of frames.push(chunk)) {
            const message = object(value);
            if (!message) throw new Error("Kanata message is not an object");
            if (message.Error || message.status === "Error")
              throw new Error(`Kanata error: ${JSON.stringify(message)}`);
            if (role === "source") {
              const layer = layerName(value);
              if (layer !== undefined) {
                ready = true;
                this.sourceHeld = layer === this.precisionLayer;
                this.apply();
              } else if (message.LayerChange || message.CurrentLayerName)
                throw new Error("Malformed layer state");
            } else if (!ready && message.FakeKeyNames) {
              const names = object(message.FakeKeyNames)?.names;
              if (!Array.isArray(names) || !names.includes(this.virtualKey))
                throw new Error(`Target does not define ${this.virtualKey}`);
              // Release stale state left by a crashed relay BEFORE reapplying snapshot.
              if (!this.write(socket, fakeKey(this.virtualKey, false))) return;
              ready = true;
              this.target = socket;
              this.sentHeld = false;
              this.apply();
            }
            // Poll replies, not unrelated notifications, prove ongoing command service.
            if ((role === "source" && !ready) || (role === "target" && !ready)) continue;
            if (message.CurrentLayerName || message.FakeKeyNames) {
              awaiting = false;
              nextPoll = Date.now() + this.pollMs;
            }
          }
        } catch (error) {
          socket.destroy(error instanceof Error ? error : new Error(String(error)));
        }
      });
      socket.on("error", (error) => this.log(`${role}: ${error.message}`));
      socket.on("close", () => {
        clearInterval(timer);
        this.sockets.delete(socket);
        if (role === "source") {
          this.sourceHeld = false;
          this.apply();
        } else if (this.target === socket) {
          this.target = undefined;
          this.sentHeld = false;
        }
        resolve();
      });
    });
  }

  public async stop(): Promise<void> {
    if (this.stopping) return;
    this.stopping = true;
    this.sourceHeld = false;
    this.apply();
    this.controller.abort();
    // A separate connection also resets if the relay's target was unhealthy.
    try {
      await resetTarget(this.options.target, this.virtualKey, this.timeoutMs);
    } finally {
      for (const socket of this.sockets) socket.destroy();
      await Promise.all(this.tasks);
    }
  }
}

/** Release then query on the same stream: command-dispatch barrier, not key-event ACK. */
export async function resetTarget(
  endpoint: Endpoint,
  virtualKey: string = "precision-hold",
  timeoutMs: number = 5000,
): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const socket = createConnection(endpoint);
    const frames = new JsonLines();
    let phase: "names" | "barrier" = "names";
    const timer = setTimeout(() => socket.destroy(new Error("Target reset timeout")), timeoutMs);
    let finished = false;
    const finish = (error?: Error): void => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      socket.destroy();
      if (error) reject(error);
      else resolve();
    };
    socket.on("connect", () => socket.write('{"RequestFakeKeyNames":{}}\n'));
    socket.on("error", finish);
    socket.on("close", () => finish(new Error("Target closed before reset barrier")));
    socket.on("data", (chunk: Buffer) => {
      try {
        for (const value of frames.push(chunk)) {
          const message = object(value);
          if (!message || message.Error || message.status === "Error")
            throw new Error(`Invalid reset response: ${JSON.stringify(value)}`);
          if (phase === "names" && message.FakeKeyNames) {
            const names = object(message.FakeKeyNames)?.names;
            if (!Array.isArray(names) || !names.includes(virtualKey))
              throw new Error(`Target does not define ${virtualKey}`);
            phase = "barrier";
            socket.write(fakeKey(virtualKey, false) + '{"RequestCurrentLayerName":{}}\n');
          } else if (
            phase === "barrier" &&
            typeof object(message.CurrentLayerName)?.name === "string"
          )
            finish();
        }
      } catch (error) {
        finish(error instanceof Error ? error : new Error(String(error)));
      }
    });
  });
}
