#!/usr/bin/env node
/**
 * archive-move.ts — move ~/archive repos to bitblaster, symlink back.
 *
 * The move convention (operator, since 2026-09/10): a repo that leaves
 * local disk goes to /mnt/bitblaster/archive/<org>/<repo> (nanomachine's
 * export) and its old path becomes a symlink to it — REPO-level symlinks
 * only, never org-level. The mount is symmetric (identically pathed on
 * both hosts), so a symlinked repo stays reachable at the same absolute
 * path everywhere.
 *
 * Why this bin exists (2026-10-18): rsync-over-NFS measured ~0.5 MB/s on
 * the pineapple-src pilot — per-file temp-file + rename + chmod + utime
 * round-trips amortize to ~10 synchronous RTTs per small file, and
 * archive trees are made of small files. The engine here is instead a
 * single tar stream piped over ssh to nanomachine, where /mnt/bitblaster
 * is LOCAL disk: one TCP stream at wire speed, extraction and metadata
 * ops server-side. Verification (file count, git HEAD, git status hash)
 * also runs server-side for the same reason, then the source is removed
 * and the symlink lands only after parity.
 *
 * Discipline: DRY-RUN by default; --apply is the only moving path (the
 * subsystem rule — the destructive half stays an explicit decision).
 * A failed or interrupted move keeps the source untouched; the dest
 * partial is safe to overwrite (re-extraction replaces files in place).
 *
 * Usage:
 *   archive-move.ts [--apply] [--concurrency 3] [--root ~/archive]
 *                   [--dest-root /mnt/bitblaster/archive] [--host nanomachine]
 *                   [--list <file>] <org/repo> [<org/repo>...]
 *
 * Exit: 0 all-ok (or dry-run), 1 any failure, 2 usage error.
 */

import { spawn } from "node:child_process";
import { lstat, readFile, symlink } from "node:fs/promises";
import { homedir } from "node:os";
import { createHash } from "node:crypto";
import { dirname, join } from "node:path";
import { parseArgs } from "node:util";
import { UsageError, capture, human } from "./lib.ts";

const PROG = "archive-move.ts";
const DEFAULT_DEST_ROOT = "/mnt/bitblaster/archive";
const DEFAULT_HOST = "nanomachine";
const DEFAULT_CONCURRENCY = 3;
/**
 * ssh-side git runs as the same user; safe.directory defuses ownership
 * distrust per-invocation and excludesFile=/dev/null neutralizes the
 * hosts' DIFFERENT global gitignores (this box hides rust target/
 * globally, nanomachine does not — status parity must compare the same
 * rules on both sides; repo-local .gitignore travels with the repo).
 */
const GIT_SAFE = "git -c safe.directory='*' -c core.excludesFile=/dev/null";

interface Outcome {
	rel: string;
	ok: boolean;
	detail: string;
	bytes?: bigint;
	ms?: number;
}

function usage(): string {
	return `usage: ${PROG} [options] <org/repo> [<org/repo>...]

Move ~/archive/<org>/<repo> to the bitblaster archive and symlink the
old path back (repo-level symlinks only — orgs are never symlinked).
Engine: tar over ssh, extracted on the host where the destination is
local disk; verified (file count, git HEAD, git status parity) before
the source is removed. DRY-RUN by default.

options:
  --apply                actually move (default: dry-run report)
  --list <file>          read org/repo lines from file ('-' for stdin),
                         in addition to positional args
  --root <dir>           source archive root (default: $HOME/archive)
  --dest-root <dir>      destination root
                         (default: ${DEFAULT_DEST_ROOT})
  --host <host>          ssh host whose local disk holds dest-root
                         (default: ${DEFAULT_HOST})
  --concurrency <n>      repos in flight (default: ${DEFAULT_CONCURRENCY})
  --help                 this help

A repo already symlinked into the destination is SKIPped. Any failure
keeps the source intact; the partial destination is safe to overwrite
by rerunning (tar replaces files in place).`;
}

/** Shell-single-quote a string for the remote command line. */
function shq(value: string): string {
	return `'${value.replaceAll("'", `'\\''`)}'`;
}

/**
 * Pipe cmdA's stdout into cmdB's stdin; resolve with cmdB's exit code and
 * collected stdout when both exit. stderr from both is inherited (visible).
 */
function pipeInto(
	cmdA: string,
	argsA: readonly string[],
	cmdB: string,
	argsB: readonly string[],
): Promise<{ code: number | null; stdout: string }> {
	return new Promise((resolve, reject) => {
		let a;
		let b;
		try {
			a = spawn(cmdA, argsA, { stdio: ["ignore", "pipe", "inherit"] });
			b = spawn(cmdB, argsB, { stdio: ["pipe", "pipe", "inherit"] });
		} catch (error) {
			reject(error);
			return;
		}
		let out = "";
		b.stdout?.on("data", (chunk: Buffer) => {
			out += chunk.toString("utf8");
		});
		a.on("error", reject);
		b.on("error", reject);
		a.stdout?.pipe(b.stdin);
		let aCode: number | null = null;
		a.on("close", (code) => {
			aCode = code;
			// pipe() ends b.stdin when a's stdout closes.
		});
		b.on("close", (code) => {
			resolve({ code: aCode !== 0 ? aCode : code, stdout: out });
		});
	});
}

/** ssh host '<command>' and capture stdout; null on failure. */
function remote(host: string, command: string, timeoutMs = 120_000): Promise<string | null> {
	return capture("ssh", ["-o", "BatchMode=yes", host, command], timeoutMs);
}

function run(command: string, args: readonly string[]): Promise<number | null> {
	return new Promise((resolve) => {
		const child = spawn(command, args, { stdio: "ignore" });
		child.on("error", () => resolve(1));
		child.on("close", (code) => resolve(code));
	});
}

async function localSize(path: string): Promise<bigint> {
	// du -sB1 parity via `du`; failures return 0n (report-only figure).
	const out = await capture("du", ["-sB1", path], 120_000);
	const bytes = out === null ? 0n : BigInt((out.trim().split("\t")[0] ?? "0"));
	return bytes;
}

async function moveRepo(
	rel: string,
	root: string,
	destRoot: string,
	host: string,
	apply: boolean,
): Promise<Outcome> {
	const start = Date.now();
	const src = join(root, rel);
	const dest = join(destRoot, rel);
	if (!/^[^/]+\/[^/]+$/.test(rel)) {
		return { rel, ok: false, detail: "not an <org>/<repo> path (orgs are never symlinked)" };
	}
	try {
		const info = await lstat(src);
		if (info.isSymbolicLink()) {
			return { rel, ok: true, detail: `SKIP: already a symlink -> ${await readFile(src, "utf8").catch(() => "?")}` };
		}
		if (!info.isDirectory()) {
			return { rel, ok: false, detail: `source is not a directory: ${src}` };
		}
	} catch {
		return { rel, ok: false, detail: `source missing: ${src}` };
	}
	const bytes = await localSize(src);
	const head = await capture("git", ["-C", src, "rev-parse", "HEAD"], 60_000);
	const status = await capture("git", ["-c", "core.excludesFile=/dev/null", "-C", src, "status", "--porcelain"], 120_000);
	const count = await capture("find", [src, "-xdev"], 300_000);
	if (count === null) {
		return { rel, ok: false, detail: "local find failed" };
	}
	const countN = count.trim().split("\n").length;
	if (!apply) {
		return { rel, ok: true, detail: `dry-run: ${human(bytes)} -> ${dest} (then symlink back)`, bytes };
	}

	// Stream the repo as one tar over ssh; extract server-side where the
	// destination is local disk. Re-extraction replaces in place (resume).
	const org = dirname(rel);
	const repo = rel.split("/")[1] ?? "";
	const extractCmd = `mkdir -p ${shq(join(destRoot, org))} && tar -C ${shq(join(destRoot, org))} -xpf -`;
	const stream = await pipeInto(
		"tar",
		["-C", join(root, org), "-cf", "-", repo],
		"ssh",
		["-o", "BatchMode=yes", host, extractCmd],
	);
	if (stream.code !== 0) {
		return { rel, ok: false, detail: `tar/ssh stream exited ${stream.code} — source intact, dest partial kept for resume`, bytes };
	}

	// Server-side verification: file count, HEAD, status parity.
	const d = "__AM__";
	const verifyCmd = [
		`c1=$(find ${shq(dest)} | wc -l)`,
		`h1=$(${GIT_SAFE} -C ${shq(dest)} rev-parse HEAD 2>/dev/null || echo NOGIT)`,
		`s1=$(${GIT_SAFE} -C ${shq(dest)} status --porcelain 2>/dev/null | sort | sha256sum | cut -d' ' -f1 || echo NOGIT)`,
		`printf '%s\\n%s\\n%s\\n' "$c1" "$h1" "$s1"`,
	].join("; ");
	const verify = await remote(host, verifyCmd, 300_000);
	if (verify === null) {
		return { rel, ok: false, detail: "verify ssh failed — source intact, dest kept for inspection", bytes };
	}
	const [vCount, vHead, vStatus] = verify.trim().split("\n");
	const localStatusHash = status === null ? "NOGIT" : await (async () => {
		// parity with `sort | sha256sum` on the remote: sorted lines, each \n-terminated,
		// and the EMPTY output hashes the empty string (not a bare newline).
		const sorted = status.trim().split("\n").filter((l) => l !== "").sort().join("\n");
		return createHash("sha256").update(sorted === "" ? "" : `${sorted}\n`).digest("hex");
	})();
	if (vCount !== String(countN) || vHead !== (head?.trim() ?? "NOGIT") || vStatus !== localStatusHash) {
		return {
			rel,
			ok: false,
			detail: `verify mismatch (count ${countN}/${vCount}, head ${(head ?? "NOGIT").trim().slice(0, 8)}/${(vHead ?? "").slice(0, 8)}, status ${localStatusHash.slice(0, 8)}/${(vStatus ?? "").slice(0, 8)}) — source intact, dest kept for inspection`,
			bytes,
		};
	}

	// Parity: swap source for a symlink.
	if ((await run("rm", ["-rf", src])) !== 0) {
		return { rel, ok: false, detail: "source removal failed — dest verified; resolve manually", bytes };
	}
	await symlink(dest, src);
	return { rel, ok: true, detail: `OK ${human(bytes)} -> ${dest}`, bytes, ms: Date.now() - start };
}

async function main(argv: string[]): Promise<number> {
	const { values, positionals } = parseArgs({
		args: argv,
		options: {
			apply: { type: "boolean", default: false },
			list: { type: "string" },
			root: { type: "string" },
			"dest-root": { type: "string" },
			host: { type: "string" },
			concurrency: { type: "string" },
			help: { type: "boolean", default: false },
		},
		strict: false,
	});
	if (values.help) {
		console.log(usage());
		return 0;
	}
	const root = values.root ?? join(homedir(), "archive");
	const destRoot = values["dest-root"] ?? DEFAULT_DEST_ROOT;
	const host = values.host ?? DEFAULT_HOST;
	const concurrency = Number.parseInt(values.concurrency ?? String(DEFAULT_CONCURRENCY), 10);
	if (!Number.isInteger(concurrency) || concurrency < 1 || concurrency > 16) {
		throw new UsageError(`--concurrency expects an integer 1..16 (got "${values.concurrency}")`);
	}
	let repos = positionals.filter((p) => p !== "");
	if (values.list !== undefined) {
		const text = values.list === "-" ? await readFile("/dev/stdin", "utf8") : await readFile(values.list, "utf8");
		repos = [...repos, ...text.split("\n").map((l) => l.trim()).filter((l) => l !== "" && !l.startsWith("#"))];
	}
	if (repos.length === 0) {
		throw new UsageError("no repos given (positional args or --list)");
	}

	const mode = values.apply === true ? "APPLY" : "dry-run";
	console.log(`${PROG}: ${mode} ${repos.length} repo(s) ${root} -> ${destRoot} via ${host} (concurrency ${concurrency})`);
	const queue = [...new Set(repos)];
	const outcomes: Outcome[] = [];
	let cursor = 0;
	async function worker(): Promise<void> {
		while (cursor < queue.length) {
			const rel = queue[cursor++];
			const outcome = await moveRepo(rel, root, destRoot, host, values.apply === true);
			outcomes.push(outcome);
			const rate = outcome.bytes && outcome.ms && outcome.ms > 0 ? `, ${(Number(outcome.bytes) / outcome.ms / 1024).toFixed(1)} MiB/s` : "";
			console.log(`${outcome.ok ? "ok " : "FAIL"}  ${outcome.rel}  ${outcome.detail}${outcome.ms !== undefined ? ` [${(outcome.ms / 1000).toFixed(1)}s${rate}]` : ""}`);
		}
	}
	await Promise.all(Array.from({ length: Math.min(concurrency, queue.length) }, worker));
	const failed = outcomes.filter((o) => !o.ok);
	const movedBytes = outcomes.reduce((sum, o) => sum + (o.ok ? (o.bytes ?? 0n) : 0n), 0n);
	console.log(`${PROG}: ${outcomes.length - failed.length}/${outcomes.length} ok, ${human(movedBytes)}${failed.length > 0 ? ` — ${failed.length} FAILED (sources intact)` : ""}`);
	return failed.length > 0 ? 1 : 0;
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
