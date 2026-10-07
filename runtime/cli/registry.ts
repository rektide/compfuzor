#!/usr/bin/env node
/** Runnable Router inspection/owner-registration frontend. Domain execution remains downstream. */
import { realpath } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import {
  argument,
  command,
  multiple,
  name,
  option,
  parse,
  route,
  routes,
  schema,
  toggle,
} from "@bomb.sh/router";
import { RootCommand } from "@bomb.sh/tab";
import { Schema } from "effect";
import { keybindingConsumers, keybindingProviders } from "../keybindings/registry.ts";
import { zimProviders } from "../zim/registry.ts";
import { explicitPolicy, registryPolicy } from "../registry/policy.ts";
import { inspectRegistry, lookup } from "../registry/read.ts";
import { planRegistration, register } from "../registry/register.ts";
import type { Domain, Scope } from "../registry/model.ts";

const definitions: readonly { name: string; domain: Domain<unknown> }[] = [
  { name: "keybinding-providers", domain: keybindingProviders },
  { name: "keybinding-consumers", domain: keybindingConsumers },
  { name: "zim-providers", domain: zimProviders },
];
const text = Schema.toStandardSchemaV1(Schema.String);
const strings = Schema.toStandardSchemaV1(Schema.UndefinedOr(Schema.Array(Schema.String)));
const optionalText = Schema.toStandardSchemaV1(Schema.UndefinedOr(Schema.String));
const scope = Schema.toStandardSchemaV1(Schema.Literals(["user", "system"]));
const collection = Schema.toStandardSchemaV1(
  Schema.Literals(["keybinding-providers", "keybinding-consumers", "zim-providers"]),
);
const common = () =>
  [
    option(name("collection"), schema(collection)),
    option(name("scope"), schema(scope)),
    option(name("root"), multiple(), schema(strings)),
    option(name("write-root"), schema(optionalText)),
    toggle(name("json")),
  ] as const;
const verbs = ["list", "explain", "register", "status", "complete"] as const;
const registryRoute = route(
  name("registry"),
  routes(
    command(name("list"), ...common()),
    command(name("explain"), argument(name("id"), schema(text)), ...common()),
    command(name("register"), option(name("source"), schema(text)), ...common()),
    command(name("status"), option(name("source"), schema(text)), ...common()),
    command(name("complete"), option(name("word"), multiple(), schema(strings)), ...common()),
  ),
);

export const REGISTRY_USAGE = `Registry inspection and owner registration (no native installation)
node runtime/cli/registry.ts <list|explain ID|register|status|complete> \\
  --collection <keybinding-providers|keybinding-consumers|zim-providers> --scope <user|system>
  [--root /absolute/low --root /absolute/high --write-root /absolute/low] [--json]
register/status require --source /absolute/owner/descriptor.json
Explicit roots replace XDG lookup; write-root must be one of those roots.
complete accepts repeated --word values for tab's synchronous completion driver.`;

export async function main(
  argv: string[],
  env: Record<string, string | undefined> = { ...process.env },
): Promise<number> {
  const parsed = parse(registryRoute, { argv });
  if (!parsed.ok) {
    console.error(JSON.stringify(parsed));
    return 2;
  }
  if (parsed.method !== "execute") {
    console.log(REGISTRY_USAGE);
    return 0;
  }
  const model = parsed.model;
  const domain = definitions.find((entry) => entry.name === model.collection)!.domain;
  const audience: Scope = model.scope;
  if (!model.root?.length && model["write-root"] !== undefined)
    throw new Error("--write-root requires explicit --root values");
  const policy = model.root?.length
    ? explicitPolicy(audience, model.root, model["write-root"] ?? model.root[0]!)
    : registryPolicy(domain.collection, audience, env);
  if (parsed.route === "/register" || parsed.route === "/status") {
    const request = { domain, policy, source: parsed.model.source };
    const plan =
      parsed.route === "/register" ? await register(request) : await planRegistration(request);
    console.log(
      model.json
        ? JSON.stringify(plan, null, 2)
        : `${plan.id}\t${plan.disposition}\t${plan.participation}\t${plan.destination}\n${plan.reason}`,
    );
    return plan.disposition === "blocked"
      ? 1
      : parsed.route === "/status" && plan.disposition === "create"
        ? 1
        : 0;
  }
  const snapshot = await inspectRegistry(domain, policy);
  if (parsed.route === "/complete") {
    if (!snapshot.complete)
      throw new Error("completion unavailable: registry root acquisition failed");
    const tab = new RootCommand();
    // One shared verb table drives both tab's static command descriptions and its ID provider.
    for (const verb of verbs) {
      const entry = tab.command(verb, `${verb} registry`);
      entry.option("--collection", "Rendezvous", (complete) => {
        for (const definition of definitions)
          complete(definition.name, definition.domain.collection);
      });
      entry.option("--scope", "Audience", (complete) => {
        complete("user", "invocation XDG");
        complete("system", "system roots only");
      });
      if (verb === "explain")
        entry.argument("id", (complete) => {
          for (const record of snapshot.records) complete(record.id, record.state);
        });
    }
    tab.parse([...(parsed.model.word ?? [])]);
    return 0;
  }
  const result = parsed.route === "/explain" ? lookup(snapshot, parsed.model.id) : snapshot;
  if (model.json) console.log(JSON.stringify(result, null, 2));
  else {
    for (const root of snapshot.roots.filter((entry) => entry.status !== "ok"))
      console.log(
        `root\t${root.status}\t${root.root}\t${root.error?.message ?? root.detail ?? ""}`,
      );
    const records =
      parsed.route === "/explain" ? [lookup(snapshot, parsed.model.id)] : snapshot.records;
    for (const record of records) {
      console.log(
        `${record.id}\t${record.state}\t${record.source.winner.path}${record.error ? `\t${record.error}` : ""}`,
      );
      if (parsed.route === "/explain")
        for (const observed of record.source.observations)
          console.log(
            `  ${observed.path}\t${observed.mask ? "mask" : observed.disabled ? "disabled slot" : observed.kind}`,
          );
    }
  }
  return snapshot.complete ? 0 : 2;
}

const argvPath = process.argv[1];
if (argvPath) {
  void Promise.all([realpath(argvPath), realpath(fileURLToPath(import.meta.url))]).then(
    ([invoked, module]) => {
      if (invoked === module)
        return main(process.argv.slice(2)).then((code) => {
          process.exitCode = code;
        });
    },
  );
}
