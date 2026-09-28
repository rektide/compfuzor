/**
 * Public library surface of the archive jj toolkit.
 *
 * Grouped, explicit exports only — no wildcard barrel: every name's origin
 * module stays greppable, and any future collision surfaces at the import
 * site instead of silently shadowing. Presentation (console output) and CLI
 * composition live above this layer (see repo-jj-archive.ts; a runtime/
 * layer for the Effect CLI is planned). Library functions return structured
 * results/notices and never write to stdout/stderr.
 */

// repository/jj.ts — the only shell boundary for jj; templates and ref queries.
export {
  JjError,
  jj,
  lines,
  exists,
  isDirectory,
  REF_TEMPLATE,
  COMMIT_TEMPLATE,
  HEAD_TEMPLATE,
  refKey,
  refs,
  revision,
  ancestor,
} from "./repository/jj.ts";
export type { BookmarkRef, Revision, JjOptions } from "./repository/jj.ts";

// repository/health.ts — ghost-head preflight and conflicted-bookmark report.
export { preflight } from "./repository/health.ts";
export type { PreflightOptions } from "./repository/health.ts";

// repository/snapshot.ts — snapshot worktree and import colocated Git refs.
export { snapshot } from "./repository/snapshot.ts";
export type { SnapshotResult } from "./repository/snapshot.ts";

// repository/fetch.ts — safe single-remote fetch with frozen local bookmarks.
export { fetchRemote } from "./repository/fetch.ts";
export type { FetchOptions, FetchResult } from "./repository/fetch.ts";

// repository/remotes.ts — declared-vs-actual remote URL policy.
export { declaredRemotes, remoteDiff, mismatchError, reconcile } from "./repository/remotes.ts";
export type { RemoteDifference } from "./repository/remotes.ts";

// repository/refresh.ts — the composed archive convergence operation.
export { refreshArchive } from "./repository/refresh.ts";
export type { RefreshOptions, RefreshResult } from "./repository/refresh.ts";

// repository/self.ts — standard compfuzor archive checkout detection.
export { locateCompfuzor } from "./repository/self.ts";

// recovery/harvest.ts — stable recovery bookmarks for mutable revisions.
export { harvest, recoveryCovered, safeLabel, stamp } from "./recovery/harvest.ts";
export type { Notice } from "./recovery/harvest.ts";

// recovery/heal.ts — explicit last-resort jj re-adoption with retained backup.
export { heal } from "./recovery/heal.ts";

// custody — read-only admission, explicit immutable transfer, independent receipt proof.
export { planAdoption, loadDispositions } from "./custody/inventory.ts";
export type { Dispositions } from "./custody/inventory.ts";
export { applyAdoption } from "./custody/apply.ts";
export type { ApplyResult, ApplyTestHooks } from "./custody/apply.ts";
export { verifyAdoption, readReceipt } from "./custody/verify.ts";
export type { VerifyInput, ObservedReceipt } from "./custody/verify.ts";
export { CustodyError } from "./custody/errors.ts";
export type { CustodyFailure } from "./custody/errors.ts";
export type {
  AdoptInput,
  PlanV1,
  ReceiptV1,
  Verification,
  Issue,
  PathReview,
} from "./custody/model.ts";
