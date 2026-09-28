/** Same-generation retry admission: never reinterpret a changed destination as a new import. */
import { canonicalJson, oid, receiptRef, validateReceipt } from "../custody/codec.ts";
import { CustodyError } from "../custody/errors.ts";
import type { Oid, PlanV1, ReceiptV1, RefName, SourceInventory } from "../custody/model.ts";
import type { RefInstall } from "./transaction.ts";

function same(left: unknown, right: unknown): boolean {
  return canonicalJson(left) === canonicalJson(right);
}
const codepoint = (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0);
function unordered<T>(items: readonly T[]): readonly T[] {
  return [...items].sort((a, b) => codepoint(canonicalJson(a), canonicalJson(b)));
}
/** Only collections with no order-dependent provenance or manifest digest. */
function comparableSource(source: SourceInventory) {
  return {
    ...source,
    refs: unordered(source.refs),
    candidates: unordered(source.candidates),
    remotes: unordered(source.remotes),
    indexEntries: unordered(source.indexEntries),
    worktreeChanges: unordered(source.worktreeChanges),
    untrackedPaths: unordered(source.untrackedPaths),
    ignoredPaths: unordered(source.ignoredPaths),
    excludedUntracked: unordered(source.excludedUntracked),
    trackedSensitivePaths: unordered(source.trackedSensitivePaths),
    leftBehind: unordered(source.leftBehind),
    jjCoverage: { ...source.jjCoverage, headOids: unordered(source.jjCoverage.headOids) },
    head: { ...source.head, treePaths: unordered(source.head.treePaths) },
  };
}
function sortedRefs(refs: ReadonlyMap<string, string>): readonly (readonly [string, string])[] {
  return [...refs].sort(([a], [b]) => codepoint(a, b));
}
function mismatch(field: string): never {
  throw new CustodyError(
    "different-receipt",
    `same-generation retry differs from recorded ${field}; choose a new generation or inspect`,
    field,
  );
}

/**
 * Caller reads the existing receipt ref and blob from destination, parses it,
 * independently verifies the sealed bundle/intent, then calls this function.
 * RefInstall approval is granted only for exact matching historical input.
 */
export function approveSameInputRetry(
  plan: PlanV1,
  existing: ReceiptV1,
  receiptCommitOid: Oid,
  currentRefs: ReadonlyMap<string, string>,
): RefInstall {
  const receipt = validateReceipt(existing);
  oid(receiptCommitOid, receipt.source.objectFormat);
  if (plan.schema !== "compfuzor.archive-adoption-plan/v1") mismatch("plan schema");
  if (plan.state !== "ready" || plan.blockers.length) mismatch("apply blockers");
  if (receipt.receiptRef !== receiptRef(plan.identity.label, plan.identity.generation))
    mismatch("identity");
  // The receipt's first capture time is immutable; fresh plan time is not part of input.
  for (const field of [
    "legacyRealpathAtCapture",
    "sourceGitCommonDir",
    "destinationRealpath",
  ] as const) {
    if (plan.identity[field] !== receipt.identity[field]) mismatch(`identity.${field}`);
  }
  if (!same(comparableSource(plan.source), comparableSource(receipt.source)))
    mismatch("source inventory/fingerprint");
  if (!same(plan.proposedSnapshot, receipt.snapshot)) mismatch("path manifest/review");
  if (!same(unordered(plan.pins), unordered(receipt.pins))) mismatch("pin mapping");
  for (const field of [
    "sourceRemoteTracking",
    "destinationWorktreeFingerprintSha256",
    "destinationIndexSha256",
    "selectedBranch",
    "declaredRepo",
    "headNotInRecordedBaseline",
  ] as const) {
    if (
      !same(
        field === "sourceRemoteTracking" ? unordered(plan.baselines[field]) : plan.baselines[field],
        field === "sourceRemoteTracking"
          ? unordered(receipt.baselines[field])
          : receipt.baselines[field],
      )
    )
      mismatch(`destination baseline ${field}`);
  }
  // A new plan's ref list/delta is measured *after* our pins. Do not replace
  // the original receipt baseline with that later observation.

  const custodyRefs = new Map<string, Oid>([[receipt.receiptRef, receiptCommitOid]]);
  for (const pin of receipt.pins) custodyRefs.set(pin.destinationRef, pin.destinationOid);
  if (currentRefs.get(receipt.receiptRef) !== receiptCommitOid) mismatch("receipt ref OID");
  for (const [name, target] of custodyRefs) {
    const actual = currentRefs.get(name);
    if (actual !== undefined && actual !== target) mismatch(`custody ref ${name}`);
  }
  const original = new Map(
    receipt.baselines.destinationPreRefs.map(({ name, oid }) => [name, oid]),
  );
  if (
    new Set(plan.baselines.destinationPreRefs.map(({ name }) => name)).size !==
    plan.baselines.destinationPreRefs.length
  )
    mismatch("duplicate fresh destination ref");
  const plannedNow = new Map(plan.baselines.destinationPreRefs.map(({ name, oid }) => [name, oid]));
  if (!same(sortedRefs(plannedNow), sortedRefs(currentRefs)))
    mismatch("fresh destination ref observation");
  const now = new Map([...currentRefs].filter(([name]) => !custodyRefs.has(name)));
  if (!same(sortedRefs(original), sortedRefs(now))) mismatch("pre-import destination refs");
  return {
    receiptRef: receipt.receiptRef,
    receiptCommitOid,
    pins: receipt.pins,
    matchingReceiptApproved: true,
  };
}

/** New generation: reject already installed custody pins without a matching receipt. */
export function freshInstall(receipt: ReceiptV1, receiptCommitOid: Oid): RefInstall {
  validateReceipt(receipt);
  oid(receiptCommitOid, receipt.source.objectFormat);
  return {
    receiptRef: receipt.receiptRef as RefName,
    receiptCommitOid,
    pins: receipt.pins,
    matchingReceiptApproved: false,
  };
}
