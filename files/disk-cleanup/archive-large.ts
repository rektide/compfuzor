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
 * Grouping (operator policy 2026-10-18): the archive holds repos we
 * have jj workspaces for; plain clones are the pool for moving to
 * /mnt/bitblaster/archive (nanomachine's NFSv4.2 export, identically
 * pathed on both hosts) and symlinking back. So hits are reported per
 * kind: no-.jj git clones (move candidates), with-.jj (keep local),
 * and neither-marker dirs (inspect before treating as movable). A repo
 * whose path is already a symlink into /mnt/bitblaster is counted as
 * moved — its bytes now live on NFS and are deliberately not walked:
 * this report is the local disk's truth, not the mount's.
 *
 * Size cache (operator ask 2026-10-18): every measured repo's size is
 * remembered in <root>/.archive-large.du (hidden, du-style
 * bytes<TAB>org/repo lines, atomically rewritten at the end of each
 * run). A run loads it first, tags repos missing from it [new], then
 * re-checks cached repos — largest cached first — re-reporting the ones
 * whose size has moved at least --delta (default 10M) as change
 * records `old -> new (+/-delta)` (--no-old-size omits the old size).
 * The cache is the run-to-run memory that turns "what is big" into
 * "what is big AND changing".
 *
 * Model: ~/archive/<org>/<repo> is the archive layout (workspace
 * convention; `dl` fetches there). Orgs and repos are the real
 * directories at those two levels — files and symlinks are skipped and
 * counted, not measured (repo-level symlinks additionally classified
 * moved/alias). Sizes are block usage (du -s parity:
 * st_blocks × 512, hardlinks once per traversal), so a repo's listed
 * children may sum to more than the repo (per-child traversals recount
 * shared inodes) — same caveat as `du -s repo/*` vs `du -s repo`.
 *
 * Usage:
 *   archive-large.ts [--root <dir>] [--threshold 2G] [--top N]
 *                    [--delta 10M] [--no-old-size] [--no-cache]
 *                    [--cache <file>]
 *
 * The default report is the grouped hit list plus org subtotals; the
 * per-hit drill-down (largest entries inside each hit) is OPT-IN via
 * --top N — operator preference 2026-10-14: the detail was noise. The
 * drill-down also floors entries at 50M (--min-child; operator
 * 2026-10-14: anything smaller is irrelevant next to multi-GiB hits)
 * and takes its top N only from entries clearing that floor.
 *
 * Exit: 0 ok (hits or not — this is a report, not a check), 1 runtime
 * failure, 2 usage error.
 */

import { readFile, readlink, readdir, rename, stat, writeFile } from "node:fs/promises";
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
/** Change-record floor: cached repos moving less than this stay silent (2026-10-18). */
const DEFAULT_DELTA = "10M";
const ORG_TOTALS_SHOWN = 10;
/**
 * Repo-level symlinks pointing in here count as "already moved to
 * bitblaster" (nanomachine NFSv4.2 export, identically pathed on both
 * hosts — the established move convention mv's the repo to
 * /mnt/bitblaster/archive/<org>/<repo> and symlinks the old path back).
 * Anything else a repo symlink points at is an alias, counted only.
 */
const MOVED_PREFIX = "/mnt/bitblaster/";
/**
 * Size cache: hidden du-style file at the archive root (operator habit:
 * ~/archive/*.du). Bytes TAB org/repo per measured repo, "#" comments.
 */
const CACHE_FILENAME = ".archive-large.du";

type RepoKind = "plain" | "workspace" | "nonrepo";

/** Report sections in this order; titles carry the archive policy. */
const GROUPS: readonly { kind: RepoKind; title: string }[] = [
	{ kind: "plain", title: "no jj workspace — plain git clones (move candidates)" },
	{ kind: "workspace", title: "with jj workspace (keep local)" },
	{ kind: "nonrepo", title: "no .git/.jj — not a repo (inspect before moving)" },
];

interface Repo {
	org: string;
	name: string;
	/** Absolute ~/archive/<org>/<repo> path. */
	path: string;
	/** Block-usage bytes (du -s parity). */
	bytes: bigint;
	/** Measurement walk hit permission/IO errors; size is a lower bound. */
	partial: boolean;
	kind: RepoKind;
	/** org/repo — cache key. */
	key: string;
	/** Cached size from the loaded cache, when present. */
	cached?: bigint;
}

interface Child {
	name: string;
	isDir: boolean;
	bytes: bigint;
}

interface ScanResult {
	repos: readonly Repo[];
	/** org/repo paths already symlinked into MOVED_PREFIX (not measured). */
	moved: readonly string[];
	/** Non-directory (or org-level symlink) entries, skipped. */
	nonDirs: number;
	/** Repo-level symlinks NOT into MOVED_PREFIX, skipped. */
	aliases: number;
	/** Unreadable (EACCES etc.) directories, skipped quietly. */
	unreadable: number;
}

interface CacheOutcome {
	/** org/repo -> cached bytes. Empty when absent or unreadable. */
	entries: Map<string, bigint>;
	/** Cache file was found and loaded (gates [new] tags + change records). */
	present: boolean;
	/** Where it came from, for the header line. */
	path: string;
	/** stat().mtimeMs of the cache file, when it exists. */
	writtenAt?: number;
	/** Unparseable lines skipped with a stderr warning. */
	badLines: number;
}

function usage(): string {
	return `usage: ${PROG} [options]

Report ~/archive/<org>/<repo> directories over a size threshold,
GROUPED by workspace status, with each hit's largest immediate entries
and org subtotals. READ-ONLY: this tool never deletes anything and has
no --apply. Run-to-run size changes are tracked through a cache.

options:
  --root <dir>        archive root (default: $HOME/archive)
  --threshold <size>  report repos at or above this size
                      (default: ${DEFAULT_THRESHOLD}; syntax below)
  --top <n>           OPT-IN drill-down: n largest immediate entries per
                      hit (default 0 = off)
  --min-child <size>  drill-down floor: entries below this size are not
                      listed (default 50M; 0 disables the floor)
  --delta <size>      change-record floor: cached repos whose size moved
                      at least this much since the cache are re-reported
                      (default ${DEFAULT_DELTA}; 0 reports every change)
  --no-old-size       change records show only the new size (default:
                      "old -> new (+/-delta)" with both sizes)
  --cache <file>      size cache file (default: <root>/${CACHE_FILENAME})
  --no-cache          do not load or write the size cache
  --help              this help

threshold syntax: a number plus optional binary unit suffix —
  2G, 2GiB, 1.5g, 512M, 64MiB, 2T, or a plain byte count (2147483648).
Units are binary (G = GiB = 2^30) to match the sizes this tool prints.

walk model: orgs are real directories directly under the root; repos
are real directories directly under each org, classified by marker —
.jj → workspace (keep local), .git alone → plain clone (move
candidate), neither → nonrepo. Repo-level symlinks into
${MOVED_PREFIX}... are counted as already moved (their bytes live on
NFS and are not walked — this report is the local disk's truth); other
symlinks and files at either level are skipped and counted. .git/.jj
are MEASURED (unlike the cleaners' walks) — in an archive they are
usually the bulk.

cache model: every measured repo's size is written to the cache
(<root>/${CACHE_FILENAME} by default — hidden, du-style
bytes<TAB>org/repo, atomically replaced at the end of the run). The
next run loads it, tags repos not in it [new], and re-reports cached
repos whose size moved at least --delta as change records, largest
cached size first. Cached entries whose repo no longer measures (moved
to bitblaster, deleted) are dropped from the rewritten cache and
counted in the report.

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

/** readdir with dirents; unreadable dirs counted, not thrown. */
async function readDirents(dir: string, scan: { unreadable: number }): Promise<readonly Dirent[]> {
	try {
		return await readdir(dir, { withFileTypes: true });
	} catch (error) {
		if (!isErrnoError(error)) throw error;
		scan.unreadable++;
		return [];
	}
}

/** Real directories at one level of the tree; non-dirs and read errors counted. */
async function realDirs(
	dir: string,
	scan: { nonDirs: number; unreadable: number },
): Promise<readonly string[]> {
	const entries = await readDirents(dir, scan);
	const names: string[] = [];
	for (const entry of entries) {
		if (await isRealDir(join(dir, entry.name))) {
			names.push(entry.name);
		} else {
			scan.nonDirs++;
		}
	}
	return names;
}

/** stat() existence; errno → false (EACCES reads as absent — markers are 0755 in practice), other errors rethrow. */
async function pathExists(path: string): Promise<boolean> {
	try {
		await stat(path);
		return true;
	} catch (error) {
		if (isErrnoError(error)) return false;
		throw error;
	}
}

/**
 * Kind of a repo dir. .jj (dir, or a stale file remnant) wins over .git —
 * a colocated jj repo is a workspace even though .git sits beside .jj.
 * A .git FILE (worktree/submodule pointer) still marks a git repo.
 */
async function classifyRepo(path: string): Promise<RepoKind> {
	if (await pathExists(join(path, ".jj"))) return "workspace";
	if (await pathExists(join(path, ".git"))) return "plain";
	return "nonrepo";
}

async function scan(root: string, cache: CacheOutcome): Promise<ScanResult> {
	const scan = { nonDirs: 0, unreadable: 0, aliases: 0 };
	const repos: Repo[] = [];
	const moved: string[] = [];
	const orgs = await realDirs(root, scan);
	await Promise.all(
		orgs.map(async (org) => {
			const entries = await readDirents(join(root, org), scan);
			await Promise.all(
				entries.map(async (entry) => {
					const path = join(root, org, entry.name);
					if (entry.isSymbolicLink()) {
						const target = await readlink(path);
						if (target.startsWith(MOVED_PREFIX)) {
							moved.push(`${org}/${entry.name}`);
						} else {
							scan.aliases++;
						}
						return;
					}
					if (!(await isRealDir(path))) {
						scan.nonDirs++;
						return;
					}
					const kind = await classifyRepo(path);
					const { bytes, errors } = await duBytes(path);
					const key = `${org}/${entry.name}`;
					repos.push({ org, name: entry.name, path, bytes, partial: errors > 0, kind, key, cached: cache.entries.get(key) });
				}),
			);
		}),
	);
	return { repos, moved, nonDirs: scan.nonDirs, aliases: scan.aliases, unreadable: scan.unreadable };
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

/** Load the size cache; absent file is a clean first run, not an error. */
async function loadCache(path: string): Promise<CacheOutcome> {
	const outcome: CacheOutcome = { entries: new Map(), present: false, path, badLines: 0 };
	try {
		const info = await stat(path);
		if (!info.isFile()) {
			console.error(`${PROG}: cache path is not a file: ${path} — continuing without cache`);
			return outcome;
		}
		outcome.writtenAt = info.mtimeMs;
		const text = await readFile(path, "utf8");
		for (const rawLine of text.split("\n")) {
			const line = rawLine.trimEnd();
			if (line === "" || line.startsWith("#")) continue;
			const match = /^(\d+)\t(.+)$/.exec(line);
			if (match === null || !match[2].includes("/")) {
				outcome.badLines++;
				continue;
			}
			outcome.entries.set(match[2], BigInt(match[1]));
		}
		outcome.present = true;
	} catch (error) {
		if (!isErrnoError(error)) throw error;
		// ENOENT (or EACCES): first run / unreadable — report says so.
	}
	return outcome;
}

/** Atomically rewrite the cache with every measured repo, largest first. */
async function writeCache(path: string, repos: readonly Repo[]): Promise<void> {
	const sorted = [...repos].sort((a, b) => (a.bytes < b.bytes ? 1 : a.bytes > b.bytes ? -1 : a.key.localeCompare(b.key)));
	const lines = [
		`# ${PROG} size cache v1 — bytes<TAB>org/repo (block usage, du -s parity)`,
		`# written ${new Date().toISOString()} — rewritten in full at the end of every run`,
	];
	for (const repo of sorted) {
		lines.push(`${repo.bytes}\t${repo.key}`);
	}
	const tmp = `${path}.tmp`;
	await writeFile(tmp, `${lines.join("\n")}\n`, "utf8");
	await rename(tmp, path);
}

function byBytesDesc(a: Repo, b: Repo): number {
	return a.bytes < b.bytes ? 1 : a.bytes > b.bytes ? -1 : 0;
}

/** "+2.6 GiB" / "-3.0 MiB" for change-record deltas. */
function signedDelta(bytes: bigint): string {
	const sign = bytes < 0n ? "-" : "+";
	const abs = bytes < 0n ? -bytes : bytes;
	return `${sign}${human(abs)}`;
}

async function report(
	root: string,
	result: ScanResult,
	cache: CacheOutcome,
	threshold: bigint,
	top: number,
	minChild: bigint,
	delta: bigint,
	oldSizeShown: boolean,
): Promise<string> {
	const lines: string[] = [];
	const sorted = [...result.repos].sort(byBytesDesc);
	const rootTotal = sorted.reduce((sum, repo) => sum + repo.bytes, 0n);
	const allHits = sorted.filter((repo) => repo.bytes >= threshold);
	const allHitsTotal = allHits.reduce((sum, repo) => sum + repo.bytes, 0n);
	const orgs = new Map<string, { bytes: bigint; repos: number; over: number }>();
	for (const repo of sorted) {
		const entry = orgs.get(repo.org) ?? { bytes: 0n, repos: 0, over: 0 };
		entry.bytes += repo.bytes;
		entry.repos++;
		if (repo.bytes >= threshold) entry.over++;
		orgs.set(repo.org, entry);
	}

	lines.push(`${PROG}: READ-ONLY report — this tool never deletes anything`);
	lines.push(`root: ${root}  threshold: ${human(threshold)}`);
	if (cache.present) {
		const cachedTotal = sorted.reduce((sum, repo) => sum + (repo.cached ?? 0n), 0n);
		const written = cache.writtenAt === undefined ? "" : `, written ${new Date(cache.writtenAt).toISOString()}`;
		lines.push(
			`cache: ${cache.path} — ${cache.entries.size} entries${written} (last run's archive total: ${human(cachedTotal)})${cache.badLines > 0 ? ` [${cache.badLines} bad line(s) skipped]` : ""}`,
		);
	} else {
		lines.push(`cache: none at ${cache.path} — first run; sizes cached for next time`);
	}
	lines.push("");
	lines.push(
		`repos at/over threshold: ${allHits.length} of ${sorted.length} (${human(allHitsTotal)}; archive total ${human(rootTotal)}; ${result.moved.length} already moved to bitblaster, not walked)`,
	);
	const fresh = sorted.filter((repo) => repo.cached === undefined);
	if (cache.present && fresh.length > 0) {
		lines.push(`new since cache: ${fresh.length} repo(s), tagged [new] below`);
	}
	for (const group of GROUPS) {
		const repos = sorted.filter((repo) => repo.kind === group.kind);
		const total = repos.reduce((sum, repo) => sum + repo.bytes, 0n);
		const hits = repos.filter((repo) => repo.bytes >= threshold);
		const hitsTotal = hits.reduce((sum, repo) => sum + repo.bytes, 0n);
		lines.push("");
		lines.push(
			`${group.title}: ${repos.length} repo(s), ${human(total)} total — ${hits.length} at/over ${human(threshold)} (${human(hitsTotal)})`,
		);
		if (hits.length === 0) {
			lines.push(`  (no hits at/over ${human(threshold)})`);
			continue;
		}
		lines.push("       SIZE  ORG/REPO");
		for (const hit of hits) {
			const note = hit.partial ? "  [partial: size is a lower bound]" : "";
			const isNew = cache.present && hit.cached === undefined ? "  [new]" : "";
			lines.push(`${human(hit.bytes).padStart(10)}  ${hit.org}/${hit.name}${note}${isNew}`);
		}
		if (top > 0) {
			const floorNote = minChild > 0n ? `, entries under ${human(minChild)} omitted` : "";
			lines.push(`  largest entries inside each hit (top ${top}${floorNote}; children can sum past the hit — hardlinks):`);
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
	}
	if (cache.present) {
		const changed = sorted
			.filter((repo) => {
				if (repo.cached === undefined) return false;
				const diff = repo.bytes > repo.cached ? repo.bytes - repo.cached : repo.cached - repo.bytes;
				return delta === 0n ? repo.bytes !== repo.cached : diff >= delta;
			})
			.sort((a, b) => {
				// Largest cached first — the operator's re-check order.
				const ac = a.cached ?? 0n;
				const bc = b.cached ?? 0n;
				return ac < bc ? 1 : ac > bc ? -1 : 0;
			});
		const dropped = cache.entries.size - sorted.filter((repo) => repo.cached !== undefined).length;
		lines.push("");
		const floorWord = delta === 0n ? "any change" : `moved ≥ ${human(delta)}`;
		lines.push(`changed since cache (${floorWord}; largest cached first):`);
		if (changed.length === 0) {
			lines.push(`  (no cached repo ${floorWord})`);
		} else if (oldSizeShown) {
			lines.push("        OLD -> NEW  (DELTA)  ORG/REPO");
			for (const repo of changed) {
				const diff = repo.bytes - (repo.cached ?? 0n);
				lines.push(
					`${human(repo.cached ?? 0n).padStart(10)} -> ${human(repo.bytes).padStart(10)}  (${signedDelta(diff)})  ${repo.org}/${repo.name}`,
				);
			}
		} else {
			lines.push("         NEW  (DELTA)  ORG/REPO");
			for (const repo of changed) {
				const diff = repo.bytes - (repo.cached ?? 0n);
				lines.push(`${human(repo.bytes).padStart(10)}  (${signedDelta(diff)})  ${repo.org}/${repo.name}`);
			}
		}
		if (dropped > 0) {
			lines.push(`  (${dropped} cached entr${dropped === 1 ? "y" : "ies"} no longer measured — moved away or deleted; dropped from cache)`);
		}
	}
	lines.push("");
	lines.push(`org subtotals (top ${ORG_TOTALS_SHOWN} of ${orgs.size}; sums repos only):`);
	const orgList = [...orgs.entries()].sort((a, b) => (a[1].bytes < b[1].bytes ? 1 : a[1].bytes > b[1].bytes ? -1 : 0));
	for (const [org, entry] of orgList.slice(0, ORG_TOTALS_SHOWN)) {
		lines.push(`${human(entry.bytes).padStart(10)}  ${org} (${entry.repos} repo${entry.repos === 1 ? "" : "s"}, ${entry.over} over)`);
	}
	lines.push("");
	lines.push(
		`skipped: ${result.unreadable} unreadable dir(s) (quiet), ${result.nonDirs} non-directory entrie(s), ${result.aliases} repo symlink(s) to elsewhere`,
	);
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
			delta: { type: "string" },
			"no-old-size": { type: "boolean", default: false },
			cache: { type: "string" },
			"no-cache": { type: "boolean", default: false },
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
	// Same 0-means-off convention for the change-record floor.
	const delta = values.delta === "0" ? 0n : parseSize(values.delta ?? DEFAULT_DELTA, "--delta");
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
	const cachePath = values.cache ?? join(rootPath, CACHE_FILENAME);

	const cache = values["no-cache"]
		? ({ entries: new Map(), present: false, path: cachePath, badLines: 0 } satisfies CacheOutcome)
		: await loadCache(cachePath);
	const result = await scan(rootPath, cache);
	console.log(await report(rootPath, result, cache, threshold, top, minChild, delta, !values["no-old-size"]));
	if (!values["no-cache"]) {
		try {
			await writeCache(cachePath, result.repos);
		} catch (error) {
			console.error(`${PROG}: cache write failed: ${cachePath} (${error instanceof Error ? error.message : error})`);
			return 1;
		}
	}
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
