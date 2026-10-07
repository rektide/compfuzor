import { load, observe } from "../discovery/figments.ts";
import {
  assertId,
  type Domain,
  type RegistryPolicy,
  type RegistryRecord,
  type RegistrySnapshot,
} from "./model.ts";

/** Read-only whole-definition registry projection, not accepted native membership. */
export async function inspectRegistry<T>(
  domain: Domain<T>,
  policy: RegistryPolicy,
): Promise<RegistrySnapshot<T>> {
  const bound = { ...policy, roots: [...policy.roots] };
  const view = await observe(bound.roots);
  const records = await Promise.all(
    view.entries.map(async (source): Promise<RegistryRecord<T>> => {
      const record: RegistryRecord<T> = { id: source.identity, state: source.state, source };
      if (source.state !== "active" && source.state !== "disabled") return record;
      try {
        assertId(source.identity);
        const payload = domain.decode(await load(source));
        if (domain.identity(payload) !== source.identity)
          throw new Error("filename and declaration identity disagree");
        const scope = domain.scope(payload);
        if (scope !== undefined && scope !== bound.scope)
          throw new Error(`declaration scope ${scope} disagrees with ${bound.scope} registry`);
        record.payload = payload;
        if (!domain.enabled(payload)) record.state = "disabled";
      } catch (error) {
        record.state = "invalid";
        record.error = error instanceof Error ? error.message : String(error);
      }
      return record;
    }),
  );
  return {
    collection: domain.collection,
    policy: bound,
    complete: view.roots.every((root) => root.status !== "failed"),
    roots: view.roots,
    records,
  };
}

/** Lookup never treats an incomplete observation as proof of absence. */
export function lookup<T>(snapshot: RegistrySnapshot<T>, id: string): RegistryRecord<T> {
  assertId(id);
  if (!snapshot.complete)
    throw new Error(
      `incomplete registry ${snapshot.collection}: inspect root errors before lookup`,
    );
  const record = snapshot.records.find((entry) => entry.id === id);
  if (!record) throw new Error(`missing registry identity ${id} in ${snapshot.collection}`);
  return record;
}
