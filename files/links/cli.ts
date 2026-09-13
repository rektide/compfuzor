/** Strict command-line parsing and help for the LINKS manager. */

import { parseArgs } from "node:util";

export type LinksCommand = "apply" | "status" | "audit" | "remove";
export type LinksScope = "system" | "user";
export type LinksStrategy = "link" | "copy";
export type LinksFormat = "human" | "jsonl" | "array";
export type SudoMode = "never" | "auto" | "always";

export interface LinksCliOptions {
  command: LinksCommand;
  scope?: LinksScope;
  id?: string[];
  format: LinksFormat;
  quiet: number;
  paths: string[];
  sudo?: string;
  strategy?: LinksStrategy;
  composed: boolean;
}

export const LINKS_HELP = `Usage: links <apply|status|audit|remove> [MANIFEST ...] [options]

Manage version 1 and 2 link plans. A directory argument means its links.json;
the default manifest is the current deployment's links.json.

Options:
  --scope system|user  Operate on one activation scope
  --id GLOBS           Comma-separated record-id globs; may be repeated
  --strategy link|copy Apply using one declared representation
  --composed           Apply only generic-install records
  --json               Emit one JSON object per row
  --json-array         Emit one JSON array
  --sudo MODE          auto (default), always, or never
                       Bare --sudo remains accepted as always for compatibility
  -q, -qq              Synopsis only, or no output
  -h, --help           Show this help

Exit: 0 success/in-sync, 1 drift or policy conflict, 2 usage/source error.`;

function fail(message: string): never {
  throw new Error(message);
}

export function parseSudoWord(value: string): SudoMode | undefined {
  const raw = value.trim().toLowerCase();
  if (raw === "auto") return "auto";
  if (["always", "1", "true", "y", "yes"].includes(raw)) return "always";
  if (["never", "0", "false", "n", "no"].includes(raw)) return "never";
  return undefined;
}

export function resolveSudoMode(flagValue: string | undefined): SudoMode {
  if (flagValue !== undefined) {
    const mode = parseSudoWord(flagValue);
    if (!mode) fail(`--sudo expects auto, always, or never (got ${flagValue})`);
    return mode;
  }
  const environmentValue = process.env.COMPFUZOR_LINKS_SUDO;
  if (environmentValue === undefined || environmentValue.trim() === "") return "auto";
  const mode = parseSudoWord(environmentValue);
  if (!mode) fail(`COMPFUZOR_LINKS_SUDO must be auto, always, or never (got ${environmentValue})`);
  return mode;
}

/**
 * node:util parseArgs intentionally has no optional-value options. Preserve the
 * historical bare `--sudo` shorthand by making its implicit value explicit;
 * every other token is passed to strict parseArgs unchanged.
 */
function normalizeBareSudo(argv: string[]): string[] {
  const normalized: string[] = [];
  for (let index = 0; index < argv.length; index++) {
    const argument = argv[index];
    const next = argv[index + 1];
    normalized.push(argument === "--sudo" && (next === undefined || parseSudoWord(next) === undefined)
      ? "--sudo=always"
      : argument);
  }
  return normalized;
}

export function parseLinksArgs(argv: string[], defaultManifest: string): LinksCliOptions {
  const { values, positionals, tokens } = parseArgs({
    args: normalizeBareSudo(argv),
    strict: true,
    allowPositionals: true,
    tokens: true,
    options: {
      scope: { type: "string" },
      id: { type: "string", multiple: true },
      strategy: { type: "string" },
      composed: { type: "boolean" },
      json: { type: "boolean" },
      "json-array": { type: "boolean" },
      sudo: { type: "string" },
      quiet: { type: "boolean", short: "q", multiple: true },
      help: { type: "boolean", short: "h" },
    },
  });
  if (values.help) {
    console.log(LINKS_HELP);
    process.exit(0);
  }

  const commandIndex = positionals.findIndex((value) => value === "apply" || value === "status" || value === "audit" || value === "remove");
  if (commandIndex < 0) fail("expected apply, status, audit, or remove");
  const command = positionals[commandIndex] as LinksCommand;
  const paths = positionals.toSpliced(commandIndex, 1);
  if (command !== "audit" && paths.length > 1) fail(`${command} accepts at most one manifest`);
  if (values.strategy !== undefined && command !== "apply") fail("--strategy is only valid with apply");
  if (values.composed && command !== "apply") fail("--composed is only valid with apply");
  if (values.scope !== undefined && values.scope !== "system" && values.scope !== "user") fail("--scope must be system or user");
  if (values.strategy !== undefined && values.strategy !== "link" && values.strategy !== "copy") fail("--strategy must be link or copy");

  const id = values.id?.flatMap((value) => value.split(",").map((part) => part.trim()).filter(Boolean));
  if (values.id !== undefined && id?.length === 0) fail("--id requires a comma-separated glob list");
  const formatToken = tokens.findLast((token) => token.kind === "option" && (token.name === "json" || token.name === "json-array"));
  const format: LinksFormat = formatToken?.name === "json-array" ? "array" : formatToken?.name === "json" ? "jsonl" : "human";

  return {
    command,
    scope: values.scope as LinksScope | undefined,
    id,
    format,
    quiet: values.quiet?.length ?? 0,
    paths: paths.length === 0 ? [defaultManifest] : paths,
    sudo: values.sudo,
    strategy: values.strategy as LinksStrategy | undefined,
    composed: values.composed ?? false,
  };
}
