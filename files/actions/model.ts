/** Shared action data admission; context/recipe semantics remain in their domains. */
import { basename, dirname, isAbsolute } from "node:path";
import type { PathSelector } from "../config/context.ts";

export type Audience = "user" | "system";
export type LegacyDomainStep = {
  kind: "domain";
  id: string;
  domain: "config" | "keybindings";
  operation: "install" | "assemble" | "sync-inputs" | "publish" | "inputs" | "host";
  context: string;
  envelope: string;
  spec?: string;
  target?: "niri" | "umbriel";
  profile?: string;
  profileSelector?: PathSelector;
  mode?: "assemble";
  manifest?: string;
  producer?: string;
  descriptor?: string;
  registryPolicy?: string;
};
export type KeybindingBatchStep = {
  kind: "domain";
  id: string;
  domain: "keybindings";
  operation: "install-offer";
  envelope: string;
  manifest: string;
  producer: string;
  selection?: string;
  registryPolicy?: string;
};
export type DomainStep = LegacyDomainStep | KeybindingBatchStep;
export type ActionStep =
  | { kind: "action"; action: string }
  | { kind: "exec"; path: string; children?: ActionStep[] }
  | DomainStep;
export type ActionSetup = { env: boolean; basedir: boolean | string };
export type ActionFamily = {
  name: string;
  action: string;
  entry: string;
  aliases: string[];
  default?: Audience;
  plans: Partial<Record<Audience, ActionStep[]>>;
  setup?: Partial<Record<Audience, ActionSetup>>;
};
export type ActionSpec = { version: 1; actions: Record<string, ActionFamily> };
export type ActionOutcome = { code: number; signal?: NodeJS.Signals };
export type ActionSelection = { family: ActionFamily; audience: Audience; deploymentDir: string };
export const AUDIENCES: readonly Audience[] = ["user", "system"];
const NAME = /^[A-Za-z0-9][A-Za-z0-9_.-]*$/;

export function fail(message: string): never {
  throw new Error(`action audiences: ${message}`);
}
export function object(value: unknown, label: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value))
    fail(`${label} must be an object`);
  return value as Record<string, unknown>;
}
export function knownKeys(
  value: Record<string, unknown>,
  keys: readonly string[],
  label: string,
): void {
  const unknown = Object.keys(value).filter((key) => !keys.includes(key));
  if (unknown.length) fail(`${label} has unknown fields: ${unknown.join(", ")}`);
}
export function named(value: unknown, label: string): string {
  if (typeof value !== "string" || !NAME.test(value)) fail(`invalid ${label}`);
  return value;
}
export function binPath(value: unknown): string {
  if (
    typeof value !== "string" ||
    !value.startsWith("bin/") ||
    isAbsolute(value) ||
    value.split("/").some((part) => !part || part === "." || part === "..")
  )
    fail(`executable must be contained beneath bin/: ${String(value)}`);
  return value;
}
export function domainStep(value: unknown): DomainStep {
  const raw = object(value, "domain step");
  knownKeys(
    raw,
    [
      "kind",
      "id",
      "domain",
      "operation",
      "context",
      "envelope",
      "spec",
      "target",
      "profile",
      "profileSelector",
      "mode",
      "manifest",
      "producer",
      "selection",
      "descriptor",
      "registryPolicy",
    ],
    "domain step",
  );
  const id = named(raw.id, "operation ID");
  const envelope = binPath(raw.envelope);
  if (raw.domain === "keybindings" && raw.operation === "install-offer") {
    knownKeys(
      raw,
      [
        "kind",
        "id",
        "domain",
        "operation",
        "envelope",
        "manifest",
        "producer",
        "selection",
        "registryPolicy",
      ],
      "registry producer operation",
    );
    if (
      typeof raw.manifest !== "string" ||
      !raw.manifest ||
      (raw.registryPolicy !== undefined &&
        (typeof raw.registryPolicy !== "string" || !raw.registryPolicy)) ||
      (raw.selection !== undefined && (typeof raw.selection !== "string" || !raw.selection))
    )
      fail("invalid registry producer locators");
    return {
      kind: "domain",
      id,
      domain: "keybindings",
      operation: "install-offer",
      envelope,
      manifest: raw.manifest,
      producer: named(raw.producer, "producer"),
      ...(raw.selection === undefined ? {} : { selection: raw.selection as string }),
      ...(raw.registryPolicy === undefined ? {} : { registryPolicy: raw.registryPolicy as string }),
    };
  }
  const context = named(raw.context, "operation context");
  if (raw.domain !== "config" && raw.domain !== "keybindings") fail("unsupported action domain");
  const operations =
    raw.domain === "config"
      ? ["install", "assemble", "sync-inputs", "publish", "inputs"]
      : ["install", "host"];
  if (!operations.includes(String(raw.operation))) fail("unsupported domain operation");
  if (raw.domain === "keybindings" && raw.target !== "niri" && raw.target !== "umbriel")
    fail("invalid keybinding target");
  for (const key of [
    "spec",
    "profile",
    "manifest",
    "producer",
    "descriptor",
    "registryPolicy",
  ] as const)
    if (raw[key] !== undefined && (typeof raw[key] !== "string" || !raw[key]))
      fail(`invalid domain ${key}`);
  if (raw.mode !== undefined && (raw.mode !== "assemble" || raw.operation !== "host"))
    fail("only host assembly can assert mode assemble");
  if (raw.profile !== undefined && raw.profileSelector !== undefined)
    fail("choose profile or profile selector");
  if (raw.profileSelector !== undefined) object(raw.profileSelector, "profile selector");
  return { ...raw, kind: "domain", id, context, envelope } as DomainStep;
}
function steps(value: unknown, label: string): ActionStep[] {
  if (!Array.isArray(value)) fail(`${label} must be an array`);
  return value.map((raw) => {
    const step = object(raw, label);
    if (step.kind === "domain") return domainStep(step);
    if (step.kind === "action")
      return { kind: "action", action: named(step.action, "action reference") };
    if (step.kind !== "exec") fail(`unsupported step in ${label}`);
    return {
      kind: "exec",
      path: binPath(step.path),
      ...(step.children === undefined
        ? {}
        : { children: steps(step.children, label + " children") }),
    };
  });
}
export function parseActionSpec(value: unknown): ActionSpec {
  const spec = object(value, "spec");
  if (spec.version !== 1) fail(`unsupported spec version: ${String(spec.version)}`);
  const actions: Record<string, ActionFamily> = Object.create(null) as Record<string, ActionFamily>;
  for (const [name, value] of Object.entries(object(spec.actions, "actions"))) {
    named(name, "action name");
    const raw = object(value, `action ${name}`);
    if (raw.name !== name) fail(`action identity mismatch: ${name}`);
    const action = named(raw.action, "action vocabulary");
    const rawPlans = object(raw.plans, `${name} plans`);
    if (Object.keys(rawPlans).some((audience) => !AUDIENCES.includes(audience as Audience)))
      fail(`unknown audience in ${name}`);
    const available = AUDIENCES.filter((audience) => rawPlans[audience] !== undefined);
    if (!available.length) fail(`action ${name} has no audience plans`);
    const plans: ActionFamily["plans"] = {};
    for (const audience of available)
      plans[audience] = steps(rawPlans[audience], `${name} ${audience}`);
    const entryAudience = available.find((audience) => raw.entry === `${name}-${audience}.mjs`);
    if (!entryAudience) fail(`invalid qualified real entry for ${name}`);
    if (raw.default !== undefined && raw.default !== entryAudience)
      fail(`default must match the real entry filename for ${name}`);
    const aliases = [
      ...(raw.default === undefined ? [] : [`${name}.mjs`]),
      ...available
        .filter((audience) => audience !== entryAudience)
        .map((audience) => `${name}-${audience}.mjs`),
    ];
    const declared = raw.aliases;
    if (
      !Array.isArray(declared) ||
      declared.length !== aliases.length ||
      aliases.some((alias, index) => declared[index] !== alias)
    )
      fail(`aliases do not match available audiences/default for ${name}`);
    const setup: ActionFamily["setup"] = {};
    if (raw.setup !== undefined)
      for (const [audience, value] of Object.entries(object(raw.setup, `${name} setup`))) {
        const entry = object(value, `${name} setup ${audience}`);
        if (
          !available.includes(audience as Audience) ||
          typeof entry.env !== "boolean" ||
          (typeof entry.basedir !== "string" && typeof entry.basedir !== "boolean")
        )
          fail(`invalid setup for ${name}`);
        setup[audience as Audience] = entry as ActionSetup;
      }
    actions[name] = {
      name,
      action,
      entry: raw.entry as string,
      aliases,
      plans,
      ...(raw.default === undefined ? {} : { default: entryAudience }),
      ...(raw.setup === undefined ? {} : { setup }),
    };
  }
  return { version: 1, actions };
}
export function selectAction(
  spec: ActionSpec,
  invokedPath: string,
  physicalEntry: string,
): ActionSelection {
  if (basename(dirname(physicalEntry)) !== "bin")
    fail("real action entry must live in deployment/bin");
  const entry = basename(physicalEntry);
  const family = Object.values(spec.actions).find((candidate) => candidate.entry === entry);
  if (!family) fail(`unavailable or stale action entry: ${entry}`);
  const invoked = basename(invokedPath);
  if (invoked !== entry && !family.aliases.includes(invoked))
    fail(`unknown or unavailable action alias: ${invoked}`);
  const audience =
    AUDIENCES.find((candidate) => invoked === `${family.name}-${candidate}.mjs`) ??
    (invoked === `${family.name}.mjs`
      ? AUDIENCES.find((candidate) => entry === `${family.name}-${candidate}.mjs`)
      : undefined);
  if (!audience || !family.plans[audience]) fail(`unavailable audience for ${invoked}`);
  return { family, audience, deploymentDir: dirname(dirname(physicalEntry)) };
}
