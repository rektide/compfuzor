import { RootCommand } from "@bomb.sh/tab";
import { basename } from "node:path";
import { shellQuote } from "../../files/config/keybindings/render.ts";
import { keybindingConsumers } from "./registry.ts";
import { registryPolicy } from "../registry/policy.ts";
import { inspectRegistry } from "../registry/read.ts";

export async function completeKeybindings(argv: string[]): Promise<number> {
  const tab = new RootCommand();
  const install = tab.command("install-offer", "Install an offer into advertised receivers");
  const host = tab.command("host", "Install an owned advertised consumer");
  for (const entry of [install, host]) {
    entry.option(
      "force-enable",
      "Invocation-only registration disabled override; masks remain vetoes",
    );
    entry.option("scope", "Invocation audience", (complete) => {
      complete("user", "XDG user offers");
      complete("system", "separate system offers");
    });
  }
  if (argv[0] !== "--") {
    const entry = process.argv[1]!;
    const executable = `${shellQuote(process.execPath)} ${shellQuote(entry)}${basename(entry).startsWith("compfuzor-runtime.") ? " keybindings" : ""}`;
    tab.setup("compfuzor-keybindings", executable, argv[0] ?? "bash");
    return 0;
  }
  const words = argv.slice(1);
  const scopeIndex = words.indexOf("--scope");
  const scope = scopeIndex !== -1 && words[scopeIndex + 1] === "system" ? "system" : "user";
  const view = await inspectRegistry(
    keybindingConsumers,
    registryPolicy(keybindingConsumers.collection, scope),
  );
  if (!view.complete)
    throw new Error("completion unavailable: consumer registry acquisition failed");
  install.option("target", "Receiver identity", (complete) => {
    for (const record of view.records.filter(
      (entry) => entry.state === "active" || entry.state === "disabled",
    ))
      complete(
        record.id,
        record.state === "disabled"
          ? "disabled; requires --force-enable"
          : (record.payload?.adapter ?? record.state),
      );
  });
  tab.parse(words);
  return 0;
}
