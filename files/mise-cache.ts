#!/usr/bin/env node
/**
 * mise-cache.ts — inventory and selective clearing of the caches that mise
 * and the tools it manages keep on this machine: mise's own metadata cache,
 * download staging and installs, plus the per-ecosystem caches those tools
 * maintain (npm, pnpm, yarn, bun, deno, cargo, go, gradle, maven, pip, uv,
 * nuget, prettier). TypeScript port of the retired mise-cache.sh; CLI via
 * node:util parse-args. Runs via Node type stripping.
 *
 * Commands:
 *   status [--fast]    per-area sizes + resolved paths, plus a `mise prune`
 *                      candidate list. --fast skips du (sizes print as "-").
 *   list               every catalog area with presence and actions
 *   gc AREAS...|--all  cache reclaim commands (mise cache prune, pnpm store
 *                      prune, uv cache prune), never installed-tool pruning
 *   clear AREAS...|--all
 *                      wipe areas: the native tool command when it is
 *                      available, else rm -rf of the resolved roots
 *
 * gc/clear accept -n/--dry-run (print the actions only) and -a/--all (every
 * present area that has that action). Areas absent on this machine are
 * skipped. `clear` never runs without an explicit selection.
 *
 * Registered in STATUSES as `mise-cache.ts status --fast` so the aggregate
 * status.sh stays quick; invoke `mise-cache.ts status` directly for real
 * sizes — a full du across every area can take minutes on a warm machine.
 *
 * Areas come from the staged catalog etc/mise-cache.areas.json written by
 * config-mise-cache.ts (config lane: base areas plus per-tool areas
 * selected by `mise ls --installed` detection), falling back to the
 * rendered union of the playbook's mise_cache_areas and
 * mise_tool_cache_areas until that step has run. `query` asks the tool
 * itself for its root (pnpm store path, go env GOMODCACHE, npm config get
 * cache, mise cache path); `fallback` applies when the tool is unavailable
 * or answers empty. Authored path strings are runtime-expanded ($HOME and
 * ${XDG_CACHE_HOME:-...} forms, nesting supported); query output is used
 * verbatim and never re-expanded. `expand` areas report one-level child
 * sizes instead of only an aggregate (mise installs, rustup toolchains).
 * `clear` is a native command, the literal `rm`, or `none` for
 * visibility-only areas. Cache/data roots follow mise's own env overrides
 * (MISE_CACHE_DIR, MISE_DATA_DIR) so a redirected mise sees its redirected
 * caches.
 *
 * Optional group/kind labels add topic and Rust-kind rollups without changing
 * leaf action selectors. Rollups canonicalize roots and omit duplicates and
 * nested roots. Topics can overlap (mise installs include Rust); TOTAL is the
 * union, not their sum. Sizes are allocated storage, not reclaim estimates.
 * Sizes come from `du -sk`; failed measurements print unknown. Exit: 0 ok, 1 an action
 * failed, 2 usage error or nothing to report (status N/A contract).
 */

import { spawn } from "node:child_process";
import { constants, readFileSync } from "node:fs";
import { access, readFile, readdir, realpath, rm, stat } from "node:fs/promises";
import { basename, delimiter, dirname, isAbsolute, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

type Command = "status" | "list" | "gc" | "clear";
const COMMANDS: readonly Command[] = ["status", "list", "gc", "clear"];
const isCommand = (value: string): value is Command =>
  (COMMANDS as readonly string[]).includes(value);

interface Area {
  readonly name: string;
  readonly group?: string;
  readonly kind?: string;
  readonly desc: string;
  readonly paths: readonly string[];
  readonly query: string;
  readonly fallback: string;
  readonly gc: string;
  readonly clear: string;
  readonly expand: boolean;
}

/** etc/mise-cache.areas.json written by config-mise-cache.ts */
interface CatalogFile {
  readonly generated: string;
  readonly tools: readonly string[];
  readonly areas: readonly Area[];
}

{% if TYPE == "mise2" %}
// mise2: route mise invocations through this deployment's isolated config
// root. Cache and data roots stay shared with the mise deployment until
// MISE_CACHE_DIR/MISE_DATA_DIR are redirected as well.
const MISE2_CONFIG_DEFAULT = "{{ mise2_config_dir }}";
{% else %}
const MISE2_CONFIG_DEFAULT: string | null = null;
{% endif %}

// Rendered fallback catalog: base areas plus every tool-mapped area
// flattened. At runtime the staged catalog from config-mise-cache.ts
// (etc/mise-cache.areas.json, computed from `mise ls --installed`) is
// preferred; this union applies until that config step has run.
{% macro area_literal(a) %}  {
    name: "{{ a['name'] }}",
    group: "{{ a['group'] | default('Other') }}",
    kind: "{{ a['kind'] | default('') }}",
    desc: "{{ a['desc'] }}",
    paths: [{% for p in a['paths'] | default([]) %}"{{ p }}", {% endfor %}],
    query: "{{ a['query'] | default("") }}",
    fallback: "{{ a['fallback'] | default("") }}",
    gc: "{{ a['gc'] | default("") }}",
    clear: "{{ a['clear'] | default("") }}",
    expand: {{ "true" if a['expand'] | default(False) | bool else "false" }},
  },
{% endmacro %}const FALLBACK_AREAS: readonly Area[] = [
{% for a in mise_cache_areas | default([]) %}{{ area_literal(a) }}{% endfor %}{% for entry in mise_tool_cache_areas | default({}) | dict2items %}{% for a in entry.value %}{{ area_literal(a) }}{% endfor %}{% endfor %}];

class UsageError extends Error {
  readonly code: number;

  constructor(message: string, code = 2) {
    super(message);
    this.code = code;
  }
}

function usage(): void {
  const names = FALLBACK_AREAS.map((a) => a.name).join(" ");
  console.error(`usage: mise-cache.ts status [--fast]
       mise-cache.ts list
       mise-cache.ts gc    AREAS...|--all [--dry-run]
       mise-cache.ts clear AREAS...|--all [--dry-run]
areas: ${names}`);
}

/** Resolved runtime state of one catalog area. */
interface ResolvedArea extends Area {
  /** existing+fallback candidates, deduped, query result first */
  readonly candidates: readonly string[];
  readonly present: boolean;
  /** KiB, set when measured */
  kb?: number;
  measurementFailed?: boolean;
  /** du output rows for expand areas: [KiB, path] */
  children?: readonly (readonly [number, string])[];
}

// Set-if-unset sourcing of the deployment env.export (envdefault semantics:
// an inherited environment always wins), so rendered defaults like
// MISE2_CONFIG_DIR reach this bin without Jinja in this file.
let envExportLoaded = false;
async function sourceEnv(path: string): Promise<void> {
  try {
    const text = await readFile(path, "utf8");
    for (const line of text.split("\n")) {
      const match = line.trim().match(/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
      if (match && process.env[match[1]] === undefined) {
        process.env[match[1]] = match[2].replace(/^["']|["']$/g, "");
      }
    }
  } catch {
    // missing env.export is fine
  }
  envExportLoaded = true;
}

// Expand one authored catalog path string ($VAR, ${VAR}, ${VAR:-default}
// with nesting, ~, ~/). The catalog is rendered from playbook vars — the
// same trust level as this script itself — but reject quotes/subshells
// anyway; query output never passes through this function.
function expandPath(raw: string): string {
  if (!raw) return "";
  if (/["`]|\$\(/.test(raw)) {
    throw new UsageError(`refusing suspicious path string: ${raw}`);
  }
  const home = process.env.HOME ?? "";
  if (raw === "~") return home;
  let s = raw.startsWith("~/") ? home + raw.slice(1) : raw;
  let out = "";
  let i = 0;
  while (i < s.length) {
    if (s[i] !== "$") {
      out += s[i];
      i++;
      continue;
    }
    if (s[i + 1] === "{") {
      const close = matchBrace(s, i + 1);
      if (close < 0) throw new UsageError(`unbalanced brace in path string: ${raw}`);
      const body = s.slice(i + 2, close);
      const sep = body.indexOf(":-");
      const name = sep < 0 ? body : body.slice(0, sep);
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) {
        throw new UsageError(`bad parameter name in path string: ${raw}`);
      }
      const value = process.env[name];
      if (value !== undefined && value !== "") {
        out += value;
      } else if (sep >= 0) {
        out += expandPath(body.slice(sep + 2));
      }
      i = close + 1;
    } else {
      const m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(s.slice(i + 1));
      if (!m) throw new UsageError(`stray $ in path string: ${raw}`);
      out += process.env[m[0]] ?? "";
      i += 1 + m[0].length;
    }
  }
  return out;
}

/** index of the `}` matching the `{` at open, -1 when unbalanced */
function matchBrace(s: string, open: number): number {
  let depth = 0;
  for (let i = open; i < s.length; i++) {
    if (s[i] === "{") depth++;
    else if (s[i] === "}") {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

async function pathExists(path: string): Promise<boolean> {
  try {
    await stat(path);
    return true;
  } catch {
    return false;
  }
}

interface ToolResult {
  readonly code: number;
  readonly stdout: string;
  readonly stderr: string;
  readonly failed: boolean;
  readonly missing: boolean;
}

let mise2Config: string | null = null;

/** deployment root: import.meta.url is <DIR>/bin/mise-cache.ts */
const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const CATALOG_PATH = join(ROOT, "etc", "mise-cache.areas.json");

/**
 * Catalog selection: prefer the staged etc/mise-cache.areas.json computed
 * by config-mise-cache.ts from `mise ls --installed` (present once the
 * config lane has run); fall back to the rendered union. Returns the areas
 * and a one-line provenance for status/list output.
 */
function loadCatalog(): { areas: readonly Area[]; source: string } {
  try {
    const parsed = JSON.parse(readFileSync(CATALOG_PATH, "utf8")) as CatalogFile;
    if (Array.isArray(parsed.areas) && parsed.areas.length > 0) {
      const tools = Array.isArray(parsed.tools) ? parsed.tools.length : 0;
      return {
        areas: parsed.areas,
        source: `computed ${parsed.generated} (${parsed.areas.length} areas from ${tools} mise tools)`,
      };
    }
  } catch {
    // absent or unreadable staged catalog -> rendered fallback
  }
  return {
    areas: FALLBACK_AREAS,
    source: `rendered fallback (${FALLBACK_AREAS.length} areas; run config-mise-cache.ts to compute from mise ls)`,
  };
}

/** how the command appears in logs (mise2 prefixes its config root) */
function displayCmd(cmd: string): string {
  const first = cmd.trim().split(/\s+/)[0];
  return first === "mise" && mise2Config ? `MISE_CONFIG_DIR=${mise2Config} ${cmd}` : cmd;
}

// Run a catalog command string (whitespace-separated words; no shell
// metacharacters are authored). `mise …` runs with this deployment's config
// root under mise2.
function runTool(cmd: string): Promise<ToolResult> {
  const words = cmd.trim().split(/\s+/);
  const env: NodeJS.ProcessEnv = { ...process.env };
  if (words[0] === "mise" && mise2Config) env.MISE_CONFIG_DIR = mise2Config;
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn(words[0], words.slice(1), { env });
    } catch (error) {
      resolve({
        code: 1,
        stdout: "",
        stderr: String(error),
        failed: true,
        missing: false,
      });
      return;
    }
    let stdout = "";
    let stderr = "";
    let missing = false;
    const settle = (code: number | null): void => {
      resolve({
        code: code ?? (missing ? 127 : 1),
        stdout,
        stderr,
        failed: missing || code !== 0,
        missing,
      });
    };
    child.on("error", (error: NodeJS.ErrnoException) => {
      missing = error.code === "ENOENT";
      stderr += String(error);
      // spawn failures (ENOENT) never emit close
      settle(null);
    });
    child.stdout?.on("data", (d) => (stdout += d));
    child.stderr?.on("data", (d) => (stderr += d));
    child.on("close", settle);
  });
}

/** Lookup only: never execute a bare tool to test its availability. */
async function executableAvailable(command: string): Promise<boolean> {
  const paths = command.includes("/") ? [command] :
    (process.env.PATH ?? "").split(delimiter).map((dir) => join(dir || ".", command));
  for (const path of paths) {
    try {
      await access(path, constants.X_OK);
      if ((await stat(path)).isFile()) return true;
    } catch { /* next PATH entry */ }
  }
  return false;
}

/** Physical, existing roots, without duplicates or descendants of another root. */
async function uniqueRoots(paths: readonly string[]): Promise<string[]> {
  const roots = new Set<string>();
  for (const path of paths) {
    if (await pathExists(path)) roots.add(await realpath(path));
  }
  return [...roots].filter((path) => ![...roots].some((parent) =>
    parent !== path && path.startsWith(parent.endsWith(sep) ? parent : parent + sep)));
}

/** `du -sk` over the given paths; resolves to parsed [KiB, path] rows */
const measurements = new Map<string, Promise<readonly (readonly [number, string])[] | undefined>>();
function du(paths: readonly string[]): Promise<readonly (readonly [number, string])[] | undefined> {
  const sorted = [...paths].sort();
  const key = JSON.stringify(sorted);
  let measurement = measurements.get(key);
  if (!measurement) {
    measurement = runDu(sorted);
    measurements.set(key, measurement);
  }
  return measurement;
}

function runDu(paths: readonly string[]): Promise<readonly (readonly [number, string])[] | undefined> {
  if (paths.length === 0) return Promise.resolve([]);
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn("du", ["-sk", "--", ...paths]);
    } catch {
      resolve(undefined);
      return;
    }
    let stdout = "";
    child.on("error", () => resolve(undefined));
    child.stdout?.on("data", (d) => (stdout += d));
    child.on("close", (code) => {
      if (code !== 0) { resolve(undefined); return; }
      const rows: [number, string][] = [];
      for (const line of stdout.split("\n")) {
        const m = line.match(/^(\d+)\t(.*)$/);
        if (m) rows.push([Number(m[1]), m[2]]);
      }
      resolve(rows);
    });
  });
}

async function resolveArea(area: Area): Promise<ResolvedArea> {
  const candidates: string[] = [];
  if (area.query) {
    const result = await runTool(area.query);
    const line = result.stdout.trimEnd().split("\n").filter(Boolean).at(-1);
    if (!result.failed && line !== undefined && isAbsolute(line)) candidates.push(line);
    else if (area.fallback) candidates.push(expandPath(area.fallback));
  } else if (area.fallback) {
    candidates.push(expandPath(area.fallback));
  }
  for (const p of area.paths) {
    const expanded = expandPath(p);
    if (expanded && !candidates.includes(expanded)) candidates.push(expanded);
  }
  const unique = [...new Set(candidates.filter(Boolean).map((path) => resolve(path)))];
  let present = false;
  for (const c of unique) {
    if (await pathExists(c)) present = true;
  }
  return { ...area, candidates: unique, present };
}

async function measureAreas(areas: readonly ResolvedArea[]): Promise<void> {
  await Promise.all(
    areas.map(async (area) => {
      if (!area.present) return;
      const roots = await uniqueRoots(area.candidates);
      const rows = await du(roots);
      area.measurementFailed = rows === undefined;
      area.kb = rows?.reduce((sum, [kb]) => sum + kb, 0);
      if (area.expand) {
        // one level of children instead of only the aggregate
        const childPaths: string[] = [];
        for (const c of roots) {
          try {
            const entries = await readdir(c);
            childPaths.push(...entries.map((e) => join(c, e)));
          } catch {
            // candidate vanished or is a file; du of the parent covers it
            childPaths.push(c);
          }
        }
        area.children = await du(await uniqueRoots(childPaths));
      } else if (roots.length > 1) area.children = rows;
    }),
  );
}

/** bytes → IEC (K/M/G/T/P, one decimal), numfmt --to=iec style */
function human(bytes: number): string {
  const units = ["K", "M", "G", "T", "P"];
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return `${value.toFixed(1)}${units[unit]}`;
}

const PAD = 14;

function statusLine(name: string, size: string, paths: string): string {
  return `${name.padEnd(PAD)} ${size.padStart(9)}  ${paths}`;
}

async function cmdStatus(
  areas: readonly ResolvedArea[],
  fast: boolean,
  source: string,
): Promise<number> {
  if (!fast) await measureAreas(areas);
  const present = areas.filter((a) => a.present);
  const absent = areas.filter((a) => !a.present).map((a) => a.name);
  console.log(`catalog: ${source}`);
  console.log(`cache areas: ${present.length} present, ${absent.length} absent`);
  if (present.length > 0) {
    console.log("allocated storage (du); installed tools and state are not cache reclaim estimates");
    console.log(statusLine("AREA", "SIZE", "PATHS"));
    const groups = new Map<string, ResolvedArea[]>();
    for (const area of present) {
      const group = area.group || "Other";
      groups.set(group, [...(groups.get(group) ?? []), area]);
    }
    for (const [group, members] of groups) {
      const rows = fast ? undefined : await du(await uniqueRoots(members.flatMap((a) => a.candidates)));
      console.log(statusLine(group, fast ? "-" : rows === undefined ? "unknown" : human(rows.reduce((sum, [kb]) => sum + kb, 0) * 1024), "topic total"));
      if (group === "Rust") {
        for (const kind of ["toolchains", "libraries", "ancillary"]) {
          const leaves = members.filter((area) => area.kind === kind);
          if (!leaves.length) continue;
          const part = fast ? undefined : await du(await uniqueRoots(leaves.flatMap((a) => a.candidates)));
          console.log(statusLine(`  ${kind}`, fast ? "-" : part === undefined ? "unknown" : human(part.reduce((sum, [kb]) => sum + kb, 0) * 1024), "Rust subtotal"));
        }
      }
      for (const area of members) {
        const size = area.measurementFailed ? "unknown" : area.kb === undefined ? "-" : human(area.kb * 1024);
        console.log(statusLine(area.name, size, area.candidates.join(" ")));
        if (area.children?.length) {
          const sorted = [...area.children].sort((a, b) => b[0] - a[0]);
          for (const [kb, path] of sorted) {
            console.log(`    ${human(kb * 1024).padStart(9)}  ${basename(path)}`);
          }
        }
      }
    }
    if (!fast) {
      const rows = await du(await uniqueRoots(present.flatMap((a) => a.candidates)));
      console.log(statusLine("TOTAL", rows === undefined ? "unknown" : human(rows.reduce((sum, [kb]) => sum + kb, 0) * 1024), "unique physical roots; topic totals may overlap"));
    }
  }
  if (absent.length > 0) console.log(`absent: ${absent.join(" ")}`);
  const mise = await runTool("mise ls --prunable --json");
  if (!mise.missing) {
    console.log("\nmise prune candidates (mise prune --tools):");
    try {
      if (mise.failed) throw new Error(mise.stderr.trim() || "query failed");
      const parsed: unknown = JSON.parse(mise.stdout);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("unexpected response");
      const lines: string[] = [];
      for (const [tool, versions] of Object.entries(parsed)) {
        if (!Array.isArray(versions)) throw new Error("unexpected tool versions");
        for (const version of versions) {
          if (!version || typeof version.version !== "string") throw new Error("unexpected version");
          lines.push(`  ${tool}@${version.version}`);
        }
      }
      console.log(lines.length ? lines.join("\n") : "  none");
    } catch (error) {
      console.log(`  unavailable: ${String(error)}`);
    }
  }
  if (present.length === 0) {
    console.log("no cache areas present");
    return 2;
  }
  return 0;
}

function cmdList(areas: readonly ResolvedArea[], source: string): number {
  console.log(`catalog: ${source}`);
  console.log(
    `${"AREA".padEnd(PAD)} ${"PRESENT".padEnd(7)} ${"GC".padEnd(3)} ${"CLEAR".padEnd(5)}  DESCRIPTION`,
  );
  for (const area of areas) {
    const gc = area.gc ? "yes" : "-";
    const clear = !area.clear || area.clear === "none" ? "-" : area.clear === "rm" ? "rm" : "cmd";
    console.log(
      `${area.name.padEnd(PAD)} ${(area.present ? "present" : "absent").padEnd(7)} ${gc.padEnd(3)} ${clear.padEnd(5)}  ${area.desc}`,
    );
  }
  return 0;
}

async function rmPaths(area: ResolvedArea, dryRun: boolean): Promise<boolean> {
  let ok = true;
  for (const path of area.candidates) {
    if (!(await pathExists(path))) continue;
    if (path === "/" || path === process.env.HOME) {
      console.error(`  refusing to remove ${path}`);
      ok = false;
      continue;
    }
    if (dryRun) {
      console.log(`  [dry-run] rm -rf ${path}`);
      continue;
    }
    console.log(`  rm -rf ${path}`);
    try {
      await rm(path, { recursive: true, force: true });
    } catch (error) {
      console.error(`  rm -rf ${path} failed: ${String(error)}`);
      ok = false;
    }
  }
  return ok;
}

async function runNative(cmd: string, dryRun: boolean): Promise<boolean> {
  if (dryRun) {
    console.log(`  [dry-run] ${displayCmd(cmd)}`);
    return true;
  }
  const words = cmd.trim().split(/\s+/);
  if (!(await executableAvailable(words[0]))) {
    console.error(`  ${words[0]} is not on PATH`);
    return false;
  }
  console.log(`  running: ${displayCmd(cmd)}`);
  const result = await runTool(cmd);
  if (result.stdout.trim()) process.stdout.write(result.stdout.endsWith("\n") ? result.stdout : result.stdout + "\n");
  if (result.stderr.trim()) process.stderr.write(result.stderr.endsWith("\n") ? result.stderr : result.stderr + "\n");
  return !result.failed;
}

async function cmdAct(
  kind: "gc" | "clear",
  areas: readonly ResolvedArea[],
  selected: readonly string[],
  all: boolean,
  dryRun: boolean,
): Promise<number> {
  const byName = new Map(areas.map((a) => [a.name, a]));
  for (const name of selected) {
    if (!byName.has(name)) {
      console.error(`mise-cache: unknown area: ${name}`);
      usage();
      return 2;
    }
  }
  const picked = areas.filter((area) => {
    if (all) {
      if (!area.present) return false;
      return kind === "gc" ? Boolean(area.gc) : Boolean(area.clear) && area.clear !== "none";
    }
    return selected.includes(area.name);
  });
  if (picked.length === 0) {
    console.error(`mise-cache: nothing selected has a ${kind} action`);
    return 2;
  }
  let rc = 0;
  for (const area of picked) {
    console.log(`${area.name}:`);
    if (!area.present) {
      console.log("  absent on this machine, skipping");
      continue;
    }
    if (kind === "gc") {
      if (!area.gc) {
        console.log("  no gc action");
        continue;
      }
      if (!(await runNative(area.gc, dryRun))) rc = 1;
      continue;
    }
    if (!area.clear || area.clear === "none") {
      console.log("  visibility only, no clear action");
      continue;
    }
    if (area.clear === "rm") {
      if (!(await rmPaths(area, dryRun))) rc = 1;
    } else {
      const words = area.clear.trim().split(/\s+/);
      if (!(await executableAvailable(words[0]))) {
        console.log(`  ${words[0]} not available, removing paths directly`);
        if (!(await rmPaths(area, dryRun))) rc = 1;
      } else if (!(await runNative(area.clear, dryRun))) {
        rc = 1;
      }
    }
  }
  return rc;
}

async function main(): Promise<number> {
  // The IIFE keeps parse-args' generic inference from the inline options
  // literal (a ReturnType annotation would widen every value to the
  // string|boolean union and defeat the per-key boolean types).
  const parsed = (() => {
    try {
      return parseArgs({
        allowPositionals: true,
        options: {
          fast: { type: "boolean" },
          "dry-run": { type: "boolean", short: "n" },
          all: { type: "boolean", short: "a" },
          help: { type: "boolean", short: "h" },
        },
      });
    } catch (error) {
      throw new UsageError(error instanceof Error ? error.message : String(error));
    }
  })();
  const { values, positionals } = parsed;

  if (values.help) {
    usage();
    return 0;
  }
  const command = positionals[0];
  const selected = positionals.slice(1);
  if (command === undefined) {
    usage();
    return 2;
  }
  if (!isCommand(command)) {
    throw new UsageError(`unknown command: ${command}`);
  }
  if ((command === "status" || command === "list") && selected.length > 0) {
    throw new UsageError(`unexpected argument: ${selected[0]}`);
  }
  const dryRun = values["dry-run"] ?? false;
  const all = values.all ?? false;
  if ((command === "gc" || command === "clear") && selected.length === 0 && !all) {
    usage();
    return 2;
  }

  // import.meta.url is <DIR>/bin/mise-cache.ts; the deployment root is one
  // dirname up (fileURLToPath form for older @types/node).
  if (!envExportLoaded) await sourceEnv(join(ROOT, "env.export"));
  if (MISE2_CONFIG_DEFAULT !== null) {
    // env.export values arrive as literal text (sourceEnv does not shell
    // expand); expandPath handles both the $HOME forms and plain paths
    mise2Config = expandPath(process.env.MISE2_CONFIG_DIR ?? MISE2_CONFIG_DEFAULT);
  }

  const { areas: catalog, source } = loadCatalog();
  const areas = await Promise.all(catalog.map(resolveArea));
  switch (command) {
    case "status":
      return cmdStatus(areas, values.fast ?? false, source);
    case "list":
      return cmdList(areas, source);
    case "gc":
    case "clear":
      return cmdAct(command, areas, selected, all, dryRun);
  }
}

main().then(
  (code) => {
    process.exitCode = code;
  },
  (error: unknown) => {
    if (error instanceof UsageError) {
      console.error(`mise-cache: ${error.message}`);
      process.exitCode = error.code;
    } else {
      console.error(error instanceof Error ? error.stack : String(error));
      process.exitCode = 1;
    }
  },
);
