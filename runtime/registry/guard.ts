/** Guard selected identities without admitting registrations that appear later. */
import { observe, type ResolvedEntry } from "../discovery/figments.ts";
import type { RegistryPolicy } from "./model.ts";

export type RegistryGuard = { roots: readonly string[]; id: string; expected: string };
export function registryGuard(policy: RegistryPolicy, entry: ResolvedEntry): RegistryGuard {
  return { roots: [...policy.roots], id: entry.identity, expected: JSON.stringify(entry) };
}
export async function assertRegistryGuards(guards: readonly RegistryGuard[]): Promise<void> {
  for (const guard of guards) {
    const view = await observe(guard.roots);
    if (view.roots.some((root) => root.status === "failed"))
      throw new Error(`registry root failure while verifying ${guard.id}`);
    if (
      (JSON.stringify(view.entries.find((entry) => entry.identity === guard.id)) ?? "missing") !==
      guard.expected
    ) {
      throw new Error(`selected registration changed: ${guard.id}`);
    }
  }
}
