#!/usr/bin/env node
/**
 * archive-large.ts — ~/archive large-dir reporter. READ-ONLY, ALWAYS.
 *
 * This tool has NO deletion path: no --apply, no rm, nothing to bypass.
 * It exists to answer one question — "what is big under ~/archive/<org>,
 * and what inside it is big?" — as the discovery half of a cleanup whose
 * destructive half (if any) stays a human decision.
 *
 * Origin (operator ask 2026-10-14): a disk-clean pass for whole rust
 * target/ removal "minus the released bins" plus node_modules. Measured
 * against the existing levers that ask was a near-noop — src-clean.ts +
 * rust-aggressive.ts already cover 11.1 of 11.6 GiB across the 138
 * ~/src cargo targets (residual: debug finals, examples/, .d/.rlib/
 * .rmeta — trash), node_modules was declined outright (pnpm store
 * semantics, see src-clean.ts), and age-based reclamation already runs
 * on the cargo-sweep timers. The surviving need was seeing which
 * archived repos hold the bytes: this bin.
 *
 * Model: ~/archive/<org>/<repo> is the archive layout (workspace
 * convention; `dl` fetches there). Orgs and repos are the real
 * directories at those two levels — files and symlinks are skipped and
 * counted, not measured. Sizes are block usage (du -s parity:
 * st_blocks × 512, hardlinks once per traversal), so a repo's listed
 * children may sum to more than the repo (per-child traversals recount
 * shared inodes) — same caveat as `du -s repo/*` vs `du -s repo`.
 *
 * Usage:
 *   archive-large.ts [--root <dir>] [--threshold 2G] [--top N]
 *
 * The default report is the plain hit list plus org subtotals; the
 * per-hit drill-down (largest entries inside each hit) is OPT-IN via
 * --top N — operator preference 2026-10-14: the detail was noise. The
 * drill-down also floors entries at 50M (--min-child; operator
 * 2026-10-14: anything smaller is irrelevant next to multi-GiB hits)
 * and takes its top N only from entries clearing that floor.
 *
 * Exit: 0 ok (hits or not — this is a report, not a check), 1 runtime
 * failure, 2 usage error.
 */

import { readdir, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { parseArgs } from "node:util";
import type { Dirent } from "node:fs";
import { UsageError, duBytes, human, isErrnoError, isRealDir } from "./lib.ts";

const PROG = "archive-large.ts";
const DEFAULT_THRESHOLD = "2G";
/** 0 = no per-hit drill-down (operator preference 2026-10-14). */
const DEFAULT_TOP = 0;
/** Drill-down floor: children below this are irrelevant (2026-10-14). */
const DEFAULT_MIN_CHILD = "50M";
const ORG_TOTALS_SHOWN = 10;

interface Repo {
	org: string;
	name: string;
	/** Absolute ~/archive/<org>/<repo> path. */
	path: string;
	/** Block-usage bytes (du -s parity). */
	bytes: bigint;
	/** Measurement walk hit permission/IO errors; size is a lower bound. */
	partial: boolean;
}

interface Child {
	name: string;
	isDir: boolean;
	bytes: bigint;
}

interface ScanResult {
	repos: readonly Repo[];
	/** Non-directory (or symlink) entries at org/repo levels, skipped. */
	nonDirs: number;
	/** Unreadable (EACCES etc.) directories, skipped quietly. */
	unreadable: number;
}

function usage(): string {
	return `usage: ${PROG} [options]

Report ~/archive/<org>/<repo> directories over a size threshold, with
each hit's largest immediate entries and org subtotals. READ-ONLY: this
tool never deletes anything and has no --apply.

options:
  --root <dir>        archive root (default: $HOME/archive)
  --threshold <size>  report repos at or above this size
                      (default: ${DEFAULT_THRESHOLD}; syntax below)
  --top <n>           OPT-IN drill-down: n largest immediate entries per
                      hit (default 0 = off)
  --min-child <size>  drill-down floor: entries below this size are not
                      listed (default 50M; 0 disables the floor)
  --help              this help

threshold syntax: a number plus optional binary unit suffix —
  2G, 2GiB, 1.5g, 512M, 64MiB, 2T, or a plain byte count (2147483648).
Units are binary (G = GiB = 2^30) to match the sizes this tool prints.

walk model: orgs are real directories directly under the root; repos
are real directories directly under each org. Files and symlinks at
either level are skipped and counted. .git/.jj are MEASURED (unlike the
cleaners' walks) — in an archive they are usually the bulk.

sizes are block usage (du -s parity: st_blocks × 512). A hit's children
may sum past the hit itself: each child traversal recounts hardlinks
the parent traversal counted once. Unreadable directories mark a size
as a lower bound and are counted in the skipped line.`;
}

/** Parse "2G"/"1.5GiB"/"512M"/plain-bytes into bytes; throws UsageError. */
function parseSize(raw: string, flag = "--threshold"): bigint {
	const match = /^(\d+(?:\.\d+)?)\s*([kKmMgGtT])?[iI]?[bB]?$/.exec(raw);
	if (match === null) {
		throw new UsageError(`${flag} cannot parse "${raw}" (try 2G, 1.5GiB, 512M, or plain bytes)`);
	}
	const value = Number(match[1]);
	const unit = (match[2] ?? "").toLowerCase();
	const multiplier = unit === "" ? 1 : unit === "k" ? 1024 : unit === "m" ? 1024 ** 2 : unit === "g" ? 1024 ** 3 : 1024 ** 4;
	const bytes = Math.round(value * multiplier);
	if (!Number.isFinite(bytes) || bytes <= 0 || bytes > Number.MAX_SAFE_INTEGER) {
		throw new UsageError(`${flag} out of range: "${raw}"`);
	}
	return BigInt(bytes);
}

/** Real directories at one level of the tree; non-dirs and read errors counted. */
async function realDirs(
	dir: string,
	scan: { nonDirs: number; unreadable: number },
): Promise<readonly string[]> {
	let entries: Dirent[];
	try {
		entries = await readdir(dir, { withFileTypes: true });
	} catch (error) {
		if (!isErrnoError(error)) throw error;
		scan.unreadable++;
		return [];
	}
	const names: string[] = [];
	for (const entry of entries) {
		const entryPath = join(dir, entry.name);
		if (await isRealDir(entryPath)) {
			names.push(entry.name);
		} else {
			scan.nonDirs++;
		}
	}
	return names;
}

async function scan(root: string): Promise<ScanResult> {
	const scan = { nonDirs: 0, unreadable: 0 };
	const repos: Repo[] = [];
	const orgs = await realDirs(root, scan);
	await Promise.all(
		orgs.map(async (org) => {
			const repoNames = await realDirs(join(root, org), scan);
			await Promise.all(
				repoNames.map(async (name) => {
					const path = join(root, org, name);
					const { bytes, errors } = await duBytes(path);
					repos.push({ org, name, path, bytes, partial: errors > 0 });
				}),
			);
		}),
	);
	return { repos, nonDirs: scan.nonDirs, unreadable: scan.unreadable };
}

/**
 * Largest immediate entries of a hit clearing minBytes: duBytes per
 * entry, filtered, sorted desc, capped at top.
 */
async function largestChildren(path: string, top: number, minBytes: bigint): Promise<readonly Child[]> {
	let entries: Dirent[];
	try {
		entries = await readdir(path, { withFileTypes: true });
	} catch (error) {
		if (!isErrnoError(error)) throw error;
		return [];
	}
	const measured = await Promise.all(
		entries.map(async (entry) => {
			// No .catch here: duBytes already swallows errno errors; letting a
			// non-errno throw propagate is the lib.ts rethrow rule (bin bugs
			// must not become silent 0-byte rows).
			const { bytes } = await duBytes(join(path, entry.name));
			return { name: entry.name, isDir: entry.isDirectory(), bytes } satisfies Child;
		}),
	);
	const relevant = measured.filter((child) => child.bytes >= minBytes);
	const sorted = relevant.sort((a, b) => (a.bytes < b.bytes ? 1 : a.bytes > b.bytes ? -1 : 0));
	return sorted.slice(0, top);
}

async function report(
	root: string,
	result: ScanResult,
	threshold: bigint,
	top: number,
	minChild: bigint,
): Promise<string> {
	const lines: string[] = [];
	const hits = [...result.repos].filter((repo) => repo.bytes >= threshold).sort((a, b) => (a.bytes < b.bytes ? 1 : a.bytes > b.bytes ? -1 : 0));
	const hitsTotal = hits.reduce((sum, repo) => sum + repo.bytes, 0n);
	const rootTotal = result.repos.reduce((sum, repo) => sum + repo.bytes, 0n);
	const orgs = new Map<string, { bytes: bigint; repos: number; over: number }>();
	for (const repo of result.repos) {
		const entry = orgs.get(repo.org) ?? { bytes: 0n, repos: 0, over: 0 };
		entry.bytes += repo.bytes;
		entry.repos++;
		if (repo.bytes >= threshold) entry.over++;
		orgs.set(repo.org, entry);
	}

	lines.push(`${PROG}: READ-ONLY report — this tool never deletes anything`);
	lines.push(`root: ${root}  threshold: ${human(threshold)}`);
	lines.push("");
	lines.push(`repos at/over threshold: ${hits.length} of ${result.repos.length} (${human(hitsTotal)}; archive total ${human(rootTotal)})`);
	if (hits.length === 0) {
		lines.push("  (none found)");
	} else {
		lines.push("       SIZE  ORG/REPO");
		for (const hit of hits) {
			const note = hit.partial ? "  [partial: size is a lower bound]" : "";
			lines.push(`${human(hit.bytes).padStart(10)}  ${hit.org}/${hit.name}${note}`);
		}
	}
	if (top > 0 && hits.length > 0) {
		lines.push("");
		const floorNote = minChild > 0n ? `, entries under ${human(minChild)} omitted` : "";
		lines.push(`largest entries inside each hit (top ${top}${floorNote}; children can sum past the hit — hardlinks):`);
		for (const hit of hits) {
			lines.push(`  ${hit.org}/${hit.name}`);
			const children = await largestChildren(hit.path, top, minChild);
			if (children.length === 0) {
				lines.push(minChild > 0n ? `    (no entries at/over ${human(minChild)})` : "    (unreadable)");
			}
			for (const child of children) {
				lines.push(`${human(child.bytes).padStart(12)}  ${child.name}${child.isDir ? "/" : ""}`);
			}
		}
	}
	lines.push("");
	lines.push(`org subtotals (top ${ORG_TOTALS_SHOWN} of ${orgs.size}; sums repos only):`);
	const orgList = [...orgs.entries()].sort((a, b) => (a[1].bytes < b[1].bytes ? 1 : a[1].bytes > b[1].bytes ? -1 : 0));
	for (const [org, entry] of orgList.slice(0, ORG_TOTALS_SHOWN)) {
		lines.push(`${human(entry.bytes).padStart(10)}  ${org} (${entry.repos} repo${entry.repos === 1 ? "" : "s"}, ${entry.over} over)`);
	}
	lines.push("");
	lines.push(`skipped: ${result.unreadable} unreadable dir(s) (quiet), ${result.nonDirs} non-directory entrie(s) at org/repo level`);
	return lines.join("\n");
}

async function main(argv: string[]): Promise<number> {
	const { values } = parseArgs({
		args: argv,
		options: {
			root: { type: "string" },
			threshold: { type: "string" },
			top: { type: "string" },
			"min-child": { type: "string" },
			help: { type: "boolean", default: false },
		},
	});
	if (values.help) {
		console.log(usage());
		return 0;
	}
	const threshold = parseSize(values.threshold ?? DEFAULT_THRESHOLD);
	// "0" disables the drill-down floor; parseSize proper rejects ≤ 0
	// (correct for --threshold, where 0 would report everything).
	const minChild = values["min-child"] === "0" ? 0n : parseSize(values["min-child"] ?? DEFAULT_MIN_CHILD, "--min-child");
	const topRaw = values.top ?? String(DEFAULT_TOP);
	const top = Number.parseInt(topRaw, 10);
	if (!Number.isInteger(top) || top < 0 || top > 50) {
		throw new UsageError(`--top expects an integer 0..50 (got "${topRaw}")`);
	}
	const rootPath = values.root ?? join(homedir(), "archive");
	try {
		const rootStat = await stat(rootPath);
		if (!rootStat.isDirectory()) {
			throw new UsageError(`--root is not a directory: ${rootPath}`);
		}
	} catch (error) {
		if (error instanceof UsageError) throw error;
		throw new UsageError(`--root is unreadable or missing: ${rootPath} (${(error as NodeJS.ErrnoException).code ?? error})`);
	}

	const result = await scan(rootPath);
	console.log(await report(rootPath, result, threshold, top, minChild));
	return 0;
}

try {
	const code = await main(process.argv.slice(2));
	process.exitCode = code;
} catch (error) {
	if (error instanceof UsageError) {
		console.error(`${PROG}: ${error.message}`);
		console.error(`${PROG}: try --help`);
		process.exitCode = error.code;
	} else {
		console.error(`${PROG}:`, error);
		process.exitCode = 1;
	}
}
