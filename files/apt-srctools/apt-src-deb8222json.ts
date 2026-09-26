#!/usr/bin/env -S node --strip-types
/**
 * apt-src-deb8222json.ts - convert deb822 .sources stanzas to the canonical
 * apt-srctools JSON model (see apt-src-model.ts).
 *
 * One stanza becomes one JSON entry. Multi-value fields (Types, URIs, Suites,
 * Components, Architectures) parse into arrays; Signed-By keyblocks are
 * preserved verbatim (one leading space per continuation line, "." for blank
 * lines, per sources.list(5)); unknown fields (By-Hash, X-Repolib-Name, ...)
 * pass through into "fields". Whole-line comments are dropped.
 *
 * Usage:
 *   apt-src-deb8222json.ts [--file PATH | --in PATH] [--out PATH] < file.sources
 */

import { readFile, writeFile } from "node:fs/promises";
import { parseArgs } from "node:util";
import { AptParseError, canonical, parseDeb822 } from "./apt-src-model.ts";

const USAGE = `apt-src-deb8222json.ts - deb822 .sources -> JSON

Usage:
  apt-src-deb8222json.ts [--file PATH | --in PATH] [--out PATH]

Options:
  --file, -f PATH   input file (default: stdin)
  --in PATH         alias for --file
  --out, -o PATH    output file (default: stdout)
  --help, -h        this help

One stanza = one JSON entry. Signed-By keyblocks are preserved verbatim;
unknown fields pass through into "fields"; comments are dropped.`;

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
  const json = canonical(parseDeb822(text));
  const out = JSON.stringify(json, null, 2) + "\n";
  if (args.values.out) await writeFile(args.values.out, out, "utf8");
  else process.stdout.write(out);
} catch (err) {
  if (err instanceof AptParseError) {
    console.error(`error: ${input ?? "stdin"}: ${err.message}`);
    process.exit(1);
  }
  throw err;
}
