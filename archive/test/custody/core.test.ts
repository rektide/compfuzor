import assert from "node:assert/strict";
import { test } from "node:test";
import {
  canonicalJson,
  candidateIdentity,
  decodeIdentity,
  destinationRefsSha256,
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
import type { PathEntry, PinIntent, ReceiptV1, SnapshotProposal } from "../../src/custody/model.ts";
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
    cleanHeadPathReview: null,
    baselines: {
      sourceRemoteTracking: [],
      destinationPreRefs: [],
      destinationPreRefsSha256: destinationRefsSha256([]),
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
      verifiedHeads: [{ ref: pin.destinationRef, oid: sourceOid }],
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
  assert.equal(refName("refs/stash"), "refs/stash");
  assert.equal(refName("refs/notes/x"), "refs/notes/x");
  assert.throws(() => refName("stash"));
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
  const receipt: ReceiptV1 = {
    ...clean,
    snapshot,
    pins: [...clean.pins, pin],
    bundle: {
      ...clean.bundle,
      verifiedHeads: [...clean.bundle.verifiedHeads, { ref: pin.destinationRef, oid: commitOid }],
    },
  };
  assert.equal(
    parseReceipt(encodeReceipt(receipt)).snapshot?.pathReview?.fileSha256,
    sha256(Buffer.from(JSON.stringify(reviewInput))),
  );
  assert.throws(
    () => validateReceipt({ ...receipt, cleanHeadPathReview: review }),
    /clean HEAD review cannot stand in/,
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

test("clean tracked-sensitive HEAD requires an exact, locally approved HEAD manifest", () => {
  const clean = sample();
  const entry: PathEntry = { path: repoPath("config/key.pem"), mode: "100644", blobOid: O("3") };
  const sensitive = {
    code: "tracked-sensitive-path",
    subject: entry.path,
    reason: "credential: local custody review required, not publication approval",
  };
  const source = {
    ...clean.source,
    head: { ...clean.source.head, treePaths: [entry] },
    trackedSensitivePaths: [sensitive],
  };
  const missingReview = { ...clean, source };
  assert.throws(() => validateReceipt(missingReview), /clean HEAD.*local custody review/);
  const input = {
    schema: "compfuzor.archive-path-review/v1",
    manifestSha256: sha256(Buffer.from(`${canonicalJson([entry])}\n`)),
    included: [
      {
        ...entry,
        classification: "credential",
        decision: "local-custody-approved",
        reason: "approved private custody, not publication",
      },
    ],
    stagedVsUnstaged: null,
  };
  const review = parsePathReview(Buffer.from(JSON.stringify(input)), "sha1");
  const approved: ReceiptV1 = { ...missingReview, cleanHeadPathReview: review };
  assert.deepEqual(parseReceipt(encodeReceipt(approved)), approved);
  assert.throws(
    () =>
      validateReceipt({
        ...approved,
        cleanHeadPathReview: {
          ...review,
          manifestSha256: D,
        },
      }),
    /clean HEAD review manifest/,
  );
  assert.throws(
    () =>
      validateReceipt({
        ...approved,
        cleanHeadPathReview: {
          ...review,
          included: [{ ...review.included[0], blobOid: O("4") }],
        },
      }),
    /stale or repeated file/,
  );
  assert.throws(
    () =>
      validateReceipt({
        ...approved,
        cleanHeadPathReview: {
          ...review,
          included: [],
        },
      }),
    /sensitive tracked HEAD path/,
  );
  assert.throws(
    () =>
      validateReceipt({
        ...approved,
        cleanHeadPathReview: {
          ...review,
          stagedVsUnstaged: { decision: "single-tree-approved", reason: "not needed" },
        },
      }),
    /clean HEAD review cannot approve/,
  );
});

test("blocked plan may expose a reviewless exact snapshot proposal without becoming ready", () => {
  const receipt = sample();
  const entry: PathEntry = { path: repoPath("config/key.pem"), mode: "100644", blobOid: O("3") };
  const proposal: SnapshotProposal = {
    format: "worktree-v1",
    parentOid: receipt.source.head.oid,
    treeOid: O("4"),
    commitOid: O("5"),
    paths: [entry],
    manifestSha256: sha256(Buffer.from(`${canonicalJson([entry])}\n`)),
    stagedVsUnstaged: "reported-not-preserved",
    excludeFileSha256: null,
    excludedUntracked: [],
    ignoredPaths: [],
    trackedSensitivePaths: [entry.path],
    reviewRequirements: { sensitivePaths: [entry.path], stagedVsUnstagedApprovalRequired: true },
  };
  const blocked: PlanV1 = {
    schema: "compfuzor.archive-adoption-plan/v1",
    state: "blocked",
    headManifestSha256: sha256(Buffer.from(`${canonicalJson(receipt.source.head.treePaths)}\n`)),
    identity: receipt.identity,
    source: receipt.source,
    proposedSnapshot: proposal,
    cleanHeadPathReview: null,
    baselines: receipt.baselines,
    pins: null,
    blockers: [{ code: "path-review-required", subject: entry.path, reason: "needs approval" }],
    warnings: [],
    retirementUnresolved: [],
  };
  assert.equal(blocked.proposedSnapshot?.manifestSha256, proposal.manifestSha256);
  assert.throws(() => approveSameInputRetry(blocked, receipt, O("6"), new Map()), /apply blockers/);
});

test("object-format validation rejects mixed SHA lengths", () => {
  assert.equal(oid("f".repeat(64), "sha256").length, 64);
  assert.throws(() => oid("f".repeat(64), "sha1"));
  assert.throws(() =>
    validateReceipt({ ...sample(), source: { ...sample().source, objectFormat: "sha256" } }),
  );
});

test("receipt cannot silently omit named refs, selected candidates, or tracked internals", () => {
  const receipt = sample();
  const branch = {
    name: refName("refs/heads/topic"),
    oid: O("2"),
    objectType: "commit" as const,
    peeledOid: null,
  };
  assert.throws(
    () => validateReceipt({ ...receipt, source: { ...receipt.source, refs: [branch] } }),
    /source ref lacks a custody pin/,
  );
  assert.throws(
    () =>
      validateReceipt({
        ...receipt,
        source: {
          ...receipt.source,
          candidates: [
            {
              kind: "reflog",
              oid: O("2"),
              objectType: "commit",
              provenance: [],
              disposition: "pin",
              reason: null,
            },
          ],
        },
      }),
    /selected candidate lacks a custody pin/,
  );
  assert.throws(
    () =>
      validateReceipt({
        ...receipt,
        source: {
          ...receipt.source,
          candidates: [
            {
              kind: "dangling",
              oid: O("2"),
              objectType: "commit",
              provenance: [],
              disposition: "not-required",
              reason: null,
            },
          ],
        },
      }),
    /operator reason/,
  );
  assert.throws(
    () =>
      validateReceipt({
        ...receipt,
        source: {
          ...receipt.source,
          head: {
            ...receipt.source.head,
            treePaths: [{ path: repoPath(".jj/store/secret"), mode: "100644", blobOid: O("2") }],
          },
        },
      }),
    /tracked Git\/jj internals/,
  );
});

test("stash ref and typed stash pin round-trip; candidate identities bind selection, OID and type", () => {
  const receipt = sample();
  const stash = {
    name: refName("refs/stash"),
    oid: O("2"),
    objectType: "commit" as const,
    peeledOid: null,
  };
  const stashPin: PinIntent = {
    sourceKind: "stash",
    sourceName: stash.name,
    sourceOid: stash.oid,
    objectType: "commit",
    destinationOid: stash.oid,
    destinationRef: pinRef(
      {
        sourceKind: "stash",
        sourceName: stash.name,
        sourceOid: stash.oid,
        destinationOid: stash.oid,
      },
      "legacy",
      "g0",
    ),
  };
  const selected = {
    kind: "stash-older" as const,
    oid: O("3"),
    objectType: "commit" as const,
    provenance: ["reflog"],
    disposition: "pin" as const,
    reason: null,
  };
  const candidatePin: PinIntent = {
    sourceKind: "reflog",
    sourceName: candidateIdentity(selected.kind, selected.oid),
    sourceOid: selected.oid,
    objectType: "commit",
    destinationOid: selected.oid,
    destinationRef: pinRef(
      {
        sourceKind: "reflog",
        sourceName: candidateIdentity(selected.kind, selected.oid),
        sourceOid: selected.oid,
        destinationOid: selected.oid,
      },
      "legacy",
      "g0",
    ),
  };
  const full: ReceiptV1 = {
    ...receipt,
    source: { ...receipt.source, refs: [stash], candidates: [selected] },
    pins: [...receipt.pins, stashPin, candidatePin],
    bundle: {
      ...receipt.bundle,
      verifiedHeads: [
        ...receipt.bundle.verifiedHeads,
        { ref: stashPin.destinationRef, oid: stash.oid },
        { ref: candidatePin.destinationRef, oid: selected.oid },
      ],
    },
  };
  assert.deepEqual(parseReceipt(encodeReceipt(full)), full);
  assert.throws(
    () =>
      validateReceipt({
        ...full,
        pins: full.pins.map((pin) =>
          pin === candidatePin
            ? {
                ...pin,
                sourceName: `stash-older:${"4".repeat(40)}`,
                destinationRef: pinRef(
                  { ...pin, sourceName: `stash-older:${"4".repeat(40)}` },
                  "legacy",
                  "g0",
                ),
              }
            : pin,
        ),
      }),
    /candidate pin identity/,
  );
  assert.throws(
    () =>
      validateReceipt({
        ...full,
        pins: full.pins.map((pin) =>
          pin === candidatePin
            ? {
                ...pin,
                sourceName: `stash-older:${"3".repeat(64)}`,
                destinationRef: pinRef(
                  { ...pin, sourceName: `stash-older:${"3".repeat(64)}` },
                  "legacy",
                  "g0",
                ),
              }
            : pin,
        ),
      }),
    /invalid sha1 object ID/,
  );
  assert.throws(
    () =>
      validateReceipt({
        ...full,
        source: {
          ...full.source,
          candidates: [{ ...selected, disposition: "not-required", reason: "excluded" }],
        },
      }),
    /candidate pin lacks selected/,
  );
  assert.throws(
    () =>
      validateReceipt({
        ...full,
        bundle: { ...full.bundle, verifiedHeads: full.bundle.verifiedHeads.slice(0, -1) },
      }),
    /bundle heads/,
  );
  assert.throws(
    () =>
      validateReceipt({
        ...full,
        bundle: {
          ...full.bundle,
          verifiedHeads: full.bundle.verifiedHeads.map((head, index) =>
            index === 1 ? { ...head, ref: refName("refs/heads/unrelated") } : head,
          ),
        },
      }),
    /bundle heads/,
  );
  assert.throws(
    () =>
      validateReceipt({
        ...full,
        bundle: {
          ...full.bundle,
          verifiedHeads: [
            ...full.bundle.verifiedHeads,
            { ref: refName("refs/stage/extra"), oid: O("4") },
          ],
        },
      }),
    /bundle heads/,
  );
});

test("destination baseline rejects repeated ref names and hashes raw inventory format", () => {
  const receipt = sample();
  const ref = {
    name: refName("refs/stash"),
    oid: O("2"),
    objectType: "commit" as const,
    peeledOid: null,
  };
  const hash = sha256(Buffer.from(`refs/stash\0${ref.oid}\0commit\0\0\n`));
  assert.equal(destinationRefsSha256([ref]), hash);
  const withRef = {
    ...receipt,
    baselines: { ...receipt.baselines, destinationPreRefs: [ref], destinationPreRefsSha256: hash },
  };
  validateReceipt(withRef);
  assert.throws(
    () =>
      validateReceipt({
        ...withRef,
        baselines: { ...withRef.baselines, destinationPreRefs: [ref, ref] },
      }),
    /duplicate ref/,
  );
  assert.throws(
    () =>
      validateReceipt({
        ...withRef,
        baselines: { ...withRef.baselines, destinationPreRefsSha256: D },
      }),
    /pre-ref hash/,
  );
  assert.throws(
    () => validateReceipt({ ...receipt, source: { ...receipt.source, refs: [ref, ref] } }),
    /duplicate ref/,
  );
});

test("same-input retry discounts only its own installed refs and retains the original baseline", () => {
  const receipt = sample();
  const receiptCommitOid = O("6");
  const plan: PlanV1 = {
    schema: "compfuzor.archive-adoption-plan/v1",
    state: "ready",
    headManifestSha256: sha256(Buffer.from(`${canonicalJson(receipt.source.head.treePaths)}\n`)),
    identity: { ...receipt.identity, createdAt: "later inspection" },
    source: receipt.source,
    proposedSnapshot: receipt.snapshot,
    cleanHeadPathReview: receipt.cleanHeadPathReview,
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
        {
          ...plan,
          state: "blocked",
          source: { ...plan.source, head: null },
          proposedSnapshot: null,
          cleanHeadPathReview: null,
          baselines: null,
          pins: null,
          blockers: [{ code: "unborn-head", subject: "HEAD", reason: "no commit" }],
        },
        receipt,
        receiptCommitOid,
        actual,
      ),
    /apply blockers/,
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

test("retry ignores ordering of independent pins and refs, but not ordered candidate provenance", () => {
  const receipt = sample();
  const branch = {
    name: refName("refs/heads/topic"),
    oid: O("2"),
    objectType: "commit" as const,
    peeledOid: null,
  };
  const tag = {
    name: refName("refs/tags/v1"),
    oid: O("3"),
    objectType: "tag" as const,
    peeledOid: O("2"),
  };
  const pins: PinIntent[] = [
    ...receipt.pins,
    ...([branch, tag] as const).map(({ name, oid: sourceOid, objectType }) => {
      const sourceKind = name.startsWith("refs/tags/") ? ("tag" as const) : ("branch" as const);
      return {
        sourceKind,
        sourceName: name,
        sourceOid,
        objectType,
        destinationOid: sourceOid,
        destinationRef: pinRef(
          { sourceKind, sourceName: name, sourceOid, destinationOid: sourceOid },
          "legacy",
          "g0",
        ),
      };
    }),
  ];
  const selected = {
    kind: "reflog" as const,
    oid: O("4"),
    objectType: "commit" as const,
    provenance: ["first", "second"],
    disposition: "pin" as const,
    reason: null,
  };
  pins.push({
    sourceKind: "reflog",
    sourceName: candidateIdentity(selected.kind, selected.oid),
    sourceOid: selected.oid,
    objectType: "commit",
    destinationOid: selected.oid,
    destinationRef: pinRef(
      {
        sourceKind: "reflog",
        sourceName: candidateIdentity(selected.kind, selected.oid),
        sourceOid: selected.oid,
        destinationOid: selected.oid,
      },
      "legacy",
      "g0",
    ),
  });
  const full: ReceiptV1 = {
    ...receipt,
    source: { ...receipt.source, refs: [branch, tag], candidates: [selected] },
    pins,
    bundle: {
      ...receipt.bundle,
      verifiedHeads: [
        ...receipt.bundle.verifiedHeads,
        ...pins.slice(1).map(({ destinationRef, destinationOid }) => ({
          ref: destinationRef,
          oid: destinationOid,
        })),
      ],
    },
  };
  const commit = O("6");
  const present = new Map<string, string>([
    [full.receiptRef, commit],
    ...pins.map(({ destinationRef, destinationOid }) => [destinationRef, destinationOid] as const),
  ]);
  const plan: PlanV1 = {
    schema: "compfuzor.archive-adoption-plan/v1",
    state: "ready",
    headManifestSha256: sha256(Buffer.from(`${canonicalJson(full.source.head.treePaths)}\n`)),
    identity: full.identity,
    source: { ...full.source, refs: [tag, branch] },
    proposedSnapshot: null,
    cleanHeadPathReview: null,
    pins: [...pins].reverse(),
    baselines: {
      ...full.baselines,
      destinationPreRefs: [...present].map(([name, target]) => ({
        name: refName(name),
        oid: oid(target, "sha1"),
        objectType: "commit" as const,
        peeledOid: null,
      })),
    },
    blockers: [],
    warnings: [],
    retirementUnresolved: [],
  };
  assert.equal(approveSameInputRetry(plan, full, commit, present).matchingReceiptApproved, true);
  assert.throws(
    () =>
      approveSameInputRetry(
        {
          ...plan,
          source: {
            ...plan.source,
            candidates: [{ ...selected, provenance: [...selected.provenance].reverse() }],
          },
        },
        full,
        commit,
        present,
      ),
    /source inventory/,
  );
  assert.throws(
    () =>
      approveSameInputRetry(
        {
          ...plan,
          baselines: {
            ...plan.baselines,
            destinationPreRefs: [
              ...plan.baselines.destinationPreRefs,
              plan.baselines.destinationPreRefs[0],
            ],
          },
        },
        full,
        commit,
        present,
      ),
    /duplicate fresh destination ref/,
  );
});
