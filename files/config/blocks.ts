/**
 * Shared CONFIG adapter for named blocks inside one explicitly adopted area.
 * It inspects caller-supplied text, writes private workspace inputs, invokes the
 * existing block-in-file CLI and returns prepared text. It never reads/writes a
 * live root or performs publication; CONFIG alone commits the returned candidate.
 * Namespace/ID markers must be well formed and contained in the area, and new
 * content cannot inject reserved management markers. Unmanaged outside text remains
 * byte-for-byte intact; native structural scope is checked by the consumer separately.
 * @see /doc/config/keybinding-consumers.md
 */
import { execFile } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";

const exec = promisify(execFile);
/** One contribution's prepared content, in explicit desired insertion order. */
export type BlockMaterial = {
  /** Stable contribution ID, not path/index; unique under the supplied namespace. */
  id: string;
  /** Native definition/reference text with no reserved area or namespace marker lines. */
  content: string;
};
/** Exact comment sentinel pair marking the operator-adopted insertion ownership. */
export type BlockArea = {
  /** Unique begin line matched after trim; must precede the end line. */
  begin: string;
  /** Unique end line; prepared contribution blocks are inserted immediately before it. */
  end: string;
};

/**
 * Locate the single ordered adoption pair without interpreting native grammar.
 * @param text Complete root/area text; no file is read or modified.
 * @param area Exact trimmed sentinel text supplied by adoption/bootstrap policy.
 * @returns Source-string offsets spanning both sentinel lines and the insertion boundary.
 * @throws On absent, duplicated or reversed sentinels. Native scope must be probed separately.
 */
export function areaOffsets(
  text: string,
  area: BlockArea,
): {
  /** Start of the begin physical line, including any original indentation. */
  start: number;
  /** End after the end physical line and its existing terminator. */
  end: number;
  /** Start of the end physical line where contribution text is inserted. */
  insert: number;
} {
  const lines = [...text.matchAll(/[^\n]*(?:\n|$)/g)].filter((match) => match[0]);
  const begins = lines.filter((line) => line[0].trim() === area.begin);
  const ends = lines.filter((line) => line[0].trim() === area.end);
  if (begins.length !== 1 || ends.length !== 1 || begins[0].index! >= ends[0].index!)
    throw new Error("root requires exactly one adopted insertion area (begin before end)");
  return {
    start: begins[0].index!,
    end: ends[0].index! + ends[0][0].length,
    insert: ends[0].index!,
  };
}

function regexEscape(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Prepare named namespace/ID blocks in a private copy of the adopted area.
 * Reject owned markers outside the area, malformed/orphaned/nested/duplicate
 * markers, unsafe IDs and reserved-marker injection. Remove only owned blocks
 * within the area, then insert the supplied ordered members; no stale file pruning
 * or arbitrary live-root takeover occurs. Timestamps/source attribution are disabled
 * so private paths and incidental time do not become persistent drift.
 * @param text Caller-captured root text, including exactly one adopted area.
 * @param blocks Closed desired named contributions, already rendered for the native context.
 * @param options Ownership/comment convention and caller-owned existing private workspace.
 * @returns Prepared full text with outside text preserved, ready for CONFIG candidate use.
 * @throws On marker/ownership/injection errors, private I/O or block-in-file failure.
 */
export async function assembleBlocks(
  text: string,
  blocks: readonly BlockMaterial[],
  options: {
    /** Explicit exact adoption pair; this adapter does not invent one in arbitrary roots. */
    area: BlockArea;
    /** Safe ownership prefix; stable full block name is namespace/contribution ID. */
    namespace: string;
    /** Native marker comment token, e.g. // for Niri or # for Umbriel. */
    comment: string;
    /** Existing private directory for block-area and per-member inputs; never a live root. */
    workspace: string;
    /** Existing CLI override; otherwise CONFIG_BLOCK_IN_FILE then block-in-file is used. */
    command?: string;
  },
): Promise<string> {
  const span = areaOffsets(text, options.area);
  if (!/^[A-Za-z0-9][A-Za-z0-9_./-]*$/.test(options.namespace))
    throw new Error("invalid block namespace");
  const ids = new Set<string>();
  const prefix = `${options.comment} ${options.namespace}/`;
  const outside = text.slice(0, span.start) + text.slice(span.end);
  if (outside.split(/\r?\n/).some((line) => line.trim().startsWith(prefix)))
    throw new Error("owned block appears outside adopted insertion area");
  const seen = new Set<string>();
  let opened: string | undefined;
  const markers = new RegExp(
    `^${regexEscape(prefix)}([A-Za-z0-9][A-Za-z0-9_.-]*) (start|end)(?:\\s.*)?$`,
  );
  for (const line of text
    .slice(span.start, span.end)
    .split(/\r?\n/)
    .map((line) => line.trim())) {
    if (!line.startsWith(prefix)) continue;
    const marker = markers.exec(line);
    if (!marker) throw new Error("malformed owned block marker");
    if (marker[2] === "start") {
      if (opened || seen.has(marker[1])) throw new Error("nested or duplicate owned block");
      opened = marker[1];
      seen.add(opened);
    } else {
      if (opened !== marker[1]) throw new Error("unmatched owned block closer");
      opened = undefined;
    }
  }
  if (opened) throw new Error("unclosed owned block");
  for (const block of blocks) {
    if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(block.id) || ids.has(block.id))
      throw new Error(`invalid or duplicate block ID ${block.id}`);
    ids.add(block.id);
    if (
      block.content
        .split(/\r?\n/)
        .some(
          (line) =>
            line.trim() === options.area.begin ||
            line.trim() === options.area.end ||
            line.trim().startsWith(prefix),
        )
    )
      throw new Error("block material contains reserved management markers");
  }
  const output = join(options.workspace, "block-area");
  await writeFile(output, text.slice(span.start, span.end));
  const command = options.command ?? process.env.CONFIG_BLOCK_IN_FILE ?? "block-in-file";
  const common = [
    "--comment",
    options.comment,
    "--timestamp=",
    "--source-attribution=false",
    "-o",
    output,
  ];
  await exec(command, [...common, "--remove-match", `^${regexEscape(options.namespace)}/`]);
  for (const [index, block] of blocks.entries()) {
    const input = join(options.workspace, `block-${index}`);
    await writeFile(input, block.content);
    await exec(command, [
      ...common,
      "-n",
      `${options.namespace}/${block.id}`,
      "-i",
      input,
      "--before",
      `^\\s*${regexEscape(options.area.end)}\\s*$`,
    ]);
  }
  const updated = await readFile(output, "utf8");
  areaOffsets(updated, options.area);
  return text.slice(0, span.start) + updated + text.slice(span.end);
}
