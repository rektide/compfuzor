#!/usr/bin/env node
import { realpath } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { PrecisionRelay, resetTarget, type Endpoint } from "./relay.ts";

export function endpoint(prefix: string): Endpoint {
  const port = Number(process.env[`${prefix}_PORT`]);
  if (!Number.isInteger(port) || port < 1 || port > 65535)
    throw new Error(`${prefix}_PORT must be an explicit TCP port (1–65535)`);
  const host = process.env[`${prefix}_HOST`] ?? "127.0.0.1";
  if (host !== "127.0.0.1" && host !== "::1")
    throw new Error("Only loopback endpoints are supported");
  return { host, port };
}

export async function main(args: string[]): Promise<void> {
  if (args.length > 1 || (args.length === 1 && args[0] !== "--reset"))
    throw new Error("Usage: cli.ts [--reset]; set KANATA_DIAL_PORT and KANATA_KEYBOARD_PORT");
  const target = endpoint("KANATA_DIAL");
  const virtualKey = process.env.KANATA_DIAL_VIRTUAL_KEY ?? "precision-hold";
  const fallbackLayer = process.env.KANATA_DIAL_FALLBACK_LAYER ?? "base";
  if (args[0] === "--reset") return resetTarget(target, virtualKey, 5000, fallbackLayer);
  const relay = new PrecisionRelay({
    source: endpoint("KANATA_KEYBOARD"),
    target,
    virtualKey,
    fallbackLayer,
    precisionLayer: process.env.KANATA_PRECISION_LAYER ?? "dial-precision",
    log: (message) => console.error(message),
  });
  const stop = (): void => {
    void relay.stop().catch((error: unknown) => {
      console.error(error);
      process.exitCode = 1;
    });
  };
  process.once("SIGINT", stop);
  process.once("SIGTERM", stop);
  relay.start();
  await Promise.all(relay.tasks);
}

if (process.argv[1]) {
  void realpath(process.argv[1]).then((path) => {
    if (path === fileURLToPath(import.meta.url)) return main(process.argv.slice(2));
  });
}
