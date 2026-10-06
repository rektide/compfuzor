#!/usr/bin/env node
// Retrieve Debian's generic amd64 config; audit distinct configuration layers.
//
// Ported from retrieve.py; outputs are byte-stable with the Python original
// (receipts and audits hash them). Compressed artifacts are xz payloads, so
// decompression and compression shell out to the system xz binary — Node's
// zlib has no lzma support. Package extraction keeps the Python shape:
// ar(1) lists and extracts the data archive, a small in-file tar reader picks
// the single expected config member, and dpkg(1) compares Debian versions.

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, existsSync, readFileSync, readdirSync, realpathSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";

const MIRROR = "https://deb.debian.org/debian/";
const INDEX = "main/binary-amd64/Packages.xz";
const DEFAULT_KEYRING = "/usr/share/keyrings/debian-archive-keyring.gpg";
const METADATA = /^(CC_VERSION_TEXT|CC_IS_.*|GCC_VERSION|CLANG_VERSION|AS_IS_.*|AS_VERSION|LD_IS_.*|LD_VERSION|LLD_VERSION|RUSTC_VERSION.*|RUSTC_LLVM_VERSION|PAHOLE_VERSION|TOOLS_SUPPORT_.*)$/;
const DESCRIPTION = "Retrieve Debian's generic amd64 config; audit distinct configuration layers.";

const XZ_MAGIC = Buffer.from([0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00]);
const SUBPROCESS_BUFFER = 1 << 30;
const HERE = dirname(fileURLToPath(import.meta.url));

// ---------------------------------------------------------------------------
// Shared helpers (kept in-file so a copied bundle stays self-sufficient).
// ---------------------------------------------------------------------------

export function sha(data: Buffer | string): string {
  return createHash("sha256").update(data).digest("hex");
}

export function checked(data: Buffer, expected: string): Buffer {
  if (sha(data) !== expected) {
    throw new Error(`SHA-256 mismatch: expected ${expected}, got ${sha(data)}`);
  }
  return data;
}

/** Python pathlib suffix: empty for dotfiles, else ".ext" from the last dot. */
export function pythonSuffix(location: string): string {
  const name = basename(location);
  const dot = name.lastIndexOf(".");
  return dot > 0 ? name.slice(dot) : "";
}

/** Strict UTF-8 decode with Python's UnicodeDecodeError message shape. */
export function decodeUtf8Strict(data: Buffer): string {
  for (let i = 0; i < data.length; ) {
    const byte = data[i];
    if (byte < 0x80) {
      i += 1;
      continue;
    }
    let length = 0;
    let low = 0x80;
    let high = 0xbf;
    if (byte >= 0xc2 && byte <= 0xdf) length = 2;
    else if (byte === 0xe0) { length = 3; low = 0xa0; }
    else if ((byte >= 0xe1 && byte <= 0xec) || byte === 0xee || byte === 0xef) length = 3;
    else if (byte === 0xed) { length = 3; high = 0x9f; }
    else if (byte === 0xf0) { length = 4; low = 0x90; }
    else if (byte >= 0xf1 && byte <= 0xf3) length = 4;
    else if (byte === 0xf4) { length = 4; high = 0x8f; }
    else throw new Error(
      `'utf-8' codec can't decode byte 0x${byte.toString(16).padStart(2, "0")} in position ${i}: invalid start byte`);
    for (let offset = 1; offset < length; offset += 1) {
      const limit = offset === 1 ? high : 0xbf;
      const floor = offset === 1 ? low : 0x80;
      const continuation = data[i + offset];
      if (continuation === undefined) {
        throw new Error(`'utf-8' codec can't decode byte 0x${byte.toString(16).padStart(2, "0")} in position ${i}: unexpected end of data`);
      }
      if (continuation < floor || continuation > limit) {
        throw new Error(`'utf-8' codec can't decode byte 0x${continuation.toString(16).padStart(2, "0")} in position ${i + offset}: invalid continuation byte`);
      }
    }
    i += length;
  }
  return data.toString("utf8");
}

/** Translate xz(1) failures to the Python lzma module's error messages. */
export function lzmaError(stderr: Buffer | string): Error {
  const text = stderr.toString();
  if (text.includes("File format not recognized")) {
    return new Error("Input format not supported by decoder");
  }
  if (text.includes("Unexpected end of input")) {
    return new Error("Compressed data ended before the end-of-stream marker was reached");
  }
  return new Error("Corrupt input data");
}

/** Decompress an xz payload through the system xz binary (preset 6 peer). */
export function xzDecompress(data: Buffer): Buffer {
  const result = spawnSync("xz", ["-dc"], { input: data, maxBuffer: SUBPROCESS_BUFFER });
  if (result.error) throw result.error;
  if (result.status !== 0) throw lzmaError(result.stderr);
  return result.stdout;
}

/** Byte-identical to Python lzma.compress defaults: xz container, preset 6, CRC64. */
export function xzCompress(data: Buffer): Buffer {
  const result = spawnSync("xz", ["-z", "-c", "-6", "-C", "crc64", "-T1"], {
    input: data, maxBuffer: SUBPROCESS_BUFFER,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw lzmaError(result.stderr);
  return result.stdout;
}

export function compareStrings(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

/** str(Path(p)): collapse redundant separators and "." components like pathlib. */
export function pythonPath(p: string): string {
  if (p === "") return ".";
  const absolute = p.startsWith("/");
  const parts = p.split("/").filter((piece) => piece !== "" && piece !== ".");
  let out = parts.join("/");
  if (absolute) out = `/${out}`;
  if (out === "") out = absolute ? "/" : ".";
  return out;
}

/** Python datetime.now(timezone.utc).isoformat(): microseconds, +00:00 offset. */
export function pythonUtcNow(): string {
  const now = new Date();
  const stamp = now.toISOString().slice(0, 19);
  const millis = now.getMilliseconds();
  return `${stamp}${millis > 0 ? `.${String(millis).padStart(3, "0")}000` : ""}+00:00`;
}

/** RFC 2822 date parsing (Debian Date/Valid-Until headers). */
export function rfc2822ToDate(text: string): Date {
  const date = new Date(text);
  if (Number.isNaN(date.getTime())) throw new Error(`Invalid date: ${text}`);
  return date;
}

/** json.dumps(value, indent=2, sort_keys=True) byte-for-byte, plus newline. */
export function dump(path: string, value: unknown): void {
  writeFileSync(path, pythonJson(value) + "\n");
}

function pythonJson(value: unknown, indent = 0): string {
  const pad = "  ".repeat(indent);
  const inner = "  ".repeat(indent + 1);
  if (value === null || value === undefined) return "null";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") return String(value);
  if (typeof value === "string") return pythonJsonString(value);
  if (Array.isArray(value)) {
    if (value.length === 0) return "[]";
    return `[\n${value.map((item) => inner + pythonJson(item, indent + 1)).join(",\n")}\n${pad}]`;
  }
  const record = value as Record<string, unknown>;
  const keys = Object.keys(record).sort(compareStrings);
  if (keys.length === 0) return "{}";
  return `{\n${keys.map((key) => `${inner}${pythonJsonString(key)}: ${pythonJson(record[key], indent + 1)}`).join(",\n")}\n${pad}}`;
}

function pythonJsonString(text: string): string {
  let out = '"';
  for (const character of text) {
    const code = character.codePointAt(0)!;
    if (character === '"') out += '\\"';
    else if (character === "\\") out += "\\\\";
    else if (character === "\n") out += "\\n";
    else if (character === "\r") out += "\\r";
    else if (character === "\t") out += "\\t";
    else if (character === "\b") out += "\\b";
    else if (character === "\f") out += "\\f";
    else if (code < 0x20 || code >= 0x7f) {
      for (const unit of character) {
        const unitCode = unit.codePointAt(0)!;
        out += `\\u${unitCode.toString(16).padStart(4, "0")}`;
      }
    } else out += character;
  }
  return out + '"';
}

// ---------------------------------------------------------------------------
// Debian index parsing and package selection.
// ---------------------------------------------------------------------------

type Record_ = Record<string, string>;

export function records(text: string): Record_[] {
  const parsed: Record_[] = [];
  for (const paragraph of text.split("\n\n")) {
    const record: Record_ = Object.create(null);
    let key: string | null = null;
    for (const line of paragraph.split("\n")) {
      if ((line.startsWith(" ") || line.startsWith("\t")) && key !== null) {
        record[key] += "\n" + line.slice(1);
      } else if (line.includes(": ")) {
        const index = line.indexOf(": ");
        key = line.slice(0, index);
        record[key] = line.slice(index + 2);
      }
    }
    if (Object.keys(record).length > 0) parsed.push(record);
  }
  return parsed;
}

/** Latest by Debian version ordering, decided by dpkg --compare-versions. */
export function newest(items: Record_[]): Record_ | null {
  let result: Record_ | null = null;
  for (const item of items) {
    if (result === null || spawnSync(
      "dpkg", ["--compare-versions", item["Version"], "gt", result["Version"]],
      { encoding: "utf8" },
    ).status === 0) {
      result = item;
    }
  }
  return result;
}

export function selectPackage(items: Record_[]): [Record_ | null, Record_ | null, string] {
  const list = [...items];
  const meta = newest(list.filter((record) => record["Package"] === "linux-headers-amd64"));
  const generic = list.filter((record) =>
    /^linux-headers-[0-9].*-amd64$/.test(record["Package"] ?? "") &&
    !/-(cloud|rt)-amd64$/.test(record["Package"]));
  if (meta !== null) {
    const targets = [...(meta["Depends"] ?? "").matchAll(/\b(linux-headers-[0-9][^ ,|()]*)\s*\(=\s*([^ )]+)\)/g)];
    const matches = generic.filter((record) =>
      targets.some((target) => target[1] === record["Package"] && target[2] === record["Version"]));
    if (matches.length !== 1) {
      throw new Error("Generic headers metapackage does not resolve to exactly one indexed package");
    }
    return [matches[0], meta, "linux-headers-amd64 exact dependency"];
  }
  return [newest(generic), null, "latest generic headers by Debian version (no metapackage)"];
}

export async function get(url: string): Promise<Buffer> {
  const response = await fetch(url, { signal: AbortSignal.timeout(90_000) });
  if (!response.ok) throw new Error(`HTTP Error ${response.status}: ${response.statusText}`);
  return Buffer.from(await response.arrayBuffer());
}

export function releaseIndex(release: Buffer): [string, number] {
  let inside = false;
  for (const line of decodeUtf8Strict(release).split("\n")) {
    if (line === "SHA256:") {
      inside = true;
    } else if (inside && !line.startsWith(" ")) {
      break;
    } else if (inside) {
      const fields = line.match(/\S+/g) ?? [];
      const [digest, size, name] = fields;
      if (name === INDEX) return [digest, parseInt(size, 10)];
    }
  }
  throw new Error(`InRelease has no SHA256 entry for ${INDEX}`);
}

// ---------------------------------------------------------------------------
// Package extraction: ar member listing plus a minimal tar reader.
// ---------------------------------------------------------------------------

function runBinary(command: string, args: string[], input?: Buffer): Buffer {
  const result = spawnSync(command, args, input === undefined
    ? { maxBuffer: SUBPROCESS_BUFFER }
    : { input, maxBuffer: SUBPROCESS_BUFFER });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`Command '[${[command, ...args].map((part) => `'${part}'`).join(", ")}]' returned non-zero exit status ${result.status}.`);
  }
  return result.stdout;
}

interface TarMember {
  name: string;
  size: number;
  offset: number;
  isFile: boolean;
}

function tarFieldString(header: Buffer, start: number, length: number): string {
  const slice = header.subarray(start, start + length);
  const end = slice.indexOf(0);
  return slice.subarray(0, end === -1 ? slice.length : end).toString("utf8");
}

function tarSize(header: Buffer): number {
  const field = header.subarray(124, 136);
  if (field[0] & 0x80) {
    let value = field[0] & 0x7f;
    for (const byte of field.subarray(1)) value = value * 256 + byte;
    return value;
  }
  return parseInt(field.toString("ascii").replace(/[\0 ]/g, ""), 8) || 0;
}

/** Transparent decompression matching tarfile "r:*": gzip, bzip2, xz, plain. */
function decompressForTar(data: Buffer): Buffer {
  if (data.subarray(0, 6).equals(XZ_MAGIC)) return xzDecompress(data);
  if (data[0] === 0x1f && data[1] === 0x8b) return gunzipSync(data);
  if (data[0] === 0x42 && data[1] === 0x5a && data[2] === 0x68) return runBinary("bzip2", ["-dc"], data);
  if (data[0] === 0x28 && data[1] === 0xb5 && data[2] === 0x2f && data[3] === 0xfd) {
    return runBinary("zstd", ["-dc"], data);
  }
  return data;
}

function parseTar(data: Buffer): TarMember[] {
  const members: TarMember[] = [];
  let offset = 0;
  let longName: string | null = null;
  let paxPath: string | null = null;
  while (offset + 512 <= data.length) {
    const header = data.subarray(offset, offset + 512);
    if (!header.some((byte) => byte !== 0)) break;
    const name = tarFieldString(header, 0, 100);
    const size = tarSize(header);
    const typeflag = String.fromCharCode(header[156]);
    const posixUstar = header.subarray(257, 265).toString("ascii") === "ustar\0" + "00";
    const prefix = tarFieldString(header, 345, 155);
    const dataOffset = offset + 512;
    const payload = data.subarray(dataOffset, dataOffset + size);
    const next = dataOffset + Math.ceil(size / 512) * 512;
    if (typeflag === "L") {
      longName = tarFieldString(payload, 0, payload.length);
      offset = next;
      continue;
    }
    if (typeflag === "K") {
      offset = next;
      continue;
    }
    if (typeflag === "x" || typeflag === "g") {
      const override = paxRecordPath(payload);
      if (typeflag === "x" && override !== null) paxPath = override;
      offset = next;
      continue;
    }
    let memberName = name;
    if (posixUstar && prefix !== "") memberName = `${prefix}/${name}`;
    if (longName !== null) {
      memberName = longName;
      longName = null;
    }
    if (paxPath !== null) {
      memberName = paxPath;
      paxPath = null;
    }
    members.push({
      name: memberName,
      size,
      offset: dataOffset,
      isFile: typeflag === "0" || typeflag === "\x00" || typeflag === "7",
    });
    offset = next;
  }
  return members;
}

function paxRecordPath(payload: Buffer): string | null {
  const text = payload.toString("utf8");
  let position = 0;
  while (position < text.length) {
    const space = text.indexOf(" ", position);
    if (space === -1) break;
    const length = parseInt(text.slice(position, space), 10);
    if (!Number.isFinite(length) || length <= 0) break;
    const record = text.slice(position, position + length);
    const equals = record.indexOf("=");
    if (equals !== -1 && record.slice(space + 1, equals) === "path") {
      const end = record.endsWith("\n") ? record.length - 1 : record.length;
      return record.slice(equals + 1, end);
    }
    position += length;
  }
  return null;
}

export function extractConfig(packagePath: string, packageName: string): [Buffer, string] {
  const members = runBinary("ar", ["t", packagePath]).toString("utf8").split("\n").filter((line) => line !== "");
  const dataMembers = members.filter((name) => name.startsWith("data.tar.") || name === "data.tar");
  if (dataMembers.length !== 1) {
    throw new Error("Expected exactly one data archive in headers package");
  }
  const member = dataMembers[0];
  let data = runBinary("ar", ["p", packagePath, member]);
  if (member.endsWith(".zst")) data = runBinary("zstd", ["-dc"], data);
  const expected = `usr/src/${packageName}/.config`;
  const source = decompressForTar(data);
  const matches = parseTar(source).filter((entry) => entry.name.replace(/^\.\//, "") === expected);
  if (matches.length !== 1 || !matches[0].isFile) {
    throw new Error(`Expected one regular ${expected}; no other package files will be extracted`);
  }
  const config = source.subarray(matches[0].offset, matches[0].offset + matches[0].size);
  if (Object.keys(parseConfig(decodeUtf8Strict(config))).length === 0) {
    throw new Error("Embedded file contains no configuration symbols");
  }
  return [config, expected];
}

// ---------------------------------------------------------------------------
// Config parsing, deltas, and policy audits.
// ---------------------------------------------------------------------------

const CONFIG_SET = /^CONFIG_([\p{L}\p{N}_]+)=(.*)$/u;
const CONFIG_NOT_SET = /^# CONFIG_([\p{L}\p{N}_]+) is not set$/u;

/** Symbol map as a plain object, mirroring the Python dict semantics. */
export function parseConfig(text: string): Record_ {
  const values: Record_ = Object.create(null);
  for (const line of text.split("\n")) {
    const match = CONFIG_SET.exec(line);
    if (match) {
      values[match[1]] = match[2];
    } else {
      const unset = CONFIG_NOT_SET.exec(line);
      if (unset) values[unset[1]] = "n";
    }
  }
  return values;
}

export function configText(path: string): string {
  const data = readFileSync(path);
  return decodeUtf8Strict(pythonSuffix(path) === ".xz" ? xzDecompress(data) : data);
}

export function delta(
  before: Record_,
  after: Record_,
  keys: Iterable<string> | null = null,
  excludeMetadata = false,
): string {
  const symbols = keys ?? new Set([...Object.keys(before), ...Object.keys(after)]);
  const lines: string[] = [];
  for (const symbol of [...symbols].sort(compareStrings)) {
    if (excludeMetadata && METADATA.test(symbol)) continue;
    const old = before[symbol] ?? "<absent>";
    const updated = after[symbol] ?? "<absent>";
    if (old !== updated) lines.push(`${symbol}: ${old} -> ${updated}`);
  }
  return lines.join("\n") + (lines.length > 0 ? "\n" : "");
}

export function requiredAudit(required: Record_, actual: Record_, declared: Record_): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const symbol of Object.keys(required).sort(compareStrings)) {
    const value = required[symbol];
    let declaration = declared[symbol] === value ? "explicit" : "inherited/not explicitly declared";
    if (symbol === "DEBUG_INFO" && value === "y" && declared["DEBUG_KERNEL"] === "y" &&
        ["DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT", "DEBUG_INFO_DWARF4", "DEBUG_INFO_DWARF5"]
          .some((choice) => declared[choice] === "y")) {
      declaration = "derived from explicitly declared debug-information choice";
    }
    result[symbol] = {
      expected: value,
      actual: actual[symbol] ?? "<absent>",
      fulfilled: actual[symbol] === value,
      declaration,
    };
  }
  return result;
}

export function mergedConfig(base: string, policy: string): string {
  const values: Record_ = Object.assign(Object.create(null), parseConfig(base), parseConfig(policy));
  return Object.keys(values).sort(compareStrings)
    .map((key) => (values[key] === "n" ? `# CONFIG_${key} is not set` : `CONFIG_${key}=${values[key]}`))
    .join("\n") + "\n";
}

export function kernelVersion(tree: string): string {
  const values: Record<string, string> = {};
  for (const line of readFileSync(join(tree, "Makefile"), "utf8").split("\n")) {
    const match = /^(VERSION|PATCHLEVEL|SUBLEVEL|EXTRAVERSION)\s*=\s*(.*)$/.exec(line);
    if (match) values[match[1]] = match[2];
  }
  const core = ["VERSION", "PATCHLEVEL", "SUBLEVEL"].map((key) => {
    if (!(key in values)) throw new Error(`KeyError: '${key}'`);
    return values[key];
  });
  return core.join(".") + (values["EXTRAVERSION"] ?? "");
}

export function kernelGitHead(tree: string): string | null {
  const resolved = realpathSync(tree);
  let result = spawnSync("git", ["-C", resolved, "rev-parse", "--show-toplevel"], { encoding: "utf8" });
  const toplevel = result.stdout?.trim();
  if (result.status !== 0 || !toplevel || realpathSync(toplevel) !== resolved) return null;
  result = spawnSync("git", ["-C", resolved, "rev-parse", "HEAD"], { encoding: "utf8" });
  return result.status === 0 ? result.stdout.trim() : null;
}

// ---------------------------------------------------------------------------
// fetch: authenticated retrieval with pinned cache replay.
// ---------------------------------------------------------------------------

export function verifyRelease(path: string, keyring: string): string[] {
  if (!existsSync(keyring)) {
    throw new Error("Archive keyring unavailable; supply --keyring or explicitly choose --tls-only");
  }
  const keyringPath = resolve(keyring);
  const result = spawnSync(
    "gpgv", ["--status-fd", "1", "--keyring", keyringPath, path],
    { encoding: "utf8", maxBuffer: 1 << 26 });
  if (result.status !== 0) {
    throw new Error(`Command '[${["gpgv", "--status-fd", "1", "--keyring", keyringPath, path].map((part) => `'${part}'`).join(", ")}]' returned non-zero exit status ${result.status}.`);
  }
  return [...result.stdout.matchAll(/^\[GNUPG:\] VALIDSIG ([0-9A-F]+) /gm)].map((match) => match[1]);
}

export interface FetchArgs {
  suite: "unstable" | "experimental" | "both";
  cacheDir: string;
  outputDir: string;
  offline: boolean;
  inspectOnly: boolean;
  keyring: string;
  tlsOnly: boolean;
}

export async function fetchCommand(args: FetchArgs): Promise<void> {
  const cache = resolve(args.cacheDir);
  const output = resolve(args.outputDir);
  const suites = args.suite === "both" ? ["unstable", "experimental"] : [args.suite];
  mkdirSync(cache, { recursive: true });
  for (const suite of suites) {
    const destination = join(output, suite);
    mkdirSync(destination, { recursive: true });
    const receiptPath = join(destination, "receipt.json");
    let release: Buffer;
    let index: Buffer;
    let receipt: Record<string, unknown>;
    if (args.offline) {
      receipt = JSON.parse(readFileSync(receiptPath, "utf8"));
      release = checked(readFileSync(join(cache, receipt["release_cache"] as string)), receipt["release_sha256"] as string);
      index = checked(readFileSync(join(cache, receipt["index_cache"] as string)), receipt["index_sha256"] as string);
      if (receipt["trust"] === "Debian InRelease signature + SHA256 chain") {
        verifyRelease(join(cache, receipt["release_cache"] as string), args.keyring);
      }
      const [digest, size] = releaseIndex(release);
      checked(index, digest);
      if (index.length !== size) throw new Error("Index size differs from InRelease");
    } else {
      const releaseUrl = `${MIRROR}dists/${suite}/InRelease`;
      release = await get(releaseUrl);
      const releaseCache = `${sha(release)}.InRelease`;
      writeFileSync(join(cache, releaseCache), release);
      const fingerprints = args.tlsOnly ? [] : verifyRelease(join(cache, releaseCache), args.keyring);
      const releaseText = release.toString("utf8");
      const expires = /^Valid-Until: (.+)$/m.exec(releaseText);
      if (expires !== null && rfc2822ToDate(expires[1]) < new Date()) {
        throw new Error("Expired current InRelease; use --offline only for deliberate pinned replay");
      }
      const [digest, size] = releaseIndex(release);
      const indexUrl = `${MIRROR}dists/${suite}/${INDEX}`;
      index = checked(await get(indexUrl), digest);
      if (index.length !== size) throw new Error("Index size differs from InRelease");
      const indexCache = `${digest}.Packages.xz`;
      writeFileSync(join(cache, indexCache), index);
      const dateMatch = /^Date: (.+)$/m.exec(releaseText);
      if (dateMatch === null) throw new Error("KeyError: 'Date' match");
      receipt = {
        schema: 1,
        suite,
        architecture: "amd64",
        flavour: "generic",
        retrieved_utc: pythonUtcNow(),
        release_url: releaseUrl,
        release_sha256: sha(release),
        release_cache: releaseCache,
        index_url: indexUrl,
        index_sha256: digest,
        index_cache: indexCache,
        trust: args.tlsOnly
          ? "TLS + SHA256 only (no archive signature verification)"
          : "Debian InRelease signature + SHA256 chain",
        keyring: args.tlsOnly ? null : args.keyring,
        verified_signing_fingerprints: fingerprints,
        release_valid_until: expires !== null ? expires[1] : null,
        release_date: dateMatch[1],
      };
    }
    const [packageRecord, meta, selection] = selectPackage(records(decodeUtf8Strict(xzDecompress(index))));
    receipt["selection"] = selection;
    receipt["metapackage"] = meta;
    receipt["package"] = packageRecord;
    receipt["status"] = packageRecord !== null ? "available" : "unavailable-in-suite-index";
    writeFileSync(join(destination, "InRelease.xz"), xzCompress(release));
    if (packageRecord !== null) {
      const filename = packageRecord["Filename"];
      if (!filename.startsWith("pool/") || filename.split("/").includes("..")) {
        throw new Error("Unexpected package filename");
      }
      const packageCache = `${packageRecord["SHA256"]}.deb`;
      receipt["package_url"] = MIRROR + filename;
      receipt["package_cache"] = packageCache;
      if (!args.inspectOnly) {
        const packagePath = join(cache, packageCache);
        if (!existsSync(packagePath)) {
          if (args.offline) {
            throw new Error(`Pinned package absent from cache: ${packagePath}`);
          }
          writeFileSync(packagePath, checked(await get(receipt["package_url"] as string), packageRecord["SHA256"]));
        }
        const packageData = checked(readFileSync(packagePath), packageRecord["SHA256"]);
        if (packageData.length !== parseInt(packageRecord["Size"], 10)) {
          throw new Error("Package size mismatch");
        }
        const [config, member] = extractConfig(packagePath, packageRecord["Package"]);
        const configName = `config-${packageRecord["Version"]}-amd64.xz`;
        writeFileSync(join(destination, configName), xzCompress(config));
        receipt["config"] = {
          file: configName,
          sha256: sha(config),
          member,
          header: decodeUtf8Strict(config).split("\n").slice(0, 8)
            .filter((line) => line.includes("Kernel Configuration")),
        };
      }
    }
    dump(receiptPath, receipt);
    process.stdout.write(`${suite}: ${packageRecord !== null ? packageRecord["Version"] : "unavailable"}; ${receiptPath}\n`);
  }
}

// ---------------------------------------------------------------------------
// diff: declaration-only audits and optional same-target evaluation.
// ---------------------------------------------------------------------------

export interface AuditArgs {
  debianConfig: string;
  outputDir: string;
  policy: string[] | null;
  requiredIntent: string;
  ourConfig: string | null;
  upstreamConfig: string | null;
  kernelTree: string | null;
  kernelRevision: string | null;
  workDir: string | null;
  toolchain: "llvm" | "gcc";
}

export function auditCommand(args: AuditArgs): void {
  const output = resolve(args.outputDir);
  mkdirSync(output, { recursive: true });
  const debianText = configText(args.debianConfig);
  const debian = parseConfig(debianText);
  const bundleRoot = resolve(HERE, "..");
  const paths = args.policy ?? [
    join(bundleRoot, "overrides.config"),
    join(bundleRoot, `overrides.${args.toolchain}`),
  ];
  const policy: Record_ = Object.create(null);
  let policyText = "";
  for (const policyPath of paths) {
    const text = configText(policyPath);
    Object.assign(policy, parseConfig(text));
    policyText += text + "\n";
  }
  const report: Record<string, unknown> = {
    debian_input: { path: pythonPath(args.debianConfig), sha256: sha(Buffer.from(debianText, "utf8")) },
    debian_header: debianText.split("\n").slice(0, 8).filter((line) => line.includes("Kernel Configuration")),
    policy_inputs: paths.map((policyPath) => ({ path: pythonPath(policyPath), sha256: sha(readFileSync(policyPath)) })),
    semantics: "Declared policy differs from Debian; absent symbols are not assumed disabled; metadata is not policy.",
  };
  const required = parseConfig(configText(args.requiredIntent));
  report["required_intent"] = {
    input: pythonPath(args.requiredIntent),
    sha256: sha(readFileSync(args.requiredIntent)),
    native_debian: requiredAudit(required, debian, policy),
  };
  writeFileSync(join(output, "policy-declared-vs-debian.diff"), delta(debian, policy, Object.keys(policy), true));
  if (args.upstreamConfig !== null) {
    const upstreamText = configText(args.upstreamConfig);
    writeFileSync(join(output, "debian-vs-upstream.raw.diff"), delta(parseConfig(upstreamText), debian));
    report["upstream_input"] = { path: pythonPath(args.upstreamConfig), sha256: sha(Buffer.from(upstreamText, "utf8")) };
    report["upstream_comparison"] =
      "RAW: caller must establish matching version/architecture/toolchain; not implied native by this helper";
  }
  if (args.ourConfig !== null) {
    const ours = parseConfig(configText(args.ourConfig));
    writeFileSync(join(output, "our-current-vs-debian.raw.diff"), delta(debian, ours));
    writeFileSync(join(output, "our-current-declared-policy-vs-debian.diff"), delta(debian, ours, Object.keys(policy), true));
    report["our_current_comparison"] = "RAW cross-version/toolchain audit, not attribution of all differences to policy";
  }
  if (args.kernelTree !== null) {
    if (args.workDir === null) {
      throw new Error("--kernel-tree requires an explicit --work-dir");
    }
    const tree = resolve(args.kernelTree);
    const work = resolve(args.workDir);
    if (tree === work || isInside(work, tree)) {
      throw new Error("Work directory must be outside the kernel source tree");
    }
    if (existsSync(work) && readdirSync(work).length > 0) {
      throw new Error("Work directory must be new or empty; no existing outputs are overwritten");
    }
    mkdirSync(work, { recursive: true });
    const env = { ...process.env, KCONFIG_CONFIG: ".config" };
    const make = (name: string, target: string, seed: string | null = null): [Record_, string] => {
      const build = join(work, name);
      mkdirSync(build);
      if (seed !== null) writeFileSync(join(build, ".config"), seed);
      const command = ["make", "-C", tree, `O=${build}`, "ARCH=x86"];
      if (args.toolchain === "llvm") command.push("LLVM=1");
      command.push(target);
      const result = spawnSync(command[0], command.slice(1), { encoding: "utf8", maxBuffer: SUBPROCESS_BUFFER });
      const log = result.stdout ?? "";
      if (result.stderr) writeFileSync(join(work, `${name}.log`), log + result.stderr);
      else writeFileSync(join(work, `${name}.log`), log);
      if (result.status !== 0) {
        throw new Error(`Command '[${command.map((part) => `'${part}'`).join(", ")}]' returned non-zero exit status ${result.status}.`);
      }
      const built = readFileSync(join(build, ".config"), "utf8");
      writeFileSync(join(output, `${name}.config.xz`), xzCompress(Buffer.from(built, "utf8")));
      return [parseConfig(built), built];
    };
    const [upstream] = make("target-upstream", "x86_64_defconfig");
    const [projected, projectedText] = make("target-debian", "olddefconfig", debianText);
    const [custom] = make("target-policy", "olddefconfig", mergedConfig(projectedText, policyText));
    writeFileSync(join(output, "target-debian-vs-upstream.diff"), delta(upstream, projected, null, true));
    writeFileSync(join(output, "target-policy-vs-debian.diff"), delta(projected, custom, null, true));
    writeFileSync(join(output, "target-toolchain-metadata.diff"), delta(
      debian, projected,
      [...new Set([...Object.keys(debian), ...Object.keys(projected)])].filter((key) => METADATA.test(key)),
    ));
    writeFileSync(join(output, "target-policy-unfulfilled.diff"), delta(policy, custom, Object.keys(policy), true));
    writeFileSync(join(output, "target-required-intent-unfulfilled.diff"), delta(required, custom, Object.keys(required), true));
    (report["required_intent"] as Record<string, unknown>)["target_policy"] = requiredAudit(required, custom, policy);
    report["target"] = {
      tree,
      version: kernelVersion(tree),
      toolchain: args.toolchain,
      declared_revision: args.kernelRevision,
      source_fingerprints: {
        Makefile: sha(readFileSync(join(tree, "Makefile"))),
        Kconfig: sha(readFileSync(join(tree, "Kconfig"))),
      },
      semantics: "PROJECTED: upstream -> Debian normalized on target -> declared policy normalized on same target; not native Debian defaults",
      work_dir: work,
    };
    (report["target"] as Record<string, unknown>)["git_head_if_available"] = kernelGitHead(tree);
    const toolVersions: Record<string, string> = {};
    (report["target"] as Record<string, unknown>)["tool_versions"] = toolVersions;
    for (const tool of [
      "make",
      args.toolchain === "llvm" ? "clang" : "gcc",
      args.toolchain === "llvm" ? "ld.lld" : "ld",
      "rustc", "bindgen", "pahole",
    ]) {
      try {
        const result = spawnSync(tool, ["--version"], { encoding: "utf8" });
        toolVersions[tool] = result.status === 0
          ? (result.stdout || result.stderr).split("\n")[0]
          : "unavailable";
      } catch {
        toolVersions[tool] = "unavailable";
      }
    }
  }
  const outputs: Record<string, string> = {};
  for (const entry of readdirSync(output, { withFileTypes: true })) {
    if (entry.isFile() && entry.name !== "audit.json") outputs[entry.name] = sha(readFileSync(join(output, entry.name)));
  }
  const sortedOutputs: Record<string, string> = {};
  for (const name of Object.keys(outputs).sort(compareStrings)) sortedOutputs[name] = outputs[name];
  report["output_sha256"] = sortedOutputs;
  dump(join(output, "audit.json"), report);
  process.stdout.write(`${join(output, "audit.json")}\n`);
}

function isInside(path: string, ancestor: string): boolean {
  let current: string | null = path;
  while (current !== null) {
    if (current === ancestor) return true;
    const parent = dirname(current);
    current = parent === current ? null : parent;
  }
  return false;
}

// ---------------------------------------------------------------------------
// CLI: Python argparse-shaped usage, help, and error rendering.
// ---------------------------------------------------------------------------

interface OptionSpec {
  long: string;
  short?: string;
  dest: string;
  takesValue: boolean;
  metavar?: string;
  choices?: string[];
  help?: string;
  required?: boolean;
  append?: boolean;
  default?: string | boolean | null;
}

function terminalWidth(): number {
  const columns = process.env.COLUMNS;
  if (columns !== undefined && /^\d+$/.test(columns)) return Math.max(parseInt(columns, 10), 1) - 2;
  return (process.stdout.columns ?? 80) - 2;
}

function wrapText(text: string, width: number): string[] {
  const chunks: string[] = [];
  for (const token of text.split(/(\s+)/)) {
    if (token === "") continue;
    if (/^\s+$/.test(token)) {
      chunks.push(" ");
      continue;
    }
    let start = 0;
    for (let index = 1; index < token.length - 1; index += 1) {
      const boundary = token[index] === "-" && /[A-Za-z]/.test(token[index - 1]) &&
        /[A-Za-z0-9]/.test(token[index + 1]);
      if (boundary) {
        chunks.push(token.slice(start, index + 1));
        start = index + 1;
      }
    }
    chunks.push(token.slice(start));
  }
  const lines: string[] = [];
  while (chunks.length > 0) {
    const line: string[] = [];
    let length = 0;
    while (chunks.length > 0) {
      const chunk = chunks[0];
      if (line.length === 0 && /^\s+$/.test(chunk)) {
        chunks.shift();
        continue;
      }
      if (length + chunk.length <= width) {
        line.push(chunks.shift()!);
        length += chunk.length;
      } else {
        break;
      }
    }
    if (chunks.length > 0 && chunks[0].length > width) {
      const spaceLeft = Math.max(width - length, 1);
      line.push(chunks[0].slice(0, spaceLeft));
      chunks[0] = chunks[0].slice(spaceLeft);
    }
    while (line.length > 0 && line[line.length - 1].trim() === "") line.pop();
    if (line.length > 0) lines.push(line.join(""));
  }
  return lines;
}

function optionInvocation(option: OptionSpec): string {
  const strings = option.short !== undefined ? `${option.short}, ${option.long}` : option.long;
  if (!option.takesValue) return strings;
  const metavar = option.metavar ?? option.dest.toUpperCase();
  return `${strings} ${metavar}`;
}

function optionUsagePart(option: OptionSpec): string {
  const strings = option.short !== undefined ? option.short : option.long;
  if (!option.takesValue) return option.required ? strings : `[${strings}]`;
  const metavar = option.metavar ?? option.dest.toUpperCase();
  return option.required ? `${strings} ${metavar}` : `[${strings} ${metavar}]`;
}

function formatUsage(prog: string, optParts: string[], posParts: string[], width: number): string {
  const prefix = "usage: ";
  const textWidth = width;
  const parts = [...optParts, ...posParts];
  const usage = [prog, ...parts].join(" ");
  if (prefix.length + usage.length <= textWidth) return prefix + usage;
  const getLines = (pieces: string[], indent: string, withPrefix: boolean): string[] => {
    const lines: string[] = [];
    let line: string[] = [];
    let lineLen = withPrefix ? prefix.length - 1 : indent.length - 1;
    for (const part of pieces) {
      if (lineLen + 1 + part.length > textWidth && line.length > 0) {
        lines.push(indent + line.join(" "));
        line = [];
        lineLen = indent.length - 1;
      }
      line.push(part);
      lineLen += part.length + 1;
    }
    if (line.length > 0) lines.push(indent + line.join(" "));
    if (withPrefix && lines.length > 0) lines[0] = lines[0].slice(indent.length);
    return lines;
  };
  let lines: string[];
  if (prefix.length + prog.length <= 0.75 * textWidth) {
    const indent = " ".repeat(prefix.length + prog.length + 1);
    if (optParts.length > 0) {
      lines = getLines([prog, ...optParts], indent, true);
      lines.push(...getLines(posParts, indent, false));
    } else {
      lines = getLines([prog, ...posParts], indent, true);
    }
  } else {
    const indent = " ".repeat(prefix.length);
    lines = getLines([...optParts, ...posParts], indent, false);
    if (lines.length > 1) {
      lines = [...getLines(optParts, indent, false), ...getLines(posParts, indent, false)];
    }
    lines.unshift(prog);
  }
  return prefix + lines.join("\n");
}

interface HelpEntry {
  invocation: string;
  help?: string;
}

function renderEntries(entries: HelpEntry[], indent: number, helpPosition: number, width: number): string {
  const actionWidth = helpPosition - indent - 2;
  const helpWidth = Math.max(width - helpPosition, 11);
  return entries.map((entry) => {
    const pad = " ".repeat(indent);
    if (!entry.help) return `${pad}${entry.invocation}\n`;
    const helpLines = wrapText(entry.help.replace(/\s+/g, " ").trim(), helpWidth);
    if (entry.invocation.length <= actionWidth) {
      return pad + entry.invocation.padEnd(actionWidth) + "  " +
        helpLines.join("\n" + " ".repeat(helpPosition)) + "\n";
    }
    return `${pad}${entry.invocation}\n` +
      helpLines.map((line) => " ".repeat(helpPosition) + line).join("\n") + "\n";
  }).join("");
}

const HELP_OPTION: OptionSpec = {
  long: "--help", short: "-h", dest: "help", takesValue: false,
  help: "show this help message and exit",
};

const FETCH_OPTIONS: OptionSpec[] = [
  HELP_OPTION,
  { long: "--suite", dest: "suite", takesValue: true, metavar: "{unstable,experimental,both}",
    choices: ["unstable", "experimental", "both"], default: "both" },
  { long: "--cache-dir", dest: "cache_dir", takesValue: true, required: true },
  { long: "--output-dir", dest: "output_dir", takesValue: true, required: true },
  { long: "--offline", dest: "offline", takesValue: false,
    help: "Replay existing output receipts and verified cached bytes" },
  { long: "--inspect-only", dest: "inspect_only", takesValue: false,
    help: "Pin metadata/selection without downloading package" },
  { long: "--keyring", dest: "keyring", takesValue: true, default: DEFAULT_KEYRING },
  { long: "--tls-only", dest: "tls_only", takesValue: false,
    help: "Explicitly waive archive signatures; receipt labels weaker trust" },
];

const DIFF_OPTIONS: OptionSpec[] = [
  HELP_OPTION,
  { long: "--debian-config", dest: "debian_config", takesValue: true, required: true },
  { long: "--output-dir", dest: "output_dir", takesValue: true, required: true },
  { long: "--policy", dest: "policy", takesValue: true, append: true,
    help: "Ordered policy fragments; defaults to common+LLVM in copied bundle" },
  { long: "--required-intent", dest: "required_intent", takesValue: true, default: null,
    help: "Audit expectations only; never silently added to policy" },
  { long: "--our-config", dest: "our_config", takesValue: true, default: null },
  { long: "--upstream-config", dest: "upstream_config", takesValue: true, default: null },
  { long: "--kernel-tree", dest: "kernel_tree", takesValue: true, default: null },
  { long: "--kernel-revision", dest: "kernel_revision", takesValue: true, default: null,
    help: "Optional caller-supplied pin for an exported source tree; recorded, not verified" },
  { long: "--work-dir", dest: "work_dir", takesValue: true, default: null },
  { long: "--toolchain", dest: "toolchain", takesValue: true, metavar: "{llvm,gcc}",
    choices: ["llvm", "gcc"], default: "llvm" },
];

const COMMANDS: { name: string; help: string; options: OptionSpec[] }[] = [
  { name: "fetch", help: "Retrieve latest or replay a pinned receipt", options: FETCH_OPTIONS },
  {
    name: "diff",
    help: "Audit declared policy; optionally evaluate layers in a user-managed kernel tree",
    options: DIFF_OPTIONS,
  },
];

function topUsage(prog: string, width: number): string {
  const parts = ["[-h]", `{${COMMANDS.map((command) => command.name).join(",")}}`, "..."];
  return formatUsage(prog, [], parts, width);
}

function subUsage(prog: string, options: OptionSpec[], width: number): string {
  return formatUsage(prog, options.map(optionUsagePart), [], width);
}

function subHelp(prog: string, options: OptionSpec[]): string {
  const width = terminalWidth();
  const maxHelpPosition = Math.min(24, Math.max(width - 20, 4));
  const entries: HelpEntry[] = options.map((option) => ({
    invocation: optionInvocation(option), help: option.help,
  }));
  const helpPosition = Math.min(
    Math.max(0, ...entries.map((entry) => entry.invocation.length + 2)) + 2, maxHelpPosition);
  let out = subUsage(prog, options, width) + "\n\n";
  out += "\noptions:\n" + renderEntries(entries, 2, helpPosition, width);
  return out.replace(/\n{3,}/g, "\n\n").replace(/\n+$/, "") + "\n";
}

function topHelp(prog: string): string {
  const width = terminalWidth();
  const maxHelpPosition = Math.min(24, Math.max(width - 20, 4));
  // Formatter-wide action max includes the subparsers metavar and the
  // indented subaction names (name length + subaction indent of 4).
  const positionalMax = Math.max("{fetch,diff}".length + 2, ...COMMANDS.map((command) => command.name.length + 4));
  const helpPosition = Math.min(positionalMax + 2, maxHelpPosition);
  let out = topUsage(prog, width) + "\n\n";
  out += DESCRIPTION + "\n\n";
  out += "\npositional arguments:\n";
  out += "  {fetch,diff}\n";
  out += renderEntries(
    COMMANDS.map((command) => ({ invocation: command.name, help: command.help })), 4, helpPosition, width);
  out += "\noptions:\n";
  out += renderEntries([{ invocation: optionInvocation(HELP_OPTION), help: HELP_OPTION.help }], 2, helpPosition, width);
  return out.replace(/\n{3,}/g, "\n\n").replace(/\n+$/, "") + "\n";
}

function commandHelp(prog: string, command: string): string {
  const spec = COMMANDS.find((candidate) => candidate.name === command)!;
  return subHelp(`${prog} ${command}`, spec.options);
}

function fail(prog: string, message: string): never {
  process.stderr.write(`${prog}: error: ${message}\n`);
  process.exit(2);
}

function usageError(prog: string, message: string): never {
  process.stderr.write(topUsage(prog, terminalWidth()) + "\n" + `${prog}: error: ${message}\n`);
  process.exit(2);
}

function parseSubcommand(prog: string, command: string, argv: string[]): Record<string, unknown> {
  const spec = COMMANDS.find((candidate) => candidate.name === command)!;
  const subProg = `${prog} ${command}`;
  const values: Record<string, unknown> = {};
  for (const option of spec.options) {
    if (option.append) values[option.dest] = null;
    else if (option.takesValue) values[option.dest] = option.default ?? null;
    else values[option.dest] = option.default ?? false;
  }
  const extra: string[] = [];
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--") {
      extra.push(...argv.slice(index + 1));
      break;
    }
    if (argument === "-h" || argument === "--help") {
      process.stdout.write(commandHelp(prog, command));
      process.exit(0);
    }
    if (argument.startsWith("-") && argument !== "-") {
      const equals = argument.indexOf("=");
      const name = equals === -1 ? argument : argument.slice(0, equals);
      const inline = equals === -1 ? undefined : argument.slice(equals + 1);
      const option = spec.options.find((candidate) => candidate.long === name);
      if (option === undefined) fail(subProg, `unrecognized arguments: ${argument}`);
      if (!option.takesValue) {
        if (inline !== undefined) fail(subProg, `unexpected value for argument ${name}: '${inline}'`);
        values[option.dest] = true;
        continue;
      }
      const raw = inline ?? argv[++index];
      if (raw === undefined || (raw.startsWith("-") && raw !== "-")) {
        fail(subProg, `argument ${option.long}: expected one argument`);
      }
      if (option.choices !== undefined && !option.choices.includes(raw)) {
        fail(subProg, `argument ${option.long}: invalid choice: '${raw}' (choose from ${option.choices.map((choice) => `'${choice}'`).join(", ")})`);
      }
      if (option.append) {
        const existing = values[option.dest] as string[] | null;
        values[option.dest] = existing === null ? [raw] : [...existing, raw];
      } else {
        values[option.dest] = raw;
      }
    } else {
      extra.push(argument);
    }
  }
  if (extra.length > 0) fail(subProg, `unrecognized arguments: ${extra.join(" ")}`);
  const missing: string[] = [];
  for (const option of spec.options) {
    if (option.required && (values[option.dest] === null || values[option.dest] === undefined)) {
      missing.push(option.long);
    }
  }
  if (missing.length > 0) fail(subProg, `the following arguments are required: ${missing.join(", ")}`);
  return values;
}

function main(argv: string[]): void {
  const prog = basename(process.argv[1] ?? "retrieve.ts");
  if (argv.length === 0) {
    usageError(prog, "the following arguments are required: command");
  }
  const [command, ...rest] = argv;
  if (command === "-h" || command === "--help") {
    process.stdout.write(topHelp(prog));
    process.exit(0);
  }
  if (!COMMANDS.some((candidate) => candidate.name === command)) {
    usageError(prog, `argument command: invalid choice: '${command}' (choose from ${COMMANDS.map((candidate) => `'${candidate.name}'`).join(", ")})`);
  }
  const values = parseSubcommand(prog, command, rest);
  if (command === "fetch") {
    const args: FetchArgs = {
      suite: values["suite"] as FetchArgs["suite"],
      cacheDir: values["cache_dir"] as string,
      outputDir: values["output_dir"] as string,
      offline: values["offline"] === true,
      inspectOnly: values["inspect_only"] === true,
      keyring: values["keyring"] as string,
      tlsOnly: values["tls_only"] === true,
    };
    fetchCommand(args).catch((error: unknown) => {
      throw error;
    });
    return;
  }
  const requiredIntent = (values["required_intent"] as string | null) ?? join(HERE, "required-intent.config");
  const args: AuditArgs = {
    debianConfig: values["debian_config"] as string,
    outputDir: values["output_dir"] as string,
    policy: values["policy"] as string[] | null,
    requiredIntent,
    ourConfig: values["our_config"] as string | null,
    upstreamConfig: values["upstream_config"] as string | null,
    kernelTree: values["kernel_tree"] as string | null,
    kernelRevision: values["kernel_revision"] as string | null,
    workDir: values["work_dir"] as string | null,
    toolchain: values["toolchain"] as AuditArgs["toolchain"],
  };
  auditCommand(args);
}

// Run only when executed directly. The realpath comparison resolves symlinks
// so the tool also runs correctly through a symlinked invocation path.
import { realpath } from "node:fs/promises";
realpath(process.argv[1] ?? "").then((self) => {
  if (self === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
}, () => {});
