/** Guard selected identities without admitting registrations that appear later. */
import { observe, type ResolvedEntry } from "../discovery/figments.ts";
import type { RegistryPolicy } from "./model.ts";
import { inspectDeliveryEntry, type DeliveryEntry } from "../../files/links/delivery.ts";
import { assertFileGuards, type FileGuard } from "../../files/config/capture.ts";

export type RegistryGuard = {
  roots: readonly string[];
  id: string;
  expected: string;
  /** Exactly one admitted owner publication, not an arbitrary same-ID replacement. */
  publication?: {
    source: string;
    destination: string;
    slots: { path: string; before: DeliveryEntry }[];
  };
  files?: FileGuard[];
};
export function registryGuard(policy: RegistryPolicy, entry: ResolvedEntry): RegistryGuard {
  return { roots: [...policy.roots], id: entry.identity, expected: JSON.stringify(entry) };
}
export async function assertRegistryGuards(guards: readonly RegistryGuard[]): Promise<void> {
  for (const guard of guards) await verifyRegistryGuard(guard);
}

/** Accept the captured pre-state or only its exact admitted publication transition. */
export async function verifyRegistryGuard(guard: RegistryGuard): Promise<"before" | "published"> {
  await assertFileGuards(guard.files ?? []);
  const view = await observe(guard.roots);
  if (view.roots.some((root) => root.status === "failed"))
    throw new Error(`registry root failure while verifying ${guard.id}`);
  const current = view.entries.find((entry) => entry.identity === guard.id);
  const publication = guard.publication;
  const slots = publication
    ? await Promise.all(
        publication.slots.map(async (slot) => ({
          ...slot,
          current: await inspectDeliveryEntry(slot.path),
        })),
      )
    : [];
  if (
    (JSON.stringify(current) ?? "missing") === guard.expected &&
    slots.every((slot) => JSON.stringify(slot.current) === JSON.stringify(slot.before))
  )
    return "before";
  if (publication && current) {
    const intended = current.observations.find((entry) => entry.path === publication.destination);
    const before: ResolvedEntry | undefined =
      guard.expected === "missing" ? undefined : JSON.parse(guard.expected);
    const unchanged = (entries: ResolvedEntry["observations"]) =>
      entries.filter((entry) => entry.path !== publication.destination);
    const exactLink =
      intended?.kind === "symlink" &&
      intended.linkTarget === publication.source &&
      intended.referentPath === publication.source &&
      intended.referent === "file" &&
      !intended.mask &&
      !intended.error &&
      intended.matched &&
      intended.stem === guard.id;
    const unchangedSlots = slots.every((slot) =>
      slot.path === publication.destination
        ? slot.current.kind === "symlink" && slot.current.target === publication.source
        : JSON.stringify(slot.current) === JSON.stringify(slot.before),
    );
    if (
      exactLink &&
      unchangedSlots &&
      JSON.stringify(unchanged(current.observations)) ===
        JSON.stringify(unchanged(before?.observations ?? []))
    )
      return "published";
  }
  throw new Error(`selected registration changed: ${guard.id}`);
}
