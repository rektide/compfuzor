#!/usr/bin/env node
import { spawn } from "node:child_process";
import { realpathSync } from "node:fs";
import { lstat, mkdir, readFile, readlink, realpath, rename, rm, symlink } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";
import { parseArgs } from "node:util";
//#region files/config-remote.ts
/** Manage external symlinks declared by config.spec.json remote targets. */
const selfDir = resolve(dirname(realpathSync(process.argv[1])), "..");
async function linkState(path) {
	try {
		if (!(await lstat(path)).isSymbolicLink()) throw new Error(`managed destination is not a symlink: ${path}`);
		return {
			path,
			target: await readlink(path)
		};
	} catch (error) {
		if (error.code === "ENOENT") return void 0;
		throw error;
	}
}
function matches(pattern, value) {
	const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&");
	return new RegExp(`^${escaped.replaceAll("*", ".*").replaceAll("?", ".")}$`).test(value);
}
function validateName(remote, target, name) {
	if (!name || basename(name) !== name || name === "." || name === "..") throw new Error(`invalid remote filename: ${name}`);
	if (remote.disabled_suffix && name.endsWith(remote.disabled_suffix)) throw new Error(`remote filename must not include disabled suffix ${remote.disabled_suffix}: ${name}`);
	if (!matches(remote.pattern, name)) throw new Error(`${name} does not match ${target} pattern ${remote.pattern}`);
}
async function atomicLink(source, destination) {
	const temporary = join(dirname(destination), `.${basename(destination)}.tmp-${process.pid}-${Date.now()}`);
	await symlink(source, temporary);
	await rename(temporary, destination).catch(async (error) => {
		await rm(temporary, { force: true });
		throw error;
	});
}
async function rebuild(config) {
	await new Promise((resolve, reject) => {
		const child = spawn(join(selfDir, "bin", "config", "command.ts"), [
			"--action",
			"assemble",
			"--context",
			"canonical",
			config
		], {
			cwd: selfDir,
			stdio: "inherit"
		});
		child.once("error", reject);
		child.once("exit", (code, signal) => code === 0 ? resolve() : reject(/* @__PURE__ */ new Error(`config rebuild failed: ${signal ?? code}`)));
	});
}
async function inspect(remote, target, name) {
	validateName(remote, target, name);
	const activePath = join(remote.directory, name);
	const disabledPath = remote.disabled_suffix ? `${activePath}${remote.disabled_suffix}` : void 0;
	const [active, disabled] = await Promise.all([linkState(activePath), disabledPath ? linkState(disabledPath) : Promise.resolve(void 0)]);
	if (active && disabled) throw new Error(`both active and disabled remote links exist: ${target}/${name}`);
	return {
		active,
		disabled
	};
}
async function main() {
	const parsed = parseArgs({
		allowPositionals: true,
		strict: true,
		options: { name: {
			type: "string",
			short: "n"
		} }
	});
	const [rawAction, target, value, positionalName] = parsed.positionals;
	const action = rawAction === "link" ? "put" : rawAction;
	const remotes = JSON.parse(await readFile(join(selfDir, "etc", "config.spec.json"), "utf-8")).remotes ?? {};
	if (action === "list") {
		if (target) throw new Error("usage: config-remote.ts list");
		for (const name of Object.keys(remotes).sort()) {
			const remote = remotes[name];
			console.log(`${name}\tconfig=${remote.config}\tdestination=${join(remote.directory, remote.pattern)}\tdisabled=${remote.disabled_suffix ?? "-"}`);
		}
		return;
	}
	if (!target || !remotes[target]) throw new Error(`unknown remote target: ${target ?? ""}`);
	const remote = remotes[target];
	if (action === "status") {
		if (!value) throw new Error("usage: config-remote.ts status <target> <name>");
		const { active, disabled } = await inspect(remote, target, value);
		console.log(`${target}/${value}\t${active ? "enabled" : disabled ? "disabled" : "absent"}${active || disabled ? `\t${(active ?? disabled).target}` : ""}`);
		return;
	}
	if (action === "put") {
		if (!value) throw new Error("usage: config-remote.ts put <target> <source> [name] [--name name]");
		if (parsed.values.name && positionalName) throw new Error("filename may be supplied positionally or with --name, not both");
		const source = await realpath(value).catch((error) => {
			throw new Error(`remote source does not exist: ${value}`, { cause: error });
		});
		if (!(await lstat(source)).isFile()) throw new Error(`remote source is not a file: ${source}`);
		const name = parsed.values.name ?? positionalName ?? basename(source);
		const { active, disabled } = await inspect(remote, target, name);
		const previous = active ?? disabled;
		const destination = previous?.path ?? join(remote.directory, name);
		await mkdir(remote.directory, { recursive: true });
		await atomicLink(source, destination);
		try {
			await rebuild(remote.config);
		} catch (error) {
			if (previous) await atomicLink(previous.target, destination);
			else await rm(destination, { force: true });
			throw error;
		}
		console.log(`put: ${target}/${name}${disabled ? " (disabled)" : ""} -> ${source}`);
		return;
	}
	if (![
		"remove",
		"enable",
		"disable"
	].includes(action ?? "") || !value) throw new Error("usage: config-remote.ts <list|put|link|status|remove|enable|disable> ...");
	const { active, disabled } = await inspect(remote, target, value);
	if (action === "remove") {
		const existing = active ?? disabled;
		if (!existing) return;
		const backup = join(remote.directory, `.${basename(existing.path)}.remove-${process.pid}-${Date.now()}`);
		await rename(existing.path, backup);
		try {
			await rebuild(remote.config);
			await rm(backup);
		} catch (error) {
			await rename(backup, existing.path);
			throw error;
		}
	} else {
		if (!remote.disabled_suffix) throw new Error(`remote target cannot be toggled: ${target}`);
		const from = action === "disable" ? active : disabled;
		if (action === "disable" ? disabled : active) return;
		if (!from) throw new Error(`remote link does not exist: ${target}/${value}`);
		const destination = action === "disable" ? `${from.path}${remote.disabled_suffix}` : from.path.slice(0, -remote.disabled_suffix.length);
		await rename(from.path, destination);
		try {
			await rebuild(remote.config);
		} catch (error) {
			await rename(destination, from.path);
			throw error;
		}
	}
	console.log(`${action}: ${target}/${value}`);
}
main().catch((error) => {
	console.error(`error: ${error instanceof Error ? error.message : String(error)}`);
	process.exitCode = 1;
});
//#endregion
export {};
