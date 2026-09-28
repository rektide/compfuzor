/** Append-only receipt + pin installation. Caller must verify bundle, receipt, source/dest drift first. */
import { CustodyError, invalid } from "../custody/errors.ts";
import { oid, refName } from "../custody/codec.ts";
import type { Oid, PinIntent, RefName } from "../custody/model.ts";
export type RefTarget = Readonly<{ ref: RefName; oid: Oid }>;

/** A reader/runner injection point: tests can simulate races without mutating real repositories. */
export interface RefStore {
  list(): Promise<ReadonlyMap<string, string>>;
  /** One `git update-ref --stdin --no-deref` transaction; verify existing and create missing. */
  createAtomically(missing: readonly RefTarget[], matching: readonly RefTarget[]): Promise<void>;
}

export interface RefInstall {
  readonly receiptRef: RefName;
  readonly receiptCommitOid: Oid;
  readonly pins: readonly PinIntent[];
  /** Only true after a separate caller checked existing receipt content and original plan. */
  readonly matchingReceiptApproved: boolean;
}
export interface InstallResult {
  readonly changed: boolean;
  readonly created: readonly RefName[];
  readonly alreadyPresent: readonly RefName[];
}

function requiredRefs(input: RefInstall): readonly RefTarget[] {
  const refs: RefTarget[] = [{ ref: refName(input.receiptRef), oid: input.receiptCommitOid }];
  const unique = new Set<string>([input.receiptRef]);
  for (const pin of input.pins) {
    const ref = refName(pin.destinationRef);
    if (unique.has(ref)) invalid(`duplicate custody ref: ${ref}`);
    unique.add(ref);
    refs.push({ ref, oid: pin.destinationOid });
  }
  // Branded types are erased by JS; independently guard runtime input before
  // interpolating an OID into update-ref's line-oriented stdin protocol.
  const format = refs[0].oid.length === 40 ? "sha1" : "sha256";
  for (const target of refs) {
    oid(target.oid, format);
    if (/^0+$/.test(target.oid)) invalid(`zero is not a custody object ID: ${target.ref}`);
  }
  for (let i = 0; i < refs.length; i++)
    for (let j = i + 1; j < refs.length; j++)
      if (prefixConflict(refs[i].ref, refs[j].ref))
        throw new CustodyError(
          "occupied-namespace",
          `desired ref prefix conflict: ${refs[i].ref} versus ${refs[j].ref}`,
          refs[i].ref,
        );
  return refs;
}

/** Ref file/directory conflicts also exist when the exact leaf does not yet exist. */
export function prefixConflict(name: string, other: string): boolean {
  return name !== other && (name.startsWith(`${other}/`) || other.startsWith(`${name}/`));
}

export function decideInstallation(
  observed: ReadonlyMap<string, string>,
  input: RefInstall,
): Readonly<{
  missing: readonly RefTarget[];
  matching: readonly RefTarget[];
  alreadyPresent: readonly RefName[];
}> {
  const desired = requiredRefs(input);
  const existingReceipt = observed.get(input.receiptRef);
  if (existingReceipt !== undefined && existingReceipt !== input.receiptCommitOid) {
    throw new CustodyError(
      "different-receipt",
      `receipt ref has another OID: ${input.receiptRef}`,
      input.receiptRef,
    );
  }
  if (existingReceipt !== undefined && !input.matchingReceiptApproved) {
    throw new CustodyError(
      "different-receipt",
      "existing receipt has not passed same-input/intent review",
      input.receiptRef,
    );
  }
  if (
    existingReceipt === undefined &&
    desired.some(({ ref }) => ref !== input.receiptRef && observed.has(ref))
  ) {
    throw new CustodyError(
      "occupied-namespace",
      "pin exists without an approved matching receipt; inspect manually",
    );
  }
  const label = input.receiptRef.split("/")[3];
  for (const old of [
    `refs/heads/harvest/${label}/head`,
    `refs/heads/harvest/${label}/working-copy`,
  ]) {
    if (observed.has(old))
      throw new CustodyError(
        "occupied-namespace",
        `legacy harvest namespace under this label: ${old}`,
        old,
      );
  }
  const missing: RefTarget[] = [];
  const matching: RefTarget[] = [];
  const alreadyPresent: RefName[] = [];
  for (const { ref, oid: expected } of desired) {
    for (const other of observed.keys()) {
      if (prefixConflict(ref, other))
        throw new CustodyError(
          "occupied-namespace",
          `ref prefix conflict: ${ref} versus ${other}`,
          ref,
        );
    }
    const actual = observed.get(ref);
    if (actual !== undefined && actual !== expected)
      throw new CustodyError("occupied-namespace", `ref has another OID: ${ref}`, ref);
    if (actual === expected) {
      alreadyPresent.push(ref);
      matching.push({ ref, oid: expected });
    } else missing.push({ ref, oid: expected });
  }
  return { missing, matching, alreadyPresent };
}

/** No automatic repair: even on a failed Git transaction, inspect refs again on retry. */
export async function installImmutableRefs(
  store: RefStore,
  input: RefInstall,
): Promise<InstallResult> {
  const observed = await store.list();
  const { missing, matching, alreadyPresent } = decideInstallation(observed, input);
  if (missing.length === 0) return { changed: false, created: [], alreadyPresent };
  try {
    await store.createAtomically(missing, matching);
  } catch (error) {
    throw new CustodyError(
      "ref-race",
      `atomic compare-and-create failed; inspect refs before retry: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
  return { changed: true, created: missing.map(({ ref }) => ref), alreadyPresent };
}

/** Exact stdin protocol: process adapter handles argv/env, Git handles atomicity. */
export function createTransactionStdin(
  missing: readonly RefTarget[],
  matching: readonly RefTarget[] = [],
): string {
  const refs = [...missing, ...matching];
  if (!refs.length) invalid("empty custody ref transaction");
  const format = refs[0].oid.length === 40 ? "sha1" : "sha256";
  const names = new Set<string>();
  for (const { ref, oid: target } of refs) {
    refName(ref);
    oid(target, format);
    if (/^0+$/.test(target) || names.has(ref)) invalid("invalid or repeated transaction target");
    names.add(ref);
  }
  return [
    "start",
    ...matching.map(({ ref, oid }) => `verify ${ref} ${oid}`),
    ...missing.map(({ ref, oid }) => `create ${refName(ref)} ${oid}`),
    "prepare",
    "commit",
    "",
  ].join("\n");
}
