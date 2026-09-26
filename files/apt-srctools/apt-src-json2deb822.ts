#!/usr/bin/env -S node --strip-types
/**
 * apt-src-json2deb822.ts - render the canonical apt-srctools JSON model as
 * deb822 .sources stanzas (see apt-src-model.ts).
 *
 * One JSON entry becomes one stanza (no deb/deb-src merging). Field order is
 * fixed: Types, URIs, Suites, Components, Architectures, Enabled, Trusted,
 * Signed-By, then "fields" passthrough. Signed-By keyblocks emit with
 * continuation-space and dot-stuffing. Classic bracket options that alias
 * into deb822 fields (lang -> Languages, target -> Targets, pdiffs -> PDiffs,
 * by-hash -> By-Hash) are mapped; the remainder warns on stderr and drops.
 *
 * Usage:
 *   apt-src-json2deb822.ts [--file PATH | --in PATH] [--out PATH] < model.json
 */

import { readFile, writeFile } from "node:fs/promises";
import { parseArgs } from "node:util";
import type { AptSourcesJson } from "./apt-src-model.ts";
import { canonical, emitDeb822, unaliasableOptions } from "./apt-src-model.ts";

const USAGE = `apt-src-json2deb822.ts - JSON -> deb822 .sources stanzas

Usage:
  apt-src-json2deb822.ts [--file PATH | --in PATH] [--out PATH]

Options:
  --file, -f PATH   input JSON file (default: stdin)
  --in PATH         alias for --file
  --out, -o PATH    output file (default: stdout)
  --help, -h        this help

One entry = one stanza. Signed-By keyblocks emit verbatim (continuation space
plus dot-stuffing). lang/target/pdfs/by-hash bracket options alias into
deb822 fields; other classic-only options warn and drop.`;

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(chunk as Buffer);
  return Buffer.concat(chunks).toString("utf8");
}

const args = parseArgs({
  options: {
    file: { type: "string", short: "f" },
    in: { type: "string" },
    out: { type: "string", short: "o" },
    help: { type: "boolean", short: "h" },
  },
});
if (args.values.help) {
  console.log(USAGE);
  process.exit(0);
}

const input = args.values.in ?? args.values.file;
try {
  const text = input ? await readFile(input, "utf8") : await readStdin();
  const json = canonical(JSON.parse(text) as AptSourcesJson);
  for (const warning of unaliasableOptions(json))
    console.error(`warn: dropping ${warning} (no deb822 field spelling)`);
  const out = emitDeb822(json);
  if (args.values.out) await writeFile(args.values.out, out, "utf8");
  else process.stdout.write(out);
} catch (err) {
  if (err instanceof SyntaxError) {
    console.error(`error: ${input ?? "stdin"}: invalid JSON: ${err.message}`);
    process.exit(1);
  }
  if (err instanceof Error && err.message.startsWith("entry ")) {
    console.error(`error: ${input ?? "stdin"}: ${err.message}`);
    process.exit(1);
  }
  throw err;
}
