import assert from "node:assert/strict";
import { test } from "node:test";
import { oid, pinRef, receiptRef } from "../../src/custody/codec.ts";
import type { Oid, PinIntent, RefName } from "../../src/custody/model.ts";
import {
  createTransactionStdin,
  decideInstallation,
  installImmutableRefs,
  prefixConflict,
  type RefStore,
  type RefTarget,
} from "../../src/recovery/transaction.ts";

const O = (digit: string) => oid(digit.repeat(40), "sha1");
class MemoryRefStore implements RefStore {
  public refs = new Map<string, string>();
  public injectRace: (() => void) | null = null;
  public async list(): Promise<ReadonlyMap<string, string>> {
    return new Map(this.refs);
  }
  public async createAtomically(missing: readonly RefTarget[], matching: readonly RefTarget[]): Promise<void> {
    this.injectRace?.();
    // The real adapter uses Git `update-ref --stdin` with one start/prepare/commit.
    // This fake models all-or-nothing create after the observation/race point.
    for (const { ref } of missing)
      if (this.refs.has(ref)) throw new Error(`already exists: ${ref}`);
    for (const { ref, oid } of matching)
      if (this.refs.get(ref) !== oid) throw new Error(`matching ref moved: ${ref}`);
    for (const { ref, oid } of missing) this.refs.set(ref, oid);
  }
}
function pin(target: Oid): PinIntent {
  const input = {
    sourceKind: "branch",
    sourceName: "refs/heads/head",
    sourceOid: target,
    destinationOid: target,
  } as const;
  return { ...input, objectType: "commit", destinationRef: pinRef(input, "legacy", "g0") };
}

test("atomic install intent, unchanged retry, partial matching receipt resumes only missing pin", async () => {
  const store = new MemoryRefStore();
  const receipt = receiptRef("legacy", "g0");
  const branch = pin(O("1"));
  const headInput = {
    sourceKind: "head",
    sourceName: "HEAD",
    sourceOid: O("2"),
    destinationOid: O("2"),
  } as const;
  const other: PinIntent = {
    ...headInput,
    objectType: "commit",
    destinationRef: pinRef(headInput, "legacy", "g0"),
  };
  const input = {
    receiptRef: receipt,
    receiptCommitOid: O("1"),
    pins: [branch, other],
    matchingReceiptApproved: false,
  };
  const expected = decideInstallation(store.refs, input).missing;
  assert.equal(
    createTransactionStdin(expected),
    `start\ncreate ${receipt} ${O("1")}\ncreate ${branch.destinationRef} ${O("1")}\ncreate ${other.destinationRef} ${O("2")}\nprepare\ncommit\n`,
  );
  assert.deepEqual((await installImmutableRefs(store, input)).created, [
    receipt,
    branch.destinationRef,
    other.destinationRef,
  ]);
  await assert.rejects(installImmutableRefs(store, input), /same-input\/intent review/);
  assert.equal(
    (await installImmutableRefs(store, { ...input, matchingReceiptApproved: true })).changed,
    false,
  );
  store.refs.delete(other.destinationRef);
  assert.equal(
    createTransactionStdin([{ ref: other.destinationRef, oid: other.destinationOid }], [
      { ref: receipt, oid: O("1") }, { ref: branch.destinationRef, oid: O("1") },
    ]),
    `start\nverify ${receipt} ${O("1")}\nverify ${branch.destinationRef} ${O("1")}\ncreate ${other.destinationRef} ${O("2")}\nprepare\ncommit\n`,
  );
  assert.deepEqual(
    (await installImmutableRefs(store, { ...input, matchingReceiptApproved: true })).created,
    [other.destinationRef],
  );
  assert.equal(store.refs.get(receipt), O("1"));
});

test("matching receipt changing during missing-pin installation aborts every creation", async () => {
  const store = new MemoryRefStore();
  const receipt = receiptRef("legacy", "g0");
  store.refs.set(receipt, O("1"));
  store.injectRace = () => store.refs.set(receipt, O("2"));
  const branch = pin(O("1"));
  await assert.rejects(
    installImmutableRefs(store, { receiptRef: receipt, receiptCommitOid: O("1"), pins: [branch], matchingReceiptApproved: true }),
    /atomic compare-and-create failed/,
  );
  assert.equal(store.refs.has(branch.destinationRef), false);
  assert.equal(store.refs.get(receipt), O("2"));
});

test("desired prefix collisions and untrusted branded OIDs are refused before writes", () => {
  const receipt = receiptRef("legacy", "g0");
  const branch = pin(O("1"));
  const root = "refs/heads/harvest/legacy/g0/branch" as RefName;
  assert.throws(() => decideInstallation(new Map(), {
    receiptRef: receipt, receiptCommitOid: O("1"),
    pins: [branch, { ...branch, destinationRef: root }], matchingReceiptApproved: false,
  }), /desired ref prefix conflict/);
  assert.throws(() => decideInstallation(new Map(), {
    receiptRef: receipt, receiptCommitOid: "1\ncommit" as Oid,
    pins: [branch], matchingReceiptApproved: false,
  }), /invalid sha256 object ID/);
  assert.throws(() => createTransactionStdin([{ ref: receipt, oid: "0".repeat(40) as Oid }]), /invalid or repeated/);
});

test("occupied old harvest prefixes and different receipt block without changing refs", async () => {
  const store = new MemoryRefStore();
  store.refs.set("refs/heads/harvest/legacy/head", O("1"));
  const receipt = receiptRef("legacy", "g0");
  const input = {
    receiptRef: receipt,
    receiptCommitOid: O("1"),
    pins: [pin(O("1"))],
    matchingReceiptApproved: false,
  };
  await assert.rejects(installImmutableRefs(store, input), /legacy harvest namespace/);
  assert.equal(store.refs.has(receipt), false);
  store.refs.delete("refs/heads/harvest/legacy/head");
  store.refs.set(receipt, O("2"));
  await assert.rejects(
    installImmutableRefs(store, { ...input, matchingReceiptApproved: true }),
    /another OID/,
  );
  assert.equal(store.refs.get(receipt), O("2"));
});

test("creation race fails whole transaction without rewriting existing pin", async () => {
  const store = new MemoryRefStore();
  const receipt = receiptRef("legacy", "g0");
  const branch = pin(O("1"));
  store.injectRace = () => store.refs.set(branch.destinationRef, O("2"));
  await assert.rejects(
    installImmutableRefs(store, {
      receiptRef: receipt,
      receiptCommitOid: O("1"),
      pins: [branch],
      matchingReceiptApproved: false,
    }),
    /atomic compare-and-create failed/,
  );
  assert.equal(store.refs.has(receipt), false);
  assert.equal(store.refs.get(branch.destinationRef), O("2"));
});

test("pure decision refuses orphan pins and prefix-colliding refs", () => {
  const receipt = receiptRef("legacy", "g0");
  const branch = pin(O("1"));
  assert.equal(prefixConflict("refs/heads/harvest/legacy/head", branch.destinationRef), false);
  assert.equal(prefixConflict("refs/heads/harvest/legacy", branch.destinationRef), true);
  assert.throws(
    () =>
      decideInstallation(new Map([[branch.destinationRef, branch.destinationOid]]), {
        receiptRef: receipt,
        receiptCommitOid: O("1"),
        pins: [branch],
        matchingReceiptApproved: false,
      }),
    /without an approved matching receipt/,
  );
  const alias = "refs/heads/harvest/legacy/g0/branch" as RefName;
  assert.throws(
    () =>
      decideInstallation(new Map([[alias, O("1")]]), {
        receiptRef: receipt,
        receiptCommitOid: O("1"),
        pins: [branch],
        matchingReceiptApproved: false,
      }),
    /prefix conflict/,
  );
});
