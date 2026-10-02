/**
 * Pure serializers for a resolved binding definition or its include reference.
 * Native definitions and incorporation pieces are different material kinds:
 * Niri definitions own a binds section; Umbriel definitions own one keybinds table.
 * Umbriel incorporation is only a files-array entry, never standalone TOML.
 * No command/script is executed, file is read/written or CONFIG output published.
 * Callers validate the complete native candidate closure before the runner commits.
 * @see /doc/config/keybindings.md
 */

import type { Implementation, Properties, ResolvedBinding, Scalar, Target } from "./model.ts";

/**
 * Quote one literal POSIX shell argument without enabling variable/subcommand expansion.
 * @param value One complete argument, including possibly empty or quoted text.
 * @returns Single-argument shell spelling; does not execute it or split a command.
 */
export function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'"'"'`)}'`;
}
/**
 * Serialize one KDL v1 quoted string, escaping ASCII controls/quotes/backslashes.
 * @param value Decoded text; Unicode outside those controls remains unchanged.
 * @returns A string literal, not a parsed node or native-schema validity guarantee.
 */
export function kdlString(value: string): string {
  return (
    '"' +
    // ASCII controls must be escaped; all Unicode text stays intact.
    // eslint-disable-next-line no-control-regex
    value.replace(/["\\\u0000-\u001f\u007f]/g, (character) => {
      if (character === '"' || character === "\\") return "\\" + character;
      if (character === "\n") return "\\n";
      if (character === "\r") return "\\r";
      if (character === "\t") return "\\t";
      const code = character.codePointAt(0)!;
      return code < 32 || code === 127 ? `\\u{${code.toString(16)}}` : character;
    }) +
    '"'
  );
}
function kdlScalar(value: Scalar): string {
  return typeof value === "string" ? kdlString(value) : String(value);
}
function kdlProperties(properties: Properties): string {
  return Object.entries(properties)
    .map(([key, value]) => ` ${key}=${kdlScalar(value)}`)
    .join("");
}
function niriAction(implementation: Implementation): string {
  if (implementation.kind === "exec")
    return `spawn ${implementation.argv.map(kdlString).join(" ")};`;
  if (implementation.kind === "script")
    return `spawn ${[implementation.shell, "-c", implementation.body].map(kdlString).join(" ")};`;
  if (implementation.kind === "umbriel-native")
    throw new Error("Umbriel native action cannot render for Niri");
  const { name, args, properties } = implementation.value;
  return `${name}${args.map((value) => " " + kdlScalar(value)).join("")}${kdlProperties(properties)};`;
}
function umbrielAction(implementation: Implementation): string {
  if (implementation.kind === "umbriel-native") return implementation.value;
  if (implementation.kind === "niri-native")
    throw new Error("Niri native action cannot render for Umbriel");
  const argv =
    implementation.kind === "exec"
      ? implementation.argv
      : [implementation.shell, "-c", implementation.body];
  return "spawn:" + argv.map(shellQuote).join(" ");
}

/**
 * Render one complete binding fragment, retaining native option spelling.
 * Portable argv becomes Niri spawn arguments or individually shell-quoted Umbriel
 * spawn text. Explicit scripts become shell `-c` invocations, not executable files.
 * Empty chord selection still emits an empty binds section/keybinds table.
 * @param binding Resolved reference/options/chords from composition.
 * @param target Matching compositor; target-native actions cannot cross adapters.
 * @returns Native definition text only; callers own delivery and closure admission.
 * @throws On wrong-target native actions or Umbriel options.action overriding the
 * resolved implementation. Native option/action schema errors are checked later.
 */
export function renderDefinition(binding: ResolvedBinding, target: Target): string {
  if (target === "niri") {
    const options = {
      ...(binding.title === undefined ? {} : { "hotkey-overlay-title": binding.title }),
      ...binding.options,
    };
    return `binds {\n${binding.keys.map((key) => `  ${kdlString(key)}${kdlProperties(options)} { ${niriAction(binding.action.implementation)} }\n`).join("")}\n}\n`;
  }
  const action = JSON.stringify(umbrielAction(binding.action.implementation));
  const options = Object.entries(binding.options).map(
    ([key, value]) => `${JSON.stringify(key)} = ${JSON.stringify(value)}`,
  );
  if ("action" in binding.options)
    throw new Error(`keybinding ${binding.id}: options.action would replace resolved action`);
  const value = options.length ? `{ action = ${action}, ${options.join(", ")} }` : action;
  return `[keybinds]\n${binding.keys.map((key) => `${JSON.stringify(key)} = ${value}\n`).join("")}`;
}

/**
 * Render incorporation against the effective live placement, not a producer guess.
 * Niri gets an include statement; Umbriel gets a quoted, comma-terminated ARRAY
 * ENTRY which must be assembled inside one include.files array. No body existence
 * or contents are checked: a referenced output may still be a pending candidate.
 * @param target Compositor selecting the reference syntax.
 * @param effectivePath Explicit path chosen/bound by the caller; selection normally
 * requires absolute concrete paths, but this serializer does not resolve them.
 * @returns Reference text, deliberately distinct from a definition document.
 * @throws For empty paths or NUL, tab or newline separators.
 */
export function renderInclude(target: Target, effectivePath: string): string {
  if (!effectivePath || /[\0\r\n\t]/.test(effectivePath))
    throw new Error("include path must be non-empty without NUL/newlines");
  return target === "niri"
    ? `include ${kdlString(effectivePath)}\n`
    : `${JSON.stringify(effectivePath)},\n`;
}
