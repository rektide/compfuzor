/**
 * Private bundle vault: sibling-of-destination storage for adoption bundles.
 *
 * The vault lives at `dirname(dest)/.compfuzor-adoptions/<archive-id>/<run-id>/`
 * where `<archive-id>` is the SHA-256 of the canonical destination realpath
 * **at capture** and `<run-id>` is a cryptographic random (128+ bit) identity
 * minted per apply run. Owner-only permissions (`0700` directories, `0600`
 * files), atomic rename installation, and exclusive creation keep the vault
 * private and never overwrite pre-existing artifacts; abandoned runs are left
 * for deliberate diagnosis, never pruned automatically.
 *
 * Two halves: safe *resolution* of a receipt's recorded bundle path under a
 * possibly moved archive (the verifier's read path), and the durable *writer*
 * {@link sealBundle} that apply uses to install a proven bundle and its
 * signed-off intent before any destination ref exists.
 */
import { link, lstat, mkdir, open, readFile, unlink } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { basename, dirname, isAbsolute, join, relative } from "node:path";
import { sha256, vaultBundlePath } from "./codec.ts";
import { CustodyError, invalid } from "./errors.ts";
import type { StageExecution } from "./stage.ts";
import type { BundleHead, ReceiptV1, SealedBundle, Sha256 } from "./model.ts";

export const VAULT_DIRNAME = ".compfuzor-adoptions";
export const BUNDLE_NAME = "source.bundle";
export const INTENT_NAME = "intent.json";

const encoder = new TextEncoder();

/** Archive identity: SHA-256 over the canonical destination realpath bytes. */
export function vaultArchiveId(destRealpath: string): Sha256 {
  return sha256(encoder.encode(destRealpath));
}

export interface VaultAddress {
  readonly archiveId: string;
  readonly runId: string;
}

/**
 * Shape-only parse of a receipt's `pathRelativeToDestinationParent` value.
 * The hash binding to a specific destination is checked by
 * {@link resolveVaultBundle} (via the codec) against the receipt's own
 * recorded capture path, never against the current location.
 */
export function parseVaultRelative(relative: string): VaultAddress {
  const parts = relative.split("/");
  if (
    parts.length !== 4 ||
    parts[0] !== VAULT_DIRNAME ||
    parts[3] !== BUNDLE_NAME ||
    !/^[0-9a-f]{64}$/.test(parts[1]) ||
    !/^[0-9a-f]{32,}$/.test(parts[2])
  )
    invalid("bundle path is outside the private vault");
  return { archiveId: parts[1], runId: parts[2] };
}

/**
 * Which on-disk vault component failed resolution, and whether it was absent
 * (versus present but wrong: symlink, wrong type). Lets the verifier report a
 * genuinely missing bundle file distinctly from a redirected or absent vault.
 */
export class VaultPathComponentError extends CustodyError {
  override readonly name: string = "VaultPathComponentError";

  public readonly component: "root" | "archive" | "run" | "bundle";
  public readonly missing: boolean;

  public constructor(init: {
    component: "root" | "archive" | "run" | "bundle";
    path: string;
    message: string;
    missing: boolean;
  }) {
    super("bundle-invalid", init.message, init.path);
    this.component = init.component;
    this.missing = init.missing;
  }
}

/**
 * The absolute bundle location implied by a receipt under the **current**
 * destination parent — shape- and hash-validated, but without touching the
 * filesystem. Pure addressing, shared by the resolver below.
 */
function vaultBundleTarget(receipt: ReceiptV1, destRealpath: string): string {
  const relative = receipt.bundle.pathRelativeToDestinationParent;
  // Bind the recorded hash to the receipt's recorded capture destination.
  // codec.vaultBundlePath also rejects `..`, absolute, and non-vault shapes.
  vaultBundlePath(receipt.identity.destinationRealpath, relative);
  const { archiveId, runId } = parseVaultRelative(relative);
  return join(dirname(destRealpath), VAULT_DIRNAME, archiveId, runId, BUNDLE_NAME);
}

/**
 * Resolve the sealed bundle for a receipt under the **current** destination,
 * proving every on-disk component is what it claims.
 *
 * Moved-archive contract: the archive-id directory name is the hash of the
 * destination realpath at capture time. Once an archive moves, a new hash
 * cannot be derived for the recorded path and the original absolute path must
 * not be consulted — so the recorded relative path is validated against the
 * receipt's own `identity.destinationRealpath` (proving it was minted for
 * exactly this archive), and then resolved relative to the *current*
 * destination's parent, where the vault must have moved with the archive. A
 * vault that stayed behind, or a clone that never had one, fails distinctly.
 *
 * Every path component is `lstat`d and must be a real directory (and the leaf
 * a real regular file): a symlink anywhere on the vault path is rejected
 * without being followed, so the bundle cannot be redirected outside the
 * vault by swapping a component for a link.
 */
export async function resolveVaultBundle(
  receipt: ReceiptV1,
  destRealpath: string,
): Promise<string> {
  const target = vaultBundleTarget(receipt, destRealpath);
  const { archiveId, runId } = parseVaultRelative(receipt.bundle.pathRelativeToDestinationParent);
  const component = async (
    path: string,
    componentKind: "root" | "archive" | "run" | "bundle",
    what: string,
    expect: "directory" | "file",
  ): Promise<void> => {
    const reject = (message: string, missing: boolean): VaultPathComponentError =>
      new VaultPathComponentError({ component: componentKind, path, message, missing });
    const info = await lstat(path).catch(() => null);
    if (info === null) throw reject(`vault ${what} is missing: ${path}`, true);
    if (info.isSymbolicLink())
      throw reject(
        `vault ${what} is a symlink; refusing to follow it out of the vault: ${path}`,
        false,
      );
    if (expect === "directory" && !info.isDirectory())
      throw reject(`vault ${what} is not a directory: ${path}`, false);
    if (expect === "file" && !info.isFile())
      throw reject(`vault ${what} is not a regular file: ${path}`, false);
  };
  const vault = join(dirname(destRealpath), VAULT_DIRNAME);
  await component(vault, "root", "root", "directory");
  await component(join(vault, archiveId), "archive", "archive directory", "directory");
  await component(join(vault, archiveId, runId), "run", "run directory", "directory");
  await component(target, "bundle", "bundle", "file");
  return target;
}

// ---------------------------------------------------------------------------
// Durable writer (apply's seal path)
// ---------------------------------------------------------------------------

/** A freshly created, exclusively owned vault run directory. */
export interface VaultRun {
  /** The vault root (`<dest parent>/.compfuzor-adoptions`). */
  readonly vaultRoot: string;
  /** This archive's directory (`<vault root>/<archive-id>`). */
  readonly archiveDir: string;
  /** The exclusive run directory (`<archive dir>/<run id>`). */
  readonly runDir: string;
  readonly bundlePath: string;
  readonly intentPath: string;
  readonly runId: string;
}

/** 128 bits of cryptographic randomness, hex-encoded. */
export function vaultRunId(): string {
  return randomBytes(16).toString("hex");
}

const vaultWrite = (message: string, subject: string | null = null): CustodyError =>
  new CustodyError("invalid-input", `vault write refused: ${message}`, subject);

/** fsync a directory (by fd) so a create/rename survives a crash. */
const syncDir = async (dir: string): Promise<void> => {
  const handle = await open(dir, "r");
  try {
    await handle.sync();
  } finally {
    await handle.close();
  }
};

/** mkdir one owner-only level, tolerating an already-correct existing level. */
const mkdirLevel = async (dir: string, what: string, signal?: AbortSignal): Promise<void> => {
  signal?.throwIfAborted();
  const existing = await lstat(dir).catch(() => null);
  signal?.throwIfAborted();
  if (existing !== null) {
    if (!existing.isDirectory() || existing.isSymbolicLink())
      throw vaultWrite(`${what} exists and is not a directory`, dir);
    return;
  }
  try {
    signal?.throwIfAborted();
    await mkdir(dir, { mode: 0o700 });
  } catch (error) {
    signal?.throwIfAborted();
    throw vaultWrite(
      `could not create ${what}: ${error instanceof Error ? error.message : String(error)}`,
      dir,
    );
  }
  await syncDir(dirname(dir));
  signal?.throwIfAborted();
};

/** Containment in either direction (a path component boundary, not prefixes). */
const contains = (parent: string, child: string): boolean => {
  const rel = relative(parent, child);
  return rel === "" || (rel !== ".." && !rel.startsWith("../") && !isAbsolute(rel));
};

/**
 * Create an exclusive, owner-only vault run directory for an apply attempt.
 * `destRealpath` is the canonical destination of *this* run (the archive-id
 * hash is minted from it); an existing run directory is refused — the vault is
 * append-only and never reuses or prunes runs. {@link sealBundle} composes
 * this with the intent/bundle installs; it stays exported for apply's
 * restart-diagnosis writes into an existing run.
 */
export async function createVaultRun(
  destRealpath: string,
  runId: string,
  execution: StageExecution = {},
): Promise<VaultRun> {
  const { signal } = execution;
  signal?.throwIfAborted();
  if (!/^[0-9a-f]{32,}$/.test(runId)) invalid("vault run id must be 128+ bits of hex randomness");
  const vaultRoot = join(dirname(destRealpath), VAULT_DIRNAME);
  const archiveDir = join(vaultRoot, vaultArchiveId(destRealpath));
  const runDir = join(archiveDir, runId);
  const existing = await lstat(runDir).catch(() => null);
  signal?.throwIfAborted();
  if (existing !== null)
    throw vaultWrite("run directory already exists; runs are exclusive and never reused", runDir);
  await mkdirLevel(vaultRoot, "vault root", signal);
  await mkdirLevel(archiveDir, "archive directory", signal);
  try {
    signal?.throwIfAborted();
    await mkdir(runDir, { mode: 0o700 });
  } catch (error) {
    signal?.throwIfAborted();
    throw vaultWrite(
      `could not create the exclusive run directory: ${error instanceof Error ? error.message : String(error)}`,
      runDir,
    );
  }
  await syncDir(archiveDir);
  signal?.throwIfAborted();
  return {
    vaultRoot,
    archiveDir,
    runDir,
    runId,
    bundlePath: join(runDir, BUNDLE_NAME),
    intentPath: join(runDir, INTENT_NAME),
  };
}

/**
 * Durably install a vault file: write to a private `0600` temporary in the
 * same directory, fsync it, then hard-link it onto the final name (`link(2)`
 * is atomic *and* exclusive — unlike `rename(2)` it cannot clobber a racing
 * creator) and fsync the directory. A pre-existing target is refused and no
 * temporary survives a failure path. Exported for apply's diagnosis writes.
 */
export async function sealVaultFile(
  target: string,
  bytes: Uint8Array,
  execution: StageExecution = {},
): Promise<void> {
  const { signal } = execution;
  signal?.throwIfAborted();
  const existing = await lstat(target).catch(() => null);
  signal?.throwIfAborted();
  if (existing !== null)
    throw vaultWrite("target already exists; vault files are never overwritten", target);
  const directory = dirname(target);
  const temp = join(directory, `.${basename(target)}.tmp-${randomBytes(8).toString("hex")}`);
  try {
    signal?.throwIfAborted();
    const handle = await open(temp, "wx", 0o600);
    try {
      signal?.throwIfAborted();
      await handle.writeFile(bytes);
      signal?.throwIfAborted();
      await handle.sync();
    } finally {
      await handle.close();
    }
    signal?.throwIfAborted();
    await link(temp, target);
  } catch (error) {
    await unlink(temp).catch(() => {});
    signal?.throwIfAborted();
    if (error instanceof CustodyError) throw error;
    throw vaultWrite(
      `could not install ${basename(target)}: ${error instanceof Error ? error.message : String(error)}`,
      target,
    );
  }
  await unlink(temp).catch(() => {});
  await syncDir(directory);
  signal?.throwIfAborted();
}

/** The proven bundle facts apply passes in (satisfied by stage's ProvenBundle). */
export interface ProvenBundleFacts {
  /** Private path of the proven bundle (scratch); never the source ODB. */
  readonly bundlePath: string;
  readonly bundleSha256: Sha256;
  readonly verifiedHeads: readonly BundleHead[];
  readonly freshRestoreVerified: true;
}

/** Everything {@link sealBundle} needs from an apply attempt. */
export interface SealBundleOptions {
  /** Canonical destination realpath of this run; defines the archive id. */
  readonly destRealpath: string;
  /** Canonical legacy source root; the vault must live outside it as well. */
  readonly legacyRealpath: string;
  /** The proven bundle from custody/stage.ts (private, checksummed, exact heads). */
  readonly proven: ProvenBundleFacts;
  /** Signed-off plan intent bytes, stored beside the bundle for restart diagnosis. */
  readonly intent: Uint8Array;
}

/** A sealed vault run: the receipt-ready record plus where everything lives. */
export interface SealedVaultRun {
  readonly run: VaultRun;
  /** Receipt-shaped bundle record: constrained relative path, checksum, heads. */
  readonly sealed: SealedBundle;
}

/**
 * Durally seal a proven adoption bundle and its signed-off intent into a new,
 * exclusive, owner-only vault run beside the destination.
 *
 * Ordering contract for apply: the intent is installed first and the bundle
 * second, both before any destination ref exists; the receipt is constructed
 * only afterwards from the returned checksum (so it can never cyclically
 * contain its own bundle hash). The vault root must lie outside both the
 * destination and the legacy checkout; a run is never reused or overwritten,
 * and abandoned attempts are left for diagnosis.
 */
export async function sealBundle(
  options: SealBundleOptions,
  execution: StageExecution = {},
): Promise<SealedVaultRun> {
  const { signal } = execution;
  signal?.throwIfAborted();
  const { destRealpath, legacyRealpath, proven, intent } = options;
  const vaultRoot = join(dirname(destRealpath), VAULT_DIRNAME);
  if (contains(destRealpath, vaultRoot) || contains(vaultRoot, destRealpath))
    invalid("vault must be a sibling of the destination, never inside or around it");
  if (contains(legacyRealpath, vaultRoot))
    throw vaultWrite("vault would live inside the legacy checkout", vaultRoot);
  if (contains(vaultRoot, legacyRealpath))
    throw vaultWrite("legacy checkout would live inside the vault", legacyRealpath);
  const bundleBytes = await readFile(proven.bundlePath).catch(() => {
    signal?.throwIfAborted();
    throw vaultWrite("proven bundle is not readable", proven.bundlePath);
  });
  signal?.throwIfAborted();
  const observed = sha256(bundleBytes);
  if (observed !== proven.bundleSha256)
    throw vaultWrite(
      `proven bundle changed underfoot: hashes to ${observed}, promised ${proven.bundleSha256}`,
      proven.bundlePath,
    );
  const run = await createVaultRun(destRealpath, vaultRunId(), execution);
  // Intent first: a crash between the two writes leaves a diagnosable intent,
  // not an unexplained bundle.
  await sealVaultFile(run.intentPath, intent, execution);
  await sealVaultFile(run.bundlePath, bundleBytes, execution);
  const sealed: SealedBundle = {
    pathRelativeToDestinationParent: join(
      VAULT_DIRNAME,
      vaultArchiveId(destRealpath),
      run.runId,
      BUNDLE_NAME,
    ),
    sha256: proven.bundleSha256,
    verifiedHeads: proven.verifiedHeads,
    freshRestoreVerified: true,
  };
  signal?.throwIfAborted();
  return { run, sealed };
}
