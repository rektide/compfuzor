#!/usr/bin/env -S node --strip-types
/**
 * apt-src-scheme.ts - flip the URI scheme (http <-> https) on apt source
 * URIs while maintaining JUST the URI row of each entry.
 *
 * For classic .list files the row is the `deb`/`deb-src` line (including
 * commented-out ones); for deb822 .sources files it is the `URIs:` row. Only
 * the scheme inside the URI token changes; everything else on the row (option
 * brackets, suites, comments, trailing whitespace) is preserved byte-exact.
 * file:/ cdrom:/ and other non-http(s) URIs are left alone.
 *
 * Row maintenance prefers block-in-file managed blocks: markers
 * `# apt-scheme-<n> begin` / `# apt-scheme-<n> end` are whole-line comments,
 * which apt accepts in BOTH formats -- including inside a deb822 stanza
 * (verified with `apt-get indextargets`; blank lines would split a stanza,
 * but comments do not). Wrapping an existing row ("adoption") is something
 * block-in-file cannot do, so the first flip inserts the markers surgically
 * around the old row; every later change of that row is then performed by
 * block-in-file itself. If block-in-file is unavailable or fails, the row is
 * rewritten surgically between the markers. Every write is followed by a
 * re-parse: entry count must be unchanged and every http(s) URI must carry
 * the target scheme, else the original file is restored.
 *
 * Usage:
 *   apt-src-scheme.ts --to https|http [FILE...]
 *
 * Examples:
 *   sudo apt-src-scheme.ts --to https
 *   apt-src-scheme.ts --to http /etc/apt/sources.list.d/mise.list
 */

import { spawn } from "node:child_process";
import {
  chmod,
  chown,
  lstat,
  readFile,
  readdir,
  realpath,
  stat,
  writeFile,
} from "node:fs/promises";
import { join } from "node:path";
import { parseArgs } from "node:util";
import {
  AptParseError,
  findClassicUri,
  parseClassic,
  parseDeb822,
  splitDeb822Values,
} from "./apt-src-model.ts";

const USAGE = `apt-src-scheme.ts - flip http <-> https on apt source URIs

Usage:
  apt-src-scheme.ts --to https|http [FILE...]

Options:
  --to SCHEME    target scheme: https or http (required)
  FILE...        source files (default: /etc/apt/sources.list plus
                 /etc/apt/sources.list.d/*.list and *.sources)
  --follow       edit through symlinks (they are skipped by default: a
                 linked source file is managed elsewhere, e.g. a compfuzor
                 deployment whose re-render would clobber the edit)
  --help, -h     this help

Maintains just the URI row per entry, via block-in-file managed blocks
(comment markers, legal in both formats) where possible, surgical row
rewrites otherwise. Rows already in the target scheme are not touched, so
the tool is idempotent. Re-parses each written file and restores the
original on any structural change.`;

const BEGIN_RE = /^# apt-scheme-(\d+) begin[ \t]*$/;
const END_RE = /^# apt-scheme-(\d+) end[ \t]*$/;
const PROVENANCE_RE = /^# source: /; // injected by block-in-file; a comment
const BIF = "block-in-file";

interface Row {
  lineIdx: number;
  newLine: string;
}

interface Block {
  id: number;
  begin: number;
  end: number;
  content: number[]; // line indices between markers, provenance excluded
}

function flipUri(uri: string, target: string): string | null {
  for (const scheme of ["http", "https"]) {
    if (uri.startsWith(`${scheme}://`))
      return scheme === target ? null : `${target}://${uri.slice(scheme.length + 3)}`;
  }
  return null; // file:, cdrom:, or already on the target scheme
}

function detectFormat(path: string, text: string): "classic" | "deb822" {
  if (path.endsWith(".sources")) return "deb822";
  if (path.endsWith(".list")) return "classic";
  return /^[-A-Za-z0-9]+:/m.test(text) ? "deb822" : "classic";
}

/** rows whose text changes: replace the whole line, scheme included */
function planRows(lines: string[], fmt: "classic" | "deb822", target: string): Row[] {
  const rows: Row[] = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!;
    if (fmt === "classic") {
      const tok = findClassicUri(line);
      if (!tok) continue;
      const flipped = flipUri(tok.text, target);
      if (flipped === null) continue;
      rows.push({
        lineIdx: i,
        newLine: line.slice(0, tok.start) + flipped + line.slice(tok.end),
      });
    } else {
      const m = line.match(/^(URIs:)[ \t]?(.*)$/);
      if (!m) continue;
      const vals = splitDeb822Values(m[2]!);
      if (!vals.some((v) => flipUri(v, target) !== null)) continue;
      rows.push({
        lineIdx: i,
        newLine: `URIs: ${vals.map((v) => flipUri(v, target) ?? v).join(" ")}`,
      });
    }
  }
  return rows;
}

/** find existing managed blocks; throws on unbalanced markers */
function scanBlocks(lines: string[]): Block[] {
  const blocks: Block[] = [];
  let open: { id: number; begin: number } | null = null;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!;
    const b = line.match(BEGIN_RE);
    if (b) {
      if (open) throw new Error(`nested '# apt-scheme-${b[1]} begin' at line ${i + 1}`);
      open = { id: Number(b[1]), begin: i };
      continue;
    }
    const e = line.match(END_RE);
    if (e) {
      if (!open || open.id !== Number(e[1]))
        throw new Error(`unmatched '# apt-scheme-${e[1]} end' at line ${i + 1}`);
      const content: number[] = [];
      for (let j = open.begin + 1; j < i; j++) if (!PROVENANCE_RE.test(lines[j]!)) content.push(j);
      blocks.push({ id: open.id, begin: open.begin, end: i, content });
      open = null;
    }
  }
  if (open)
    throw new Error(`'# apt-scheme-${open.id} begin' at line ${open.begin + 1} has no end marker`);
  return blocks;
}

function verify(
  text: string,
  fmt: "classic" | "deb822",
  target: string,
  expectedCount: number,
): string | null {
  let json;
  try {
    json = fmt === "deb822" ? parseDeb822(text) : parseClassic(text);
  } catch (err) {
    return `re-parse failed: ${(err as Error).message}`;
  }
  if (json.sources.length !== expectedCount)
    return `entry count changed ${expectedCount} -> ${json.sources.length}`;
  for (const e of json.sources)
    for (const u of e.uris)
      if (/^https?:\/\//.test(u) && !u.startsWith(`${target}://`))
        return `URI '${u}' is not ${target}`;
  return null;
}

function bifUpdate(path: string, id: number, content: string): Promise<boolean> {
  const args = [
    path,
    "--name",
    `apt-scheme-${id}`,
    "--comment",
    "#",
    "--marker-start",
    "begin",
    "--marker-end",
    "end",
    "--mode",
    "ensure",
    "--source-label",
    SOURCE_LABEL,
  ];
  return new Promise((resolve) => {
    const child = spawn(BIF, args, { stdio: ["pipe", "ignore", "pipe"] });
    child.on("error", () => resolve(false)); // e.g. ENOENT: BIF not installed
    child.on("close", (code) => resolve(code === 0));
    child.stdin.on("error", () => {}); // EPIPE if BIF exits before reading
    child.stdin.end(content + "\n");
  });
}

/** Provenance label BIF stamps as `# source: <text>` on rows we manage --
 *  BIF's README recommends a path identifying the managing source. */
const SOURCE_LABEL = "files/apt-srctools/apt-src-scheme.ts";

async function defaultFiles(): Promise<string[]> {
  const out: string[] = [];
  try {
    await stat("/etc/apt/sources.list");
    out.push("/etc/apt/sources.list");
  } catch {
    /* absent: fine */
  }
  try {
    for (const ent of (await readdir("/etc/apt/sources.list.d")).sort())
      if (ent.endsWith(".list") || ent.endsWith(".sources"))
        out.push(join("/etc/apt/sources.list.d", ent));
  } catch {
    /* absent: fine */
  }
  return out;
}

/** splice rows (+ optional marker wraps) into a fresh file text */
function render(
  lines: string[],
  rows: Row[],
  adopt: Map<number, number>, // lineIdx -> new block id
): string {
  const byLine = new Map(rows.map((r) => [r.lineIdx, r]));
  const out: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const id = adopt.get(i);
    if (id !== undefined) {
      out.push(`# apt-scheme-${id} begin`);
      out.push(byLine.get(i)!.newLine);
      out.push(`# apt-scheme-${id} end`);
      continue;
    }
    out.push(byLine.has(i) ? byLine.get(i)!.newLine : lines[i]!);
  }
  return out.join("\n");
}

/** processFile mutates system config; every writer below (our writeFile and
 *  block-in-file's temp-file+rename alike) derives new-file mode from the
 *  invoking umask -- under a root shell with umask 077 that silently turns
 *  0644 sources into 0600 and breaks unprivileged readers (apt itself, and
 *  any user-side tooling). Preserve the pre-edit stat: mode always, owner
 *  when running as root. This is tool-side belt-and-braces until
 *  block-in-file itself preserves modes on managed edits. */
async function processFile(path: string, target: string): Promise<string | null> {
  const st = await stat(path);
  try {
    return await processFileInner(path, target);
  } finally {
    const current = await stat(path);
    const root = typeof process.geteuid === "function" && process.geteuid() === 0;
    const ownershipChanged = root && (current.uid !== st.uid || current.gid !== st.gid);
    if (ownershipChanged) {
      await chown(path, st.uid, st.gid);
    }
    // chown can clear setuid/setgid bits, so restore mode after ownership.
    if (ownershipChanged || (current.mode & 0o7777) !== (st.mode & 0o7777)) {
      await chmod(path, st.mode & 0o7777);
    }
  }
}

async function processFileInner(path: string, target: string): Promise<string | null> {
  const original = await readFile(path, "utf8");
  const fmt = detectFormat(path, original);
  let expectedCount: number;
  try {
    const json = fmt === "deb822" ? parseDeb822(original) : parseClassic(original);
    expectedCount = json.sources.length;
  } catch (err) {
    if (err instanceof AptParseError) throw new Error(err.message);
    throw err;
  }

  const lines = original.split("\n");
  const rows = planRows(lines, fmt, target);
  if (rows.length === 0) return null; // nothing to flip

  const blocks = scanBlocks(lines); // throws on unbalanced markers
  const nextId = blocks.reduce((m, b) => Math.max(m, b.id), 0) + 1;

  // adoption: changed rows that live in no managed block yet
  const adopt = new Map<number, number>();
  let id = nextId;
  const singleContent = new Map<number, number>(); // row lineIdx -> block id
  for (const b of blocks) if (b.content.length === 1) singleContent.set(b.content[0]!, b.id);
  for (const r of rows) if (!singleContent.has(r.lineIdx)) adopt.set(r.lineIdx, id++);

  const viaBif: Array<{ id: number; content: string }> = [];
  for (const r of rows) {
    const blockId = singleContent.get(r.lineIdx) ?? adopt.get(r.lineIdx);
    if (blockId !== undefined) viaBif.push({ id: blockId, content: r.newLine });
  }

  const finish = async (text: string): Promise<void> => {
    const problem = verify(text, fmt, target, expectedCount);
    if (problem) {
      await writeFile(path, original, "utf8");
      throw new Error(`verification failed (${problem}); original restored`);
    }
    await writeFile(path, text, "utf8");
  };

  // Preferred path: adopt surgically (markers around the OLD row), then let
  // block-in-file perform every row change. Rows wrapped by hand into
  // multi-content blocks fall back to the surgical rewrite below.
  const surgicalText = render(lines, rows, adopt);
  const multiContentBlocked = rows.some(
    (r) =>
      !adopt.has(r.lineIdx) &&
      !singleContent.has(r.lineIdx) &&
      blocks.some((b) => b.begin < r.lineIdx && r.lineIdx < b.end),
  );
  if (!multiContentBlocked && viaBif.length > 0) {
    // step 1: markers around old row content (no semantic change yet)
    const adoptionOnly = render(
      lines,
      rows.map((r) => ({ ...r, newLine: lines[r.lineIdx]! })),
      adopt,
    );
    await writeFile(path, adoptionOnly, "utf8");
    // step 2: block-in-file swaps each row content
    let bifOk = true;
    for (const b of viaBif) {
      if (!(await bifUpdate(path, b.id, b.content))) {
        bifOk = false;
        break;
      }
    }
    if (bifOk) {
      const after = await readFile(path, "utf8");
      const problem = verify(after, fmt, target, expectedCount);
      if (!problem) {
        return (
          `${path}: flipped ${rows.length} URI row(s) to ${target} ` +
          `(${viaBif.length} via block-in-file, ${adopt.size} adopted)`
        );
      }
      console.warn(`warn: ${path}: block-in-file path failed verification; retrying surgically`);
      await writeFile(path, original, "utf8");
      // fall through to surgical
    }
  }

  await finish(surgicalText);
  return `${path}: flipped ${rows.length} URI row(s) to ${target} (surgical)`;
}

async function main(): Promise<number> {
  const args = parseArgs({
    allowPositionals: true,
    options: {
      to: { type: "string" },
      follow: { type: "boolean" },
      help: { type: "boolean", short: "h" },
    },
  });
  if (args.values.help) {
    console.log(USAGE);
    process.exit(0);
  }
  if (args.values.to !== "https" && args.values.to !== "http") {
    console.error(`error: --to must be 'https' or 'http', not '${args.values.to ?? ""}'`);
    process.exit(2);
  }
  const target = args.values.to;

  const files = args.positionals.length ? args.positionals : await defaultFiles();
  if (files.length === 0) {
    console.error("error: no source files found (default set is empty; pass FILE...)");
    return 1;
  }

  let failures = 0;
  for (const path of files) {
    try {
      // lstat, not stat: see through the link rather than to the target, so
      // compfuzor-managed symlinks are not silently edited behind their
      // playbook (a re-render would clobber the change).
      const stat_ = await lstat(path);
      if (stat_.isSymbolicLink() && !args.values.follow) {
        console.warn(`skip: ${path} is a symlink (managed elsewhere; --follow to edit through it)`);
        continue;
      }
      if (!stat_.isFile() && !stat_.isSymbolicLink()) {
        console.warn(`skip: ${path} is not a regular file`);
        continue;
      }
      // --follow must edit the referent, not the link: block-in-file's
      // atomic write (temp + rename) would REPLACE the symlink with a
      // regular file while the surgical adoption wrote through it --
      // a split-brain stale-target + destroyed-link outcome.
      const filePath = stat_.isSymbolicLink() ? await realpath(path) : path;
      const msg = await processFile(filePath, target);
      if (msg === null) console.log(`${path}: no flippable URIs (already ${target} or non-http)`);
      else console.log(msg);
    } catch (err) {
      console.error(`error: ${path}: ${(err as Error).message}`);
      failures++;
    }
  }
  return failures ? 1 : 0;
}

const code = await main();
process.exitCode = code;
