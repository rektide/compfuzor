/**
 * `planAdoption`: the read-only adoption plan for a standalone Git checkout.
 *
 * The plan is an observation, not a reservation: dirty work is previewed in
 * disposable private scratch, and approved snapshots may be planned, but no
 * source or destination repository is mutated. Missing destinations report
 * `destination-missing` pending deliberate cloning.
 *
 * Failure model: invalid operator input (bad label/generation/branch, a
 * dispositions or path-review file that does not parse, unknown disposition
 * identities, nested/aliased paths) fails the Effect with `CustodyError`.
 * Every inspection or admission problem is a blocker inside a successful
 * `PlanV1` — never a fabricated fact, never an inferred empty set.
 */
import { Effect, Result } from "effect";
import { lstat, mkdtemp, readFile, realpath, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { gitRead } from "../repository/git.ts";
import { previewSnapshot } from "./stage.ts";
import {
  canonicalJson,
  candidateIdentity,
  parsePathReview,
  pinRef,
  refComponent,
  refName,
  sha256,
} from "./codec.ts";
import { CustodyError, invalid } from "./errors.ts";
import type {
  AdoptInput,
  DestinationBaseline,
  GitTip,
  Issue,
  Oid,
  PinIntent,
  PlanV1,
  RemoteBaseline,
  RepoPath,
  Sha256,
  Snapshot,
  SnapshotProposal,
  SourceInventory,
} from "./model.ts";
import { parseCount } from "./inventory/decode.ts";
import { destinationJjView, sourceJjView } from "./inventory/jj.ts";
import { probeDestination, probeSource } from "./inventory/probe.ts";

const encoder = new TextEncoder();

export interface Dispositions {
  readonly decisions: ReadonlyMap<
    string,
    { disposition: "pin" | "not-required"; reason: string | null }
  >;
  readonly fileSha256: Sha256;
}

/** Strict `--dispositions` loader: JSON object keyed by `kind:oid`. */
export function loadDispositions(path: string): Effect.Effect<Dispositions, CustodyError> {
  return Effect.gen(function* () {
    const bytes = yield* Effect.tryPromise({
      try: () => readFile(path),
      catch: (error) =>
        new CustodyError(
          "invalid-input",
          `dispositions file: ${error instanceof Error ? error.message : String(error)}`,
        ),
    });
    const parsed: unknown = yield* Effect.try({
      try: () => JSON.parse(strictText(bytes)),
      catch: () => new CustodyError("invalid-input", "dispositions file is not UTF-8 JSON"),
    });
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed))
      invalid("dispositions must be a JSON object keyed by candidate identity");
    const decisions = new Map<
      string,
      { disposition: "pin" | "not-required"; reason: string | null }
    >();
    for (const [key, value] of Object.entries(parsed as Record<string, unknown>)) {
      if (!/^(stash-older|reflog|dangling):([0-9a-f]{40}|[0-9a-f]{64})$/.test(key))
        invalid(`dispositions key is not a candidate identity: ${key}`);
      if (value === null || typeof value !== "object" || Array.isArray(value))
        invalid(`dispositions entry must be an object: ${key}`);
      const entry = value as Record<string, unknown>;
      const keys = Object.keys(entry).sort();
      const disposition = entry.disposition;
      const reason = entry.reason;
      if (
        disposition === "pin" &&
        (keys.length === 1 || (keys.length === 2 && typeof reason === "string"))
      ) {
        decisions.set(key, {
          disposition: "pin",
          reason: typeof reason === "string" ? reason : null,
        });
        continue;
      }
      if (
        disposition === "not-required" &&
        keys.length === 2 &&
        typeof reason === "string" &&
        reason.trim() !== ""
      ) {
        decisions.set(key, { disposition: "not-required", reason });
        continue;
      }
      invalid(`dispositions entry must be pin or not-required (with reason): ${key}`);
    }
    return { decisions, fileSha256: sha256(bytes) };
  });
}

function strictText(bytes: Uint8Array): string {
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

function pathContains(outer: string, inner: string): boolean {
  return outer !== inner && (inner.startsWith(`${outer}/`) || outer.startsWith(`${inner}/`));
}

function validateInput(input: AdoptInput): void {
  refComponent(input.label);
  refComponent(input.generation);
  refName(`refs/heads/${input.branch.replace(/^refs\/heads\//, "")}`);
  if (input.repo.trim() === "") invalid("--repo must be a nonempty URL");
}

function resolvePaths(input: AdoptInput): { legacy: string; dest: string } {
  const legacy = resolve(input.legacy);
  const dest = resolve(input.dest);
  if (legacy === dest) invalid(`legacy and destination are the same path: ${legacy}`);
  if (pathContains(legacy, dest))
    invalid(`destination nests inside the legacy checkout: ${dest} under ${legacy}`);
  if (pathContains(dest, legacy))
    invalid(`legacy checkout nests inside the destination: ${legacy} under ${dest}`);
  return { legacy, dest };
}

/** Canonicalize even an absent path through its nearest existing ancestor. */
async function canonicalPath(path: string): Promise<{ path: string; exists: boolean }> {
  const tail: string[] = [];
  let cursor = path;
  while (true) {
    try {
      await lstat(cursor);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      const parent = dirname(cursor);
      if (parent === cursor) throw error;
      tail.push(basename(cursor));
      cursor = parent;
      continue;
    }
    // An existing but dangling symlink is not a missing destination.
    const ancestor = await realpath(cursor);
    return { path: resolve(ancestor, ...tail.reverse()), exists: tail.length === 0 };
  }
}

/**
 * Produce the adoption plan. The Effect fails only for invalid operator
 * input; inspection and admission problems are blockers in the plan.
 */
export const planAdoption: (input: AdoptInput) => Effect.Effect<PlanV1, CustodyError> = Effect.fn(
  "custody.planAdoption",
)((input: AdoptInput): Effect.Effect<PlanV1, CustodyError> =>
  Effect.gen(function* () {
    validateInput(input);
    const paths = resolvePaths(input);
    // No repo query or private staging may run against aliased or nested
    // roots. Lexical checks alone miss symlink aliases (including parents of
    // a not-yet-existing destination).
    const canonical = yield* Effect.tryPromise({
      try: () => Promise.all([canonicalPath(paths.legacy), canonicalPath(paths.dest)]),
      catch: (error) =>
        new CustodyError("invalid-input", `resolve repository roots: ${String(error)}`),
    });
    if (
      canonical[0].path === canonical[1].path ||
      pathContains(canonical[0].path, canonical[1].path)
    )
      invalid("source and destination resolve to identical or nested paths");

    const dispositions =
      input.dispositions === null ? null : yield* loadDispositions(input.dispositions);
    const excludeBytes =
      input.excludeFrom === null
        ? null
        : yield* Effect.tryPromise({
            try: () => readFile(input.excludeFrom as string),
            catch: (error) =>
              new CustodyError(
                "invalid-input",
                `exclude file: ${error instanceof Error ? error.message : String(error)}`,
              ),
          });
    const pathReviewBytes =
      input.pathReview === null
        ? null
        : yield* Effect.tryPromise({
            try: () => readFile(input.pathReview as string),
            catch: (error) =>
              new CustodyError(
                "invalid-input",
                `path review file: ${error instanceof Error ? error.message : String(error)}`,
              ),
          });

    const probe = yield* probeSource(paths.legacy, {
      excludeFrom: input.excludeFrom,
      dispositions: dispositions?.decisions ?? null,
    });

    // Unknown disposition identities are rejected, not ignored.
    if (dispositions !== null && probe.observed.candidates !== null) {
      const known = new Set(probe.observed.candidates.map(({ kind, oid }) => `${kind}:${oid}`));
      const unknown = [...dispositions.decisions.keys()].filter((key) => !known.has(key));
      if (unknown.length > 0)
        invalid(`dispositions reference unknown candidates: ${unknown.join(", ")}`);
    }

    const blockers: Issue[] = [...probe.blockers];
    const warnings: Issue[] = [...probe.warnings];
    const retirement: Issue[] = [...probe.retirementUnresolved];

    // --- jj classification ---
    const jj = yield* sourceJjView(
      probe.source,
      probe.selectedTipOids,
      probe.objectFormat ?? "sha1",
    );
    probe.observed.jjCoverage = {
      classification: jj.classification,
      headOids: jj.headOids,
      operationId: jj.operationId,
    };
    if (jj.classification === "blocked" && jj.failure !== null) blockers.push(jj.failure);
    if (jj.uncoveredOids.length > 0)
      blockers.push({
        code: "jj-heads-uncovered",
        subject: null,
        reason: `jj visible heads not covered by selected Git tips: ${jj.uncoveredOids.join(", ").slice(0, 400)}`,
      });
    if (jj.classification !== "none") {
      retirement.push({
        code: "jj-operation-history",
        subject: join(probe.source, ".jj"),
        reason: "jj operation log and workspace state are not preserved by Git custody",
      });
      if (jj.workingCopyEmpty === false || jj.workingCopyDescribed === true)
        warnings.push({
          code: "jj-working-copy-snapshot",
          subject: null,
          reason:
            "jj working-copy commit has content or a description; it counts as jj-only work for coverage",
        });
    }

    // --- snapshot preview and privacy gates ---
    // The clean-review digest the operator must bind; also published as
    // PlanV1.headManifestSha256 so the chicken-and-egg (approval needs the
    // manifest, manifest needs inspection) resolves without apply.
    const headManifestSha256 =
      probe.observed.head === null
        ? null
        : (sha256(encoder.encode(`${canonicalJson(probe.observed.head.treePaths)}\n`)) as Sha256);
    let pathReview = null as ReturnType<typeof parsePathReview> | null;
    if (probe.objectFormat !== null && pathReviewBytes !== null)
      pathReview = yield* Effect.try({
        try: () => parsePathReview(pathReviewBytes, probe.objectFormat as "sha1" | "sha256"),
        catch: (error) =>
          error instanceof CustodyError
            ? error
            : new CustodyError("invalid-input", "path review failed to parse"),
      });
    const sensitiveTracked = probe.observed.trackedSensitivePaths ?? [];
    if (sensitiveTracked.length > 0) {
      retirement.push({
        code: "publication-review",
        subject: null,
        reason: `${sensitiveTracked.length} tracked sensitive path(s) require review before any publication; custody does not authorize it`,
      });
    }
    const sensitiveSubjects = sensitiveTracked
      .map(({ subject }) => subject)
      .filter((subject): subject is string => subject !== null);

    // Approval-free preview: the exact synthetic tree the apply door would
    // mint, from disposable private scratch (stage fixtures prove the source
    // and the later approved snapshot both match it). The preview is a
    // proposal: it can never serve as an approved apply Snapshot.
    let proposal: SnapshotProposal | null = null;
    const changes = probe.observed.worktreeChanges ?? [];
    const stagedExists = changes.some(({ indexStatus }) => indexStatus !== "unchanged");
    const unstagedExists = changes.some(({ worktreeStatus }) => worktreeStatus !== "unchanged");
    const previewable =
      probe.dirty &&
      probe.objectFormat !== null &&
      probe.observed.head !== null &&
      probe.observed.worktreeChanges !== null &&
      probe.observed.untrackedPaths !== null &&
      probe.observed.excludedUntracked !== null;
    if (previewable) {
      const scratchRoot = yield* Effect.tryPromise({
        try: () => mkdtemp(join(tmpdir(), "custody-preview-")),
        catch: (error) =>
          new CustodyError(
            "inspection-failed",
            `preview scratch: ${error instanceof Error ? error.message : String(error)}`,
          ),
      });
      const previewed = yield* Effect.result(
        Effect.tryPromise({
          try: (signal) =>
            previewSnapshot(
              {
                sourceRoot: probe.source,
                scratchRoot,
                objectFormat: probe.objectFormat as "sha1" | "sha256",
                headOid: (probe.observed.head as { oid: Oid }).oid,
                restageTracked: [...new Set(changes.map(({ path }) => path))],
                addUntracked: (probe.observed.untrackedPaths as readonly RepoPath[]).filter(
                  (path) =>
                    !(probe.observed.excludedUntracked as readonly RepoPath[]).includes(path),
                ),
                stagedVsUnstaged:
                  stagedExists && unstagedExists ? "reported-not-preserved" : "none",
                excludeFileSha256: excludeBytes === null ? null : sha256(excludeBytes),
                excludedUntracked: probe.observed.excludedUntracked as readonly RepoPath[],
                ignoredPaths: probe.observed.ignoredPaths ?? [],
                trackedSensitivePaths: sensitiveSubjects as RepoPath[],
                pathReview: null,
                expected: probe.includedManifest,
              },
              { signal },
            ),
          catch: (error) =>
            new CustodyError(
              "inspection-failed",
              `snapshot preview failed: ${error instanceof Error ? error.message : String(error)}`,
            ),
        }),
      );
      if (Result.isFailure(previewed))
        blockers.push({
          code: "snapshot-preview-failed",
          subject: probe.source,
          reason: previewed.failure.message,
        });
      else proposal = previewed.success;
      // previewSnapshot removes its own stage directory in a finally;
      // the outer scratch root is best-effort cleanup.
      yield* Effect.tryPromise({
        try: () => rm(scratchRoot, { recursive: true, force: true }),
        catch: (error) =>
          new CustodyError("inspection-failed", `preview scratch cleanup: ${String(error)}`),
      }).pipe(Effect.catch(() => Effect.succeed(undefined)));
    } else if (probe.dirty) {
      blockers.push({
        code: "snapshot-preview-unknowable",
        subject: probe.source,
        reason:
          "worktree is dirty but inventory categories are missing; the proposal cannot be computed",
      });
    }

    // A staged version can differ from both HEAD and the worktree while the
    // preview tree equals HEAD. No synthetic commit or pin then retains that
    // index-only blob. A review cannot turn absent custody into preservation.
    if (probe.dirty && proposal === null && stagedExists)
      blockers.push({
        code: "source-index-only-state",
        subject: probe.source,
        reason:
          "staged index state has no synthetic snapshot; separate index custody is required before adoption",
      });

    let cleanHeadPathReview: ReturnType<typeof parsePathReview> | null = null;
    let approvedSnapshot: Snapshot | null = null;
    let workingCopy: { commitOid: Oid; parentOid: Oid; treeOid: Oid } | null = null;
    if (probe.dirty && proposal !== null) {
      // Mirror the receipt rules — the same rules stage.prepareSnapshot's
      // bindPathReview enforces at apply — so a plan that cannot produce a
      // valid receipt reports it now, not at apply time.
      const needsReview =
        proposal.trackedSensitivePaths.length > 0 ||
        proposal.reviewRequirements.stagedVsUnstagedApprovalRequired;
      let reviewProblems = false;
      if (pathReview === null) {
        if (needsReview) {
          reviewProblems = true;
          blockers.push({
            code: "path-review-required",
            subject: null,
            reason: `snapshot with sensitive paths or a staged/unstaged split requires --path-review bound to manifest ${proposal.manifestSha256}: ${[
              ...proposal.reviewRequirements.sensitivePaths,
            ]
              .slice(0, 16)
              .join(", ")}`,
          });
        }
      } else {
        const entries = new Set(
          proposal.paths.map(({ path, mode, blobOid }) => `${path}\0${mode}\0${blobOid}`),
        );
        const included = new Set<string>();
        const problems: string[] = [];
        if (pathReview.manifestSha256 !== proposal.manifestSha256)
          problems.push("review manifest digest differs from the snapshot proposal");
        for (const entry of pathReview.included) {
          const key = `${entry.path}\0${entry.mode}\0${entry.blobOid}`;
          if (!entries.has(key)) problems.push(`review includes stale file ${entry.path}`);
          else if (included.has(entry.path)) problems.push(`review repeats file ${entry.path}`);
          else included.add(entry.path);
        }
        for (const path of proposal.reviewRequirements.sensitivePaths)
          if (!included.has(path)) problems.push(`sensitive path lacks an exact review: ${path}`);
        if (
          proposal.reviewRequirements.stagedVsUnstagedApprovalRequired &&
          pathReview.stagedVsUnstaged === null
        )
          problems.push("lost index/worktree split is not approved");
        if (problems.length > 0) {
          reviewProblems = true;
          blockers.push({
            code: "path-review-invalid",
            subject: null,
            reason: problems.slice(0, 8).join("; "),
          });
        }
      }
      if (!reviewProblems) {
        // Approved: the proposal minus its proposal-only fields becomes the
        // Snapshot the apply door mints from the identical private stage
        // (deterministic identity — prepareSnapshot reproduces the same
        // commit OID from the same manifest). A plain dirty worktree with no
        // sensitive paths and no staged/unstaged split needs no review.
        approvedSnapshot = {
          format: proposal.format,
          parentOid: proposal.parentOid,
          treeOid: proposal.treeOid,
          commitOid: proposal.commitOid,
          paths: proposal.paths,
          stagedVsUnstaged: proposal.stagedVsUnstaged,
          excludeFileSha256: proposal.excludeFileSha256,
          excludedUntracked: proposal.excludedUntracked,
          ignoredPaths: proposal.ignoredPaths,
          trackedSensitivePaths: proposal.trackedSensitivePaths,
          pathReview,
        };
        workingCopy = {
          commitOid: proposal.commitOid,
          parentOid: proposal.parentOid,
          treeOid: proposal.treeOid,
        };
      }
    } else if (pathReview !== null && probe.observed.head !== null && !probe.dirty) {
      // Clean HEAD: the review binds the exact HEAD tree manifest. Mirror
      // the receipt rules from codec.validateReceipt so a plan that cannot
      // produce a valid receipt reports it now, not at apply time.
      const manifest = probe.observed.head.treePaths;
      const expected = headManifestSha256;
      const entries = new Set(
        manifest.map(({ path, mode, blobOid }) => `${path}\0${mode}\0${blobOid}`),
      );
      const included = new Set<string>();
      const problems: string[] = [];
      if (pathReview.manifestSha256 !== expected)
        problems.push("review manifest digest differs from the clean HEAD tree");
      if (pathReview.stagedVsUnstaged !== null)
        problems.push("clean HEAD review cannot approve a lost index/worktree split");
      for (const entry of pathReview.included) {
        const key = `${entry.path}\0${entry.mode}\0${entry.blobOid}`;
        if (!entries.has(key)) problems.push(`review includes stale file ${entry.path}`);
        else if (included.has(entry.path)) problems.push(`review repeats file ${entry.path}`);
        else included.add(entry.path);
      }
      for (const { subject } of sensitiveTracked)
        if (subject === null || !included.has(subject))
          problems.push(`sensitive tracked path lacks an exact review: ${subject}`);
      if (problems.length > 0)
        blockers.push({
          code: "clean-head-path-review-invalid",
          subject: null,
          reason: problems.slice(0, 8).join("; "),
        });
      else cleanHeadPathReview = pathReview;
    }
    if (!probe.dirty && sensitiveTracked.length > 0 && cleanHeadPathReview === null)
      blockers.push({
        code: "clean-head-path-review-required",
        subject: null,
        reason: `clean HEAD with tracked sensitive paths requires a --path-review binding the HEAD tree manifest: ${sensitiveTracked
          .map(({ subject }) => subject)
          .filter((subject): subject is string => subject !== null)
          .slice(0, 16)
          .join(", ")}`,
      });

    // --- destination ---
    const dest = yield* probeDestination(paths.dest, input.repo, probe.objectFormat);
    blockers.push(...dest.blockers);
    warnings.push(...dest.warnings);
    if (dest.exists) {
      const destJj = yield* destinationJjView(dest.realpath as string);
      if (destJj.failure !== null) blockers.push(destJj.failure);
    }

    // --- baselines and counts ---
    const remotes = probe.observed.remotes ?? [];
    const urlByName = new Map(remotes.map(({ name, url }) => [name, url]));
    const remoteTracking: RemoteBaseline[] = [];
    for (const ref of probe.observed.refs ?? []) {
      const match = ref.name.match(/^refs\/remotes\/([^/]+)\/(.+)$/);
      if (match === null || match[2] !== input.branch) continue;
      const url = urlByName.get(match[1]);
      if (url === undefined) {
        warnings.push({
          code: "remote-url-unknown",
          subject: match[1],
          reason: "remote-tracking ref exists without a configured remote url",
        });
        continue;
      }
      remoteTracking.push({
        remote: match[1],
        url,
        ref: ref.name,
        oid: ref.oid,
        freshness: "local-only",
      });
    }
    remoteTracking.sort((a, b) => (a.remote < b.remote ? -1 : a.remote > b.remote ? 1 : 0));

    const head = probe.observed.head;
    let headNotInRecordedBaseline: number | null = null;
    if (head !== null && remoteTracking.length > 0) {
      headNotInRecordedBaseline = yield* countNotIn(
        probe.source,
        [head.oid],
        [remoteTracking[0].oid],
      );
    } else if (head !== null) {
      warnings.push({
        code: "baseline-unknown",
        subject: null,
        reason: "no locally recorded remote-tracking baseline; unknown, not unpushed",
      });
    }

    let selectedTipsNotInDestination: number | null = null;
    const branchTips = (probe.observed.refs ?? [])
      .filter(({ name }) => name.startsWith("refs/heads/"))
      .map(({ oid }) => oid);
    if (dest.preRefs !== null && head !== null) {
      // refs/jj/* keep refs are jj-internal destination state, not archive
      // content tips: requiring them in the source ODB would make every
      // jj-colocated destination's delta count unknowable.
      const destTips = dest.preRefs
        .filter(({ name }) => !name.startsWith("refs/jj/"))
        .map(({ peeledOid, oid }) => peeledOid ?? oid);
      selectedTipsNotInDestination = yield* countNotIn(
        probe.source,
        [head.oid, ...branchTips],
        destTips,
      );
      if (selectedTipsNotInDestination === null)
        warnings.push({
          code: "destination-count-unknown",
          subject: null,
          reason:
            "destination tips are not all present in the source object store; delta count unknown",
        });
    }

    let baselines: DestinationBaseline | null = null;
    if (
      dest.exists &&
      dest.preRefs !== null &&
      dest.statusSha256 !== null &&
      dest.indexSha256 !== null
    ) {
      baselines = {
        sourceRemoteTracking: remoteTracking,
        destinationPreRefs: dest.preRefs,
        destinationPreRefsSha256: dest.preRefsSha256 as Sha256,
        destinationWorktreeFingerprintSha256: dest.statusSha256 as Sha256,
        destinationIndexSha256: dest.indexSha256 as Sha256,
        selectedBranch: input.branch,
        declaredRepo: input.repo,
        headNotInRecordedBaseline,
        selectedTipsNotInDestination,
      };
    }

    // --- fingerprints (only when every input was actually observed) ---
    if (
      probe.fingerprintFiles !== null &&
      probe.includedManifest !== null &&
      probe.raw.refs !== null &&
      probe.raw.reflogs !== null &&
      probe.fingerprintFiles.odbListing !== null
    ) {
      const { indexBytes, configBytes, odbListing, jjStore } = probe.fingerprintFiles;
      const indexSha256 = sha256(indexBytes);
      const canonicalInputs = {
        head: head === null ? null : { symbolicRef: head.symbolicRef, oid: head.oid },
        refs: (probe.observed.refs ?? []).map(({ name, oid, objectType, peeledOid }) => ({
          name,
          oid,
          objectType,
          peeledOid,
        })),
        reflogSelection: (probe.observed.candidates ?? []).map(({ kind, oid, disposition }) => ({
          kind,
          oid,
          disposition,
        })),
        indexSha256,
        includedManifest: probe.includedManifest,
        excludeFileSha256: excludeBytes === null ? null : sha256(excludeBytes),
        dispositionsFileSha256: dispositions === null ? null : dispositions.fileSha256,
        declaredRepo: input.repo,
        selectedBranch: input.branch,
      };
      probe.observed.fingerprints = {
        indexSha256,
        gitConfigSha256: sha256(configBytes),
        refsSha256: sha256(probe.raw.refs),
        reflogsSha256: sha256(probe.raw.reflogs),
        odbListingSha256: sha256(encoder.encode(odbListing)),
        includedWorktreeSha256: sha256(
          encoder.encode(`${canonicalJson(probe.includedManifest)}\n`),
        ),
        jjStoreSha256: jjStore === null ? null : (sha256(encoder.encode(jjStore)) as Sha256),
        canonicalInputsSha256: sha256(encoder.encode(`${canonicalJson(canonicalInputs)}\n`)),
      };
      probe.observed.excludeFileSha256 = excludeBytes === null ? null : sha256(excludeBytes);
      probe.observed.dispositionsFileSha256 =
        dispositions === null ? null : dispositions.fileSha256;
    }

    // --- pins (ready plans only) ---
    const { pins, failures } = buildPins(
      probe.observed,
      input.label,
      input.generation,
      workingCopy,
    );
    if (failures.length > 0) blockers.push(...failures);

    // --- assemble the plan ---
    const partialIdentity = {
      label: input.label,
      generation: input.generation,
      legacyRealpathAtCapture: probe.source,
      sourceGitCommonDir: probe.gitDir,
      destinationRealpath: dest.realpath,
      createdAt: new Date().toISOString(),
    };
    const uniqueBlockers = [
      ...new Map(blockers.map((issue) => [`${issue.code}\0${issue.subject}`, issue])).values(),
    ];

    if (uniqueBlockers.length > 0) {
      return {
        schema: "compfuzor.archive-adoption-plan/v1",
        state: "blocked",
        headManifestSha256,
        identity: partialIdentity,
        source: probe.observed,
        proposedSnapshot: proposal,
        cleanHeadPathReview,
        baselines,
        pins: null,
        blockers: uniqueBlockers,
        warnings,
        retirementUnresolved: retirement,
      } satisfies PlanV1;
    }

    const source = assembleSource(probe.observed);
    if (source === null || baselines === null)
      invalid("internal: blocker-free plan still lacks inventory categories");
    if (probe.gitDir === null || dest.realpath === null)
      invalid("internal: blocker-free plan lacks resolved repository paths");
    return {
      schema: "compfuzor.archive-adoption-plan/v1",
      state: "ready",
      headManifestSha256,
      identity: {
        ...partialIdentity,
        sourceGitCommonDir: probe.gitDir,
        destinationRealpath: dest.realpath,
      },
      source,
      proposedSnapshot: approvedSnapshot,
      cleanHeadPathReview,
      baselines,
      pins,
      blockers: [],
      warnings,
      retirementUnresolved: retirement,
    } satisfies PlanV1;
  }),
);

/** Deduplicated `rev-list --count tips --not negatives`; null when unknowable. */
function countNotIn(
  source: string,
  tips: readonly string[],
  negatives: readonly string[],
): Effect.Effect<number | null, CustodyError> {
  return Effect.gen(function* () {
    if (tips.length === 0 || negatives.length === 0) return null;
    for (const negative of negatives) {
      const exists = yield* gitRead(["cat-file", "-e", `${negative}^{commit}`], {
        cwd: source,
      }).pipe(
        Effect.map((result) => result.exitCode === 0),
        Effect.catch(() => Effect.succeed(false)),
      );
      if (!exists) return null;
    }
    const result = yield* gitRead(
      ["rev-list", "--count", ...tips, ...negatives.map((oid) => `^${oid}`)],
      { cwd: source },
    ).pipe(Effect.mapError((error) => new CustodyError("inspection-failed", error.message)));
    if (result.exitCode !== 0) return null;
    const counted = yield* Effect.result(
      Effect.try({
        try: () => parseCount(result.stdout),
        catch: (error) =>
          error instanceof CustodyError
            ? error
            : new CustodyError("inspection-failed", String(error)),
      }),
    );
    return Result.isSuccess(counted) ? counted.success : null;
  });
}

interface PinMaterial {
  readonly head: { readonly oid: Oid } | null;
  readonly refs: readonly GitTip[] | null;
  readonly candidates:
    | readonly {
        readonly kind: "stash-older" | "reflog" | "dangling";
        readonly oid: Oid;
        readonly objectType: "commit" | "tag" | "tree" | "blob";
        readonly disposition: string;
      }[]
    | null;
}

function buildPins(
  observed: PinMaterial,
  label: string,
  generation: string,
  workingCopy: { commitOid: Oid; parentOid: Oid; treeOid: Oid } | null,
): { readonly pins: readonly PinIntent[]; readonly failures: readonly Issue[] } {
  const pins: PinIntent[] = [];
  const failures: Issue[] = [];
  const pin = (intent: Omit<PinIntent, "destinationRef">): void => {
    try {
      pins.push({ ...intent, destinationRef: pinRef(intent, label, generation) });
    } catch (error) {
      failures.push({
        code: "pin-mapping-invalid",
        subject: intent.sourceName,
        reason: error instanceof Error ? error.message : String(error),
      });
    }
  };
  if (observed.head !== null)
    pin({
      sourceKind: "head",
      sourceName: "HEAD",
      sourceOid: observed.head.oid,
      objectType: "commit",
      destinationOid: observed.head.oid,
    });
  for (const ref of observed.refs ?? []) {
    const kind: PinIntent["sourceKind"] = ref.name.startsWith("refs/heads/")
      ? "branch"
      : ref.name.startsWith("refs/tags/")
        ? "tag"
        : ref.name === "refs/stash"
          ? "stash"
          : "other";
    pin({
      sourceKind: kind,
      sourceName: ref.name,
      sourceOid: ref.oid,
      objectType: ref.objectType,
      destinationOid: ref.oid,
    });
  }
  for (const candidate of observed.candidates ?? []) {
    if (candidate.disposition !== "pin") continue;
    pin({
      sourceKind: "reflog",
      sourceName: candidateIdentity(candidate.kind, candidate.oid),
      sourceOid: candidate.oid,
      objectType: candidate.objectType,
      destinationOid: candidate.oid,
    });
  }
  // The synthetic working-copy commit is only pinned when its snapshot is
  // approved; the content-addressed lane makes an unchanged retry identical.
  if (workingCopy !== null) {
    const intent: Omit<PinIntent, "destinationRef"> = {
      sourceKind: "working-copy",
      sourceName: "working-copy",
      sourceOid: workingCopy.commitOid,
      objectType: "commit",
      destinationOid: workingCopy.commitOid,
    };
    try {
      pins.push({ ...intent, destinationRef: pinRef(intent, label, generation, workingCopy) });
    } catch (error) {
      failures.push({
        code: "pin-mapping-invalid",
        subject: "working-copy",
        reason: error instanceof Error ? error.message : String(error),
      });
    }
  }
  return { pins, failures };
}

/** Narrow an observed inventory to the complete shape, or null. */
function assembleSource(observed: {
  [K in keyof SourceInventory]: SourceInventory[K] | null;
}): SourceInventory | null {
  if (
    observed.objectFormat === null ||
    observed.sourceGitCommonDir === null ||
    observed.head === null ||
    observed.refs === null ||
    observed.candidates === null ||
    observed.remotes === null ||
    observed.indexEntries === null ||
    observed.worktreeChanges === null ||
    observed.untrackedPaths === null ||
    observed.ignoredPaths === null ||
    observed.excludedUntracked === null ||
    observed.trackedSensitivePaths === null ||
    observed.leftBehind === null ||
    observed.jjCoverage === null ||
    observed.fingerprints === null
  )
    return null;
  return {
    objectFormat: observed.objectFormat,
    sourceGitCommonDir: observed.sourceGitCommonDir,
    head: observed.head,
    refs: observed.refs,
    candidates: observed.candidates,
    remotes: observed.remotes,
    indexEntries: observed.indexEntries,
    worktreeChanges: observed.worktreeChanges,
    untrackedPaths: observed.untrackedPaths,
    ignoredPaths: observed.ignoredPaths,
    excludedUntracked: observed.excludedUntracked,
    trackedSensitivePaths: observed.trackedSensitivePaths,
    leftBehind: observed.leftBehind,
    jjCoverage: observed.jjCoverage,
    fingerprints: observed.fingerprints,
    excludeFileSha256: observed.excludeFileSha256,
    dispositionsFileSha256: observed.dispositionsFileSha256,
  };
}
