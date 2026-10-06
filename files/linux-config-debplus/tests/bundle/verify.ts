#!/usr/bin/env node
// Verify a rendered linux-config-debplus stage against the bundle's receipts.
//
// Maintenance tool, not part of any automatic test run. From a repository
// checkout the playbook declaring the bundle is discovered above this script,
// so only the stage is needed:
//
//     node files/linux-config-debplus/tests/bundle/verify.ts --stage .test-agent/<domain>/stage
//
// Checks performed: every declared FILES entry exists in the stage,
// byte-identical to the controller input, with the declared mode; the set of
// repository-tracked material files equals the declared set; no __pycache__
// leaked into the stage; the compression registry in
// baselines/7.1/validation.json matches compressed and decompressed hashes of
// its artifacts; every debian snapshots audit.json output_sha256 entry matches
// the file next to it; and relative markdown links in bundled README files
// resolve.
//
// From a deployed bundle copy (no linux-config-debplus.src.pb above this
// script) the declaration, mode, and tracked-set checks are skipped with a
// note; receipt and link checks still run. Exits non-zero when any performed
// check fails.
//
// Ported from verify.py with identical observable behavior (messages, exit
// codes). xz artifacts decompress through the system xz binary.

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync, realpathSync, statSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const DESCRIPTION = `Verify a rendered linux-config-debplus stage against the bundle's receipts.

Maintenance tool, not part of any automatic test run. From a repository
checkout the playbook declaring the bundle is discovered above this script,
so only the stage is needed:

    node files/linux-config-debplus/tests/bundle/verify.ts --stage .test-agent/<domain>/stage

Checks performed: every declared FILES entry exists in the stage,
byte-identical to the controller input, with the declared mode; the set of
repository-tracked material files equals the declared set; no __pycache__
leaked into the stage; the compression registry in
baselines/7.1/validation.json matches compressed and decompressed hashes of
its artifacts; every debian snapshots audit.json output_sha256 entry matches
the file next to it; and relative markdown links in bundled README files
resolve.

From a deployed bundle copy (no linux-config-debplus.src.pb above this
script) the declaration, mode, and tracked-set checks are skipped with a
note; receipt and link checks still run. Exits non-zero when any performed
check fails.`;

const HERE = dirname(fileURLToPath(import.meta.url));               // .../tests/bundle
const BUNDLE = resolve(HERE, "..", "..");                           // controller tree or deployed copy
const PLAYBOOK_NAME = "linux-config-debplus.src.pb";
const CONTROLLER_PREFIX = "files/linux-config-debplus/";
const SUBPROCESS_BUFFER = 1 << 30;

function digest(data: Buffer): string {
  return createHash("sha256").update(data).digest("hex");
}

/** Decompress an xz payload through the system xz binary (no Node lzma). */
function xzDecompress(data: Buffer): Buffer {
  const result = spawnSync("xz", ["-dc"], { input: data, maxBuffer: SUBPROCESS_BUFFER });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`xz -dc failed with status ${result.status}: ${result.stderr.toString()}`);
  }
  return result.stdout;
}

function findPlaybook(): string | null {
  let directory = HERE;
  for (;;) {
    const candidate = join(directory, PLAYBOOK_NAME);
    if (existsSync(candidate) && statSync(candidate).isFile()) return candidate;
    const parent = dirname(directory);
    if (parent === directory) return null;
    directory = parent;
  }
}

/**
 * Read the playbook's FILES rows without a YAML dependency.
 *
 * Every declared row has the same three-line shape (name / copyDir: True /
 * mode); matching it directly keeps this tool stdlib-only so it also runs
 * from a deployed copy of the bundle.
 */
export function parseFilesEntries(text: string): [string, string][] {
  const pattern = /^[ \t]*-[ \t]+name:[ \t]*(\S+)[ \t]*$\n^[ \t]*copyDir:[ \t]*True[ \t]*$\n^[ \t]*mode:[ \t]*"(\d{4})"[ \t]*$/gm;
  return [...text.matchAll(pattern)].map((match) => [match[1], match[2]]);
}

export function playbookType(text: string): string | null {
  const match = /^\s*TYPE:[ \t]*(\S+)/m.exec(text);
  return match !== null ? match[1] : null;
}

/** Bundle-relative names of tracked material files, or null without a repo. */
export function trackedMaterialFiles(playbookDir: string, bundleName: string): Set<string> | null {
  const repoRelative = join("files", bundleName);
  for (const command of [
    ["git", "ls-files", repoRelative],
    ["jj", "file", "list", repoRelative],
  ] as [string, string, string, string][]) {
    const result = spawnSync(command[0], command.slice(1), { cwd: playbookDir, encoding: "utf8", maxBuffer: 1 << 26 });
    if (result.status === 0) {
      const tracked = new Set<string>();
      for (const line of result.stdout.split("\n")) {
        if (line.trim() === "") continue;
        if (!line.startsWith(`${repoRelative}/`)) {
          throw new Error(`ValueError: '${line}' is not in the subpath of '${repoRelative}'`);
        }
        tracked.add(line.slice(repoRelative.length + 1));
      }
      return tracked;
    }
  }
  return null;
}

function relativePaths(root: string, name: string): string[] {
  const found: string[] = [];
  const walk = (directory: string, prefix: string): void => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const entryPath = join(directory, entry.name);
      const relative = prefix === "" ? entry.name : `${prefix}/${entry.name}`;
      if (entry.name === name) found.push(relative);
      if (entry.isDirectory()) walk(entryPath, relative);
    }
  };
  walk(root, "");
  return found;
}

/** Python repr of a sorted string list: ['a', 'b']. */
function pythonReprList(items: string[]): string {
  return `['${items.join("', '")}']`;
}

export interface VerifyResult {
  failures: string[];
  notes: string[];
}

export function verify(stage: string, playbook: string | null): VerifyResult {
  const failures: string[] = [];
  const notes: string[] = [];
  const check = (condition: boolean, message: string): boolean => {
    if (!condition) failures.push(message);
    return condition;
  };

  // Declared files: presence, byte identity, and mode in the stage.
  let entries: [string, string][] | null = null;
  if (playbook === null) {
    notes.push("no playbook found above this script; declared byte/mode/tracked-set checks skipped");
  } else {
    entries = parseFilesEntries(readFileSync(playbook, "utf8"));
    const names = entries.map(([name]) => name);
    check(new Set(names).size === names.length, "duplicate FILES declarations");
    for (const [name, mode] of entries) {
      const source = join(BUNDLE, name);
      const rendered = join(stage, name);
      if (!(check(isFile(source), `controller input missing: ${name}`) &&
            check(isFile(rendered), `stage file missing: ${name}`))) {
        continue;
      }
      check(readFileSync(source).equals(readFileSync(rendered)), `content differs from controller input: ${name}`);
      check((statSync(rendered).mode & 0o777) === parseInt(mode, 8), `mode differs from declaration: ${name}`);
    }
    const tracked = trackedMaterialFiles(dirname(playbook), playbookType(readFileSync(playbook, "utf8")) ?? basename(BUNDLE));
    if (tracked === null) {
      notes.push("no usable git/jj repository above the playbook; tracked-set check skipped");
    } else {
      const declared = new Set(names);
      const difference = [...new Set([...tracked, ...declared])].filter(
        (name) => tracked.has(name) !== declared.has(name)).sort();
      check(difference.length === 0,
        `tracked material files and declarations differ: ${pythonReprList(difference)}`);
    }
  }

  // The render must not carry Python bytecode caches.
  const leaked = relativePaths(stage, "__pycache__");
  check(leaked.length === 0, `__pycache__ leaked into the stage: ${pythonReprList(leaked)}`);

  // Compression registry: compressed and decompressed hashes and sizes.
  const registryPath = join(BUNDLE, "baselines/7.1/validation.json");
  if (check(isFile(registryPath), "compression registry missing")) {
    const registry = JSON.parse(readFileSync(registryPath, "utf8"));
    for (const key of Object.keys(registry["compression"]["artifacts"])) {
      const item = registry["compression"]["artifacts"][key];
      const recorded: string = item["path"];
      const artifact = recorded.startsWith(CONTROLLER_PREFIX)
        ? join(BUNDLE, recorded.slice(CONTROLLER_PREFIX.length))
        : playbook !== null ? join(dirname(playbook), recorded) : null;
      if (!(artifact !== null && check(isFile(artifact), `registry artifact missing: ${key}`))) {
        notes.push(`registry artifact not present here: ${key}`);
        continue;
      }
      const encoded = readFileSync(artifact);
      check(digest(encoded) === item["sha256"], `compressed hash differs: ${key}`);
      const decoded = xzDecompress(encoded);
      check(digest(decoded) === item["plaintext_sha256"], `decompressed hash differs: ${key}`);
      check(encoded.length === item["xz_bytes"], `compressed size differs: ${key}`);
      check(decoded.length === item["plaintext_bytes"], `decompressed size differs: ${key}`);
    }
  }

  // Saved audit receipts: every recorded output hash matches the file next
  // to the audit.json that recorded it.
  for (const relative of sortedAuditPaths()) {
    const auditPath = join(BUNDLE, relative);
    const audit = JSON.parse(readFileSync(auditPath, "utf8"));
    for (const name of Object.keys(audit["output_sha256"] ?? {})) {
      const expected = audit["output_sha256"][name];
      const output = join(dirname(auditPath), name);
      const label = relativePathWithin(BUNDLE, output);
      if (check(isFile(output), `audited output missing: ${label}`)) {
        check(digest(readFileSync(output)) === expected, `audited output hash differs: ${label}`);
      }
    }
  }

  // Relative markdown links inside bundled README files must resolve.
  const broken: string[] = [];
  for (const readmeRelative of relativePaths(BUNDLE, "README.md")) {
    const readme = join(BUNDLE, readmeRelative);
    const text = readFileSync(readme, "utf8");
    for (const match of text.matchAll(/\]\(([^)]+)\)/g)) {
      const target = match[1];
      if (target.startsWith("https://") || target.startsWith("http://") ||
          target.startsWith("/") || target.startsWith("#")) {
        continue;
      }
      const path = target.split("#")[0];
      if (path !== "" && !existsSync(join(dirname(readme), path))) {
        broken.push(`${readmeRelative} -> ${target}`);
      }
    }
  }
  check(broken.length === 0, `broken README links: ${pythonReprList(broken)}`);
  return { failures, notes };
}

function isFile(path: string): boolean {
  return existsSync(path) && statSync(path).isFile();
}

function sortedAuditPaths(): string[] {
  const root = join(BUNDLE, "debian", "snapshots");
  if (!existsSync(root)) return [];
  return relativePaths(root, "audit.json")
    .map((relative) => `debian/snapshots/${relative}`)
    .sort();
}

function relativePathWithin(bundle: string, output: string): string {
  return output.startsWith(`${bundle}/`) ? output.slice(bundle.length + 1) : output;
}

// ---------------------------------------------------------------------------
// Minimal CLI layer reproducing Python argparse's rendered output.
// ---------------------------------------------------------------------------

function terminalWidth(): number {
  const columns = process.env.COLUMNS;
  if (columns !== undefined && /^\d+$/.test(columns)) return Math.max(parseInt(columns, 10), 1) - 2;
  return (process.stdout.columns ?? 80) - 2;
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

interface OptionSpec {
  long: string;
  short?: string;
  dest: string;
  takesValue: boolean;
  help?: string;
  required?: boolean;
}

const OPTIONS: OptionSpec[] = [
  { long: "--help", short: "-h", dest: "help", takesValue: false, help: "show this help message and exit" },
  { long: "--stage", dest: "stage", takesValue: true, required: true,
    help: "rendered bundle directory to verify" },
  { long: "--playbook", dest: "playbook", takesValue: true,
    help: "playbook declaring the bundle (default: search parent directories of this script)" },
];

function invocation(option: OptionSpec): string {
  const strings = option.short !== undefined ? `${option.short}, ${option.long}` : option.long;
  return option.takesValue ? `${strings} ${option.dest.toUpperCase()}` : strings;
}

function usagePart(option: OptionSpec): string {
  const strings = option.short !== undefined ? option.short : option.long;
  if (!option.takesValue) return `[${strings}]`;
  return option.required ? `${strings} ${option.dest.toUpperCase()}` : `[${strings} ${option.dest.toUpperCase()}]`;
}

function usage(prog: string, width: number, withHelp: boolean): string {
  const options = withHelp ? OPTIONS : OPTIONS.filter((option) => option.dest !== "help");
  const parts = options.map(usagePart);
  const prefix = "usage: ";
  const line = `${prefix}${prog} ${parts.join(" ")}`;
  if (line.length <= width) return line;
  const indent = " ".repeat(prefix.length + prog.length + 1);
  const lines: string[] = [];
  let current = "";
  let length = prefix.length - 1;
  for (const part of [prog, ...parts]) {
    if (length + 1 + part.length > width && current !== "") {
      lines.push(indent + current);
      current = "";
      length = indent.length - 1;
    }
    current = current === "" ? part : `${current} ${part}`;
    length += part.length + 1;
  }
  if (current !== "") lines.push(indent + current);
  lines[0] = prefix + lines[0].slice(indent.length);
  return lines.join("\n");
}

function buildHelp(prog: string): string {
  const width = terminalWidth();
  const entries: HelpEntry[] = OPTIONS.map((option) => ({
    invocation: invocation(option), help: option.help,
  }));
  const helpPosition = Math.min(
    Math.max(...entries.map((entry) => entry.invocation.length + 2)) + 2,
    Math.min(24, Math.max(width - 20, 4)));
  let out = usage(prog, width, true) + "\n\n";
  out += DESCRIPTION + "\n\n";
  out += "\noptions:\n" + renderEntries(entries, 2, helpPosition, width);
  return out.replace(/\n{3,}/g, "\n\n").replace(/\n+$/, "") + "\n";
}

// ---------------------------------------------------------------------------

function main(argv: string[]): void {
  const prog = basename(process.argv[1] ?? "verify.ts");
  let stage: string | null = null;
  let playbook: string | null = null;
  const expected = (flag: string): never => {
    process.stderr.write(usage(prog, terminalWidth(), false) + "\n" +
      `${prog}: error: argument ${flag}: expected one argument\n`);
    process.exit(2);
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "-h" || argument === "--help") {
      process.stdout.write(buildHelp(prog));
      process.exit(0);
    }
    let flag = argument;
    let inline: string | undefined;
    if (argument.startsWith("--") && argument.includes("=")) {
      flag = argument.slice(0, argument.indexOf("="));
      inline = argument.slice(argument.indexOf("=") + 1);
    }
    if (flag === "--stage" || flag === "--playbook") {
      let value = inline;
      if (value === undefined) {
        value = argv[++index];
        if (value === undefined || value.startsWith("-")) expected(flag);
      }
      if (flag === "--stage") stage = value;
      else playbook = value;
    } else {
      process.stderr.write(usage(prog, terminalWidth(), false) + "\n" +
        `${prog}: error: unrecognized arguments: ${argument}\n`);
      process.exit(2);
    }
  }
  if (stage === null) {
    process.stderr.write(usage(prog, terminalWidth(), false) + "\n" +
      `${prog}: error: the following arguments are required: --stage\n`);
    process.exit(2);
  }
  const stagePath = resolve(stage);
  if (!existsSync(stagePath) || !statSync(stagePath).isDirectory()) {
    process.stderr.write(`verify: stage directory not found: ${stagePath}\n`);
    process.exit(2);
  }
  const resolvedStage = realpathOf(stagePath);
  const resolvedPlaybook = playbook !== null ? realpathOf(resolve(playbook)) : findPlaybook();
  const { failures, notes } = verify(resolvedStage, resolvedPlaybook);
  for (const note of notes) {
    process.stdout.write(`note: ${note}\n`);
  }
  if (failures.length > 0) {
    for (const failure of failures) {
      process.stderr.write(`FAIL: ${failure}\n`);
    }
    process.exit(1);
  }
  process.stdout.write(`verified stage ${resolvedStage}: declared bytes/modes, hashes, and links\n`);
}

function realpathOf(path: string): string {
  try {
    return realpathSync(path);
  } catch {
    return path;
  }
}

// Run only when executed directly. The realpath comparison resolves symlinks
// so the tool also runs correctly through a symlinked invocation path.
import { realpath } from "node:fs/promises";
realpath(process.argv[1] ?? "").then((self) => {
  if (self === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
}, () => {});
