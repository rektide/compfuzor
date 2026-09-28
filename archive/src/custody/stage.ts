/**
 * Private Git staging and the complete-bundle proof for archive adoption.
 *
 * This module owns the stage/bundle slice of the adoption brief: turning a
 * reviewed legacy checkout state into (a) an exact `worktree-v1` snapshot
 * minted inside a private bare scratch repository, and (b) a proven,
 * self-contained `git bundle` of the selected typed pins. It does not plan
 * admissions (inventory), seal vault bundles, mint receipts, or write
 * destination refs: those are separate owners. Every Git call goes through
 * the shared Effect adapter in `repository/git.ts`; there is no private
 * process runner here.
 *
 * Two doors share one staging core: `previewSnapshot` is the approval-free
 * proposal door (plain data, disposable scratch — it exists so an operator
 * can author a path review against the exact manifest digest without which
 * `prepareSnapshot` would refuse), and `prepareSnapshot` is the apply door
 * (enforces the manifest-bound review; `expected: null` is never an approval
 * bypass). Neither door accepts a force-style flag.
 *
 * Isolation model: the scratch repository is created outside the source
 * checkout; its object database and index are brand new, and source objects
 * are readable only through an `objects/info/alternates` pointer at the
 * source's object store. Every new blob/tree/commit lands in scratch. This is
 * the fix for the historical hazard that redirecting `GIT_INDEX_FILE` alone
 * still writes the untracked file's blob into the source ODB: routing
 * (`GIT_DIR`/`GIT_WORK_TREE`/`GIT_INDEX_FILE`/`GIT_OBJECT_DIRECTORY`) is
 * explicit on every staging command, and the adapter sanitizes inherited
 * `GIT_*` variables so a polluted parent cannot reroute a write. The
 * alternates pointer is removed before any bundle is created, so the bundle —
 * and its fresh-repository restore proof — can only carry objects that were
 * materialized into scratch itself.
 */
import { mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { isAbsolute, join, relative } from "node:path";
import { Effect } from "effect";
import { prefixConflict } from "../recovery/transaction.ts";
import { GitError, gitRead, utf8Fatal } from "../repository/git.ts";
import { canonicalJson, oid, refName, repoPath, sha256 } from "./codec.ts";
import { CustodyError, invalid } from "./errors.ts";
import type {
  BundleHead,
  GitObjectFormat,
  Oid,
  PathEntry,
  PathReview,
  PinIntent,
  RefName,
  RepoPath,
  Sha256,
  Snapshot,
  SnapshotProposal,
} from "./model.ts";

/**
 * Fixed `worktree-v1` commit metadata: identical parent, tree, and format
 * must always produce the identical commit OID. The epoch date keeps the
 * snapshot a pure function of tree content — no capture-time clock leaks into
 * custody identity.
 */
export const WORKTREE_V1_METADATA = {
  authorName: "compfuzor archive",
  authorEmail: "archive@compfuzor.invalid",
  committerName: "compfuzor archive",
  committerEmail: "archive@compfuzor.invalid",
  date: "@0 +0000",
  message: "compfuzor worktree snapshot (worktree-v1)",
} as const;

/**
 * Explicit snapshot request: the caller (inventory/plan) supplies the exact
 * source root, object format, HEAD, and the selected tracked/untracked path
 * manifests. Nothing is discovered implicitly, no ignore rule or filter is
 * consulted to widen the selection, and the module never invents a ready
 * plan — it returns the snapshot that these inputs actually produce.
 */
export interface PrepareSnapshotInput {
  /** Absolute path of the legacy checkout root (its worktree). */
  readonly sourceRoot: string;
  /** Absolute path of an existing directory for private scratch, outside the source. */
  readonly scratchRoot: string;
  readonly objectFormat: GitObjectFormat;
  /** Source HEAD commit OID: the snapshot parent and clean-tree baseline. */
  readonly headOid: Oid;
  /**
   * Tracked paths whose current worktree state must be re-staged; a path that
   * is missing from the worktree stages as a deletion. Index-only state is
   * not consulted: the scratch index is built from the HEAD tree.
   */
  readonly restageTracked: readonly RepoPath[];
  /** Explicitly selected untracked paths to include in the synthetic tree. */
  readonly addUntracked: readonly RepoPath[];
  readonly stagedVsUnstaged: Snapshot["stagedVsUnstaged"];
  readonly excludeFileSha256: Sha256 | null;
  readonly excludedUntracked: readonly RepoPath[];
  readonly ignoredPaths: readonly RepoPath[];
  readonly trackedSensitivePaths: readonly RepoPath[];
  readonly pathReview: PathReview | null;
  /**
   * Proposed path/mode/blob manifest (sorted by path). When present the
   * staged tree must match it exactly or staging aborts with a drift error —
   * never a silent capture of a different tree than the one reviewed.
   */
  readonly expected: readonly PathEntry[] | null;
}

/**
 * The private stage plus the exact snapshot it produced. `snapshot` is null
 * exactly when the staged tree is identical to the HEAD tree (nothing
 * differed, so no working-copy commit exists). The handle is the closure
 * token for `proveBundle`; the caller owns the scratch directory lifecycle.
 */
export interface StageHandle {
  readonly stageRoot: string;
  readonly gitDir: string;
  readonly sourceRoot: string;
  readonly sourceObjectsDir: string;
  readonly objectFormat: GitObjectFormat;
  readonly headOid: Oid;
  readonly headTreeOid: Oid;
  readonly snapshot: Snapshot | null;
  readonly snapshotCommitOid: Oid | null;
}

/**
 * A private bundle that has already survived the complete proof: closure
 * materialized in scratch, alternates removed, a no-prerequisite bundle
 * created, and every advertised head plus the snapshot path manifest
 * restored and re-checked inside a fresh empty repository of the same object
 * format. Sealing it into the durable vault is a later, separate step.
 */
export interface ProvenBundle {
  readonly stage: StageHandle;
  readonly bundlePath: string;
  readonly bundleSha256: Sha256;
  readonly verifiedHeads: readonly BundleHead[];
  readonly freshRestoreVerified: true;
  /** Kept for caller inspection; removed with the rest of the scratch. */
  readonly restoreRepoPath: string;
  readonly snapshotManifestVerified: boolean;
}

/**
 * Receipt-shaped bundle restoration check, reusable by the independent
 * verifier: prove that a bundle alone restores the exact pin refs/OIDs,
 * object types and full snapshot path manifest into a fresh empty repository
 * of the declared object format — with no source, destination, or stage
 * repository anywhere in reach. `pins` are the receipt's pins (or the
 * caller's selected set); only ref/OID/type fields are consulted.
 */
export interface RestorationCheckInput {
  readonly bundlePath: string;
  readonly objectFormat: GitObjectFormat;
  /** Existing directory outside any repository for the disposable restore. */
  readonly scratchRoot: string;
  readonly pins: readonly PinIntent[];
  readonly snapshot: {
    readonly commitOid: Oid;
    readonly treeOid: Oid;
    readonly paths: readonly PathEntry[];
  } | null;
}

export interface RestorationCheck {
  readonly freshRestoreVerified: true;
  readonly restoreRepoPath: string;
  readonly verifiedHeads: readonly BundleHead[];
  readonly snapshotManifestVerified: boolean;
}

const encoder = new TextEncoder();

/** Both directions matter: scratch inside source and source inside scratch. */
const contains = (parent: string, child: string): boolean => {
  const rel = relative(parent, child);
  return rel === "" || (rel !== ".." && !rel.startsWith("../") && !isAbsolute(rel));
};

const stepFailure = (
  code: "inspection-failed" | "bundle-invalid",
  step: string,
  error: unknown,
): CustodyError =>
  error instanceof CustodyError
    ? error
    : new CustodyError(
        code,
        `${step} failed: ${error instanceof Error ? error.message : String(error)}`,
      );

interface Wiring {
  readonly gitDir: string;
  readonly workTree: string | null;
}

/**
 * Every stage command names its repository explicitly. Worktree-touching
 * commands (check-attr, add) add GIT_WORK_TREE and run with the source root
 * as cwd; everything else runs inside the bare scratch with no worktree, so
 * ls-tree paths are never relativized.
 */
const runStage = async (
  wiring: Wiring,
  args: readonly string[],
  env: Record<string, string> = {},
): Promise<Uint8Array> => {
  const routing: Record<string, string> = {
    GIT_DIR: wiring.gitDir,
    GIT_OBJECT_DIRECTORY: join(wiring.gitDir, "objects"),
    GIT_INDEX_FILE: join(wiring.gitDir, "index"),
  };
  if (wiring.workTree !== null) routing.GIT_WORK_TREE = wiring.workTree;
  return checkedRead(
    args,
    wiring.workTree ?? wiring.gitDir,
    { ...routing, ...env },
    "private stage git",
  );
};

/** Discovery and restore commands: no Git routing, cwd decides the repo. */
const runPlain = async (args: readonly string[], cwd: string): Promise<Uint8Array> =>
  checkedRead(args, cwd, {}, "git");

/**
 * `gitRead` isolation plus checked exit: stdout bytes on success, `GitError`
 * (argv/stderr retained, never printed) on failure, wrapped as a custody
 * failure naming the step.
 */
const checkedRead = async (
  args: readonly string[],
  cwd: string,
  env: Record<string, string>,
  step: string,
  input?: Uint8Array,
): Promise<Uint8Array> => {
  try {
    const result = await Effect.runPromise(gitRead(args, { cwd, env, input }));
    if (result.exitCode !== 0)
      throw new GitError({ argv: args, cwd, exitCode: result.exitCode, stderr: result.stderr });
    return result.stdout;
  } catch (error) {
    throw stepFailure("inspection-failed", `${step} ${args[0] ?? ""}`, error);
  }
};

const unsupported = (reason: string, subject: string | null): CustodyError =>
  new CustodyError("unsupported-repository", reason, subject);

const denyInternals = (
  paths: readonly RepoPath[],
  what: string,
  fail: (message: string) => never = invalid,
): void => {
  for (const entry of paths)
    if (entry.split("/").some((part) => part === ".git" || part === ".jj"))
      fail(`${what} names nested .git/.jj internals: ${entry}`);
};

const validatedPaths = (paths: readonly RepoPath[], what: string): readonly RepoPath[] => {
  const seen = new Set<string>();
  for (const entry of paths) {
    repoPath(entry);
    if (seen.has(entry)) invalid(`duplicate ${what} path: ${entry}`);
    seen.add(entry);
  }
  return [...paths];
};

const pathOrder = (a: PathEntry, b: PathEntry): number =>
  a.path < b.path ? -1 : a.path > b.path ? 1 : 0;

const validateExpected = (
  expected: readonly PathEntry[],
  format: GitObjectFormat,
): readonly PathEntry[] => {
  const copy = [...expected];
  for (const entry of copy) {
    repoPath(entry.path);
    oid(entry.blobOid, format);
    if (entry.mode === "160000")
      throw unsupported(`gitlink path requires separate custody design: ${entry.path}`, entry.path);
  }
  denyInternals(
    copy.map(({ path }) => path),
    "expected manifest",
  );
  const sorted = [...copy].sort(pathOrder);
  for (let i = 0; i < sorted.length; i++)
    if (expected[i] !== sorted[i]) invalid("expected manifest must be sorted by path");
  return sorted;
};

/**
 * Read-only source discovery: the Git dir must be a plain directory (not a
 * linked worktree or bare repo) holding the declared object format, with no
 * alternates or shallow grafts of its own. Alternates in the source would be
 * followed transitively by the stage, and shallow/partial objects cannot
 * back a complete-custody promise.
 */
const discoverSource = async (
  sourceRoot: string,
  format: GitObjectFormat,
): Promise<{ readonly gitDir: string; readonly objectsDir: string }> => {
  const gitDir = utf8Fatal(await runPlain(["rev-parse", "--absolute-git-dir"], sourceRoot)).trim();
  const commonRaw = utf8Fatal(await runPlain(["rev-parse", "--git-common-dir"], sourceRoot)).trim();
  const commonDir = commonRaw.startsWith("/") ? commonRaw : join(sourceRoot, commonRaw);
  if (commonDir !== gitDir)
    throw unsupported(
      `linked worktrees are unsupported: git dir ${gitDir} differs from common dir ${commonDir}`,
      sourceRoot,
    );
  if (
    utf8Fatal(await runPlain(["rev-parse", "--is-bare-repository"], sourceRoot)).trim() === "true"
  )
    throw unsupported("a bare source has no worktree to stage", sourceRoot);
  const observed = utf8Fatal(
    await runPlain(["rev-parse", "--show-object-format"], sourceRoot),
  ).trim();
  if (observed !== format)
    invalid(`source object format is ${observed}, but ${format} was declared`);
  const objectsDir = join(gitDir, "objects");
  const fileExists = async (file: string): Promise<boolean> => {
    try {
      await readFile(file);
      return true;
    } catch {
      return false;
    }
  };
  for (const [file, reason] of [
    [join(objectsDir, "info", "alternates"), "source itself uses alternates"],
    [join(gitDir, "shallow"), "shallow source"],
  ] as const) {
    if (await fileExists(file)) throw unsupported(reason, file);
  }
  return { gitDir, objectsDir };
};

/** check-attr needs the path list on stdin as NUL-delimited bytes. */
const runStageWithInput = async (
  wiring: Wiring,
  args: readonly string[],
  paths: readonly RepoPath[],
): Promise<Uint8Array> => {
  const routing: Record<string, string> = {
    GIT_DIR: wiring.gitDir,
    GIT_OBJECT_DIRECTORY: join(wiring.gitDir, "objects"),
    GIT_INDEX_FILE: join(wiring.gitDir, "index"),
  };
  if (wiring.workTree !== null) routing.GIT_WORK_TREE = wiring.workTree;
  return checkedRead(
    args,
    wiring.workTree ?? wiring.gitDir,
    routing,
    "private stage git",
    encoder.encode(`${paths.join("\0")}\0`),
  );
};

/**
 * Refuse clean/smudge filter attributes *before* any payload file is read.
 * `text`/`eol` re-encoding is Git-native and deterministic; an external
 * filter driver is an arbitrary program whose bytes cannot be promised here.
 */
const assertNoFilters = async (wiring: Wiring, paths: readonly RepoPath[]): Promise<void> => {
  if (!paths.length) return;
  const output = await runStageWithInput(
    wiring,
    ["check-attr", "--stdin", "-z", "-z", "filter"],
    paths,
  );
  const tokens = utf8Fatal(output).split("\0");
  if (tokens.at(-1) === "") tokens.pop();
  if (tokens.length !== paths.length * 3) invalid("malformed check-attr output");
  const requested = new Set<string>(paths);
  for (let i = 0; i < tokens.length; i += 3) {
    const path = tokens[i];
    const attribute = tokens[i + 1];
    const value = tokens[i + 2];
    if (attribute !== "filter" || !requested.has(path))
      invalid("check-attr reported an unexpected path");
    if (value !== "unspecified" && value !== "unset")
      throw unsupported(`clean/smudge filter attribute cannot be faithfully staged: ${path}`, path);
  }
};

/**
 * Parse `ls-tree -r -z` into the canonical manifest: the first TAB separates
 * `mode type oid` from a path that may contain any bytes (spaces, globs,
 * newlines are impossible in lossless-UTF-8 validated names). Entries are
 * sorted by path (code-unit order) — the order the receipt and path-review
 * digest are computed over.
 */
const parseManifest = (bytes: Uint8Array, format: GitObjectFormat): readonly PathEntry[] => {
  const records: Uint8Array[] = [];
  let start = 0;
  for (let i = 0; i < bytes.length; i++) {
    if (bytes[i] === 0) {
      records.push(bytes.subarray(start, i));
      start = i + 1;
    }
  }
  if (start < bytes.length) records.push(bytes.subarray(start));
  const entries: PathEntry[] = [];
  for (const record of records) {
    if (!record.length) continue;
    let tab = -1;
    for (let i = 0; i < record.length; i++)
      if (record[i] === 9) {
        tab = i;
        break;
      }
    if (tab < 0) invalid("malformed ls-tree record");
    const meta = utf8Fatal(record.subarray(0, tab)).split(" ");
    if (meta.length !== 3) invalid("malformed ls-tree metadata");
    const [mode, type, oidText] = meta;
    const entryPath = repoPath(utf8Fatal(record.subarray(tab + 1)));
    if (type === "commit")
      throw unsupported(`gitlink path requires separate custody design: ${entryPath}`, entryPath);
    if (type !== "blob") invalid(`unexpected ls-tree entry type: ${type}`);
    if (mode !== "100644" && mode !== "100755" && mode !== "120000")
      invalid(`unexpected ls-tree mode: ${mode}`);
    entries.push({ path: entryPath, mode, blobOid: oid(oidText, format) });
  }
  entries.sort(pathOrder);
  return entries;
};

/** The staged manifest must equal the reviewed proposal exactly, or stop. */
const compareWithExpected = (
  manifest: readonly PathEntry[],
  expected: readonly PathEntry[],
): void => {
  if (canonicalJson(manifest) === canonicalJson(expected)) return;
  const actual = new Map(manifest.map((entry) => [entry.path as string, entry]));
  const proposed = new Map(expected.map((entry) => [entry.path as string, entry]));
  const differences: string[] = [];
  for (const [path, entry] of proposed) {
    const staged = actual.get(path);
    if (staged === undefined) differences.push(`missing ${path}`);
    else if (staged.mode !== entry.mode || staged.blobOid !== entry.blobOid)
      differences.push(`changed ${path}`);
  }
  for (const path of actual.keys()) if (!proposed.has(path)) differences.push(`extra ${path}`);
  throw new CustodyError(
    "source-drift",
    `staged tree differs from the reviewed manifest: ${differences.slice(0, 8).join("; ")}`,
    differences[0] ?? null,
  );
};

/** Mirror the receipt-level path-review invariants while the stage is live. */
const bindPathReview = (
  snapshotPaths: readonly PathEntry[],
  input: PrepareSnapshotInput,
  snapshotWillExist: boolean,
): void => {
  const review = input.pathReview;
  if (snapshotWillExist && input.trackedSensitivePaths.length > 0 && review === null)
    invalid("sensitive tracked paths require an approved path review");
  if (
    snapshotWillExist &&
    input.stagedVsUnstaged === "reported-not-preserved" &&
    review?.stagedVsUnstaged == null
  )
    invalid("losing the staged/unstaged split requires the path review's single-tree approval");
  if (review === null) return;
  if (review.manifestSha256 !== sha256(encoder.encode(`${canonicalJson(snapshotPaths)}\n`)))
    invalid("path review digest does not match the staged manifest");
  const staged = new Map(snapshotPaths.map((entry) => [entry.path as string, entry]));
  for (const entry of review.included) {
    const match = staged.get(entry.path);
    if (match === undefined || match.mode !== entry.mode || match.blobOid !== entry.blobOid)
      invalid(`path review includes a path absent from the staged manifest: ${entry.path}`);
  }
  const reviewed = new Set(review.included.map((entry) => entry.path as string));
  for (const path of input.trackedSensitivePaths)
    if (!reviewed.has(path)) invalid(`sensitive tracked path has no review entry: ${path}`);
};

interface StagedTree {
  readonly wiring: Wiring;
  readonly stageRoot: string;
  readonly gitDir: string;
  readonly sourceRoot: string;
  readonly sourceObjectsDir: string;
  readonly objectFormat: GitObjectFormat;
  readonly headOid: Oid;
  readonly headTreeOid: Oid;
  readonly treeOid: Oid;
  readonly manifest: readonly PathEntry[];
  readonly dirty: boolean;
}

/**
 * Shared staging core for `prepareSnapshot` and `previewSnapshot`: validate
 * the request, build the private stage, stage exactly the requested paths,
 * and compute the exact tree manifest (compared against `expected` when
 * present). Approval enforcement is deliberately **not** part of the core —
 * the preview and apply doors differ exactly there. Scratch is left in place
 * on failure for inspection; its lifecycle belongs to the caller.
 */
const stageTree = async (input: PrepareSnapshotInput): Promise<StagedTree> => {
  const format = input.objectFormat;
  oid(input.headOid, format);
  const restage = validatedPaths(input.restageTracked, "restaged tracked");
  const untracked = validatedPaths(input.addUntracked, "selected untracked");
  validatedPaths(input.excludedUntracked, "excluded untracked");
  validatedPaths(input.ignoredPaths, "ignored");
  validatedPaths(input.trackedSensitivePaths, "sensitive tracked");
  denyInternals(restage, "tracked restage list");
  denyInternals(untracked, "selected untracked list");
  for (const path of restage)
    if ((untracked as readonly string[]).includes(path))
      invalid(`path is both tracked-restage and untracked: ${path}`);
  const expected = input.expected === null ? null : validateExpected(input.expected, format);

  const sourceRoot = await realpath(input.sourceRoot).catch(() =>
    invalid(`source root does not exist: ${input.sourceRoot}`),
  );
  const scratchRoot = await realpath(input.scratchRoot).catch(() =>
    invalid(`scratch root does not exist: ${input.scratchRoot}`),
  );
  if (contains(sourceRoot, scratchRoot))
    invalid("private scratch must live outside the source checkout");
  if (contains(scratchRoot, sourceRoot))
    invalid("source checkout must not live inside the private scratch");

  const { objectsDir: sourceObjectsDir } = await discoverSource(sourceRoot, format);

  const stageRoot = await mkdtemp(join(scratchRoot, "stage-"));
  const gitDir = join(stageRoot, "stage.git");
  await runPlain(
    [
      "init",
      "--quiet",
      "--bare",
      `--object-format=${format}`,
      "--initial-branch=compfuzor-stage-unborn",
      gitDir,
    ],
    stageRoot,
  );
  const wiring: Wiring = { gitDir, workTree: null };
  const workWiring: Wiring = { gitDir, workTree: sourceRoot };
  await runStage(wiring, ["config", "core.bare", "false"]);
  // Read-only view of source objects; scratch receives every new object.
  const alternatesPath = join(gitDir, "objects", "info", "alternates");
  await writeFile(alternatesPath, `${sourceObjectsDir}\n`);

  const headTreeOid = oid(
    utf8Fatal(await runStage(wiring, ["rev-parse", `${input.headOid}^{tree}`])).trim(),
    format,
  );
  await runStage(wiring, ["read-tree", headTreeOid]);

  const selected = [...restage, ...untracked];
  await assertNoFilters(workWiring, selected);
  if (selected.length > 0) {
    const pathspecFile = join(stageRoot, "pathspec.nul");
    await writeFile(pathspecFile, encoder.encode(selected.map((p) => `:(literal)${p}`).join("\0")));
    await runStage(workWiring, [
      "add",
      "-A",
      `--pathspec-from-file=${pathspecFile}`,
      "--pathspec-file-nul",
    ]);
  }
  const treeOid = oid(utf8Fatal(await runStage(wiring, ["write-tree"])).trim(), format);
  const manifest = parseManifest(await runStage(wiring, ["ls-tree", "-r", "-z", treeOid]), format);
  denyInternals(
    manifest.map(({ path }) => path),
    "staged tree",
    (message) => {
      throw unsupported(message, null);
    },
  );
  if (expected !== null) compareWithExpected(manifest, expected);
  return {
    wiring,
    stageRoot,
    gitDir,
    sourceRoot,
    sourceObjectsDir,
    objectFormat: format,
    headOid: input.headOid,
    headTreeOid,
    treeOid,
    manifest,
    dirty: treeOid !== headTreeOid,
  };
};

/** Mint the deterministic `worktree-v1` commit; caller has decided it exists. */
const mintWorktreeCommit = async (staged: StagedTree): Promise<Oid> =>
  oid(
    utf8Fatal(
      await runStage(
        staged.wiring,
        ["commit-tree", staged.treeOid, "-p", staged.headOid, "-m", WORKTREE_V1_METADATA.message],
        {
          GIT_AUTHOR_NAME: WORKTREE_V1_METADATA.authorName,
          GIT_AUTHOR_EMAIL: WORKTREE_V1_METADATA.authorEmail,
          GIT_COMMITTER_NAME: WORKTREE_V1_METADATA.committerName,
          GIT_COMMITTER_EMAIL: WORKTREE_V1_METADATA.committerEmail,
          GIT_AUTHOR_DATE: WORKTREE_V1_METADATA.date,
          GIT_COMMITTER_DATE: WORKTREE_V1_METADATA.date,
        },
      ),
    ).trim(),
    staged.objectFormat,
  );

/**
 * Build the `worktree-v1` snapshot of a legacy checkout inside a new private
 * bare scratch repository. The source's ODB, index, refs, reflogs and
 * worktree are never written; new blobs, trees and the optional deterministic
 * commit exist only in scratch. The synthetic commit is minted **iff** the
 * staged tree differs from the HEAD tree, with fixed metadata so identical
 * parent+tree always produce the identical commit OID.
 *
 * This is the apply door: sensitive tracked paths and a reported staged
 * split require a path review already bound to the exact manifest digest,
 * and `expected: null` is never an approval bypass. Use `previewSnapshot`
 * to compute the proposal and digest first.
 */
export const prepareSnapshot = async (input: PrepareSnapshotInput): Promise<StageHandle> => {
  const staged = await stageTree(input);
  bindPathReview(staged.manifest, input, staged.dirty);
  const snapshotCommitOid = staged.dirty ? await mintWorktreeCommit(staged) : null;
  const snapshot: Snapshot | null =
    snapshotCommitOid === null
      ? null
      : {
          format: "worktree-v1",
          parentOid: input.headOid,
          treeOid: staged.treeOid,
          commitOid: snapshotCommitOid,
          paths: staged.manifest,
          stagedVsUnstaged: input.stagedVsUnstaged,
          excludeFileSha256: input.excludeFileSha256,
          excludedUntracked: [...input.excludedUntracked],
          ignoredPaths: [...input.ignoredPaths],
          trackedSensitivePaths: [...input.trackedSensitivePaths],
          pathReview: input.pathReview,
        };
  return {
    stageRoot: staged.stageRoot,
    gitDir: staged.gitDir,
    sourceRoot: staged.sourceRoot,
    sourceObjectsDir: staged.sourceObjectsDir,
    objectFormat: staged.objectFormat,
    headOid: staged.headOid,
    headTreeOid: staged.headTreeOid,
    snapshot,
    snapshotCommitOid,
  };
};

/**
 * Compute the proposed snapshot without requiring any approval: the answer
 * to the review chicken-and-egg. The preview runs the identical private,
 * source-read-only staging as `prepareSnapshot` and returns the shared
 * [`SnapshotProposal`](./model.ts) contract — the exact manifest, the
 * deterministic commit identity it would mint, the digest a path review must
 * bind, and the review requirements the apply door will enforce — then
 * disposes its throwaway scratch. A clean source (tree identical to HEAD)
 * yields `null`, exactly like a plan's `proposedSnapshot`: inspect the
 * inventory's HEAD tree manifest and use the receipt-level
 * `cleanHeadPathReview` there; this module owns only the dirty preview/apply
 * pair. Plain data only — never a `StageHandle`, nothing transferable to
 * `proveBundle`, and no force-style flag that could weaken `prepareSnapshot`.
 */
export const previewSnapshot = async (
  input: PrepareSnapshotInput,
): Promise<SnapshotProposal | null> => {
  const staged = await stageTree(input);
  try {
    if (!staged.dirty) return null;
    const commitOid = await mintWorktreeCommit(staged);
    return {
      format: "worktree-v1",
      parentOid: input.headOid,
      treeOid: staged.treeOid,
      commitOid,
      paths: staged.manifest,
      stagedVsUnstaged: input.stagedVsUnstaged,
      excludeFileSha256: input.excludeFileSha256,
      excludedUntracked: [...input.excludedUntracked],
      ignoredPaths: [...input.ignoredPaths],
      trackedSensitivePaths: [...input.trackedSensitivePaths],
      manifestSha256: sha256(encoder.encode(`${canonicalJson(staged.manifest)}\n`)),
      reviewRequirements: {
        sensitivePaths: [...input.trackedSensitivePaths],
        stagedVsUnstagedApprovalRequired: input.stagedVsUnstaged === "reported-not-preserved",
      },
    };
  } finally {
    await rm(staged.stageRoot, { recursive: true, force: true });
  }
};

const bundleInvalid = (reason: string, subject: string | null = null): CustodyError =>
  new CustodyError("bundle-invalid", reason, subject);

const parseBundleHeads = (bytes: Uint8Array, format: GitObjectFormat): readonly BundleHead[] => {
  // `git bundle list-heads` prints `<oid> SP <ref>` per advertised head.
  const heads: BundleHead[] = [];
  for (const line of utf8Fatal(bytes).split("\n")) {
    if (!line) continue;
    const space = line.indexOf(" ");
    if (space < 0) throw bundleInvalid("malformed bundle head record");
    const headOid = oid(line.slice(0, space), format);
    const name = line.slice(space + 1);
    let ref: RefName;
    try {
      ref = refName(name);
    } catch {
      throw bundleInvalid(`bundle advertises a non-ref head: ${name}`, name);
    }
    heads.push({ ref, oid: headOid });
  }
  heads.sort((a, b) => (a.ref < b.ref ? -1 : a.ref > b.ref ? 1 : 0));
  return heads;
};

const parseForEachRef = (
  bytes: Uint8Array,
  format: GitObjectFormat,
): ReadonlyMap<string, string> => {
  const refs = new Map<string, string>();
  const output = utf8Fatal(bytes);
  if (output === "") return refs;
  if (!output.endsWith("\n")) invalid("truncated for-each-ref listing");
  for (const line of output.split("\n").slice(0, -1)) {
    const fields = line.split("\0");
    if (fields.length !== 2) invalid("malformed for-each-ref listing");
    refs.set(refName(fields[0]), oid(fields[1], format));
  }
  return refs;
};

/**
 * Structural pin validation shared by the stage proof and the standalone
 * restoration check: OIDs match the declared format, source and destination
 * OIDs are identical, refs are valid and pairwise non-conflicting, and only
 * commit/tag tips are promised — `git bundle` on the installed Git can
 * mechanically carry tree/blob tip refs, but the custody promise (ancestry,
 * peeled targets, manifest checks) is only defined for commits and tags, so
 * v1 refuses them rather than promising something untested.
 */
const validateBundlePins = (
  format: GitObjectFormat,
  pins: readonly PinIntent[],
): ReadonlyMap<string, PinIntent> => {
  if (!pins.length) invalid("no pins selected for the bundle proof");
  const seen = new Set<string>();
  const pinMap = new Map<string, PinIntent>();
  for (const pin of pins) {
    if (pin.destinationOid !== pin.sourceOid)
      invalid(`pin source/destination OIDs differ: ${pin.sourceKind}`);
    oid(pin.sourceOid, format);
    if (pin.objectType === "tree" || pin.objectType === "blob")
      throw unsupported(
        `git bundle custody is not promised for ${pin.objectType} tips; ` +
          "pinned trees/blobs need separate design",
        pin.sourceName,
      );
    const ref = refName(pin.destinationRef);
    if (seen.has(ref)) invalid(`duplicate pin ref: ${ref}`);
    for (const other of seen)
      if (prefixConflict(ref, other))
        throw new CustodyError(
          "occupied-namespace",
          `pin refs conflict: ${ref} versus ${other}`,
          ref,
        );
    seen.add(ref);
    pinMap.set(ref, pin);
  }
  return pinMap;
};

/**
 * Prove a bundle restores its complete custody promise using nothing but
 * itself: `bundle list-heads` must advertise exactly the pin refs at the pin
 * OIDs, `bundle verify` must succeed inside a fresh empty repository of the
 * declared object format (which also proves there are no prerequisites the
 * empty repo would lack), `fetch '+refs/*:refs/*'` must recreate every pin
 * ref, each object must have its pinned type (tag objects must still peel to
 * a commit), the snapshot commit must carry exactly the recorded tree and
 * path/mode/blob manifest, and a full reachable-object walk must succeed
 * there. The restore repository is returned for inspection and disposal.
 */
export const checkBundleRestoration = async (
  input: RestorationCheckInput,
): Promise<RestorationCheck> => {
  const format = input.objectFormat;
  const pinMap = validateBundlePins(format, input.pins);
  const scratchRoot = await realpath(input.scratchRoot).catch(() =>
    invalid(`restore scratch root does not exist: ${input.scratchRoot}`),
  );
  const heads = parseBundleHeads(
    await runPlain(["bundle", "list-heads", input.bundlePath], scratchRoot),
    format,
  );
  const advertised = new Map(heads.map((head) => [head.ref as string, head.oid as string]));
  if (advertised.size !== pinMap.size || [...pinMap.keys()].some((ref) => !advertised.has(ref)))
    throw bundleInvalid(
      `bundle advertises ${advertised.size} heads for ${pinMap.size} pins`,
      [...advertised.keys()].find((ref) => !pinMap.has(ref)) ?? null,
    );
  for (const [ref, pin] of pinMap)
    if (advertised.get(ref) !== pin.sourceOid)
      throw bundleInvalid(`bundle head OID differs from pin: ${ref}`, ref);

  const restoreDir = await mkdtemp(join(scratchRoot, "restore-"));
  const restoreGit = join(restoreDir, "restore.git");
  await runPlain(
    [
      "init",
      "--quiet",
      "--bare",
      `--object-format=${format}`,
      "--initial-branch=compfuzor-restore-unborn",
      restoreGit,
    ],
    restoreDir,
  );
  const verifyOut = utf8Fatal(await runPlain(["bundle", "verify", input.bundlePath], restoreGit));
  const algorithm = verifyOut.match(/hash algorithm: (sha1|sha256)/);
  if (algorithm !== null && algorithm[1] !== format)
    throw bundleInvalid(`bundle object format ${algorithm[1]} differs from ${format}`);
  await runPlain(["fetch", "--quiet", input.bundlePath, "+refs/*:refs/*"], restoreGit);
  const restored = parseForEachRef(
    await runPlain(["for-each-ref", "--format=%(refname)%00%(objectname)"], restoreGit),
    format,
  );
  if (restored.size !== pinMap.size)
    throw bundleInvalid(`fresh restore holds ${restored.size} refs for ${pinMap.size} pins`);
  for (const [ref, pin] of pinMap) {
    if (restored.get(ref) !== pin.sourceOid)
      throw bundleInvalid(`restored ref OID differs from pin: ${ref}`, ref);
    const type = utf8Fatal(await runPlain(["cat-file", "-t", pin.sourceOid], restoreGit)).trim();
    if (type !== pin.objectType)
      throw bundleInvalid(
        `restored object type ${type} differs from ${pin.objectType}: ${ref}`,
        ref,
      );
    if (pin.objectType === "tag")
      await runPlain(["rev-parse", `${pin.sourceOid}^{commit}`], restoreGit);
  }
  await runPlain(["rev-list", "--objects", "--all"], restoreGit);

  let snapshotManifestVerified = false;
  if (input.snapshot !== null) {
    const restoredTree = utf8Fatal(
      await runPlain(["rev-parse", `${input.snapshot.commitOid}^{tree}`], restoreGit),
    ).trim();
    if (restoredTree !== input.snapshot.treeOid)
      throw bundleInvalid("restored snapshot commit does not carry the staged tree");
    const manifest = parseManifest(
      await runPlain(["ls-tree", "-r", "-z", input.snapshot.commitOid], restoreGit),
      format,
    );
    if (canonicalJson(manifest) !== canonicalJson(input.snapshot.paths))
      throw bundleInvalid("restored snapshot path manifest differs from the staged manifest");
    snapshotManifestVerified = true;
  }
  return {
    freshRestoreVerified: true,
    restoreRepoPath: restoreGit,
    verifiedHeads: heads,
    snapshotManifestVerified,
  };
};

/**
 * Prove a complete, source-independent bundle of the selected typed pins
 * (branches, HEAD, annotated/lightweight tags, stash, reflog candidates, and
 * the synthetic working-copy commit).
 *
 * The proof: attach one staging ref per pin, materialize the reachable
 * closure into the scratch ODB (`repack -a -d`), **remove the alternates
 * pointer to the source**, walk every object locally, create a
 * no-prerequisite `git bundle create --all`, and hand the resulting private
 * bundle to `checkBundleRestoration` for the fresh-repository proof. The
 * returned bundle is proven but still private: sealing it into the durable
 * vault (atomic write, fsync, permissions) belongs to the vault owner.
 */
export const proveBundle = async (
  stage: StageHandle,
  pins: readonly PinIntent[],
): Promise<ProvenBundle> => {
  const format = stage.objectFormat;
  const wiring: Wiring = { gitDir: stage.gitDir, workTree: null };
  const pinMap = validateBundlePins(format, pins);
  for (const pin of pins) {
    if (pin.sourceKind === "head" && pin.sourceOid !== stage.headOid)
      invalid("HEAD pin does not match the staged source HEAD");
    if (pin.sourceKind === "working-copy") {
      if (stage.snapshotCommitOid === null)
        throw unsupported("working-copy pin on a clean (snapshot-free) stage", pin.sourceName);
      if (pin.sourceOid !== stage.snapshotCommitOid)
        invalid("working-copy pin does not match the staged snapshot commit");
    }
  }
  if (
    stage.snapshotCommitOid !== null &&
    !pins.some(({ sourceKind }) => sourceKind === "working-copy")
  )
    invalid("a staged snapshot requires its working-copy pin in the bundle");

  for (const [ref, pin] of pinMap) await runStage(wiring, ["update-ref", ref, pin.sourceOid]);
  await runStage(wiring, ["repack", "-a", "-d", "-q"]);
  // From here the stage must be self-contained: no source object access.
  await rm(join(stage.gitDir, "objects", "info", "alternates"), { force: true });
  await runStage(wiring, ["rev-list", "--objects", "--all"]);
  await runStage(wiring, ["cat-file", "--batch-all-objects", "--batch-check"]);

  const bundlePath = join(stage.stageRoot, "source.bundle");
  await runStage(wiring, ["bundle", "create", bundlePath, "--all"]);
  const check = await checkBundleRestoration({
    bundlePath,
    objectFormat: format,
    scratchRoot: stage.stageRoot,
    pins,
    snapshot:
      stage.snapshot === null
        ? null
        : {
            commitOid: stage.snapshot.commitOid,
            treeOid: stage.snapshot.treeOid,
            paths: stage.snapshot.paths,
          },
  });
  return {
    stage,
    bundlePath,
    bundleSha256: sha256(await readFile(bundlePath)),
    verifiedHeads: check.verifiedHeads,
    freshRestoreVerified: check.freshRestoreVerified,
    restoreRepoPath: check.restoreRepoPath,
    snapshotManifestVerified: check.snapshotManifestVerified,
  };
};
