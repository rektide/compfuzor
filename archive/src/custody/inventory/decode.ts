/**
 * Pure byte-level decoding of Git plumbing output into custody model values.
 *
 * No I/O happens here: every function takes the raw bytes (or text) a Git
 * command produced and either returns fully validated values or throws
 * `CustodyError`. The probe layer maps those failures to named blockers and
 * records which inventory category could not be represented — a decode
 * failure is never silently coerced to an empty list.
 *
 * Parsing rules (see design/archive-migration/brief0.gpt6sol.md):
 * - `--z` record output is split on NUL so filenames cannot spoof delimiters;
 * - mixed NUL/newline formats (`for-each-ref`, `reflog show --format`) are
 *   split on newline first, and each line must end with a NUL terminator;
 * - all names are decoded as strict UTF-8 and must round-trip byte-for-byte,
 *   so unrepresentable path/ref bytes become named blockers, not lossy data;
 * - OIDs are validated against the repository's object format before use.
 */
import { oid as oidOf, refName, repoPath } from "../codec.ts";
import { CustodyError } from "../errors.ts";
import type {
  GitObjectFormat,
  GitObjectType,
  GitTip,
  IndexEntry,
  Oid,
  PathEntry,
  RepoPath,
  WorktreeChange,
} from "../model.ts";

const encoder = new TextEncoder();

/** Strict UTF-8 decode that refuses lossy round-trips (lone surrogates). */
export function strictUtf8(bytes: Uint8Array, what: string): string {
  let decoded: string;
  try {
    decoded = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw new CustodyError("invalid-input", `${what} is not valid UTF-8`);
  }
  if (!Buffer.from(encoder.encode(decoded)).equals(Buffer.from(bytes)))
    throw new CustodyError("invalid-input", `${what} cannot round-trip UTF-8`);
  return decoded;
}

/**
 * Split pure NUL-terminated records (`--z` output with no newline framing):
 * each record is the bytes between NUL bytes; one trailing empty record from
 * the final terminator is dropped, any interior empty record is invalid.
 */
export function nulRecords(bytes: Uint8Array, what: string): Uint8Array[] {
  const parts: Uint8Array[] = [];
  let start = 0;
  for (let i = 0; i < bytes.length; i += 1) {
    if (bytes[i] === 0) {
      parts.push(bytes.subarray(start, i));
      start = i + 1;
    }
  }
  if (start < bytes.length) parts.push(bytes.subarray(start));
  if (parts.length > 0 && parts[parts.length - 1].length === 0) parts.pop();
  if (parts.some((part) => part.length === 0))
    throw new CustodyError("inspection-failed", `empty ${what} record`);
  return parts;
}

/**
 * Line-framed NUL format (`--format='...%00'`): each record ends with NUL
 * followed by a newline, so the buffer is split on newline first and every
 * line must end with the NUL terminator. Returns strict-UTF-8 field lists.
 */
export function nulLines(bytes: Uint8Array, what: string): string[][] {
  const text = strictUtf8(bytes, what);
  const lines = text.split("\n");
  if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
  return lines.map((line) => {
    if (!line.endsWith("\0"))
      throw new CustodyError("inspection-failed", `${what} record is not NUL-terminated`);
    return line.slice(0, -1).split("\0");
  });
}

/** `for-each-ref --format='%(refname)%00%(objectname)%00%(objecttype)%00%(*objectname)%00'` */
export function parseForEachRef(bytes: Uint8Array, format: GitObjectFormat): GitTip[] {
  return nulLines(bytes, "for-each-ref record").map((fields) => {
    if (fields.length !== 4)
      throw new CustodyError("inspection-failed", "for-each-ref record arity");
    const [name, target, type, peeled] = fields;
    if (type !== "commit" && type !== "tag" && type !== "tree" && type !== "blob")
      throw new CustodyError("inspection-failed", `unknown object type for ${name}`);
    return {
      name: refName(name),
      oid: oidOf(target, format),
      objectType: type,
      peeledOid: peeled === "" ? null : oidOf(peeled, format),
    };
  });
}

/** `ls-files --stage -z`: `mode SP oid SP stage TAB path`. */
export function parseLsFilesStage(bytes: Uint8Array, format: GitObjectFormat): IndexEntry[] {
  return nulRecords(bytes, "ls-files record").map((record) => {
    const tab = record.indexOf(9);
    if (tab === -1) throw new CustodyError("inspection-failed", "ls-files record has no path");
    const meta = strictUtf8(record.subarray(0, tab), "ls-files metadata").split(" ");
    if (meta.length !== 3) throw new CustodyError("inspection-failed", "ls-files metadata arity");
    const stage = Number.parseInt(meta[2], 10);
    if (stage !== 0 && stage !== 1 && stage !== 2 && stage !== 3)
      throw new CustodyError("inspection-failed", `unknown index stage ${meta[2]}`);
    return {
      mode: modeOf(meta[0]),
      blobOid: oidOf(meta[1], format),
      path: repoPath(record.subarray(tab + 1)),
      stage,
    };
  });
}

/** `ls-tree -r -z`: `mode SP type SP oid TAB path` (blobs and gitlinks with `-r`). */
export function parseLsTree(bytes: Uint8Array, format: GitObjectFormat): PathEntry[] {
  return nulRecords(bytes, "ls-tree record").map((record) => {
    const tab = record.indexOf(9);
    if (tab === -1) throw new CustodyError("inspection-failed", "ls-tree record has no path");
    const meta = strictUtf8(record.subarray(0, tab), "ls-tree metadata").split(" ");
    if (meta.length !== 3) throw new CustodyError("inspection-failed", "ls-tree metadata arity");
    if (meta[1] !== "blob" && !(meta[1] === "commit" && meta[0] === "160000"))
      throw new CustodyError("inspection-failed", `unexpected ls-tree entry type ${meta[1]}`);
    return {
      mode: modeOf(meta[0]),
      blobOid: oidOf(meta[2], format),
      path: repoPath(record.subarray(tab + 1)),
    };
  });
}

function modeOf(mode: string): PathEntry["mode"] {
  if (mode === "100644" || mode === "100755" || mode === "120000" || mode === "160000") return mode;
  throw new CustodyError("inspection-failed", `unsupported Git mode ${mode}`);
}

export interface StatusV2 {
  readonly changes: WorktreeChange[];
  readonly untracked: RepoPath[];
  readonly ignored: RepoPath[];
}

const STATUS_LETTER: Record<string, WorktreeChange["indexStatus"]> = {
  ".": "unchanged",
  A: "added",
  M: "modified",
  D: "deleted",
  R: "renamed",
  C: "copied",
  T: "typechanged",
  U: "unmerged",
};

function letter(char: string, what: string): WorktreeChange["indexStatus"] {
  const status = STATUS_LETTER[char];
  if (status === undefined)
    throw new CustodyError("inspection-failed", `unknown status letter ${char} in ${what}`);
  return status;
}

/**
 * `status --porcelain=v2 -z --untracked-files=all`. Rename/copy records carry
 * two paths (`path` NUL `origPath` NUL), so records are consumed with a
 * cursor rather than parsed independently. Header widths are field-counted
 * from real Git output: `1` records carry two object names (Git omits the
 * worktree hash), `2` adds the rename score, `u` carries all three stages.
 */
export function parseStatusV2(bytes: Uint8Array): StatusV2 {
  const records = nulRecords(bytes, "status record");
  const changes: WorktreeChange[] = [];
  const untracked: RepoPath[] = [];
  const ignored: RepoPath[] = [];
  const spacesBeforePath: Record<string, number> = { "1": 8, "2": 9, u: 10 };
  for (let i = 0; i < records.length; i += 1) {
    const record = strictUtf8(records[i], "status record");
    if (record.startsWith("? ") || record.startsWith("! ")) {
      const path = repoPath(record.slice(2));
      (record.startsWith("? ") ? untracked : ignored).push(path);
      continue;
    }
    const kind = record.slice(0, 1);
    const headerSpaces = spacesBeforePath[kind];
    if (headerSpaces === undefined)
      throw new CustodyError("inspection-failed", `unknown status record kind ${kind}`);
    let spaces = 0;
    let pathStart = -1;
    for (let j = 0; j < record.length; j += 1) {
      if (record.charCodeAt(j) === 32) {
        spaces += 1;
        if (spaces === headerSpaces) {
          pathStart = j + 1;
          break;
        }
      }
    }
    if (pathStart === -1) throw new CustodyError("inspection-failed", "status record header arity");
    const header = record.slice(0, pathStart).trim().split(/\s+/);
    const path = repoPath(record.slice(pathStart));
    if (kind === "1" || kind === "u") {
      const xy = header[1] ?? "";
      if (xy.length !== 2) throw new CustodyError("inspection-failed", "status XY arity");
      const shared: WorktreeChange["indexStatus"] =
        kind === "u" ? "unmerged" : letter(xy[0], "index status");
      const worktree = kind === "u" ? "unmerged" : letter(xy[1], "worktree status");
      changes.push({ path, originalPath: null, indexStatus: shared, worktreeStatus: worktree });
    } else if (kind === "2") {
      const xy = header[1] ?? "";
      if (xy.length !== 2) throw new CustodyError("inspection-failed", "status XY arity");
      const original = records[i + 1];
      if (original === undefined)
        throw new CustodyError("inspection-failed", "rename record lacks original path");
      i += 1;
      changes.push({
        path,
        originalPath: repoPath(original),
        indexStatus: letter(xy[0], "index status"),
        worktreeStatus: letter(xy[1], "worktree status"),
      });
    } else {
      throw new CustodyError("inspection-failed", `unknown status record kind ${kind}`);
    }
  }
  return { changes, untracked, ignored };
}

export interface ReflogEntry {
  readonly oid: Oid;
  readonly selector: string;
}

/** `reflog show --all --format='%H%x00%gD%x00'`: full reflog selector provenance. */
export function parseReflogShow(bytes: Uint8Array, format: GitObjectFormat): ReflogEntry[] {
  return nulLines(bytes, "reflog record").map((fields) => {
    if (fields.length !== 2) throw new CustodyError("inspection-failed", "reflog record arity");
    const selector = fields[1];
    if (!selector.includes("@{") || selector.includes("\0"))
      throw new CustodyError("inspection-failed", `malformed reflog selector`);
    return { oid: oidOf(fields[0], format), selector };
  });
}

export interface FsckCandidate {
  readonly oid: Oid;
  readonly objectType: GitObjectType;
  readonly label: "dangling" | "unreachable";
}

export interface FsckReport {
  /** Tips not referenced by anything — the objects requiring classification. */
  readonly candidates: readonly FsckCandidate[];
  /** Any other fsck output line; corruption evidence, bounded. */
  readonly corruption: readonly string[];
}

/** `fsck --no-reflogs --unreachable`: dangling tips are candidates; anything else is evidence. */
export function parseFsck(
  stdout: Uint8Array,
  stderr: Uint8Array,
  format: GitObjectFormat,
): FsckReport {
  const lines = [
    ...new TextDecoder("utf-8", { fatal: false }).decode(stdout).split("\n"),
    ...new TextDecoder("utf-8", { fatal: false }).decode(stderr).split("\n"),
  ].filter((line) => line !== "");
  const candidates = new Map<string, FsckCandidate>();
  const corruption: string[] = [];
  const candidate = /^(dangling|unreachable) (commit|tag|tree|blob) ([0-9a-f]+)$/;
  for (const line of lines) {
    const match = line.match(candidate);
    if (match === null) {
      corruption.push(line.slice(0, 200));
      continue;
    }
    try {
      oidOf(match[3], format);
    } catch {
      corruption.push(line.slice(0, 200));
      continue;
    }
    const oid = match[3] as Oid;
    const key = `${match[2]}:${oid}`;
    const entry: FsckCandidate = {
      oid,
      objectType: match[2] as GitObjectType,
      label: "dangling",
    };
    const existing = candidates.get(key);
    if (existing === undefined) candidates.set(key, entry);
    else if (match[1] === "dangling") candidates.set(key, entry);
  }
  return {
    candidates: [...candidates.values()].filter(({ label }) => label === "dangling"),
    corruption: corruption.slice(0, 32),
  };
}

/** `config --get-regexp ^remote\..*\.url$` lines: `remote.<name>.url <value>`. */
export function parseRemoteUrls(
  bytes: Uint8Array,
): readonly { readonly name: string; readonly url: string }[] {
  const text = strictUtf8(bytes, "remote configuration");
  return text
    .split("\n")
    .filter((line) => line !== "")
    .map((line) => {
      const match = line.match(/^remote\.([A-Za-z0-9][A-Za-z0-9._-]*)\.url (.+)$/);
      if (match === null) throw new CustodyError("inspection-failed", "malformed remote url line");
      return { name: match[1], url: match[2] };
    });
}

/** `config --get-regexp <pattern>` lines split into key/value pairs. */
export function parseConfigPairs(
  bytes: Uint8Array,
): readonly { readonly key: string; readonly value: string }[] {
  const text = strictUtf8(bytes, "repository configuration");
  return text
    .split("\n")
    .filter((line) => line !== "")
    .map((line) => {
      const space = line.indexOf(" ");
      if (space === -1) throw new CustodyError("inspection-failed", "config line without value");
      return { key: line.slice(0, space), value: line.slice(space + 1) };
    });
}

/** `rev-list --count` output: a single nonnegative decimal. */
export function parseCount(bytes: Uint8Array): number {
  const text = strictUtf8(bytes, "rev-list count");
  if (!/^\d+\n?$/.test(text))
    throw new CustodyError("inspection-failed", "malformed rev-list count");
  const value = Number.parseInt(text, 10);
  if (!Number.isSafeInteger(value) || value < 0)
    throw new CustodyError("inspection-failed", "rev-list count out of range");
  return value;
}

/** `rev-parse --is-*` / boolean config output: exactly `true` or `false`. */
export function parseBoolean(bytes: Uint8Array, what: string): boolean {
  const text = strictUtf8(bytes, what);
  if (text === "true\n" || text === "true") return true;
  if (text === "false\n" || text === "false") return false;
  throw new CustodyError("inspection-failed", `${what} is not a boolean`);
}

/** `hash-object` batch output: one hex OID per line, in argument order. */
export function parseHashObjectLines(
  bytes: Uint8Array,
  format: GitObjectFormat,
  expected: number,
): readonly Oid[] {
  const text = strictUtf8(bytes, "hash-object output");
  const lines = text.split("\n");
  if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
  if (lines.length !== expected)
    throw new CustodyError("inspection-failed", "hash-object output count mismatch");
  return lines.map((line) => oidOf(line, format));
}
