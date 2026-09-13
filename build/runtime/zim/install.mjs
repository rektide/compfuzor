#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
import { chmod, copyFile, lstat, mkdir, mkdtemp, readFile, readdir, readlink, realpath, rename, rm, stat, symlink, writeFile } from "node:fs/promises";
import { basename, dirname, isAbsolute, join, matchesGlob, normalize, relative, resolve } from "node:path";
import { constants, tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { parseArgs } from "node:util";
//#region files/config/context.ts
/** Import-safe consumer-context selection and path binding for CONFIGS specs. */
function fail$6(message) {
	throw new Error(message);
}
function object$1(value, label) {
	if (!value || typeof value !== "object" || Array.isArray(value)) fail$6(`${label} must be an object`);
	return value;
}
function knownRoot(name) {
	const home = process.env.HOME;
	if (name === "HOME") return home;
	if (name === "XDG_CONFIG_HOME") return process.env.XDG_CONFIG_HOME || (home ? join(home, ".config") : void 0);
	if (name === "XDG_STATE_HOME") return process.env.XDG_STATE_HOME || (home ? join(home, ".local", "state") : void 0);
	if (name === "XDG_CACHE_HOME") return process.env.XDG_CACHE_HOME || (home ? join(home, ".cache") : void 0);
	if (name === "XDG_DATA_HOME") return process.env.XDG_DATA_HOME || (home ? join(home, ".local", "share") : void 0);
}
function expandPath(value, base, label) {
	let expanded = value;
	if (value === "~" || value.startsWith("~/")) {
		const home = knownRoot("HOME") ?? fail$6(`${label}: HOME is required to expand ${value}`);
		if (value.slice(1).includes("$") || value.slice(1).includes("~")) fail$6(`${label}: unsupported runtime-root expression: ${value}`);
		expanded = home + value.slice(1);
	} else if (value.startsWith("${")) {
		const match = /^\$\{(HOME|XDG_CONFIG_HOME|XDG_STATE_HOME|XDG_CACHE_HOME|XDG_DATA_HOME)\}(?:\/|$)/.exec(value);
		if (!match) fail$6(`${label}: unsupported runtime-root expression: ${value}`);
		const root = knownRoot(match[1]) ?? fail$6(`${label}: ${match[1]} or HOME is required to expand ${value}`);
		const suffix = value.slice(match[0].length - (match[0].endsWith("/") ? 1 : 0));
		if (suffix.includes("$") || suffix.includes("~")) fail$6(`${label}: unsupported runtime-root expression: ${value}`);
		expanded = root + suffix;
	} else if (value.includes("$") || value.includes("~")) fail$6(`${label}: unsupported runtime-root expression: ${value}`);
	if (!isAbsolute(expanded)) {
		if (!base) fail$6(`${label}: resolved root must be absolute: ${expanded}`);
		expanded = resolve(base, expanded);
	}
	return normalize(expanded);
}
function resolvePathSelector(raw, base, label) {
	const selector = object$1(raw, label);
	if ([
		selector.path !== void 0,
		selector.relative !== void 0,
		selector.env !== void 0
	].filter(Boolean).length !== 1) fail$6(`${label} must contain exactly one of path, relative, or env`);
	if (selector.path !== void 0) {
		if (typeof selector.path !== "string" || !selector.path) fail$6(`${label}.path must be a non-empty string`);
		return expandPath(selector.path, void 0, `${label}.path`);
	}
	if (selector.relative !== void 0) {
		if (typeof selector.relative !== "string" || !selector.relative || !base) fail$6(`${label}.relative requires a context root`);
		const resolved = resolve(base, selector.relative);
		const fromBase = relative(base, resolved);
		if (fromBase === ".." || fromBase.startsWith(`..${process.platform === "win32" ? "\\" : "/"}`) || isAbsolute(fromBase)) fail$6(`${label}.relative escapes the context root`);
		return normalize(resolved);
	}
	if (typeof selector.env !== "string" || !selector.env) fail$6(`${label}.env must name an environment variable`);
	const environmentValue = process.env[selector.env];
	if (environmentValue && !selector.ignore?.includes(environmentValue)) return expandPath(environmentValue, base, `${label}.env(${selector.env})`);
	if (selector.default !== void 0) return resolvePathSelector(selector.default, base, `${label}.default`);
	fail$6(`${label}: environment variable ${selector.env} is required`);
}
function getConfigContext(spec, contextName) {
	if (spec.version !== 2) fail$6(`unsupported config spec version: ${String(spec.version)}; rerender the deployment (expected version 2)`);
	const context = object$1(object$1(spec.contexts, "config spec contexts")[contextName], `unknown config context ${contextName}`);
	if (context.scope !== "user" && context.scope !== "system") fail$6(`context ${contextName}: invalid scope`);
	object$1(context.configs, `context ${contextName}.configs`);
	return context;
}
function contextConfigNames(spec, contextName, applyOnly = false) {
	const context = getConfigContext(spec, contextName);
	const names = Object.keys(context.configs);
	if (!applyOnly) return names;
	return names.filter((name) => {
		return object$1(spec.configs[name], `context ${contextName}: missing source config ${name}`).apply !== false;
	});
}
function bindContextConfigs(spec, contextName, names) {
	const context = getConfigContext(spec, contextName);
	for (const name of names) if (!(name in context.configs)) fail$6(`unknown config in context ${contextName}: ${name}`);
	const root = resolvePathSelector(context.root, void 0, `context ${contextName}.root`);
	const base = context.subpath ? resolve(root, context.subpath) : root;
	const contextConfigs = object$1(context.configs, `context ${contextName}.configs`);
	const resolvedConfigs = {};
	const outputs = /* @__PURE__ */ new Map();
	for (const name of names) {
		const source = object$1(spec.configs[name], `context ${contextName}: missing source config ${name}`);
		const binding = object$1(contextConfigs[name], `context ${contextName}.configs.${name}`);
		if (!Array.isArray(source.inputs) || !Array.isArray(binding.inputs) || source.inputs.length !== binding.inputs.length) fail$6(`context ${contextName}.configs.${name}: input bindings do not match the source recipe`);
		const output = resolvePathSelector(binding.output, base, `context ${contextName}.configs.${name}.output`);
		const prior = outputs.get(output);
		if (prior) fail$6(`context ${contextName}: configs ${prior} and ${name} resolve to the same output ${output}`);
		outputs.set(output, name);
		const inputs = source.inputs.map((rawInput, index) => {
			const input = { ...object$1(rawInput, `config ${name}.inputs[${index}]`) };
			const path = resolvePathSelector(binding.inputs[index], base, `context ${contextName}.configs.${name}.inputs[${index}]`);
			if (input.file !== void 0) input.file = path;
			else {
				input.directory = path;
				input.glob = join(path, String(input.pattern));
			}
			return input;
		});
		resolvedConfigs[name] = {
			...source,
			output,
			inputs
		};
	}
	return {
		...spec,
		configs: resolvedConfigs,
		contexts: void 0,
		remotes: {}
	};
}
//#endregion
//#region files/links/delivery.ts
/** Shared, import-safe filesystem delivery primitives used by LINKS and CONFIGS. */
const localLinkDeliveryExecutor = {
	async mkdir(path) {
		await mkdir(path, { recursive: true });
	},
	async symlink(source, destination) {
		await symlink(source, destination);
	},
	async rename(source, destination) {
		await rename(source, destination);
	},
	async rm(path) {
		await rm(path, { force: true });
	}
};
const localCopyDeliveryExecutor = {
	async mkdir(path) {
		await mkdir(path, { recursive: true });
	},
	async copyFile(source, destination) {
		await copyFile(source, destination);
	},
	async chmod(path, mode) {
		await chmod(path, mode);
	},
	async rename(source, destination) {
		await rename(source, destination);
	},
	async rm(path) {
		await rm(path, { force: true });
	}
};
async function inspectDeliveryEntry(path) {
	let entry;
	try {
		entry = await lstat(path);
	} catch (error) {
		if (error.code === "ENOENT") return { kind: "missing" };
		throw error;
	}
	if (entry.isSymbolicLink()) {
		const target = await readlink(path);
		return {
			kind: "symlink",
			target,
			targetPath: normalize(isAbsolute(target) ? target : resolve(dirname(path), target))
		};
	}
	if (entry.isFile()) return { kind: "file" };
	if (entry.isDirectory()) return { kind: "directory" };
	return { kind: "special" };
}
function linkMatches(entry, source) {
	return entry.kind === "symlink" && entry.targetPath === normalize(resolve(source));
}
/** Compare final regular-file referents. CONFIGS accepts equivalent topology;
* LINKS keeps using linkMatches() where the literal managed target is identity. */
async function linkResolvesToSameFile(entry, source) {
	if (entry.kind !== "symlink") return false;
	try {
		const [targetPath, sourcePath, targetStat, sourceStat] = await Promise.all([
			realpath(entry.targetPath),
			realpath(source),
			stat(entry.targetPath),
			stat(source)
		]);
		return targetStat.isFile() && sourceStat.isFile() && (targetPath === sourcePath || targetStat.dev === sourceStat.dev && targetStat.ino === sourceStat.ino);
	} catch (error) {
		if (error.code === "ENOENT") return false;
		throw error;
	}
}
function temporaryPath(destination) {
	return join(dirname(destination), `.${destination.split("/").pop()}.delivery-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`);
}
function assertReplaceable(entry, destination) {
	if (entry.kind === "directory" || entry.kind === "special") throw new Error(`delivery destination is not a regular file or symlink: ${destination}`);
}
async function physicalParent(path) {
	const parent = dirname(resolve(path));
	try {
		return await realpath(parent);
	} catch (error) {
		if (error.code !== "ENOENT" || dirname(parent) === parent) throw error;
		return join(await physicalParent(parent), basename(parent));
	}
}
/** Compare directory entries without following either final entry. */
async function pathsSharePhysicalEntry(first, second) {
	if (normalize(resolve(first)) === normalize(resolve(second))) return true;
	const [firstParent, secondParent] = await Promise.all([physicalParent(first), physicalParent(second)]);
	return firstParent === secondParent && basename(first) === basename(second);
}
async function physicalDirectory(path) {
	try {
		return await realpath(path);
	} catch (error) {
		if (error.code !== "ENOENT") throw error;
		return join(await physicalParent(path), basename(path));
	}
}
/** Compare directory locations, following a final directory symlink. */
async function pathsSharePhysicalDirectory(first, second) {
	const [firstDirectory, secondDirectory] = await Promise.all([physicalDirectory(first), physicalDirectory(second)]);
	return firstDirectory === secondDirectory;
}
async function assertDistinct(source, destination) {
	if (await pathsSharePhysicalEntry(source, destination)) throw new Error(`delivery source and destination resolve to the same directory entry: ${source}`);
}
async function replaceWithLink(source, destination, executor = localLinkDeliveryExecutor) {
	await assertDistinct(source, destination);
	assertReplaceable(await inspectDeliveryEntry(destination), destination);
	await executor.mkdir(dirname(destination));
	const temporary = temporaryPath(destination);
	try {
		await executor.symlink(source, temporary);
		await executor.rename(temporary, destination);
	} catch (error) {
		await executor.rm(temporary).catch(() => void 0);
		throw error;
	}
}
async function replaceWithCopy(source, destination, executor = localCopyDeliveryExecutor) {
	await assertDistinct(source, destination);
	const sourceStat = await stat(source);
	if (!sourceStat.isFile()) throw new Error(`delivery source is not a regular file: ${source}`);
	assertReplaceable(await inspectDeliveryEntry(destination), destination);
	await executor.mkdir(dirname(destination));
	const temporary = temporaryPath(destination);
	try {
		await executor.copyFile(source, temporary);
		await executor.chmod(temporary, sourceStat.mode & 511);
		await executor.rename(temporary, destination);
	} catch (error) {
		await executor.rm(temporary).catch(() => void 0);
		throw error;
	}
}
//#endregion
//#region files/config/assembly.ts
/** Bind CONFIG recipes to one context and invoke the sole transaction runner. */
async function assertContextOutputsSeparated(source, resolved) {
	for (const [name, config] of Object.entries(resolved.configs)) {
		const canonical = source.configs[name]?.output;
		if (canonical && await pathsSharePhysicalEntry(canonical, config.output)) throw new Error(`context output aliases canonical output for ${name}: ${config.output}`);
	}
}
function signalExitCode(signal) {
	const number = constants.signals[signal];
	return typeof number === "number" ? 128 + number : 1;
}
async function invokeRunner(options, specPath) {
	const runnerDirectory = dirname(options.runner);
	const runnerDeploymentDir = resolve(runnerDirectory, basename(runnerDirectory) === "config" ? "../.." : "..");
	const args = [
		...options.check ? ["--check"] : [],
		...options.stdout ? ["--stdout"] : [],
		...options.quiet ? ["--quiet"] : [],
		...options.names
	];
	return await new Promise((complete, reject) => {
		const stdio = options.stdio === "pipe" ? [
			"ignore",
			"pipe",
			"pipe"
		] : options.stdio ?? "inherit";
		const child = spawn(options.runner, args, {
			cwd: runnerDeploymentDir,
			detached: true,
			env: {
				...process.env,
				DIR: runnerDeploymentDir,
				CONFIG_SPEC: specPath
			},
			stdio
		});
		const stdout = [];
		const stderr = [];
		child.stdout?.on("data", (chunk) => stdout.push(Buffer.from(chunk)));
		child.stderr?.on("data", (chunk) => stderr.push(Buffer.from(chunk)));
		const handlers = /* @__PURE__ */ new Map();
		const cleanupHandlers = () => {
			for (const [signal, handler] of handlers) process.off(signal, handler);
		};
		for (const signal of [
			"SIGINT",
			"SIGHUP",
			"SIGTERM"
		]) {
			const handler = () => {
				if (child.pid === void 0) return;
				try {
					process.kill(-child.pid, signal);
				} catch (error) {
					if (error.code !== "ESRCH") reject(error);
				}
			};
			handlers.set(signal, handler);
			process.on(signal, handler);
		}
		child.once("error", (error) => {
			cleanupHandlers();
			reject(error);
		});
		child.once("exit", (code, signal) => {
			cleanupHandlers();
			complete({
				code: signal ? signalExitCode(signal) : code ?? 1,
				stdout: Buffer.concat(stdout),
				stderr: Buffer.concat(stderr)
			});
		});
	});
}
async function runAssemblyResult(options) {
	const resolvedSpec = bindContextConfigs(options.spec, options.contextName, options.names);
	if (!getConfigContext(options.spec, options.contextName).canonical && !options.check && !options.stdout) await assertContextOutputsSeparated(options.spec, resolvedSpec);
	const temporary = await mkdtemp(join(tmpdir(), "compfuzor-config-context-"));
	const resolvedPath = join(temporary, "config.spec.json");
	try {
		await writeFile(resolvedPath, JSON.stringify(resolvedSpec), { mode: 384 });
		return await invokeRunner(options, resolvedPath);
	} finally {
		await rm(temporary, {
			recursive: true,
			force: true
		});
	}
}
async function runAssembly(options) {
	return (await runAssemblyResult(options)).code;
}
async function evaluateAssembly(options, name) {
	try {
		const result = await runAssemblyResult({
			...options,
			names: [name],
			stdout: true,
			stdio: "pipe"
		});
		if (result.code === 0) return { candidate: result.stdout };
		const detail = result.stderr.toString("utf8").trim();
		return { error: `assembly candidate failed (exit ${result.code})${detail ? `: ${detail}` : ""}` };
	} catch (error) {
		return { error: `assembly candidate could not run: ${error instanceof Error ? error.message : String(error)}` };
	}
}
//#endregion
//#region files/config/file-state.ts
/** Shared regular-file availability and byte comparison observations. */
async function compareFileContents(first, second) {
	try {
		const [one, two] = await Promise.all([readFile(first), readFile(second)]);
		return { equal: one.equals(two) };
	} catch (error) {
		return {
			equal: false,
			error: `cannot compare ${first} and ${second}: ${error instanceof Error ? error.message : String(error)}`
		};
	}
}
async function inspectUsableFile(path) {
	const entry = await inspectDeliveryEntry(path);
	if (entry.kind === "missing") return {
		usable: false,
		note: "donor entry missing"
	};
	if (entry.kind === "directory" || entry.kind === "special") return {
		usable: false,
		note: `donor entry is ${entry.kind}`
	};
	try {
		if (!(await stat(path)).isFile()) return {
			usable: false,
			note: "donor entry does not resolve to a regular file"
		};
	} catch (error) {
		if (error.code === "ENOENT") return {
			usable: false,
			note: "donor entry is dangling"
		};
		return {
			usable: false,
			note: error instanceof Error ? error.message : String(error)
		};
	}
	return { usable: true };
}
//#endregion
//#region files/config/input-state.ts
/** Consumer input catalog, synchronization, and status observation. */
function fail$5(message) {
	throw new Error(message);
}
function object(value, label) {
	if (!value || typeof value !== "object" || Array.isArray(value)) fail$5(`${label} must be an object`);
	return value;
}
function filenameMatches$1(value, pattern) {
	return matchesGlob(`x${value}`, `x${pattern}`);
}
function inputIdentity$1(input, index) {
	return typeof input.name === "string" && input.name ? input.name : String(index);
}
async function pathKind(path) {
	return (await inspectDeliveryEntry(path)).kind;
}
async function readDirectory(path) {
	try {
		return await readdir(path, {
			withFileTypes: true,
			encoding: "utf8"
		});
	} catch (error) {
		if (error.code === "ENOENT") return void 0;
		throw error;
	}
}
async function inputCatalog(spec, contextName, names) {
	const resolved = bindContextConfigs(spec, contextName, names);
	const relations = [];
	const directories = [];
	const rows = [];
	for (const configName of names) {
		const donorConfig = object(spec.configs[configName], `config ${configName}`);
		const localConfig = object(resolved.configs[configName], `resolved config ${configName}`);
		for (let index = 0; index < donorConfig.inputs.length; index++) {
			const donor = donorConfig.inputs[index];
			const local = localConfig.inputs[index];
			const name = inputIdentity$1(donor, index);
			if (typeof donor.file === "string" && typeof local.file === "string") {
				const aliasHazard = await pathsSharePhysicalEntry(donor.file, local.file) ? `consumer file aliases canonical input: ${local.file}` : void 0;
				relations.push({
					id: `${configName}/${name}`,
					config: configName,
					inputIndex: index,
					inputName: name,
					source: donor.file,
					destination: local.file,
					logicalName: basename(local.file),
					donorState: "enabled",
					aliasHazard
				});
				continue;
			}
			if (typeof donor.directory !== "string" || typeof donor.pattern !== "string" || typeof local.directory !== "string") fail$5(`config ${configName} input ${index} has an invalid compiled shape`);
			const suffix = typeof donor.disabled_suffix === "string" ? donor.disabled_suffix : void 0;
			const directory = {
				config: configName,
				inputIndex: index,
				inputName: name,
				donorDirectory: donor.directory,
				destinationDirectory: local.directory,
				pattern: donor.pattern,
				suffix,
				donorNames: /* @__PURE__ */ new Set(),
				aliasHazard: await pathsSharePhysicalDirectory(donor.directory, local.directory) ? `consumer directory aliases canonical input directory: ${local.directory}` : void 0
			};
			directories.push(directory);
			const entries = await readDirectory(donor.directory);
			if (entries === void 0) {
				rows.push({
					kind: "input",
					status: "donor-missing",
					severity: "error",
					config: configName,
					name,
					source: donor.directory,
					destination: local.directory,
					note: "donor input directory is missing"
				});
				continue;
			}
			const byLogical = /* @__PURE__ */ new Map();
			for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
				const disabled = suffix !== void 0 && entry.name.endsWith(suffix);
				const logicalName = disabled ? entry.name.slice(0, -suffix.length) : entry.name;
				if (!filenameMatches$1(logicalName, donor.pattern)) continue;
				const source = join(donor.directory, entry.name);
				const relation = {
					id: `${configName}/${name}/${logicalName}`,
					config: configName,
					inputIndex: index,
					inputName: name,
					source,
					destinationDirectory: local.directory,
					destination: join(local.directory, entry.name),
					logicalName,
					pattern: donor.pattern,
					suffix,
					donorState: disabled ? "disabled" : "enabled"
				};
				const previous = byLogical.get(logicalName);
				if (previous) {
					previous.donorConflict = source;
					continue;
				}
				byLogical.set(logicalName, relation);
				directory.donorNames.add(logicalName);
			}
			relations.push(...byLogical.values());
		}
	}
	return {
		relations,
		directories,
		rows
	};
}
async function localSelection(relation) {
	if (!relation.destinationDirectory || !relation.suffix) {
		const entry = await inspectDeliveryEntry(relation.destination);
		return {
			active: relation.destination,
			activeEntry: entry,
			selectedPath: entry.kind === "missing" ? void 0 : relation.destination,
			selectedState: entry.kind === "missing" ? void 0 : "enabled",
			selectedEntry: entry.kind === "missing" ? void 0 : entry,
			conflict: false
		};
	}
	const active = join(relation.destinationDirectory, relation.logicalName);
	const disabled = `${active}${relation.suffix}`;
	const [activeEntry, disabledEntry] = await Promise.all([inspectDeliveryEntry(active), inspectDeliveryEntry(disabled)]);
	const hasActive = activeEntry.kind !== "missing";
	const hasDisabled = disabledEntry.kind !== "missing";
	return {
		active,
		disabled,
		activeEntry,
		disabledEntry,
		selectedPath: hasActive ? active : hasDisabled ? disabled : void 0,
		selectedState: hasActive ? "enabled" : hasDisabled ? "disabled" : void 0,
		selectedEntry: hasActive ? activeEntry : hasDisabled ? disabledEntry : void 0,
		conflict: hasActive && hasDisabled
	};
}
async function deliver$1(source, destination, strategy) {
	if (strategy === "link") await replaceWithLink(source, destination);
	else await replaceWithCopy(source, destination);
}
async function applyRelation(relation, strategy, seed) {
	if (relation.aliasHazard) fail$5(`${relation.id}: ${relation.aliasHazard}`);
	if (relation.donorConflict) fail$5(`${relation.id}: donor has both enabled and disabled entries`);
	const sourceEntry = await inspectDeliveryEntry(relation.source);
	if (sourceEntry.kind === "missing" || sourceEntry.kind === "directory" || sourceEntry.kind === "special") fail$5(`${relation.id}: donor source is ${sourceEntry.kind}: ${relation.source}`);
	const local = await localSelection(relation);
	if (local.conflict) fail$5(`${relation.id}: both enabled and disabled local entries exist`);
	if (seed && local.selectedPath) return `preserved\t${relation.id}\t${local.selectedState}\t${local.selectedPath}`;
	const state = local.selectedState ?? relation.donorState;
	const destination = state === "disabled" && relation.suffix && relation.destinationDirectory ? join(relation.destinationDirectory, `${relation.logicalName}${relation.suffix}`) : relation.destinationDirectory ? join(relation.destinationDirectory, relation.logicalName) : relation.destination;
	await deliver$1(relation.source, destination, strategy);
	return `${seed ? "seeded" : "refreshed"}\t${relation.id}\t${state}\t${strategy}\t${destination}`;
}
async function syncInputs(options) {
	const catalog = await inputCatalog(options.spec, options.contextName, options.names);
	let failed = catalog.rows.some((row) => row.severity === "error");
	for (const row of catalog.rows) console.error(`${row.status}: ${row.config}/${row.name}: ${row.note}`);
	const aliasHazards = [...catalog.relations.filter((relation) => relation.aliasHazard).map((relation) => `${relation.id}: ${relation.aliasHazard}`), ...catalog.directories.filter((directory) => directory.aliasHazard).map((directory) => `${directory.config}/${directory.inputName}: ${directory.aliasHazard}`)];
	if (aliasHazards.length > 0) {
		for (const hazard of aliasHazards) console.error(`error: ${hazard}`);
		return 2;
	}
	for (const directory of catalog.directories) try {
		await mkdir(directory.destinationDirectory, { recursive: true });
	} catch (error) {
		failed = true;
		console.error(`error: cannot create input directory ${directory.destinationDirectory}: ${error instanceof Error ? error.message : String(error)}`);
	}
	for (const relation of catalog.relations) try {
		console.log(await applyRelation(relation, options.strategy, options.seed));
	} catch (error) {
		failed = true;
		console.error(`error: ${error instanceof Error ? error.message : String(error)}`);
	}
	return failed ? 2 : 0;
}
async function relationStatus(relation) {
	if (relation.aliasHazard) return {
		kind: "input",
		status: "alias-hazard",
		severity: "error",
		config: relation.config,
		name: relation.logicalName,
		source: relation.source,
		destination: relation.destination,
		note: relation.aliasHazard
	};
	if (relation.donorConflict) return {
		kind: "input",
		status: "donor-conflict",
		severity: "drift",
		config: relation.config,
		name: relation.logicalName,
		source: relation.source,
		destination: relation.destination,
		note: `also present as ${relation.donorConflict}`
	};
	const source = await inspectUsableFile(relation.source);
	const local = await localSelection(relation);
	if (local.conflict) return {
		kind: "input",
		status: "local-conflict",
		severity: "drift",
		config: relation.config,
		name: relation.logicalName,
		source: relation.source,
		destination: local.active,
		note: `both ${local.active} and ${local.disabled} exist`
	};
	if (!local.selectedPath || !local.selectedEntry) return {
		kind: "input",
		status: source.usable ? "missing" : "donor-missing",
		severity: source.usable ? "drift" : "error",
		config: relation.config,
		name: relation.logicalName,
		state: relation.donorState,
		source: relation.source,
		destination: relation.destination,
		note: source.note
	};
	const common = {
		kind: "input",
		config: relation.config,
		name: relation.logicalName,
		state: local.selectedState,
		source: relation.source,
		destination: local.selectedPath
	};
	if (!source.usable) return {
		...common,
		status: "donor-missing",
		severity: "error",
		representation: local.selectedEntry.kind,
		note: source.note
	};
	if (local.selectedEntry.kind === "symlink") try {
		if (await linkResolvesToSameFile(local.selectedEntry, relation.source)) return {
			...common,
			status: "ok",
			severity: "ok",
			representation: "link"
		};
	} catch (error) {
		return {
			...common,
			status: "evaluation-error",
			severity: "error",
			representation: "link",
			note: `cannot resolve link referents: ${error instanceof Error ? error.message : String(error)}`
		};
	}
	if (local.selectedEntry.kind === "file") {
		const comparison = await compareFileContents(relation.source, local.selectedPath);
		if (comparison.error) return {
			...common,
			status: "evaluation-error",
			severity: "error",
			representation: "copy",
			note: comparison.error
		};
		if (comparison.equal) return {
			...common,
			status: "ok",
			severity: "ok",
			representation: "copy"
		};
	}
	if (local.selectedEntry.kind === "directory" || local.selectedEntry.kind === "special") return {
		...common,
		status: "unsupported",
		severity: "drift",
		representation: local.selectedEntry.kind
	};
	return {
		...common,
		status: "modified",
		severity: "drift",
		representation: local.selectedEntry.kind === "file" ? "copy" : "link",
		note: local.selectedEntry.kind === "symlink" ? `points to ${local.selectedEntry.target}` : "bytes differ from donor"
	};
}
async function extraInputRows(directory) {
	const entries = await readDirectory(directory.destinationDirectory);
	if (entries === void 0) return [];
	const grouped = /* @__PURE__ */ new Map();
	for (const entry of entries) {
		const suffix = directory.suffix;
		const disabled = suffix !== void 0 && entry.name.endsWith(suffix);
		const logical = disabled ? entry.name.slice(0, -suffix.length) : entry.name;
		if (!filenameMatches$1(logical, directory.pattern) || directory.donorNames.has(logical)) continue;
		const group = grouped.get(logical) ?? {};
		group[disabled ? "disabled" : "active"] = join(directory.destinationDirectory, entry.name);
		grouped.set(logical, group);
	}
	const rows = [];
	for (const [logical, group] of [...grouped].sort(([a], [b]) => a.localeCompare(b))) {
		if (group.active && group.disabled) {
			rows.push({
				kind: "input",
				status: "local-conflict",
				severity: "drift",
				config: directory.config,
				name: logical,
				source: directory.donorDirectory,
				destination: group.active,
				note: `both active and disabled local entries exist`
			});
			continue;
		}
		const path = group.active ?? group.disabled;
		const entry = await inspectDeliveryEntry(path);
		let status = "local";
		let severity = entry.kind === "directory" || entry.kind === "special" ? "drift" : "ok";
		let note = "not present in current donor catalog";
		if (entry.kind === "symlink") {
			const donorRelative = normalize(entry.targetPath).startsWith(`${normalize(directory.donorDirectory)}/`);
			try {
				if (!(await stat(path)).isFile()) {
					status = "non-file-referent";
					severity = "drift";
					note = `local link resolves to a non-file: ${entry.target}`;
				}
			} catch (error) {
				if (error.code === "ENOENT") {
					status = donorRelative ? "donor-missing" : "dangling";
					severity = "error";
					note = donorRelative ? `dangling link into donor directory: ${entry.target}` : `local link has a missing referent: ${entry.target}`;
				} else {
					status = "evaluation-error";
					severity = "error";
					note = `cannot inspect local link referent: ${error instanceof Error ? error.message : String(error)}`;
				}
			}
		}
		rows.push({
			kind: "input",
			status,
			severity,
			config: directory.config,
			name: logical,
			state: group.disabled ? "disabled" : "enabled",
			representation: entry.kind,
			destination: path,
			note
		});
	}
	return rows;
}
async function inputStatusRows(spec, contextName, names) {
	const catalog = await inputCatalog(spec, contextName, names);
	const rows = [...catalog.rows];
	for (const relation of catalog.relations) rows.push(await relationStatus(relation));
	for (const directory of catalog.directories) {
		if (directory.aliasHazard) {
			rows.push({
				kind: "input",
				status: "alias-hazard",
				severity: "error",
				config: directory.config,
				name: directory.inputName,
				source: directory.donorDirectory,
				destination: directory.destinationDirectory,
				note: directory.aliasHazard
			});
			continue;
		}
		if (directory.donorNames.size === 0 && await pathKind(directory.destinationDirectory) === "missing") rows.push({
			kind: "input",
			status: "missing",
			severity: "drift",
			config: directory.config,
			name: directory.inputName,
			source: directory.donorDirectory,
			destination: directory.destinationDirectory,
			note: "empty consumer input directory is missing"
		});
		rows.push(...await extraInputRows(directory));
	}
	return rows;
}
//#endregion
//#region files/config/report.ts
function statusCode(rows) {
	if (rows.some((row) => row.severity === "error")) return 2;
	return rows.some((row) => row.severity === "drift") ? 1 : 0;
}
function printStatusRows(rows, format) {
	if (format === "array") {
		console.log(JSON.stringify(rows, null, 2));
		return;
	}
	if (format === "jsonl") {
		for (const row of rows) console.log(JSON.stringify(row));
		return;
	}
	if (rows.length === 0) return;
	console.log("kind	status	recipe	item	state	representation	source	destination	note");
	for (const row of rows) console.log([
		row.kind,
		row.status,
		row.config,
		row.name,
		row.state ?? "-",
		row.representation ?? "-",
		row.source ?? "-",
		row.destination ?? "-",
		row.note ?? "-"
	].join("	"));
}
//#endregion
//#region files/config/inputs.ts
function fail$4(message) {
	throw new Error(message);
}
function filenameMatches(value, pattern) {
	return matchesGlob(`x${value}`, `x${pattern}`);
}
function inputIdentity(input, index) {
	return typeof input.name === "string" && input.name ? input.name : String(index);
}
async function deliver(source, destination, strategy) {
	if (strategy === "link") await replaceWithLink(source, destination);
	else await replaceWithCopy(source, destination);
}
function selectInput(spec, contextName, selector) {
	const slash = selector.indexOf("/");
	const configSelector = slash === -1 ? void 0 : selector.slice(0, slash);
	const inputSelector = slash === -1 ? selector : selector.slice(slash + 1);
	const matches = [];
	for (const config of contextConfigNames(spec, contextName)) {
		if (configSelector && config !== configSelector) continue;
		spec.configs[config].inputs.forEach((input, index) => {
			if (inputIdentity(input, index) === inputSelector) matches.push({
				config,
				index,
				source: input
			});
		});
	}
	if (matches.length !== 1) fail$4(matches.length === 0 ? `unknown context input: ${selector}` : `ambiguous context input: ${selector}; use CONFIG/INPUT`);
	const selected = matches[0];
	const consumer = bindContextConfigs(spec, contextName, [selected.config]).configs[selected.config].inputs[selected.index];
	return {
		...selected,
		consumer
	};
}
async function rebuild(options, config) {
	const code = await runAssembly({
		spec: options.spec,
		contextName: options.contextName,
		runner: options.runner,
		names: [config]
	});
	if (code === 0) return 0;
	console.error(`input mutation remains; config rebuild failed for ${config} (exit ${code})`);
	return 4;
}
function localInputPaths(selected, name) {
	if (typeof selected.consumer.directory !== "string") fail$4(`${selected.config}/${inputIdentity(selected.source, selected.index)} is not a glob input`);
	const suffix = typeof selected.source.disabled_suffix === "string" ? selected.source.disabled_suffix : void 0;
	return {
		active: join(selected.consumer.directory, name),
		disabled: suffix ? join(selected.consumer.directory, `${name}${suffix}`) : void 0
	};
}
async function assertInputBindingSeparated(selected) {
	if (typeof selected.source.file === "string" && typeof selected.consumer.file === "string") {
		if (await pathsSharePhysicalEntry(selected.source.file, selected.consumer.file)) fail$4(`${selected.config}/${inputIdentity(selected.source, selected.index)} consumer file aliases canonical input: ${selected.consumer.file}`);
		return;
	}
	if (typeof selected.source.directory === "string" && typeof selected.consumer.directory === "string" && await pathsSharePhysicalDirectory(selected.source.directory, selected.consumer.directory)) fail$4(`${selected.config}/${inputIdentity(selected.source, selected.index)} consumer directory aliases canonical input directory: ${selected.consumer.directory}`);
}
function validateInputName(input, name) {
	if (!name || basename(name) !== name || name === "." || name === "..") fail$4(`invalid input filename: ${name}`);
	if (typeof input.pattern !== "string" || !filenameMatches(name, input.pattern)) fail$4(`${name} does not match input pattern ${String(input.pattern)}`);
	if (typeof input.disabled_suffix === "string" && name.endsWith(input.disabled_suffix)) fail$4(`input filename must not include disabled suffix ${input.disabled_suffix}`);
}
async function inspectPair(paths) {
	const [active, disabled] = await Promise.all([inspectDeliveryEntry(paths.active), paths.disabled ? inspectDeliveryEntry(paths.disabled) : Promise.resolve(void 0)]);
	return {
		active,
		disabled,
		conflict: active.kind !== "missing" && disabled !== void 0 && disabled.kind !== "missing"
	};
}
async function putInput(options) {
	const spec = options.spec;
	const selector = options.selector;
	const sourceArgument = options.source;
	const suppliedName = options.name;
	const selected = selectInput(spec, options.contextName, selector);
	await assertInputBindingSeparated(selected);
	const source = resolve(sourceArgument);
	if (typeof selected.source.file === "string") {
		if (suppliedName !== void 0) fail$4(`${selector} is a direct file input and does not accept a destination name`);
		if (options.initiallyDisabled ?? false) fail$4(`${selector} is a direct file input and cannot be disabled`);
		if (typeof selected.consumer.file !== "string") fail$4(`${selector} has an invalid resolved file binding`);
		await deliver(source, selected.consumer.file, options.strategy ?? getConfigContext(spec, options.contextName).dropins ?? "link");
		console.log(`put\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${selected.consumer.file}`);
		return options.rebuild ?? true ? rebuild(options, selected.config) : 0;
	}
	const name = suppliedName ?? basename(source);
	validateInputName(selected.source, name);
	const paths = localInputPaths(selected, name);
	const pair = await inspectPair(paths);
	if (pair.conflict) fail$4(`both enabled and disabled local entries exist for ${name}`);
	const destination = pair.active.kind !== "missing" ? paths.active : pair.disabled && pair.disabled.kind !== "missing" ? paths.disabled : options.initiallyDisabled ?? false ? paths.disabled ?? fail$4(`${selector} cannot be disabled`) : paths.active;
	await deliver(source, destination, options.strategy ?? getConfigContext(spec, options.contextName).dropins ?? "link");
	console.log(`put\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${destination}`);
	return options.rebuild ?? true ? rebuild(options, selected.config) : 0;
}
//#endregion
//#region files/config/publication.ts
/** Whole-output publication for selected CONFIG recipes. */
async function publishOutputs(options) {
	const resolved = bindContextConfigs(options.spec, options.contextName, options.names);
	let failed = false;
	for (const name of options.names) {
		const source = options.spec.configs[name].output;
		const destination = resolved.configs[name].output;
		try {
			if (options.strategy === "link") await replaceWithLink(source, destination);
			else await replaceWithCopy(source, destination);
			console.log(`${options.strategy}\t${name}\t${source}\t${destination}`);
		} catch (error) {
			failed = true;
			console.error(`error: ${name}: ${error instanceof Error ? error.message : String(error)}`);
		}
	}
	return failed ? 2 : 0;
}
//#endregion
//#region files/config/install.ts
/** Complete ordinary CONFIG install over typed assembly and delivery operations. */
function truthy$1(value) {
	return [
		"1",
		"true",
		"y",
		"yes"
	].includes(value?.trim().toLowerCase() ?? "");
}
function resolve$1(value) {
	return typeof value === "function" ? value() : value;
}
async function installContext(options) {
	const reason = truthy$1(process.env.COMPFUZOR_CONFIG_CONTEXTS_BYPASS) ? "COMPFUZOR_CONFIG_CONTEXTS_BYPASS" : truthy$1(process.env.COMPFUZOR_CONFIG_BYPASS) ? "COMPFUZOR_CONFIG_BYPASS" : void 0;
	if (reason) return {
		status: "skipped",
		code: 0,
		reason
	};
	const strategy = resolve$1(options.strategy);
	if (strategy === "copy" || strategy === "link") return {
		status: "completed",
		code: await publishOutputs({
			...options,
			strategy
		})
	};
	if (!options.inputStrategy) throw new Error("assemble install requires an input strategy");
	const inputStrategy = resolve$1(options.inputStrategy);
	const seeded = await syncInputs({
		...options,
		strategy: inputStrategy,
		seed: true
	});
	if (seeded !== 0) return {
		status: "completed",
		code: seeded
	};
	return {
		status: "completed",
		code: await runAssembly({
			spec: options.spec,
			contextName: options.contextName,
			runner: options.runner,
			names: options.names
		})
	};
}
//#endregion
//#region files/config/status.ts
/** Multi-representation CONFIG status over selected recipes. */
async function candidateMatches(candidate, destination) {
	try {
		return { equal: candidate.equals(await readFile(destination)) };
	} catch (error) {
		return {
			equal: false,
			error: `cannot read assembled output ${destination}: ${error instanceof Error ? error.message : String(error)}`
		};
	}
}
async function outputStatusRows(options) {
	const resolved = bindContextConfigs(options.spec, options.contextName, options.names);
	const rows = [];
	for (const name of options.names) {
		const source = options.spec.configs[name].output;
		const destination = resolved.configs[name].output;
		const [sourceState, entry, assembly, aliasHazard] = await Promise.all([
			inspectUsableFile(source),
			inspectDeliveryEntry(destination),
			evaluateAssembly(options, name),
			pathsSharePhysicalEntry(source, destination)
		]);
		const common = {
			kind: "output",
			config: name,
			name,
			source,
			destination
		};
		rows.push(assembly.error ? {
			kind: "assembly",
			status: "evaluation-error",
			severity: "error",
			config: name,
			name,
			note: assembly.error
		} : {
			kind: "assembly",
			status: "ready",
			severity: "ok",
			config: name,
			name
		});
		if (aliasHazard) {
			rows.push({
				...common,
				status: "alias-hazard",
				severity: "error",
				note: `consumer output aliases canonical output: ${destination}`
			});
			continue;
		}
		if (entry.kind === "missing") {
			rows.push({
				...common,
				status: "missing",
				severity: "drift",
				note: sourceState.usable ? void 0 : `canonical output unavailable: ${sourceState.note}`
			});
			continue;
		}
		if (entry.kind === "directory" || entry.kind === "special") {
			rows.push({
				...common,
				status: "unsupported",
				severity: "drift",
				representation: entry.kind
			});
			continue;
		}
		if (entry.kind === "symlink") {
			if (!sourceState.usable && linkMatches(entry, source)) {
				rows.push({
					...common,
					status: "donor-missing",
					severity: "error",
					representation: "link",
					note: sourceState.note
				});
				continue;
			}
			if (sourceState.usable) try {
				if (await linkResolvesToSameFile(entry, source)) {
					rows.push({
						...common,
						status: "ok",
						severity: "ok",
						representation: "link"
					});
					continue;
				}
			} catch (error) {
				rows.push({
					...common,
					status: "evaluation-error",
					severity: "error",
					representation: "link",
					note: `cannot resolve link referents: ${error instanceof Error ? error.message : String(error)}`
				});
				continue;
			}
			rows.push({
				...common,
				status: "modified",
				severity: "drift",
				representation: "link",
				note: `points to ${entry.target}`
			});
			continue;
		}
		let donorComparisonError;
		if (sourceState.usable) {
			const donorComparison = await compareFileContents(source, destination);
			if (donorComparison.equal) {
				rows.push({
					...common,
					status: "ok",
					severity: "ok",
					representation: "copy"
				});
				continue;
			}
			donorComparisonError = donorComparison.error;
			if (donorComparison.error && !assembly.candidate) {
				rows.push({
					...common,
					status: "evaluation-error",
					severity: "error",
					representation: "copy",
					note: donorComparison.error
				});
				continue;
			}
		}
		if (assembly.candidate) {
			const localComparison = await candidateMatches(assembly.candidate, destination);
			if (localComparison.error) rows.push({
				...common,
				status: "evaluation-error",
				severity: "error",
				representation: "assembly",
				note: localComparison.error
			});
			else if (localComparison.equal) rows.push({
				...common,
				status: "ok",
				severity: "ok",
				representation: "assembly",
				note: donorComparisonError ?? (sourceState.usable ? void 0 : `canonical output unavailable: ${sourceState.note}`)
			});
			else rows.push({
				...common,
				status: "modified",
				severity: "drift",
				representation: "assembly",
				note: donorComparisonError ?? (sourceState.usable ? "differs from donor and local assembly" : `differs from local assembly; canonical output unavailable: ${sourceState.note}`)
			});
		} else rows.push({
			...common,
			status: "unclassified",
			severity: "error",
			representation: "file",
			note: "assembly evaluation failed"
		});
	}
	return rows;
}
async function assemblyInputsActive(spec, contextName, config) {
	const resolved = bindContextConfigs(spec, contextName, [config]).configs[config];
	for (const input of resolved.inputs) {
		const path = typeof input.file === "string" ? input.file : input.directory;
		if (typeof path !== "string") continue;
		if ((await inspectDeliveryEntry(path)).kind !== "missing") return true;
	}
	return false;
}
async function markInactiveAssemblyRoutes(options, rows) {
	for (const config of options.names) {
		const output = rows.find((row) => row.kind === "output" && row.config === config);
		const assembly = rows.find((row) => row.kind === "assembly" && row.config === config);
		if (!(output?.status === "ok" && (output.representation === "copy" || output.representation === "link")) || assembly?.status !== "evaluation-error" || await assemblyInputsActive(options.spec, options.contextName, config)) continue;
		assembly.status = "inactive";
		assembly.severity = "ok";
		assembly.note = `local assembly inputs are not initialized; ${assembly.note}`;
		for (const row of rows) if (row.kind === "input" && row.config === config && row.status === "missing") {
			row.status = "inactive";
			row.severity = "ok";
			row.note = row.note ? `inactive assembly route: ${row.note}` : "inactive assembly route";
		}
	}
}
async function canonicalStatusRows(options) {
	const rows = [];
	for (const name of options.names) {
		const destination = options.spec.configs[name].output;
		const [entry, assembly] = await Promise.all([inspectDeliveryEntry(destination), evaluateAssembly(options, name)]);
		if (assembly.error) {
			rows.push({
				kind: "assembly",
				status: "evaluation-error",
				severity: "error",
				config: name,
				name,
				destination,
				note: assembly.error
			});
			continue;
		}
		rows.push({
			kind: "assembly",
			status: "ready",
			severity: "ok",
			config: name,
			name,
			destination
		});
		if (entry.kind === "missing") rows.push({
			kind: "output",
			status: "missing",
			severity: "drift",
			config: name,
			name,
			destination
		});
		else if (entry.kind !== "file") rows.push({
			kind: "output",
			status: "unsupported",
			severity: "drift",
			config: name,
			name,
			destination,
			representation: entry.kind,
			note: "canonical assembly owns a regular file"
		});
		else {
			const comparison = await candidateMatches(assembly.candidate, destination);
			rows.push(comparison.error ? {
				kind: "output",
				status: "evaluation-error",
				severity: "error",
				config: name,
				name,
				destination,
				representation: "assembly",
				note: comparison.error
			} : {
				kind: "output",
				status: comparison.equal ? "ok" : "modified",
				severity: comparison.equal ? "ok" : "drift",
				config: name,
				name,
				destination,
				representation: "assembly"
			});
		}
	}
	return rows;
}
async function statusContext(options) {
	const context = getConfigContext(options.spec, options.contextName);
	const rows = context.canonical ? await canonicalStatusRows(options) : [...await outputStatusRows(options), ...await inputStatusRows(options.spec, options.contextName, options.names)];
	if (!context.canonical) await markInactiveAssemblyRoutes(options, rows);
	printStatusRows(rows, options.format);
	return statusCode(rows);
}
//#endregion
//#region files/zim/activation.ts
/** Zim context binding, loader projection, cache builds, and health checks. */
function fail$3(message) {
	throw new Error(message);
}
function resolveActivation(name, zimSpec, configSpec) {
	const spec = zimSpec.contexts[name] ?? fail$3(`unknown Zim context: ${name}`);
	const bound = bindContextConfigs(configSpec, spec.config, ["zimrc", "zimenv"]);
	return {
		name,
		spec,
		configSpec,
		zimrc: bound.configs.zimrc.output,
		zimenv: bound.configs.zimenv.output,
		loaderRoot: resolvePathSelector(spec.loader_root, void 0, `Zim context ${name}.loader_root`),
		zimrcHome: resolvePathSelector(spec.zimrc_home, void 0, `Zim context ${name}.zimrc_home`),
		zimenvHome: resolvePathSelector(spec.zimenv_home, void 0, `Zim context ${name}.zimenv_home`),
		registry: resolvePathSelector(spec.registry, void 0, `Zim context ${name}.registry`)
	};
}
async function runCommand(file, args, capture = false, input) {
	return await new Promise((complete, reject) => {
		const child = spawn(file, args, { stdio: capture ? [
			input ? "pipe" : "ignore",
			"pipe",
			"pipe"
		] : input ? [
			"pipe",
			"inherit",
			"inherit"
		] : "inherit" });
		const stdout = [];
		const stderr = [];
		child.stdout?.on("data", (chunk) => stdout.push(Buffer.from(chunk)));
		child.stderr?.on("data", (chunk) => stderr.push(Buffer.from(chunk)));
		child.once("error", reject);
		child.once("exit", (code, signal) => complete({
			code: signal ? 1 : code ?? 1,
			stdout: Buffer.concat(stdout),
			stderr: Buffer.concat(stderr)
		}));
		if (input) child.stdin?.end(input);
	});
}
function zshQuote(value) {
	if (value.includes("\0")) fail$3("cannot project a Zsh path containing NUL");
	return `'${value.replaceAll("'", "'\\''")}'`;
}
function replaceLoaderToken(template, token, value, source) {
	const first = template.indexOf(token);
	if (first < 0) fail$3(`Zim loader template ${source} is missing ${token}`);
	if (template.indexOf(token, first + token.length) >= 0) fail$3(`Zim loader template ${source} repeats ${token}`);
	return `${template.slice(0, first)}${value}${template.slice(first + token.length)}`;
}
async function projectLoader(channel, activation, canonical) {
	const template = channel === "zimrc" ? canonical.zimrcLoaderTemplate : canonical.zimenvLoaderTemplate;
	const home = channel === "zimrc" ? activation.zimrcHome : activation.zimenvHome;
	const config = channel === "zimrc" ? activation.zimrc : activation.zimenv;
	const legacy = channel === "zimrc" ? canonical.zimrcLegacy : canonical.zimenvLegacy;
	let projected = await readFile(template, "utf8");
	const replacements = [
		["@@ZIM_CACHE_HOME@@", zshQuote(home)],
		["@@ZIM_CONFIG_OUTPUT@@", zshQuote(config)],
		["@@ZIM_LEGACY_CONFIG_PATTERN@@", [...new Set(legacy)].map(zshQuote).join("|")],
		["@@ZIM_CONTROLLER@@", zshQuote(canonical.controller)]
	];
	if (channel === "zimrc") replacements.push(["@@ZIM_EMERGENCY_MODULE@@", zshQuote(canonical.emergencyModule)]);
	for (const [token, value] of replacements) projected = replaceLoaderToken(projected, token, value, template);
	const unknown = projected.match(/@@ZIM_[A-Z_]+@@/);
	if (unknown) fail$3(`Zim loader template ${template} has unsupported placeholder ${unknown[0]}`);
	projected = projected.replace(/\r?\n$/, "");
	return {
		content: Buffer.from(projected),
		template
	};
}
async function installLoader(block, content, destination, legacyBlock) {
	const executable = process.env.CONFIG_BLOCK_IN_FILE || "block-in-file";
	try {
		await lstat(destination);
		if ((await runCommand(executable, [
			"--remove-match",
			`^${legacyBlock}$`,
			"-o",
			destination
		])).code !== 0) fail$3(`failed to remove legacy block from ${destination}`);
	} catch (error) {
		if (error.code !== "ENOENT") throw error;
	}
	if ((await runCommand(executable, [
		"-n",
		block,
		"-C",
		"true",
		"-i",
		"-",
		"-o",
		destination
	], false, content)).code !== 0) fail$3(`failed to install block ${block} in ${destination}`);
}
async function buildChannel(channel, activation, canonical) {
	const home = channel === "zimrc" ? activation.zimrcHome : activation.zimenvHome;
	const config = channel === "zimrc" ? activation.zimrc : activation.zimenv;
	if ((await runCommand("zsh", [
		"-dfc",
		`ZIM_HOME=$1\nZIM_CONFIG_FILE=$2\ncontroller=$3\nshift 3\nsource "$controller" "$@"`,
		`zimfw-${channel}`,
		home,
		config,
		canonical.controller,
		"install"
	])).code !== 0) fail$3(`failed to build ${channel} cache for context ${activation.name}`);
}
async function installActivation(activation, canonical) {
	const [zimenvLoader, zimrcLoader] = await Promise.all([projectLoader("zimenv", activation, canonical), projectLoader("zimrc", activation, canonical)]);
	await mkdir(activation.loaderRoot, { recursive: true });
	await installLoader(`${canonical.blockPrefix}-zimenv`, zimenvLoader.content, join(activation.loaderRoot, ".zshenv"), canonical.blockPrefix);
	await installLoader(`${canonical.blockPrefix}-zimrc`, zimrcLoader.content, join(activation.loaderRoot, ".zshrc"), canonical.blockPrefix);
	await buildChannel("zimenv", activation, canonical);
	await buildChannel("zimrc", activation, canonical);
}
async function loaderHealthy(channel, activation, canonical) {
	const destination = join(activation.loaderRoot, channel === "zimrc" ? ".zshrc" : ".zshenv");
	let projection;
	try {
		projection = await projectLoader(channel, activation, canonical);
	} catch (error) {
		const template = channel === "zimrc" ? canonical.zimrcLoaderTemplate : canonical.zimenvLoaderTemplate;
		console.log(`zim ${channel} loader: drift: ${destination} (loader template is missing or invalid: ${template}: ${error instanceof Error ? error.message : String(error)})`);
		return false;
	}
	const name = `${canonical.blockPrefix}-${channel}`;
	const result = await runCommand(process.env.CONFIG_BLOCK_IN_FILE || "block-in-file", [
		"--read",
		"-n",
		name,
		destination
	], true);
	if (result.code !== 0) {
		console.log(`zim ${channel} loader: drift: ${destination} (block ${name} is missing or unreadable)`);
		return false;
	}
	if (projection.content.equals(result.stdout)) {
		console.log(`zim ${channel} loader: ok: ${destination}`);
		return true;
	}
	console.log(`zim ${channel} loader: drift: ${destination} (block ${name} differs from projected template ${projection.template})`);
	return false;
}
async function cacheHealthy(channel, activation) {
	const config = channel === "zimrc" ? activation.zimrc : activation.zimenv;
	const home = channel === "zimrc" ? activation.zimrcHome : activation.zimenvHome;
	const cache = join(home, "init.zsh");
	try {
		const [configStat, cacheStat] = await Promise.all([stat(config), stat(cache)]);
		if (cacheStat.mtimeMs > configStat.mtimeMs) {
			console.log(`zim ${channel} cache: ok: ${cache}`);
			return true;
		}
	} catch {}
	console.log(`zim ${channel} cache: drift: ${cache} (missing or stale for ${config})`);
	return false;
}
async function activationHealthy(activation, canonical) {
	return (await Promise.all([
		cacheHealthy("zimenv", activation),
		cacheHealthy("zimrc", activation),
		loaderHealthy("zimenv", activation, canonical),
		loaderHealthy("zimrc", activation, canonical)
	])).every(Boolean);
}
//#endregion
//#region files/config/invocation.ts
function fail$2(message) {
	throw new Error(message);
}
/**
* Resolve one declared name. Alias parsing is deliberately lazy: an explicit
* value completely bypasses it, allowing callers to escape stale aliases.
*/
function resolveSelectedName(options) {
	const declared = new Set(options.declared);
	const selected = options.explicit ?? options.inferAlias(options.invokedAs, declared) ?? options.environment ?? options.fallback;
	if (!declared.has(selected)) fail$2(`unknown ${options.label}: ${selected}`);
	return selected;
}
//#endregion
//#region files/zim/cli.ts
/** Zim command parsing, context selection, strategy normalization, and help. */
const HELP = {
	install: `Usage: install-zim.sh [--context NAME] [--install assemble|copy|link] [--dropins copy|link]

Install and activate Zim for a selected context: install its CONFIG recipes,
project startup loaders, build both caches, and publish the registry link.

Options:
  --context NAME                 Select a declared Zim context
  --install assemble|copy|link  Override CONFIG output installation
  --dropins copy|link            Override CONFIG input delivery`,
	import: `Usage: install-zim-context.sh [--context NAME] [--dropins copy|link] PRODUCER_DIR

Import a producer's Zim fragments into a selected consumer context, then rebuild
only the channels that received fragments.

Options:
  --context NAME       Select a declared Zim context
  --dropins copy|link  Select imported fragment representation`,
	status: `Usage: status-zim.sh [--context NAME] [--activation-only]

Report Zim activation health: CONFIG state, startup loaders, both caches, and
the registry link. Exit 0 is clean, 1 is drift, and 2 is an evaluation error.

Options:
  --context NAME     Select a declared Zim context
  --activation-only  Skip CONFIG rows (used by aggregate status)`
};
function fail$1(message) {
	throw new Error(message);
}
function parseInstallStrategy(value, label) {
	if (value === "assemble" || value === "copy" || value === "link") return value;
	fail$1(`${label} must be assemble, copy, or link`);
}
function parseInputStrategy(value, label) {
	if (value === "copy" || value === "link") return value;
	fail$1(`${label} must be copy or link`);
}
function parseZimArgs(argv, deploymentDir) {
	const { values, positionals } = parseArgs({
		args: argv,
		strict: true,
		allowPositionals: true,
		options: {
			context: { type: "string" },
			install: { type: "string" },
			dropins: { type: "string" },
			"invoked-as": { type: "string" },
			spec: { type: "string" },
			"config-spec": { type: "string" },
			"config-runner": { type: "string" },
			"activation-only": { type: "boolean" },
			help: {
				type: "boolean",
				short: "h"
			}
		}
	});
	const actionIndex = positionals.findIndex((value) => value === "install" || value === "import" || value === "status");
	const action = actionIndex < 0 ? void 0 : positionals[actionIndex];
	if (values.help) {
		console.log(action ? HELP[action] : Object.values(HELP).join("\n\n"));
		process.exit(0);
	}
	if (!action) fail$1("expected Zim action: install, import, or status");
	const args = positionals.toSpliced(actionIndex, 1);
	if (action !== "import" && args.length > 0) fail$1(`${action} does not accept positional arguments`);
	if (action === "import" && args.length !== 1) fail$1("import requires exactly one producer directory");
	if (values["activation-only"] && action !== "status") fail$1("--activation-only requires status");
	return {
		action,
		context: values.context,
		install: values.install === void 0 ? void 0 : parseInstallStrategy(values.install, "--install"),
		dropins: values.dropins === void 0 ? void 0 : parseInputStrategy(values.dropins, "--dropins"),
		invokedAs: basename(values["invoked-as"] ?? "install-zim.sh"),
		zimSpecPath: resolve(values.spec ?? join(deploymentDir, "etc", "zim.spec.json")),
		configSpecPath: resolve(values["config-spec"] ?? join(deploymentDir, "etc", "config.spec.json")),
		configRunner: resolve(values["config-runner"] ?? join(deploymentDir, "bin", "config", "run.sh")),
		activationOnly: values["activation-only"] ?? false,
		args
	};
}
function aliasContext(invokedAs, spec) {
	if (invokedAs === "install-zim.sh") return void 0;
	const match = /^install-zim-(.+)\.sh$/.exec(invokedAs);
	if (!match) fail$1(`unsupported Zim command alias ${invokedAs}; use install-zim-CONTEXT.sh or explicit --context`);
	if (!(match[1] in spec.contexts)) fail$1(`Zim command alias ${invokedAs} names undeclared context ${match[1]}`);
	return match[1];
}
function resolveSettings(options, spec, configSpec) {
	const contextName = resolveSelectedName({
		explicit: options.context,
		invokedAs: options.invokedAs,
		inferAlias: (invokedAs) => options.action === "install" ? aliasContext(invokedAs, spec) : void 0,
		environment: process.env.COMPFUZOR_ZIM_CONTEXT ?? process.env.COMPFUZOR_CONTEXT,
		fallback: spec.defaultContext,
		declared: Object.keys(spec.contexts),
		label: "Zim context"
	});
	const activation = spec.contexts[contextName];
	const configContext = getConfigContext(configSpec, activation.config);
	if (configContext.scope !== activation.scope) fail$1(`Zim context ${contextName} scope does not match config context ${activation.config}`);
	return {
		contextName,
		install: options.action === "install" ? options.install : void 0,
		dropins: options.action === "import" ? options.dropins ?? parseInputStrategy(process.env.COMPFUZOR_ZIM_DROPINS_STRATEGY ?? process.env.COMPFUZOR_CONFIG_DROPINS_STRATEGY ?? configContext.dropins ?? "link", "effective drop-in strategy") : options.action === "install" ? options.dropins : void 0
	};
}
//#endregion
//#region files/zim/install.ts
/** Complete Zim install, producer import, and status orchestration. */
function fail(message) {
	throw new Error(message);
}
function truthy(value) {
	return [
		"1",
		"true",
		"y",
		"yes"
	].includes(value?.trim().toLowerCase() ?? "");
}
async function withRegistryManifest(activation, canonical, callback) {
	const temporary = await mkdtemp(join(tmpdir(), "compfuzor-zim-registry-"));
	const path = join(temporary, "links.json");
	const manifest = {
		version: 1,
		deployment: { dir: dirname(canonical.controller) },
		links: [{
			id: `zim-registry-${activation.name}`,
			scope: activation.spec.scope,
			src: canonical.registry,
			dest: activation.registry,
			policy: "replace",
			state: "present"
		}]
	};
	try {
		await writeFile(path, JSON.stringify(manifest), { mode: 384 });
		return await callback(path);
	} finally {
		await rm(temporary, {
			recursive: true,
			force: true
		});
	}
}
async function runRegistry(action, activation, canonical, deploymentDir) {
	return withRegistryManifest(activation, canonical, async (manifest) => {
		const args = [
			action,
			"--scope",
			activation.spec.scope
		];
		if (action === "apply") args.push("--sudo", "never");
		args.push(manifest);
		return (await runCommand(join(deploymentDir, "bin", "links.mjs"), args)).code;
	});
}
async function installZim(options, settings, activation, spec, deploymentDir) {
	const configContext = getConfigContext(activation.configSpec, activation.spec.config);
	const configResult = await installContext({
		spec: activation.configSpec,
		contextName: activation.spec.config,
		runner: options.configRunner,
		names: ["zimrc", "zimenv"],
		strategy: () => settings.install ?? parseInstallStrategy(process.env.COMPFUZOR_ZIM_INSTALL_STRATEGY ?? process.env.COMPFUZOR_CONFIG_INSTALL_STRATEGY ?? configContext.install ?? "assemble", "effective install strategy"),
		inputStrategy: () => settings.dropins ?? parseInputStrategy(process.env.COMPFUZOR_ZIM_DROPINS_STRATEGY ?? process.env.COMPFUZOR_CONFIG_DROPINS_STRATEGY ?? configContext.dropins ?? "link", "effective drop-in strategy")
	});
	if (configResult.code !== 0) return configResult.code;
	if (configResult.status === "skipped") {
		const available = await Promise.all([activation.zimenv, activation.zimrc].map(async (path) => {
			try {
				return (await stat(path)).isFile();
			} catch {
				return false;
			}
		}));
		console.error(`skipped Zim config install for ${activation.name}: ${configResult.reason}`);
		if (!available.every(Boolean)) {
			console.error(`skipped remaining Zim install for ${activation.name}: required config outputs are unavailable`);
			return 0;
		}
	}
	await installActivation(activation, spec.canonical);
	const registryResult = await runRegistry("apply", activation, spec.canonical, deploymentDir);
	if (registryResult !== 0) return registryResult;
	return 0;
}
async function inventoryProducer(producer) {
	const records = [];
	const seen = /* @__PURE__ */ new Set();
	for (const channel of ["zimenv", "zimrc"]) for (const state of ["active", "disabled"]) {
		const directory = join(producer, "etc", "zim", channel, state);
		let entries;
		try {
			entries = await readdir(directory, {
				withFileTypes: true,
				encoding: "utf8"
			});
		} catch (error) {
			if (error.code === "ENOENT") continue;
			throw error;
		}
		for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
			if (!entry.name.endsWith(".conf") || !entry.isFile() && !entry.isSymbolicLink()) continue;
			const key = `${channel}/${entry.name}`;
			if (seen.has(key)) fail(`producer has both active and disabled entries: ${key}`);
			seen.add(key);
			records.push({
				channel,
				source: join(directory, entry.name),
				disabled: state === "disabled"
			});
		}
	}
	return records;
}
async function importProducer(options, settings, activation, spec) {
	const records = await inventoryProducer(resolve(options.args[0]));
	const touched = /* @__PURE__ */ new Set();
	for (const record of records) {
		const result = await putInput({
			spec: activation.configSpec,
			contextName: activation.spec.config,
			runner: options.configRunner,
			strategy: settings.dropins,
			rebuild: false,
			initiallyDisabled: record.disabled,
			selector: `${record.channel}/${record.channel}`,
			source: record.source,
			name: basename(record.source)
		});
		if (result !== 0) return result;
		touched.add(record.channel);
	}
	for (const channel of ["zimenv", "zimrc"]) {
		if (!touched.has(channel)) continue;
		const assembled = await runAssembly({
			spec: activation.configSpec,
			contextName: activation.spec.config,
			runner: options.configRunner,
			names: [channel]
		});
		if (assembled !== 0) return assembled;
		await buildChannel(channel, activation, spec.canonical);
	}
	console.log(`install-zim-context: imported ${records.length} fragment(s) for context ${activation.name}`);
	return 0;
}
async function statusZim(activation, spec, deploymentDir, configRunner, activationOnly) {
	const configResult = activationOnly ? 0 : await statusContext({
		spec: activation.configSpec,
		contextName: activation.spec.config,
		runner: configRunner,
		names: ["zimrc", "zimenv"],
		format: "human"
	});
	const healthy = await activationHealthy(activation, spec.canonical);
	const registryResult = await runRegistry("status", activation, spec.canonical, deploymentDir);
	if (configResult === 2 || registryResult === 2) return 2;
	return configResult === 0 && healthy && registryResult === 0 ? 0 : 1;
}
async function runZim(options, deploymentDir) {
	if (options.action !== "status" && truthy(process.env.COMPFUZOR_ZIM_BYPASS)) {
		console.error(`skipped Zim ${options.action}: COMPFUZOR_ZIM_BYPASS`);
		return 0;
	}
	const [zimSpec, configSpec] = await Promise.all([readFile(options.zimSpecPath, "utf8").then((text) => JSON.parse(text)), readFile(options.configSpecPath, "utf8").then((text) => JSON.parse(text))]);
	if (zimSpec.version !== 2) fail(`unsupported Zim spec version: ${String(zimSpec.version)}; rerender the deployment with the current playbook (expected version 2)`);
	const settings = resolveSettings(options, zimSpec, configSpec);
	const activation = resolveActivation(settings.contextName, zimSpec, configSpec);
	if (options.action === "install") return installZim(options, settings, activation, zimSpec, deploymentDir);
	if (options.action === "import") return importProducer(options, settings, activation, zimSpec);
	return statusZim(activation, zimSpec, deploymentDir, options.configRunner, options.activationOnly);
}
async function main(argv = process.argv.slice(2), modulePath = fileURLToPath(import.meta.url)) {
	const realModule = await realpath(modulePath);
	const deploymentDir = resolve(dirname(realModule), "../..");
	return runZim(parseZimArgs(argv, deploymentDir), deploymentDir);
}
const argvPath = process.argv[1];
if (argvPath) Promise.all([realpath(argvPath), realpath(fileURLToPath(import.meta.url))]).then(([realArgv, realModule]) => {
	if (realArgv !== realModule) return;
	return main(process.argv.slice(2), realModule).then((code) => {
		process.exitCode = code;
	}, (error) => {
		console.error(error instanceof Error ? error.stack : String(error));
		process.exitCode = 2;
	});
}, (error) => {
	console.error(error instanceof Error ? error.stack : String(error));
	process.exitCode = 2;
});
//#endregion
export { main, parseZimArgs, resolveSettings, runZim, zshQuote };
