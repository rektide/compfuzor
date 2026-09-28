/**
 * Source-independent custody verification (`verify-adoption`).
 *
 * The verifier reads the receipt by full ref from the destination Git ODB
 * (`<receipt ref>:adoption.json`), strictly re-parses it, and re-derives every
 * custody claim against the archive and its private vault bundle — without
 * opening the legacy checkout. Proven at verification time:
 *
 * - the receipt ref resolves to a parentless metadata commit holding exactly
 *   one `adoption.json` blob (whose canonical JSON never names its own commit);
 * - every pin's destination ref exists in the archive with the exact expected
 *   OID and object type, its lane recomputed from the receipt's own identity,
 *   with commit/tag closures walking inside the destination ODB;
 * - the recorded full HEAD tree and the worktree snapshot tree are reproduced
 *   path/mode/blob-exactly from the destination object store;
 * - the vault bundle hashes to its recorded checksum and restores completely
 *   through the shared `checkBundleRestoration` proof (exact advertised heads,
 *   no prerequisites, fresh empty repository with no alternates, per-pin
 *   type/closure, snapshot manifest equality).
 *
 * Reported separately from custody: destination drift (pre-import refs,
 * worktree, index observed now versus the receipt baseline) and optional
 * legacy source drift are diagnostics — subsequent drift never redefines
 * historical custody, and custody never grants retirement permission. jj
 * health is additional evidence (`readOnly` query mode, never snapshot/import):
 * its findings land in `retirementUnresolved`, and receipt-carried unresolved
 * items are preserved.
 *
 * Failure model: structural inability to observe a receipt at all (missing
 * ref, unusable destination) throws `CustodyError` for the CLI to exit
 * nonzero. Every check that a parsed receipt frames — ref/object/manifest/
 * bundle/vault evidence — is collected into `custodyFailures` with
 * `custodyVerified: false`, also a nonzero exit for the CLI. The only writes
 * this module ever performs are inside its private scratch directory.
 */
import { mkdtemp, open, readFile, readlink, realpath, rm, stat, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { constants } from "node:fs";
import { dirname, join } from "node:path";
import { Effect } from "effect";
import { preflight } from "../repository/health.ts";
import { gitRead, utf8Fatal } from "../repository/git.ts";
import { localHelpers } from "./inventory/probe.ts";
import { readVaultBundle, VaultPathComponentError } from "./vault.ts";
import { checkBundleRestoration, type StageExecution } from "./stage.ts";
import { canonicalJson, parseReceipt, pinRef, refName, sha256 } from "./codec.ts";
import { CustodyError } from "./errors.ts";
import type {
  GitObjectFormat,
  Issue,
  Oid,
  PathEntry,
  ReceiptV1,
  RefName,
  Verification,
} from "./model.ts";

/** Everything `verifyAdoption` needs; the legacy path is optional diagnostics. */
export interface VerifyInput {
  /** Destination archive root (jj-colocated Git checkout). */
  readonly dest: string;
  /** Full receipt ref, e.g. `refs/adopt/receipts/<label>/<generation>`. */
  readonly receiptRef: string;
  /** Optional legacy source root: presence/head/refs/index are compared and reported as drift. */
  readonly legacy: string | null;
  /** Existing directory outside both checkouts for private restore scratch. */
  readonly scratchRoot: string;
}

/** A receipt observed in a destination: parsed values plus its commit OID. */
export interface ObservedReceipt {
  readonly receipt: ReceiptV1;
  readonly receiptCommitOid: Oid;
  readonly adoptionJson: Uint8Array;
}

/** One `for-each-ref` row: name, OID, direct type, peeled OID when annotated. */
interface RefRow {
  readonly name: string;
  readonly oid: Oid;
  readonly objectType: string;
  readonly peeledOid: Oid | null;
}

const REF_FORMAT = "--format=%(refname)%00%(objectname)%00%(objecttype)%00%(*objectname)%00";

const gitBlobOid = (bytes: Uint8Array, format: GitObjectFormat): string =>
  createHash(format).update(`blob ${bytes.byteLength}\0`).update(bytes).digest("hex");

/** Literal path acquisition: descriptors prevent a swapped directory or leaf
 * symlink from redirecting the read outside the legacy worktree. */
const readManifestPath = async (
  source: string,
  entry: PathEntry,
  signal?: AbortSignal,
): Promise<Uint8Array | null> => {
  const handles: Awaited<ReturnType<typeof open>>[] = [];
  try {
    signal?.throwIfAborted();
    handles.push(
      await open(source, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW),
    );
    const parts = entry.path.split("/");
    for (const part of parts.slice(0, -1)) {
      signal?.throwIfAborted();
      const parent = handles.at(-1)!;
      handles.push(
        await open(
          `/proc/self/fd/${parent.fd}/${part}`,
          constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW,
        ),
      );
    }
    signal?.throwIfAborted();
    const leaf = `/proc/self/fd/${handles.at(-1)!.fd}/${parts.at(-1)!}`;
    if (entry.mode === "120000") return await readlink(leaf, { encoding: "buffer" });
    const file = await open(leaf, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    handles.push(file);
    if (!(await file.stat()).isFile()) return null;
    return await file.readFile();
  } catch (error) {
    signal?.throwIfAborted();
    const code = (error as NodeJS.ErrnoException).code;
    if (["ENOENT", "ELOOP", "ENOTDIR", "EINVAL"].includes(code ?? "")) return null;
    throw error;
  } finally {
    for (const handle of handles.reverse()) await handle.close();
  }
};

/**
 * Read-only runner: raw stdout bytes on exit 0, `null` otherwise. Git failures
 * are observations for the caller to classify, never exceptions here.
 */
const softGit = async (
  args: readonly string[],
  cwd: string,
  signal?: AbortSignal,
): Promise<Uint8Array | null> => {
  signal?.throwIfAborted();
  const outcome = await Effect.runPromise(gitRead(args, { cwd }), { signal }).catch(
    (error: unknown) => {
      signal?.throwIfAborted();
      throw error;
    },
  );
  signal?.throwIfAborted();
  return outcome.exitCode === 0 ? outcome.stdout : null;
};

/** Structural runner: a nonzero exit means the step itself is broken. */
const hardGit = async (
  args: readonly string[],
  cwd: string,
  step: string,
  signal?: AbortSignal,
): Promise<Uint8Array> => {
  signal?.throwIfAborted();
  const outcome = await Effect.runPromise(gitRead(args, { cwd }), { signal }).catch(
    (error: unknown) => {
      signal?.throwIfAborted();
      throw error;
    },
  );
  signal?.throwIfAborted();
  if (outcome.exitCode !== 0)
    throw new CustodyError(
      "inspection-failed",
      `${step} failed (git ${args[0] ?? ""} exited ${outcome.exitCode})`,
    );
  return outcome.stdout;
};

const parseRefRows = (bytes: Uint8Array, format: GitObjectFormat): readonly RefRow[] => {
  const rows: RefRow[] = [];
  const text = utf8Fatal(bytes);
  if (text === "") return rows;
  if (!text.endsWith("\n"))
    throw new CustodyError("inspection-failed", "truncated for-each-ref output");
  for (const line of text.split("\n").slice(0, -1)) {
    const fields = line.split("\0");
    if (fields.length !== 5)
      throw new CustodyError("inspection-failed", "malformed for-each-ref output");
    rows.push({
      name: refName(fields[0]),
      oid: requireOid(fields[1], format),
      objectType: fields[2],
      peeledOid: fields[3] === "" ? null : requireOid(fields[3], format),
    });
  }
  return rows;
};

const requireOid = (value: string, format: GitObjectFormat): Oid => {
  if (!new RegExp(`^[0-9a-f]{${format === "sha1" ? 40 : 64}}$`).test(value))
    throw new CustodyError("inspection-failed", `observed OID is not ${format}-shaped: ${value}`);
  return value as Oid;
};

/**
 * Parse `ls-tree -r -z` into the canonical path/mode/blob manifest. The first
 * TAB separates `mode type oid` from a path that may contain any bytes; the
 * result is sorted by path, matching how receipts and reviews digest it.
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
    if (record.length === 0) continue;
    let tab = -1;
    for (let i = 0; i < record.length; i++)
      if (record[i] === 9) {
        tab = i;
        break;
      }
    if (tab < 0) throw new CustodyError("inspection-failed", "malformed ls-tree record");
    const meta = utf8Fatal(record.subarray(0, tab)).split(" ");
    if (meta.length !== 3)
      throw new CustodyError("inspection-failed", "malformed ls-tree metadata");
    if (meta[1] !== "blob")
      throw new CustodyError("inspection-failed", `unexpected ls-tree entry type: ${meta[1]}`);
    entries.push({
      path: requireRepoPath(utf8Fatal(record.subarray(tab + 1))),
      mode: requireMode(meta[0]),
      blobOid: requireOid(meta[2], format),
    });
  }
  entries.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  return entries;
};

const requireRepoPath = (value: string): PathEntry["path"] => {
  if (
    !value ||
    value.startsWith("/") ||
    value.split("/").some((part) => part === "" || part === "." || part === "..")
  )
    throw new CustodyError("inspection-failed", "observed tree path is not representable");
  return value as PathEntry["path"];
};

const requireMode = (value: string): PathEntry["mode"] => {
  if (value !== "100644" && value !== "100755" && value !== "120000")
    throw new CustodyError("inspection-failed", `unexpected ls-tree mode: ${value}`);
  return value;
};

/** The single `for-each-ref` row for an exact ref name, or null when absent. */
const exactRefRow = async (
  repo: string,
  ref: RefName,
  format: GitObjectFormat,
  signal?: AbortSignal,
): Promise<RefRow | null> => {
  const rows = parseRefRows(
    await hardGit(["for-each-ref", REF_FORMAT, ref], repo, `ref lookup for ${ref}`, signal),
    format,
  );
  return rows.find((row) => row.name === ref) ?? null;
};

/**
 * Observe and strictly parse the receipt behind `receiptRef`. Throws
 * `CustodyError` when the ref is missing or the repository is unusable —
 * apply's retry protocol and the verifier share this exact reading.
 */
export async function readReceipt(
  dest: string,
  receiptRef: string,
  execution: StageExecution = {},
): Promise<ObservedReceipt> {
  const { signal } = execution;
  signal?.throwIfAborted();
  const ref = refName(receiptRef);
  const destReal = await realpath(dest).catch(() => {
    throw new CustodyError("invalid-input", `destination does not exist: ${dest}`, dest);
  });
  const formatText = utf8Fatal(
    await hardGit(
      ["rev-parse", "--show-object-format"],
      destReal,
      "destination object format probe",
      signal,
    ),
  ).trim();
  if (formatText !== "sha1" && formatText !== "sha256")
    throw new CustodyError(
      "unsupported-repository",
      `destination object format is not sha1/sha256: ${formatText}`,
      destReal,
    );
  const format: GitObjectFormat = formatText;
  const row = await exactRefRow(destReal, ref, format, signal);
  if (row === null)
    throw new CustodyError(
      "verification-failed",
      `receipt ref does not exist in the destination: ${ref}`,
      ref,
    );
  if (row.objectType !== "commit")
    throw new CustodyError(
      "verification-failed",
      `receipt ref does not point at a commit (observed ${row.objectType}): ${ref}`,
      ref,
    );
  const blob = await softGit(["cat-file", "blob", `${row.oid}:adoption.json`], destReal, signal);
  if (blob === null)
    throw new CustodyError(
      "verification-failed",
      `receipt commit has no adoption.json blob: ${ref}`,
      ref,
    );
  return {
    receipt: parseReceipt(blob),
    receiptCommitOid: row.oid,
    adoptionJson: blob,
  };
}

/**
 * Independent verification of an installed adoption. See the module comment
 * for the full check list and the custody/drift/jj reporting split.
 */
export async function verifyAdoption(
  input: VerifyInput,
  execution: StageExecution = {},
): Promise<Verification> {
  const { signal } = execution;
  signal?.throwIfAborted();
  const soft = (args: readonly string[], cwd: string) => softGit(args, cwd, signal);
  const hard = (args: readonly string[], cwd: string, step: string) =>
    hardGit(args, cwd, step, signal);
  const failures: Issue[] = [];
  const retirement: Issue[] = [];
  const fail = (code: string, subject: string | null, reason: string): void => {
    failures.push({ code, subject, reason });
  };

  const ref = refName(input.receiptRef);
  const destReal = await realpath(input.dest).catch(() => {
    throw new CustodyError(
      "invalid-input",
      `destination does not exist: ${input.dest}`,
      input.dest,
    );
  });
  const gitDir = utf8Fatal(
    await hard(["rev-parse", "--absolute-git-dir"], destReal, "destination discovery"),
  ).trim();
  const formatText = utf8Fatal(
    await hard(["rev-parse", "--show-object-format"], destReal, "destination object format probe"),
  ).trim();
  if (formatText !== "sha1" && formatText !== "sha256")
    throw new CustodyError(
      "unsupported-repository",
      `destination object format is not sha1/sha256: ${formatText}`,
      destReal,
    );
  const destFormat: GitObjectFormat = formatText;

  // --- phase 1: the receipt ref itself -------------------------------------
  const row = await exactRefRow(destReal, ref, destFormat, signal);
  if (row === null)
    throw new CustodyError(
      "verification-failed",
      `receipt ref does not exist in the destination: ${ref}`,
      ref,
    );
  const receiptCommitOid = row.oid;
  let receipt: ReceiptV1 | null = null;
  if (row.objectType !== "commit") {
    fail(
      "receipt-not-commit",
      ref,
      `receipt ref points at a ${row.objectType}, not the metadata commit`,
    );
  } else {
    const blob = await soft(["cat-file", "blob", `${receiptCommitOid}:adoption.json`], destReal);
    if (blob === null) {
      fail("receipt-blob-missing", ref, "receipt commit carries no adoption.json blob");
    } else {
      try {
        const parsed = parseReceipt(blob);
        // A receipt read from one ref must be the receipt it claims to be.
        if (parsed.receiptRef !== ref)
          fail(
            "receipt-ref-mismatch",
            ref,
            `receipt names ${parsed.receiptRef}; it was read from ${ref}`,
          );
        // Self-reference: the observed metadata commit OID must not appear in
        // its own JSON — a tampered or self-naming receipt is not canonical.
        if (utf8Fatal(blob).includes(receiptCommitOid))
          fail("receipt-self-reference", ref, "adoption.json embeds its own metadata commit OID");
        receipt = parsed;
      } catch (error) {
        signal?.throwIfAborted();
        fail("receipt-invalid", ref, error instanceof Error ? error.message : String(error));
      }
    }
  }

  // --- phase 2: metadata commit shape ---------------------------------------
  if (receipt !== null) {
    const parentsBytes = await soft(
      ["rev-list", "--parents", "-n", "1", receiptCommitOid],
      destReal,
    );
    if (parentsBytes === null)
      fail("receipt-commit-shape", ref, "receipt metadata commit is unreadable");
    else if (utf8Fatal(parentsBytes).trim().split(" ").length > 1)
      fail("receipt-commit-shape", ref, "receipt metadata commit has parents");
    const treeRows = await soft(["ls-tree", "-z", `${receiptCommitOid}^{tree}`], destReal);
    let sole = false;
    if (treeRows === null) {
      fail("receipt-commit-shape", ref, "receipt metadata commit tree is unreadable");
    } else {
      const entries = utf8Fatal(treeRows)
        .split("\0")
        .filter((line) => line !== "");
      sole =
        entries.length === 1 && /^100644 blob [0-9a-f]{40,64}\tadoption\.json$/.test(entries[0]!);
      if (!sole)
        fail(
          "receipt-commit-shape",
          ref,
          "receipt metadata commit tree must hold exactly one adoption.json blob",
        );
    }
    if (receipt.source.objectFormat !== destFormat)
      fail(
        "object-format-mismatch",
        destReal,
        `receipt records ${receipt.source.objectFormat}; destination is ${destFormat}`,
      );
    for (const pin of receipt.pins) {
      const expected = pinRef(
        pin,
        receipt.identity.label,
        receipt.identity.generation,
        receipt.snapshot,
      );
      if (pin.destinationRef !== expected)
        fail(
          "pin-mapping",
          pin.destinationRef,
          "recomputed destination lane differs from the recorded pin",
        );
    }
  }

  // --- phase 3: destination refs and objects behind every pin --------------
  if (receipt !== null) {
    const alternates = await readFile(join(gitDir, "objects", "info", "alternates")).catch(
      () => null,
    );
    if (alternates !== null && alternates.length > 0)
      fail(
        "destination-alternates",
        destReal,
        "destination object store uses alternates; custody objects may live elsewhere",
      );
    const listing = await soft(["for-each-ref", REF_FORMAT], destReal);
    let observed: ReadonlyMap<string, RefRow> | null = null;
    try {
      observed =
        listing === null
          ? null
          : new Map(parseRefRows(listing, destFormat).map((r) => [r.name, r]));
    } catch {
      observed = null;
    }
    if (observed === null) {
      fail("destination-refs-unreadable", destReal, "destination ref listing is unreadable");
    } else {
      for (const pin of receipt.pins) {
        const actual = observed.get(pin.destinationRef);
        if (actual === undefined) {
          fail("pin-ref-missing", pin.destinationRef, "custody pin ref is absent");
          continue;
        }
        if (actual.oid !== pin.destinationOid)
          fail(
            "pin-oid-mismatch",
            pin.destinationRef,
            `pin ref holds ${actual.oid}; receipt expects ${pin.destinationOid}`,
          );
        if (actual.objectType !== pin.objectType)
          fail(
            "pin-type-mismatch",
            pin.destinationRef,
            `pin ref holds a ${actual.objectType}; receipt expects ${pin.objectType}`,
          );
        if (actual.oid !== pin.destinationOid || actual.objectType !== pin.objectType) continue;
        // Object-level evidence inside the destination store itself.
        const type = await soft(["cat-file", "-t", pin.destinationOid], destReal);
        if (type === null || utf8Fatal(type).trim() !== pin.objectType)
          fail(
            "pin-object-missing",
            pin.destinationRef,
            "pinned object is missing from the destination store",
          );
        if (pin.objectType === "tag") {
          const peeled = await soft(["rev-parse", `${pin.destinationOid}^{commit}`], destReal);
          if (peeled === null)
            fail("pin-object-missing", pin.destinationRef, "annotated tag target is missing");
        }
        if (pin.objectType === "commit") {
          const closure = await soft(["rev-list", "--objects", pin.destinationOid], destReal);
          if (closure === null)
            fail(
              "pin-closure",
              pin.destinationRef,
              "reachable closure does not walk inside the destination object store",
            );
        }
      }
    }
    // Full HEAD tree manifest, recomputed from the destination store: exact
    // tree OID plus every path/mode/blob the receipt recorded.
    const head = receipt.source.head;
    const headTree = await soft(["rev-parse", `${head.oid}^{tree}`], destReal);
    if (headTree === null || utf8Fatal(headTree).trim() !== head.treeOid) {
      fail("tree-oid-mismatch", head.oid, "HEAD commit does not carry the recorded tree");
    } else {
      const headListing = await soft(["ls-tree", "-r", "-z", head.treeOid], destReal);
      if (headListing === null)
        fail("manifest-mismatch", head.treeOid, "HEAD tree is unreadable in the destination");
      else if (
        canonicalJson(parseManifest(headListing, destFormat)) !== canonicalJson(head.treePaths)
      )
        fail("manifest-mismatch", head.treeOid, "HEAD tree manifest differs from the receipt");
    }
    // The snapshot tree gets the same destination-side exactness; the bundle
    // side re-proves it inside the fresh restore.
    const snapshot = receipt.snapshot;
    if (snapshot !== null) {
      const tree = await soft(["rev-parse", `${snapshot.commitOid}^{tree}`], destReal);
      if (tree === null || utf8Fatal(tree).trim() !== snapshot.treeOid) {
        fail(
          "tree-oid-mismatch",
          snapshot.commitOid,
          "snapshot commit does not carry the recorded tree",
        );
      } else {
        const snapshotListing = await soft(["ls-tree", "-r", "-z", snapshot.treeOid], destReal);
        if (snapshotListing === null)
          fail(
            "manifest-mismatch",
            snapshot.treeOid,
            "snapshot tree is unreadable in the destination",
          );
        else if (
          canonicalJson(parseManifest(snapshotListing, destFormat)) !==
          canonicalJson(snapshot.paths)
        )
          fail("manifest-mismatch", snapshot.treeOid, "snapshot manifest differs from the receipt");
      }
    }
  }

  // --- phase 4: vault bundle + fresh-repository restore proof ---------------
  if (receipt !== null) {
    // A genuinely absent bundle file is a different custody failure from a
    // redirected or wholly missing vault; the typed component error carries
    // that distinction from the resolver.
    let bundleBytes: Uint8Array | null = null;
    try {
      const bundle = await readVaultBundle(receipt, destReal);
      bundleBytes = bundle.bytes;
    } catch (error) {
      signal?.throwIfAborted();
      const detail = error instanceof Error ? error.message : String(error);
      if (error instanceof VaultPathComponentError && error.component === "bundle" && error.missing)
        fail("bundle-unreadable", error.subject, detail);
      else
        fail(
          "vault-path-invalid",
          error instanceof CustodyError
            ? error.subject
            : receipt.bundle.pathRelativeToDestinationParent,
          detail,
        );
    }
    if (bundleBytes === null) {
      // The anchored resolver already classified missing/unsafe bundle reads.
    } else {
      const observed = sha256(bundleBytes);
      if (observed !== receipt.bundle.sha256)
        fail(
          "bundle-checksum",
          receipt.bundle.pathRelativeToDestinationParent,
          `bundle hashes to ${observed}; receipt records ${receipt.bundle.sha256}`,
        );
      // Restore the very bytes read from anchored vault descriptors. Passing
      // the vault pathname back to Git would reopen a replaceable component
      // after its ownership/checksum check (a path-swap race). The copy lives
      // only in private scratch and never touches destination or legacy.
      let proofScratch: string | null = null;
      try {
        signal?.throwIfAborted();
        proofScratch = await mkdtemp(join(input.scratchRoot, "verify-bundle-"));
        const proofBundle = join(proofScratch, "source.bundle");
        signal?.throwIfAborted();
        await writeFile(proofBundle, bundleBytes, { mode: 0o600 });
        signal?.throwIfAborted();
        // The shared restoration proof checks heads, prerequisites, complete
        // fetch, pin closure and the snapshot manifest in a fresh repository.
        const check = await checkBundleRestoration(
          {
            bundlePath: proofBundle,
            objectFormat: receipt.source.objectFormat,
            scratchRoot: input.scratchRoot,
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
          execution,
        );
        // The proof hands back its disposable restore repository; nothing of
        // it may outlive verification.
        await rm(dirname(check.restoreRepoPath), { recursive: true, force: true });
      } catch (error) {
        signal?.throwIfAborted();
        fail(
          "bundle-restore",
          error instanceof CustodyError ? error.subject : null,
          error instanceof Error ? error.message : String(error),
        );
      } finally {
        if (proofScratch !== null) await rm(proofScratch, { recursive: true, force: true });
      }
    }
  }

  // --- phase 5: jj health (additional evidence, never custody) -------------
  const jjDirectory = await stat(join(destReal, ".jj")).catch(() => null);
  if (jjDirectory === null || !jjDirectory.isDirectory()) {
    retirement.push({
      code: "jj-preflight-unavailable",
      subject: destReal,
      reason: "destination has no .jj store; jj visibility of custody refs is unproven",
    });
  } else {
    try {
      const conflicts = await preflight(destReal, { readOnly: true }, execution);
      if (conflicts.length > 0)
        retirement.push({
          code: "jj-bookmark-conflict",
          subject: conflicts.join(", "),
          reason:
            "conflicted visible bookmarks need repair before retirement; custody refs and objects are checked independently above",
        });
    } catch (error) {
      signal?.throwIfAborted();
      retirement.push({
        code: "jj-preflight-failed",
        subject: destReal,
        reason: error instanceof Error ? error.message : String(error),
      });
    }
  }

  // A later operator may have configured a clean filter since adoption.
  // Git status can execute it, even with read-only Git environment flags.
  // Use inventory's config-only admission check before optional drift status;
  // custody evidence remains independent when drift cannot be observed safely.
  let safeDestinationStatus = receipt !== null;
  if (receipt !== null) {
    let reason: string | null = null;
    try {
      const helpers = await Effect.runPromise(localHelpers(destReal), { signal });
      signal?.throwIfAborted();
      if (helpers.length > 0)
        reason = `repository-local executable helpers are configured: ${helpers.join(", ")}`;
    } catch (error) {
      signal?.throwIfAborted();
      reason = `repository-local helper config cannot be inspected: ${error instanceof Error ? error.message : String(error)}`;
    }
    if (reason !== null) {
      safeDestinationStatus = false;
      retirement.push({ code: "destination-drift-unavailable", subject: destReal, reason });
    }
  }

  const verification: Verification = {
    receiptRef: ref,
    receiptCommitOid,
    custodyVerified: failures.length === 0,
    custodyFailures: failures,
    sourceDrift: await sourceDriftOf(input, receipt, signal).catch(() => {
      signal?.throwIfAborted();
      return "unknown";
    }),
    destinationDrift: await destinationDriftOf(
      receipt,
      destReal,
      gitDir,
      ref,
      receiptCommitOid,
      safeDestinationStatus,
      signal,
    ).catch(() => {
      signal?.throwIfAborted();
      return "unknown";
    }),
    retirementUnresolved: [...(receipt?.unresolved ?? []), ...retirement],
  };
  signal?.throwIfAborted();
  return verification;
}

/**
 * Subsequent destination drift, reported separately from historical custody:
 * the pre-import protected refs must still exist at their recorded OIDs, the
 * only new refs must be this receipt's custody refs, and the worktree/index
 * fingerprints must match the recorded baseline. Any unreadable category
 * yields `"unknown"`; this never flips `custodyVerified`.
 */
const destinationDriftOf = async (
  receipt: ReceiptV1 | null,
  destReal: string,
  gitDir: string,
  ref: RefName,
  receiptCommitOid: Oid,
  safeStatus: boolean,
  signal?: AbortSignal,
): Promise<Verification["destinationDrift"]> => {
  if (!safeStatus) return "unknown";
  const soft = (args: readonly string[], cwd: string) => softGit(args, cwd, signal);
  if (receipt === null) return "unknown";
  let changed = false;
  let unknown = false;
  const expected = new Map<string, string>();
  for (const tip of receipt.baselines.destinationPreRefs) expected.set(tip.name, tip.oid);
  expected.set(ref, receiptCommitOid);
  for (const pin of receipt.pins) expected.set(pin.destinationRef, pin.destinationOid);
  const listing = await soft(["for-each-ref", REF_FORMAT], destReal);
  if (listing === null) {
    unknown = true;
  } else {
    const observed = new Map<string, string>();
    for (const row of parseRefRows(listing, receipt.source.objectFormat))
      observed.set(row.name, row.oid);
    for (const [name, oid] of expected) if (observed.get(name) !== oid) changed = true;
    for (const name of observed.keys()) if (!expected.has(name)) changed = true;
  }
  const status = await soft(["status", "--porcelain=v2", "-z", "--untracked-files=all"], destReal);
  if (status === null) unknown = true;
  else if (sha256(status) !== receipt.baselines.destinationWorktreeFingerprintSha256)
    changed = true;
  const index = await readFile(join(gitDir, "index")).catch(() => null);
  if (index === null) unknown = true;
  else if (sha256(index) !== receipt.baselines.destinationIndexSha256) changed = true;
  return changed ? "changed" : unknown ? "unknown" : "unchanged";
};

/**
 * Optional legacy diagnostics: compare the surviving legacy checkout's HEAD,
 * full ref map, index digest, `.jj` presence, and the content of every path
 * in the recorded included manifest (literal filesystem paths, hash symlink
 * text rather than its target). Absence, change, or omission
 * never redefines custody that was already proven into the archive.
 */
const sourceDriftOf = async (
  input: VerifyInput,
  receipt: ReceiptV1 | null,
  signal?: AbortSignal,
): Promise<Verification["sourceDrift"]> => {
  const soft = (args: readonly string[], cwd: string) => softGit(args, cwd, signal);
  if (input.legacy === null || receipt === null) return "unknown";
  const real = await realpath(input.legacy).catch(() => null);
  if (real === null) return "absent";
  let changed = false;
  const head = await soft(["rev-parse", "HEAD"], real);
  if (head === null || utf8Fatal(head).trim() !== receipt.source.head.oid) changed = true;
  const format = receipt.source.objectFormat;
  const listing = await soft(["for-each-ref", REF_FORMAT], real);
  if (listing === null) {
    changed = true;
  } else {
    const observed = new Map<string, string>();
    for (const row of parseRefRows(listing, format)) observed.set(row.name, row.oid);
    const recorded = new Map(
      receipt.source.refs.map((tip) => [tip.name as string, tip.oid as string]),
    );
    if (observed.size !== recorded.size) changed = true;
    for (const [name, oid] of recorded) if (observed.get(name) !== oid) changed = true;
  }
  const legacyGitDir = await soft(["rev-parse", "--absolute-git-dir"], real);
  if (legacyGitDir === null) {
    changed = true;
  } else {
    const index = await readFile(join(utf8Fatal(legacyGitDir).trim(), "index")).catch(() => null);
    if (index === null || sha256(index) !== receipt.source.fingerprints.indexSha256) changed = true;
  }
  const jjDirectory = await stat(join(real, ".jj")).catch(() => null);
  const jjRecorded =
    receipt.source.fingerprints.jjStoreSha256 !== null ||
    receipt.source.jjCoverage.classification !== "none";
  if ((jjDirectory !== null && jjDirectory.isDirectory()) !== jjRecorded) changed = true;
  // Worktree content over the recorded included set: the snapshot manifest
  // when one exists, otherwise the clean HEAD tree. Literal per-path reads
  // support newlines and do not use Git's quoted/newline path protocol.
  const manifest = receipt.snapshot?.paths ?? receipt.source.head.treePaths;
  for (const entry of manifest) {
    signal?.throwIfAborted();
    const bytes = await readManifestPath(real, entry, signal);
    signal?.throwIfAborted();
    if (bytes === null || gitBlobOid(bytes, format) !== entry.blobOid) changed = true;
  }
  return changed ? "changed" : "unchanged";
};
