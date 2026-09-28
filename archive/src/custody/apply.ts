/** Append-only adoption orchestration. No source or destination worktree writes. */
import { Effect } from "effect";
import { mkdtemp, open, readFile, rm } from "node:fs/promises";
import { constants } from "node:fs";
import { dirname, join } from "node:path";
import { gitChecked, readEnv, utf8Fatal } from "../repository/git.ts";
import { GitRefStore } from "../recovery/git-ref-store.ts";
import { approveSameInputRetry, freshInstall } from "../recovery/retry.ts";
import { installImmutableRefs, prefixConflict } from "../recovery/transaction.ts";
import { canonicalJson, encodeReceipt, oid, receiptRef, sha256 } from "./codec.ts";
import { CustodyError } from "./errors.ts";
import { planAdoption } from "./inventory.ts";
import type {
  AdoptInput,
  Oid,
  PinIntent,
  PlanV1,
  ReceiptV1,
  RefName,
  RepoPath,
  SealedBundle,
  Verification,
} from "./model.ts";
import {
  prepareSnapshot,
  proveBundle,
  checkBundleRestoration,
  type PrepareSnapshotInput,
} from "./stage.ts";
import { readReceipt, verifyAdoption } from "./verify.ts";
import { INTENT_NAME, resolveVaultBundle, sealBundle } from "./vault.ts";

export interface ApplyResult {
  readonly changed: boolean;
  readonly receiptRef: RefName;
  readonly receiptCommitOid: Oid;
  readonly verification: Verification;
}

const fail = (code: CustodyError["code"], detail: string): never => {
  throw new CustodyError(code, detail);
};
const ready = (plan: PlanV1): Extract<PlanV1, { state: "ready" }> => {
  if (plan.state !== "ready" || plan.blockers.length)
    throw new CustodyError(
      "invalid-input",
      `adoption blocked: ${plan.blockers.map((issue) => issue.code).join(", ")}`,
    );
  return plan;
};
const same = (a: unknown, b: unknown): boolean => canonicalJson(a) === canonicalJson(b);
const sortedRefPairs = (
  pairs: Iterable<readonly [string, string]>,
): readonly (readonly [string, string])[] =>
  [...pairs].sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0));

/** The intent stores the reviewed facts rather than a second receipt schema. */
function intentFacts(
  receipt: Pick<
    ReceiptV1,
    "identity" | "source" | "snapshot" | "cleanHeadPathReview" | "baselines" | "pins" | "unresolved"
  >,
  bundle: Pick<ReceiptV1["bundle"], "sha256" | "verifiedHeads">,
) {
  return {
    identity: receipt.identity,
    source: receipt.source,
    snapshot: receipt.snapshot,
    cleanHeadPathReview: receipt.cleanHeadPathReview,
    baselines: receipt.baselines,
    pins: receipt.pins,
    bundleSha256: bundle.sha256,
    verifiedHeads: bundle.verifiedHeads,
    unresolved: receipt.unresolved,
  };
}
const intentBytes = (facts: ReturnType<typeof intentFacts>): Uint8Array =>
  new TextEncoder().encode(`${canonicalJson(facts)}\n`);

function receiptFacts(
  plan: Extract<PlanV1, { state: "ready" }>,
  snapshot: ReceiptV1["snapshot"],
  pins: readonly PinIntent[],
): Pick<
  ReceiptV1,
  "identity" | "source" | "snapshot" | "cleanHeadPathReview" | "baselines" | "pins" | "unresolved"
> {
  return {
    identity: plan.identity,
    source: plan.source,
    snapshot,
    cleanHeadPathReview: plan.cleanHeadPathReview,
    baselines: plan.baselines,
    pins,
    unresolved: plan.retirementUnresolved,
  };
}

function receiptOf(
  plan: Extract<PlanV1, { state: "ready" }>,
  facts: ReturnType<typeof receiptFacts>,
  bundle: SealedBundle,
): ReceiptV1 {
  return {
    schema: "compfuzor.archive-adoption/v1",
    receiptRef: receiptRef(plan.identity.label, plan.identity.generation),
    ...facts,
    bundle,
    checks: {
      sourceFingerprintRechecked: true,
      sourceOdbUnchanged: true,
      destinationWorktreeUnchanged: true,
      bundleClosureVerified: true,
    },
  };
}

/** Reinspect exact immutable input and worktree/index/refs before proceeding. */
function recheck(first: Extract<PlanV1, { state: "ready" }>, next: PlanV1, retry: boolean): void {
  const now = ready(next);
  if (
    !same(first.source, now.source) ||
    !same(first.proposedSnapshot, now.proposedSnapshot) ||
    !same(first.pins, now.pins) ||
    !same(first.cleanHeadPathReview, now.cleanHeadPathReview) ||
    first.identity.legacyRealpathAtCapture !== now.identity.legacyRealpathAtCapture ||
    first.identity.destinationRealpath !== now.identity.destinationRealpath
  )
    fail("source-drift", "source inventory or reviewed snapshot changed during apply");
  for (const key of [
    "destinationWorktreeFingerprintSha256",
    "destinationIndexSha256",
    "selectedBranch",
    "declaredRepo",
  ] as const)
    if (!same(first.baselines[key], now.baselines[key]))
      fail("destination-drift", `destination baseline changed during apply: ${key}`);
  // Fresh installs may not introduce *any* new destination refs. Retry plans
  // observe their own receipt/pins, whose identities are checked separately.
  if (!retry && !same(first.baselines.destinationPreRefs, now.baselines.destinationPreRefs))
    fail("destination-drift", "destination refs changed during apply");
}

const mutation = (
  args: readonly string[],
  cwd: string,
  input?: Uint8Array,
  env?: Record<string, string>,
) =>
  gitChecked(args, { cwd, input, env: { ...readEnv, ...env } }).pipe(
    Effect.mapError(
      (error) =>
        new CustodyError(
          "inspection-failed",
          `private Git object transfer failed: ${error.message}`,
        ),
    ),
  );

/** Unbundle writes only objects; it does not fetch a branch or touch FETCH_HEAD. */
function importBundle(dest: string, bundlePath: string): Effect.Effect<void, CustodyError> {
  return mutation(["bundle", "unbundle", bundlePath], dest).pipe(Effect.asVoid);
}

/** Pack the parentless metadata commit from scratch, import without changing any refs. */
function importReceipt(
  dest: string,
  stageGitDir: string,
  commitOid: Oid,
): Effect.Effect<void, CustodyError> {
  return Effect.gen(function* () {
    const pack = yield* mutation(
      ["pack-objects", "--stdout", "--revs"],
      stageGitDir,
      new TextEncoder().encode(`${commitOid}\n`),
      { GIT_DIR: stageGitDir, GIT_OBJECT_DIRECTORY: join(stageGitDir, "objects") },
    );
    yield* mutation(["index-pack", "--stdin"], dest, pack);
  });
}

function stagePaths(plan: Extract<PlanV1, { state: "ready" }>): readonly RepoPath[] {
  // Must match inventory's preview request, not reconstruct a different
  // selection from Git's rename/index observations.
  return [...new Set(plan.source.worktreeChanges.map(({ path }) => path))];
}

function stageRequest(
  plan: Extract<PlanV1, { state: "ready" }>,
  scratchRoot: string,
): PrepareSnapshotInput {
  const proposal = plan.proposedSnapshot;
  return {
    sourceRoot: plan.identity.legacyRealpathAtCapture,
    scratchRoot,
    objectFormat: plan.source.objectFormat,
    headOid: plan.source.head.oid,
    restageTracked: stagePaths(plan),
    addUntracked: plan.source.untrackedPaths.filter(
      (path) => !plan.source.excludedUntracked.includes(path),
    ),
    stagedVsUnstaged: proposal?.stagedVsUnstaged ?? "none",
    excludeFileSha256: plan.source.excludeFileSha256,
    excludedUntracked: plan.source.excludedUntracked,
    ignoredPaths: plan.source.ignoredPaths,
    trackedSensitivePaths: plan.source.trackedSensitivePaths.map(
      ({ subject }) => subject as RepoPath,
    ),
    pathReview: proposal?.pathReview ?? null,
    expected: proposal?.paths ?? plan.source.head.treePaths,
  };
}

/** One parentless fixed-metadata commit, isolated in the already private stage. */
function mintReceipt(stageGitDir: string, receipt: ReceiptV1): Effect.Effect<Oid, CustodyError> {
  return Effect.gen(function* () {
    const env = { GIT_DIR: stageGitDir, GIT_OBJECT_DIRECTORY: join(stageGitDir, "objects") };
    const blob = oid(
      utf8Fatal(
        yield* mutation(["hash-object", "-w", "--stdin"], stageGitDir, encodeReceipt(receipt), env),
      ).trim(),
      receipt.source.objectFormat,
    );
    const tree = oid(
      utf8Fatal(
        yield* mutation(
          ["mktree", "-z"],
          stageGitDir,
          new TextEncoder().encode(`100644 blob ${blob}\tadoption.json\0`),
          env,
        ),
      ).trim(),
      receipt.source.objectFormat,
    );
    const commit = yield* mutation(
      ["commit-tree", tree, "-m", "compfuzor archive adoption receipt (v1)"],
      stageGitDir,
      undefined,
      {
        ...env,
        GIT_AUTHOR_NAME: "compfuzor archive",
        GIT_AUTHOR_EMAIL: "archive@compfuzor.invalid",
        GIT_COMMITTER_NAME: "compfuzor archive",
        GIT_COMMITTER_EMAIL: "archive@compfuzor.invalid",
        GIT_AUTHOR_DATE: "@0 +0000",
        GIT_COMMITTER_DATE: "@0 +0000",
      },
    );
    return oid(utf8Fatal(commit).trim(), receipt.source.objectFormat);
  });
}

/** No ref prefix collision or orphan pin may be allowed through staging. */
function precheck(
  refs: ReadonlyMap<string, string>,
  ref: RefName,
  pins: readonly PinIntent[],
): void {
  const desired = [ref, ...pins.map((pin) => pin.destinationRef)];
  for (const name of desired) {
    if (refs.has(name)) fail("occupied-namespace", `custody ref already exists: ${name}`);
    for (const existing of refs.keys())
      if (prefixConflict(name, existing))
        fail("occupied-namespace", `custody ref prefix conflict: ${name} / ${existing}`);
  }
  const label = ref.split("/")[3];
  for (const old of [
    `refs/heads/harvest/${label}/head`,
    `refs/heads/harvest/${label}/working-copy`,
  ])
    if (refs.has(old)) fail("occupied-namespace", `old harvest namespace occupied: ${old}`);
}

function assertObservedRefs(
  plan: Extract<PlanV1, { state: "ready" }>,
  actual: ReadonlyMap<string, string>,
): void {
  const observed = plan.baselines.destinationPreRefs.map(({ name, oid }): [string, string] => [
    name as string,
    oid as string,
  ]);
  if (!same(sortedRefPairs(observed), sortedRefPairs(actual)))
    fail("destination-drift", "destination refs changed since the read-only plan");
}

/** The receipt's own refs are the only discounted entries on retry. */
function retryRefsUnchanged(
  plan: Extract<PlanV1, { state: "ready" }>,
  original: ReceiptV1,
  current: ReadonlyMap<string, string>,
  commitOid: Oid,
): void {
  const expected = new Map([
    [original.receiptRef as string, commitOid as string],
    ...original.pins.map((pin): [string, string] => [pin.destinationRef, pin.destinationOid]),
  ]);
  const clean = new Map([...current].filter(([name]) => !expected.has(name)));
  const baseline = new Map(
    original.baselines.destinationPreRefs.map(({ name, oid }) => [name as string, oid as string]),
  );
  if (!same(sortedRefPairs(clean), sortedRefPairs(baseline)))
    fail("destination-drift", "destination refs changed since original receipt");
  // approveSameInputRetry additionally compares the freshly observed ref map.
  const observed = plan.baselines.destinationPreRefs.map(({ name, oid }): [string, string] => [
    name,
    oid,
  ]);
  if (!same(sortedRefPairs(observed), sortedRefPairs(current)))
    fail("destination-drift", "destination ref observation changed");
}

/** Fail closed until every independent proof passes; historical drift is diagnostic. */
function verified(report: Verification): Verification {
  if (!report.custodyVerified || report.custodyFailures.length)
    fail(
      "verification-failed",
      `independent custody verification failed: ${report.custodyFailures.map((i) => i.code).join(", ")}`,
    );
  return report;
}

/** Promise adapters only around the existing legacy Promise-based seams. */
const fromPromise = <A>(
  operation: (signal: AbortSignal) => Promise<A>,
  code: CustodyError["code"],
): Effect.Effect<A, CustodyError> =>
  Effect.tryPromise({
    try: operation,
    catch: (error) =>
      error instanceof CustodyError
        ? error
        : new CustodyError(code, error instanceof Error ? error.message : String(error)),
  });

/** A test may stop at a single boundary, without altering production transfer semantics. */
export interface ApplyTestHooks {
  readonly afterSeal?: () => Promise<void>;
  readonly afterTransfer?: () => Promise<void>;
  readonly afterInstall?: () => Promise<void>;
}

const hook = (action: (() => Promise<void>) | undefined): Effect.Effect<void, CustodyError> =>
  action === undefined ? Effect.void : fromPromise(action, "inspection-failed");

function proveExistingBundle(
  receipt: ReceiptV1,
  dest: string,
  scratchRoot: string,
): Effect.Effect<string, CustodyError> {
  return Effect.gen(function* () {
    const bundlePath = yield* fromPromise(
      () => resolveVaultBundle(receipt, dest),
      "bundle-invalid",
    );
    const intent = yield* fromPromise(async (signal) => {
      const file = await open(
        join(dirname(bundlePath), INTENT_NAME),
        constants.O_RDONLY | constants.O_NOFOLLOW,
      );
      try {
        if (!(await file.stat()).isFile())
          fail("bundle-invalid", "existing intent is not a regular file");
        return file.readFile({ signal });
      } finally {
        await file.close();
      }
    }, "bundle-invalid");
    const expectedIntent = intentBytes(intentFacts(receipt, receipt.bundle));
    if (!Buffer.from(intent).equals(Buffer.from(expectedIntent)))
      fail("different-receipt", "sealed original intent does not match existing receipt");
    const bytes = yield* fromPromise(
      (signal) => readFile(bundlePath, { signal }),
      "bundle-invalid",
    );
    if (sha256(bytes) !== receipt.bundle.sha256)
      fail("bundle-invalid", "existing receipt bundle checksum mismatch");
    const proof = yield* fromPromise(
      (signal) =>
        checkBundleRestoration(
          {
            bundlePath,
            objectFormat: receipt.source.objectFormat,
            scratchRoot,
            pins: receipt.pins,
            snapshot:
              receipt.snapshot === null
                ? null
                : {
                    commitOid: receipt.snapshot.commitOid,
                    treeOid: receipt.snapshot.treeOid,
                    paths: receipt.snapshot.paths,
                  },
          },
          { signal },
        ),
      "bundle-invalid",
    );
    if (!same(proof.verifiedHeads, receipt.bundle.verifiedHeads))
      fail("bundle-invalid", "existing receipt bundle advertises different pin heads");
    return bundlePath;
  });
}

/**
 * Replan on every invocation. The existing receipt, if any, wins over a fresh
 * timestamp or vault: its original intent and baseline are immutable. All
 * destination writes are object-only until one atomic compare/create of refs.
 */
export const applyAdoption = (
  input: AdoptInput,
  testHooks: ApplyTestHooks = {},
): Effect.Effect<ApplyResult, CustodyError> =>
  Effect.gen(function* () {
    const plan = ready(yield* planAdoption(input));
    const dest = plan.identity.destinationRealpath;
    const ref = receiptRef(plan.identity.label, plan.identity.generation);
    const listRefs = () =>
      fromPromise((signal) => new GitRefStore(dest, { signal }).list(), "inspection-failed");
    const current = yield* listRefs();
    assertObservedRefs(plan, current);

    // Existing receipt first: no stage, no freshly sealed bundle, and no
    // invented timestamp on a same-generation retry.
    if (current.has(ref)) {
      const original = yield* fromPromise(
        (signal) => readReceipt(dest, ref, { signal }),
        "different-receipt",
      );
      const receipt = original.receipt;
      if (original.receiptCommitOid !== current.get(ref))
        fail("ref-race", "receipt ref changed while it was being read");
      retryRefsUnchanged(plan, receipt, current, original.receiptCommitOid);
      const install = approveSameInputRetry(plan, receipt, original.receiptCommitOid, current);
      const scratch = yield* fromPromise(
        () => mkdtemp(join(dirname(dest), ".compfuzor-verify-")),
        "inspection-failed",
      );
      // Disposable restoration scratch is removed only on success; a failed
      // attempt retains the private evidence for diagnosis.
      yield* proveExistingBundle(receipt, dest, scratch);
      const checked = ready(yield* planAdoption(input));
      recheck(plan, checked, true);
      const beforeInstall = yield* listRefs();
      retryRefsUnchanged(checked, receipt, beforeInstall, original.receiptCommitOid);
      approveSameInputRetry(checked, receipt, original.receiptCommitOid, beforeInstall);
      const changed = yield* fromPromise(
        (signal) => installImmutableRefs(new GitRefStore(dest, { signal }), install),
        "ref-race",
      );
      yield* hook(testHooks.afterInstall);
      const verification = verified(
        yield* fromPromise(
          (signal) =>
            verifyAdoption(
              {
                dest,
                receiptRef: ref,
                legacy: input.legacy,
                scratchRoot: scratch,
              },
              { signal },
            ),
          "verification-failed",
        ),
      );
      yield* fromPromise(() => rm(scratch, { recursive: true, force: true }), "inspection-failed");
      return {
        changed: changed.changed,
        receiptRef: ref,
        receiptCommitOid: original.receiptCommitOid,
        verification,
      };
    }

    precheck(current, ref, plan.pins);
    const scratch = yield* fromPromise(
      () => mkdtemp(join(dirname(dest), ".compfuzor-stage-")),
      "inspection-failed",
    );
    const stage = yield* fromPromise(
      (signal) => prepareSnapshot(stageRequest(plan, scratch), { signal }),
      "source-drift",
    );
    if (!same(stage.snapshot, plan.proposedSnapshot))
      fail("source-drift", "private stage differs from the exact reviewed snapshot");
    if (
      stage.snapshot !== null &&
      !plan.pins.some(
        ({ sourceKind, sourceOid }) =>
          sourceKind === "working-copy" && sourceOid === stage.snapshot?.commitOid,
      )
    )
      fail("invalid-input", "ready dirty plan has no exact working-copy pin");
    recheck(plan, yield* planAdoption(input), false);
    const proven = yield* fromPromise(
      (signal) => proveBundle(stage, plan.pins, { signal }),
      "bundle-invalid",
    );
    recheck(plan, yield* planAdoption(input), false);
    const facts = receiptFacts(plan, stage.snapshot, plan.pins);
    const sealed = yield* fromPromise(
      (signal) =>
        sealBundle(
          {
            destRealpath: dest,
            legacyRealpath: plan.identity.legacyRealpathAtCapture,
            proven,
            intent: intentBytes(
              intentFacts(facts, {
                sha256: proven.bundleSha256,
                verifiedHeads: proven.verifiedHeads,
              }),
            ),
          },
          { signal },
        ),
      "bundle-invalid",
    );
    yield* hook(testHooks.afterSeal);
    const receipt = receiptOf(plan, facts, sealed.sealed);
    const commitOid = yield* mintReceipt(stage.gitDir, receipt);
    // The sealed vault is already durable; a crash/abort leaves it intact for
    // diagnosis. No destination ref has changed yet.
    yield* importBundle(dest, sealed.run.bundlePath);
    yield* importReceipt(dest, stage.gitDir, commitOid);
    yield* hook(testHooks.afterTransfer);
    recheck(plan, yield* planAdoption(input), false);
    const immediatelyBefore = yield* listRefs();
    assertObservedRefs(plan, immediatelyBefore);
    const installed = yield* fromPromise(
      (signal) =>
        installImmutableRefs(new GitRefStore(dest, { signal }), freshInstall(receipt, commitOid)),
      "ref-race",
    );
    yield* hook(testHooks.afterInstall);
    const verification = verified(
      yield* fromPromise(
        (signal) =>
          verifyAdoption(
            {
              dest,
              receiptRef: ref,
              legacy: input.legacy,
              scratchRoot: scratch,
            },
            { signal },
          ),
        "verification-failed",
      ),
    );
    yield* fromPromise(() => rm(scratch, { recursive: true, force: true }), "inspection-failed");
    return {
      changed: installed.changed,
      receiptRef: ref,
      receiptCommitOid: commitOid,
      verification,
    };
  }).pipe(
    Effect.catchDefect((defect) =>
      Effect.fail(
        defect instanceof CustodyError
          ? defect
          : new CustodyError("inspection-failed", `unexpected apply defect: ${String(defect)}`),
      ),
    ),
  );
