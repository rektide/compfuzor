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
 * This module currently owns safe *resolution* of a receipt's recorded bundle
 * path under a possibly moved archive — the read half the independent
 * verifier depends on. The durable writer (apply's seal/install half) is a
 * separate implementation stage.
 */
import { lstat } from "node:fs/promises";
import { dirname, join } from "node:path";
import { sha256, vaultBundlePath } from "./codec.ts";
import { CustodyError, invalid } from "./errors.ts";
import type { ReceiptV1, Sha256 } from "./model.ts";

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
