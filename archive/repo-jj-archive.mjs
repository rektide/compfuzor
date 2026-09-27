#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdir, realpath, stat } from "node:fs/promises";
import { dirname, join } from "node:path";
import { parseArgs, promisify } from "node:util";
//#region archive/src/repo-jj-archive.ts
/**
* Refresh a canonical archive without using Git's worktree-resetting update path.
*
* Stdout is one JSON result for Ansible; jj diagnostics and failures go to stderr.
* Only run this on a checkout whose working tree is not being edited concurrently.
*/
const exec = promisify(execFile);
const USAGE = `Usage: repo-jj-archive.ts --dest DEST --repo URL --label LABEL [--remotes JSON]
                    [--remote NAME] [--version VERSION] [--depth N] [--submodules]
                    [--update true|false]

Refresh a canonical jj-colocated archive without Git's worktree-resetting update
path. Stdout is one JSON result for Ansible; jj diagnostics and failures go to
stderr. Only run this on a checkout whose working tree is not being edited
concurrently.`;
const REF_TEMPLATE = "name ++ \"\\t\" ++ if(remote,remote,\"-\") ++ \"\\t\" ++ if(normal_target,normal_target.commit_id(),\"conflict\") ++ \"\\t\" ++ tracked ++ \"\\n\"";
const COMMIT_TEMPLATE = "commit_id ++ \"\\t\" ++ empty ++ \"\\t\" ++ parents.map(|c| c.commit_id()).join(\",\") ++ \"\\t\" ++ conflict ++ \"\\n\"";
const HEAD_TEMPLATE = "commit_id ++ \"\\n\"";
const REMOTE_NAME = /[A-Za-z0-9][A-Za-z0-9._-]*/;
/** Python re.fullmatch parity: the pattern must consume the entire text. */
function fullmatch(pattern, text) {
	const match = pattern.exec(text);
	return match !== null && match[0] === text;
}
/** Python str.splitlines() parity for newline-terminated jj template output. */
function lines(output) {
	return output === "" ? [] : output.split("\n");
}
async function jj(args, cwd) {
	const command = [
		"jj",
		"--no-pager",
		"--color=never",
		...args
	];
	try {
		const { stdout } = await exec(command[0], command.slice(1), {
			cwd,
			encoding: "utf8",
			maxBuffer: 67108864
		});
		return stdout.trim();
	} catch (error) {
		const detail = typeof error.stderr === "string" ? error.stderr : "";
		throw new Error(`${command.join(" ")}: ${detail.trim()}`);
	}
}
const refKey = (name, remote) => `${name}\t${remote}`;
async function refs(dest) {
	const result = /* @__PURE__ */ new Map();
	const output = await jj([
		"bookmark",
		"list",
		"--all-remotes",
		"-T",
		REF_TEMPLATE
	], dest);
	for (const line of lines(output)) {
		const parts = line.split("	");
		if (parts.length !== 4) throw new Error(`malformed bookmark line: ${line}`);
		result.set(refKey(parts[0], parts[1]), {
			name: parts[0],
			remote: parts[1],
			target: parts[2],
			tracked: parts[3] === "true"
		});
	}
	return result;
}
async function revision(dest, rev) {
	const output = await jj([
		"log",
		"-G",
		"-r",
		rev,
		"-T",
		COMMIT_TEMPLATE
	], dest);
	const parts = output.split("	");
	if (parts.length !== 4) throw new Error(`malformed revision line for ${rev}: ${output}`);
	return {
		commit: parts[0],
		empty: parts[1] === "true",
		parents: parts[2] === "" ? [] : parts[2].split(","),
		conflict: parts[3] === "true"
	};
}
async function ancestor(dest, older, newer) {
	return Number(await jj([
		"log",
		"-r",
		`${older}::${newer}`,
		"--count"
	], dest)) > 0;
}
async function exists(path) {
	return await stat(path, { throwIfNoEntry: false }) !== void 0;
}
async function isDirectory(path) {
	const info = await stat(path, { throwIfNoEntry: false });
	return info !== void 0 && info.isDirectory();
}
async function main() {
	const { values } = parseArgs({
		args: process.argv.slice(2),
		strict: true,
		options: {
			help: {
				type: "boolean",
				short: "h",
				default: false
			},
			dest: { type: "string" },
			repo: { type: "string" },
			remotes: { type: "string" },
			remote: {
				type: "string",
				default: "origin"
			},
			version: {
				type: "string",
				default: "HEAD"
			},
			label: { type: "string" },
			depth: { type: "string" },
			submodules: {
				type: "boolean",
				default: false
			},
			update: {
				type: "string",
				default: "true"
			}
		}
	});
	if (values.help) {
		console.log(USAGE);
		return;
	}
	const required = (name, value) => {
		if (value === void 0) throw new Error(`the following arguments are required: --${name}`);
		return value;
	};
	const dest = required("dest", values.dest);
	const repo = required("repo", values.repo);
	const remotesArg = required("remotes", values.remotes);
	const labelArg = required("label", values.label);
	if (values.update !== "true" && values.update !== "false") throw new Error(`argument --update: invalid choice: '${values.update}' (choose from 'true', 'false')`);
	const update = values.update;
	const remotesJson = JSON.parse(remotesArg);
	if (remotesJson === null || typeof remotesJson !== "object" || Array.isArray(remotesJson)) throw new Error("--remotes must be a JSON object mapping remote names to URLs");
	const declared = /* @__PURE__ */ new Map([["origin", repo]]);
	for (const [name, url] of Object.entries(remotesJson)) declared.set(name, url);
	let version = values.version;
	let selected = values.remote;
	const marker = version.lastIndexOf("@");
	if (marker !== -1 && declared.has(version.slice(marker + 1))) {
		selected = version.slice(marker + 1);
		version = version.slice(0, marker);
	}
	if (!declared.has(selected)) throw new Error(`selected remote '${selected}' is not declared`);
	const urls = /* @__PURE__ */ new Map();
	for (const [name, url] of declared) {
		if (!fullmatch(REMOTE_NAME, name) || typeof url !== "string" || url === "") throw new Error("remote names or URLs are invalid");
		urls.set(name, url);
	}
	if (values.submodules) throw new Error("GIT_SUBMODULES requires explicit submodule safety handling; disable it for this archive render");
	const depth = values.depth === void 0 ? void 0 : Number(values.depth);
	if (depth !== void 0 && (!Number.isInteger(depth) || depth < 1)) throw new Error("GIT_DEPTH must be positive");
	const label = labelArg.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^[.-]+|[.-]+$/g, "") || "deployment";
	const now = /* @__PURE__ */ new Date();
	const pad = (value) => String(value).padStart(2, "0");
	const stamp = `${now.getUTCFullYear()}${pad(now.getUTCMonth() + 1)}${pad(now.getUTCDate())}-${pad(now.getUTCHours())}${pad(now.getUTCMinutes())}${pad(now.getUTCSeconds())}`;
	const notices = [];
	let changed = false;
	let cloned = false;
	const harvest = async (kind, target, copy = false) => {
		let commit = target;
		if (copy) {
			const heads = new Set(lines(await jj([
				"log",
				"-G",
				"-r",
				"heads(all())",
				"-T",
				HEAD_TEMPLATE
			], dest)));
			await jj([
				"duplicate",
				"-r",
				target
			], dest);
			const newHeads = lines(await jj([
				"log",
				"-G",
				"-r",
				"heads(all())",
				"-T",
				HEAD_TEMPLATE
			], dest)).filter((head) => !heads.has(head));
			if (newHeads.length !== 1) throw new Error(`expected one duplicated jj snapshot; found [${newHeads.join(", ")}]`);
			commit = newHeads[0];
		}
		const name = `harvest/${label}/${kind}-${stamp}-${randomUUID().replaceAll("-", "").slice(0, 8)}`;
		await jj([
			"bookmark",
			"create",
			name,
			"-r",
			commit
		], dest);
		notices.push({
			kind: "bookmark-created",
			name,
			target: commit
		});
		changed = true;
	};
	if (!await exists(dest)) {
		await mkdir(dirname(dest), { recursive: true });
		const command = [
			"git",
			"clone",
			"--colocate",
			"--remote",
			selected
		];
		if (depth !== void 0) command.push("--depth", String(depth));
		if (version !== "HEAD") command.push("--branch", version);
		await jj([
			...command,
			urls.get(selected),
			dest
		], dirname(dest));
		notices.push({
			kind: "notice",
			message: `cloned jj-colocated archive ${dest}`
		});
		changed = true;
		cloned = true;
	} else if (!await isDirectory(dest) || !await exists(join(dest, ".git"))) throw new Error(`${dest} exists but is not a colocated Git checkout; refusing to replace it`);
	else if (!await exists(join(dest, ".jj"))) {
		await jj([
			"git",
			"init",
			"--git-repo",
			join(dest, ".git"),
			dest
		], dest);
		notices.push({
			kind: "notice",
			message: `adopted existing Git archive into jj: ${dest}`
		});
		changed = true;
	}
	await jj(["status"], dest);
	const before = await refs(dest);
	const working = await revision(dest, "@");
	const work = working.commit;
	const empty = working.empty;
	const parents = working.parents;
	const remoteUrls = /* @__PURE__ */ new Map();
	for (const line of lines(await jj([
		"git",
		"remote",
		"list"
	], dest))) {
		const space = line.indexOf(" ");
		remoteUrls.set(space === -1 ? line : line.slice(0, space), space === -1 ? "" : line.slice(space + 1));
	}
	for (const [name, url] of urls) if (!remoteUrls.has(name)) {
		await jj([
			"git",
			"remote",
			"add",
			name,
			url
		], dest);
		changed = true;
	} else if (remoteUrls.get(name) !== url) {
		await jj([
			"git",
			"remote",
			"set-url",
			name,
			url
		], dest);
		changed = true;
	}
	if (update === "false" && before.size > 0) {
		console.log(JSON.stringify({
			changed,
			notices
		}));
		return;
	}
	let recoveryCovered = false;
	if (!empty) for (const ref of before.values()) {
		if (!ref.name.startsWith(`harvest/${label}/working-copy-`) || ref.remote !== "-") continue;
		if ((await revision(dest, ref.target)).parents.join(",") !== parents.join(",")) continue;
		if (await jj([
			"diff",
			"--from",
			ref.target,
			"--to",
			"@",
			"--summary"
		], dest) !== "") continue;
		recoveryCovered = true;
		break;
	}
	if (!empty && !recoveryCovered) await harvest("working-copy", work, true);
	for (const ref of before.values()) if (ref.remote !== "-" && ref.remote !== "git" && ref.tracked) await jj([
		"bookmark",
		"untrack",
		ref.name,
		"--remote",
		ref.remote
	], dest);
	for (const name of urls.keys()) await jj([
		"--config",
		"git.abandon-unreachable-commits=false",
		"git",
		"fetch",
		"--remote",
		name
	], dest);
	const after = await refs(dest);
	const base = version !== "HEAD" ? version : ["main", "master"].find((name) => after.has(refKey(name, selected))) ?? null;
	if (base === null || !after.has(refKey(base, selected))) throw new Error(`remote ${selected} does not have branch ${version}; specify GIT_VERSION explicitly`);
	const upstream = after.get(refKey(base, selected)).target;
	if (upstream === "conflict") throw new Error(`remote ${base}@${selected} is conflicted`);
	const oldBase = before.get(refKey(base, "-"))?.target ?? null;
	if (oldBase === "conflict") throw new Error(`local bookmark ${base} is conflicted; resolve it before updating`);
	for (const ref of before.values()) {
		if (ref.remote !== "-" || ref.name === base || ref.target === "conflict") continue;
		const current = after.get(refKey(ref.name, "-"));
		if (current === void 0 || current.target !== ref.target) await harvest(`${ref.name.replaceAll("/", "-")}-local`, ref.target);
	}
	if (oldBase !== null && oldBase !== upstream && !await ancestor(dest, oldBase, upstream)) await harvest(base.replaceAll("/", "-"), oldBase);
	if (oldBase !== upstream) {
		await jj([
			"bookmark",
			"set",
			"-B",
			"-r",
			upstream,
			base
		], dest);
		if (oldBase === null) notices.push({
			kind: "bookmark-created",
			name: base,
			target: upstream
		});
		else notices.push({
			kind: "notice",
			message: `${base} -> ${upstream} (${selected})`
		});
		changed = true;
	} else if (cloned) notices.push({
		kind: "bookmark-created",
		name: base,
		target: upstream
	});
	await jj([
		"bookmark",
		"track",
		base,
		"--remote",
		selected
	], dest);
	const current = await revision(dest, "@");
	if (oldBase === current.commit && oldBase !== upstream && await ancestor(dest, upstream, current.commit)) {
		await jj(["new", "@"], dest);
		changed = true;
	} else if (!await ancestor(dest, upstream, current.commit)) {
		if (current.empty && oldBase !== null && current.parents.join(",") === oldBase && await ancestor(dest, oldBase, upstream)) await jj([
			"rebase",
			"-r",
			"@",
			"-d",
			base
		], dest);
		else {
			if (empty && current.commit !== work) await harvest("head", work);
			await jj([
				"new",
				"@",
				base
			], dest);
		}
		changed = true;
		notices.push({
			kind: "notice",
			message: `merged local checkout with ${base}@${selected}`
		});
	}
	if ((await revision(dest, "@")).conflict) notices.push({
		kind: "notice",
		message: "working copy has merge conflicts; resolve them before building"
	});
	if ((before.get(refKey(base, selected))?.target ?? null) !== upstream) changed = true;
	console.log(JSON.stringify({
		changed,
		notices
	}));
}
const argvPath = process.argv[1];
if (argvPath) realpath(argvPath).then((realArgv) => {
	if (realArgv !== import.meta.filename) return;
	return main().catch((error) => {
		console.error(`repo-jj-archive: ${error instanceof Error ? error.message : String(error)}`);
		process.exitCode = 1;
	});
}, (error) => {
	console.error(`repo-jj-archive: ${error instanceof Error ? error.message : String(error)}`);
	process.exitCode = 1;
});
//#endregion
export { main };
