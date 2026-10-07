#!/usr/bin/env node
import { spawn } from "node:child_process";
import { realpath } from "node:fs/promises";
import { dirname, isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

export interface Receiver {
  target: "niri" | "umbriel";
  profile: string;
  context: string;
}

export interface ToggleOptions {
  mode: "on" | "off";
  receivers: Receiver[];
  material: string;
  applyCommand: string;
  node?: string;
  systemctl?: string[];
}

export type Runner = (argv: string[]) => Promise<void>;

export async function run(argv: string[]): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const child = spawn(argv[0]!, argv.slice(1), {
      stdio: "inherit",
      signal: AbortSignal.timeout(30_000),
    });
    child.on("error", reject);
    child.on("exit", (code, signal) => {
      if (code === 0) resolve();
      else reject(new Error(`${argv[0]} failed (${signal ?? code})`));
    });
  });
}

/** Explicit orchestration over existing membership APIs; no shared transaction. */
export async function toggle(options: ToggleOptions, execute: Runner = run): Promise<void> {
  if (!options.receivers.length) throw new Error("Choose at least one receiver profile");
  if (!isAbsolute(options.material) || !isAbsolute(options.applyCommand))
    throw new Error("Material and explicit compositor apply command must be absolute paths");
  if (
    new Set(options.receivers.map((receiver) => receiver.target)).size !== options.receivers.length
  )
    throw new Error("Duplicate receiver target");
  for (const receiver of options.receivers)
    if (!isAbsolute(receiver.profile) || !receiver.context)
      throw new Error("Explicit receiver profile and context are required");
  const service = (verb: string, unit: string, extra: string[] = []): Promise<void> =>
    execute([
      ...(options.systemctl ?? ["/usr/bin/sudo", "-n", "/usr/bin/systemctl"]),
      verb,
      ...extra,
      unit,
    ]);
  const membership = (command: string, receiver: Receiver): Promise<void> =>
    execute([
      options.node ?? "/usr/bin/node",
      join(options.material, "bin/keybindings.mjs"),
      command,
      "--target",
      receiver.target,
      "--profile",
      receiver.profile,
      "--context",
      receiver.context,
      "--scope",
      "user",
      ...(command === "install"
        ? ["--manifest", join(options.material, "keybinding-producer.json")]
        : ["--group", "kanata-dial"]),
    ]);
  const apply = (): Promise<void> =>
    execute([
      options.applyCommand,
      options.mode,
      ...options.receivers.flatMap((receiver) => [
        `--${receiver.target}-profile`,
        receiver.profile,
        `--${receiver.target}-context`,
        receiver.context,
      ]),
    ]);
  const safeStop = async (): Promise<void> => {
    try {
      // Stop suppresses Restart=on-failure; disable also prevents a previously
      // hand-enabled boot unit from reappearing after membership is disabled.
      await service("disable", "kanata-dial-relay.service", ["--now"]);
      // One-shot reset runs INSIDE the anchor namespace and requires observed base.
      await service("start", "kanata-dial-reset.service");
    } catch (error) {
      try {
        await service("stop", "kanata-dial.service");
      } catch (stopError) {
        throw new AggregateError(
          [error, stopError],
          "Precision reset and dial fail-safe stop failed; retain F bindings",
        );
      }
      throw new Error("Precision reset failed; dial stopped as fail-safe; F bindings retained", {
        cause: error,
      });
    }
  };
  if (options.mode === "off") {
    await safeStop();
    for (const receiver of options.receivers) await membership("disable", receiver);
    await apply();
    // Dial and namespace stay running: enhancement-only OFF, legacy fallback.
    return;
  }
  await service("stop", "kanata-dial-relay.service");
  await service("start", "kanata-dial.service");
  await safeStop();
  try {
    for (const receiver of options.receivers) {
      await membership("install", receiver);
      await membership("enable", receiver);
    }
    await apply();
    await service("start", "kanata-dial-relay.service");
  } catch (error) {
    // Never leave a possibly started/restarting relay after partial ON failure.
    try {
      await safeStop();
    } catch (stopError) {
      throw new AggregateError([error, stopError], "ON failed and reset recovery failed");
    }
    throw error;
  }
}

export async function main(args: string[]): Promise<void> {
  const { values, positionals } = parseArgs({
    args,
    allowPositionals: true,
    strict: true,
    options: {
      "niri-profile": { type: "string" },
      "umbriel-profile": { type: "string" },
      context: { type: "string", default: "user" },
      "apply-command": { type: "string" },
      material: { type: "string" },
    },
  });
  if (positionals.length !== 1 || !["on", "off"].includes(positionals[0]!))
    throw new Error(
      "Usage: toggle.ts on|off --niri-profile PATH and/or --umbriel-profile PATH --apply-command PATH",
    );
  if (!values["apply-command"])
    throw new Error("Explicit compositor apply command is required; no automatic reload default");
  const receivers: Receiver[] = [];
  for (const target of ["niri", "umbriel"] as const) {
    const profile = values[`${target}-profile`];
    if (profile) receivers.push({ target, profile, context: values.context! });
  }
  await toggle({
    mode: positionals[0] as "on" | "off",
    receivers,
    material: values.material ?? dirname(dirname(fileURLToPath(import.meta.url))),
    applyCommand: values["apply-command"],
  });
}

if (process.argv[1]) {
  void realpath(process.argv[1]).then((path) => {
    if (path === fileURLToPath(import.meta.url)) return main(process.argv.slice(2));
  });
}
