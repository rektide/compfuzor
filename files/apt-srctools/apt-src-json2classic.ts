#!/usr/bin/env -S node --strip-types
/**
 * apt-src-json2classic.ts - render the canonical apt-srctools JSON model as
 * one-line classic .list sources (see apt-src-model.ts).
 *
 * Each entry expands to its types x uris x suites cartesian lines, matching
 * the legacy Compfuzor renderer's bracket style:
 *
 *   deb [ signed-by=/usr/share/keyrings/x.gpg arch=amd64 ] https://... stable main
 *
 * Disabled entries are emitted as "#deb ...". deb822-only "fields" (By-Hash,
 * X-Repolib-Name, ...) and inline Signed-By keyblocks have no classic
 * spelling: they warn on stderr and are dropped.
 *
 * Usage:
 *   apt-src-json2classic.ts [--file PATH | --in PATH] [--out PATH] < model.json
 */

import { readFile, writeFile } from "node:fs/promises";
import { parseArgs } from "node:util";
import type { AptSourcesJson } from "./apt-src-model.ts";
import { canonical, emitClassic, unclassicable } from "./apt-src-model.ts";

const USAGE = `apt-src-json2classic.ts - JSON -> classic .list sources

Usage:
  apt-src-json2classic.ts [--file PATH | --in PATH] [--out PATH]

Options:
  --file, -f PATH   input JSON file (default: stdin)
  --in PATH         alias for --file
  --out, -o PATH    output file (default: stdout)
  --help, -h        this help

Each JSON entry expands to types x uris x suite classic lines. deb822-only
fields and keyblock Signed-By warn and drop (classic cannot express them).`;

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
  for (const warning of unclassicable(json))
    console.error(`warn: dropping ${warning} (no classic .list spelling)`);
  const out = emitClassic(json);
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
