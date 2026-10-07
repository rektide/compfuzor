/** One public versioned policy document binds BOTH registries for the selected audience. */
import { dirname, resolve } from "node:path";
import { realpath } from "node:fs/promises";
import { captureFile, fileText, type FileGuard } from "../../files/config/capture.ts";
import { resolvePathSelector, validatePathSelector } from "../../files/config/context.ts";
import { explicitPolicy, registryPolicy } from "../registry/policy.ts";
import type { RegistryPolicy, Scope } from "../registry/model.ts";

export type RegistryPolicyPair = { providers: RegistryPolicy; consumers: RegistryPolicy };
export type BoundRegistryPolicies = RegistryPolicyPair & { guards: FileGuard[]; locator?: string };

export async function bindRegistryPolicies(
  audience: Scope,
  locator?: string,
  supplied?: RegistryPolicyPair,
): Promise<BoundRegistryPolicies> {
  if (locator && supplied) throw new Error("choose registry policy document or concrete pair");
  if (supplied) {
    if (!supplied.providers || !supplied.consumers)
      throw new Error("registry policy pair requires both providers and consumers");
    if (supplied.providers.scope !== audience || supplied.consumers.scope !== audience)
      throw new Error("registry policy pair audience mismatch");
    return {
      providers: explicitPolicy(audience, supplied.providers.roots, supplied.providers.writeRoot),
      consumers: explicitPolicy(audience, supplied.consumers.roots, supplied.consumers.writeRoot),
      guards: [],
    };
  }
  if (!locator)
    return {
      providers: registryPolicy("keybindings/providers.d", audience),
      consumers: registryPolicy("keybindings/consumers.d", audience),
      guards: [],
    };
  const path = resolve(locator),
    file = await captureFile(path),
    text = fileText(file);
  if (text === undefined) throw new Error("missing registry policy document");
  const value: unknown = JSON.parse(text);
  if (
    !value ||
    typeof value !== "object" ||
    !("version" in value) ||
    value.version !== 1 ||
    !("audiences" in value) ||
    !value.audiences ||
    typeof value.audiences !== "object"
  )
    throw new Error("invalid registry policy document");
  const pair = (value.audiences as Record<string, unknown>)[audience];
  if (!pair || typeof pair !== "object")
    throw new Error(`registry policy has no ${audience} pair; refusing default fallback`);
  const base = dirname(await realpath(path));
  const bind = (role: "providers" | "consumers"): RegistryPolicy => {
    const raw = (pair as Record<string, unknown>)[role];
    if (
      !raw ||
      typeof raw !== "object" ||
      !("roots" in raw) ||
      !Array.isArray(raw.roots) ||
      !("writeRoot" in raw)
    )
      throw new Error(
        `registry policy requires ${audience}.${role} roots/writeRoot; refusing fallback`,
      );
    const roots = raw.roots.map((selector) =>
      resolvePathSelector(validatePathSelector(selector, `${role} root`), base, `${role} root`),
    );
    const writeRoot = resolvePathSelector(
      validatePathSelector(raw.writeRoot, `${role} write root`),
      base,
      `${role} write root`,
    );
    return explicitPolicy(audience, roots, writeRoot);
  };
  return {
    providers: bind("providers"),
    consumers: bind("consumers"),
    guards: [file.guard],
    locator: path,
  };
}
