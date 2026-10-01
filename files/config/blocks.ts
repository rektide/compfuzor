/** Shared CONFIG block-in-file adapter over a private adopted insertion area.
 * Live publication remains the sole CONFIG runner's responsibility. */
import { execFile } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";

const exec = promisify(execFile);
export type BlockMaterial = { id: string; content: string };
export type BlockArea = { begin: string; end: string };

export function areaOffsets(text: string, area: BlockArea): { start: number; end: number; insert: number } {
  const lines = [...text.matchAll(/[^\n]*(?:\n|$)/g)].filter((match) => match[0]);
  const begins = lines.filter((line) => line[0].trim() === area.begin);
  const ends = lines.filter((line) => line[0].trim() === area.end);
  if (begins.length !== 1 || ends.length !== 1 || begins[0].index! >= ends[0].index!) throw new Error("root requires exactly one adopted insertion area (begin before end)");
  return { start: begins[0].index!, end: ends[0].index! + ends[0][0].length, insert: ends[0].index! };
}

function regexEscape(value: string): string { return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }

export async function assembleBlocks(text: string, blocks: readonly BlockMaterial[], options: {
  area: BlockArea; namespace: string; comment: string; workspace: string; command?: string;
}): Promise<string> {
  const span = areaOffsets(text, options.area);
  if (!/^[A-Za-z0-9][A-Za-z0-9_./-]*$/.test(options.namespace)) throw new Error("invalid block namespace");
  const ids = new Set<string>();
  for (const block of blocks) {
    if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(block.id) || ids.has(block.id)) throw new Error(`invalid or duplicate block ID ${block.id}`);
    ids.add(block.id);
  }
  const output = join(options.workspace, "block-area");
  await writeFile(output, text.slice(span.start, span.end));
  const command = options.command ?? process.env.CONFIG_BLOCK_IN_FILE ?? "block-in-file";
  const common = ["--comment", options.comment, "--timestamp=", "--source-attribution=false", "-o", output];
  await exec(command, [...common, "--remove-match", `^${regexEscape(options.namespace)}/`]);
  for (const [index, block] of blocks.entries()) {
    const input = join(options.workspace, `block-${index}`);
    await writeFile(input, block.content);
    await exec(command, [...common, "-n", `${options.namespace}/${block.id}`, "-i", input, "--before", `^\\s*${regexEscape(options.area.end)}\\s*$`]);
  }
  return text.slice(0, span.start) + await readFile(output, "utf8") + text.slice(span.end);
}
