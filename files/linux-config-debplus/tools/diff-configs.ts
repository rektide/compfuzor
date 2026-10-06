#!/usr/bin/env node
// Compare two kernel configuration files and print their symbol differences.
//
// Output matches the bundle's recorded layer diffs: one "SYMBOL: old -> new"
// line per difference and nothing else. Inputs may be plain text or .xz
// compressed files; "-" reads standard input (compressed input there is
// detected by its magic bytes). The exit status is 0 whether or not symbols
// differ, and non-zero only for usage or input errors.
//
// Toolchain version/identity symbols are excluded by default: Kconfig records
// them at normalize time, so they describe the invoking machine, not policy.

import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { basename } from "node:path";

const DESCRIPTION = `Compare two kernel configuration files and print their symbol differences.

Output matches the bundle's recorded layer diffs: one "SYMBOL: old -> new"
line per difference and nothing else. Inputs may be plain text or .xz
compressed files; "-" reads standard input (compressed input there is
detected by its magic bytes). The exit status is 0 whether or not symbols
differ, and non-zero only for usage or input errors.

Toolchain version/identity symbols are excluded by default: Kconfig records
them at normalize time, so they describe the invoking machine, not policy.`;

// Same toolchain-metadata symbol family as debian/retrieve.ts's METADATA
// pattern (compiler/tool version probes). The regex is deliberately
// duplicated rather than imported so this tool stays standalone when the
// bundle directory is copied out of the repository.
const METADATA = /^(CC_VERSION_TEXT|CC_IS_.*|GCC_VERSION|CLANG_VERSION|AS_IS_.*|AS_VERSION|LD_IS_.*|LD_VERSION|LLD_VERSION|RUSTC_VERSION.*|RUSTC_LLVM_VERSION|PAHOLE_VERSION|TOOLS_SUPPORT_.*)$/;

// Python's re \w is Unicode-aware: letters, digits, underscore.
const CONFIG_SET = /^CONFIG_([\p{L}\p{N}_]+)=(.*)$/u;
const CONFIG_NOT_SET = /^# CONFIG_([\p{L}\p{N}_]+) is not set$/u;

const XZ_MAGIC = Buffer.from([0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00]);
const SUBPROCESS_BUFFER = 1 << 30;

/** Map symbol name to value; "# CONFIG_X is not set" becomes "n". */
export function parseConfig(text: string): Map<string, string> {
  const values = new Map<string, string>();
  for (const line of text.split("\n")) {
    const match = CONFIG_SET.exec(line);
    if (match) {
      values.set(match[1], match[2]);
    } else {
      const unset = CONFIG_NOT_SET.exec(line);
      if (unset) values.set(unset[1], "n");
    }
  }
  return values;
}

/** Python pathlib suffix: empty for dotfiles, else ".ext" from the last dot. */
export function pythonSuffix(location: string): string {
  const name = basename(location);
  const dot = name.lastIndexOf(".");
  return dot > 0 ? name.slice(dot) : "";
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

/**
 * Decompress an xz payload through the system `xz` binary. Node's zlib has
 * no lzma support, and xz created every compressed artifact in this bundle.
 */
export function xzDecompress(data: Buffer): Buffer {
  const result = spawnSync("xz", ["-dc"], { input: data, maxBuffer: SUBPROCESS_BUFFER });
  if (result.error) throw result.error;
  if (result.status !== 0) throw lzmaError(result.stderr);
  return result.stdout;
}

/** Compress with the parameters of Python's lzma.compress defaults (preset 6). */
export function xzCompress(data: Buffer): Buffer {
  const result = spawnSync("xz", ["-z", "-c", "-6", "-C", "crc64", "-T1"], {
    input: data, maxBuffer: SUBPROCESS_BUFFER,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw lzmaError(result.stderr);
  return result.stdout;
}

/** Reproduce Python's OSError rendering for the common errno cases. */
export function pythonOSError(error: NodeJS.ErrnoException): Error {
  const table: Record<string, [number, string]> = {
    ENOENT: [2, "No such file or directory"],
    EACCES: [13, "Permission denied"],
    EISDIR: [21, "Is a directory"],
    ENOTDIR: [20, "Not a directory"],
    ELOOP: [40, "Too many levels of symbolic links"],
    ENAMETOOLONG: [36, "File name too long"],
  };
  const known = error.code ? table[error.code] : undefined;
  if (known) return new Error(`[Errno ${known[0]}] ${known[1]}: '${error.path ?? ""}'`);
  return new Error(error.message);
}

/** Strict UTF-8 decode with Python's UnicodeDecodeError message shape. */
export function decodeUtf8Strict(data: Buffer): string {
  const invalid = utf8InvalidPosition(data);
  if (invalid !== null) {
    const [position, reason] = invalid;
    throw new Error(
      `'utf-8' codec can't decode byte 0x${data[position].toString(16).padStart(2, "0")} in position ${position}: ${reason}`);
  }
  return data.toString("utf8");
}

function utf8InvalidPosition(data: Buffer): [number, string] | null {
  for (let i = 0; i < data.length; ) {
    const byte = data[i];
    if (byte < 0x80) {
      i += 1;
      continue;
    }
    let length = 0;
    let low = 0x80;
    let high = 0xbf;
    if (byte >= 0xc2 && byte <= 0xdf) {
      length = 2;
    } else if (byte === 0xe0) {
      length = 3;
      low = 0xa0;
    } else if ((byte >= 0xe1 && byte <= 0xec) || byte === 0xee || byte === 0xef) {
      length = 3;
    } else if (byte === 0xed) {
      length = 3;
      high = 0x9f;
    } else if (byte === 0xf0) {
      length = 4;
      low = 0x90;
    } else if (byte >= 0xf1 && byte <= 0xf3) {
      length = 4;
    } else if (byte === 0xf4) {
      length = 4;
      high = 0x8f;
    } else {
      return [i, "invalid start byte"];
    }
    for (let offset = 1; offset < length; offset += 1) {
      const limit = offset === 1 ? high : 0xbf;
      const floor = offset === 1 ? low : 0x80;
      const continuation = data[i + offset];
      if (continuation === undefined) return [i, "unexpected end of data"];
      if (continuation < floor || continuation > limit) return [i + offset, "invalid continuation byte"];
    }
    i += length;
  }
  return null;
}

function readLocation(location: string): Buffer {
  if (location === "-") {
    const data = readFileSync(0);
    return data.subarray(0, 6).equals(XZ_MAGIC) ? xzDecompress(data) : data;
  }
  const data = readFileSync(location);
  return pythonSuffix(location) === ".xz" ? xzDecompress(data) : data;
}

/** Read a config from a path (".xz" honored by suffix) or stdin ("-"). */
export function configBytes(location: string): Buffer {
  try {
    return readLocation(location);
  } catch (error) {
    if (error instanceof Error && (error as NodeJS.ErrnoException).code !== undefined) {
      throw pythonOSError(error as NodeJS.ErrnoException);
    }
    throw error;
  }
}

export function compareStrings(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

/** Sorted "SYMBOL: old -> new" lines, restricted to keys when given. */
export function delta(
  before: Map<string, string>,
  after: Map<string, string>,
  keys: Iterable<string> | null = null,
  excludeMetadata = true,
): string[] {
  const symbols = keys ?? new Set([...before.keys(), ...after.keys()]);
  const lines: string[] = [];
  for (const symbol of [...symbols].sort(compareStrings)) {
    if (excludeMetadata && METADATA.test(symbol)) continue;
    const old = before.get(symbol) ?? "<absent>";
    const updated = after.get(symbol) ?? "<absent>";
    if (old !== updated) lines.push(`${symbol}: ${old} -> ${updated}`);
  }
  return lines;
}

// ---------------------------------------------------------------------------
// Minimal CLI layer reproducing Python argparse's rendered output for this
// tool's fixed surface (usage, help, and error messages).
// ---------------------------------------------------------------------------

export interface OptionSpec {
  long: string;
  short?: string;
  dest: string;
  takesValue: boolean;
  metavar?: string;
  help?: string;
  required?: boolean;
}

export interface PositionalSpec {
  name: string;
  help?: string;
}

export function terminalWidth(): number {
  const columns = process.env.COLUMNS;
  if (columns !== undefined && /^\d+$/.test(columns)) return Math.max(parseInt(columns, 10), 1) - 2;
  return (process.stdout.columns ?? 80) - 2;
}

/** textwrap.wrap defaults: chunks keep their separators; hyphen boundaries are
 * break points; greedy fill per line; long words hard-split at line width. */
export function wrapText(text: string, width: number): string[] {
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

export function optionInvocation(option: OptionSpec): string {
  const strings = option.short !== undefined ? `${option.short}, ${option.long}` : option.long;
  return option.takesValue ? `${strings} ${option.metavar ?? option.dest.toUpperCase()}` : strings;
}

function optionUsagePart(option: OptionSpec): string {
  const strings = option.short !== undefined ? option.short : option.long;
  if (!option.takesValue) return option.required ? strings : `[${strings}]`;
  const metavar = option.metavar ?? option.dest.toUpperCase();
  return option.required ? `${strings} ${metavar}` : `[${strings} ${metavar}]`;
}

/** argparse's _format_usage: part-based greedy wrap, prog leading the first line. */
export function formatUsage(prog: string, optParts: string[], posParts: string[], width: number): string {
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

export interface HelpEntry {
  invocation: string;
  help?: string;
}

export function renderHelpEntries(
  entries: HelpEntry[], indent: number, helpPosition: number, width: number,
): string {
  const actionWidth = helpPosition - indent - 2;
  const helpWidth = Math.max(width - helpPosition, 11);
  return entries.map((entry) => {
    const pad = " ".repeat(indent);
    if (!entry.help) return `${pad}${entry.invocation}\n`;
    const helpLines = wrapText(entry.help.replace(/\s+/g, " ").trim(), helpWidth);
    if (entry.invocation.length <= actionWidth) {
      const header = pad + entry.invocation.padEnd(actionWidth) + "  ";
      return header + helpLines.join("\n" + " ".repeat(helpPosition)) + "\n";
    }
    return `${pad}${entry.invocation}\n` +
      helpLines.map((line) => " ".repeat(helpPosition) + line).join("\n") + "\n";
  }).join("");
}

export function helpPositionFor(entries: HelpEntry[]): number {
  const width = terminalWidth();
  const maxHelpPosition = Math.min(24, Math.max(width - 20, 4));
  const actionMaxLength = Math.max(0, ...entries.map((entry) => entry.invocation.length + 2));
  return Math.min(actionMaxLength + 2, maxHelpPosition);
}

const OPTIONS: OptionSpec[] = [
  { long: "--help", short: "-h", dest: "help", takesValue: false, help: "show this help message and exit" },
  { long: "--include-metadata", dest: "include_metadata", takesValue: false,
    help: "also report toolchain version/identity symbols" },
  { long: "--keys-from", dest: "keys_from", takesValue: true, metavar: "PATH",
    help: "only compare symbols declared in this policy fragment" },
  { long: "--quiet", dest: "quiet", takesValue: false, help: "print only the number of differences" },
];

const POSITIONALS: PositionalSpec[] = [
  { name: "old", help: "old configuration file, or - for stdin" },
  { name: "new", help: "new configuration file, or - for stdin" },
];

function usageWithHelp(prog: string): string {
  return formatUsage(prog, OPTIONS.map(optionUsagePart), POSITIONALS.map((p) => p.name), terminalWidth());
}

function buildHelp(prog: string): string {
  const width = terminalWidth();
  const positionalEntries = POSITIONALS.map((entry) => ({ invocation: entry.name, help: entry.help }));
  const optionEntries = OPTIONS.map((option) => ({
    invocation: optionInvocation(option), help: option.help,
  }));
  const helpPosition = Math.max(helpPositionFor(positionalEntries), helpPositionFor(optionEntries));
  let out = usageWithHelp(prog) + "\n\n";
  out += DESCRIPTION + "\n\n";
  out += "\npositional arguments:\n" + renderHelpEntries(positionalEntries, 2, helpPosition, width);
  out += "\noptions:\n" + renderHelpEntries(optionEntries, 2, helpPosition, width);
  return out.replace(/\n{3,}/g, "\n\n").replace(/\n+$/, "") + "\n";
}

function fail(prog: string, message: string): never {
  process.stderr.write(usageWithHelp(prog) + "\n" + `${prog}: error: ${message}\n`);
  process.exit(2);
}

interface Arguments {
  old: string;
  new: string;
  includeMetadata: boolean;
  keysFrom: string | null;
  quiet: boolean;
}

function parseArguments(prog: string, argv: string[]): Arguments {
  const result: Arguments = { old: "", new: "", includeMetadata: false, keysFrom: null, quiet: false };
  const positional: string[] = [];
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--") {
      positional.push(...argv.slice(index + 1));
      break;
    }
    if (argument === "-h" || argument === "--help") {
      process.stdout.write(buildHelp(prog));
      process.exit(0);
    }
    if (argument.startsWith("-") && argument !== "-") {
      const equals = argument.indexOf("=");
      const name = equals === -1 ? argument : argument.slice(0, equals);
      const inline = equals === -1 ? undefined : argument.slice(equals + 1);
      if (name === "--include-metadata" || name === "--quiet") {
        if (inline !== undefined) fail(prog, `unexpected value for argument ${name}: '${inline}'`);
        if (name === "--include-metadata") result.includeMetadata = true;
        else result.quiet = true;
      } else if (name === "--keys-from") {
        const value = inline ?? argv[index + 1];
        if (value === undefined || (value.startsWith("-") && value !== "-")) {
          fail(prog, "argument --keys-from: expected one argument");
        }
        index += 1;
        result.keysFrom = value;
      } else {
        fail(prog, `unrecognized arguments: ${argument}`);
      }
    } else {
      positional.push(argument);
    }
  }
  if (positional.length > 2) fail(prog, `unrecognized arguments: ${positional.slice(2).join(" ")}`);
  const missing: string[] = [];
  if (positional.length < 1) missing.push("old");
  if (positional.length < 2) missing.push("new");
  if (missing.length > 0) fail(prog, `the following arguments are required: ${missing.join(", ")}`);
  result.old = positional[0];
  result.new = positional[1];
  return result;
}

function main(argv: string[]): number {
  const prog = basename(process.argv[1] ?? "diff-configs.ts");
  const args = parseArguments(prog, argv);
  try {
    const before = parseConfig(decodeUtf8Strict(configBytes(args.old)));
    const after = parseConfig(decodeUtf8Strict(configBytes(args.new)));
    const keys = args.keysFrom !== null
      ? parseConfig(decodeUtf8Strict(configBytes(args.keysFrom))).keys()
      : null;
    const lines = delta(before, after, keys, !args.includeMetadata);
    if (args.quiet) {
      process.stdout.write(`${lines.length}\n`);
    } else {
      for (const line of lines) process.stdout.write(`${line}\n`);
    }
  } catch (error) {
    process.stderr.write(`diff-configs: ${error instanceof Error ? error.message : error}\n`);
    process.exit(2);
  }
  return 0;
}

// Run only when executed directly. The realpath comparison resolves symlinks
// so the tool also runs correctly through a symlinked invocation path.
import { realpath } from "node:fs/promises";
import { fileURLToPath } from "node:url";
realpath(process.argv[1] ?? "").then((self) => {
  if (self === fileURLToPath(import.meta.url)) process.exit(main(process.argv.slice(2)));
}, () => {});
