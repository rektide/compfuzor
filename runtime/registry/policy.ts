import { isAbsolute, join, resolve } from "node:path";
import { xdgConfigDirs, xdgDataDirs } from "../discovery/figments.ts";
import type { RegistryPolicy, Scope } from "./model.ts";

/** Data registrations below root-major config policy; system audience is a separate namespace. */
export function registryPolicy(
  collection: string,
  scope: Scope,
  env: Record<string, string | undefined> = { ...process.env },
): RegistryPolicy {
  const segments = collection.split("/");
  if (
    segments.length < 2 ||
    segments.some(
      (part) => !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(part) || part === "." || part === "..",
    ) ||
    !collection.endsWith(".d")
  ) {
    throw new Error(`invalid rendezvous collection: ${collection}`);
  }
  const maskCollection = collection.replace(/\.d$/, ".mask.d");
  if (scope === "system") {
    return explicitPolicy(
      scope,
      [
        join("/usr/share/compfuzor/system", collection),
        join("/usr/local/share/compfuzor/system", collection),
        join("/var/lib/compfuzor/system", collection),
        join("/etc/compfuzor/system", collection),
        join("/etc/compfuzor/system", maskCollection),
      ],
      join("/var/lib/compfuzor/system", collection),
    );
  }
  const data = xdgDataDirs("compfuzor", { env });
  const config = xdgConfigDirs("compfuzor", { env });
  return explicitPolicy(
    scope,
    [
      ...data.toReversed().map((root) => join(root, collection)),
      ...config
        .toReversed()
        .flatMap((root) => [join(root, collection), join(root, maskCollection)]),
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
