/** Shared, source-independent wire contracts. No Effect dependency in the data layer. */
export type GitObjectFormat = "sha1" | "sha256";
export type GitObjectType = "commit" | "tag" | "tree" | "blob";
export type Oid = string & { readonly __oid: unique symbol };
export type RefName = string & { readonly __ref: unique symbol };
export type RepoPath = string & { readonly __path: unique symbol };
export type Sha256 = string & { readonly __sha256: unique symbol };

export interface Issue {
  readonly code: string;
  readonly subject: string | null;
  readonly reason: string;
}
export interface PathEntry {
  readonly path: RepoPath;
  readonly mode: "100644" | "100755" | "120000" | "160000";
  readonly blobOid: Oid;
}
export interface GitTip {
  readonly name: RefName;
  readonly oid: Oid;
  readonly objectType: GitObjectType;
  readonly peeledOid: Oid | null;
}
export interface IndexEntry {
  readonly path: RepoPath;
  readonly stage: 0 | 1 | 2 | 3;
  readonly mode: PathEntry["mode"];
  readonly blobOid: Oid;
}
export interface WorktreeChange {
  readonly path: RepoPath;
  readonly originalPath: RepoPath | null;
  readonly indexStatus:
    | "unchanged"
    | "added"
    | "modified"
    | "deleted"
    | "renamed"
    | "copied"
    | "typechanged"
    | "unmerged";
  readonly worktreeStatus:
    | "unchanged"
    | "added"
    | "modified"
    | "deleted"
    | "renamed"
    | "copied"
    | "typechanged"
    | "unmerged";
}
export interface SourceFingerprints {
  readonly indexSha256: Sha256;
  readonly gitConfigSha256: Sha256;
  readonly refsSha256: Sha256;
  readonly reflogsSha256: Sha256;
  readonly odbListingSha256: Sha256;
  readonly includedWorktreeSha256: Sha256;
  readonly jjStoreSha256: Sha256 | null;
  readonly canonicalInputsSha256: Sha256;
}
export type CandidateKind = "stash-older" | "reflog" | "dangling";
export interface Candidate {
  readonly kind: CandidateKind;
  readonly oid: Oid;
  readonly objectType: GitObjectType;
  readonly provenance: readonly string[];
  readonly disposition: "pin" | "not-required" | "unclassified";
  readonly reason: string | null;
}
export interface Head {
  readonly symbolicRef: RefName | null;
  readonly oid: Oid;
  readonly treeOid: Oid;
  readonly treePaths: readonly PathEntry[];
}
export interface JjCoverage {
  readonly classification: "none" | "git-covered" | "blocked";
  readonly headOids: readonly Oid[];
  readonly operationId: string | null;
}
export interface SourceInventory {
  readonly objectFormat: GitObjectFormat;
  readonly sourceGitCommonDir: string;
  readonly head: Head;
  readonly refs: readonly GitTip[];
  readonly candidates: readonly Candidate[];
  readonly remotes: readonly { readonly name: string; readonly url: string }[];
  readonly indexEntries: readonly IndexEntry[];
  readonly worktreeChanges: readonly WorktreeChange[];
  readonly untrackedPaths: readonly RepoPath[];
  readonly ignoredPaths: readonly RepoPath[];
  readonly excludedUntracked: readonly RepoPath[];
  readonly trackedSensitivePaths: readonly Issue[];
  readonly leftBehind: readonly Issue[];
  readonly jjCoverage: JjCoverage;
  readonly fingerprints: SourceFingerprints;
  readonly excludeFileSha256: Sha256 | null;
  readonly dispositionsFileSha256: Sha256 | null;
}
export interface ReviewedPath {
  readonly path: RepoPath;
  readonly mode: PathEntry["mode"];
  readonly blobOid: Oid;
  readonly classification: "credential" | "runtime-state" | "other-sensitive";
  readonly decision: "local-custody-approved";
  readonly reason: string;
}
/** Separate from kind+OID candidate dispositions. Review never authorizes publication. */
export interface PathReview {
  readonly schema: "compfuzor.archive-path-review/v1";
  readonly manifestSha256: Sha256;
  readonly fileSha256: Sha256;
  readonly included: readonly ReviewedPath[];
  readonly stagedVsUnstaged: {
    readonly decision: "single-tree-approved";
    readonly reason: string;
  } | null;
}
export interface Snapshot {
  readonly format: "worktree-v1";
  readonly parentOid: Oid;
  readonly treeOid: Oid;
  readonly commitOid: Oid;
  readonly paths: readonly PathEntry[];
  readonly stagedVsUnstaged: "none" | "reported-not-preserved";
  readonly excludeFileSha256: Sha256 | null;
  readonly excludedUntracked: readonly RepoPath[];
  readonly ignoredPaths: readonly RepoPath[];
  readonly trackedSensitivePaths: readonly RepoPath[];
  readonly pathReview: PathReview | null;
}
export interface RemoteBaseline {
  readonly remote: string;
  readonly url: string;
  readonly ref: RefName;
  readonly oid: Oid;
  readonly freshness: "local-only";
}
export interface DestinationBaseline {
  readonly sourceRemoteTracking: readonly RemoteBaseline[];
  readonly destinationPreRefs: readonly GitTip[];
  readonly destinationPreRefsSha256: Sha256;
  readonly destinationWorktreeFingerprintSha256: Sha256;
  readonly destinationIndexSha256: Sha256;
  readonly selectedBranch: string;
  readonly declaredRepo: string;
  readonly headNotInRecordedBaseline: number | null;
  readonly selectedTipsNotInDestination: number | null;
}
export type PinKind = "branch" | "head" | "tag" | "stash" | "other" | "reflog" | "working-copy";
export interface PinIntent {
  readonly sourceKind: PinKind;
  readonly sourceName: string;
  readonly sourceOid: Oid;
  readonly objectType: GitObjectType;
  readonly destinationRef: RefName;
  readonly destinationOid: Oid;
}
export interface BundleHead {
  readonly ref: RefName;
  readonly oid: Oid;
}
export interface SealedBundle {
  readonly pathRelativeToDestinationParent: string;
  readonly sha256: Sha256;
  readonly verifiedHeads: readonly BundleHead[];
  readonly freshRestoreVerified: true;
}
export interface ReceiptV1 {
  readonly schema: "compfuzor.archive-adoption/v1";
  readonly receiptRef: RefName;
  readonly identity: {
    readonly label: string;
    readonly generation: string;
    readonly legacyRealpathAtCapture: string;
    readonly sourceGitCommonDir: string;
    readonly destinationRealpath: string;
    readonly createdAt: string;
  };
  readonly source: SourceInventory;
  readonly snapshot: Snapshot | null;
  readonly baselines: DestinationBaseline;
  readonly pins: readonly PinIntent[];
  readonly bundle: SealedBundle;
  readonly checks: {
    readonly sourceFingerprintRechecked: true;
    readonly sourceOdbUnchanged: true;
    readonly destinationWorktreeUnchanged: true;
    readonly bundleClosureVerified: true;
  };
  readonly unresolved: readonly Issue[];
}

export interface PlanV1 {
  readonly schema: "compfuzor.archive-adoption-plan/v1";
  readonly identity: ReceiptV1["identity"];
  readonly source: SourceInventory;
  readonly proposedSnapshot: Snapshot | null;
  readonly baselines: DestinationBaseline;
  readonly pins: readonly PinIntent[];
  readonly blockers: readonly Issue[];
  readonly warnings: readonly Issue[];
  readonly retirementUnresolved: readonly Issue[];
}
export interface Verification {
  readonly receiptRef: RefName;
  readonly receiptCommitOid: Oid;
  readonly custodyVerified: boolean;
  readonly custodyFailures: readonly Issue[];
  readonly sourceDrift: "absent" | "unchanged" | "changed" | "unknown";
  readonly destinationDrift: "unchanged" | "changed" | "unknown";
  readonly retirementUnresolved: readonly Issue[];
}

export interface AdoptInput {
  readonly legacy: string;
  readonly dest: string;
  readonly repo: string;
  readonly branch: string;
  readonly label: string;
  readonly generation: string;
  readonly excludeFrom: string | null;
  readonly dispositions: string | null;
  readonly pathReview: string | null;
}
