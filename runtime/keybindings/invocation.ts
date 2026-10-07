/** Domain batch admission. Receiver IDs are not native formats; membership commits remain per receiver. */
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import {
  captureFile,
  fileText,
  assertFileGuards,
  type FileGuard,
} from "../../files/config/capture.ts";
import {
  resolvePathSelector,
  validatePathSelector,
  type PathSelector,
} from "../../files/config/context.ts";
import {
  admitKeybindingCommand,
  runAdmittedKeybindingCommand,
  type AdmittedKeybindingCommand,
  type KeybindingRuntimeDefaults,
} from "../../files/config/keybindings/runtime.ts";
import { pathsSharePhysicalEntry } from "../../files/links/delivery.ts";
import { keybindingConsumers, keybindingProviders } from "./registry.ts";
import { registryPolicy } from "../registry/policy.ts";
import { inspectRegistry, lookup } from "../registry/read.ts";
import { registryGuard, assertRegistryGuards, type RegistryGuard } from "../registry/guard.ts";
import type { RegistryPolicy, RegistryRecord, Scope } from "../registry/model.ts";
import type { Consumer } from "./registry.ts";
import {
  planRegistration,
  applyRegistration,
  type RegistrationPlan,
} from "../registry/register.ts";

export type ReceiverRequest = {
  id: string;
  profile?: PathSelector;
  context?: string;
  scope?: Scope;
};
export type SelectionPolicy = { version: 1; receivers: null | ReceiverRequest[] };
export type AdmittedReceiver = {
  id: string;
  originalState: RegistryRecord<Consumer>["state"];
  forced: boolean;
  registry: RegistryGuard;
  admitted: AdmittedKeybindingCommand;
};
export type AdmittedKeybindingBatch = {
  version: 1;
  kind: "keybinding-batch";
  audience: Scope;
  forceEnable: boolean;
  members: AdmittedReceiver[];
  guards: FileGuard[];
  publication: { source: string; policy: RegistryPolicy; plan: RegistrationPlan };
};
export type BatchRequest = {
  args: string[];
  defaults: KeybindingRuntimeDefaults;
  policy?: RegistryPolicy;
  audience?: Scope;
  manifest?: string;
  selection?: string;
  producer?: string;
};

function selection(value: unknown): SelectionPolicy {
  if (
    typeof value !== "object" ||
    value === null ||
    !("version" in value) ||
    value.version !== 1 ||
    !("receivers" in value)
  )
    throw new Error("invalid receiver selection policy");
  if (value.receivers === null) return { version: 1, receivers: null };
  if (!Array.isArray(value.receivers))
    throw new Error("selection receivers must be null or a list");
  const seen = new Set<string>();
  const receivers = value.receivers.map((raw): ReceiverRequest => {
    if (!raw || typeof raw !== "object" || typeof raw.id !== "string" || seen.has(raw.id))
      throw new Error("invalid/duplicate receiver selection");
    seen.add(raw.id);
    if (raw.context !== undefined && (typeof raw.context !== "string" || !raw.context.trim()))
      throw new Error("invalid receiver context override");
    if (raw.scope !== undefined && raw.scope !== "user" && raw.scope !== "system")
      throw new Error("invalid receiver scope override");
    return {
      id: raw.id,
      context: raw.context,
      scope: raw.scope,
      ...(raw.profile === undefined
        ? {}
        : { profile: validatePathSelector(raw.profile, "receiver profile override") }),
    };
  });
  return { version: 1, receivers };
}

export async function admitKeybindingBatch(
  request: BatchRequest,
): Promise<AdmittedKeybindingBatch> {
  const { values } = parseArgs({
    args: request.args,
    strict: true,
    allowPositionals: false,
    options: {
      manifest: { type: "string" },
      selection: { type: "string" },
      target: { type: "string", multiple: true },
      scope: { type: "string", default: request.audience ?? "user" },
      context: { type: "string" },
      profile: { type: "string" },
      "profile-selector": { type: "string" },
      "force-enable": { type: "boolean", default: false },
      mode: { type: "string" },
      runner: { type: "string" },
    },
  });
  if (values.scope !== "user" && values.scope !== "system")
    throw new Error("invalid keybinding scope");
  if (request.audience && values.scope !== request.audience)
    throw new Error("batch audience override is not allowed");
  const manifestPath = values.manifest ?? request.manifest;
  if (!manifestPath) throw new Error("install-offer requires --manifest");
  const manifestFile = await captureFile(resolve(manifestPath));
  const manifestText = fileText(manifestFile);
  if (manifestText === undefined) throw new Error("missing producer manifest");
  const manifest = keybindingProviders.decode(JSON.parse(manifestText));
  if (request.producer && manifest.producer !== request.producer)
    throw new Error("producer identity disagrees with declared operation");
  const providerPolicy = registryPolicy(keybindingProviders.collection, values.scope);
  const publicationRequest = {
    domain: keybindingProviders,
    policy: providerPolicy,
    source: resolve(manifestPath),
  };
  const publicationPlan = await planRegistration(publicationRequest);
  if (publicationPlan.disposition === "blocked")
    throw new Error(`provider publication blocked: ${publicationPlan.reason}`);
  if (publicationPlan.effective.state === "masked")
    throw new Error("producer registration is masked");
  if (publicationPlan.effective.state === "disabled" && !values["force-enable"])
    throw new Error("producer registration is disabled; use --force-enable");
  const guards: FileGuard[] = [manifestFile.guard];
  if (manifest.enabled === false && !values["force-enable"])
    throw new Error("producer offer is disabled; use --force-enable for invocation-only selection");
  for (const resource of manifest.resources) guards.push((await captureFile(resource.path)).guard);
  const policyPath = values.selection ?? request.selection;
  const declared = policyPath
    ? selection(JSON.parse(await readFile(policyPath, "utf8")))
    : { version: 1 as const, receivers: null };
  if (policyPath) guards.push((await captureFile(resolve(policyPath))).guard);
  const policy = request.policy ?? registryPolicy(keybindingConsumers.collection, values.scope);
  if (policy.scope !== values.scope) throw new Error("registry scope mismatch");
  const snapshot = await inspectRegistry(keybindingConsumers, policy);
  if (!snapshot.complete) throw new Error("cannot admit receivers from an incomplete registry");
  const requested = values.target;
  if (requested && new Set(requested).size !== requested.length)
    throw new Error("duplicate receiver selection");
  if (
    requested &&
    declared.receivers &&
    requested.some((id) => !declared.receivers!.some((entry) => entry.id === id))
  )
    throw new Error("requested receiver is outside declared selection");
  const explicit = requested ?? declared.receivers?.map((entry) => entry.id);
  const candidates = explicit ? explicit.map((id) => lookup(snapshot, id)) : snapshot.records;
  if ((values.profile || values["profile-selector"] || values.context) && candidates.length !== 1)
    throw new Error("profile/context override requires exactly one receiver");
  const members: AdmittedReceiver[] = [];
  for (const record of candidates) {
    if (record.state === "masked") {
      if (explicit) throw new Error(`receiver ${record.id} is masked`);
      continue;
    }
    if (record.state === "disabled" && !values["force-enable"]) {
      if (explicit) throw new Error(`receiver ${record.id} is disabled; use --force-enable`);
      continue;
    }
    if (!record.payload || record.state === "invalid" || record.state === "conflict")
      throw new Error(
        `receiver ${record.id} is ${record.state}: ${record.error ?? "unusable registration"}`,
      );
    const consumer = record.payload;
    if (consumer.adapter !== "niri" && consumer.adapter !== "umbriel") {
      if (explicit) throw new Error(`unsupported receiver adapter ${consumer.adapter}`);
      continue;
    }
    if (!manifest.targets.includes(consumer.adapter)) {
      if (explicit) throw new Error(`producer does not support receiver ${record.id}'s adapter`);
      continue;
    }
    const override = declared.receivers?.find((entry) => entry.id === record.id);
    if (override?.scope && override.scope !== values.scope)
      throw new Error("receiver scope override disagrees with invocation audience");
    const context = values.context ?? override?.context ?? consumer.defaultContext;
    if (!consumer.contexts.includes(context))
      throw new Error(`receiver ${record.id} does not advertise context ${context}`);
    const profile =
      values.profile ??
      resolvePathSelector(
        values["profile-selector"]
          ? JSON.parse(values["profile-selector"])
          : (override?.profile ?? consumer.profile),
        undefined,
        `receiver ${record.id} profile`,
      );
    const args = [
      "--manifest",
      resolve(manifestPath),
      "--target",
      consumer.adapter,
      "--profile",
      profile,
      "--context",
      context,
      "--scope",
      values.scope,
    ];
    if (values.mode) args.push("--mode", values.mode);
    if (values.runner) args.push("--runner", values.runner);
    const admitted = await admitKeybindingCommand("install", args, request.defaults, {
      command: "install",
      target: consumer.adapter,
      audience: values.scope,
      context,
      producer: manifest.producer,
    });
    admitted.manifest = {
      version: 1,
      producer: manifest.producer,
      order: manifest.order,
      resources: manifest.resources.map((entry) => ({ ...entry })),
      targets: [...manifest.targets],
    };
    const registration = registryGuard(policy, record.source);
    const descriptorGuard = (await captureFile(record.source.winner.path)).guard;
    admitted.options.inputGuards = [...guards, descriptorGuard];
    admitted.options.registryGuards = [registration];
    members.push({
      id: record.id,
      originalState: record.state,
      forced: record.state === "disabled" && values["force-enable"],
      registry: registration,
      admitted,
    });
  }
  if (members.length > 128) throw new Error("keybinding receiver batch exceeds admission bound");
  for (let i = 0; i < members.length; i++)
    for (let j = 0; j < i; j++) {
      const left = members[i]!.admitted.bound,
        right = members[j]!.admitted.bound;
      if (
        (await pathsSharePhysicalEntry(left.request.root.path, right.request.root.path)) ||
        (await pathsSharePhysicalEntry(left.statePath, right.statePath))
      )
        throw new Error("selected receivers alias the same owned root/membership");
    }
  return {
    version: 1,
    kind: "keybinding-batch",
    audience: values.scope,
    forceEnable: values["force-enable"],
    members,
    guards,
    publication: {
      source: publicationRequest.source,
      policy: providerPolicy,
      plan: publicationPlan,
    },
  };
}

export async function runAdmittedKeybindingBatch(batch: AdmittedKeybindingBatch): Promise<number> {
  await assertFileGuards(batch.guards);
  await assertRegistryGuards(batch.members.map((member) => member.registry));
  await applyRegistration(
    {
      domain: keybindingProviders,
      policy: batch.publication.policy,
      source: batch.publication.source,
    },
    batch.publication.plan,
  );
  const offered = await inspectRegistry(keybindingProviders, batch.publication.policy);
  const provider = lookup(offered, batch.publication.plan.id);
  const providerGuard = registryGuard(batch.publication.policy, provider.source);
  for (const member of batch.members) {
    member.admitted.options.registryGuards = [
      ...(member.admitted.options.registryGuards ?? []),
      providerGuard,
    ];
    console.log(
      `receiver ${member.id}: ${member.originalState}${member.forced ? " (forced for this invocation)" : ""}`,
    );
    const code = await runAdmittedKeybindingCommand(member.admitted);
    if (code !== 0) return code;
  }
  return 0;
}
