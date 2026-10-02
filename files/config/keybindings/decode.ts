/**
 * Pure admission of version-1, one-record action/binding declarations from captured
 * values or YAML text. It validates record shape and explicit target refinements,
 * not cross-record references or complete compositor schemas. No filesystem,
 * environment, registration, command execution or CONFIG publication occurs here.
 * Record-authored IDs remain authoritative; caller labels provide provenance only.
 * @see /doc/config/keybindings.md
 */

import { parseDocument } from "yaml";
import type {
  ActionFields,
  BindingFields,
  Contribution,
  Implementation,
  Properties,
  Scalar,
  Target,
} from "./model.ts";

const ID = /^[A-Za-z0-9][A-Za-z0-9_.-]*$/;
const NAME = /^[A-Za-z][A-Za-z0-9_-]*$/;

function object(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new Error(`${label}: expected mapping`);
  return value as Record<string, unknown>;
}
function known(value: Record<string, unknown>, fields: string[], label: string): void {
  const unknown = Object.keys(value).filter((key) => !fields.includes(key));
  if (unknown.length) throw new Error(`${label}: unknown fields ${unknown.join(", ")}`);
}
function text(value: unknown, label: string, empty = false): string {
  if (typeof value !== "string" || (!empty && !value) || value.includes("\0"))
    throw new Error(`${label}: expected ${empty ? "" : "non-empty "}string without NUL`);
  return value;
}
function id(value: unknown, label: string): string {
  const result = text(value, label);
  if (!ID.test(result)) throw new Error(`${label}: invalid identifier ${result}`);
  return result;
}
function bool(value: unknown, label: string): boolean {
  if (typeof value !== "boolean") throw new Error(`${label}: expected boolean`);
  return value;
}
function sequence(value: unknown, label: string): unknown[] {
  if (!Array.isArray(value)) throw new Error(`${label}: expected sequence`);
  return value;
}
function scalar(value: unknown, label: string): Scalar {
  if (typeof value === "string") return text(value, label, true);
  if (typeof value === "boolean" || (typeof value === "number" && Number.isFinite(value)))
    return value;
  throw new Error(`${label}: expected string, boolean or finite number`);
}
function properties(value: unknown, label: string): Properties {
  return Object.fromEntries(
    Object.entries(object(value, label)).map(([key, entry]) => {
      if (!NAME.test(key)) throw new Error(`${label}: invalid property name ${key}`);
      return [key, scalar(entry, `${label}.${key}`)];
    }),
  );
}
function implementation(
  value: Record<string, unknown>,
  label: string,
  target?: Target,
): Implementation | undefined {
  const kinds = ["exec", "script", "native"].filter((key) => value[key] !== undefined);
  if (kinds.length > 1)
    throw new Error(`${label}: exec, script and native replace one another; specify only one`);
  if (!kinds.length) return undefined;
  if (kinds[0] === "exec") {
    const argv = sequence(value.exec, `${label}.exec`).map((entry, index) =>
      text(entry, `${label}.exec[${index}]`, index > 0),
    );
    if (!argv.length) throw new Error(`${label}.exec: command argv must not be empty`);
    return { kind: "exec", argv };
  }
  if (kinds[0] === "script") {
    const script = object(value.script, `${label}.script`);
    known(script, ["shell", "body"], `${label}.script`);
    return {
      kind: "script",
      shell: text(script.shell, `${label}.script.shell`),
      body: text(script.body, `${label}.script.body`),
    };
  }
  if (!target) throw new Error(`${label}: native requires a target specifier`);
  if (target === "umbriel")
    return { kind: "umbriel-native", value: text(value.native, `${label}.native`) };
  const native = object(value.native, `${label}.native`);
  known(native, ["name", "args", "properties"], `${label}.native`);
  const name = text(native.name, `${label}.native.name`);
  if (!NAME.test(name)) throw new Error(`${label}.native.name: invalid node name`);
  return {
    kind: "niri-native",
    value: {
      name,
      args: sequence(native.args ?? [], `${label}.native.args`).map((entry) =>
        scalar(entry, `${label}.native.args`),
      ),
      properties:
        native.properties === undefined
          ? {}
          : properties(native.properties, `${label}.native.properties`),
    },
  };
}
function actionFields(raw: Record<string, unknown>, label: string, target?: Target): ActionFields {
  known(raw, ["exec", "script", "native", "enabled"], label);
  const result: ActionFields = {};
  const body = implementation(raw, label, target);
  if (body) result.implementation = body;
  if (raw.enabled !== undefined) result.enabled = bool(raw.enabled, `${label}.enabled`);
  return result;
}
function bindingFields(raw: Record<string, unknown>, label: string): BindingFields {
  known(raw, ["action", "keys", "add-keys", "title", "options", "enabled"], label);
  const result: BindingFields = {};
  if (raw.action !== undefined) result.action = id(raw.action, `${label}.action`);
  for (const [field, property] of [
    ["keys", "keys"],
    ["add-keys", "addKeys"],
  ] as const) {
    if (raw[field] === undefined) continue;
    result[property] = sequence(raw[field], `${label}.${field}`).map((entry) => {
      const chord = text(entry, `${label}.${field}`);
      if (!/^[A-Za-z0-9_]+(?:\+[A-Za-z0-9_]+)*$/.test(chord))
        throw new Error(`${label}.${field}: unsupported chord syntax ${chord}`);
      return chord;
    });
  }
  if (raw.title !== undefined) result.title = text(raw.title, `${label}.title`, true);
  if (raw.options !== undefined) result.options = properties(raw.options, `${label}.options`);
  if (raw.enabled !== undefined) result.enabled = bool(raw.enabled, `${label}.enabled`);
  return result;
}

/**
 * Admit one source record and translate authoring fields into the domain model.
 * Exec/script/native are mutually exclusive per layer; native implementations
 * require a target specifier. Partial records are allowed for later composition.
 * @param value Parsed data containing version, kind, ID and declaration fields.
 * @param source Diagnostic label; never used to infer or overwrite the record ID.
 * @returns A decoded contribution without reading, registering or publishing anything.
 * @throws On unsupported version/kind, unknown fields, malformed identifiers,
 * invalid field types, unsafe scalar spelling or ambiguous implementation selection.
 */
export function decodeContribution(value: unknown, source: string): Contribution {
  const raw = object(value, source);
  const { version, kind, id: rawId, patch, niri, umbriel, ...fields } = raw;
  if (version !== 1) throw new Error(`${source}: expected version: 1`);
  const common = {
    id: id(rawId, `${source}.id`),
    patch: patch === undefined ? false : bool(patch, `${source}.patch`),
    source,
  };
  if (kind === "action") {
    return {
      ...common,
      kind,
      fields: actionFields(fields, source),
      targets: {
        ...(niri === undefined
          ? {}
          : { niri: actionFields(object(niri, `${source}.niri`), `${source}.niri`, "niri") }),
        ...(umbriel === undefined
          ? {}
          : {
              umbriel: actionFields(
                object(umbriel, `${source}.umbriel`),
                `${source}.umbriel`,
                "umbriel",
              ),
            }),
      },
    };
  }
  if (kind !== "keybinding") throw new Error(`${source}: kind must be action or keybinding`);
  return {
    ...common,
    kind,
    fields: bindingFields(fields, source),
    targets: {
      ...(niri === undefined
        ? {}
        : { niri: bindingFields(object(niri, `${source}.niri`), `${source}.niri`) }),
      ...(umbriel === undefined
        ? {}
        : { umbriel: bindingFields(object(umbriel, `${source}.umbriel`), `${source}.umbriel`) }),
    },
  };
}

/**
 * Decode exactly one captured YAML document using the strict record contract.
 * Duplicate keys, custom/unsupported syntax warnings, multiple documents and
 * aliases are rejected rather than silently reduced into a different declaration.
 * UTF-8 byte admission belongs to the capture adapter, not this text-only function.
 * @param text Already captured YAML text; no file lookup or env substitution occurs.
 * @param source Provenance label included in parser and record diagnostics.
 * @returns One decoded contribution for ordered composition.
 * @throws On YAML admission errors or any invalid record field.
 */
export function decodeYaml(text: string, source: string): Contribution {
  const document = parseDocument(text, { uniqueKeys: true, schema: "core" });
  if (document.errors.length)
    throw new Error(`${source}: ${document.errors.map((error) => error.message).join("; ")}`);
  if (document.warnings.length)
    throw new Error(
      `${source}: unsupported YAML syntax: ${document.warnings.map((warning) => warning.message).join("; ")}`,
    );
  return decodeContribution(document.toJS({ maxAliasCount: 0 }), source);
}
