import { createHash } from "node:crypto";
import { dirname, resolve } from "node:path";
import { isDeepStrictEqual } from "node:util";
import { invalid } from "./errors.ts";
import type {
  GitObjectFormat,
  Oid,
  RefName,
  RepoPath,
  Sha256,
  PinIntent,
  ReceiptV1,
  PathReview,
} from "./model.ts";

const enc = new TextEncoder();
const dec = new TextDecoder("utf-8", { fatal: true });

export function sha256(bytes: Uint8Array): Sha256 {
  return createHash("sha256").update(bytes).digest("hex") as Sha256;
}
export function oid(value: string, format: GitObjectFormat): Oid {
  if (!new RegExp(`^[0-9a-f]{${format === "sha1" ? 40 : 64}}$`).test(value))
    invalid(`invalid ${format} object ID`);
  return value as Oid;
}
export function digest(value: string): Sha256 {
  if (!/^[0-9a-f]{64}$/.test(value)) invalid("invalid SHA-256 digest");
  return value as Sha256;
}
function text(bytes: Uint8Array): string {
  let decoded: string;
  try {
    decoded = dec.decode(bytes);
  } catch {
    return invalid("Git name is not lossless UTF-8");
  }
  if (!Buffer.from(enc.encode(decoded)).equals(Buffer.from(bytes)))
    invalid("Git name cannot round-trip UTF-8");
  return decoded;
}
export function repoPath(value: string | Uint8Array): RepoPath {
  const path = typeof value === "string" ? value : text(value);
  if (
    !path ||
    path.startsWith("/") ||
    path.includes("\0") ||
    path.split("/").some((part) => part === "" || part === "." || part === "..")
  )
    invalid("invalid repository path");
  if (typeof value === "string" && text(enc.encode(value)) !== value) invalid("invalid UTF-8 path");
  return path as RepoPath;
}
/** Git ref component rules plus refusal to normalize operator input. */
export function refComponent(value: string): string {
  if (
    !value ||
    value === "." ||
    value === ".." ||
    value.endsWith(".lock") ||
    value.startsWith(".") ||
    value.endsWith(".") ||
    value.includes("..") ||
    value.includes("@{") ||
    Array.from(value).some(
      (char) =>
        char.charCodeAt(0) <= 32 || char.charCodeAt(0) === 127 || "~^:?*[]\\/".includes(char),
    )
  )
    invalid(`invalid Git ref component ${JSON.stringify(value)}`);
  if (text(enc.encode(value)) !== value) invalid("invalid UTF-8 ref component");
  return value;
}
export function refName(value: string | Uint8Array): RefName {
  const name = typeof value === "string" ? value : text(value);
  if (!name.startsWith("refs/") || enc.encode(name).length > 4096) invalid("invalid full Git ref");
  for (const component of name.split("/")) refComponent(component);
  return name as RefName;
}

/** Fixed-size hex components; length prefix disambiguates concatenations and empty bytes. */
export function encodeIdentity(value: string): string {
  const data = enc.encode(value);
  if (text(data) !== value || data.length > 1024) invalid("identity is not encodable as a Git ref");
  const hex = Buffer.from(data).toString("hex");
  return [
    `b${data.length.toString(16).padStart(8, "0")}`,
    ...(hex.match(/.{1,64}/g) ?? ["00"]),
  ].join("/");
}
export function decodeIdentity(value: string): string {
  const [length, ...parts] = value.split("/");
  if (
    !/^b[0-9a-f]{8}$/.test(length) ||
    !parts.length ||
    parts.some((part) => !/^[0-9a-f]+$/.test(part) || part.length > 64 || part.length % 2)
  )
    invalid("invalid encoded identity");
  const hex = parts.join("");
  const size = Number.parseInt(length.slice(1), 16);
  if (hex.length !== size * 2) {
    if (size === 0 && parts.length === 1 && parts[0] === "00") return "";
    invalid("encoded identity length mismatch");
  }
  const decoded = text(Buffer.from(hex, "hex"));
  if (encodeIdentity(decoded) !== value) invalid("noncanonical encoded identity");
  return decoded;
}

export function receiptRef(label: string, generation: string): RefName {
  refComponent(label);
  refComponent(generation);
  return refName(`refs/adopt/receipts/${label}/${generation}`);
}
/** A candidate sourceName is a stable kind+OID identity, not a reflog index. */
export function candidateIdentity(kind: "stash-older" | "reflog" | "dangling", id: Oid): string {
  return `${kind}:${id}`;
}
/** Lexical checks only: vault opener must also lstat every component and reject symlinks. */
export function vaultBundlePath(destRealpath: string, relative: string): string {
  const root = dirname(destRealpath);
  const archive = sha256(enc.encode(destRealpath));
  const parts = relative.split("/");
  if (
    parts.length !== 4 ||
    parts[0] !== ".compfuzor-adoptions" ||
    parts[1] !== archive ||
    !/^[0-9a-f]{32,}$/.test(parts[2]) ||
    parts[3] !== "source.bundle"
  )
    invalid("bundle path is outside the private vault");
  const full = resolve(root, ...parts);
  if (!full.startsWith(`${resolve(root, ".compfuzor-adoptions", archive)}/`))
    invalid("bundle vault path escape");
  return full;
}
export function pinRef(
  pin: Pick<PinIntent, "sourceKind" | "sourceName" | "sourceOid" | "destinationOid">,
  label: string,
  generation: string,
  snapshot?: { parentOid: Oid; treeOid: Oid } | null,
): RefName {
  refComponent(label);
  refComponent(generation);
  const root = `${label}/${generation}`;
  const { sourceKind: kind, sourceName: name, sourceOid } = pin;
  let full: string;
  if (kind === "branch") {
    if (!name.startsWith("refs/heads/")) invalid("branch pin requires full original branch ref");
    refName(name);
    full = `refs/heads/harvest/${root}/branch/${encodeIdentity(name.slice(11))}`;
  } else if (kind === "tag") {
    if (!name.startsWith("refs/tags/")) invalid("tag pin requires full original tag ref");
    refName(name);
    full = `refs/tags/harvest/${root}/${encodeIdentity(name.slice(10))}`;
  } else if (kind === "head") {
    if (name !== "HEAD") invalid("HEAD pin must identify HEAD");
    full = `refs/heads/harvest/${root}/head/${sourceOid}`;
  } else if (kind === "working-copy") {
    if (!snapshot || name !== "working-copy" || sourceOid !== pin.destinationOid)
      invalid("invalid worktree pin");
    full = `refs/heads/harvest/${root}/working-copy/${snapshot.parentOid}-${snapshot.treeOid}-worktree-v1`;
  } else {
    if (kind === "reflog") {
      if (!/^(stash-older|reflog|dangling):[0-9a-f]{40}([0-9a-f]{24})?$/.test(name))
        invalid("invalid stable candidate identity");
    } else refName(name);
    full = `refs/adopt/custody/${root}/${kind}/${encodeIdentity(name)}`;
  }
  return refName(full);
}

function record(
  value: unknown,
  fields: Record<string, Validator>,
  at: string,
): Record<string, unknown> {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    Object.getPrototypeOf(value) !== Object.prototype
  )
    invalid(`${at} must be a plain object`);
  const object = value as Record<string, unknown>;
  if (!isDeepStrictEqual(Object.keys(object).sort(), Object.keys(fields).sort()))
    invalid(`${at} has missing or unknown fields`);
  for (const [name, check] of Object.entries(fields)) check(object[name], `${at}.${name}`);
  return object;
}
type Validator = (value: unknown, at: string) => void;
const str: Validator = (value, at) => {
  if (typeof value !== "string") invalid(`${at} must be a string`);
};
const nonempty: Validator = (value, at) => {
  str(value, at);
  if (!(value as string).trim()) invalid(`${at} must be nonempty`);
};
const nul =
  (check: Validator): Validator =>
  (value, at) => {
    if (value !== null) check(value, at);
  };
const lit =
  (expected: string | boolean): Validator =>
  (value, at) => {
    if (value !== expected) invalid(`${at} must be ${JSON.stringify(expected)}`);
  };
const one =
  (...values: readonly (string | number)[]): Validator =>
  (value, at) => {
    if (!values.includes(value as string | number)) invalid(`${at} has invalid value`);
  };
const arr =
  (check: Validator): Validator =>
  (value, at) => {
    if (!Array.isArray(value)) invalid(`${at} must be an array`);
    value.forEach((item: unknown, index: number) => check(item, `${at}[${index}]`));
  };
const shape =
  (fields: Record<string, Validator>): Validator =>
  (value, at) => {
    record(value, fields, at);
  };
const hash: Validator = (value, at) => {
  str(value, at);
  digest(value as string);
};
const path: Validator = (value, at) => {
  str(value, at);
  repoPath(value as string);
};
const ref: Validator = (value, at) => {
  str(value, at);
  refName(value as string);
};
const mode = one("100644", "100755", "120000", "160000");
const changeStatus = one(
  "unchanged",
  "added",
  "modified",
  "deleted",
  "renamed",
  "copied",
  "typechanged",
  "unmerged",
);
const gitOid =
  (format: GitObjectFormat): Validator =>
  (value, at) => {
    str(value, at);
    oid(value as string, format);
  };
const count: Validator = (value, at) => {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0)
    invalid(`${at} must be a nonnegative count`);
};
const issue = shape({ code: nonempty, subject: nul(str), reason: nonempty });
const pathEntry = (id: Validator) => shape({ path, mode, blobOid: id });

function reviewSchema(id: Validator): Validator {
  return shape({
    schema: lit("compfuzor.archive-path-review/v1"),
    manifestSha256: hash,
    fileSha256: hash,
    included: arr(
      shape({
        path,
        mode,
        blobOid: id,
        classification: one("credential", "runtime-state", "other-sensitive"),
        decision: lit("local-custody-approved"),
        reason: nonempty,
      }),
    ),
    stagedVsUnstaged: nul(shape({ decision: lit("single-tree-approved"), reason: nonempty })),
  });
}
export function parsePathReview(bytes: Uint8Array, format: GitObjectFormat): PathReview {
  let value: unknown;
  try {
    value = JSON.parse(text(bytes));
  } catch {
    return invalid("invalid path review JSON");
  }
  if (value === null || typeof value !== "object" || Array.isArray(value))
    invalid("path review must be an object");
  const review = value as Record<string, unknown>;
  // The input cannot contain its own SHA-256 without a circular dependency.
  reviewSchema(gitOid(format))({ ...review, fileSha256: sha256(bytes) }, "pathReview");
  if (Object.hasOwn(review, "fileSha256"))
    invalid("path review input cannot contain its own file hash");
  return { ...review, fileSha256: sha256(bytes) } as unknown as PathReview;
}

/** Sorted object keys, stable array order, no undefined/NaN/duplicate keys or prototype tricks. */
export function canonicalJson(value: unknown): string {
  if (value === null || typeof value === "string" || typeof value === "boolean")
    return JSON.stringify(value);
  if (typeof value === "number" && Number.isSafeInteger(value)) return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (typeof value !== "object" || Object.getPrototypeOf(value) !== Object.prototype)
    invalid("non-JSON canonical value");
  const entries = Object.entries(value as Record<string, unknown>).sort(([a], [b]) =>
    a < b ? -1 : a > b ? 1 : 0,
  );
  return `{${entries.map(([key, field]) => `${JSON.stringify(key)}:${canonicalJson(field)}`).join(",")}}`;
}

/** The exact bytes of inventory's for-each-ref --format output, in Git refname order. */
export function destinationRefsSha256(
  refs: readonly { name: RefName; oid: Oid; objectType: string; peeledOid: Oid | null }[],
): Sha256 {
  const ordered = [...refs].sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  return sha256(
    enc.encode(
      ordered
        .map(
          ({ name, oid: target, objectType, peeledOid }) =>
            `${name}\0${target}\0${objectType}\0${peeledOid ?? ""}\0\n`,
        )
        .join(""),
    ),
  );
}

export function validateReceipt(value: unknown): ReceiptV1 {
  if (!value || typeof value !== "object" || Array.isArray(value))
    invalid("receipt must be an object");
  const raw = value as Record<string, unknown>;
  const source = raw.source as Record<string, unknown>;
  const format = source?.objectFormat;
  if (format !== "sha1" && format !== "sha256") invalid("unknown receipt Git object format");
  const id = gitOid(format);
  const tip = shape({
    name: ref,
    oid: id,
    objectType: one("commit", "tag", "tree", "blob"),
    peeledOid: nul(id),
  });
  const candidate = shape({
    kind: one("stash-older", "reflog", "dangling"),
    oid: id,
    objectType: one("commit", "tag", "tree", "blob"),
    provenance: arr(str),
    disposition: one("pin", "not-required", "unclassified"),
    reason: nul(nonempty),
  });
  const identity = shape({
    label: nonempty,
    generation: nonempty,
    legacyRealpathAtCapture: nonempty,
    sourceGitCommonDir: nonempty,
    destinationRealpath: nonempty,
    createdAt: nonempty,
  });
  const snapshot = shape({
    format: lit("worktree-v1"),
    parentOid: id,
    treeOid: id,
    commitOid: id,
    paths: arr(pathEntry(id)),
    stagedVsUnstaged: one("none", "reported-not-preserved"),
    excludeFileSha256: nul(hash),
    excludedUntracked: arr(path),
    ignoredPaths: arr(path),
    trackedSensitivePaths: arr(path),
    pathReview: nul(reviewSchema(id)),
  });
  record(
    value,
    {
      schema: lit("compfuzor.archive-adoption/v1"),
      receiptRef: ref,
      identity,
      source: shape({
        objectFormat: lit(format),
        sourceGitCommonDir: nonempty,
        head: shape({ symbolicRef: nul(ref), oid: id, treeOid: id, treePaths: arr(pathEntry(id)) }),
        refs: arr(tip),
        candidates: arr(candidate),
        remotes: arr(shape({ name: nonempty, url: nonempty })),
        indexEntries: arr(shape({ path, stage: one(0, 1, 2, 3), mode, blobOid: id })),
        worktreeChanges: arr(
          shape({
            path,
            originalPath: nul(path),
            indexStatus: changeStatus,
            worktreeStatus: changeStatus,
          }),
        ),
        untrackedPaths: arr(path),
        ignoredPaths: arr(path),
        excludedUntracked: arr(path),
        trackedSensitivePaths: arr(issue),
        leftBehind: arr(issue),
        jjCoverage: shape({
          classification: one("none", "git-covered", "blocked"),
          headOids: arr(id),
          operationId: nul(str),
        }),
        fingerprints: shape({
          indexSha256: hash,
          gitConfigSha256: hash,
          refsSha256: hash,
          reflogsSha256: hash,
          odbListingSha256: hash,
          includedWorktreeSha256: hash,
          jjStoreSha256: nul(hash),
          canonicalInputsSha256: hash,
        }),
        excludeFileSha256: nul(hash),
        dispositionsFileSha256: nul(hash),
      }),
      snapshot: nul(snapshot),
      cleanHeadPathReview: nul(reviewSchema(id)),
      baselines: shape({
        sourceRemoteTracking: arr(
          shape({ remote: nonempty, url: nonempty, ref, oid: id, freshness: lit("local-only") }),
        ),
        destinationPreRefs: arr(tip),
        destinationPreRefsSha256: hash,
        destinationWorktreeFingerprintSha256: hash,
        destinationIndexSha256: hash,
        selectedBranch: nonempty,
        declaredRepo: nonempty,
        headNotInRecordedBaseline: nul(count),
        selectedTipsNotInDestination: nul(count),
      }),
      pins: arr(
        shape({
          sourceKind: one("branch", "head", "tag", "stash", "other", "reflog", "working-copy"),
          sourceName: nonempty,
          sourceOid: id,
          objectType: one("commit", "tag", "tree", "blob"),
          destinationRef: ref,
          destinationOid: id,
        }),
      ),
      bundle: shape({
        pathRelativeToDestinationParent: nonempty,
        sha256: hash,
        verifiedHeads: arr(shape({ ref, oid: id })),
        freshRestoreVerified: lit(true),
      }),
      checks: shape({
        sourceFingerprintRechecked: lit(true),
        sourceOdbUnchanged: lit(true),
        destinationWorktreeUnchanged: lit(true),
        bundleClosureVerified: lit(true),
      }),
      unresolved: arr(issue),
    },
    "receipt",
  );
  const receipt = value as ReceiptV1;
  if (receipt.receiptRef !== receiptRef(receipt.identity.label, receipt.identity.generation))
    invalid("receipt identity/ref mismatch");
  vaultBundlePath(
    receipt.identity.destinationRealpath,
    receipt.bundle.pathRelativeToDestinationParent,
  );
  for (const refs of [receipt.source.refs, receipt.baselines.destinationPreRefs]) {
    const seen = new Set<string>();
    for (const { name } of refs) {
      if (seen.has(name)) invalid(`duplicate ref in inventory: ${name}`);
      seen.add(name);
    }
  }
  const candidateNames = new Set<string>();
  for (const candidate of receipt.source.candidates) {
    const name = candidateIdentity(candidate.kind, candidate.oid);
    if (candidateNames.has(name)) invalid(`duplicate candidate identity: ${name}`);
    candidateNames.add(name);
  }
  if (
    receipt.baselines.destinationPreRefsSha256 !==
    destinationRefsSha256(receipt.baselines.destinationPreRefs)
  )
    invalid("destination pre-ref hash differs from inventory");
  const heads = new Map<string, Oid>();
  for (const head of receipt.bundle.verifiedHeads) {
    if (heads.has(head.ref)) invalid("duplicate advertised bundle head");
    heads.set(head.ref, head.oid);
  }
  const names = new Set<string>();
  for (const pin of receipt.pins) {
    if (
      pin.sourceKind === "branch" ||
      pin.sourceKind === "head" ||
      pin.sourceKind === "working-copy"
    ) {
      if (pin.objectType !== "commit") invalid("commit lane has a noncommit object");
    }
    if (pin.sourceKind === "working-copy" && pin.sourceOid !== receipt.snapshot?.commitOid)
      invalid("working-copy commit differs from snapshot");
    if (pin.sourceKind === "head" && pin.sourceOid !== receipt.source.head.oid)
      invalid("HEAD pin differs from source HEAD");
    if (pin.destinationOid !== pin.sourceOid) invalid("pin source/destination OIDs differ");
    if (pin.sourceKind === "reflog") {
      const match = /^(stash-older|reflog|dangling):(.+)$/.exec(pin.sourceName);
      if (!match || oid(match[2], format) !== pin.sourceOid)
        invalid("candidate pin identity differs from source OID");
      const matched = receipt.source.candidates.find(
        (candidate) => candidateIdentity(candidate.kind, candidate.oid) === pin.sourceName,
      );
      if (!matched || matched.disposition !== "pin" || matched.objectType !== pin.objectType)
        invalid("candidate pin lacks selected matching candidate");
    } else if (
      pin.sourceKind !== "head" &&
      pin.sourceKind !== "working-copy" &&
      !receipt.source.refs.some(
        ({ name, oid: id, objectType }) =>
          name === pin.sourceName && id === pin.sourceOid && objectType === pin.objectType,
      )
    ) {
      invalid("named pin lacks matching source ref");
    } else if (pin.sourceKind === "stash" && pin.sourceName !== "refs/stash") {
      invalid("stash pin must name refs/stash");
    } else if (
      pin.sourceKind === "other" &&
      (/^refs\/(heads|tags)\//.test(pin.sourceName) || pin.sourceName === "refs/stash")
    ) {
      invalid("named Git ref must use its dedicated pin lane");
    }
    const computed = pinRef(
      pin,
      receipt.identity.label,
      receipt.identity.generation,
      receipt.snapshot,
    );
    if (pin.destinationRef !== computed || names.has(computed))
      invalid("pin mapping mismatch or duplicate");
    names.add(computed);
  }
  // Stage proves `bundle list-heads` exactly equals its installed pin refs.
  if (
    heads.size !== receipt.pins.length ||
    receipt.pins.some(
      ({ destinationRef, destinationOid }) => heads.get(destinationRef) !== destinationOid,
    )
  )
    invalid("advertised bundle heads do not equal selected pin refs and OIDs");
  for (const tip of receipt.source.refs) {
    const kind =
      tip.name === "refs/stash"
        ? "stash"
        : tip.name.startsWith("refs/heads/")
          ? "branch"
          : tip.name.startsWith("refs/tags/")
            ? "tag"
            : "other";
    if (
      !receipt.pins.some(
        (pin) =>
          pin.sourceKind === kind &&
          pin.sourceName === tip.name &&
          pin.sourceOid === tip.oid &&
          pin.objectType === tip.objectType,
      )
    )
      invalid(`source ref lacks a custody pin: ${tip.name}`);
  }
  for (const candidate of receipt.source.candidates) {
    if (candidate.disposition === "not-required" && !candidate.reason)
      invalid("excluded candidate lacks operator reason");
    if (
      candidate.disposition === "pin" &&
      !receipt.pins.some(
        (pin) =>
          pin.sourceName === candidateIdentity(candidate.kind, candidate.oid) &&
          pin.sourceOid === candidate.oid &&
          pin.objectType === candidate.objectType,
      )
    )
      invalid("selected candidate lacks a custody pin");
  }
  for (const entries of [receipt.source.head.treePaths, receipt.snapshot?.paths ?? []]) {
    const uniquePaths = new Set<string>();
    for (const entry of entries) {
      if (uniquePaths.has(entry.path)) invalid("duplicate path in tree manifest");
      uniquePaths.add(entry.path);
      if (entry.mode === "160000") invalid("submodule gitlink requires separate custody design");
      if (entry.path.split("/").some((part) => part === ".git" || part === ".jj"))
        invalid("tracked Git/jj internals cannot be adopted");
    }
  }
  if (receipt.snapshot !== null && receipt.cleanHeadPathReview !== null)
    invalid("clean HEAD review cannot stand in for a snapshot review");
  if (receipt.snapshot === null) {
    const review = receipt.cleanHeadPathReview;
    const sensitive = receipt.source.trackedSensitivePaths;
    if (sensitive.length && review === null)
      invalid("clean HEAD with tracked sensitive paths lacks local custody review");
    if (review !== null) {
      const manifest = receipt.source.head.treePaths;
      if (review.manifestSha256 !== sha256(enc.encode(`${canonicalJson(manifest)}\n`)))
        invalid("clean HEAD review manifest differs from source HEAD");
      if (review.stagedVsUnstaged !== null)
        invalid("clean HEAD review cannot approve a lost index/worktree split");
      const included = new Set<string>();
      const entries = new Set(
        manifest.map(({ path, mode, blobOid }) => `${path}\0${mode}\0${blobOid}`),
      );
      for (const { path, mode, blobOid } of review.included) {
        const key = `${path}\0${mode}\0${blobOid}`;
        if (!entries.has(key) || included.has(path))
          invalid("clean HEAD review includes stale or repeated file");
        included.add(path);
      }
      for (const { subject } of sensitive) {
        if (subject === null || !included.has(subject))
          invalid("sensitive tracked HEAD path has no exact local custody review");
      }
    }
  }
  if (receipt.snapshot && receipt.snapshot.parentOid !== receipt.source.head.oid)
    invalid("snapshot parent differs from HEAD");
  if (!receipt.pins.some(({ sourceKind }) => sourceKind === "head"))
    invalid("receipt lacks a HEAD pin");
  if (
    receipt.snapshot !== null &&
    !receipt.pins.some(({ sourceKind }) => sourceKind === "working-copy")
  )
    invalid("receipt lacks snapshot pin");
  if (
    receipt.snapshot === null &&
    receipt.pins.some(({ sourceKind }) => sourceKind === "working-copy")
  )
    invalid("clean receipt has working-copy pin");
  if (
    receipt.snapshot?.stagedVsUnstaged === "reported-not-preserved" &&
    !receipt.snapshot.pathReview?.stagedVsUnstaged
  )
    invalid("lost index/worktree split is not reviewed");
  if (receipt.snapshot !== null && receipt.snapshot.pathReview !== null) {
    const snapshot = receipt.snapshot;
    const review = receipt.snapshot.pathReview;
    const manifest = sha256(enc.encode(`${canonicalJson(snapshot.paths)}\n`));
    if (review.manifestSha256 !== manifest) invalid("path review manifest does not match snapshot");
    const entries = new Set(
      snapshot.paths.map(({ path, mode, blobOid }) => `${path}\0${mode}\0${blobOid}`),
    );
    const reviewed = new Set<string>();
    for (const { path, mode, blobOid } of review.included) {
      const key = `${path}\0${mode}\0${blobOid}`;
      if (!entries.has(key) || reviewed.has(key))
        invalid("path review includes stale or repeated file");
      reviewed.add(key);
    }
    for (const sensitive of snapshot.trackedSensitivePaths) {
      if (!review.included.some(({ path }) => path === sensitive))
        invalid("sensitive tracked path has no review");
    }
  } else if (receipt.snapshot?.trackedSensitivePaths.length)
    invalid("sensitive tracked paths have no review");
  if (receipt.source.candidates.some((candidate) => candidate.disposition === "unclassified"))
    invalid("receipt has unclassified candidates");
  return receipt;
}

export function encodeReceipt(receipt: ReceiptV1): Uint8Array {
  validateReceipt(receipt);
  return enc.encode(`${canonicalJson(receipt)}\n`);
}
export function parseReceipt(bytes: Uint8Array): ReceiptV1 {
  const wire = text(bytes);
  let parsed: unknown;
  try {
    parsed = JSON.parse(wire);
  } catch {
    return invalid("invalid receipt JSON");
  }
  const receipt = validateReceipt(parsed);
  if (wire !== `${canonicalJson(receipt)}\n`) invalid("receipt is not canonically serialized");
  return receipt;
}
