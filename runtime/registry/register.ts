/** Owner-side registration material. No declaration copies, pruning, reloads or native publication. */
import { resolve, join, isAbsolute, dirname } from "node:path";
import { captureFile, fileText } from "../../files/config/capture.ts";
import { verifyRegistryGuard, type RegistryGuard } from "./guard.ts";
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
  expectation: RegistryGuard;
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
  const owned = await captureFile(source);
  const text = fileText(owned);
  if (text === undefined) throw new Error(`missing owner descriptor: ${source}`);
  const payload = request.domain.decode(JSON.parse(text));
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
    // Optional root creation by another publisher is not a membership change.
    // Replanning still refuses every failed root, and compares this identity/slots.
    roots: policy.roots,
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
    expectation: {
      roots: [...policy.roots],
      id,
      expected: JSON.stringify(effective?.source) ?? "missing",
      files: [owned.guard],
    } as RegistryGuard,
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
  for (const observation of effective?.source.observations ?? []) {
    if (!observation.mask && (observation.kind === "file" || observation.referent === "file"))
      base.expectation.files!.push((await captureFile(observation.path)).guard);
  }
  base.expectation.publication = {
    source,
    destination,
    slots: [
      { path: activePath, before: active },
      { path: disabledPath, before: disabled },
      ...(destination !== activePath && destination !== disabledPath
        ? [{ path: destination, before: slot }]
        : []),
    ],
  };
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
  if (
    resolve(request.source) !== plan.source ||
    (request.policy.scope !== plan.material.links[0]?.scope && plan.disposition !== "blocked") ||
    dirname(plan.destination) !== resolve(request.policy.writeRoot) ||
    JSON.stringify(
      explicitPolicy(request.policy.scope, request.policy.roots, request.policy.writeRoot).roots,
    ) !== JSON.stringify(plan.expectation.roots)
  )
    throw new Error("registration request disagrees with admitted publication");
  if (plan.disposition === "blocked") return plan;
  const phase = await verifyRegistryGuard(plan.expectation);
  if (phase === "before" && plan.disposition === "create")
    await replaceWithLink(plan.source, plan.destination);
  // Never bless a newly observed override/mask after delivery as a fresh guard.
  await verifyRegistryGuard(plan.expectation);
  return { ...plan, disposition: phase === "published" ? "current" : plan.disposition };
}

export async function register<T>(request: RegistrationRequest<T>): Promise<RegistrationPlan> {
  return applyRegistration(request, await planRegistration(request));
}
