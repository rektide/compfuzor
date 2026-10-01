#!/usr/bin/env node
/**
 * config-mise-cache.ts — config-lane generator: recompute the mise cache
 * catalog from live machine state and stage it for mise-cache.ts.
 *
 * Detection is mise-scoped ("all things mise"): the catalog is the
 * playbook's base areas (mise's own cache/data/state trees) plus the
 * per-tool areas mapped in mise_tool_cache_areas, selected by the tools
 * actually installed via `mise ls --json --installed`. The mapped stores
 * (npm, pnpm, cargo, go, ...) are ecosystem caches, not mise-owned — they
 * appear because the tool that populates them is mise-managed here.
 *
 * Output: $DIR/etc/mise-cache.areas.json (atomic tmp+rename), consumed by
 * mise-cache.ts which prefers it over its rendered fallback catalog. A
 * staged artifact beside the ansible-rendered ones: regenerating needs no
 * re-render, and a fresh render works before this step has ever run.
 *
 * Composes into bin/config.sh (config-* lane). CLI via node:util parse-args;
 * runs via Node type stripping.
 *
 * Usage:
 *   config-mise-cache.ts            # detect + stage (writes the JSON)
 *   config-mise-cache.ts --stdout   # detect only; print JSON to stdout
 *
 * When mise is unavailable or `mise ls` fails, the base areas are staged
 * with a warning (never an error): mise-cache.ts would find no tool-mapped
 * caches either.
 *
 * Exit: 0 staged/printed, 2 usage error, 1 write failure.
 */

import { spawn } from "node:child_process";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

interface Area {
  readonly name: string;
  readonly desc: string;
  readonly paths: readonly string[];
  readonly query: string;
  readonly fallback: string;
  readonly gc: string;
  readonly clear: string;
  readonly expand: boolean;
}

class UsageError extends Error {
  readonly code: number;

  constructor(message: string, code = 2) {
    super(message);
    this.code = code;
  }
}

function usage(): void {
  console.error(`usage: config-mise-cache.ts [--stdout]
  detect installed mise tools (mise ls --json --installed), select base +
  per-tool cache areas, and stage $DIR/etc/mise-cache.areas.json for
  mise-cache.ts (--stdout prints instead of writing)`);
}

{% if TYPE == "mise2" %}
// mise2: run mise against this deployment's isolated config root. Cache and
// data roots stay shared with the mise deployment.
const MISE2_CONFIG_DEFAULT = "{{ mise2_config_dir }}";
{% else %}
const MISE2_CONFIG_DEFAULT: string | null = null;
{% endif %}

{% macro area_literal(a) %}    {
      name: "{{ a['name'] }}",
      desc: "{{ a['desc'] }}",
      paths: [{% for p in a['paths'] | default([]) %}"{{ p }}", {% endfor %}],
      query: "{{ a['query'] | default("") }}",
      fallback: "{{ a['fallback'] | default("") }}",
      gc: "{{ a['gc'] | default("") }}",
      clear: "{{ a['clear'] | default("") }}",
      expand: {{ "true" if a['expand'] | default(False) | bool else "false" }},
    },
{% endmacro %}
// Base areas: mise's own directories, always in the catalog.
const BASE_AREAS: readonly Area[] = [
{% for a in mise_cache_areas | default([]) %}{{ area_literal(a) }}{% endfor %}];

// Per-tool areas: included when that tool is installed via mise.
const TOOL_AREAS: Readonly<Record<string, readonly Area[]>> = {
{% for entry in mise_tool_cache_areas | default({}) | dict2items %}  "{{ entry.key }}": [
{% for a in entry.value %}{{ area_literal(a) }}{% endfor %}  ],
{% endfor %}};

// Set-if-unset sourcing of the deployment env.export (envdefault
// semantics), so rendered defaults like MISE2_CONFIG_DIR reach this bin.
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
}

/** $VAR / ${VAR} / ${VAR:-default} (one level) for env.export values */
function expandPath(raw: string): string {
  return raw.replace(/\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}|\$([A-Za-z_][A-Za-z0-9_]*)/g, (
    _whole,
    name?: string,
    fallback?: string,
    bare?: string,
  ) => {
    const key = name ?? bare;
    const value = key === undefined ? undefined : process.env[key];
    if (value !== undefined && value !== "") return value;
    if (name !== undefined && fallback !== undefined) return fallback;
    return "";
  });
}

let mise2Config: string | null = null;

interface ToolResult {
  readonly stdout: string;
  readonly stderr: string;
  readonly failed: boolean;
  readonly missing: boolean;
}

// Run a whitespace-separated command string; `mise …` runs with this
// deployment's config root under mise2.
function runTool(cmd: string): Promise<ToolResult> {
  const words = cmd.trim().split(/\s+/);
  const env: NodeJS.ProcessEnv = { ...process.env };
  if (words[0] === "mise" && mise2Config) env.MISE_CONFIG_DIR = mise2Config;
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn(words[0], words.slice(1), { env });
    } catch (error) {
      resolve({ stdout: "", stderr: String(error), failed: true, missing: false });
      return;
    }
    let stdout = "";
    let stderr = "";
    let missing = false;
    const settle = (code: number | null): void => {
      resolve({ stdout, stderr, failed: missing || code !== 0, missing });
    };
    child.on("error", (error: NodeJS.ErrnoException) => {
      missing = error.code === "ENOENT";
      stderr += String(error);
      settle(null); // spawn failures (ENOENT) never emit close
    });
    child.stdout?.on("data", (d) => (stdout += d));
    child.stderr?.on("data", (d) => (stderr += d));
    child.on("close", settle);
  });
}

/** tool names installed via mise; empty (with a warning) when detection fails */
async function detectTools(): Promise<string[]> {
  const result = await runTool("mise ls --json --installed");
  if (result.missing) {
    console.error("config-mise-cache: mise is not on PATH; staging base areas only");
    return [];
  }
  if (result.failed) {
    const reason = result.stderr.trim().split("\n")[0] ?? "";
    console.error(`config-mise-cache: mise ls failed (${reason}); staging base areas only`);
    return [];
  }
  try {
    const parsed: unknown = JSON.parse(result.stdout || "{}");
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("unexpected shape");
    }
    return Object.keys(parsed).sort();
  } catch {
    console.error("config-mise-cache: mise ls output was not a tool map; staging base areas only");
    return [];
  }
}

async function main(): Promise<number> {
  const parsed = (() => {
    try {
      return parseArgs({
        options: {
          stdout: { type: "boolean" },
          help: { type: "boolean", short: "h" },
        },
      });
    } catch (error) {
      throw new UsageError(error instanceof Error ? error.message : String(error));
    }
  })();
  if (parsed.values.help) {
    usage();
    return 0;
  }

  // import.meta.url is <DIR>/bin/config-mise-cache.ts
  const root = dirname(dirname(fileURLToPath(import.meta.url)));
  await sourceEnv(join(root, "env.export"));
  if (MISE2_CONFIG_DEFAULT !== null) {
    mise2Config = expandPath(process.env.MISE2_CONFIG_DIR ?? MISE2_CONFIG_DEFAULT);
  }

  const tools = await detectTools();

  // base + mapped areas for installed tools, deduped by name (first wins)
  const areas: Area[] = [...BASE_AREAS];
  const seen = new Set(areas.map((a) => a.name));
  for (const tool of tools) {
    for (const area of TOOL_AREAS[tool] ?? []) {
      if (!seen.has(area.name)) {
        seen.add(area.name);
        areas.push(area);
      }
    }
  }

  const catalog = {
    generated: new Date().toISOString(),
    tools,
    areas,
  };
  const json = JSON.stringify(catalog, null, 2) + "\n";

  if (parsed.values.stdout) {
    process.stdout.write(json);
    return 0;
  }

  const dest = join(root, "etc", "mise-cache.areas.json");
  try {
    await mkdir(dirname(dest), { recursive: true });
    // summary against the previous staged catalog before replacing it
    try {
      const previous = JSON.parse(await readFile(dest, "utf8")) as { areas?: { name: string }[] };
      const oldNames = new Set((previous.areas ?? []).map((a) => a.name));
      const added = areas.filter((a) => !oldNames.has(a.name)).map((a) => a.name);
      const removed = [...oldNames].filter((n) => !seen.has(n));
      if (added.length > 0) console.log(`config-mise-cache: added areas: ${added.join(" ")}`);
      if (removed.length > 0) console.log(`config-mise-cache: removed areas: ${removed.join(" ")}`);
    } catch {
      // no previous staged catalog
    }
    const tmp = `${dest}.tmp`;
    await writeFile(tmp, json, "utf8");
    await rename(tmp, dest);
  } catch (error) {
    console.error(`config-mise-cache: failed to stage ${dest}: ${String(error)}`);
    return 1;
  }

  const mapped = areas.length - BASE_AREAS.length;
  console.log(
    `config-mise-cache: staged ${dest} (${areas.length} areas: ${BASE_AREAS.length} base + ${mapped} mapped from ${tools.length} mise tools)`,
  );
  return 0;
}

main().then(
  (code) => {
    process.exitCode = code;
  },
  (error: unknown) => {
    if (error instanceof UsageError) {
      console.error(`config-mise-cache: ${error.message}`);
      process.exitCode = error.code;
    } else {
      console.error(error instanceof Error ? error.stack : String(error));
      process.exitCode = 1;
    }
  },
);
