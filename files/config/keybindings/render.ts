/** Native single-binding definitions, distinct from incorporation material. */

import type { Implementation, Properties, ResolvedBinding, Scalar, Target } from "./model.ts";

export function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'"'"'`)}'`;
}
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

/** Umbriel incorporation is an ARRAY ENTRY, deliberately not standalone TOML. */
export function renderInclude(target: Target, effectivePath: string): string {
  if (!effectivePath || /[\0\r\n\t]/.test(effectivePath))
    throw new Error("include path must be non-empty without NUL/newlines");
  return target === "niri"
    ? `include ${kdlString(effectivePath)}\n`
    : `${JSON.stringify(effectivePath)},\n`;
}
