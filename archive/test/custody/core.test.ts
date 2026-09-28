import assert from "node:assert/strict";
import { test } from "node:test";
import {
  canonicalJson,
  candidateIdentity,
  decodeIdentity,
  digest,
  encodeIdentity,
  encodeReceipt,
  oid,
  parsePathReview,
  parseReceipt,
  pinRef,
  receiptRef,
  refComponent,
  refName,
  repoPath,
  sha256,
  validateReceipt,
  vaultBundlePath,
} from "../../src/custody/codec.ts";
import type { PathEntry, PinIntent, ReceiptV1 } from "../../src/custody/model.ts";
import type { PlanV1 } from "../../src/custody/model.ts";
import { approveSameInputRetry, freshInstall } from "../../src/recovery/retry.ts";

const O = (char: string) => oid(char.repeat(40), "sha1");
const D = digest("a".repeat(64));
function sample(): ReceiptV1 {
  const sourceOid = O("1");
  const pin: PinIntent = {
    sourceKind: "head",
    sourceName: "HEAD",
    sourceOid,
    objectType: "commit",
    destinationOid: sourceOid,
    destinationRef: pinRef(
      { sourceKind: "head", sourceName: "HEAD", sourceOid, destinationOid: sourceOid },
      "legacy",
      "g0",
    ),
  };
  return {
    schema: "compfuzor.archive-adoption/v1",
    receiptRef: receiptRef("legacy", "g0"),
    identity: {
      label: "legacy",
      generation: "g0",
      legacyRealpathAtCapture: "/fixtures/source",
      sourceGitCommonDir: "/fixtures/source/.git",
      destinationRealpath: "/fixtures/archive",
      createdAt: "2026-09-27T00:00:00Z",
    },
    source: {
      objectFormat: "sha1",
      sourceGitCommonDir: "/fixtures/source/.git",
      head: { symbolicRef: null, oid: sourceOid, treeOid: O("2"), treePaths: [] },
      refs: [],
      candidates: [],
      remotes: [],
      indexEntries: [],
      worktreeChanges: [],
      untrackedPaths: [],
      ignoredPaths: [],
      excludedUntracked: [],
      trackedSensitivePaths: [],
      leftBehind: [],
      jjCoverage: { classification: "none", headOids: [], operationId: null },
      fingerprints: {
        indexSha256: D,
        gitConfigSha256: D,
        refsSha256: D,
        reflogsSha256: D,
        odbListingSha256: D,
        includedWorktreeSha256: D,
        jjStoreSha256: null,
        canonicalInputsSha256: D,
      },
      excludeFileSha256: null,
      dispositionsFileSha256: null,
    },
    snapshot: null,
    baselines: {
      sourceRemoteTracking: [],
      destinationPreRefs: [],
      destinationPreRefsSha256: D,
      destinationWorktreeFingerprintSha256: D,
      destinationIndexSha256: D,
      selectedBranch: "main",
      declaredRepo: "https://example.test/repo",
      headNotInRecordedBaseline: null,
      selectedTipsNotInDestination: 0,
    },
    pins: [pin],
    bundle: {
      pathRelativeToDestinationParent: `.compfuzor-adoptions/${sha256(Buffer.from("/fixtures/archive"))}/${"e".repeat(32)}/source.bundle`,
      sha256: D,
      verifiedHeads: [{ ref: refName("refs/stage/head"), oid: sourceOid }],
      freshRestoreVerified: true,
    },
    checks: {
      sourceFingerprintRechecked: true,
      sourceOdbUnchanged: true,
      destinationWorktreeUnchanged: true,
      bundleClosureVerified: true,
    },
    unresolved: [],
  };
}

test("typed ref lanes round-trip source names and never collide with HEAD/working-copy", () => {
  for (const name of ["head", "working-copy", "a/b", "żółć", "b00000001", "x".repeat(90)]) {
    const branchName = `refs/heads/${name}`;
    const target = pinRef(
      { sourceKind: "branch", sourceName: branchName, sourceOid: O("1"), destinationOid: O("1") },
      "legacy",
      "g0",
    );
    const encoded = target.split("/branch/")[1];
    assert.equal(decodeIdentity(encoded), name);
    assert.notEqual(
      target,
      pinRef(
        { sourceKind: "head", sourceName: "HEAD", sourceOid: O("1"), destinationOid: O("1") },
        "legacy",
        "g0",
      ),
    );
  }
  const tag = pinRef(
    { sourceKind: "tag", sourceName: "refs/tags/v1", sourceOid: O("2"), destinationOid: O("2") },
    "legacy",
    "g0",
  );
  assert.match(tag, /^refs\/tags\/harvest\/legacy\/g0\//);
  const candidate = candidateIdentity("stash-older", O("3"));
  const stash = pinRef(
    { sourceKind: "reflog", sourceName: candidate, sourceOid: O("3"), destinationOid: O("3") },
    "legacy",
    "g0",
  );
  assert.match(stash, /^refs\/adopt\/custody\/legacy\/g0\/reflog\//);
  assert.equal(decodeIdentity(stash.split("/reflog/")[1]), candidate);
  assert.equal(encodeIdentity(""), "b00000000/00");
  assert.equal(decodeIdentity("b00000000/00"), "");
  assert.throws(() => decodeIdentity("b00000001/0061"));
});

test("bad components, lossy paths, and unsafe vault paths are rejected", () => {
  for (const label of ["x/y", "a..b", "a.lock", ".private", "x?y", "x\ud800"])
    assert.throws(() => refComponent(label));
  assert.throws(() => repoPath(Buffer.from([0xff])));
  assert.throws(() => refName(Buffer.from([0xff])));
  assert.throws(() =>
    vaultBundlePath("/fixtures/archive", ".compfuzor-adoptions/../../etc/passwd"),
  );
  assert.throws(() =>
    vaultBundlePath(
      "/fixtures/archive",
      ".compfuzor-adoptions/wrong/0123456789abcdef0123456789abcdef/source.bundle",
    ),
  );
});

test("receipt canonical serialization includes nulls; parser rejects absent, extra, incompatible and noncanonical wire fields", () => {
  const receipt = sample();
  const encoded = encodeReceipt(receipt);
  assert.deepEqual(parseReceipt(encoded), receipt);
  assert.equal(Buffer.from(encoded).toString(), `${canonicalJson(receipt)}\n`);
  assert.equal(parseReceipt(encoded).snapshot, null);
  assert.throws(() =>
    parseReceipt(Buffer.from(JSON.stringify({ ...receipt, snapshot: undefined }))),
  );
  assert.throws(() => validateReceipt({ ...receipt, newField: true }));
  assert.throws(() => validateReceipt({ ...receipt, schema: "compfuzor.archive-adoption/v2" }));
  assert.throws(() => parseReceipt(Buffer.from(JSON.stringify(receipt))));
  assert.throws(() =>
    validateReceipt({
      ...receipt,
      bundle: { ...receipt.bundle, pathRelativeToDestinationParent: "../../escaped" },
    }),
  );
  assert.throws(() =>
    validateReceipt({
      ...receipt,
      pins: [
        { ...receipt.pins[0], destinationRef: refName("refs/heads/harvest/legacy/g0/head/dead") },
      ],
    }),
  );
});

test("exact reviewed path and staged/index loss are mandatory for dirty snapshot", () => {
  const clean = sample();
  const entry: PathEntry = { path: repoPath(".data/live.db-wal"), mode: "100644", blobOid: O("3") };
  const reviewInput = {
    schema: "compfuzor.archive-path-review/v1",
    manifestSha256: sha256(Buffer.from(`${canonicalJson([entry])}\n`)),
    included: [
      {
        path: entry.path,
        mode: entry.mode,
        blobOid: entry.blobOid,
        classification: "runtime-state",
        decision: "local-custody-approved",
        reason: "local custody only",
      },
    ],
    stagedVsUnstaged: { decision: "single-tree-approved", reason: "index split may be lost" },
  } as const;
  const review = parsePathReview(Buffer.from(JSON.stringify(reviewInput)), "sha1");
  const commitOid = O("4");
  const snapshot = {
    format: "worktree-v1",
    parentOid: clean.source.head.oid,
    treeOid: O("5"),
    commitOid,
    paths: [entry],
    stagedVsUnstaged: "reported-not-preserved",
    excludeFileSha256: null,
    excludedUntracked: [],
    ignoredPaths: [],
    trackedSensitivePaths: [entry.path],
    pathReview: review,
  } as const;
  const pin = {
    sourceKind: "working-copy",
    sourceName: "working-copy",
    sourceOid: commitOid,
    objectType: "commit",
    destinationOid: commitOid,
    destinationRef: pinRef(
      {
        sourceKind: "working-copy",
        sourceName: "working-copy",
        sourceOid: commitOid,
        destinationOid: commitOid,
      },
      "legacy",
      "g0",
      snapshot,
    ),
  } as const;
  const receipt: ReceiptV1 = { ...clean, snapshot, pins: [...clean.pins, pin] };
  assert.equal(
    parseReceipt(encodeReceipt(receipt)).snapshot?.pathReview?.fileSha256,
    sha256(Buffer.from(JSON.stringify(reviewInput))),
  );
  assert.throws(() =>
    validateReceipt({
      ...receipt,
      snapshot: { ...snapshot, pathReview: { ...review, stagedVsUnstaged: null } },
    }),
  );
  assert.throws(() =>
    validateReceipt({
      ...receipt,
      snapshot: { ...snapshot, paths: [{ ...entry, blobOid: O("6") }] },
    }),
  );
  assert.throws(() =>
    parsePathReview(Buffer.from(JSON.stringify({ ...reviewInput, fileSha256: D })), "sha1"),
  );
});

test("object-format validation rejects mixed SHA lengths", () => {
  assert.equal(oid("f".repeat(64), "sha256").length, 64);
  assert.throws(() => oid("f".repeat(64), "sha1"));
  assert.throws(() =>
    validateReceipt({ ...sample(), source: { ...sample().source, objectFormat: "sha256" } }),
  );
});

test("same-input retry discounts only its own installed refs and retains the original baseline", () => {
  const receipt = sample();
  const receiptCommitOid = O("6");
  const plan: PlanV1 = {
    schema: "compfuzor.archive-adoption-plan/v1",
    identity: { ...receipt.identity, createdAt: "later inspection" },
    source: receipt.source,
    proposedSnapshot: receipt.snapshot,
    baselines: {
      ...receipt.baselines,
      destinationPreRefs: [
        { name: receipt.receiptRef, oid: receiptCommitOid, objectType: "commit", peeledOid: null },
        {
          name: receipt.pins[0].destinationRef,
          oid: receipt.pins[0].destinationOid,
          objectType: "commit",
          peeledOid: null,
        },
      ],
      selectedTipsNotInDestination: 0,
    },
    pins: receipt.pins,
    blockers: [],
    warnings: [],
    retirementUnresolved: [],
  };
  const actual = new Map<string, string>([
    [receipt.receiptRef, receiptCommitOid],
    [receipt.pins[0].destinationRef, receipt.pins[0].destinationOid],
  ]);
  assert.equal(freshInstall(receipt, receiptCommitOid).matchingReceiptApproved, false);
  assert.equal(
    approveSameInputRetry(plan, receipt, receiptCommitOid, actual).matchingReceiptApproved,
    true,
  );
  assert.throws(
    () =>
      approveSameInputRetry(
        {
          ...plan,
          source: {
            ...plan.source,
            fingerprints: {
              ...plan.source.fingerprints,
              canonicalInputsSha256: digest("b".repeat(64)),
            },
          },
        },
        receipt,
        receiptCommitOid,
        actual,
      ),
    /source inventory/,
  );
  assert.throws(
    () =>
      approveSameInputRetry(
        plan,
        receipt,
        receiptCommitOid,
        new Map([...actual, ["refs/heads/main", O("1")]]),
      ),
    /fresh destination ref observation/,
  );
  assert.throws(
    () =>
      approveSameInputRetry(
        plan,
        receipt,
        receiptCommitOid,
        new Map([[receipt.receiptRef, receiptCommitOid]]),
      ),
    /fresh destination ref observation/,
  );
});
