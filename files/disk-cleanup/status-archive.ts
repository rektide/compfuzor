#!/usr/bin/env node
/**
 * status-archive.ts — ~/archive status reporter. READ-ONLY, ALWAYS.
 *
 * This tool has NO deletion path: no --apply, no rm, nothing to bypass.
 * It answers "what is under ~/archive, how big, in what condition, and
 * what changed since last look" — the discovery half of cleanup and
 * archival moves whose destructive halves stay human decisions.
 *
 * History: born 2026-10-14 as archive-large.ts (a large-dir reporter
 * after the whole-target hollowing ask was measured a near-noop next to
 * src-clean.ts + rust-aggressive.ts); renamed and widened 2026-10-18
 * when the operator made the archive org-centric and policy-bound:
 * the archive holds repos we have jj workspaces for, plain clones are
 * the move pool to /mnt/bitblaster/archive (nanomachine NFSv4.2,
 * identically pathed on both hosts; the move convention mv's the repo
 * and symlinks the old path back — repo-level symlinks only, never
 * org-level). This reporter makes that policy visible.
 *
 * Classification: every repo dir is one class —
 *   workspace     has .jj → keep local (junk inside is REPORTED, never
 *                 cleared by the move exercise: workspaces are expected
 *                 to hold stuff)
 *   plain-clean   git clone, no .jj, and git agrees nothing is ours:
 *                 clean status, no commits outside remote-reachable
 *                 refs, no stashes → move candidate
 *   plain-flagged git clone with local state (dirty status / unpushed
 *                 commits / stashes / git errors) → review before moving
 *   nonrepo       neither .git nor .jj → inspect before treating as
 *                 movable
 * A repo whose path is already a symlink into /mnt/bitblaster counts
 * as moved — its bytes live on NFS and are deliberately not walked:
 * this report is the local disk's truth, not the mount's.
 *
 * Org-centricity: the default report is per-repo, grouped by class;
 * --dirs flips to the org view (whole orgs at a time is how moves are
 * planned). Group and org sections carry per-group du subtotals.
 *
 * Size caches — attributed du, per class, hidden and cheeky
 * (operator spec 2026-10-18): every measured repo's size AND its
 * attributes land in <root>/.status-archive.<class>.du+jsonl —
 * JSON-lines one object per repo: bytes, flags, and the junk
 * attributes (node_modules/target sizes) so the cache is not just du
 * but du-plus-classification. Moved symlinks get their own file with
 * link targets. Caches are rewritten in full, atomically, at the end
 * of every run. A run loads them, tags repos missing from them [new],
 * and re-reports cached repos whose size moved at least --delta
 * (default 10M) as change records `old -> new (+/-delta)` ordered
 * largest-cached-first (--no-old-size omits the old size). Entries
 * whose repo stopped measuring drop out of the rewrite and are
 * counted in the report.
 *
 * Junk reporting: node_modules/ and rust target/ sizes are measured
 * per repo and reported as aggregates + top offenders under "reported,
 * not touched" — reclaiming them is a separate exercise from moving.
 *
 * Model: ~/archive/<org>/<repo> is the archive layout (`dl` fetches
 * there). Orgs and repos are real directories at those two levels —
 * files and symlinks are skipped and counted, not measured. Sizes are
 * block usage (du -s parity: st_blocks × 512, hardlinks once per
 * traversal); a repo's listed children may sum past the repo (per-child
 * traversals recount shared inodes) — same caveat as `du -s repo/*`.
 *
 * Usage:
 *   status-archive.ts [--root <dir>] [--threshold 60M] [--top N] [--dirs]
 *                     [--delta 10M] [--no-old-size] [--no-cache]
 *                     [--cache-stem <prefix>]
 *
 * Exit: 0 ok (hits or not — this is a report, not a check), 1 runtime
 * failure, 2 usage error.
 */

import { readFile, readlink, readdir, rename, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import { parseArgs } from "node:util";
import type { Dirent } from "node:fs";
import { UsageError, capture, duBytes, human, isErrnoError, isRealDir } from "./lib.ts";

const PROG = "status-archive.ts";
/** Operator 2026-10-18: 2G only ever showed the extremes; 60M is the working floor. */
const DEFAULT_THRESHOLD = "60M";
/** 0 = no per-hit drill-down (operator preference 2026-10-14, carried over). */
const DEFAULT_TOP = 0;
/** Drill-down floor: children below this are irrelevant (2026-10-14). */
const DEFAULT_MIN_CHILD = "50M";
/** Change-record floor: cached repos moving less than this stay silent (2026-10-18). */
const DEFAULT_DELTA = "10M";
/** Junk top-offenders lists: entries at/over this, at most this many (2026-10-18). */
const JUNK_FLOOR = 100n * 1024n ** 2n;
const JUNK_TOP = 8;
const ORG_TOTALS_SHOWN = 10;
/**
 * Repo-level symlinks pointing in here count as "already moved to
 * bitblaster" (nanomachine NFSv4.2 export, identically pathed on both
 * hosts). Anything else a repo symlink points at is an alias, counted
 * only.
 */
const MOVED_PREFIX = "/mnt/bitblaster/";
/** Cache files: <stem>.<class>.du+jsonl under the archive root (hidden). */
const CACHE_STEM_BASENAME = ".status-archive";

type Class = "plain-clean" | "plain-flagged" | "workspace" | "nonrepo";

/** Report sections in this order; titles carry the archive policy. */
const CLASSES: readonly { cls: Class; title: string }[] = [
	{ cls: "plain-clean", title: "plain git clones, nothing of ours (move candidates)" },
	{ cls: "plain-flagged", title: "plain git clones with local state (review before moving)" },
	{ cls: "workspace", title: "with jj workspace (keep local)" },
	{ cls: "nonrepo", title: "no .git/.jj (inspect before moving)" },
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
	cls: Class;
	/** plain-repo git findings: dirty-status / unpushed / stashes / git-error. */
	flags: readonly string[];
	/** node_modules/ block usage, when present. Reported, never touched. */
	junkNodeModules?: bigint;
	/** rust target/ block usage, when present. Reported, never touched. */
	junkTarget?: bigint;
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

interface CacheEntry {
	bytes: bigint;
	flags: readonly string[];
}

interface CacheOutcome {
	/** org/repo -> cached entry. Empty when absent or unreadable. */
	entries: Map<string, CacheEntry>;
	/** At least one cache file loaded with parseable lines (gates [new]/change sections). */
	present: boolean;
	/** Loaded file names, for the header line. */
	files: readonly string[];
	/** Unparseable lines skipped with a stderr warning. */
	badLines: number;
}

function usage(): string {
	return `usage: ${PROG} [options]

Report ~/archive status: repos grouped by class (move candidates /
flagged / workspaces / nonrepos), org view on request, junk inside
kept repos reported-not-touched, and run-to-run size changes through
attributed per-class caches. READ-ONLY: this tool never deletes
anything and has no --apply.

options:
  --root <dir>          archive root (default: $HOME/archive)
  --threshold <size>    report repos at or above this size
                        (default: ${DEFAULT_THRESHOLD}; syntax below)
  --dirs                ORG VIEW instead of per-repo sections: whole
                        orgs at/over threshold with their class mix —
                        moves are planned org by org
  --top <n>             OPT-IN drill-down: n largest immediate entries
                        per hit (default 0 = off)
  --min-child <size>    drill-down floor: entries below this size are
                        not listed (default 50M; 0 disables the floor)
  --delta <size>        change-record floor: cached repos whose size
                        moved at least this much since the cache are
                        re-reported (default ${DEFAULT_DELTA}; 0 reports
                        every change)
  --no-old-size         change records show only the new size (default:
                        "old -> new (+/-delta)" with both sizes)
  --cache-stem <prefix> cache file prefix; caches are
                        <prefix>.<class>.du+jsonl
                        (default: <root>/${CACHE_STEM_BASENAME})
  --no-cache            do not load or write the size caches
  --help                this help

threshold syntax: a number plus optional binary unit suffix —
  2G, 2GiB, 1.5g, 512M, 64MiB, 2T, or a plain byte count (2147483648).
Units are binary (G = GiB = 2^30) to match the sizes this tool prints.

walk model: orgs are real directories directly under the root; repos
are real directories directly under each org, classified by marker and
(for plain clones) live git checks — clean status, no commits outside
remote-reachable refs, no stashes → plain-clean; anything else →
plain-flagged. Repo-level symlinks into ${MOVED_PREFIX}... are counted
as already moved (their bytes live on NFS and are not walked — this
report is the local disk's truth); other symlinks and files at either
level are skipped and counted. .git/.jj ARE measured — in an archive
they are usually the bulk.

cache model: one hidden JSON-lines file per class,
<root>/${CACHE_STEM_BASENAME}.<class>.du+jsonl, each line an attributed
du record {org, repo, bytes, flags?, node_modules?, target?}; moved
symlinks get a file of {org, repo, target}. Rewritten in full and
atomically at the end of every run. The next run loads them, tags
repos not in them [new], and re-reports cached repos whose size moved
at least --delta as change records, largest cached size first. Cached
entries whose repo no longer measures are dropped from the rewrite and
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
async function classifyRepo(path: string): Promise<"workspace" | "plain" | "nonrepo"> {
	if (await pathExists(join(path, ".jj"))) return "workspace";
	if (await pathExists(join(path, ".git"))) return "plain";
	return "nonrepo";
}

/**
 * Live git findings for a plain clone. `git status` refreshes the index
 * (a write to .git/index) — accepted as the least-invasive honest check;
 * nothing content-bearing is touched.
 */
async function plainFlags(path: string): Promise<readonly string[]> {
	const flags: string[] = [];
	const status = await capture("git", ["-C", path, "status", "--porcelain"], 60_000);
	if (status === null) return ["git-error"];
	if (status.trim() !== "") flags.push("dirty-status");
	const unpushed = await capture("git", ["-C", path, "log", "--all", "--not", "--remotes", "--oneline"], 60_000);
	if (unpushed !== null && unpushed.trim() !== "") flags.push("unpushed");
	const stashes = await capture("git", ["-C", path, "stash", "list"], 60_000);
	if (stashes !== null && stashes.trim() !== "") flags.push("stashes");
	return flags;
}

async function scan(root: string, cache: CacheOutcome): Promise<ScanResult> {
	const walk = { nonDirs: 0, unreadable: 0, aliases: 0 };
	const repos: Repo[] = [];
	const moved: string[] = [];
	const orgs = await realDirs(root, walk);
	await Promise.all(
		orgs.map(async (org) => {
			const entries = await readDirents(join(root, org), walk);
			await Promise.all(
				entries.map(async (entry) => {
					const path = join(root, org, entry.name);
					if (entry.isSymbolicLink()) {
						const target = await readlink(path);
						if (target.startsWith(MOVED_PREFIX)) {
							moved.push(`${org}/${entry.name}`);
						} else {
							walk.aliases++;
						}
						return;
					}
					if (!(await isRealDir(path))) {
						walk.nonDirs++;
						return;
					}
					const kind = await classifyRepo(path);
					let cls: Class;
					let flags: readonly string[] = [];
					if (kind === "workspace") {
						cls = "workspace";
					} else if (kind === "nonrepo") {
						cls = "nonrepo";
					} else {
						flags = await plainFlags(path);
						cls = flags.length > 0 ? "plain-flagged" : "plain-clean";
					}
					const { bytes, errors } = await duBytes(path);
					const key = `${org}/${entry.name}`;
					let junkNodeModules: bigint | undefined;
					let junkTarget: bigint | undefined;
					if (await pathExists(join(path, "node_modules"))) {
						junkNodeModules = (await duBytes(join(path, "node_modules"))).bytes;
					}
					if (await pathExists(join(path, "target"))) {
						junkTarget = (await duBytes(join(path, "target"))).bytes;
					}
					repos.push({
						org,
						name: entry.name,
						path,
						bytes,
						partial: errors > 0,
						cls,
						flags,
						junkNodeModules,
						junkTarget,
						key,
						cached: cache.entries.get(key)?.bytes,
					});
				}),
			);
		}),
	);
	return { repos, moved, nonDirs: walk.nonDirs, aliases: walk.aliases, unreadable: walk.unreadable };
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

/** Load every <stem>.<class>.du+jsonl; absent files are a clean first run. */
async function loadCaches(stem: string, root: string): Promise<CacheOutcome> {
	const outcome: CacheOutcome = { entries: new Map(), present: false, files: [], badLines: 0 };
	let dirents: Dirent[];
	try {
		dirents = await readdir(root, { withFileTypes: true });
	} catch (error) {
		if (!isErrnoError(error)) throw error;
		return outcome;
	}
	// dirents carry bare names; the stem may be absolute — compare on its basename.
	const stemBase = basename(stem);
	const cacheFiles = dirents.filter((d) => d.name.startsWith(`${stemBase}.`) && d.name.endsWith(".du+jsonl"));
	for (const file of cacheFiles) {
		const path = join(root, file.name);
		let text: string;
		try {
			text = await readFile(path, "utf8");
		} catch (error) {
			if (!isErrnoError(error)) throw error;
			console.error(`${PROG}: cache unreadable: ${path} — skipping`);
			continue;
		}
		outcome.files.push(file.name);
		for (const line of text.split("\n")) {
			if (line.trim() === "") continue;
			try {
				const record = JSON.parse(line) as { org?: string; repo?: string; bytes?: number; flags?: string[] };
				if (typeof record.org !== "string" || typeof record.repo !== "string" || typeof record.bytes !== "number") {
					// moved records carry targets, not bytes — they are not entries,
					// and they are not bad lines either.
					if (typeof record.org === "string" && typeof record.repo === "string") continue;
					throw new Error("missing fields");
				}
				outcome.entries.set(`${record.org}/${record.repo}`, {
					bytes: BigInt(record.bytes),
					flags: record.flags ?? [],
				});
				outcome.present = true;
			} catch {
				outcome.badLines++;
			}
		}
	}
	if (outcome.badLines > 0) {
		console.error(`${PROG}: ${outcome.badLines} bad cache line(s) skipped`);
	}
	return outcome;
}

/** Serialize one repo to its attributed du line. */
function cacheLine(repo: Repo): string {
	const record: Record<string, unknown> = { org: repo.org, repo: repo.name, bytes: Number(repo.bytes) };
	if (repo.flags.length > 0) record.flags = [...repo.flags];
	if (repo.junkNodeModules !== undefined) record.node_modules = Number(repo.junkNodeModules);
	if (repo.junkTarget !== undefined) record.target = Number(repo.junkTarget);
	return JSON.stringify(record);
}

/** Atomically rewrite every <stem>.<class>.du+jsonl (moved repos get targets). */
async function writeCaches(stem: string, root: string, repos: readonly Repo[], moved: readonly string[]): Promise<void> {
	const byClass = new Map<string, string[]>();
	for (const repo of repos) {
		const lines = byClass.get(repo.cls) ?? [];
		lines.push(cacheLine(repo));
		byClass.set(repo.cls, lines);
	}
	const movedLines = moved.map((key) => {
		const [org, ...rest] = key.split("/");
		return JSON.stringify({ org, repo: rest.join("/"), target: `${MOVED_PREFIX}${key}` });
	});
	byClass.set("moved", movedLines);
	for (const [suffix, lines] of byClass) {
		const path = `${stem}.${suffix}.du+jsonl`;
		const tmp = `${path}.tmp`;
		await writeFile(tmp, `${lines.join("\n")}${lines.length > 0 ? "\n" : ""}`, "utf8");
		await rename(tmp, path);
	}
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

/** Per-group junk aggregate + top offenders, "reported, not touched". */
function junkSection(repos: readonly Repo[]): string[] {
	const lines: string[] = [];
	const families: { label: string; pick: (repo: Repo) => bigint | undefined }[] = [
		{ label: "node_modules", pick: (r) => r.junkNodeModules },
		{ label: "rust target/", pick: (r) => r.junkTarget },
	];
	for (const family of families) {
		const hits = repos
			.filter((repo) => (family.pick(repo) ?? 0n) >= JUNK_FLOOR)
			.sort((a, b) => ((family.pick(a) ?? 0n) < (family.pick(b) ?? 0n) ? 1 : -1));
		const total = repos.reduce((sum, repo) => sum + (family.pick(repo) ?? 0n), 0n);
		const count = repos.filter((repo) => family.pick(repo) !== undefined).length;
		lines.push(`${family.label}: ${human(total)} across ${count} repo(s)${hits.length > 0 ? ` — top:` : ""}`);
		for (const hit of hits.slice(0, JUNK_TOP)) {
			lines.push(`${human(family.pick(hit) ?? 0n).padStart(10)}  ${hit.org}/${hit.name} [${hit.cls}]`);
		}
	}
	return lines;
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
	dirsView: boolean,
): Promise<string> {
	const lines: string[] = [];
	const sorted = [...result.repos].sort(byBytesDesc);
	const rootTotal = sorted.reduce((sum, repo) => sum + repo.bytes, 0n);
	const allHits = sorted.filter((repo) => repo.bytes >= threshold);
	const allHitsTotal = allHits.reduce((sum, repo) => sum + repo.bytes, 0n);

	lines.push(`${PROG}: READ-ONLY report — this tool never deletes anything`);
	lines.push(`root: ${root}  threshold: ${human(threshold)}${dirsView ? "  (org view)" : ""}`);
	if (cache.present) {
		const cachedTotal = sorted.reduce((sum, repo) => sum + (repo.cached ?? 0n), 0n);
		lines.push(
			`cache: ${cache.files.length} file(s), ${cache.entries.size} entries (last run's archive total: ${human(cachedTotal)})${cache.badLines > 0 ? ` [${cache.badLines} bad line(s) skipped]` : ""}`,
		);
	} else {
		lines.push(`cache: none found under ${root} — first run; sizes cached for next time`);
	}
	lines.push("");
	lines.push(
		`repos at/over threshold: ${allHits.length} of ${sorted.length} (${human(allHitsTotal)}; archive total ${human(rootTotal)}; ${result.moved.length} already moved to bitblaster, not walked)`,
	);
	const fresh = sorted.filter((repo) => repo.cached === undefined);
	if (cache.present && fresh.length > 0) {
		lines.push(`new since cache: ${fresh.length} repo(s), tagged [new] below`);
	}

	if (dirsView) {
		const orgs = new Map<string, { bytes: bigint; repos: Repo[] }>();
		for (const repo of sorted) {
			const entry = orgs.get(repo.org) ?? { bytes: 0n, repos: [] };
			entry.bytes += repo.bytes;
			entry.repos.push(repo);
			orgs.set(repo.org, entry);
		}
		const orgList = [...orgs.entries()]
			.filter(([, entry]) => entry.bytes >= threshold)
			.sort((a, b) => (a[1].bytes < b[1].bytes ? 1 : a[1].bytes > b[1].bytes ? -1 : 0));
		lines.push("");
		lines.push(`orgs at/over ${human(threshold)} (class mix: clean/flagged/workspace/nonrepo):`);
		if (orgList.length === 0) {
			lines.push(`  (no org at/over ${human(threshold)})`);
		} else {
			lines.push("       SIZE  ORG  repos (cfwsnr)");
			for (const [org, entry] of orgList) {
				const mix = ["plain-clean", "plain-flagged", "workspace", "nonrepo"].map(
					(cls) => entry.repos.filter((repo) => repo.cls === cls).length,
				);
				lines.push(`${human(entry.bytes).padStart(10)}  ${org}  ${entry.repos.length} (${mix.join("/")})`);
			}
		}
	} else {
		for (const group of CLASSES) {
			const repos = sorted.filter((repo) => repo.cls === group.cls);
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
				const flags = hit.flags.length > 0 ? `  {${hit.flags.join(",")}}` : "";
				lines.push(`${human(hit.bytes).padStart(10)}  ${hit.org}/${hit.name}${flags}${note}${isNew}`);
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
	}

	lines.push("");
	lines.push("junk inside kept repos (reported, not touched — separate exercise from moving):");
	const junk = junkSection(sorted);
	lines.push(...(junk.length > 0 ? junk : ["  (none measured)"]));

	if (cache.present) {
		const changed = sorted
			.filter((repo) => {
				if (repo.cached === undefined) return false;
				if (repo.bytes === repo.cached) return false;
				if (delta === 0n) return true;
				const diff = repo.bytes > repo.cached ? repo.bytes - repo.cached : repo.cached - repo.bytes;
				return diff >= delta;
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

	if (!dirsView) {
		lines.push("");
		lines.push(`org subtotals (top ${ORG_TOTALS_SHOWN}; sums repos only):`);
		const orgs = new Map<string, { bytes: bigint; repos: number; over: number }>();
		for (const repo of sorted) {
			const entry = orgs.get(repo.org) ?? { bytes: 0n, repos: 0, over: 0 };
			entry.bytes += repo.bytes;
			entry.repos++;
			if (repo.bytes >= threshold) entry.over++;
			orgs.set(repo.org, entry);
		}
		const orgList = [...orgs.entries()].sort((a, b) => (a[1].bytes < b[1].bytes ? 1 : a[1].bytes > b[1].bytes ? -1 : 0));
		for (const [org, entry] of orgList.slice(0, ORG_TOTALS_SHOWN)) {
			lines.push(`${human(entry.bytes).padStart(10)}  ${org} (${entry.repos} repo${entry.repos === 1 ? "" : "s"}, ${entry.over} over)`);
		}
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
			dirs: { type: "boolean", default: false },
			"cache-stem": { type: "string" },
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
	const cacheStem = values["cache-stem"] ?? join(rootPath, CACHE_STEM_BASENAME);

	const cache = values["no-cache"]
		? ({ entries: new Map(), present: false, files: [], badLines: 0 } satisfies CacheOutcome)
		: await loadCaches(cacheStem, rootPath);
	const result = await scan(rootPath, cache);
	console.log(await report(rootPath, result, cache, threshold, top, minChild, delta, !values["no-old-size"], values.dirs === true));
	if (!values["no-cache"]) {
		try {
			await writeCaches(cacheStem, rootPath, result.repos, result.moved);
		} catch (error) {
			console.error(`${PROG}: cache write failed under ${rootPath} (${error instanceof Error ? error.message : error})`);
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
