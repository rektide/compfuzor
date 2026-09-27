#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
import { mkdir, realpath, rename, stat } from "node:fs/promises";
import i from "node:assert";
import { randomUUID } from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { dirname, join } from "node:path";
import { homedir } from "node:os";
//#region node_modules/.pnpm/gunshi@0.37.3/node_modules/gunshi/lib/utils-DbRhwNIU.js
/**
* Entry point of utils.
*
* Note that this entry point is used by gunshi to import utility functions.
*
* @module
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Convert a string to kebab-case.
*
* @param str - A string to convert
* @returns Converted string into kebab-case.
*/
function kebabnize$1(str) {
	return str.replace(/[A-Z]/g, (match, offset) => (offset > 0 ? "-" : "") + match.toLowerCase());
}
/**
* Format allowed argument choices for validation error values and fallback messages.
*
* @param choices - Choice values to format
* @returns JSON-quoted choices joined with `, `.
*/
function formatChoices(choices) {
	return choices.map((value) => JSON.stringify(value)).join(", ");
}
//#endregion
//#region node_modules/.pnpm/gunshi@0.37.3/node_modules/gunshi/lib/utils.js
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Check if the given command is a {@link LazyCommand}.
*
* @param cmd - A command to check
* @returns `true` if the command is a {@link LazyCommand}, otherwise `false
*/
function isLazyCommand$2(cmd) {
	return typeof cmd === "function" && "commandName" in cmd && !!cmd.commandName;
}
/**
* Resolve a lazy command to a {@link Command}.
*
* @param cmd - A {@link Commandable} or {@link LazyCommand} to resolve
* @param name - Optional name of the command, if not provided, it will use the name from the command itself.
* @param needRunResolving - Whether to run the resolving function of the lazy command.
* @returns A resolved {@link Command}
*/
async function resolveLazyCommand$1(cmd, name, needRunResolving = false) {
	let command;
	if (isLazyCommand$2(cmd)) {
		const baseCommand = {
			name: cmd.commandName,
			description: cmd.description,
			args: cmd.args,
			examples: cmd.examples,
			internal: cmd.internal,
			entry: cmd.entry,
			subCommands: cmd.subCommands
		};
		if ("resource" in cmd && cmd.resource) baseCommand.resource = cmd.resource;
		command = Object.assign(create$2(), baseCommand);
		if (needRunResolving) {
			const loaded = await cmd();
			if (typeof loaded === "function") command.run = loaded;
			else if (typeof loaded === "object") {
				if (loaded.run == null) throw new TypeError(`'run' is required in command: ${cmd.name || name}`);
				command.run = loaded.run;
				command.name = loaded.name;
				command.description = loaded.description;
				command.args = loaded.args;
				command.examples = loaded.examples;
				command.internal = loaded.internal;
				command.entry = loaded.entry;
				command.subCommands = loaded.subCommands || cmd.subCommands;
				if ("resource" in loaded && loaded.resource) command.resource = loaded.resource;
			} else throw new TypeError(`Cannot resolve command: ${cmd.name || name}`);
		}
	} else command = Object.assign(create$2(), cmd);
	if (command.name == null && name) command.name = name;
	return deepFreeze$2(command);
}
/**
* Create an object with the specified prototype. A shorthand for `Object.create`.
*
* @param obj - An object to use as the prototype for the new object. If `null`, it will create an object with no prototype.
* @returns A new object with the specified prototype
*/
function create$2(obj = null) {
	return Object.create(obj);
}
/**
* Log a message to the console.
*
* @param args - Arguments to log
*/
function log$1(...args) {
	console.log(...args);
}
/**
* Get the sub-commands of a command as a normalized Map.
*
* @param cmd - A command or lazy command
* @returns A Map of sub-commands, or undefined if the command has no sub-commands.
*/
function getCommandSubCommands(cmd) {
	const subCommands = isLazyCommand$2(cmd) ? cmd.subCommands : typeof cmd === "object" ? cmd.subCommands : void 0;
	if (!subCommands) return;
	if (subCommands instanceof Map) return subCommands.size > 0 ? subCommands : void 0;
	if (typeof subCommands === "object") {
		const entries = Object.entries(subCommands);
		if (entries.length === 0) return;
		const map = /* @__PURE__ */ new Map();
		for (const [name, cmd] of entries) map.set(name, cmd);
		return map;
	}
}
/**
* Deep freeze an object, making it immutable.
*
* @param obj - The object to freeze
* @param ignores - Properties to ignore during freezing
* @returns A frozen object
*/
function deepFreeze$2(obj, ignores = []) {
	if (obj === null || typeof obj !== "object") return obj;
	for (const key of Object.keys(obj)) {
		const value = obj[key];
		if (ignores.includes(key)) continue;
		if (typeof value === "object" && value !== null) deepFreeze$2(value, ignores);
	}
	return Object.freeze(obj);
}
//#endregion
//#region node_modules/.pnpm/gunshi@0.37.3/node_modules/gunshi/lib/context-CAPhwgJJ.js
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
const ANONYMOUS_COMMAND_NAME$1 = "(anonymous)";
/**
* A no-operation function.
*/
const NOOP$1 = () => {};
const CLI_OPTIONS_DEFAULT$1 = {
	name: void 0,
	description: void 0,
	version: void 0,
	cwd: void 0,
	usageSilent: false,
	subCommands: void 0,
	leftMargin: 2,
	middleMargin: 10,
	usageOptionType: false,
	usageOptionValue: true,
	strict: false,
	renderHeader: void 0,
	renderUsage: void 0,
	renderValidationErrors: void 0,
	plugins: void 0,
	fallbackToEntry: false
};
/**
* The entry for gunshi context.
* This module is exported for the purpose of testing the command.
*
* @example
* ```js
* import { createCommandContext } from 'gunshi/context'
* ```
*
* @module
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Create a command context.
*
* @param param - A {@link CommandContextParams | parameters} to create a command context.
* @returns A {@link CommandContext | command context}, which is readonly.
*/
async function createCommandContext$1({ args = {}, explicit = {}, values = {}, positionals = [], rest = [], argv = [], tokens = [], command = {}, extensions = {}, cliOptions = {}, callMode = "entry", commandPath = [], omitted = false, validationError }) {
	/**
	* normailize the options schema and values, to avoid prototype pollution
	*/
	const _args = Object.entries(args).reduce((acc, [key, value]) => {
		acc[key] = Object.assign(create$2(), value);
		return acc;
	}, create$2());
	/**
	* setup the environment
	*/
	const env = Object.assign(create$2(), CLI_OPTIONS_DEFAULT$1, cliOptions);
	/**
	* apply Command definition's rendering option with highest priority
	*/
	if (command.rendering) {
		const { header, usage, validationErrors } = command.rendering;
		if (header !== void 0) env.renderHeader = header;
		if (usage !== void 0) env.renderUsage = usage;
		if (validationErrors !== void 0) env.renderValidationErrors = validationErrors;
	}
	/**
	* create the command context
	*/
	const core = Object.assign(create$2(), {
		name: getCommandName$1(command),
		description: command.description,
		omitted,
		callMode,
		commandPath,
		env,
		args: _args,
		explicit,
		values,
		positionals,
		rest,
		_: argv,
		tokens,
		toKebab: command.toKebab,
		log: cliOptions.usageSilent ? NOOP$1 : log$1,
		validationError
	});
	/**
	* extend the command context with extensions
	*/
	if (Object.keys(extensions).length > 0) {
		const ext = create$2(null);
		Object.defineProperty(core, "extensions", {
			value: ext,
			writable: false,
			enumerable: true,
			configurable: true
		});
		for (const [key, extension] of Object.entries(extensions)) {
			ext[key] = await extension.factory(core, command);
			if (extension.onFactory) await extension.onFactory(core, command);
		}
	}
	return deepFreeze$2(core, ["extensions"]);
}
function getCommandName$1(cmd) {
	if (isLazyCommand$2(cmd)) return cmd.commandName || cmd.name || "(anonymous)";
	else if (typeof cmd === "object") return cmd.name || "(anonymous)";
	else return ANONYMOUS_COMMAND_NAME$1;
}
//#endregion
//#region node_modules/.pnpm/gunshi@0.37.3/node_modules/gunshi/lib/resolver-D5skgYcF.js
/**
* forked from `nodejs/node` (`pkgjs/parseargs`)
* repository url: https://github.com/nodejs/node (https://github.com/pkgjs/parseargs)
* code url: https://github.com/nodejs/node/blob/main/lib/internal/util/parse_args/parse_args.js
*
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
const HYPHEN_CHAR = "-";
const HYPHEN_CODE = HYPHEN_CHAR.codePointAt(0);
const EQUAL_CHAR = "=";
const EQUAL_CODE = EQUAL_CHAR.codePointAt(0);
const TERMINATOR$1 = "--";
const SHORT_OPTION_PREFIX = HYPHEN_CHAR;
const LONG_OPTION_PREFIX = "--";
/**
* Parse command line arguments.
*
* @param args - command line arguments
* @param options - parse options, about details see {@link ParserOptions}
* @returns Argument tokens.
*
* @example
* ```js
* import { parseArgs } from 'args-tokens' // for Node.js and Bun
* // import { parseArgs } from 'jsr:@kazupon/args-tokens' // for Deno
*
* const tokens = parseArgs(['--foo', 'bar', '-x', '--bar=baz'])
* // do something with using tokens
* // ...
* console.log('tokens:', tokens)
* ```
*/
function parseArgs(args, options = {}) {
	const { allowCompatible = false } = options;
	const tokens = [];
	const remainings = [...args];
	let index = -1;
	let groupCount = 0;
	let hasShortValueSeparator = false;
	while (remainings.length > 0) {
		const arg = remainings.shift();
		if (arg == void 0) break;
		const nextArg = remainings[0];
		if (groupCount > 0) groupCount--;
		else index++;
		if (arg === TERMINATOR$1) {
			tokens.push({
				kind: "option-terminator",
				index
			});
			const mapped = remainings.map((arg) => {
				return {
					kind: "positional",
					index: ++index,
					value: arg
				};
			});
			tokens.push(...mapped);
			break;
		}
		if (isShortOption(arg)) {
			const shortOption = arg.charAt(1);
			let value;
			let inlineValue;
			if (groupCount) {
				tokens.push({
					kind: "option",
					name: shortOption,
					rawName: arg,
					index,
					value,
					inlineValue
				});
				if (groupCount === 1 && hasOptionValue(nextArg)) {
					value = remainings.shift();
					if (hasShortValueSeparator) {
						inlineValue = true;
						hasShortValueSeparator = false;
					}
					tokens.push({
						kind: "option",
						index,
						value,
						inlineValue
					});
				}
			} else tokens.push({
				kind: "option",
				name: shortOption,
				rawName: arg,
				index,
				value,
				inlineValue
			});
			if (value != null) ++index;
			continue;
		}
		if (isShortOptionGroup(arg)) {
			const expanded = [];
			let shortValue = "";
			for (let i = 1; i < arg.length; i++) {
				const shortableOption = arg.charAt(i);
				if (hasShortValueSeparator) shortValue += shortableOption;
				else if (!allowCompatible && shortableOption.codePointAt(0) === EQUAL_CODE) hasShortValueSeparator = true;
				else expanded.push(`${SHORT_OPTION_PREFIX}${shortableOption}`);
			}
			if (shortValue) expanded.push(shortValue);
			remainings.unshift(...expanded);
			groupCount = expanded.length;
			continue;
		}
		if (isLongOption(arg)) {
			const longOption = arg.slice(2);
			tokens.push({
				kind: "option",
				name: longOption,
				rawName: arg,
				index,
				value: void 0,
				inlineValue: void 0
			});
			continue;
		}
		if (isLongOptionAndValue(arg)) {
			const equalIndex = arg.indexOf(EQUAL_CHAR);
			const longOption = arg.slice(2, equalIndex);
			const value = arg.slice(equalIndex + 1);
			tokens.push({
				kind: "option",
				name: longOption,
				rawName: `${LONG_OPTION_PREFIX}${longOption}`,
				index,
				value,
				inlineValue: true
			});
			continue;
		}
		tokens.push({
			kind: "positional",
			index,
			value: arg
		});
	}
	return tokens;
}
/**
* Check if `arg` is a short option (e.g. `-f`).
*
* @param arg - An argument to check
* @returns Whether `arg` is a short option.
*/
function isShortOption(arg) {
	return arg.length === 2 && arg.codePointAt(0) === HYPHEN_CODE && arg.codePointAt(1) !== HYPHEN_CODE;
}
/**
* Check if `arg` is a short option group (e.g. `-abc`).
*
* @param arg - An argument to check
* @returns Whether `arg` is a short option group.
*/
function isShortOptionGroup(arg) {
	if (arg.length <= 2) return false;
	if (arg.codePointAt(0) !== HYPHEN_CODE) return false;
	if (arg.codePointAt(1) === HYPHEN_CODE) return false;
	return true;
}
/**
* Check if `arg` is a long option (e.g. `--foo`).
*
* @param arg - An argument to check
* @returns Whether `arg` is a long option.
*/
function isLongOption(arg) {
	return hasLongOptionPrefix(arg) && !arg.includes(EQUAL_CHAR, 3);
}
/**
* Check if `arg` is a long option with value (e.g. `--foo=bar`).
*
* @param arg - An argument to check
* @returns Whether `arg` is a long option.
*/
function isLongOptionAndValue(arg) {
	return hasLongOptionPrefix(arg) && arg.includes(EQUAL_CHAR, 3);
}
/**
* Check if `arg` is a long option prefix (e.g. `--`).
*
* @param arg - An argument to check
* @returns Whether `arg` is a long option prefix.
*/
function hasLongOptionPrefix(arg) {
	return arg.startsWith(LONG_OPTION_PREFIX) && arg.length > 2;
}
/**
* Check if a `value` is an option value.
*
* @param value - A value to check
* @returns Whether a `value` is an option value.
*/
function hasOptionValue(value) {
	return !(value == null) && value.codePointAt(0) !== HYPHEN_CODE;
}
/**
* Entry point of argument options resolver.
*
* @module
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Machine-readable error codes for {@link ArgsValidationError}.
*
* Each code identifies a validation failure category and is also suitable as an
* i18n resource key for localized rendering.
*/
const ArgsValidationErrorKeys = {
	requiredOption: "err:arg:required-option",
	requiredPositional: "err:arg:required-positional",
	invalidType: "err:arg:invalid-type",
	invalidChoice: "err:arg:invalid-choice",
	customParse: "err:arg:custom-parse",
	unknownOption: "err:arg:unknown-option"
};
/**
* Brand that marks {@link ArgsValidationError} instances.
*
* The brand is looked up in the global symbol registry with `Symbol.for`, so it stays
* identical across bundled copies of this module and across realms. It lets
* {@link isArgsValidationError} recognize errors created by another copy of `args-tokens`,
* where `instanceof` cannot match.
*/
const ARGS_VALIDATION_ERROR_BRAND = Symbol.for("args-tokens.ArgsValidationError");
/**
* An error that contains structured metadata for argument validation failures.
*
* The `message` remains the English fallback message. Renderers can use `code`
* and `values` to localize the error, falling back to `message` when localization
* is unavailable.
*
* Each instance carries a non-enumerable brand keyed by
* `Symbol.for('args-tokens.ArgsValidationError')`, which {@link isArgsValidationError}
* uses to recognize instances created by another bundled copy of `args-tokens`.
*/
var ArgsValidationError = class extends Error {
	/**
	* Machine-readable error code for this validation failure.
	*
	* This code can also be used as an i18n resource key.
	*/
	code;
	/**
	* Interpolation values for `code`.
	*/
	values;
	/**
	* Create an `ArgsValidationError` instance.
	*
	* @param message - fallback error message
	* @param options - structured validation metadata
	*/
	constructor(message, options = {}) {
		super(message, { cause: options.cause });
		this.name = "ArgsValidationError";
		this.code = options.code;
		this.values = options.values ?? {};
		Object.defineProperty(this, ARGS_VALIDATION_ERROR_BRAND, {
			value: true,
			enumerable: false,
			writable: false,
			configurable: false
		});
	}
};
/**
* Check whether the given value is an {@link ArgsValidationError}.
*
* This guard also recognizes errors created by another bundled copy of `args-tokens`
* (0.29.0 or later), where `instanceof` does not match. Such an error must have an own brand
* keyed by `Symbol.for('args-tokens.ArgsValidationError')` set to `true`, and a `values` object.
* The guard does not rely on `error.name`, so subclasses such as {@link ArgResolveError} that
* override `name` are still recognized.
*
* The guard narrows to `ArgsValidationError` only. Across bundled copies,
* `instanceof ArgResolveError` still does not match.
*
* @param error - value to check
* @returns `true` when the value is an `ArgsValidationError`
*/
function isArgsValidationError$1(error) {
	if (error instanceof ArgsValidationError) return true;
	if (typeof error !== "object" || error === null) return false;
	if (!Object.hasOwn(error, ARGS_VALIDATION_ERROR_BRAND) || error[ARGS_VALIDATION_ERROR_BRAND] !== true) return false;
	const values = error.values;
	return typeof values === "object" && values !== null;
}
const SKIP_POSITIONAL_DEFAULT = -1;
/**
* Resolve command line arguments.
*
* @typeParam A - {@link Args | Arguments}, which is an object that defines the command line arguments.
*
* @param args - An arguments that contains {@link ArgSchema | arguments schema}.
* @param tokens - An array of {@link ArgToken | tokens}.
* @param resolveArgs - An arguments that contains {@link ResolveArgs | resolve arguments}.
* @returns An object that contains the values of the arguments, positional arguments, rest arguments, {@link AggregateError | validation errors}, and explicit provision status.
*
* @example
* ```typescript
* // passed tokens: --port 3000
*
* const { values, explicit } = resolveArgs({
*   port: {
*     type: 'number',
*     default: 8080
*   },
*   host: {
*     type: 'string',
*     default: 'localhost'
*   }
* }, parsedTokens)
*
* values.port // 3000
* values.host // 'localhost'
*
* explicit.port // true (explicitly provided)
* explicit.host // false (not provided, fallback to default)
* ```
*/
function resolveArgs(args, tokens, { shortGrouping = false, skipPositional = SKIP_POSITIONAL_DEFAULT, toKebab = false } = {}) {
	const skipPositionalIndex = typeof skipPositional === "number" ? Math.max(skipPositional, SKIP_POSITIONAL_DEFAULT) : SKIP_POSITIONAL_DEFAULT;
	const rest = [];
	const optionTokens = [];
	const positionalTokens = [];
	const argEntries = Object.entries(args);
	let currentLongOption;
	let currentShortOption;
	const expandableShortOptions = [];
	function getOptionName(rawArg, schema) {
		return toKebab || schema.toKebab ? kebabnize$1(rawArg) : rawArg;
	}
	function checkLongTokenName(option, schema, token) {
		if (token.rawName == void 0 || !hasLongOptionPrefix(token.rawName)) return false;
		return token.name === option || schema.type === "boolean" && schema.negatable === true && token.name === `no-${option}`;
	}
	function toShortValue() {
		if (expandableShortOptions.length === 0) return;
		else {
			const value = expandableShortOptions.map((token) => token.name).join("");
			expandableShortOptions.length = 0;
			return value;
		}
	}
	function applyLongOptionValue(value) {
		if (currentLongOption) {
			currentLongOption.value = value;
			optionTokens.push({ ...currentLongOption });
			currentLongOption = void 0;
		}
	}
	function applyShortOptionValue(value) {
		if (currentShortOption) {
			currentShortOption.value = value || toShortValue();
			optionTokens.push({ ...currentShortOption });
			currentShortOption = void 0;
		}
	}
	/**
	* analyze phase to resolve value
	* separate tokens into positionals, long and short options, after that resolve values
	*/
	const schemas = Object.values(args);
	const booleanLongOptionNames = /* @__PURE__ */ new Set();
	for (const [rawArg, schema] of Object.entries(args)) {
		if (schema.type !== "boolean") continue;
		const arg = toKebab || schema.toKebab ? kebabnize$1(rawArg) : rawArg;
		booleanLongOptionNames.add(arg);
		if (schema.negatable === true) booleanLongOptionNames.add(`no-${arg}`);
	}
	let terminated = false;
	for (let i = 0; i < tokens.length; i++) {
		const token = tokens[i];
		if (token.kind === "positional") {
			if (terminated && token.value) {
				rest.push(token.value);
				continue;
			}
			if (currentShortOption) {
				if (schemas.find((schema) => schema.short === currentShortOption.name && schema.type === "boolean")) {
					positionalTokens.push({ ...token });
					applyShortOptionValue();
				} else applyShortOptionValue(token.value);
			} else if (currentLongOption) {
				if (booleanLongOptionNames.has(currentLongOption.name)) {
					positionalTokens.push({ ...token });
					applyLongOptionValue();
				} else applyLongOptionValue(token.value);
			} else positionalTokens.push({ ...token });
		} else if (token.kind === "option") {
			if (token.rawName) {
				if (hasLongOptionPrefix(token.rawName)) {
					applyLongOptionValue();
					if (token.inlineValue) optionTokens.push({ ...token });
					else currentLongOption = { ...token };
					applyShortOptionValue();
				} else if (isShortOption(token.rawName)) {
					if (currentShortOption) {
						if (currentShortOption.index === token.index) {
							if (shortGrouping) {
								currentShortOption.value = token.value;
								optionTokens.push({ ...currentShortOption });
								currentShortOption = { ...token };
							} else expandableShortOptions.push({ ...token });
						} else {
							currentShortOption.value = toShortValue();
							optionTokens.push({ ...currentShortOption });
							currentShortOption = { ...token };
						}
						applyLongOptionValue();
					} else {
						currentShortOption = { ...token };
						applyLongOptionValue();
					}
				}
			} else {
				if (currentShortOption && currentShortOption.index == token.index && token.inlineValue) {
					currentShortOption.value = token.value;
					optionTokens.push({ ...currentShortOption });
					currentShortOption = void 0;
				}
				applyLongOptionValue();
			}
		} else {
			if (token.kind === "option-terminator") terminated = true;
			applyLongOptionValue();
			applyShortOptionValue();
		}
	}
	/**
	* check if the last long or short option is not resolved
	*/
	applyLongOptionValue();
	applyShortOptionValue();
	/**
	* resolve values
	*/
	const values = Object.create(null);
	const errors = [];
	const explicit = Object.create(null);
	const actualInputNames = /* @__PURE__ */ new Map();
	let requiredPositionalsAfter;
	const positionalItemCount = tokens.filter((token) => token.kind === "positional").length;
	function getPositionalSkipIndex() {
		return Math.min(skipPositionalIndex, positionalItemCount);
	}
	function getRequiredPositionalsAfter(rawArg) {
		requiredPositionalsAfter ??= createRequiredPositionalsAfter(argEntries);
		return requiredPositionalsAfter[rawArg] ?? 0;
	}
	let positionalsCount = 0;
	for (const [rawArg, schema] of argEntries) {
		const arg = getOptionName(rawArg, schema);
		explicit[rawArg] = false;
		if (schema.type === "positional") {
			if (skipPositionalIndex > SKIP_POSITIONAL_DEFAULT) while (positionalsCount <= getPositionalSkipIndex()) positionalsCount++;
			if (schema.multiple) {
				const availablePositionals = Math.max(positionalTokens.length - positionalsCount, 0);
				if (availablePositionals > 0) {
					const requiredPositionals = getRequiredPositionalsAfter(rawArg);
					const positionalsToConsume = Math.max(availablePositionals - requiredPositionals, 0);
					if (positionalsToConsume > 0) {
						const endPositionals = positionalsCount + positionalsToConsume;
						if (typeof schema.parse === "function") {
							const parsed = [];
							for (let i = positionalsCount; i < endPositionals; i++) {
								const p = positionalTokens[i];
								const [parsedValue, error] = parseSchemaValue(p.value, rawArg, arg, schema);
								if (error) errors.push(error);
								else parsed.push(parsedValue);
							}
							values[rawArg] = parsed;
						} else {
							const valuesArray = [];
							for (let i = positionalsCount; i < endPositionals; i++) valuesArray.push(positionalTokens[i].value);
							values[rawArg] = valuesArray;
						}
						positionalsCount = endPositionals;
						explicit[rawArg] = true;
					} else if (schema.required) errors.push(createRequireError(rawArg, arg, schema));
				} else if (schema.required) errors.push(createRequireError(rawArg, arg, schema));
			} else {
				const positional = positionalTokens[positionalsCount];
				if (shouldRequireMissingSinglePositional(schema)) {
					if (positional != null) {
						resolveSinglePositionalValue(values, errors, rawArg, arg, schema, positional);
						explicit[rawArg] = true;
						positionalsCount++;
					} else errors.push(createRequireError(rawArg, arg, schema));
					continue;
				}
				if (positional != null) {
					const requiredPositionals = getRequiredPositionalsAfter(rawArg);
					if (Math.max(positionalTokens.length - positionalsCount, 0) > requiredPositionals) {
						resolveSinglePositionalValue(values, errors, rawArg, arg, schema, positional);
						explicit[rawArg] = true;
						positionalsCount++;
						continue;
					}
				}
				if (hasDefault(schema)) values[rawArg] = schema.default;
			}
			continue;
		}
		if (schema.required) {
			if (!optionTokens.find((token) => {
				return schema.short && token.name === schema.short && token.rawName != void 0 && isShortOption(token.rawName) || checkLongTokenName(arg, schema, token);
			})) {
				errors.push(createRequireError(rawArg, arg, schema));
				continue;
			}
		}
		for (let i = 0; i < optionTokens.length; i++) {
			const token = optionTokens[i];
			if (checkLongTokenName(arg, schema, token) || schema.short === token.name && token.rawName != void 0 && isShortOption(token.rawName)) {
				const invalid = validateRequire(token, rawArg, arg, schema);
				if (invalid) {
					errors.push(invalid);
					continue;
				}
				explicit[rawArg] = true;
				const rawName = token.rawName;
				const actualInputName = isShortOption(rawName) ? `-${token.name}` : rawName;
				actualInputNames.set(rawArg, actualInputName);
				const [parsedValue, error] = parse(token, rawArg, arg, schema);
				if (error) errors.push(error);
				else if (schema.multiple) {
					values[rawArg] ||= [];
					values[rawArg].push(parsedValue);
				} else values[rawArg] = parsedValue;
			}
		}
		if (values[rawArg] == null && schema.default != null) values[rawArg] = schema.default;
	}
	const conflictErrors = checkConflicts(args, explicit, toKebab, actualInputNames);
	errors.push(...conflictErrors);
	return {
		values,
		positionals: positionalTokens.map((token) => token.value),
		rest,
		error: errors.length > 0 ? new AggregateError(errors) : void 0,
		explicit
	};
}
function parse(token, rawArg, option, schema) {
	if (typeof schema.parse === "function") {
		if (schema.type === "boolean") {
			const boolValue = !(schema.negatable && token.name.startsWith("no-"));
			return parseSchemaValue(String(boolValue), rawArg, option, schema);
		}
		return parseSchemaValue(token.value ?? String(schema.default ?? ""), rawArg, option, schema);
	}
	switch (schema.type) {
		case "string": return typeof token.value === "string" ? [token.value || schema.default, void 0] : [void 0, createTypeError(rawArg, option, schema, token.value)];
		case "boolean": return [!(schema.negatable && token.name.startsWith("no-")), void 0];
		case "number":
			if (!isNumeric(token.value)) return [void 0, createTypeError(rawArg, option, schema, token.value)];
			return token.value ? [+token.value, void 0] : [+(schema.default || ""), void 0];
		case "enum":
			if (schema.choices && !schema.choices.includes(token.value)) return [void 0, createChoiceError(rawArg, option, schema, token.value)];
			return [token.value || schema.default, void 0];
		case "custom": throw new TypeError(`argument '${option}' should have a 'parse' function`);
		default: throw new Error(`Unsupported argument type '${schema.type}' for option '${option}'`);
	}
}
function parseSchemaValue(value, rawArg, option, schema) {
	try {
		return [schema.parse(value), void 0];
	} catch (error) {
		return [void 0, createCustomParseError(error, rawArg, option, schema, value)];
	}
}
function createRequireError(rawArg, option, schema) {
	return new ArgResolveError(schema.type === "positional" ? `Positional argument '${option}' is required` : `Optional argument ${createOptionDisplayName(option, schema)} is required`, option, "required", schema, {
		code: schema.type === "positional" ? ArgsValidationErrorKeys.requiredPositional : ArgsValidationErrorKeys.requiredOption,
		values: schema.type === "positional" ? { name: rawArg } : {
			displayName: createOptionDisplayName(option, schema),
			name: rawArg
		}
	});
}
function resolveSinglePositionalValue(values, errors, rawArg, option, schema, positional) {
	if (typeof schema.parse === "function") {
		const [parsedValue, error] = parseSchemaValue(positional.value, rawArg, option, schema);
		if (error) errors.push(error);
		else values[rawArg] = parsedValue;
	} else values[rawArg] = positional.value;
}
function hasDefault(schema) {
	return schema.default != null;
}
function shouldRequireMissingSinglePositional(schema) {
	if (schema.required === true) return true;
	if (schema.required === false) return false;
	return !hasDefault(schema);
}
function getRequiredPositionalInputCount(schema) {
	if (schema.type !== "positional") return 0;
	if (schema.multiple) return schema.required === true ? 1 : 0;
	return shouldRequireMissingSinglePositional(schema) ? 1 : 0;
}
function createRequiredPositionalsAfter(argEntries) {
	const requiredPositionalsAfter = Object.create(null);
	let minimumRequiredPositionals = 0;
	for (let i = argEntries.length - 1; i >= 0; i--) {
		const [rawArg, schema] = argEntries[i];
		if (schema.type !== "positional") continue;
		requiredPositionalsAfter[rawArg] = minimumRequiredPositionals;
		minimumRequiredPositionals += getRequiredPositionalInputCount(schema);
	}
	return requiredPositionalsAfter;
}
/**
* An error that occurs when resolving arguments.
* This error is thrown when the argument is not valid.
*/
var ArgResolveError = class extends ArgsValidationError {
	name;
	schema;
	type;
	/**
	* Create an `ArgResolveError` instance.
	*
	* @param message - the error message
	* @param name - the name of the argument
	* @param type - the type of the error: 'type', 'required', or 'conflict'
	* @param schema - the argument schema that caused the error
	* @param options - structured validation metadata
	*/
	constructor(message, name, type, schema, options = {}) {
		super(message, options);
		this.name = name;
		this.type = type;
		this.schema = schema;
	}
};
function validateRequire(token, rawArg, option, schema) {
	if (schema.required && schema.type !== "boolean" && !token.value) return createRequireError(rawArg, option, schema);
}
function isNumeric(str) {
	return str.trim() !== "" && !isNaN(str);
}
function createTypeError(rawArg, option, schema, actual) {
	return new ArgResolveError(`Optional argument ${createOptionDisplayName(option, schema)} should be '${schema.type}'`, option, "type", schema, {
		code: ArgsValidationErrorKeys.invalidType,
		values: {
			displayName: createOptionDisplayName(option, schema),
			name: rawArg,
			expected: schema.type,
			...actual != null ? { actual } : {}
		}
	});
}
function createChoiceError(rawArg, option, schema, actual) {
	const choices = schema.choices ?? [];
	return new ArgResolveError(`Optional argument ${createOptionDisplayName(option, schema)} should be chosen from '${schema.type}' [${formatChoices(choices)}] values`, option, "type", schema, {
		code: ArgsValidationErrorKeys.invalidChoice,
		values: {
			displayName: createOptionDisplayName(option, schema),
			name: rawArg,
			expected: schema.type,
			choices: formatChoices(choices),
			choiceValues: [...choices],
			...actual != null ? { actual } : {}
		}
	});
}
function createCustomParseError(error, rawArg, option, schema, value) {
	const reused = reuseValidationError(error, rawArg, option, schema, value);
	if (reused) return reused;
	const reason = getErrorReason(error);
	return new ArgsValidationError(reason, {
		code: ArgsValidationErrorKeys.customParse,
		values: {
			displayName: createArgumentDisplayName(option, schema),
			name: rawArg,
			reason
		},
		cause: error
	});
}
/**
* Reuse an {@link ArgsValidationError} thrown from a custom `parse` function, filling in missing values.
*
* @param error - The value thrown from `parse`
* @param rawArg - The argument key in the schema
* @param option - The option name used on the command line
* @param schema - The argument schema
* @param value - The raw input value
* @returns The same error when it can be reused, otherwise `undefined` so the caller wraps it.
* Inspecting or updating the thrown value can throw, for example when its `values` object is frozen
* or an accessor throws; such values are not reused, so a custom `parse` cannot make `resolveArgs` throw this way.
*/
function reuseValidationError(error, rawArg, option, schema, value) {
	try {
		if (isArgsValidationError$1(error)) {
			augmentValidationError(error, rawArg, option, schema, value);
			return error;
		}
	} catch {}
}
function augmentValidationError(error, rawArg, option, schema, value) {
	const values = error.values;
	values.name ??= rawArg;
	values.displayName ??= createArgumentDisplayName(option, schema);
	if ((error.code === ArgsValidationErrorKeys.invalidType || error.code === ArgsValidationErrorKeys.invalidChoice) && values.actual == null) values.actual = value;
}
function getErrorReason(error) {
	return error instanceof Error ? error.message : String(error);
}
function createArgumentDisplayName(option, schema) {
	return schema.type === "positional" ? `'${option}'` : createOptionDisplayName(option, schema);
}
function createOptionDisplayName(option, schema) {
	return `'--${option}'${schema.short ? ` or '-${schema.short}'` : ""}`;
}
function checkConflicts(args, explicit, toKebab, actualInputNames) {
	for (const rawArg in args) {
		const schema = args[rawArg];
		if (!explicit[rawArg]) continue;
		if (!schema.conflicts) continue;
		const conflicts = Array.isArray(schema.conflicts) ? schema.conflicts : [schema.conflicts];
		for (let i = 0; i < conflicts.length; i++) {
			const conflictingArg = conflicts[i];
			if (!explicit[conflictingArg]) continue;
			const arg = toKebab || schema.toKebab ? kebabnize$1(rawArg) : rawArg;
			const conflictingArgKebab = toKebab || args[conflictingArg]?.toKebab ? kebabnize$1(conflictingArg) : conflictingArg;
			return [new ArgResolveError(`Optional argument '${actualInputNames.get(rawArg) || `--${arg}`}' conflicts with '${actualInputNames.get(conflictingArg) || `--${conflictingArgKebab}`}'`, rawArg, "conflict", schema)];
		}
	}
	return [];
}
//#endregion
//#region node_modules/.pnpm/gunshi@0.37.3/node_modules/gunshi/lib/error-B5QxSzk9.js
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Command not found error resource keys.
*/
const CommandNotFoundErrorKeys = { notFound: "err:cmd:not-found" };
/**
* Brand that marks {@link CommandNotFoundError} instances.
*
* The brand is looked up in the global symbol registry with `Symbol.for`, so it stays
* identical across bundled copies of gunshi (`gunshi`, `@gunshi/plugin`, `@gunshi/bone`)
* and across realms. It lets {@link isCommandNotFoundError} recognize errors created by
* another copy, where `instanceof` cannot match.
*/
const COMMAND_NOT_FOUND_ERROR_BRAND = Symbol.for("gunshi.CommandNotFoundError");
/**
* Error raised when a command cannot be resolved.
*
* Each instance carries a non-enumerable brand keyed by
* `Symbol.for('gunshi.CommandNotFoundError')`, so that {@link isCommandNotFoundError}
* recognizes it even when it was created by another bundled copy of gunshi.
*/
var CommandNotFoundError = class extends Error {
	code;
	values;
	commandName;
	candidates;
	commandPath;
	/**
	* Create a command-not-found error.
	*
	* @param message - Fallback error message
	* @param options - Command-not-found metadata
	*/
	constructor(message, options) {
		super(message, { cause: options.cause });
		this.name = "CommandNotFoundError";
		this.code = options.code;
		this.values = options.values || {};
		this.commandName = options.commandName;
		this.candidates = options.candidates || [];
		this.commandPath = options.commandPath || [];
		Object.defineProperty(this, COMMAND_NOT_FOUND_ERROR_BRAND, {
			value: true,
			enumerable: false,
			writable: false,
			configurable: false
		});
	}
};
/**
* Check whether an error is a {@link CommandNotFoundError}.
*
* `instanceof` alone is not enough: `@gunshi/plugin` is bundled with its own copy of this
* class (`noExternal: ['gunshi/plugin']`), so an error thrown by `gunshi` is never an instance
* of the class a plugin imports. Errors from another copy are recognized through the
* `Symbol.for('gunshi.CommandNotFoundError')` brand, which does not depend on `error.name`.
*
* @param error - An unknown error
* @returns `true` if the error is a {@link CommandNotFoundError}
*/
function isCommandNotFoundError(error) {
	if (error instanceof CommandNotFoundError) return true;
	if (!isRecord(error) || !hasCommandNotFoundErrorShape(error)) return false;
	if (Object.hasOwn(error, COMMAND_NOT_FOUND_ERROR_BRAND) && error[COMMAND_NOT_FOUND_ERROR_BRAND] === true) return true;
	return error instanceof Error && error.name === "CommandNotFoundError";
}
/**
* Check whether an error is an {@link ArgsValidationError}.
*
* Prefer this over the `args-tokens` guard of the same name. Both recognize errors from another
* bundled copy through the `Symbol.for('args-tokens.ArgsValidationError')` brand that
* `args-tokens` 0.29.0 or later sets, including subclasses such as `ArgResolveError` that
* override `name` with the argument name. This guard additionally:
*
* - recognizes direct `ArgsValidationError` instances from copies bundling `args-tokens`
*   older than 0.29.0, which do not set the brand
* - checks that `code` and `values` of an error from another copy have the expected types
*
* The guard narrows only to {@link ArgsValidationError}: across copies,
* `instanceof ArgResolveError` still fails, so do not rely on `type` or `schema` for such errors.
*
* @param error - An unknown error
* @returns `true` if the error is an {@link ArgsValidationError}
*/
function isArgsValidationError(error) {
	if (error instanceof ArgsValidationError) return true;
	if (!isRecord(error) || !hasArgsValidationErrorShape(error)) return false;
	if (isArgsValidationError$1(error)) return true;
	return error instanceof Error && error.name === "ArgsValidationError";
}
function isRecord(value) {
	return typeof value === "object" && value !== null;
}
function isStringArray(value) {
	return Array.isArray(value) && value.every((item) => typeof item === "string");
}
/**
* Check whether `code` is an own or inherited property that is a string or `undefined`.
*
* Constructors always assign `code`, even when the option is omitted.
*
* @param error - An error from another copy
* @returns `true` if `code` has the expected type
*/
function hasOptionalStringCode(error) {
	return "code" in error && (error.code === void 0 || typeof error.code === "string");
}
function hasCommandNotFoundErrorShape(error) {
	return hasOptionalStringCode(error) && isRecord(error.values) && typeof error.commandName === "string" && isStringArray(error.candidates) && isStringArray(error.commandPath);
}
function hasArgsValidationErrorShape(error) {
	return hasOptionalStringCode(error) && isRecord(error.values);
}
/**
* Check whether validation errors should be handled before version, help, or command execution.
*
* @param error - An aggregate validation error
* @returns `true` if the validation error must be handled with priority
*/
function hasPriorityValidationError(error) {
	return error?.errors.some((error) => isCommandNotFoundError(error) || isArgsValidationError(error) && error.code === ArgsValidationErrorKeys.unknownOption) ?? false;
}
//#endregion
//#region node_modules/.pnpm/gunshi@0.37.3/node_modules/gunshi/lib/plugin-DneW3Toi.js
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
const NOOP_EXTENSION$1 = () => {
	return Object.create(null);
};
/**
* Define a plugin
*
* @param options - {@linkcode PluginOptions | plugin options}
* @returns A defined plugin
*
* @since v0.27.0
*/
function plugin$1(options = {}) {
	const { id, name, setup, onExtension, dependencies } = options;
	const extension = options.extension || NOOP_EXTENSION$1;
	const pluginFn = async (ctx) => {
		if (setup) await setup(ctx);
	};
	const props = {
		writable: false,
		enumerable: true,
		configurable: true
	};
	return Object.defineProperties(pluginFn, {
		id: {
			value: id,
			...props
		},
		...name && { name: {
			value: name,
			...props
		} },
		...dependencies && { dependencies: {
			value: dependencies,
			...props
		} },
		...extension && { extension: {
			value: {
				key: Symbol(id),
				factory: extension,
				onFactory: onExtension
			},
			...props
		} }
	});
}
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
//#endregion
//#region node_modules/.pnpm/gunshi@0.37.3/node_modules/gunshi/lib/src-80_afJQM.js
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
const BUILD_IN_PREFIX_AND_KEY_SEPARATOR$1 = `_:`;
const ARG_PREFIX_AND_KEY_SEPARATOR$1 = `arg:`;
const ERROR_PREFIX_AND_KEY_SEPARATOR$1 = `err:`;
const COMMON_ARGS = {
	help: {
		type: "boolean",
		short: "h",
		description: "Display this help message"
	},
	version: {
		type: "boolean",
		short: "v",
		description: "Display this version"
	}
};
var en_US_default$1 = {
	COMMAND: "COMMAND",
	COMMANDS: "COMMANDS",
	SUBCOMMAND: "SUBCOMMAND",
	USAGE: "USAGE",
	ARGUMENTS: "ARGUMENTS",
	OPTIONS: "OPTIONS",
	EXAMPLES: "EXAMPLES",
	FORMORE: "For more info, run any command with the `--help` flag",
	NEGATABLE: "Negatable of",
	DEFAULT: "default",
	CHOICES: "choices",
	help: "Display this help message",
	version: "Display this version",
	"err:arg:required-option": "Optional argument {$displayName} is required",
	"err:arg:required-positional": "Positional argument {$name} is required",
	"err:arg:invalid-type": "Invalid value for {$displayName}: expected {$expected}",
	"err:arg:invalid-choice": "Invalid value for {$displayName}: expected one of {$choices}",
	"err:arg:custom-parse": "Invalid value for {$displayName}: {$reason}",
	"err:arg:unknown-option": "Unknown option: {$rawName}",
	"err:cmd:not-found": "Command not found: {$commandName}",
	"err:suggestion:did-you-mean": "Did you mean {$name}?"
};
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Resolve a namespaced key for built-in resources.
*
* Built-in keys are prefixed with "_:".
*
* @typeParam K - The type of the built-in key to resolve. Defaults to command built-in argument and resource keys.
*
* @param key - The built-in key to resolve.
* @returns Prefixed built-in key.
*/
function resolveBuiltInKey(key) {
	return `_:${key}`;
}
/**
* Resolve a namespaced key for argument resources.
*
* Argument keys are prefixed with "arg:".
* If the command name is provided, it will be prefixed with the command name (e.g. "cmd1:arg:foo").
*
* @typeParam A - The {@linkcode Args} type extracted from G
*
* @param key - The argument key to resolve.
* @param name - The command name.
* @returns Prefixed argument key.
*/
function resolveArgKey$1(key, name) {
	return `${name ? `${name}:` : ""}arg:${key}`;
}
/**
* Resolve a namespaced key for non-built-in resources.
*
* Non-built-in keys are not prefixed with any special characters. If the command name is provided, it will be prefixed with the command name (e.g. "cmd1:foo").
*
* @typeParam T - The type of the non-built-in key to resolve. Defaults to string.
*
* @param key - The non-built-in key to resolve.
* @param name - The command name.
* @returns Prefixed non-built-in key.
*/
function resolveKey$1(key, name) {
	return `${name ? `${name}:` : ""}${key}`;
}
/**
* Resolve command examples.
*
* @typeParam G - Type parameter extending {@linkcode GunshiParams}
*
* @param ctx - A {@linkcode CommandContext | command context}.
* @param examples - The examples to resolve, which can be a string or a {@linkcode CommandExamplesFetcher | function} that returns a string.
* @returns A resolved string of examples.
*/
async function resolveExamples$1(ctx, examples) {
	return typeof examples === "string" ? examples : typeof examples === "function" ? await examples(ctx) : "";
}
/**
* Generate a namespaced key for a plugin.
*
* @typeParam K - The type of the plugin id to generate a namespaced key for.
*
* @param id - A plugin id to generate a namespaced key.
* @returns A namespaced key for the plugin.
*/
function namespacedId$1(id) {
	return `g:${id}`;
}
/**
* Generate a short and long option pair for command arguments.
*
* @param schema - The {@linkcode ArgSchema | argument schema} to generate the option pair.
* @param name - The name of the argument.
* @param toKebab - Whether to convert the name to kebab-case for display in help text.
* @returns A string representing the short and long option pair.
*/
function makeShortLongOptionPair$1(schema, name, toKebab) {
	let key = `--${toKebab || schema.toKebab ? kebabnize$1(name) : name}`;
	if (schema.short) key = `-${schema.short}, ${key}`;
	return key;
}
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Create a localizable function for a command.
*
* This function will resolve the translation key based on the command context and the provided translation function.
*
* @typeParam A - The {@linkcode Args} type extracted from Gunshi command.
* @typeParam C - Additional context type for command localization.
* @typeParam E - Extended resource keys type.
*
* @param ctx - Command context
* @param cmd - Command
* @param translate - Translation function
* @returns Localizable function
*/
function localizable$1(ctx, cmd, translate) {
	async function localize(key, values) {
		if (translate) return translate(key, values);
		if (key.startsWith(BUILD_IN_PREFIX_AND_KEY_SEPARATOR$1)) return resolveAndFormatResource$1(key.slice(BUILD_IN_PREFIX_AND_KEY_SEPARATOR$1.length), key, values);
		if (key.startsWith(ERROR_PREFIX_AND_KEY_SEPARATOR$1)) return resolveAndFormatResource$1(key, key, values);
		const namaspacedArgKey = resolveKey$1(ARG_PREFIX_AND_KEY_SEPARATOR$1, ctx.name);
		if (key.startsWith(namaspacedArgKey)) {
			let argKey = key.slice(namaspacedArgKey.length);
			let negatable = false;
			if (argKey.startsWith("no-")) {
				argKey = argKey.slice(3);
				negatable = true;
			}
			const schema = ctx.args[argKey];
			if (!schema) return argKey;
			return negatable && schema.type === "boolean" && schema.negatable ? `${en_US_default$1["NEGATABLE"]} ${makeShortLongOptionPair$1(schema, argKey, ctx.toKebab)}` : schema.description || "";
		}
		if (key === resolveKey$1("description", ctx.name)) return "";
		else if (key === resolveKey$1("examples", ctx.name)) return await resolveExamples$1(ctx, cmd.examples);
		else return key;
	}
	return localize;
}
function resolveAndFormatResource$1(resourceKey, fallbackKey, values) {
	return formatResource$1(en_US_default$1[resourceKey], values) || fallbackKey;
}
/**
* Format a resource message by replacing placeholder values.
*
* @param resource - Resource message template
* @param values - Placeholder values
* @returns Formatted resource message
*/
function formatResource$1(resource, values = Object.create(null)) {
	return resource?.replaceAll(/\{\$(\w+)\}/g, (_, name) => {
		return values[name] == null ? "" : String(values[name]);
	});
}
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Render the header.
*
* @param ctx - A {@link CommandContext | command context}
* @returns A rendered header.
*/
function renderHeader(ctx) {
	const title = ctx.env.description || ctx.env.name || "";
	return Promise.resolve(title ? `${title} (${ctx.env.name || ""}${ctx.env.version ? ` v${ctx.env.version}` : ""})` : title);
}
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* The unique identifier for usage renderer plugin.
*/
const pluginId$2 = namespacedId$1("renderer");
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
const COMMON_ARGS_KEYS = Object.keys(COMMON_ARGS);
function isHiddenArg(schema) {
	return schema.hidden === true;
}
function getVisibleOptionalArgs(args) {
	return Object.entries(args).filter(([_, schema]) => schema.type !== "positional" && !isHiddenArg(schema));
}
function getVisiblePositionalArgs(args) {
	return Object.entries(args).filter(([_, schema]) => schema.type === "positional" && !isHiddenArg(schema));
}
/**
* Render the usage.
*
* @param ctx - A {@link CommandContext | command context}
* @returns A rendered usage.
*/
async function renderUsage(ctx) {
	const messages = [];
	if (ctx.callMode === "subCommand") {
		const description = await resolveDescription(ctx);
		if (description) messages.push(description, "");
	}
	messages.push(...await renderUsageSection(ctx), "");
	if (ctx.omitted && await hasCommands(ctx)) messages.push(...await renderCommandsSection(ctx), "");
	if (hasPositionalArgs(ctx.args)) messages.push(...await renderPositionalArgsSection(ctx), "");
	if (hasOptionalArgs(ctx.args)) messages.push(...await renderOptionalArgsSection(ctx), "");
	const examples = await renderExamplesSection(ctx);
	if (examples.length > 0) messages.push(...examples, "");
	return messages.join("\n");
}
/**
* Render the positional arguments section
*
* @param ctx - A {@link CommandContext | command context}
* @returns A rendered arguments section
*/
async function renderPositionalArgsSection(ctx) {
	const messages = [];
	messages.push(`${await ctx.extensions[pluginId$2].text(resolveBuiltInKey("ARGUMENTS"))}:`);
	messages.push(await generatePositionalArgsUsage(ctx));
	return messages;
}
/**
* Render the optional arguments section
*
* @param ctx - A {@link CommandContext | command context}
* @returns A rendered options section
*/
async function renderOptionalArgsSection(ctx) {
	const messages = [];
	messages.push(`${await ctx.extensions[pluginId$2].text(resolveBuiltInKey("OPTIONS"))}:`);
	messages.push(await generateOptionalArgsUsage(ctx, getOptionalArgsPairs(ctx)));
	return messages;
}
/**
* Render the examples section
*
* @param ctx - A {@link CommandContext | command context}
* @returns A rendered examples section
*/
async function renderExamplesSection(ctx) {
	const messages = [];
	const resolvedExamples = await resolveExamples$2(ctx);
	if (resolvedExamples) {
		const examples = resolvedExamples.split("\n").map((example) => example.padStart(ctx.env.leftMargin + example.length));
		messages.push(`${await ctx.extensions[pluginId$2].text(resolveBuiltInKey("EXAMPLES"))}:`, ...examples);
	}
	return messages;
}
/**
* Render the usage section
*
* @param ctx - A {@link CommandContext | command context}
* @returns A rendered usage section
*/
async function renderUsageSection(ctx) {
	const messages = [`${await ctx.extensions[pluginId$2].text(resolveBuiltInKey("USAGE"))}:`];
	const usageStr = await makeUsageSymbols(ctx);
	messages.push(usageStr.padStart(ctx.env.leftMargin + usageStr.length));
	return messages;
}
async function makeUsageSymbols(ctx) {
	const messages = [await resolveEntry(ctx)];
	if (ctx.omitted) {
		if (await hasCommands(ctx)) messages.push(` [${await ctx.extensions[pluginId$2].text(resolveBuiltInKey("COMMANDS"))}]`);
		else messages.push(`${ctx.callMode === "subCommand" ? ` ${await resolveSubCommand(ctx)}` : ""}`);
	} else messages.push(`${ctx.callMode === "subCommand" ? ` ${await resolveSubCommand(ctx)}` : ""}`);
	const optionsSymbols = await generateOptionsSymbols(ctx, ctx.args);
	if (optionsSymbols) messages.push(" ", optionsSymbols);
	const positionalSymbols = generatePositionalSymbols(ctx.args);
	if (positionalSymbols) messages.push(" ", positionalSymbols);
	return messages.join("");
}
/**
* Render the commands section
*
* @param ctx - A {@link CommandContext | command context}
* @returns A rendered commands section
*/
async function renderCommandsSection(ctx) {
	const messages = [`${await ctx.extensions[pluginId$2].text(resolveBuiltInKey("COMMANDS"))}:`];
	const loadedCommands = await ctx.extensions?.[pluginId$2].loadCommands() || [];
	const commandMaxLength = Math.max(...loadedCommands.map((cmd) => (cmd.name || "").length));
	const commandsStr = await Promise.all(loadedCommands.map(async (cmd) => {
		const desc = cmd.description || "";
		const optionSymbol = await generateOptionsSymbols(ctx, ctx.args);
		const positionalSymbol = generatePositionalSymbols(ctx.args);
		const commandStr = await makeCommandSymbol(ctx, cmd);
		const symbolLength = desc.length > 0 ? commandMaxLength + optionSymbol.length + positionalSymbol.length : 0;
		const command = `${commandStr.padEnd(symbolLength + ctx.env.middleMargin)}${desc}`;
		return `${command.padStart(ctx.env.leftMargin + command.length)}`;
	}));
	messages.push(...commandsStr, "", `${await ctx.extensions[pluginId$2].text(resolveBuiltInKey("FORMORE"))}:`);
	const basePath = ctx.commandPath && ctx.commandPath.length > 0 ? `${ctx.env.name} ${ctx.commandPath.join(" ")}` : ctx.env.name;
	messages.push(...loadedCommands.map((cmd) => {
		let commandStr = cmd.entry ? "" : cmd.name || "";
		if (commandStr) commandStr += " ";
		const commandHelp = `${basePath} ${commandStr}--help`;
		return `${commandHelp.padStart(ctx.env.leftMargin + commandHelp.length)}`;
	}));
	return messages;
}
async function makeCommandSymbol(ctx, cmd) {
	const optionSymbol = await generateOptionsSymbols(ctx, ctx.args);
	const positionalSymbol = generatePositionalSymbols(ctx.args);
	let commandStr = cmd.entry ? cmd.name === void 0 || cmd.name === "(anonymous)" ? "" : `[${cmd.name}]` : cmd.name || "";
	if (optionSymbol) {
		if (commandStr) commandStr += " ";
		commandStr += `${optionSymbol}`;
	}
	if (positionalSymbol) {
		if (commandStr) commandStr += " ";
		commandStr += `${positionalSymbol}`;
	}
	return commandStr;
}
/**
* Resolve the entry command name
*
* @param ctx - A {@link CommandContext | command context}
* @returns The entry command name
*/
async function resolveEntry(ctx) {
	return ctx.env.name || await ctx.extensions[pluginId$2].text(resolveBuiltInKey("COMMAND"));
}
/**
* Resolve the sub command name
*
* @param ctx - A {@link CommandContext | command context}
* @returns The sub command name
*/
async function resolveSubCommand(ctx) {
	if (ctx.commandPath && ctx.commandPath.length > 0) return ctx.commandPath.join(" ");
	return ctx.name || await ctx.extensions[pluginId$2].text(resolveBuiltInKey("SUBCOMMAND"));
}
/**
* Resolve the command description
*
* @param ctx - A {@link CommandContext | command context}
* @returns resolved command description
*/
async function resolveDescription(ctx) {
	return await ctx.extensions[pluginId$2].text(resolveKey$1("description", ctx.name)) || ctx.description || "";
}
/**
* Resolve the command examples
*
* @param ctx - A {@link CommandContext | command context}
* @returns resolved command examples, if not resolved, return empty string
*/
async function resolveExamples$2(ctx) {
	const ret = await ctx.extensions[pluginId$2].text(resolveKey$1("examples", ctx.name));
	if (ret) return ret;
	const command = ctx.env.subCommands?.get(ctx.name || "");
	return await resolveExamples$1(ctx, command?.examples);
}
/**
* Check if the command has sub commands
*
* @param ctx - A {@link CommandContext | command context}
* @returns True if the command has sub commands
*/
async function hasCommands(ctx) {
	return (await ctx.extensions?.[pluginId$2].loadCommands() || []).length > 1;
}
/**
* Check if the command has optional arguments
*
* @param args - A {@link Args | command optional arguments}
* @returns True if the command has options
*/
function hasOptionalArgs(args) {
	return getVisibleOptionalArgs(args).length > 0;
}
/**
* Check if the command has positional arguments
*
* @param args - A {@link Args | command positional arguments}
* @returns True if the command has options
*/
function hasPositionalArgs(args) {
	return getVisiblePositionalArgs(args).length > 0;
}
/**
* Check if all options have default values
*
* @param args - An {@link Args | command argument}
* @returns True if all options have default values
*/
function hasAllDefaultOptions(args) {
	const visibleOptionalArgs = getVisibleOptionalArgs(args);
	return visibleOptionalArgs.length > 0 && visibleOptionalArgs.every(([_, arg]) => arg.default);
}
/**
* Generate options symbols for usage
*
* @param ctx - A {@link CommandContext | command context}
* @param args - {@link Args | command arguments}
* @returns Options symbols for usage
*/
async function generateOptionsSymbols(ctx, args) {
	return getVisibleOptionalArgs(args).length > 0 ? hasAllDefaultOptions(args) ? `[${await ctx.extensions[pluginId$2].text(resolveBuiltInKey("OPTIONS"))}]` : `<${await ctx.extensions[pluginId$2].text(resolveBuiltInKey("OPTIONS"))}>` : "";
}
/**
* Get optional arguments pairs for usage
*
* @param ctx - A {@link CommandContext | command context}
* @returns Options pairs for usage
*/
function getOptionalArgsPairs(ctx) {
	return getVisibleOptionalArgs(ctx.args).reduce((acc, [name, schema]) => {
		let key = makeShortLongOptionPair$1(schema, name, ctx.toKebab);
		if (schema.type !== "boolean") {
			const displayName = ctx.toKebab || schema.toKebab ? kebabnize$1(name) : name;
			key = schema.default ? `${key} [${displayName}]` : `${key} <${displayName}>`;
		}
		acc[name] = key;
		if (schema.type === "boolean" && schema.negatable && !COMMON_ARGS_KEYS.includes(name)) {
			const displayName = ctx.toKebab || schema.toKebab ? kebabnize$1(name) : name;
			acc[`no-${name}`] = `--no-${displayName}`;
		}
		return acc;
	}, Object.create(null));
}
const resolveNegatableKey = (key) => key.split("no-")[1];
function resolveNegatableType(key, ctx) {
	return ctx.args[key.startsWith("no-") ? resolveNegatableKey(key) : key].type;
}
async function generateDefaultDisplayValue(ctx, schema) {
	return `${await ctx.extensions[pluginId$2].text(resolveBuiltInKey("DEFAULT"))}: ${schema.default}`;
}
async function resolveDisplayValue(ctx, key) {
	if (COMMON_ARGS_KEYS.includes(key)) return "";
	const schema = ctx.args[key];
	if ((schema.type === "boolean" || schema.type === "number" || schema.type === "string" || schema.type === "custom") && schema.default !== void 0) return `(${await generateDefaultDisplayValue(ctx, schema)})`;
	if (schema.type === "enum") {
		const _default = schema.default === void 0 ? "" : await generateDefaultDisplayValue(ctx, schema);
		const choices = `${await ctx.extensions[pluginId$2].text(resolveBuiltInKey("CHOICES"))}: ${schema.choices.join(" | ")}`;
		return `(${_default ? `${_default}, ${choices}` : choices})`;
	}
	return "";
}
/**
* Generate optional arguments usage
*
* @param ctx - A {@link CommandContext | command context}
* @param optionsPairs - Options pairs for usage
* @returns Generated options usage
*/
async function generateOptionalArgsUsage(ctx, optionsPairs) {
	const optionsPairsEntries = Object.entries(optionsPairs);
	if (optionsPairsEntries.length === 0) return "";
	const optionsMaxLength = Math.max(...optionsPairsEntries.map(([_, value]) => value.length));
	const optionSchemaMaxLength = ctx.env.usageOptionType ? Math.max(...optionsPairsEntries.map(([key]) => resolveNegatableType(key, ctx).length)) : 0;
	return (await Promise.all(optionsPairsEntries.map(async ([key, value]) => {
		let rawDesc = await ctx.extensions[pluginId$2].text(resolveArgKey$1(key, ctx.name));
		if (!rawDesc && key.startsWith("no-")) {
			const name = resolveNegatableKey(key);
			const schema = ctx.args[name];
			const optionKey = makeShortLongOptionPair$1(schema, name, ctx.toKebab);
			rawDesc = `${await ctx.extensions[pluginId$2].text(resolveBuiltInKey("NEGATABLE"))} ${optionKey}`;
		}
		const optionsSchema = ctx.env.usageOptionType ? `[${resolveNegatableType(key, ctx)}] ` : "";
		const valueDesc = key.startsWith("no-") ? "" : await resolveDisplayValue(ctx, key);
		const desc = `${optionsSchema ? optionsSchema.padEnd(optionSchemaMaxLength + 3) : ""}${rawDesc}`;
		const descLength = desc.length + valueDesc.length;
		const option = `${value.padEnd((descLength > 0 ? optionsMaxLength : 0) + ctx.env.middleMargin)}${desc}${valueDesc ? ` ${valueDesc}` : ""}`;
		return `${option.padStart(ctx.env.leftMargin + option.length)}`;
	}))).join("\n");
}
function getPositionalArgs(args) {
	return getVisiblePositionalArgs(args);
}
async function generatePositionalArgsUsage(ctx) {
	const positionals = getPositionalArgs(ctx.args);
	if (positionals.length === 0) return "";
	const argsMaxLength = Math.max(...positionals.map(([name]) => name.length));
	return (await Promise.all(positionals.map(async ([name]) => {
		const desc = await ctx.extensions[pluginId$2].text(resolveArgKey$1(name, ctx.name)) || ctx.args[name].description || "";
		const arg = `${name.padEnd(argsMaxLength + ctx.env.middleMargin)} ${desc}`;
		return `${arg.padStart(ctx.env.leftMargin + arg.length)}`;
	}))).join("\n");
}
function generatePositionalSymbols(args) {
	const visiblePositionalArgs = getVisiblePositionalArgs(args);
	return visiblePositionalArgs.length > 0 ? visiblePositionalArgs.map(([name, arg]) => {
		const elements = [];
		if (arg.multiple) {
			if (arg.required) elements.push(`<${name}>`);
			elements.push(`[<${name}> ...]`);
		} else elements.push(isRequiredSinglePositionalArg(arg) ? `<${name}>` : `[<${name}>]`);
		return elements.join(" ");
	}).join(" ") : "";
}
function isRequiredSinglePositionalArg(arg) {
	if (arg.required === true) return true;
	if (arg.required === false) return false;
	return arg.default == null;
}
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
const i18nPluginId$1 = namespacedId$1("i18n");
/**
* Render the validation errors.
*
* @param ctx - A {@link CommandContext | command context}
* @param error - An {@link AggregateError} of option in `args-token` validation
* @returns A rendered validation error.
*/
async function renderValidationErrors(ctx, error) {
	const messages = [];
	for (const err of error.errors) messages.push(await renderValidationError(ctx, err));
	return messages.join("\n");
}
async function renderValidationError(ctx, error) {
	if (isCommandNotFoundError(error) && error.code) {
		const message = await localize(ctx, error.code, error.values);
		if (message && message !== error.code) return message;
	}
	if (isArgsValidationError(error) && error.code) {
		const values = await resolveValidationValues(ctx, error);
		const message = await localize(ctx, error.code, values);
		if (message && message !== error.code) return message;
	}
	return error.message;
}
async function resolveValidationValues(ctx, error) {
	if (error.code !== ArgsValidationErrorKeys.customParse) return error.values;
	const { reasonKey, reasonValues } = error.values;
	if (typeof reasonKey !== "string") return error.values;
	const key = resolveKey$1(reasonKey, ctx.name);
	const localizedReason = await localize(ctx, key, toRecord(reasonValues));
	if (!localizedReason || localizedReason === key) return error.values;
	return {
		...error.values,
		reason: localizedReason
	};
}
async function localize(ctx, key, values) {
	const i18n = ctx.extensions?.[i18nPluginId$1];
	if (i18n?.translate) return i18n.translate(key, values);
	return key;
}
function toRecord(value) {
	return value != null && typeof value === "object" ? value : Object.create(null);
}
/**
* The entry point of usage renderer plugin
*
* @example
* ```js
* import renderer from '@gunshi/plugin-renderer'
* import { cli } from 'gunshi'
*
* const entry = (ctx) => {
*   // ...
* }
*
* await cli(process.argv.slice(2), entry, {
*   // ...
*
*   plugins: [
*     renderer()
*   ],
*
*   // ...
* })
* ```
*
* @module
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
const i18nPluginId$2 = namespacedId$1("i18n");
const dependencies$1 = [{
	id: i18nPluginId$2,
	optional: true
}];
/**
* usage renderer plugin
*
* @returns A defined plugin as usage renderer
*/
function renderer() {
	return plugin$1({
		id: pluginId$2,
		name: "usage renderer",
		dependencies: dependencies$1,
		extension: (ctx, cmd) => {
			const i18n = ctx.extensions[i18nPluginId$2];
			let cachedCommands;
			async function loadCommands() {
				if (cachedCommands) return cachedCommands;
				const subCommands = [...ctx.env.subCommands || []];
				cachedCommands = (await Promise.all(subCommands.map(async ([name, cmd]) => await resolveLazyCommand$1(cmd, name)))).filter((cmd) => !cmd.internal).filter(Boolean);
				cachedCommands.sort((a, b) => {
					if (a.entry && !b.entry) return -1;
					if (!a.entry && b.entry) return 1;
					if (a.name && b.name) return a.name.localeCompare(b.name);
					if (a.name && !b.name) return -1;
					if (!a.name && b.name) return 1;
					return 0;
				});
				return cachedCommands;
			}
			return {
				text: localizable$1(ctx, cmd, i18n?.translate),
				loadCommands
			};
		},
		setup: (ctx) => {
			ctx.decorateHeaderRenderer(async (_baseRenderer, cmdCtx) => await renderHeader(cmdCtx));
			ctx.decorateUsageRenderer(async (_baseRenderer, cmdCtx) => await renderUsage(cmdCtx));
			ctx.decorateValidationErrorsRenderer(async (_baseRenderer, cmdCtx, error) => await renderValidationErrors(cmdCtx, error));
		}
	});
}
//#endregion
//#region node_modules/.pnpm/gunshi@0.37.3/node_modules/gunshi/lib/core-CLzX86kY.js
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
const EMPTY_RENDERER = () => Promise.resolve("");
/**
* Factory function for creating a decorators manager.
*
* @returns A new decorators manager instance
*/
function createDecorators() {
	/**
	* private states
	*/
	const headerDecorators = [];
	const usageDecorators = [];
	const validationDecorators = [];
	const commandDecorators = [];
	/**
	* helper function for building renderers
	*/
	function buildRenderer(decorators, defaultRenderer) {
		if (decorators.length === 0) return defaultRenderer;
		let renderer = defaultRenderer;
		for (const decorator of decorators) {
			const previousRenderer = renderer;
			renderer = (ctx) => decorator(previousRenderer, ctx);
		}
		return renderer;
	}
	/**
	* public interfaces
	*/
	return Object.freeze({
		addHeaderDecorator(decorator) {
			headerDecorators.push(decorator);
		},
		addUsageDecorator(decorator) {
			usageDecorators.push(decorator);
		},
		addValidationErrorsDecorator(decorator) {
			validationDecorators.push(decorator);
		},
		addCommandDecorator(decorator) {
			commandDecorators.push(decorator);
		},
		get commandDecorators() {
			return [...commandDecorators];
		},
		getHeaderRenderer() {
			return buildRenderer(headerDecorators, EMPTY_RENDERER);
		},
		getUsageRenderer() {
			return buildRenderer(usageDecorators, EMPTY_RENDERER);
		},
		getValidationErrorsRenderer() {
			if (validationDecorators.length === 0) return EMPTY_RENDERER;
			let renderer = EMPTY_RENDERER;
			for (const decorator of validationDecorators) {
				const previousRenderer = renderer;
				renderer = (ctx, error) => decorator(previousRenderer, ctx, error);
			}
			return renderer;
		}
	});
}
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Factory function for creating a plugin context.
*
* @typeParam G - A type extending {@linkcode GunshiParams} to specify the shape of command parameters.
*
* @param decorators - A {@linkcode Decorators} instance.
* @param initialSubCommands - Initial sub commands map.
* @returns A new {@linkcode PluginContext} instance.
*/
function createPluginContext(decorators, initialSubCommands) {
	/**
	* private states
	*/
	const globalOptions = /* @__PURE__ */ new Map();
	const subCommands = new Map(initialSubCommands || []);
	/**
	* public interfaces
	*/
	return Object.freeze({
		get globalOptions() {
			return new Map(globalOptions);
		},
		addGlobalOption(name, schema) {
			if (!name) throw new Error("Option name must be a non-empty string");
			if (globalOptions.has(name)) throw new Error(`Global option '${name}' is already registered`);
			globalOptions.set(name, schema);
		},
		get subCommands() {
			return new Map(subCommands);
		},
		addCommand(name, command) {
			if (!name) throw new Error("Command name must be a non-empty string");
			if (subCommands.has(name)) throw new Error(`Command '${name}' is already registered`);
			subCommands.set(name, command);
		},
		hasCommand(name) {
			return subCommands.has(name);
		},
		decorateHeaderRenderer(decorator) {
			decorators.addHeaderDecorator(decorator);
		},
		decorateUsageRenderer(decorator) {
			decorators.addUsageDecorator(decorator);
		},
		decorateValidationErrorsRenderer(decorator) {
			decorators.addValidationErrorsDecorator(decorator);
		},
		decorateCommand(decorator) {
			decorators.addCommandDecorator(decorator);
		}
	});
}
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Resolve plugin dependencies using topological sort
*
* @param plugins - Array of plugins to resolve
* @returns Array of plugins sorted by dependencies
*/
function resolveDependencies(plugins) {
	const sorted = [];
	const visited = /* @__PURE__ */ new Set();
	const visiting = /* @__PURE__ */ new Set();
	const pluginMap = /* @__PURE__ */ new Map();
	for (const plugin of plugins) if (plugin.id) {
		if (pluginMap.has(plugin.id)) console.warn(`Duplicate plugin id detected: \`${plugin.id}\``);
		pluginMap.set(plugin.id, plugin);
	}
	function visit(plugin) {
		if (!plugin.id) return;
		if (visited.has(plugin.id)) return;
		if (visiting.has(plugin.id)) throw new Error(`Circular dependency detected: \`${[...visiting].join(` -> `) + " -> " + plugin.id}\``);
		visiting.add(plugin.id);
		const deps = plugin.dependencies || [];
		for (const dep of deps) {
			const depId = typeof dep === "string" ? dep : dep.id;
			const isOptional = typeof dep === "string" ? false : dep.optional || false;
			const depPlugin = pluginMap.get(depId);
			if (!depPlugin && !isOptional) throw new Error(`Missing required dependency: \`${depId}\` on \`${plugin.id}\``);
			if (depPlugin) visit(depPlugin);
		}
		visiting.delete(plugin.id);
		visited.add(plugin.id);
		sorted.push(plugin);
	}
	for (const plugin of plugins) visit(plugin);
	return sorted;
}
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Run the command.
*
* @typeParam G - A type extending {@linkcode GunshiParams} to specify the shape of command and cli options.
*
* @param argv - Command line arguments
* @param entry - A {@link Command | entry command}, an {@link CommandRunner | inline command runner}, or a {@link LazyCommand | lazily-loaded command}
* @param options - A {@link CliOptions | CLI options}
* @param plugins - An array of {@link Plugin | plugins} to be applied
* @returns A rendered usage or undefined. if you will use {@link CliOptions.usageSilent} option, it will return rendered usage string.
*/
async function cliCore(argv, entry, options, plugins) {
	const decorators = createDecorators();
	const pluginContext = createPluginContext(decorators, createInitialSubCommands(options, entry));
	const resolvedPlugins = await applyPlugins(pluginContext, [...plugins, ...options.plugins || []]);
	const cliOptions = normalizeCliOptions(options, decorators, pluginContext);
	const tokens = parseArgs(argv);
	const resolved = resolveCommandTree(tokens, entry, cliOptions);
	const { commandName: name, command, callMode, commandPath, depth, levelSubCommands } = resolved;
	let targetCommand = command;
	let targetCommandName = name;
	let targetCallMode = callMode;
	let targetCommandPath = commandPath;
	let targetDepth = depth;
	let targetOmitted = resolved.omitted;
	let targetLevelSubCommands = levelSubCommands;
	const additionalValidationErrors = [];
	if (!targetCommand) {
		if (!resolved.parentCommand || !resolved.unresolvedCommandName) throw new Error(`Command not found: ${name || ""}`);
		targetCommand = resolved.parentCommand;
		targetCommandName = resolved.parentCommandName;
		targetCommandPath = resolved.parentCommandPath || [];
		targetDepth = targetCommandPath.length;
		targetCallMode = targetDepth > 0 ? "subCommand" : "entry";
		targetOmitted = false;
		targetLevelSubCommands = resolved.parentSubCommands;
		additionalValidationErrors.push(createCommandNotFoundError(resolved));
	}
	if (targetLevelSubCommands) cliOptions.subCommands = targetLevelSubCommands;
	const resolvedCommand = isLazyCommand$2(targetCommand) ? await resolveLazyCommand$1(targetCommand, targetCommandName, true) : targetCommand;
	const args = resolveArguments(pluginContext, getCommandArgs(resolvedCommand));
	const skipPositional = targetDepth > 0 ? targetDepth - 1 : -1;
	const { explicit, values, positionals, rest, error } = resolveArgs(args, tokens, {
		shortGrouping: true,
		toKebab: resolvedCommand.toKebab,
		skipPositional
	});
	const validationError = mergeValidationErrors(error, [...additionalValidationErrors, ...cliOptions.strict ? createUnknownOptionErrors(findUnknownOptions(args, tokens, { toKebab: resolvedCommand.toKebab })) : []]);
	return await executeCommand(resolvedCommand, await createCommandContext$1({
		args,
		explicit,
		values,
		positionals,
		rest,
		argv,
		tokens,
		omitted: targetOmitted,
		callMode: targetCallMode,
		commandPath: targetCommandPath,
		command: resolvedCommand,
		extensions: getPluginExtensions(resolvedPlugins),
		validationError,
		cliOptions
	}), decorators.commandDecorators);
}
async function applyPlugins(pluginContext, plugins) {
	const sortedPlugins = resolveDependencies(plugins);
	try {
		for (const plugin of sortedPlugins)
 /**
		* NOTE(kazupon):
		* strictly `Args` are not required for plugin installation.
		* because the strictly `Args` required by each plugin are unknown,
		* and the plugin side can not know what the user will specify.
		*/
		await plugin(pluginContext);
	} catch (error) {
		console.error("Error loading plugin:", error.message);
	}
	return sortedPlugins;
}
function getCommandArgs(cmd) {
	if (isLazyCommand$2(cmd)) return cmd.args || create$2();
	else if (typeof cmd === "object") return cmd.args || create$2();
	else return create$2();
}
function resolveArguments(pluginContext, args) {
	return Object.assign(create$2(), Object.fromEntries(pluginContext.globalOptions), args);
}
const NEGATABLE_OPTION_PREFIX = "no-";
function findUnknownOptions(args, tokens, options) {
	const knownLongOptions = /* @__PURE__ */ new Set();
	const knownShortOptions = /* @__PURE__ */ new Set();
	const knownNegatableOptions = /* @__PURE__ */ new Set();
	const knownLongOptionCandidates = /* @__PURE__ */ new Set();
	const longOptionCandidates = [];
	function addLongOptionCandidate(name) {
		const candidate = `--${name}`;
		if (knownLongOptionCandidates.has(candidate)) return;
		knownLongOptionCandidates.add(candidate);
		longOptionCandidates.push(candidate);
	}
	for (const [name, schema] of Object.entries(args)) {
		if (schema.type === "positional") continue;
		const optionName = resolveOptionName(name, schema, options);
		knownLongOptions.add(optionName);
		addLongOptionCandidate(optionName);
		if (schema.short) knownShortOptions.add(schema.short);
		if (schema.type === "boolean" && schema.negatable) {
			const negatableOptionName = `${NEGATABLE_OPTION_PREFIX}${optionName}`;
			knownNegatableOptions.add(negatableOptionName);
			addLongOptionCandidate(negatableOptionName);
		}
	}
	const unknownOptions = [];
	for (const token of tokens) {
		if (token.kind === "option-terminator") break;
		if (token.kind !== "option" || !token.name || !token.rawName) continue;
		const isLongOption = token.rawName.startsWith("--");
		if (isLongOption) {
			if (knownLongOptions.has(token.name) || knownNegatableOptions.has(token.name)) continue;
		} else if (knownShortOptions.has(token.name)) continue;
		unknownOptions.push({
			rawName: token.rawName,
			name: token.name,
			candidates: isLongOption ? longOptionCandidates : []
		});
	}
	return unknownOptions;
}
function resolveOptionName(name, schema, options) {
	return options.toKebab || schema.toKebab ? kebabnize$1(name) : name;
}
function createUnknownOptionErrors(unknownOptions) {
	return unknownOptions.map(({ rawName, name, candidates }) => {
		return new ArgsValidationError(`Unknown option: ${rawName}`, {
			code: ArgsValidationErrorKeys.unknownOption,
			values: {
				rawName,
				name,
				candidates
			}
		});
	});
}
function mergeValidationErrors(error, additionalErrors) {
	if (additionalErrors.length === 0) return error;
	return new AggregateError(error ? [...error.errors, ...additionalErrors] : additionalErrors, error?.message || additionalErrors[0]?.message);
}
const isObject = (val) => val !== null && typeof val === "object";
function createInitialSubCommands(options, entryCmd) {
	const hasSubCommands = options.subCommands ? options.subCommands instanceof Map ? options.subCommands.size > 0 : isObject(options.subCommands) && Object.keys(options.subCommands).length > 0 : false;
	const subCommands = new Map(options.subCommands instanceof Map ? options.subCommands : []);
	if (!(options.subCommands instanceof Map) && isObject(options.subCommands)) for (const [name, cmd] of Object.entries(options.subCommands)) subCommands.set(name, cmd);
	if (hasSubCommands) {
		if (isLazyCommand$2(entryCmd)) {
			const entryCopy = Object.assign((...args) => entryCmd(...args), entryCmd, { entry: true });
			subCommands.set(resolveEntryName(entryCopy), entryCopy);
		} else if (typeof entryCmd === "object") {
			const entryCopy = Object.assign(create$2(), entryCmd, { entry: true });
			subCommands.set(resolveEntryName(entryCopy), entryCopy);
		} else if (typeof entryCmd === "function") {
			const name = entryCmd.name || "(anonymous)";
			subCommands.set(name, {
				run: entryCmd,
				name,
				entry: true
			});
		}
	}
	return subCommands;
}
function normalizeCliOptions(options, decorators, pluginContext) {
	const subCommands = new Map(pluginContext.subCommands);
	const resolvedOptions = Object.assign(create$2(), CLI_OPTIONS_DEFAULT$1, options, { subCommands });
	if (resolvedOptions.renderHeader === void 0) resolvedOptions.renderHeader = decorators.getHeaderRenderer();
	if (resolvedOptions.renderUsage === void 0) resolvedOptions.renderUsage = decorators.getUsageRenderer();
	if (resolvedOptions.renderValidationErrors === void 0) resolvedOptions.renderValidationErrors = decorators.getValidationErrorsRenderer();
	return resolvedOptions;
}
function getPositionalTokens(tokens) {
	return tokens.filter((t) => t.kind === "positional").map((t) => t.value).filter((v) => !!v);
}
function resolveCommandTree(tokens, entry, options) {
	const positionals = getPositionalTokens(tokens);
	function resolveAsEntry() {
		if (typeof entry === "function") {
			if ("commandName" in entry && entry.commandName) return {
				commandName: entry.commandName,
				command: entry,
				callMode: "entry",
				commandPath: [],
				depth: 0,
				omitted: options.subCommands.size > 0 && !positionals[0],
				levelSubCommands: options.subCommands.size > 0 ? options.subCommands : void 0
			};
			else return {
				command: {
					run: entry,
					entry: true
				},
				callMode: "entry",
				commandPath: [],
				depth: 0,
				omitted: options.subCommands.size > 0 && !positionals[0],
				levelSubCommands: options.subCommands.size > 0 ? options.subCommands : void 0
			};
		} else if (typeof entry === "object") return {
			commandName: resolveEntryName(entry),
			command: entry,
			callMode: "entry",
			commandPath: [],
			depth: 0,
			omitted: options.subCommands.size > 0 && !positionals[0],
			levelSubCommands: options.subCommands.size > 0 ? options.subCommands : void 0
		};
		else return {
			callMode: "unexpected",
			commandPath: [],
			depth: 0,
			omitted: false,
			levelSubCommands: void 0
		};
	}
	if (positionals.length === 0 || options.subCommands.size === 0) return resolveAsEntry();
	let currentSubCommands = options.subCommands;
	let resolvedCommand;
	let resolvedName;
	const commandPath = [];
	let depth = 0;
	for (let i = 0; i < positionals.length; i++) {
		const token = positionals[i];
		const cmd = currentSubCommands.get(token);
		if (cmd == null) {
			if (depth === 0) {
				if (options.fallbackToEntry) return resolveAsEntry();
				const parent = resolveAsEntry();
				return {
					commandName: token,
					callMode: "unexpected",
					commandPath: [],
					depth: 0,
					omitted: false,
					levelSubCommands: void 0,
					unresolvedCommandName: token,
					parentCommand: parent.command,
					parentCommandName: parent.commandName,
					parentCommandPath: [],
					parentSubCommands: options.subCommands
				};
			}
			return {
				commandName: token,
				callMode: "unexpected",
				commandPath: [...commandPath],
				depth,
				omitted: false,
				levelSubCommands: void 0,
				unresolvedCommandName: token,
				parentCommand: resolvedCommand,
				parentCommandName: resolvedName,
				parentCommandPath: [...commandPath],
				parentSubCommands: currentSubCommands
			};
		}
		let resolved = cmd;
		if (typeof cmd === "function" && cmd.commandName == null) resolved = Object.assign((...args) => cmd(...args), cmd, { commandName: token });
		else if (typeof cmd === "object" && cmd.name == null) resolved = Object.assign(create$2(), cmd, { name: token });
		resolvedCommand = resolved;
		resolvedName = token;
		commandPath.push(token);
		depth++;
		const nestedSubCommands = getCommandSubCommands(cmd);
		if (nestedSubCommands && nestedSubCommands.size > 0) currentSubCommands = nestedSubCommands;
		else break;
	}
	if (!resolvedCommand) return resolveAsEntry();
	const resolvedSubCommands = getCommandSubCommands(resolvedCommand);
	const omitted = resolvedSubCommands != null && resolvedSubCommands.size > 0;
	let levelSubCommands;
	if (omitted && resolvedSubCommands) {
		levelSubCommands = new Map(resolvedSubCommands);
		let entryCopy;
		if (typeof resolvedCommand === "function") entryCopy = Object.assign((...args) => resolvedCommand(...args), resolvedCommand, { entry: true });
		else entryCopy = Object.assign(create$2(), resolvedCommand, { entry: true });
		levelSubCommands.set(resolvedName || resolveEntryName(entryCopy), entryCopy);
	}
	return {
		commandName: resolvedName,
		command: resolvedCommand,
		callMode: depth > 0 ? "subCommand" : "entry",
		commandPath,
		depth,
		omitted,
		levelSubCommands
	};
}
function createCommandNotFoundError(resolved) {
	const commandName = resolved.unresolvedCommandName || resolved.commandName || "";
	return new CommandNotFoundError(`Command not found: ${commandName}`, {
		code: CommandNotFoundErrorKeys.notFound,
		values: { commandName },
		commandName,
		candidates: [...resolved.parentSubCommands?.keys() || []],
		commandPath: resolved.parentCommandPath || []
	});
}
function resolveEntryName(entry) {
	return isLazyCommand$2(entry) ? entry.commandName || "(anonymous)" : entry.name || "(anonymous)";
}
function getPluginExtensions(plugins) {
	const extensions = create$2();
	for (const plugin of plugins) if (plugin.extension) {
		const key = plugin.id;
		if (extensions[key]) console.warn(`Plugin "${key}" is already installed. Ignore it for command context extending.`);
		else extensions[key] = plugin.extension;
	}
	return extensions;
}
async function executeCommand(cmd, ctx, decorators) {
	const commandRunner = cmd.run || NOOP$1;
	const baseRunner = (ctx) => {
		if (hasPriorityValidationError(ctx.validationError)) throw ctx.validationError;
		return commandRunner(ctx);
	};
	const decoratedRunner = decorators.reduceRight((runner, decorator) => decorator(runner), baseRunner);
	try {
		if (ctx.env.onBeforeCommand) await ctx.env.onBeforeCommand(ctx);
		const result = await decoratedRunner(ctx);
		if (ctx.env.onAfterCommand) await ctx.env.onAfterCommand(ctx, result);
		return typeof result === "string" ? result : void 0;
	} catch (error) {
		if (ctx.env.onErrorCommand) try {
			await ctx.env.onErrorCommand(ctx, error);
		} catch (hookError) {
			console.error("Error in onErrorCommand hook:", hookError);
		}
		throw error;
	}
}
//#endregion
//#region node_modules/.pnpm/gunshi@0.37.3/node_modules/gunshi/lib/cli-BnmSo-DW.js
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* The unique identifier for the global options plugin.
*/
const pluginId$1 = namespacedId$1("global");
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Decorator function to extend the command with global options.
*
* @param baseRunner - The base command runner
* @returns A command decorator that adds global options handling
*/
const decorator = (baseRunner) => async (ctx) => {
	const { values, validationError, extensions: { [pluginId$1]: { showVersion, showHeader, showUsage, showValidationErrors } } } = ctx;
	if (hasPriorityValidationError(validationError)) {
		await showValidationErrors(validationError);
		throw validationError;
	}
	if (values.version) return showVersion();
	const buf = [];
	const header = await showHeader();
	if (header) buf.push(header);
	if (values.help) {
		const usage = await showUsage();
		if (usage) {
			buf.push(usage);
			return buf.join("\n");
		}
		return;
	}
	if (validationError) {
		await showValidationErrors(validationError);
		throw validationError;
	}
	return baseRunner(ctx);
};
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Extends the command context for global options plugin.
*
* @param ctx - The {@linkcode CommandContextCore | command context} core
* @returns An {@linkcode GlobalExtension} of global options plugin
*/
function extension(ctx) {
	return {
		showVersion: () => {
			const version = ctx.env.version || "unknown";
			if (!ctx.env.usageSilent) ctx.log(version);
			return version;
		},
		showHeader: async () => {
			let header;
			if (ctx.env.renderHeader != null) {
				header = await ctx.env.renderHeader(ctx);
				if (header) {
					ctx.log(header);
					ctx.log();
				}
			}
			return header;
		},
		showUsage: async () => {
			if (ctx.env.renderUsage != null) {
				const usage = await ctx.env.renderUsage(ctx);
				if (usage) {
					ctx.log(usage);
					return usage;
				}
			}
		},
		showValidationErrors: async (error) => {
			if (ctx.env.renderValidationErrors === null) return;
			if (ctx.env.renderValidationErrors !== void 0) {
				const message = await ctx.env.renderValidationErrors(ctx, error);
				ctx.log(message);
				return message;
			}
		}
	};
}
/**
* The entry point of global options plugin
*
* @example
* ```js
* import global from '@gunshi/plugin-global'
* import { cli } from 'gunshi'
*
* const entry = (ctx) => {
*   // ...
* }
*
* await cli(process.argv.slice(2), entry, {
*   // ...
*
*   plugins: [
*     global()
*   ],
*
*   // ...
* })
* ```
*
* @module
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* global options plugin
*
* @returns A defined plugin as global options
*/
function global() {
	return plugin$1({
		id: pluginId$1,
		name: "global options",
		extension,
		setup(ctx) {
			for (const [name, schema] of Object.entries(COMMON_ARGS)) ctx.addGlobalOption(name, schema);
			ctx.decorateCommand(decorator);
		}
	});
}
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Run the command.
*
* @typeParam G - A type extending {@linkcode GunshiParams} to specify the shape of command and cli options.
*
* @param args - Command line arguments
* @param entry - A {@link Command | entry command}, an {@link CommandRunner | inline command runner}, or a {@link LazyCommand | lazily-loaded command}
* @param options - A {@link CliOptions | CLI options}
* @returns A rendered usage or undefined. if you will use {@linkcode CliOptions.usageSilent} option, it will return rendered usage string.
*/
async function cli(args, entry, options = {}) {
	return cliCore(args, entry, options, [global(), renderer()]);
}
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
//#endregion
//#region node_modules/.pnpm/gunshi@0.37.3/node_modules/gunshi/lib/definition.js
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Define a {@link Command | command}.
*
* @typeParam G - A {@link GunshiParamsConstraint} type
*
* @param definition - A {@link Command | command} definition
* @returns A defined {@link Command | command}
*/
function define(definition) {
	return definition;
}
//#endregion
//#region node_modules/.pnpm/gunshi@0.37.3/node_modules/gunshi/lib/index.js
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
namespacedId$1("i18n");
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
"_".codePointAt(0);
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
//#endregion
//#region node_modules/.pnpm/@bomb.sh+tab@0.0.22/node_modules/@bomb.sh/tab/dist/powershell-C1q3FW2e.mjs
function t(t, n) {
	return `#compdef ${t}
compdef _${t} ${t}

# zsh completion for ${t} -*- shell-script -*-

__${t}_debug() {
    local file="$BASH_COMP_DEBUG_FILE"
    if [[ -n \${file} ]]; then
        echo "$*" >> "\${file}"
    fi
}

_${t}() {
    local shellCompDirectiveError=${a.ShellCompDirectiveError}
    local shellCompDirectiveNoSpace=${a.ShellCompDirectiveNoSpace}
    local shellCompDirectiveNoFileComp=${a.ShellCompDirectiveNoFileComp}
    local shellCompDirectiveFilterFileExt=${a.ShellCompDirectiveFilterFileExt}
    local shellCompDirectiveFilterDirs=${a.ShellCompDirectiveFilterDirs}
    local shellCompDirectiveKeepOrder=${a.ShellCompDirectiveKeepOrder}

    local lastParam lastChar flagPrefix requestComp out directive comp lastComp noSpace keepOrder
    local -a completions

    __${t}_debug "\\n========= starting completion logic =========="
    __${t}_debug "CURRENT: \${CURRENT}, words[*]: \${words[*]}"

    # The user could have moved the cursor backwards on the command-line.
    # We need to trigger completion from the $CURRENT location, so we need
    # to truncate the command-line ($words) up to the $CURRENT location.
    # (We cannot use $CURSOR as its value does not work when a command is an alias.)
    words=( "\${=words[1,CURRENT]}" )
    __${t}_debug "Truncated words[*]: \${words[*]},"

    lastParam=\${words[-1]}
    lastChar=\${lastParam[-1]}
    __${t}_debug "lastParam: \${lastParam}, lastChar: \${lastChar}"

    # For zsh, when completing a flag with an = (e.g., ${t} -n=<TAB>)
    # completions must be prefixed with the flag
    setopt local_options BASH_REMATCH
    if [[ "\${lastParam}" =~ '-.*=' ]]; then
        # We are dealing with a flag with an =
        flagPrefix="-P \${BASH_REMATCH}"
    fi

    # Prepare the command to obtain completions, ensuring arguments are quoted for eval
    local -a args_to_quote=("\${(@)words[2,-1]}")
    if [ "\${lastChar}" = "" ] && [ "\${args_to_quote[-1]}" != "" ]; then
        # If the last parameter is complete (there is a space following it)
        # We add an extra empty parameter so we can indicate this to the go completion code.
        __${t}_debug "Adding extra empty parameter"
        args_to_quote+=("")
    fi

    # Use Zsh's (q) flag to quote each argument safely for eval
    local quoted_args=("\${(@q)args_to_quote}")

    # Join the main command and the quoted arguments into a single string for eval
    requestComp="${n} complete -- \${quoted_args[*]}"

    __${t}_debug "About to call: eval \${requestComp}"

    # Use eval to handle any environment variables and such
    out=$(eval \${requestComp} 2>/dev/null)
    __${t}_debug "completion output: \${out}"

    # Extract the directive integer following a : from the last line
    local lastLine
    while IFS='\n' read -r line; do
        lastLine=\${line}
    done < <(printf "%s\n" "\${out[@]}")
    __${t}_debug "last line: \${lastLine}"

    if [ "\${lastLine[1]}" = : ]; then
        directive=\${lastLine[2,-1]}
        # Remove the directive including the : and the newline
        local suffix
        (( suffix=\${#lastLine}+2))
        out=\${out[1,-$suffix]}
    else
        # There is no directive specified.  Leave $out as is.
        __${t}_debug "No directive found.  Setting to default"
        directive=0
    fi

    __${t}_debug "directive: \${directive}"
    __${t}_debug "completions: \${out}"
    __${t}_debug "flagPrefix: \${flagPrefix}"

    if [ $((directive & shellCompDirectiveError)) -ne 0 ]; then
        __${t}_debug "Completion received error. Ignoring completions."
        return
    fi

    local activeHelpMarker="%"
    local endIndex=\${#activeHelpMarker}
    local startIndex=$((\${#activeHelpMarker}+1))
    local hasActiveHelp=0
    while IFS='\n' read -r comp; do
        # Check if this is an activeHelp statement (i.e., prefixed with $activeHelpMarker)
        if [ "\${comp[1,$endIndex]}" = "$activeHelpMarker" ];then
            __${t}_debug "ActiveHelp found: $comp"
            comp="\${comp[$startIndex,-1]}"
            if [ -n "$comp" ]; then
                compadd -x "\${comp}"
                __${t}_debug "ActiveHelp will need delimiter"
                hasActiveHelp=1
            fi
            continue
        fi

        if [ -n "$comp" ]; then
            # If requested, completions are returned with a description.
            # The description is preceded by a TAB character.
            # For zsh's _describe, we need to use a : instead of a TAB.
            # We first need to escape any : as part of the completion itself.
            comp=\${comp//:/\\:}

            local tab="$(printf '\\t')"
            comp=\${comp//$tab/:}

            __${t}_debug "Adding completion: \${comp}"
            completions+=\${comp}
            lastComp=$comp
        fi
    done < <(printf "%s\n" "\${out[@]}")

    # Add a delimiter after the activeHelp statements, but only if:
    # - there are completions following the activeHelp statements, or
    # - file completion will be performed (so there will be choices after the activeHelp)
    if [ $hasActiveHelp -eq 1 ]; then
        if [ \${#completions} -ne 0 ] || [ $((directive & shellCompDirectiveNoFileComp)) -eq 0 ]; then
            __${t}_debug "Adding activeHelp delimiter"
            compadd -x "--"
            hasActiveHelp=0
        fi
    fi

    if [ $((directive & shellCompDirectiveNoSpace)) -ne 0 ]; then
        __${t}_debug "Activating nospace."
        noSpace="-S ''"
    fi

    if [ $((directive & shellCompDirectiveKeepOrder)) -ne 0 ]; then
        __${t}_debug "Activating keep order."
        keepOrder="-V"
    fi

    if [ $((directive & shellCompDirectiveFilterFileExt)) -ne 0 ]; then
        # File extension filtering
        local filteringCmd
        filteringCmd='_files'
        for filter in \${completions[@]}; do
            if [ \${filter[1]} != '*' ]; then
                # zsh requires a glob pattern to do file filtering
                filter="\\*.$filter"
            fi
            filteringCmd+=" -g $filter"
        done
        filteringCmd+=" \${flagPrefix}"

        __${t}_debug "File filtering command: $filteringCmd"
        _arguments '*:filename:'"$filteringCmd"
    elif [ $((directive & shellCompDirectiveFilterDirs)) -ne 0 ]; then
        # File completion for directories only
        local subdir
        subdir="\${completions[1]}"
        if [ -n "$subdir" ]; then
            __${t}_debug "Listing directories in $subdir"
            pushd "\${subdir}" >/dev/null 2>&1
        else
            __${t}_debug "Listing directories in ."
        fi

        local result
        _arguments '*:dirname:_files -/'" \${flagPrefix}"
        result=$?
        if [ -n "$subdir" ]; then
            popd >/dev/null 2>&1
        fi
        return $result
    else
        __${t}_debug "Calling _describe"
        if eval _describe $keepOrder "completions" completions -Q \${flagPrefix} \${noSpace}; then
            __${t}_debug "_describe found some completions"

            # Return the success of having called _describe
            return 0
        else
            __${t}_debug "_describe did not find completions."
            __${t}_debug "Checking if we should do file completion."
            if [ $((directive & shellCompDirectiveNoFileComp)) -ne 0 ]; then
                __${t}_debug "deactivating file completion"

                # Return 0 to indicate completion is finished and prevent zsh from
                # trying other completion algorithms (which could cause hanging).
                # We use NoFileComp directive to explicitly disable file completion.
                return 0
            else
                # Perform file completion
                __${t}_debug "Activating file completion"

                # We must return the result of this command, so it must be the
                # last command, or else we must store its result to return it.
                _arguments '*:filename:_files'" \${flagPrefix}"
            fi
        fi
    fi
}

# don't run the completion function when being sourced or eval-ed
if [ "\${funcstack[1]}" = "_${t}" ]; then
    _${t}
fi
`;
}
function n(t, n) {
	let r = t.replace(/[-:]/g, `_`);
	return `# bash completion for ${t}

# Define shell completion directives
readonly ShellCompDirectiveError=${a.ShellCompDirectiveError}
readonly ShellCompDirectiveNoSpace=${a.ShellCompDirectiveNoSpace}
readonly ShellCompDirectiveNoFileComp=${a.ShellCompDirectiveNoFileComp}
readonly ShellCompDirectiveFilterFileExt=${a.ShellCompDirectiveFilterFileExt}
readonly ShellCompDirectiveFilterDirs=${a.ShellCompDirectiveFilterDirs}
readonly ShellCompDirectiveKeepOrder=${a.ShellCompDirectiveKeepOrder}

# Function to debug completion
__${r}_debug() {
    if [[ -n \${BASH_COMP_DEBUG_FILE:-} ]]; then
        echo "$*" >> "\${BASH_COMP_DEBUG_FILE}"
    fi
}

# Function to handle completions
__${r}_complete() {
    local cur prev words cword
    _get_comp_words_by_ref -n "=:" cur prev words cword

    local requestComp out directive
    
    # Build the command to get completions
    requestComp="${n} complete -- \${words[@]:1}"
    
    # Add an empty parameter if the last parameter is complete
    if [[ -z "$cur" ]]; then
        requestComp="$requestComp ''"
    fi
    
    # Get completions from the program
    out=$(eval "$requestComp" 2>/dev/null)
    
    # Extract directive if present
    directive=0
    if [[ "$out" == *:* ]]; then
        directive=\${out##*:}
        out=\${out%:*}
    fi
    
    # Process completions based on directive
    if [[ $((directive & $ShellCompDirectiveError)) -ne 0 ]]; then
        # Error, no completion
        return
    fi
    
    # Apply directives
    if [[ $((directive & $ShellCompDirectiveNoSpace)) -ne 0 ]]; then
        compopt -o nospace
    fi
    if [[ $((directive & $ShellCompDirectiveKeepOrder)) -ne 0 ]]; then
        compopt -o nosort
    fi
    if [[ $((directive & $ShellCompDirectiveNoFileComp)) -ne 0 ]]; then
        compopt +o default
    fi
    
    # Handle file extension filtering
    if [[ $((directive & $ShellCompDirectiveFilterFileExt)) -ne 0 ]]; then
        local filter=""
        for ext in $out; do
            filter="$filter|$ext"
        done
        filter="\\.($filter)"
        compopt -o filenames
        COMPREPLY=( $(compgen -f -X "!$filter" -- "$cur") )
        return
    fi
    
    # Handle directory filtering
    if [[ $((directive & $ShellCompDirectiveFilterDirs)) -ne 0 ]]; then
        compopt -o dirnames
        COMPREPLY=( $(compgen -d -- "$cur") )
        return
    fi
    
    # Process completions
    local IFS=$'\\n'
    local tab=$(printf '\\t')
    
    # Parse completions with descriptions
    local completions=()
    while read -r comp; do
        if [[ "$comp" == *$tab* ]]; then
            # Split completion and description
            local value=\${comp%%$tab*}
            local desc=\${comp#*$tab}
            completions+=("$value")
        else
            completions+=("$comp")
        fi
    done <<< "$out"
    
    # Return completions
    COMPREPLY=( $(compgen -W "\${completions[*]}" -- "$cur") )
}

# Register completion function
complete -F __${r}_complete ${t}
`;
}
function r(t, n) {
	let r = t.replace(/[-:]/g, `_`), i = a.ShellCompDirectiveError, a$1 = a.ShellCompDirectiveNoSpace, o = a.ShellCompDirectiveNoFileComp, s = a.ShellCompDirectiveFilterFileExt, c = a.ShellCompDirectiveFilterDirs;
	return `# fish completion for ${t} -*- shell-script -*-

function __${r}_debug
    set -l file "$BASH_COMP_DEBUG_FILE"
    if test -n "$file"
        echo "$argv" >> $file
    end
end

function __${r}_perform_completion
    __${r}_debug "Starting __${r}_perform_completion"

    # Extract all args except the last one
    set -l args (commandline -opc)
    # Extract the token currently being completed (may be empty on a trailing space)
    set -l lastArg (commandline -ct)

    __${r}_debug "args: $args"
    __${r}_debug "last arg: $lastArg"

    # Pass each arg as its own token (no string join/eval, which would collapse multi-segment paths); quote "$lastArg" so an empty trailing token is still sent.
    __${r}_debug "Calling ${n} complete -- $args[2..-1] $lastArg"
    set -l results (${n} complete -- $args[2..-1] "$lastArg" 2> /dev/null)

    # Some programs may output extra empty lines after the directive.
    # Let's ignore them or else it will break completion.
    # Ref: https://github.com/spf13/cobra/issues/1279
    for line in $results[-1..1]
        if test (string trim -- $line) = ""
            # Found an empty line, remove it
            set results $results[1..-2]
        else
            # Found non-empty line, we have our proper output
            break
        end
    end

    set -l comps $results[1..-2]
    set -l directiveLine $results[-1]

    # For Fish, when completing a flag with an = (e.g., <program> -n=<TAB>)
    # completions must be prefixed with the flag
    set -l flagPrefix (string match -r -- '-.*=' "$lastArg")

    __${r}_debug "Comps: $comps"
    __${r}_debug "DirectiveLine: $directiveLine"
    __${r}_debug "flagPrefix: $flagPrefix"

    for comp in $comps
        printf "%s%s\\n" "$flagPrefix" "$comp"
    end

    printf "%s\\n" "$directiveLine"
end

# This function limits calls to __${r}_perform_completion, by caching the result
function __${r}_perform_completion_once
    __${r}_debug "Starting __${r}_perform_completion_once"

    if test -n "$__${r}_perform_completion_once_result"
        __${r}_debug "Seems like a valid result already exists, skipping __${r}_perform_completion"
        return 0
    end

    set --global __${r}_perform_completion_once_result (__${r}_perform_completion)
    if test -z "$__${r}_perform_completion_once_result"
        __${r}_debug "No completions, probably due to a failure"
        return 1
    end

    __${r}_debug "Performed completions and set __${r}_perform_completion_once_result"
    return 0
end

# This function is used to clear the cached result after completions are run
function __${r}_clear_perform_completion_once_result
    __${r}_debug ""
    __${r}_debug "========= clearing previously set __${r}_perform_completion_once_result variable =========="
    set --erase __${r}_perform_completion_once_result
    __${r}_debug "Successfully erased the variable __${r}_perform_completion_once_result"
end

function __${r}_requires_order_preservation
    __${r}_debug ""
    __${r}_debug "========= checking if order preservation is required =========="

    __${r}_perform_completion_once
    if test -z "$__${r}_perform_completion_once_result"
        __${r}_debug "Error determining if order preservation is required"
        return 1
    end

    set -l directive (string sub --start 2 $__${r}_perform_completion_once_result[-1])
    __${r}_debug "Directive is: $directive"

    set -l shellCompDirectiveKeepOrder ${a.ShellCompDirectiveKeepOrder}
    set -l keeporder (math (math --scale 0 $directive / $shellCompDirectiveKeepOrder) % 2)
    __${r}_debug "Keeporder is: $keeporder"

    if test $keeporder -ne 0
        __${r}_debug "This does require order preservation"
        return 0
    end

    __${r}_debug "This doesn't require order preservation"
    return 1
end

# This function does two things:
# - Obtain the completions and store them in the global __${r}_comp_results
# - Return false if file completion should be performed
function __${r}_prepare_completions
    __${r}_debug ""
    __${r}_debug "========= starting completion logic =========="

    # Start fresh
    set --erase __${r}_comp_results

    __${r}_perform_completion_once
    __${r}_debug "Completion results: $__${r}_perform_completion_once_result"

    if test -z "$__${r}_perform_completion_once_result"
        __${r}_debug "No completion, probably due to a failure"
        # Might as well do file completion, in case it helps
        return 1
    end

    set -l directive (string sub --start 2 $__${r}_perform_completion_once_result[-1])
    set --global __${r}_comp_results $__${r}_perform_completion_once_result[1..-2]

    __${r}_debug "Completions are: $__${r}_comp_results"
    __${r}_debug "Directive is: $directive"

    set -l shellCompDirectiveError ${i}
    set -l shellCompDirectiveNoSpace ${a$1}
    set -l shellCompDirectiveNoFileComp ${o}
    set -l shellCompDirectiveFilterFileExt ${s}
    set -l shellCompDirectiveFilterDirs ${c}

    if test -z "$directive"
        set directive 0
    end

    set -l compErr (math (math --scale 0 $directive / $shellCompDirectiveError) % 2)
    if test $compErr -eq 1
        __${r}_debug "Received error directive: aborting."
        # Might as well do file completion, in case it helps
        return 1
    end

    set -l filefilter (math (math --scale 0 $directive / $shellCompDirectiveFilterFileExt) % 2)
    set -l dirfilter (math (math --scale 0 $directive / $shellCompDirectiveFilterDirs) % 2)
    if test $filefilter -eq 1; or test $dirfilter -eq 1
        __${r}_debug "File extension filtering or directory filtering not supported"
        # Do full file completion instead
        return 1
    end

    set -l nospace (math (math --scale 0 $directive / $shellCompDirectiveNoSpace) % 2)
    set -l nofiles (math (math --scale 0 $directive / $shellCompDirectiveNoFileComp) % 2)

    __${r}_debug "nospace: $nospace, nofiles: $nofiles"

    # If we want to prevent a space, or if file completion is NOT disabled,
    # we need to count the number of valid completions.
    # To do so, we will filter on prefix as the completions we have received
    # may not already be filtered so as to allow fish to match on different
    # criteria than the prefix.
    if test $nospace -ne 0; or test $nofiles -eq 0
        set -l prefix (commandline -t | string escape --style=regex)
        __${r}_debug "prefix: $prefix"

        set -l completions (string match -r -- "^$prefix.*" $__${r}_comp_results)
        set --global __${r}_comp_results $completions
        __${r}_debug "Filtered completions are: $__${r}_comp_results"

        # Important not to quote the variable for count to work
        set -l numComps (count $__${r}_comp_results)
        __${r}_debug "numComps: $numComps"

        if test $numComps -eq 1; and test $nospace -ne 0
            # We must first split on \\t to get rid of the descriptions to be
            # able to check what the actual completion will be.
            # We don't need descriptions anyway since there is only a single
            # real completion which the shell will expand immediately.
            set -l split (string split --max 1 "\\t" $__${r}_comp_results[1])

            # Fish won't add a space if the completion ends with any
            # of the following characters: @=/:.,
            set -l lastChar (string sub -s -1 -- $split)
            if not string match -r -q "[@=/:.,]" -- "$lastChar"
                # In other cases, to support the "nospace" directive we trick the shell
                # by outputting an extra, longer completion.
                __${r}_debug "Adding second completion to perform nospace directive"
                set --global __${r}_comp_results $split[1] $split[1].
                __${r}_debug "Completions are now: $__${r}_comp_results"
            end
        end

        if test $numComps -eq 0; and test $nofiles -eq 0
            # To be consistent with bash and zsh, we only trigger file
            # completion when there are no other completions
            __${r}_debug "Requesting file completion"
            return 1
        end
    end

    return 0
end

# Since Fish completions are only loaded once the user triggers them, we trigger them ourselves
# so we can properly delete any completions provided by another script.
# Only do this if the program can be found, or else fish may print some errors; besides,
# the existing completions will only be loaded if the program can be found.
if type -q "${t}"
    # The space after the program name is essential to trigger completion for the program
    # and not completion of the program name itself.
    # Also, we use '> /dev/null 2>&1' since '&>' is not supported in older versions of fish.
    complete --do-complete "${t} " > /dev/null 2>&1
end

# Remove any pre-existing completions for the program since we will be handling all of them.
complete -c ${t} -e

# This will get called after the two calls below and clear the cached result
complete -c ${t} -n '__${r}_clear_perform_completion_once_result'
# The call to __${r}_prepare_completions will setup __${r}_comp_results
# which provides the program's completion choices.
# If this doesn't require order preservation, we don't use the -k flag
complete -c ${t} -n 'not __${r}_requires_order_preservation && __${r}_prepare_completions' -f -a '$__${r}_comp_results'
# Otherwise we use the -k flag
complete -k -c ${t} -n '__${r}_requires_order_preservation && __${r}_prepare_completions' -f -a '$__${r}_comp_results'
`;
}
function i$1(t, n) {
	let r = t.replace(/[-:]/g, `_`);
	return `# powershell completion for ${t} -*- shell-script -*-

  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    function __${t}_debug {
        if ($env:BASH_COMP_DEBUG_FILE) {
            "$args" | Out-File -Append -FilePath "$env:BASH_COMP_DEBUG_FILE"
        }
    }

    filter __${t}_escapeStringWithSpecialChars {
        $_ -replace '\\s|#|@|\\$|;|,|''|\\{|\\}|\\(|\\)|"|\\||<|>|&','\`$&'
    }

[scriptblock]$__${r}CompleterBlock = {
    param(
            $WordToComplete,
            $CommandAst,
            $CursorPosition
        )

    # Get the current command line and convert into a string
    $Command = $CommandAst.CommandElements
    $Command = "$Command"

    __${t}_debug ""
    __${t}_debug "========= starting completion logic =========="
    __${t}_debug "WordToComplete: $WordToComplete Command: $Command CursorPosition: $CursorPosition"

    # The user could have moved the cursor backwards on the command-line.
    # We need to trigger completion from the $CursorPosition location, so we need
    # to truncate the command-line ($Command) up to the $CursorPosition location.
    # Make sure the $Command is longer then the $CursorPosition before we truncate.
    # This happens because the $Command does not include the last space.
    if ($Command.Length -gt $CursorPosition) {
        $Command = $Command.Substring(0, $CursorPosition)
    }
    __${t}_debug "Truncated command: $Command"

    $ShellCompDirectiveError=${a.ShellCompDirectiveError}
    $ShellCompDirectiveNoSpace=${a.ShellCompDirectiveNoSpace}
    $ShellCompDirectiveNoFileComp=${a.ShellCompDirectiveNoFileComp}
    $ShellCompDirectiveFilterFileExt=${a.ShellCompDirectiveFilterFileExt}
    $ShellCompDirectiveFilterDirs=${a.ShellCompDirectiveFilterDirs}
    $ShellCompDirectiveKeepOrder=${a.ShellCompDirectiveKeepOrder}

    # Prepare the command to request completions for the program.
    # Split the command at the first space to separate the program and arguments.
    $Program, $Arguments = $Command.Split(" ", 2)

    $QuotedArgs = ($Arguments -split ' ' | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ' '
    __${t}_debug "QuotedArgs: $QuotedArgs"

    $RequestComp = "& ${n} complete '--' $QuotedArgs"
    __${t}_debug "RequestComp: $RequestComp"

    # we cannot use $WordToComplete because it
    # has the wrong values if the cursor was moved
    # so use the last argument
    if ($WordToComplete -ne "" ) {
        $WordToComplete = $Arguments.Split(" ")[-1]
    }
    __${t}_debug "New WordToComplete: $WordToComplete"


    # Check for flag with equal sign
    $IsEqualFlag = ($WordToComplete -Like "--*=*" )
    if ( $IsEqualFlag ) {
        __${t}_debug "Completing equal sign flag"
        # Remove the flag part
        $Flag, $WordToComplete = $WordToComplete.Split("=", 2)
    }
    $HasTrailingEmptyArg = $QuotedArgs -match "(^| )''$"
    __${t}_debug "HasTrailingEmptyArg: $HasTrailingEmptyArg"
    
    if ( $WordToComplete -eq "" -And ( -Not $IsEqualFlag ) -And ( -Not $HasTrailingEmptyArg )) {
        # If the last parameter is complete (there is a space following it)
        # We add an extra empty parameter so we can indicate this to the go method.
        __${t}_debug "Adding extra empty parameter"
        # PowerShell 7.2+ changed the way how the arguments are passed to executables,
        # so for pre-7.2 or when Legacy argument passing is enabled we need to use
        if ($PSVersionTable.PsVersion -lt [version]'7.2.0' -or
            ($PSVersionTable.PsVersion -lt [version]'7.3.0' -and -not [ExperimentalFeature]::IsEnabled("PSNativeCommandArgumentPassing")) -or
            (($PSVersionTable.PsVersion -ge [version]'7.3.0' -or [ExperimentalFeature]::IsEnabled("PSNativeCommandArgumentPassing")) -and
              $PSNativeCommandArgumentPassing -eq 'Legacy')) {
             $RequestComp="$RequestComp" + ' \`"\`"'
        } else {
             $RequestComp = "$RequestComp" + ' ""'
        }
    }

    __${t}_debug "Calling $RequestComp"
    # First disable ActiveHelp which is not supported for Powershell
    $env:ActiveHelp = 0

    # call the command store the output in $out and redirect stderr and stdout to null
    # $Out is an array contains each line per element
    Invoke-Expression -OutVariable out "$RequestComp" 2>&1 | Out-Null

    # get directive from last line
    [int]$Directive = $Out[-1].TrimStart(':')
    if ($Directive -eq "") {
        # There is no directive specified
        $Directive = 0
    }
    __${t}_debug "The completion directive is: $Directive"

    # remove directive (last element) from out
    $Out = $Out | Where-Object { $_ -ne $Out[-1] }
    __${t}_debug "The completions are: $Out"

    if (($Directive -band $ShellCompDirectiveError) -ne 0 ) {
        # Error code.  No completion.
        __${t}_debug "Received error from custom completion go code"
        return
    }

    $Longest = 0
    [Array]$Values = $Out | ForEach-Object {
        # Split the output in name and description
        $Name, $Description = $_.Split("\`t", 2)
        __${t}_debug "Name: $Name Description: $Description"

        # Look for the longest completion so that we can format things nicely
        if ($Longest -lt $Name.Length) {
            $Longest = $Name.Length
        }

        # Set the description to a one space string if there is none set.
        # This is needed because the CompletionResult does not accept an empty string as argument
        if (-Not $Description) {
            $Description = " "
        }
        @{ Name = "$Name"; Description = "$Description" }
    }


    $Space = " "
    if (($Directive -band $ShellCompDirectiveNoSpace) -ne 0 ) {
        # remove the space here
        __${t}_debug "ShellCompDirectiveNoSpace is called"
        $Space = ""
    }

    if ((($Directive -band $ShellCompDirectiveFilterFileExt) -ne 0 ) -or
       (($Directive -band $ShellCompDirectiveFilterDirs) -ne 0 ))  {
        __${t}_debug "ShellCompDirectiveFilterFileExt ShellCompDirectiveFilterDirs are not supported"

        # return here to prevent the completion of the extensions
        return
    }

    $Values = $Values | Where-Object {
        # filter the result
        $_.Name -like "$WordToComplete*"

        # Join the flag back if we have an equal sign flag
        if ( $IsEqualFlag ) {
            __${t}_debug "Join the equal sign flag back to the completion value"
            $_.Name = $Flag + "=" + $_.Name
        }
    }

    # we sort the values in ascending order by name if keep order isn't passed
    if (($Directive -band $ShellCompDirectiveKeepOrder) -eq 0 ) {
        $Values = $Values | Sort-Object -Property Name
    }

    if (($Directive -band $ShellCompDirectiveNoFileComp) -ne 0 ) {
        __${t}_debug "ShellCompDirectiveNoFileComp is called"

        if ($Values.Length -eq 0) {
            # Just print an empty string here so the
            # shell does not start to complete paths.
            # We cannot use CompletionResult here because
            # it does not accept an empty string as argument.
            ""
            return
        }
    }

    # Get the current mode
    $Mode = (Get-PSReadLineKeyHandler | Where-Object { $_.Key -eq "Tab" }).Function
    __${t}_debug "Mode: $Mode"

    $Values | ForEach-Object {

        # store temporary because switch will overwrite $_
        $comp = $_

        # PowerShell supports three different completion modes
        # - TabCompleteNext (default windows style - on each key press the next option is displayed)
        # - Complete (works like bash)
        # - MenuComplete (works like zsh)
        # You set the mode with Set-PSReadLineKeyHandler -Key Tab -Function <mode>

        # CompletionResult Arguments:
        # 1) CompletionText text to be used as the auto completion result
        # 2) ListItemText   text to be displayed in the suggestion list
        # 3) ResultType     type of completion result
        # 4) ToolTip        text for the tooltip with details about the object

        switch ($Mode) {

            # bash like
            "Complete" {

                if ($Values.Length -eq 1) {
                    __${t}_debug "Only one completion left"

                    # insert space after value
                    [System.Management.Automation.CompletionResult]::new($($comp.Name | __${t}_escapeStringWithSpecialChars) + $Space, "$($comp.Name)", 'ParameterValue', "$($comp.Description)")

                } else {
                    # Add the proper number of spaces to align the descriptions
                    while($comp.Name.Length -lt $Longest) {
                        $comp.Name = $comp.Name + " "
                    }

                    # Check for empty description and only add parentheses if needed
                    if ($($comp.Description) -eq " " ) {
                        $Description = ""
                    } else {
                        $Description = "  ($($comp.Description))"
                    }

                    [System.Management.Automation.CompletionResult]::new("$($comp.Name)$Description", "$($comp.Name)$Description", 'ParameterValue', "$($comp.Description)")
                }
             }

            # zsh like
            "MenuComplete" {
                # insert space after value
                # MenuComplete will automatically show the ToolTip of
                # the highlighted value at the bottom of the suggestions.
                [System.Management.Automation.CompletionResult]::new($($comp.Name | __${t}_escapeStringWithSpecialChars) + $Space, "$($comp.Name)", 'ParameterValue', "$($comp.Description)")
            }

            # TabCompleteNext and in case we get something unknown
            Default {
                # Like MenuComplete but we don't want to add a space here because
                # the user need to press space anyway to get the completion.
                # Description will not be shown because that's not possible with TabCompleteNext
                [System.Management.Automation.CompletionResult]::new($($comp.Name | __${t}_escapeStringWithSpecialChars), "$($comp.Name)", 'ParameterValue', "$($comp.Description)")
            }
        }

    }
}

Register-ArgumentCompleter -CommandName '${t}' -ScriptBlock $__${r}CompleterBlock
`;
}
//#endregion
//#region node_modules/.pnpm/@bomb.sh+tab@0.0.22/node_modules/@bomb.sh/tab/dist/index.mjs
const a = {
	ShellCompDirectiveError: 1,
	ShellCompDirectiveNoSpace: 2,
	ShellCompDirectiveNoFileComp: 4,
	ShellCompDirectiveFilterFileExt: 8,
	ShellCompDirectiveFilterDirs: 16,
	ShellCompDirectiveKeepOrder: 32,
	shellCompDirectiveMaxValue: 64,
	ShellCompDirectiveDefault: 0
};
var o = class {
	name;
	variadic;
	command;
	handler;
	constructor(e, t, n, r = !1) {
		this.command = e, this.name = t, this.handler = n, this.variadic = r;
	}
};
var s = class {
	value;
	description;
	command;
	handler;
	alias;
	isBoolean;
	constructor(e, t, n, r, i, a) {
		this.command = e, this.value = t, this.description = n, this.handler = r, this.alias = i, this.isBoolean = a;
	}
};
var c = class {
	value;
	description;
	options = /* @__PURE__ */ new Map();
	arguments = /* @__PURE__ */ new Map();
	parent;
	constructor(e, t) {
		this.value = e, this.description = t;
	}
	option(e, t, n, r) {
		let i, a, o;
		typeof n == `function` ? (i = n, a = r, o = !1) : typeof n == `string` ? (i = void 0, a = n, o = !0) : (i = void 0, a = void 0, o = !0);
		let c = new s(this, e, t, i, a, o);
		return this.options.set(e, c), this;
	}
	argument(e, t, n = !1) {
		let r = new o(this, e, t, n);
		return this.arguments.set(e, r), this;
	}
};
var l = class extends c {
	commands = /* @__PURE__ */ new Map();
	completions = [];
	directive = a.ShellCompDirectiveDefault;
	constructor() {
		super(``, ``);
	}
	command(e, t) {
		let n = new c(e, t);
		return this.commands.set(e, n), n;
	}
	stripOptions(e) {
		let t = [], n = 0;
		for (; n < e.length;) {
			let r = e[n];
			if (r.startsWith(`-`)) {
				n++;
				let t = !1, i = this.findOption(this, r);
				if (i) t = i.isBoolean ?? !1;
				else for (let [, e] of this.commands) {
					let n = this.findOption(e, r);
					if (n) {
						t = n.isBoolean ?? !1;
						break;
					}
				}
				!t && n < e.length && !e[n].startsWith(`-`) && n++;
			} else t.push(r), n++;
		}
		return t;
	}
	matchCommand(e) {
		e = this.stripOptions(e);
		let t = [], n = [], r = null;
		for (let i = 0; i < e.length; i++) {
			let a = e[i];
			t.push(a);
			let o = this.commands.get(t.join(` `));
			if (o) r = o;
			else {
				n = e.slice(i, e.length);
				break;
			}
		}
		return [r || this, n];
	}
	shouldCompleteFlags(e, t) {
		if (t.startsWith(`-`)) return !0;
		if (e?.startsWith(`-`)) {
			let t = this.findOption(this, e);
			if (!t) {
				for (let [, n] of this.commands) if (t = this.findOption(n, e), t) break;
			}
			return !(t && t.isBoolean);
		}
		return !1;
	}
	shouldCompleteCommands(e) {
		return !e.startsWith(`-`);
	}
	handleFlagCompletion(e, t, n, r) {
		let i;
		if (n.includes(`=`)) {
			let [e] = n.split(`=`);
			i = e;
		} else if (r?.startsWith(`-`)) {
			let t = this.findOption(e, r);
			t && !t.isBoolean && (i = r);
		}
		if (i) {
			let t = this.findOption(e, i);
			if (t?.handler) {
				let n = [];
				t.handler.call(t, (e, t) => n.push({
					value: e,
					description: t
				}), e.options), this.completions = n;
			}
			return;
		}
		if (n.startsWith(`-`)) {
			let t = n.startsWith(`-`) && !n.startsWith(`--`), r = n.replace(/^-+/, ``);
			for (let [i, a] of e.options) t && a.alias && `-${a.alias}`.startsWith(n) ? this.completions.push({
				value: `-${a.alias}`,
				description: a.description
			}) : !t && i.startsWith(r) && this.completions.push({
				value: `--${i}`,
				description: a.description
			});
		}
	}
	findOption(e, t) {
		let n = e.options.get(t);
		if (n || (n = e.options.get(t.replace(/^-+/, ``)), n)) return n;
		for (let [n, r] of e.options) if (r.alias && `-${r.alias}` === t) return r;
	}
	handleCommandCompletion(e, t) {
		let n = this.stripOptions(e);
		for (let [e, r] of this.commands) {
			if (e === ``) continue;
			let i = e.split(` `);
			i.slice(0, n.length).every((e, t) => e === n[t]) && i[n.length]?.startsWith(t) && this.completions.push({
				value: i[n.length],
				description: r.description
			});
		}
	}
	handlePositionalCompletion(e, t) {
		let n = this.stripOptions(t), r = e.value.split(` `).length, i = Math.max(0, n.length - r), a = Array.from(e.arguments.entries());
		if (a.length > 0) {
			let t;
			if (i < a.length) {
				let [e, n] = a[i];
				t = n;
			} else {
				let e = a[a.length - 1][1];
				e.variadic && (t = e);
			}
			if (t && t.handler && typeof t.handler == `function`) {
				let n = [];
				t.handler.call(t, (e, t) => n.push({
					value: e,
					description: t
				}), e.options), this.completions.push(...n);
			}
		}
	}
	complete(e) {
		this.directive = a.ShellCompDirectiveNoFileComp;
		let t = /* @__PURE__ */ new Set();
		this.completions.filter((e) => t.has(e.value) ? !1 : (t.add(e.value), !0)).filter((t) => {
			if (e.includes(`=`)) {
				let [, n] = e.split(`=`);
				return t.value.startsWith(n);
			}
			return t.value.startsWith(e);
		}).forEach((e) => console.log(`${e.value}\t${e.description ?? ``}`)), console.log(`:${this.directive}`);
	}
	parse(e) {
		this.completions = [];
		let t = e[e.length - 1] === ``;
		t && e.pop();
		let n = e[e.length - 1] || ``, r = e.slice(0, -1);
		t && (n !== `` && r.push(n), n = ``);
		let [i] = this.matchCommand(r), a = r[r.length - 1];
		this.shouldCompleteFlags(a, n) ? this.handleFlagCompletion(i, r, n, a) : (this.shouldCompleteCommands(n) && this.handleCommandCompletion(r, n), i && i.arguments.size > 0 && this.handlePositionalCompletion(i, r)), this.complete(n);
	}
	setup(a, o, s) {
		switch (i(s === `zsh` || s === `bash` || s === `fish` || s === `powershell`, `Unsupported shell`), s) {
			case `zsh`: {
				let t$1 = t(a, o);
				console.log(t$1);
				break;
			}
			case `bash`: {
				let e = n(a, o);
				console.log(e);
				break;
			}
			case `fish`: {
				let e = r(a, o);
				console.log(e);
				break;
			}
			case `powershell`: {
				let e = i$1(a, o);
				console.log(e);
				break;
			}
		}
	}
};
new l();
//#endregion
//#region node_modules/.pnpm/@gunshi+plugin@0.37.3/node_modules/@gunshi/plugin/lib/index.js
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
const ANONYMOUS_COMMAND_NAME = "(anonymous)";
/**
* A no-operation function.
*/
const NOOP = () => {};
const CLI_OPTIONS_DEFAULT = {
	name: void 0,
	description: void 0,
	version: void 0,
	cwd: void 0,
	usageSilent: false,
	subCommands: void 0,
	leftMargin: 2,
	middleMargin: 10,
	usageOptionType: false,
	usageOptionValue: true,
	strict: false,
	renderHeader: void 0,
	renderUsage: void 0,
	renderValidationErrors: void 0,
	plugins: void 0,
	fallbackToEntry: false
};
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Check if the given command is a {@link LazyCommand}.
*
* @param cmd - A command to check
* @returns `true` if the command is a {@link LazyCommand}, otherwise `false
*/
function isLazyCommand$1(cmd) {
	return typeof cmd === "function" && "commandName" in cmd && !!cmd.commandName;
}
/**
* Create an object with the specified prototype. A shorthand for `Object.create`.
*
* @param obj - An object to use as the prototype for the new object. If `null`, it will create an object with no prototype.
* @returns A new object with the specified prototype
*/
function create$1(obj = null) {
	return Object.create(obj);
}
/**
* Log a message to the console.
*
* @param args - Arguments to log
*/
function log(...args) {
	console.log(...args);
}
/**
* Deep freeze an object, making it immutable.
*
* @param obj - The object to freeze
* @param ignores - Properties to ignore during freezing
* @returns A frozen object
*/
function deepFreeze$1(obj, ignores = []) {
	if (obj === null || typeof obj !== "object") return obj;
	for (const key of Object.keys(obj)) {
		const value = obj[key];
		if (ignores.includes(key)) continue;
		if (typeof value === "object" && value !== null) deepFreeze$1(value, ignores);
	}
	return Object.freeze(obj);
}
/**
* The entry for gunshi context.
* This module is exported for the purpose of testing the command.
*
* @example
* ```js
* import { createCommandContext } from 'gunshi/context'
* ```
*
* @module
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Create a command context.
*
* @param param - A {@link CommandContextParams | parameters} to create a command context.
* @returns A {@link CommandContext | command context}, which is readonly.
*/
async function createCommandContext({ args = {}, explicit = {}, values = {}, positionals = [], rest = [], argv = [], tokens = [], command = {}, extensions = {}, cliOptions = {}, callMode = "entry", commandPath = [], omitted = false, validationError }) {
	/**
	* normailize the options schema and values, to avoid prototype pollution
	*/
	const _args = Object.entries(args).reduce((acc, [key, value]) => {
		acc[key] = Object.assign(create$1(), value);
		return acc;
	}, create$1());
	/**
	* setup the environment
	*/
	const env = Object.assign(create$1(), CLI_OPTIONS_DEFAULT, cliOptions);
	/**
	* apply Command definition's rendering option with highest priority
	*/
	if (command.rendering) {
		const { header, usage, validationErrors } = command.rendering;
		if (header !== void 0) env.renderHeader = header;
		if (usage !== void 0) env.renderUsage = usage;
		if (validationErrors !== void 0) env.renderValidationErrors = validationErrors;
	}
	/**
	* create the command context
	*/
	const core = Object.assign(create$1(), {
		name: getCommandName(command),
		description: command.description,
		omitted,
		callMode,
		commandPath,
		env,
		args: _args,
		explicit,
		values,
		positionals,
		rest,
		_: argv,
		tokens,
		toKebab: command.toKebab,
		log: cliOptions.usageSilent ? NOOP : log,
		validationError
	});
	/**
	* extend the command context with extensions
	*/
	if (Object.keys(extensions).length > 0) {
		const ext = create$1(null);
		Object.defineProperty(core, "extensions", {
			value: ext,
			writable: false,
			enumerable: true,
			configurable: true
		});
		for (const [key, extension] of Object.entries(extensions)) {
			ext[key] = await extension.factory(core, command);
			if (extension.onFactory) await extension.onFactory(core, command);
		}
	}
	return deepFreeze$1(core, ["extensions"]);
}
function getCommandName(cmd) {
	if (isLazyCommand$1(cmd)) return cmd.commandName || cmd.name || "(anonymous)";
	else if (typeof cmd === "object") return cmd.name || "(anonymous)";
	else return ANONYMOUS_COMMAND_NAME;
}
/**
* forked from `nodejs/node` (`pkgjs/parseargs`)
* repository url: https://github.com/nodejs/node (https://github.com/pkgjs/parseargs)
* code url: https://github.com/nodejs/node/blob/main/lib/internal/util/parse_args/parse_args.js
*
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
"-".codePointAt(0);
"=".codePointAt(0);
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
const NOOP_EXTENSION = () => {
	return Object.create(null);
};
/**
* Define a plugin
*
* @param options - {@linkcode PluginOptions | plugin options}
* @returns A defined plugin
*
* @since v0.27.0
*/
function plugin(options = {}) {
	const { id, name, setup, onExtension, dependencies } = options;
	const extension = options.extension || NOOP_EXTENSION;
	const pluginFn = async (ctx) => {
		if (setup) await setup(ctx);
	};
	const props = {
		writable: false,
		enumerable: true,
		configurable: true
	};
	return Object.defineProperties(pluginFn, {
		id: {
			value: id,
			...props
		},
		...name && { name: {
			value: name,
			...props
		} },
		...dependencies && { dependencies: {
			value: dependencies,
			...props
		} },
		...extension && { extension: {
			value: {
				key: Symbol(id),
				factory: extension,
				onFactory: onExtension
			},
			...props
		} }
	});
}
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
//#endregion
//#region node_modules/.pnpm/@gunshi+plugin-completion@0.37.3_@gunshi+plugin-i18n@0.37.3/node_modules/@gunshi/plugin-completion/lib/index.js
/*! license ISC 
* @author Bombshell team and Bombshell contributors
* Bombshell related codes are forked from @bombsh/tab
*/
/**
* Entry point of utils.
*
* Note that this entry point is used by gunshi to import utility functions.
*
* @module
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Convert a string to kebab-case.
*
* @param str - A string to convert
* @returns Converted string into kebab-case.
*/
function kebabnize(str) {
	return str.replace(/[A-Z]/g, (match, offset) => (offset > 0 ? "-" : "") + match.toLowerCase());
}
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Check if the given command is a {@link LazyCommand}.
*
* @param cmd - A command to check
* @returns `true` if the command is a {@link LazyCommand}, otherwise `false
*/
function isLazyCommand(cmd) {
	return typeof cmd === "function" && "commandName" in cmd && !!cmd.commandName;
}
/**
* Resolve a lazy command to a {@link Command}.
*
* @param cmd - A {@link Commandable} or {@link LazyCommand} to resolve
* @param name - Optional name of the command, if not provided, it will use the name from the command itself.
* @param needRunResolving - Whether to run the resolving function of the lazy command.
* @returns A resolved {@link Command}
*/
async function resolveLazyCommand(cmd, name, needRunResolving = false) {
	let command;
	if (isLazyCommand(cmd)) {
		const baseCommand = {
			name: cmd.commandName,
			description: cmd.description,
			args: cmd.args,
			examples: cmd.examples,
			internal: cmd.internal,
			entry: cmd.entry,
			subCommands: cmd.subCommands
		};
		if ("resource" in cmd && cmd.resource) baseCommand.resource = cmd.resource;
		command = Object.assign(create(), baseCommand);
		if (needRunResolving) {
			const loaded = await cmd();
			if (typeof loaded === "function") command.run = loaded;
			else if (typeof loaded === "object") {
				if (loaded.run == null) throw new TypeError(`'run' is required in command: ${cmd.name || name}`);
				command.run = loaded.run;
				command.name = loaded.name;
				command.description = loaded.description;
				command.args = loaded.args;
				command.examples = loaded.examples;
				command.internal = loaded.internal;
				command.entry = loaded.entry;
				command.subCommands = loaded.subCommands || cmd.subCommands;
				if ("resource" in loaded && loaded.resource) command.resource = loaded.resource;
			} else throw new TypeError(`Cannot resolve command: ${cmd.name || name}`);
		}
	} else command = Object.assign(create(), cmd);
	if (command.name == null && name) command.name = name;
	return deepFreeze(command);
}
/**
* Create an object with the specified prototype. A shorthand for `Object.create`.
*
* @param obj - An object to use as the prototype for the new object. If `null`, it will create an object with no prototype.
* @returns A new object with the specified prototype
*/
function create(obj = null) {
	return Object.create(obj);
}
/**
* Deep freeze an object, making it immutable.
*
* @param obj - The object to freeze
* @param ignores - Properties to ignore during freezing
* @returns A frozen object
*/
function deepFreeze(obj, ignores = []) {
	if (obj === null || typeof obj !== "object") return obj;
	for (const key of Object.keys(obj)) {
		const value = obj[key];
		if (ignores.includes(key)) continue;
		if (typeof value === "object" && value !== null) deepFreeze(value, ignores);
	}
	return Object.freeze(obj);
}
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
const BUILD_IN_PREFIX_AND_KEY_SEPARATOR = `_:`;
const ARG_PREFIX_AND_KEY_SEPARATOR = `arg:`;
const ERROR_PREFIX_AND_KEY_SEPARATOR = `err:`;
var en_US_default = {
	COMMAND: "COMMAND",
	COMMANDS: "COMMANDS",
	SUBCOMMAND: "SUBCOMMAND",
	USAGE: "USAGE",
	ARGUMENTS: "ARGUMENTS",
	OPTIONS: "OPTIONS",
	EXAMPLES: "EXAMPLES",
	FORMORE: "For more info, run any command with the `--help` flag",
	NEGATABLE: "Negatable of",
	DEFAULT: "default",
	CHOICES: "choices",
	help: "Display this help message",
	version: "Display this version",
	"err:arg:required-option": "Optional argument {$displayName} is required",
	"err:arg:required-positional": "Positional argument {$name} is required",
	"err:arg:invalid-type": "Invalid value for {$displayName}: expected {$expected}",
	"err:arg:invalid-choice": "Invalid value for {$displayName}: expected one of {$choices}",
	"err:arg:custom-parse": "Invalid value for {$displayName}: {$reason}",
	"err:arg:unknown-option": "Unknown option: {$rawName}",
	"err:cmd:not-found": "Command not found: {$commandName}",
	"err:suggestion:did-you-mean": "Did you mean {$name}?"
};
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Resolve a namespaced key for argument resources.
*
* Argument keys are prefixed with "arg:".
* If the command name is provided, it will be prefixed with the command name (e.g. "cmd1:arg:foo").
*
* @typeParam A - The {@linkcode Args} type extracted from G
*
* @param key - The argument key to resolve.
* @param name - The command name.
* @returns Prefixed argument key.
*/
function resolveArgKey(key, name) {
	return `${name ? `${name}:` : ""}arg:${key}`;
}
/**
* Resolve a namespaced key for non-built-in resources.
*
* Non-built-in keys are not prefixed with any special characters. If the command name is provided, it will be prefixed with the command name (e.g. "cmd1:foo").
*
* @typeParam T - The type of the non-built-in key to resolve. Defaults to string.
*
* @param key - The non-built-in key to resolve.
* @param name - The command name.
* @returns Prefixed non-built-in key.
*/
function resolveKey(key, name) {
	return `${name ? `${name}:` : ""}${key}`;
}
/**
* Resolve command examples.
*
* @typeParam G - Type parameter extending {@linkcode GunshiParams}
*
* @param ctx - A {@linkcode CommandContext | command context}.
* @param examples - The examples to resolve, which can be a string or a {@linkcode CommandExamplesFetcher | function} that returns a string.
* @returns A resolved string of examples.
*/
async function resolveExamples(ctx, examples) {
	return typeof examples === "string" ? examples : typeof examples === "function" ? await examples(ctx) : "";
}
/**
* Generate a namespaced key for a plugin.
*
* @typeParam K - The type of the plugin id to generate a namespaced key for.
*
* @param id - A plugin id to generate a namespaced key.
* @returns A namespaced key for the plugin.
*/
function namespacedId(id) {
	return `g:${id}`;
}
/**
* Generate a short and long option pair for command arguments.
*
* @param schema - The {@linkcode ArgSchema | argument schema} to generate the option pair.
* @param name - The name of the argument.
* @param toKebab - Whether to convert the name to kebab-case for display in help text.
* @returns A string representing the short and long option pair.
*/
function makeShortLongOptionPair(schema, name, toKebab) {
	let key = `--${toKebab || schema.toKebab ? kebabnize(name) : name}`;
	if (schema.short) key = `-${schema.short}, ${key}`;
	return key;
}
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* Create a localizable function for a command.
*
* This function will resolve the translation key based on the command context and the provided translation function.
*
* @typeParam A - The {@linkcode Args} type extracted from Gunshi command.
* @typeParam C - Additional context type for command localization.
* @typeParam E - Extended resource keys type.
*
* @param ctx - Command context
* @param cmd - Command
* @param translate - Translation function
* @returns Localizable function
*/
function localizable(ctx, cmd, translate) {
	async function localize(key, values) {
		if (translate) return translate(key, values);
		if (key.startsWith(BUILD_IN_PREFIX_AND_KEY_SEPARATOR)) return resolveAndFormatResource(key.slice(BUILD_IN_PREFIX_AND_KEY_SEPARATOR.length), key, values);
		if (key.startsWith(ERROR_PREFIX_AND_KEY_SEPARATOR)) return resolveAndFormatResource(key, key, values);
		const namaspacedArgKey = resolveKey(ARG_PREFIX_AND_KEY_SEPARATOR, ctx.name);
		if (key.startsWith(namaspacedArgKey)) {
			let argKey = key.slice(namaspacedArgKey.length);
			let negatable = false;
			if (argKey.startsWith("no-")) {
				argKey = argKey.slice(3);
				negatable = true;
			}
			const schema = ctx.args[argKey];
			if (!schema) return argKey;
			return negatable && schema.type === "boolean" && schema.negatable ? `${en_US_default["NEGATABLE"]} ${makeShortLongOptionPair(schema, argKey, ctx.toKebab)}` : schema.description || "";
		}
		if (key === resolveKey("description", ctx.name)) return "";
		else if (key === resolveKey("examples", ctx.name)) return await resolveExamples(ctx, cmd.examples);
		else return key;
	}
	return localize;
}
function resolveAndFormatResource(resourceKey, fallbackKey, values) {
	return formatResource(en_US_default[resourceKey], values) || fallbackKey;
}
/**
* Format a resource message by replacing placeholder values.
*
* @param resource - Resource message template
* @param values - Placeholder values
* @returns Formatted resource message
*/
function formatResource(resource, values = Object.create(null)) {
	return resource?.replaceAll(/\{\$(\w+)\}/g, (_, name) => {
		return values[name] == null ? "" : String(values[name]);
	});
}
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
/**
* The unique identifier for the completion plugin.
*/
const pluginId = namespacedId("completion");
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
function getRuntimeGlobals() {
	return globalThis;
}
/**
* Detect the active JavaScript runtime.
*
* @returns The detected runtime name
*/
function detectRuntime() {
	return detectRuntimeFromGlobals(getRuntimeGlobals());
}
/**
* Detect the active JavaScript runtime from globals.
*
* @param globals - Runtime globals to inspect
* @returns The detected runtime name
*/
function detectRuntimeFromGlobals(globals) {
	if (globals.Bun !== void 0) return "bun";
	if (globals.Deno !== void 0) return "deno";
	if (globals.process !== void 0 && globals.process.release?.name === "node") return "node";
	return "unknown";
}
/**
* Quote a shell command part when needed.
*
* This protects the command part when the generated completion script later
* evaluates the assembled command string. Callers that embed the quoted result
* into another shell string still need to escape that outer string.
*
* @param value - The command part to quote
* @returns The shell-safe command part
*/
function shellQuote(value) {
	if (value.length === 0) return "''";
	if (/^[\w%+,./:=@-]+$/.test(value)) return value;
	return `'${value.replaceAll(`'`, `'\\''`)}'`;
}
function escapeDoubleQuotedShellString(value) {
	return value.replaceAll(/[$`"\\]/g, "\\$&");
}
function basename(path) {
	const slash = path.lastIndexOf("/");
	const backslash = path.lastIndexOf("\\");
	return path.slice(Math.max(slash, backslash) + 1);
}
/**
* Check if the entry is a Bun virtual entry.
*
* @param entry - The entry to check
* @returns Whether the entry is a Bun virtual entry
*
* Bun compiled executables may surface internal virtual paths in `process.argv`
* instead of the original source entry. These markers are intentionally private
* to keep the single-binary check heuristic rather than a public contract.
*
* @see https://github.com/oven-sh/bun/blob/main/src/standalone_graph/StandaloneModuleGraph.rs#L44-L70
* @see https://github.com/oven-sh/bun/blob/main/test/regression/issue/22157.test.ts#L47-L55
*/
function isBunVirtualEntry(entry) {
	return entry?.startsWith("/$bunfs/") === true || entry?.startsWith("B:\\~BUN\\") === true || entry?.startsWith("B:/~BUN/") === true;
}
/**
* Check if the executable is a likely Bun single binary.
*
* @param execPath - The executable path
* @param entry - The entry to check
* @returns Whether the executable is a likely Bun single binary
*
* Bun documents `bun build --compile` as producing a single-file executable,
* but it does not expose a stable "compiled executable" runtime flag.
* Prefer calling the current executable when `process.execPath` is no longer
* the Bun launcher, because the shell completion script needs to re-enter the
* compiled CLI rather than the original source file.
*
* @see https://bun.com/docs/bundler/executables
* @see https://github.com/oven-sh/bun/issues/14676
*/
function isLikelyBunSingleBinary(execPath, entry) {
	const name = basename(execPath).toLowerCase();
	if (name !== "bun" && name !== "bun.exe") return true;
	return isBunVirtualEntry(entry);
}
/**
* Resolve executable command parts for Node.js source execution.
*
* @param process - Node-compatible process global
* @returns Executable command parts
*/
function resolveNodeExecParts(process) {
	const entry = process.argv[1];
	return [
		process.execPath,
		...process.execArgv ?? [],
		...entry ? [entry] : []
	];
}
/**
* Resolve executable command parts for Bun source and compiled execution.
*
* @param process - Bun process global
* @returns Executable command parts
*/
function resolveBunExecParts(process) {
	const entry = process.argv[1];
	if (isLikelyBunSingleBinary(process.execPath, entry)) return [process.execPath];
	return [
		process.execPath,
		...process.execArgv ?? [],
		...entry ? [entry] : []
	];
}
/**
* Join executable command parts into a shell-safe command string.
*
* @param parts - Executable command parts
* @returns The executable command string
*/
function joinExecParts(parts) {
	return escapeDoubleQuotedShellString(parts.map(shellQuote).join(" "));
}
/**
* Quote the exec command for the current runtime.
*
* @returns The quoted exec command string
*/
function quoteExec() {
	const globals = getRuntimeGlobals();
	switch (detectRuntime()) {
		case "node": return joinExecParts(resolveNodeExecParts(globals.process));
		case "deno": throw new Error("Deno runtime is not supported for completion script generation yet.");
		case "bun": return joinExecParts(resolveBunExecParts(globals.process));
		default: throw new Error("Unsupported JavaScript runtime for completion script generation.");
	}
}
/**
* The entry point of completion plugin
*
* @example
* ```js
* import { cli } from 'gunshi'
* import completion from '@gunshi/plugin-completion'
*
* const command = {
*   name: 'deploy',
*   args: {
*     environment: {
*       type: 'string',
*       short: 'e',
*       description: 'Target environment'
*     },
*     config: {
*       type: 'string',
*       short: 'c',
*       description: 'Config file path'
*     }
*   },
*   run: ctx => {
*     console.log(`Deploying to ${ctx.values.environment}`)
*   }
* }
*
* await cli(process.argv.slice(2), command, {
*   name: 'my-cli',
*   version: '1.0.0',
*   plugins: [
*     completion({
*       config: {
*         entry: {
*           args: {
*             config: {
*               handler: () => [
*                 { value: 'prod.json', description: 'Production config' },
*                 { value: 'dev.json', description: 'Development config' },
*                 { value: 'test.json', description: 'Test config' }
*               ]
*             }
*           }
*         }
*       }
*     })
*   ]
* })
* ```
*
* @module
*/
/**
* @author kazuya kawaguchi (a.k.a. kazupon)
* @license MIT
*/
const TERMINATOR = "--";
const NOOP_HANDLER = () => {
	return [];
};
const i18nPluginId = namespacedId("i18n");
const dependencies = [{
	id: i18nPluginId,
	optional: true
}];
/**
* completion plugin
*
* @param options - A {@linkcode CompletionOptions | Completion options}
* @returns A defined plugin as completion
*/
function completion(options = {}) {
	const config = options.config || {};
	const t = new l();
	return plugin({
		id: pluginId,
		name: "completion",
		dependencies,
		setup(ctx) {
			/**
			* add command for completion script generation
			*/
			const completeName = "complete";
			ctx.addCommand(completeName, {
				name: completeName,
				description: "Generate shell completion script",
				rendering: { header: null },
				run: (cmdCtx) => {
					if (!cmdCtx.env.name) throw new Error("your cli name is not defined.");
					let shell = cmdCtx._[1];
					if (shell === TERMINATOR) shell = void 0;
					if (shell === void 0) t.parse(cmdCtx._.slice(cmdCtx._.indexOf(TERMINATOR) + 1));
					else if ([
						"zsh",
						"bash",
						"fish",
						"powershell"
					].includes(shell)) t.setup(cmdCtx.env.name, quoteExec(), shell);
				}
			});
		},
		/**
		* setup bombshell completion with `onExtension` hook
		*/
		onExtension: async (ctx, cmd) => {
			const i18n = ctx.extensions[i18nPluginId];
			const subCommands = ctx.env.subCommands;
			await registerCompletion({
				name: "entry",
				cmd: [...subCommands].map(([_, cmd]) => cmd).find((cmd) => cmd.entry) || cmd,
				config,
				i18nPluginId,
				i18n,
				t,
				isBombshellRoot: true
			});
			await handleSubCommands(t, subCommands, i18nPluginId, config.subCommands, i18n);
		}
	});
}
async function registerCompletion({ name, cmd, config, i18nPluginId, i18n, t, isBombshellRoot = false }) {
	const resolvedCmd = await resolveLazyCommand(cmd);
	const extensions = Object.create(null);
	if (i18n) extensions[i18nPluginId] = {
		key: Symbol(i18nPluginId),
		factory: () => i18n
	};
	const ctx = await createCommandContext({
		args: resolvedCmd.args || Object.create(null),
		command: resolvedCmd,
		callMode: resolvedCmd.entry ? "entry" : "subCommand",
		extensions
	});
	if (i18n) {
		if (!await i18n.loadResource(i18n.locale, ctx, resolvedCmd)) console.warn(`Failed to load i18n resources for command: ${name} (${i18n.locale.toString()})`);
	}
	const localizeDescription = localizable(ctx, resolvedCmd, i18n ? i18n.translate : void 0);
	const commandTab = isBombshellRoot ? t : t.command(name, await localizeDescription(resolveKey("description", ctx.name)) || resolvedCmd.description || "");
	const args = resolvedCmd.args || Object.create(null);
	for (const [key, schema] of Object.entries(args)) if (schema.type === "positional") commandTab.argument(key, resolveCompletionHandler(name, key, config, i18n), schema.multiple);
	else commandTab.option(key, await localizeDescription(resolveArgKey(key, ctx.name)) || schema.description || "", resolveCompletionHandler(name, key, config, i18n), schema.short);
}
function resolveCompletionHandler(name, optionOrArgKey, config, i18n) {
	return function(complete) {
		const handler = config[name]?.args?.[optionOrArgKey]?.handler || NOOP_HANDLER;
		for (const item of handler({ locale: i18n?.locale })) complete(item.value, item.description || "");
	};
}
async function handleSubCommands(t, subCommands, i18nPluginId, config = {}, i18n, parentPath = "") {
	for (const [name, cmd] of subCommands) {
		if (cmd.internal || cmd.entry || name === "complete") continue;
		const fullName = parentPath ? `${parentPath} ${name}` : name;
		await registerCompletion({
			name: fullName,
			cmd,
			config,
			i18nPluginId,
			i18n,
			t
		});
		const nestedSubCommands = getNestedSubCommands(cmd);
		if (nestedSubCommands && nestedSubCommands.size > 0) await handleSubCommands(t, nestedSubCommands, i18nPluginId, config, i18n, fullName);
	}
}
function getNestedSubCommands(cmd) {
	const subCommands = typeof cmd === "function" ? cmd.subCommands : cmd.subCommands;
	if (!subCommands) return;
	if (subCommands instanceof Map) return subCommands.size > 0 ? subCommands : void 0;
	if (typeof subCommands === "object") {
		const entries = Object.entries(subCommands);
		if (entries.length === 0) return;
		const map = /* @__PURE__ */ new Map();
		for (const [name, c] of entries) map.set(name, c);
		return map;
	}
}
//#endregion
//#region archive/src/jj.ts
/** The only shell boundary for jj; never interpolate user arguments into a shell. */
const exec = promisify(execFile);
var JjError = class extends Error {
	args;
	detail;
	constructor(args, detail) {
		super(`jj ${args.join(" ")}: ${detail}`);
		this.args = args;
		this.detail = detail;
	}
};
async function jj(args, cwd) {
	try {
		const { stdout } = await exec("jj", [
			"--no-pager",
			"--color=never",
			...args
		], {
			cwd,
			encoding: "utf8",
			maxBuffer: 67108864
		});
		return stdout.trim();
	} catch (error) {
		throw new JjError(args, typeof error.stderr === "string" ? error.stderr.trim() : String(error));
	}
}
function lines(output) {
	return output === "" ? [] : output.split("\n").filter(Boolean);
}
async function exists(path) {
	return await stat(path, { throwIfNoEntry: false }) !== void 0;
}
async function isDirectory(path) {
	const info = await stat(path, { throwIfNoEntry: false });
	return info !== void 0 && info.isDirectory();
}
const REF_TEMPLATE = "name ++ \"\\t\" ++ if(remote,remote,\"-\") ++ \"\\t\" ++ if(normal_target,normal_target.commit_id(),\"conflict\") ++ \"\\t\" ++ tracked ++ \"\\n\"";
const COMMIT_TEMPLATE = "commit_id ++ \"\\t\" ++ empty ++ \"\\t\" ++ parents.map(|c| c.commit_id()).join(\",\") ++ \"\\t\" ++ conflict ++ \"\\n\"";
const HEAD_TEMPLATE = "commit_id ++ \"\\n\"";
const refKey = (name, remote) => `${name}\t${remote}`;
async function refs(dest) {
	const result = /* @__PURE__ */ new Map();
	for (const line of lines(await jj([
		"bookmark",
		"list",
		"--all-remotes",
		"-T",
		REF_TEMPLATE
	], dest))) {
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
//#endregion
//#region archive/src/health.ts
/** Materialize all visible view heads, including bare heads and bookmark conflict terms. */
async function preflight(dest) {
	try {
		await jj([
			"log",
			"-G",
			"-r",
			"visible_heads()",
			"-T",
			"commit_id ++ \"\\n\""
		], dest);
	} catch (error) {
		if (!(error instanceof JjError)) throw error;
		const ghosts = [...new Set([...error.detail.matchAll(/Object ([0-9a-f]{40,64}) of type commit not found/gi)].map((match) => match[1]))];
		if (ghosts.length === 0) throw error;
		throw new Error(`jj ghost commit(s) missing from Git object store: ${ghosts.join(", ")}. Resolve conflicted bookmarks and re-adopt the checkout, or explicitly run node '${(process.argv[1] ?? "archive/src/repo-jj-archive.ts").replaceAll("'", "'\\''")}' heal --dest '${dest.replaceAll("'", "'\\''")}' --yes (backs up .jj).`);
	}
	return [...(await refs(dest)).values()].filter((ref) => ref.target === "conflict").map((ref) => `${ref.name}${ref.remote === "-" ? "" : `@${ref.remote}`}`);
}
//#endregion
//#region archive/src/harvest.ts
function stamp() {
	const now = /* @__PURE__ */ new Date();
	const pad = (value) => String(value).padStart(2, "0");
	return `${now.getUTCFullYear()}${pad(now.getUTCMonth() + 1)}${pad(now.getUTCDate())}-${pad(now.getUTCHours())}${pad(now.getUTCMinutes())}${pad(now.getUTCSeconds())}`;
}
function safeLabel(label) {
	return label.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^[.-]+|[.-]+$/g, "") || "deployment";
}
/** Duplicate a mutable @ so its recovery bookmark cannot drift with subsequent edits. */
async function harvest(dest, label, kind, target, copy = false) {
	let commit = target;
	if (copy) {
		await preflight(dest);
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
		await preflight(dest);
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
	const name = `harvest/${safeLabel(label)}/${kind}-${stamp()}-${randomUUID().replaceAll("-", "").slice(0, 8)}`;
	await jj([
		"bookmark",
		"create",
		name,
		"-r",
		commit
	], dest);
	return {
		kind: "bookmark-created",
		name,
		target: commit
	};
}
async function recoveryCovered(dest, label, before, parents) {
	for (const ref of before.values()) {
		if (!ref.name.startsWith(`harvest/${safeLabel(label)}/working-copy-`) || ref.remote !== "-") continue;
		if ((await revision(dest, ref.target)).parents.join(",") !== parents.join(",")) continue;
		if (await jj([
			"diff",
			"--from",
			ref.target,
			"--to",
			"@",
			"--summary"
		], dest) !== "") continue;
		return true;
	}
	return false;
}
//#endregion
//#region archive/src/heal.ts
/** Explicit re-adoption drops jj's broken view, not the Git checkout or backup. */
async function heal(dest, yes) {
	if (!yes) throw new Error("heal is destructive to jj's operation history; pass --yes to back up .jj and re-adopt");
	if (!await isDirectory(dest) || !await exists(join(dest, ".git")) || !await isDirectory(join(dest, ".jj"))) throw new Error(`${dest} must be a jj-colocated Git checkout; refusing to re-adopt`);
	const backup = join(dest, `.jj.broken-ghost-${stamp()}-${randomUUID().slice(0, 8)}`);
	await rename(join(dest, ".jj"), backup);
	await jj([
		"git",
		"init",
		"--colocate"
	], dest);
	return backup;
}
//#endregion
//#region archive/src/remotes.ts
const REMOTE_NAME = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const quote = (value) => `'${value.replaceAll("'", "'\\''")}'`;
function declaredRemotes(repo, remotes) {
	const json = JSON.parse(remotes);
	if (json === null || typeof json !== "object" || Array.isArray(json)) throw new Error("--remotes must be a JSON object mapping remote names to URLs");
	const declared = new Map([["origin", repo], ...Object.entries(json)]);
	const urls = /* @__PURE__ */ new Map();
	for (const [name, url] of declared) {
		if (!REMOTE_NAME.test(name) || typeof url !== "string" || !url) throw new Error("remote names or URLs are invalid");
		urls.set(name, url);
	}
	return urls;
}
async function remoteDiff(dest, urls) {
	const actual = /* @__PURE__ */ new Map();
	for (const line of lines(await jj([
		"git",
		"remote",
		"list"
	], dest))) {
		const space = line.indexOf(" ");
		actual.set(space === -1 ? line : line.slice(0, space), space === -1 ? "" : line.slice(space + 1));
	}
	return [...urls].filter(([name, url]) => actual.get(name) !== url).map(([name, declared]) => ({
		name,
		declared,
		actual: actual.get(name) ?? null
	}));
}
function mismatchError(dest, differences, repo, remotes) {
	const table = differences.map(({ name, declared, actual }) => `${name}\t${JSON.stringify(declared)}\t${JSON.stringify(actual ?? "(missing)")}`).join("\n");
	return /* @__PURE__ */ new Error(`declared remote URL mismatch (no remote was changed):\nname\tdeclared\tactual\n${table}\nTo apply deliberately: node ${quote(process.argv[1] ?? "archive/src/repo-jj-archive.ts")} remotes --dest ${quote(dest)} --repo ${quote(repo)} --remotes ${quote(remotes)} --reconcile`);
}
/** Adds missing remotes and rewrites mismatches only on explicit operator request. */
async function reconcile(dest, differences) {
	for (const { name, declared, actual } of differences) await jj([
		"git",
		"remote",
		actual === null ? "add" : "set-url",
		name,
		declared
	], dest);
}
//#endregion
//#region archive/src/refresh.ts
/**
* Refresh a canonical archive without using Git's worktree-resetting update path.
*
* Stdout is one JSON result for Ansible; jj diagnostics and failures go to stderr.
* Only run this on a checkout whose working tree is not being edited concurrently.
*/
async function refreshArchive(options) {
	const { dest, repo, remotes: remotesArg, label, reconcileRemotes } = options;
	const update = options.update ?? "true";
	if (update !== "true" && update !== "false") throw new Error(`argument --update: invalid choice: '${update}' (choose from 'true', 'false')`);
	const urls = declaredRemotes(repo, remotesArg);
	let version = options.version ?? "HEAD";
	let selected = options.remote ?? "origin";
	const marker = version.lastIndexOf("@");
	if (marker !== -1 && urls.has(version.slice(marker + 1))) {
		selected = version.slice(marker + 1);
		version = version.slice(0, marker);
	}
	if (!urls.has(selected)) throw new Error(`selected remote '${selected}' is not declared`);
	if (options.submodules) throw new Error("GIT_SUBMODULES requires explicit submodule safety handling; disable it for this archive render");
	const depth = options.depth === void 0 ? void 0 : Number(options.depth);
	if (depth !== void 0 && (!Number.isInteger(depth) || depth < 1)) throw new Error("GIT_DEPTH must be positive");
	const notices = [];
	let changed = false;
	let cloned = false;
	const harvest$1 = async (kind, target, copy = false) => {
		notices.push(await harvest(dest, label, kind, target, copy));
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
	await preflight(dest);
	await jj(["status"], dest);
	const before = await refs(dest);
	const working = await revision(dest, "@");
	const work = working.commit;
	const empty = working.empty;
	const parents = working.parents;
	const differences = await remoteDiff(dest, urls);
	if (differences.some((difference) => difference.actual !== null) && !reconcileRemotes) throw mismatchError(dest, differences, repo, remotesArg);
	if (differences.length) {
		await reconcile(dest, differences);
		changed = true;
	}
	if (update === "false" && before.size > 0) return {
		changed,
		notices
	};
	if (!empty && !await recoveryCovered(dest, label, before, parents)) await harvest$1("working-copy", work, true);
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
		if (current === void 0 || current.target !== ref.target) await harvest$1(`${ref.name.replaceAll("/", "-")}-local`, ref.target);
	}
	if (oldBase !== null && oldBase !== upstream && !await ancestor(dest, oldBase, upstream)) await harvest$1(base.replaceAll("/", "-"), oldBase);
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
			if (empty && current.commit !== work) await harvest$1("head", work);
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
	return {
		changed,
		notices
	};
}
//#endregion
//#region archive/src/self.ts
/** Convenience only; compfuzor playbooks always use the launcher in playbook_dir. */
async function locateCompfuzor(freshen, archiveDir) {
	const root = archiveDir ?? join(homedir(), "archive");
	const path = join(root, "rektide", "compfuzor");
	if (!await exists(join(path, ".git"))) return null;
	if (freshen) {
		if (!await exists(join(path, ".jj"))) throw new Error(`${path} is not a jj checkout; cannot freshen`);
		await jj([
			"--config",
			"git.abandon-unreachable-commits=false",
			"git",
			"fetch",
			"--remote",
			"origin"
		], path);
	}
	return path;
}
//#endregion
//#region archive/src/repo-jj-archive.ts
/** General jj toolkit, with a JSON-only refresh mode for Ansible. */
const destArg = {
	type: "string",
	required: true,
	description: "Path to jj-colocated archive checkout"
};
const repoArg = {
	type: "string",
	required: true,
	description: "Declared origin URL"
};
const remotesArg = {
	type: "string",
	default: "{}",
	description: "JSON object of additional remote names and URLs"
};
const refresh = define({
	name: "refresh",
	description: "Snapshot, preserve recovery tips, fetch, and reconcile the selected base and worktree.",
	args: {
		dest: destArg,
		repo: repoArg,
		remotes: remotesArg,
		label: {
			type: "string",
			required: true,
			description: "Deployment label for recovery bookmarks"
		},
		remote: {
			type: "string",
			default: "origin",
			description: "Selected declared remote"
		},
		branch: {
			type: "string",
			default: "HEAD",
			description: "Branch or branch@remote; HEAD chooses main then master"
		},
		update: {
			type: "string",
			default: "true",
			description: "Fetch/reconcile: true or false"
		},
		depth: {
			type: "string",
			description: "Clone depth (only for new archives)"
		},
		submodules: {
			type: "boolean",
			description: "Unsupported: fail rather than silently recurse"
		},
		json: {
			type: "boolean",
			description: "Exactly one JSON line on stdout for Ansible"
		},
		"reconcile-remotes": {
			type: "boolean",
			description: "Explicitly add/rewrite declared remotes before refresh"
		}
	},
	run: async (ctx) => {
		const { dest, repo, remotes, label, remote, branch, update, depth, submodules, json } = ctx.values;
		const result = await refreshArchive({
			dest,
			repo,
			remotes,
			label,
			remote,
			version: branch,
			update,
			depth,
			submodules,
			reconcileRemotes: ctx.values["reconcile-remotes"]
		});
		if (json) console.log(JSON.stringify(result));
		else {
			console.log(result.changed ? "Archive changed" : "Archive unchanged");
			for (const notice of result.notices) console.log(notice.kind === "bookmark-created" ? `BOOKMARK CREATED  ${notice.name} -> ${notice.target}` : `REPO NOTICE ${notice.message}`);
		}
	}
});
const health = define({
	name: "health",
	description: "Materialize visible_heads() and list conflicted bookmarks; no mutations.",
	args: { dest: destArg },
	run: async (ctx) => {
		const conflicts = await preflight(ctx.values.dest);
		console.log(conflicts.length ? `Visible heads OK; conflicted bookmarks: ${conflicts.join(", ")}` : "Visible heads OK; no conflicted bookmarks");
	}
});
const snapshot = define({
	name: "snapshot",
	description: "Snapshot current tracked/untracked work and import colocated Git refs.",
	args: { dest: destArg },
	run: async (ctx) => {
		await preflight(ctx.values.dest);
		await jj(["status"], ctx.values.dest);
		console.log(`Snapshotted ${ctx.values.dest}`);
	}
});
const save = define({
	name: "harvest",
	description: "Pin a revision under a unique harvest/<label>/ bookmark.",
	args: {
		dest: destArg,
		label: {
			type: "string",
			required: true,
			description: "Recovery bookmark namespace"
		},
		kind: {
			type: "string",
			default: "manual",
			description: "Recovery bookmark category"
		},
		target: {
			type: "string",
			default: "@",
			description: "Revision to pin"
		},
		copy: {
			type: "boolean",
			description: "Duplicate mutable @ to a fixed change ID before pinning"
		}
	},
	run: async (ctx) => {
		const { dest, label, kind, target, copy } = ctx.values;
		await preflight(dest);
		await jj(["status"], dest);
		const notice = await harvest(dest, label, kind, target, copy);
		console.log(`BOOKMARK CREATED  ${notice.name} -> ${notice.target}`);
	}
});
const remotes = define({
	name: "remotes",
	description: "Compare declared remote URLs; --reconcile deliberately applies differences.",
	args: {
		dest: destArg,
		repo: repoArg,
		remotes: remotesArg,
		reconcile: {
			type: "boolean",
			description: "Apply missing or mismatched remote URLs"
		}
	},
	run: async (ctx) => {
		const { dest, repo, remotes: additional, reconcile: apply } = ctx.values;
		const diff = await remoteDiff(dest, declaredRemotes(repo, additional));
		if (apply) {
			await reconcile(dest, diff);
			console.log(diff.length ? `Reconciled ${diff.map(({ name }) => name).join(", ")}` : "Remotes match");
		} else if (diff.length) throw mismatchError(dest, diff, repo, additional);
		else console.log("Remotes match");
	}
});
const fetch = define({
	name: "fetch",
	description: "Snapshot, harvest dirty @, freeze tracked refs, then fetch one remote.",
	args: {
		dest: destArg,
		remote: {
			type: "string",
			default: "origin",
			description: "Existing remote to fetch"
		},
		label: {
			type: "string",
			required: true,
			description: "Recovery bookmark namespace"
		}
	},
	run: async (ctx) => {
		const { dest, remote, label } = ctx.values;
		await preflight(dest);
		await jj(["status"], dest);
		const before = await refs(dest);
		const working = await revision(dest, "@");
		if (!working.empty && !await recoveryCovered(dest, label, before, working.parents)) {
			const saved = await harvest(dest, label, "working-copy", working.commit, true);
			console.log(`BOOKMARK CREATED  ${saved.name} -> ${saved.target}`);
		}
		for (const ref of before.values()) if (ref.remote !== "-" && ref.remote !== "git" && ref.tracked) await jj([
			"bookmark",
			"untrack",
			ref.name,
			"--remote",
			ref.remote
		], dest);
		await jj([
			"--config",
			"git.abandon-unreachable-commits=false",
			"git",
			"fetch",
			"--remote",
			remote
		], dest);
		console.log(`Fetched ${remote}; local bookmarks remain frozen until refresh`);
	}
});
const healCommand = define({
	name: "heal",
	description: "Back up .jj and re-adopt from Git refs; loses jj-only operation history.",
	args: {
		dest: destArg,
		yes: {
			type: "boolean",
			description: "Required explicit permission to back up and replace .jj"
		}
	},
	run: async (ctx) => console.log(`Re-adopted ${ctx.values.dest}; old jj state preserved at ${await heal(ctx.values.dest, ctx.values.yes ?? false)}`)
});
const self = define({
	name: "self",
	description: "Detect ~/archive/rektide/compfuzor; optionally fetch its origin.",
	args: {
		"archive-dir": {
			type: "string",
			description: "Override ~/archive for detection (useful for fixtures)"
		},
		freshen: {
			type: "boolean",
			description: "Opt in to fetching origin of detected checkout"
		}
	},
	run: async (ctx) => {
		const location = await locateCompfuzor(ctx.values.freshen ?? false, ctx.values["archive-dir"]);
		console.log(location === null ? "No compfuzor archive checkout detected" : `${location}${ctx.values.freshen ? " (origin fetched)" : ""}`);
	}
});
async function main() {
	const args = process.argv.slice(2);
	const argv = args[0]?.startsWith("--") && args[0] !== "--help" ? [
		"refresh",
		...args,
		"--json"
	] : [...args];
	if (argv[0] === "refresh") {
		for (let i = 1; i < argv.length; i++) if (argv[i] === "--version") argv[i] = "--branch";
	}
	await cli(argv, define({
		name: "archive",
		description: "Composable jj archive operations; use COMMAND --help for flags.",
		run: () => console.log("Run repo-jj-archive --help for commands.")
	}), {
		name: "repo-jj-archive",
		version: "0.1.0",
		renderHeader: null,
		renderValidationErrors: null,
		strict: true,
		subCommands: {
			refresh,
			health,
			snapshot,
			harvest: save,
			remotes,
			fetch,
			heal: healCommand,
			self
		},
		plugins: [completion()]
	});
}
const argvPath = process.argv[1];
if (argvPath) realpath(argvPath).then((realArgv) => {
	if (realArgv !== import.meta.filename) return;
	return main().catch((error) => {
		const detail = error instanceof AggregateError ? error.errors.map((item) => item instanceof Error ? item.message : String(item)).join("; ") : error instanceof Error ? error.message : String(error);
		console.error(`repo-jj-archive: ${detail}`);
		process.exitCode = 1;
	});
}, (error) => {
	console.error(`repo-jj-archive: ${error instanceof Error ? error.message : String(error)}`);
	process.exitCode = 1;
});
//#endregion
export { main };
