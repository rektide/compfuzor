import type { RegistryView, ResolvedEntry } from "../discovery/figments.ts";

export type Scope = "user" | "system";
export type RegistryPolicy = {
  scope: Scope;
  /** Lower precedence first. Explicit roots must include writeRoot. */
  roots: readonly string[];
  writeRoot: string;
};
export type Domain<T> = {
  /** Domain-owned rendezvous path, e.g. keybindings/providers.d. */
  collection: string;
  decode(value: unknown): T;
  identity(value: T): string;
  enabled(value: T): boolean;
  scope(value: T): Scope | undefined;
};
export type RegistryRecord<T> = {
  id: string;
  state: ResolvedEntry["state"];
  /** Participation and payload validity are distinct from discovery topology. */
  payload?: T;
  error?: string;
  source: ResolvedEntry;
};
export type RegistrySnapshot<T> = {
  collection: string;
  policy: RegistryPolicy;
  complete: boolean;
  roots: RegistryView["roots"];
  records: readonly RegistryRecord<T>[];
};

/** IDs are literal filename stems; dots/numeric IDs never become key paths. */
export function assertId(id: string): void {
  if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(id) || id.endsWith(".disabled")) {
    throw new Error(`unsafe registry identity: ${id}`);
  }
}
