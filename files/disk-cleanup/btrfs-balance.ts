#!/usr/bin/env node
/**
 * btrfs-balance.ts — staged data-chunk balance for a btrfs filesystem.
 * DRY-RUN BY DEFAULT.
 *
 * Context: this host's root btrfs (/dev/nvme0n1p6, ~3.4T, was 99-100%
 * full) is fully chunk-allocated — btrfs handed out all chunks, so free
 * space hides inside partially-used data chunks that only a balance can
 * reclaim. `btrfs balance start -dusage=N` relocates the contents of data
 * chunks whose usage is AT OR BELOW N%, emptying them so the allocator
 * can hand the space out again.
 *
 * HOST FINDING 2026-10-01: stages 2/8/20 relocated 0/0/1 of 3340 data
 * chunks — this filesystem has NO sparse chunks; its 3.22TiB is dense
 * live data. Balance is a null lever here TODAY. The tool stays because
 * big deletions (src-clean passes, toolchain uninstalls) can re-sparse
 * chunks later; re-run the cheap stages then. 45/65 would rewrite large
 * amounts of live data for ~1GiB chunks — not worth it absent new
 * evidence, which is why --dusage-cap exists: "stop at 20" had to be
 * done by hand once already.
 *
 * Stages ascend 2 → 8 → 20 → 45 on purpose:
 *   -dusage=2   nearly-empty chunks: a few % of live data rewritten per
 *               reclaimed chunk — cheapest pass, often the big win
 *   -dusage=8   still cheap; catches chunks the first pass redistributed
 *   -dusage=20  moderate rewrite, meaningful IO
 *   -dusage=45  big rewrite: relocates chunks under half full
 *   -dusage=65  --deep only: rewrites large amounts of live data for
 *               marginal reclaim — opt-in because for most filesystems
 *               the cost/benefit past ~50% is poor
 * Ascending order matters: emptying nearly-empty chunks first gives later
 * passes sparser targets (data consolidated into fewer chunks), so each
 * stage reconsiders chunks whose usage dropped below its threshold. A
 * single high-dusage pass would rewrite everything at once.
 *
 * This is HEAVY IO. Run it when the machine is idle — never during
 * builds, never while anything latency-sensitive (etcd, databases) is
 * live. --apply requires root (balance ioctls need it); the dry run does
 * not. Guards: refuses to run at all — even dry-run — when the target is
 * not btrfs (findmnt check), so this can never quietly "balance" a wrong
 * filesystem.
 *
 * Usage:
 *   btrfs-balance.ts [--mount /]           # dry run: print exact commands
 *   sudo btrfs-balance.ts --apply [--deep] # execute stages sequentially
 *
 * Exit: 0 ok, 1 runtime failure, 2 usage error.
 */

import { spawn } from "node:child_process";
import { parseArgs } from "node:util";

const PROG = "btrfs-balance.ts";

interface Stage {
	dusage: number;
	expectation: string;
}

const STAGES: readonly Stage[] = [
	{
		dusage: 2,
		expectation:
			"relocates data chunks ≤2% used (nearly-empty). Cheap and fast; on a\n" +
			"  fully-allocated fs this commonly frees the most chunks per GiB rewritten.",
	},
	{
		dusage: 8,
		expectation:
			"relocates chunks ≤8% used. Still cheap; catches chunks the previous\n" +
			"  stage's redistribution pushed under the threshold.",
	},
	{
		dusage: 20,
		expectation:
			"relocates chunks ≤20% used. Moderate IO, meaningful live-data rewrite.",
	},
	{
		dusage: 45,
		expectation:
			"relocates chunks ≤45% used. A big rewrite of up to ~half of each\n" +
			"  target chunk's live data — expect sustained heavy IO.",
	},
];

const DEEP_STAGE: Stage = {
	dusage: 65,
	expectation:
		"relocates chunks ≤65% used. Rewrites large amounts of live data for\n" +
		"  marginal additional reclaim; opt-in (--deep) for exactly this reason.",
};

class UsageError extends Error {
	readonly code = 2;
}

function usage(): string {
	return `usage: ${PROG} [--mount <path>] [--dusage-cap N] [--apply] [--deep]

Staged btrfs data-chunk balance (2 → 8 → 20 → 45% dusage, +65% with
--deep). DRY-RUN BY DEFAULT: prints the exact commands and expectations;
--apply executes stages sequentially, printing progress between stages
and aborting the chain on the first failure.

Host finding 2026-10-01: this fs has NO sparse chunks (stages 2/8/20
relocated 0/0/1 of 3340) — balance reclaims nothing here until big
deletions re-sparse chunks. Prefer the cheap stages after cleanup runs.

options:
  --apply            execute the balance stages (requires root; dry run
                     does not)
  --dusage-cap <n>   only run stages with dusage <= n (e.g. --dusage-cap 20
                     stops after the 20% stage; the 45% stage is skipped
                     unless n >= 45). Clamps --deep's 65% stage too
  --deep             append a final -dusage=65 stage (OFF by default: it
                     rewrites huge amounts of live data for marginal gain)
  --mount <path>     mount point to balance (default: /)
  --help             this help

guards and caveats:
  - refuses to run — even dry-run — unless findmnt reports the target as
    btrfs
  - --apply needs root: re-run as \`sudo ${PROG} --apply\`
  - HEAVY IO: run when idle; never during builds or while anything
    latency-sensitive (etcd, databases) is live
  - expect \`df\` free space to grow as chunks are emptied and released;
    before/after, compare \`btrfs filesystem usage <mount>\` (Data
    size/unallocated) rather than df alone`;
}

/** Capture a command's stdout; null on any failure (never rejects). */
function capture(command: string, args: readonly string[]): Promise<string | null> {
	return new Promise((resolve) => {
		let child;
		try {
			child = spawn(command, args, { stdio: ["ignore", "pipe", "ignore"] });
		} catch {
			resolve(null);
			return;
		}
		let out = "";
		child.stdout?.on("data", (chunk: Buffer) => {
			out += chunk.toString("utf8");
		});
		child.on("error", () => resolve(null));
		child.on("close", (code) => resolve(code === 0 ? out : null));
	});
}

/** Run a command inheriting stdio; resolve to its exit code (never rejects). */
function run(command: string, args: readonly string[]): Promise<number | null> {
	return new Promise((resolve) => {
		let child;
		try {
			child = spawn(command, args, { stdio: "inherit" });
		} catch (error) {
			console.error(`${PROG}: failed to spawn ${command}:`, error);
			resolve(1);
			return;
		}
		child.on("error", (error) => {
			console.error(`${PROG}: ${command}:`, error);
			resolve(1);
		});
		child.on("close", (code) => resolve(code));
	});
}

function stageCommand(stage: Stage, mount: string): string {
	return `btrfs balance start -dusage=${stage.dusage} ${mount}`;
}

async function main(argv: string[]): Promise<number> {
	const { values } = parseArgs({
		args: argv,
		options: {
			apply: { type: "boolean", default: false },
			deep: { type: "boolean", default: false },
			"dusage-cap": { type: "string" },
			mount: { type: "string", default: "/" },
			help: { type: "boolean", default: false },
		},
	});
	if (values.help) {
		console.log(usage());
		return 0;
	}
	const mount = values.mount ?? "/";
	const capRaw = values["dusage-cap"];
	let cap: number | null = null;
	if (capRaw !== undefined) {
		cap = Number.parseInt(capRaw, 10);
		if (!Number.isInteger(cap) || cap < 1 || cap > 100) {
			console.error(`${PROG}: --dusage-cap expects an integer 1..100 (got "${capRaw}")`);
			console.error(`${PROG}: try --help`);
			return 2;
		}
	}
	const allStages: Stage[] = [...STAGES];
	if (values.deep) allStages.push(DEEP_STAGE);
	// The cap clamps everything, --deep included: "stop at 20" must be
	// expressible without silently keeping a 65% rewrite in the chain.
	const stages = cap === null ? allStages : allStages.filter((stage) => stage.dusage <= cap);
	if (stages.length === 0) {
		console.error(`${PROG}: --dusage-cap ${cap} filters out every stage (smallest is ${STAGES[0].dusage})`);
		return 2;
	}

	// Guard: btrfs only, checked before anything else — even the dry run
	// must refuse a non-btrfs target so nobody previews-and-habit-retries
	// against the wrong filesystem.
	const fstype = await capture("findmnt", ["-n", "-o", "FSTYPE", mount]);
	if (fstype === null) {
		console.error(`${PROG}: findmnt failed for ${mount}: is it a mount point?`);
		return 1;
	}
	if (fstype.trim() !== "btrfs") {
		console.error(`${PROG}: refusing to balance ${mount}: fstype is "${fstype.trim()}", not btrfs`);
		return 1;
	}

	if (!values.apply) {
		console.log(`${PROG}: DRY RUN (no --apply) — printing commands only, nothing will run`);
		console.log(`target: ${mount} (fstype btrfs, confirmed via findmnt)`);
		console.log(`stages: ${stages.map((stage) => stage.dusage).join(" → ")}${cap === null ? "" : `  (capped at --dusage-cap ${cap})`}`);
		if (cap !== null && allStages.length > stages.length) {
			console.log(`skipped by cap: ${allStages.filter((stage) => stage.dusage > cap).map((stage) => stage.dusage).join(", ")}`);
		}
		console.log("");
		console.log("before:  btrfs filesystem usage " + mount + "   # note Data size / unallocated");
		for (const stage of stages) {
			console.log("");
			console.log(`  ${stageCommand(stage, mount)}`);
			console.log(`    ${stage.expectation}`);
		}
		console.log("");
		console.log("after:   btrfs filesystem usage " + mount + "   # unallocated should grow;");
		console.log("         df free space grows only as the allocator releases emptied chunks");
		console.log("");
		console.log(`to execute: sudo ${PROG} --apply${values.deep ? " --deep" : ""}${cap === null ? "" : ` --dusage-cap ${cap}`}`);
		return 0;
	}

	if (process.geteuid === undefined || process.geteuid() !== 0) {
		console.error(`${PROG}: --apply needs root (balance ioctls are privileged).`);
		console.error(`${PROG}: re-run as: sudo ${PROG} --apply${values.deep ? " --deep" : ""}${cap === null ? "" : ` --dusage-cap ${cap}`}`);
		return 1;
	}

	console.log(`${PROG}: APPLY — staged balance of ${mount}`);
	const usageBefore = await capture("btrfs", ["filesystem", "usage", "--raw", mount]);
	if (usageBefore !== null) {
		const line = usageBefore.split("\n").find((l) => l.trim().startsWith("Device size:"));
		if (line) console.log(`before: ${line.trim()}`);
	}
	for (const [index, stage] of stages.entries()) {
		const started = Date.now();
		console.log("");
		console.log(`${PROG}: stage ${index + 1}/${stages.length}: ${stageCommand(stage, mount)}`);
		const code = await run("btrfs", ["balance", "start", `-dusage=${stage.dusage}`, mount]);
		const seconds = Math.round((Date.now() - started) / 1000);
		if (code !== 0) {
			console.error(`${PROG}: stage ${index + 1} failed (exit ${code}) after ${seconds}s — aborting the chain.`);
			console.error(`${PROG}: later stages were NOT run; already-balanced progress is kept.`);
			console.error(`${PROG}: inspect with: btrfs balance status ${mount}`);
			return code ?? 1;
		}
		console.log(`${PROG}: stage ${index + 1} done in ${seconds}s`);
		// Progress between stages: confirm no balance is still running and
		// surface how much data now sits in chunks before the next pass.
		const status = await capture("btrfs", ["balance", "status", mount]);
		if (status !== null && status.includes("No balance")) {
			console.log(`${PROG}: balance status: idle`);
		} else if (status !== null) {
			console.log(`${PROG}: WARNING: balance still reported active:\n${status.trim()}`);
		}
	}
	const usageAfter = await capture("btrfs", ["filesystem", "usage", "--raw", mount]);
	if (usageAfter !== null) {
		const line = usageAfter.split("\n").find((l) => l.trim().startsWith("Device size:"));
		if (line) console.log(`after:  ${line.trim()}`);
	}
	console.log(`${PROG}: all ${stages.length} stage(s) complete`);
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
