/** Version-one declaration admission. No execution or discovery side effects. */
import { posix } from "node:path";

export type Kind = "zim-import" | "shell-source" | "exec";
export type Scope = "user" | "system";
export type Deployment = { id: string; dir: string };
export type Fuze = {
  version: 1;
  id: string;
  deployment: Deployment;
  scope: Scope;
  actions: Record<string, { kind: Kind; required: string[] }>;
};
export type Contribution =
  | { kind: "zim-import"; order: number }
  | { kind: "shell-source"; order: number; path: string }
  | { kind: "exec"; order: number; path: string; args: string[] };
export type Fuzing = {
  version: 1;
  id: string;
  deployment: Deployment;
  target: { dir: string; fuze: string; scope: Scope };
  actions: Record<string, Contribution>;
};

export function fail(message: string): never {
  throw new Error(`fuzings: ${message}`);
}
export function name(value: unknown, label: string): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9]/.test(value) || /[^A-Za-z0-9_.-]/.test(value))
    fail(`invalid ${label}`);
  return value;
}
function object(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    fail(`${label} must be an object`);
  return value as Record<string, unknown>;
}
function record(value: unknown, keys: string[], label: string): Record<string, unknown> {
  const raw = object(value, label);
  for (const key of Object.keys(raw))
    if (!keys.includes(key)) fail(`${label} has unknown field: ${key}`);
  return raw;
}
function directory(value: unknown): string {
  if (
    typeof value !== "string" ||
    !value.startsWith("/") ||
    value.includes("\0") ||
    value === "/" ||
    value.startsWith("//") ||
    posix.normalize(value) !== value ||
    value.endsWith("/")
  )
    fail("expected a normalized absolute non-root directory");
  return value;
}
function scope(value: unknown): Scope {
  if (value !== "user" && value !== "system") fail("scope must be user or system");
  return value;
}
function kind(value: unknown): Kind {
  if (value !== "zim-import" && value !== "shell-source" && value !== "exec")
    fail("kind must be zim-import, shell-source, or exec");
  return value;
}
function deployment(value: unknown): Deployment {
  const raw = record(value, ["id", "dir"], "deployment");
  return { id: name(raw.id, "deployment ID"), dir: directory(raw.dir) };
}
function path(value: unknown, kind: "exec" | "shell-source"): string {
  const prefix = kind === "exec" ? "bin/" : "etc/";
  if (
    typeof value !== "string" ||
    !value.startsWith(prefix) ||
    value.includes("\0") ||
    value.split("/").some((part) => !part || part === "." || part === "..")
  )
    fail(`${kind} path must be a relative file beneath ${prefix}`);
  return value;
}
function actions(value: unknown): Array<[string, unknown]> {
  const entries = Object.entries(object(value, "actions"));
  if (!entries.length) fail("actions must not be empty");
  for (const [key] of entries) name(key, "action name");
  return entries;
}
function header(raw: Record<string, unknown>): { version: 1; id: string; deployment: Deployment } {
  if (raw.version !== 1) fail("unsupported descriptor version");
  return { version: 1, id: name(raw.id, "descriptor ID"), deployment: deployment(raw.deployment) };
}

export function parseFuze(value: unknown): Fuze {
  const raw = record(value, ["version", "id", "deployment", "scope", "actions"], "fuze");
  const compiled: Fuze["actions"] = Object.create(null) as Fuze["actions"];
  for (const [key, value] of actions(raw.actions)) {
    const entry = record(value, ["kind", "required"], `action ${key}`);
    const required = entry.required === undefined ? [] : entry.required;
    if (!Array.isArray(required)) fail("required must be an array");
    const ids = required.map((id: unknown) => name(id, "required fuzing ID"));
    if (new Set(ids).size !== ids.length) fail("duplicate required fuzing ID");
    compiled[key] = { kind: kind(entry.kind), required: ids };
  }
  return { ...header(raw), scope: scope(raw.scope), actions: compiled };
}

export function parseFuzing(value: unknown): Fuzing {
  const raw = record(value, ["version", "id", "deployment", "target", "actions"], "fuzing");
  const target = record(raw.target, ["dir", "fuze", "scope"], "target");
  const compiled: Fuzing["actions"] = Object.create(null) as Fuzing["actions"];
  for (const [key, value] of actions(raw.actions)) {
    const entry = record(value, ["kind", "order", "path", "args"], `action ${key}`);
    const type = kind(entry.kind);
    const order = entry.order;
    if (typeof order !== "number" || !Number.isSafeInteger(order) || order < 0)
      fail("order must be a nonnegative safe integer");
    if (type === "zim-import") {
      if ("path" in entry || "args" in entry) fail("zim-import accepts neither path nor args");
      compiled[key] = { kind: type, order };
    } else if (type === "shell-source") {
      if ("args" in entry) fail("shell-source does not accept args");
      compiled[key] = { kind: type, order, path: path(entry.path, type) };
    } else {
      const args = entry.args === undefined ? [] : entry.args;
      if (!Array.isArray(args) || args.some((arg) => typeof arg !== "string" || arg.includes("\0")))
        fail("args must be literal strings without NUL");
      compiled[key] = { kind: type, order, path: path(entry.path, type), args: args as string[] };
    }
  }
  return {
    ...header(raw),
    target: {
      dir: directory(target.dir),
      fuze: name(target.fuze, "target fuze"),
      scope: scope(target.scope),
    },
    actions: compiled,
  };
}
