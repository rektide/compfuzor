/** Owner-side registration material. No declaration copies, pruning, reloads or native publication. */
import { resolve, join, isAbsolute } from "node:path";
import { loadOwner } from "../discovery/figments.ts";
import { inspectDeliveryEntry, linkMatches, replaceWithLink } from "../../files/links/delivery.ts";
import { inspectRegistry } from "./read.ts";
import { explicitPolicy } from "./policy.ts";
import { assertId, type Domain, type RegistryPolicy } from "./model.ts";

export type RegistrationRequest<T> = {
  domain: Domain<T>;
  policy: RegistryPolicy;
  /** Exact descriptor in the owner's deployment, not a central registry copy. */
  source: string;
};
export type RegistrationPlan = {
  id: string;
  source: string;
  destination: string;
  disposition: "create" | "current" | "blocked";
  participation: "active" | "disabled";
  /** Effective discovery state before publication; independent of the local link's status. */
  effective: {
    state: "missing" | "active" | "disabled" | "masked" | "invalid" | "conflict";
    winner?: string;
  };
  reason: string;
  /** Ordinary LINKS material, for generated installers to consume after policy admission. */
  material: {
    version: 1;
    links: {
      id: string;
      scope: "user" | "system";
      src: string;
      dest: string;
      policy: "replace";
      state: "present";
    }[];
  };
  /** Observation guard, not a lock or a content snapshot. */
  guard: string;
};

export async function planRegistration<T>(
  request: RegistrationRequest<T>,
): Promise<RegistrationPlan> {
  if (!isAbsolute(request.source))
    throw new Error("registration requires an absolute owner descriptor path");
  const source = resolve(request.source);
  const policy = explicitPolicy(
    request.policy.scope,
    request.policy.roots,
    request.policy.writeRoot,
  );
  const payload = request.domain.decode(await loadOwner(source));
  const id = request.domain.identity(payload);
  assertId(id);
  const scope = request.domain.scope(payload);
  if (scope !== undefined && scope !== policy.scope)
    throw new Error("owner descriptor audience disagrees with registration scope");
  const snapshot = await inspectRegistry(request.domain, policy);
  if (!snapshot.complete)
    throw new Error("cannot register into an incompletely observed registry; inspect root errors");
  const effective = snapshot.records.find((record) => record.id === id);
  const activePath = join(policy.writeRoot, `${id}.json`);
  const disabledPath = `${activePath}.disabled`;
  const [active, disabled] = await Promise.all([
    inspectDeliveryEntry(activePath),
    inspectDeliveryEntry(disabledPath),
  ]);
  const activePresent = active.kind !== "missing";
  const disabledPresent = disabled.kind !== "missing";
  const local =
    effective?.source.participating.filter((entry) => entry.root === policy.writeRoot) ?? [];
  if ((activePresent && disabledPresent) || local.length > 1)
    throw new Error(`conflicting local registration slots for ${id}`);
  const existing = local[0];
  const disabledSlot =
    existing?.disabled ?? (disabledPresent || (!activePresent && !request.domain.enabled(payload)));
  const participation: RegistrationPlan["participation"] =
    disabledSlot || !request.domain.enabled(payload) ? "disabled" : "active";
  const destination = existing?.path ?? (disabledSlot ? disabledPath : activePath);
  const slot = existing
    ? await inspectDeliveryEntry(existing.path)
    : disabledSlot
      ? disabled
      : active;
  const guard = JSON.stringify({
    roots: snapshot.roots,
    source: effective?.source,
    state: effective?.state,
    active,
    disabled,
  });
  const base = {
    id,
    source,
    destination,
    participation,
    guard,
    effective: {
      state: effective?.state ?? ("missing" as const),
      winner: effective?.source.winner.path,
    },
  };
  const blocked = (reason: string): RegistrationPlan => ({
    ...base,
    disposition: "blocked",
    reason,
    material: { version: 1, links: [] },
  });
  // A regular operator declaration (including enabled:false) is never replaced.
  if (slot.kind !== "missing" && !linkMatches(slot, source))
    return blocked(`local slot is not this owner's reference: ${destination}`);
  const disposition = slot.kind === "missing" ? "create" : "current";
  return {
    ...base,
    disposition,
    reason:
      participation === "disabled"
        ? "retained disabled registration (not activation)"
        : "owner reference only (not accepted membership)",
    material: {
      version: 1,
      links: [
        {
          id: `registry-${id}`,
          scope: policy.scope,
          src: source,
          dest: destination,
          policy: "replace",
          state: "present",
        },
      ],
    },
  };
}

/** Recheck policy/slots immediately before delivery. Concurrent writers are not locked. */
export async function applyRegistration<T>(
  request: RegistrationRequest<T>,
  plan: RegistrationPlan,
): Promise<RegistrationPlan> {
  const current = await planRegistration(request);
  if (JSON.stringify(current) !== JSON.stringify(plan))
    throw new Error("registration changed since planning; inspect and plan again");
  if (current.disposition === "create") await replaceWithLink(current.source, current.destination);
  return current;
}

export async function register<T>(request: RegistrationRequest<T>): Promise<RegistrationPlan> {
  return applyRegistration(request, await planRegistration(request));
}
