import { isAbsolute, join, resolve } from "node:path";
import { xdgConfigDirs, xdgDataDirs } from "../discovery/figments.ts";
import type { RegistryPolicy, Scope } from "./model.ts";

/** Proposed default layout: data registrations, config overrides, then config masks. */
export function registryPolicy(
  collection: string,
  scope: Scope,
  env: Record<string, string | undefined> = { ...process.env },
): RegistryPolicy {
  if (!/^[a-z][a-z0-9-]*\/(providers|consumers)\.d$/.test(collection)) {
    throw new Error(`invalid rendezvous collection: ${collection}`);
  }
  const maskCollection = collection.replace(/\.d$/, ".mask.d");
  if (scope === "system") {
    return explicitPolicy(
      scope,
      [
        join("/usr/share/compfuzor", collection),
        join("/usr/local/share/compfuzor", collection),
        join("/var/lib/compfuzor", collection),
        join("/etc/compfuzor", collection),
        join("/etc/compfuzor", maskCollection),
      ],
      join("/var/lib/compfuzor", collection),
    );
  }
  const data = xdgDataDirs("compfuzor", { env });
  const config = xdgConfigDirs("compfuzor", { env });
  return explicitPolicy(
    scope,
    [
      ...data.toReversed().map((root) => join(root, collection)),
      ...config.toReversed().map((root) => join(root, collection)),
      ...config.toReversed().map((root) => join(root, maskCollection)),
    ],
    join(data[0]!, collection),
  );
}

/** Embedders/tests choose their own roots; absolute paths bind before effects. */
export function explicitPolicy(
  scope: Scope,
  roots: readonly string[],
  writeRoot: string,
): RegistryPolicy {
  if (scope !== "user" && scope !== "system")
    throw new Error("registry policy requires user or system scope");
  if (roots.length === 0 || ![...roots, writeRoot].every(isAbsolute)) {
    throw new Error("registry policy requires absolute roots and a writable root");
  }
  // Repeated roots are one location; retain its LAST occurrence to preserve precedence.
  const normalized = [...new Set(roots.map((root) => resolve(root)).toReversed())].toReversed();
  const writable = resolve(writeRoot);
  if (!normalized.includes(writable)) throw new Error("writeRoot must belong to registry roots");
  return { scope, roots: normalized, writeRoot: writable };
}
