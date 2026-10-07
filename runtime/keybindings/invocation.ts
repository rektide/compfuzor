/** Domain batch admission. Receiver IDs are not native formats; membership commits remain per receiver. */
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import {
  captureFile,
  fileText,
  assertFileGuards,
  type FileGuard,
} from "../../files/config/capture.ts";
import { validatePathSelector, type PathSelector } from "../../files/config/context.ts";
import {
  admitKeybindingCommand,
  runAdmittedKeybindingCommand,
  type AdmittedKeybindingCommand,
  type KeybindingRuntimeDefaults,
} from "../../files/config/keybindings/runtime.ts";
import {
  pathsSharePhysicalEntry,
  pathsSharePhysicalDirectory,
} from "../../files/links/delivery.ts";
import { keybindingConsumers, keybindingProviders, resolveConsumerProfile } from "./registry.ts";
import { inspectRegistry, lookup } from "../registry/read.ts";
import { registryGuard, assertRegistryGuards, type RegistryGuard } from "../registry/guard.ts";
import type { RegistryPolicy, RegistryRecord, Scope } from "../registry/model.ts";
import type { Consumer } from "./registry.ts";
import { decodeYaml } from "../../files/config/keybindings/decode.ts";
import {
  planRegistration,
  applyRegistration,
  type RegistrationPlan,
} from "../registry/register.ts";
import { bindRegistryPolicies, type RegistryPolicyPair } from "./policy.ts";

export type ReceiverRequest = {
  id: string;
  profile?: PathSelector;
  context?: string;
  scope?: Scope;
  actionContexts?: Partial<Record<Scope, string>>;
};
export type SelectionPolicy = {
  version: 1;
  receivers: null | ReceiverRequest[];
  prospectiveConsumers?: Partial<Record<Scope, PathSelector[]>>;
};
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
  registries?: RegistryPolicyPair;
  registryPolicy?: string;
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
  const prospectiveConsumers: SelectionPolicy["prospectiveConsumers"] = {};
  if ("prospectiveConsumers" in value && value.prospectiveConsumers !== undefined) {
    if (
      !value.prospectiveConsumers ||
      typeof value.prospectiveConsumers !== "object" ||
      Array.isArray(value.prospectiveConsumers)
    )
      throw new Error("invalid prospective consumer references");
    for (const [audience, refs] of Object.entries(value.prospectiveConsumers)) {
      if (!["user", "system"].includes(audience) || !Array.isArray(refs))
        throw new Error("prospective consumers must be audience-scoped lists");
      prospectiveConsumers[audience as Scope] = refs.map((ref) =>
        validatePathSelector(ref, "prospective consumer"),
      );
    }
  }
  if (value.receivers === null) return { version: 1, receivers: null, prospectiveConsumers };
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
    if (
      raw.actionContexts !== undefined &&
      (typeof raw.actionContexts !== "object" ||
        raw.actionContexts === null ||
        Array.isArray(raw.actionContexts) ||
        Object.entries(raw.actionContexts).some(
          ([audience, context]) =>
            !["user", "system"].includes(audience) ||
            typeof context !== "string" ||
            !context.trim(),
        ))
    )
      throw new Error("invalid receiver audience/context mapping");
    return {
      id: raw.id,
      context: raw.context,
      scope: raw.scope,
      actionContexts: raw.actionContexts,
      ...(raw.profile === undefined
        ? {}
        : { profile: validatePathSelector(raw.profile, "receiver profile override") }),
    };
  });
  return { version: 1, receivers, prospectiveConsumers };
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
      "registry-policy": { type: "string" },
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
  const policies = await bindRegistryPolicies(
    values.scope,
    values["registry-policy"] ?? request.registryPolicy,
    request.registries ?? request.defaults.registries,
  );
  const providerPolicy = policies.providers;
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
  if (
    publicationPlan.effective.state === "invalid" ||
    publicationPlan.effective.state === "conflict"
  )
    throw new Error(`producer registration is ${publicationPlan.effective.state}`);
  if (publicationPlan.effective.state === "disabled" && !values["force-enable"])
    throw new Error("producer registration is disabled; use --force-enable");
  const guards: FileGuard[] = [
    manifestFile.guard,
    ...policies.guards,
    ...(publicationPlan.expectation.files ?? []),
  ];
  const providerView = await inspectRegistry(keybindingProviders, providerPolicy);
  if (!providerView.complete) throw new Error("incomplete provider registry during admission");
  const effectiveProvider = providerView.records.find((entry) => entry.id === manifest.producer);
  if (effectiveProvider) {
    if (!effectiveProvider.payload || !["active", "disabled"].includes(effectiveProvider.state))
      throw new Error(`producer registration is ${effectiveProvider.state}`);
    const { enabled: _ownedEnabled, ...ownedOffer } = manifest;
    const { enabled: _effectiveEnabled, ...effectiveOffer } = effectiveProvider.payload;
    if (JSON.stringify(ownedOffer) !== JSON.stringify(effectiveOffer))
      throw new Error("effective producer declaration redirects the owned operative offer");
    if (effectiveProvider.state === "disabled" && !values["force-enable"])
      throw new Error("producer registration is disabled; use --force-enable");
  }
  if (publicationPlan.effective.winner)
    guards.push((await captureFile(publicationPlan.effective.winner)).guard);
  if (manifest.enabled === false && !values["force-enable"])
    throw new Error("producer offer is disabled; use --force-enable for invocation-only selection");
  const resourceFiles = await Promise.all(
    manifest.resources.map((resource) => captureFile(resource.path)),
  );
  guards.push(...resourceFiles.map((file) => file.guard));
  const policyPath = values.selection ?? request.selection;
  const selectionFile = policyPath ? await captureFile(resolve(policyPath)) : undefined;
  const selectionText = selectionFile ? fileText(selectionFile) : undefined;
  if (selectionFile && selectionText === undefined)
    throw new Error("missing owner-held selection policy");
  const declared = selectionText
    ? selection(JSON.parse(selectionText))
    : { version: 1 as const, receivers: null };
  if (selectionFile) guards.push(selectionFile.guard);
  const policy = policies.consumers;
  if (policy.scope !== values.scope) throw new Error("registry scope mismatch");
  const snapshot = await inspectRegistry(keybindingConsumers, policy);
  if (!snapshot.complete) throw new Error("cannot admit receivers from an incomplete registry");
  const requested = values.target;
  if (requested && new Set(requested).size !== requested.length)
    throw new Error("duplicate receiver selection");
  const eligibleRequests = declared.receivers?.filter((entry) =>
    entry.actionContexts
      ? !!entry.actionContexts[values.scope as Scope]
      : !entry.scope || entry.scope === values.scope,
  );
  if (
    requested &&
    declared.receivers &&
    requested.some(
      (id) =>
        declared.receivers!.some((entry) => entry.id === id) &&
        !eligibleRequests!.some((entry) => entry.id === id),
    )
  )
    throw new Error("explicit receiver is outside invocation audience");
  if (
    requested &&
    declared.receivers &&
    requested.some((id) => !declared.receivers!.some((entry) => entry.id === id))
  )
    throw new Error("requested receiver is outside declared selection");
  type Candidate = Omit<RegistryRecord<Consumer>, "source"> & {
    source?: RegistryRecord<Consumer>["source"];
    descriptor: string;
    expectation?: RegistryGuard;
  };
  const available = new Map<string, Candidate>(
    snapshot.records.map((record) => [
      record.id,
      { ...record, descriptor: record.source.winner.path },
    ]),
  );
  const prospectiveIds = new Set<string>();
  for (const selector of declared.prospectiveConsumers?.[values.scope] ?? []) {
    if (!policyPath)
      throw new Error("prospective references require an owner-held selection document");
    const source = await resolveConsumerProfile(
      selector,
      resolve(policyPath),
      "prospective consumer descriptor",
    );
    const file = await captureFile(source),
      text = fileText(file);
    if (text === undefined) throw new Error("missing prospective consumer descriptor");
    const payload = keybindingConsumers.decode(JSON.parse(text));
    if (payload.audience !== values.scope || prospectiveIds.has(payload.id))
      throw new Error("invalid/duplicate prospective consumer audience/identity");
    prospectiveIds.add(payload.id);
    guards.push(file.guard);
    if (!available.has(payload.id)) {
      const planned = await planRegistration({ domain: keybindingConsumers, policy, source });
      if (planned.disposition === "blocked")
        throw new Error(`prospective consumer publication blocked: ${planned.reason}`);
      available.set(payload.id, {
        id: payload.id,
        state: payload.enabled === false ? "disabled" : "active",
        payload,
        descriptor: source,
        expectation: planned.expectation,
      });
    }
  }
  const explicit = requested ?? eligibleRequests?.map((entry) => entry.id);
  const candidates = explicit
    ? explicit.map((id) => {
        const candidate = available.get(id);
        if (!candidate) lookup(snapshot, id);
        return candidate!;
      })
    : [...available.values()].sort((a, b) => a.id.localeCompare(b.id));
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
    const descriptor = await captureFile(record.descriptor);
    const descriptorText = fileText(descriptor);
    if (
      descriptorText === undefined ||
      JSON.stringify(keybindingConsumers.decode(JSON.parse(descriptorText))) !==
        JSON.stringify(record.payload)
    )
      throw new Error(`receiver ${record.id} changed during admission`);
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
    if (override?.actionContexts && !override.actionContexts[values.scope])
      throw new Error("receiver is not declared for invocation audience");
    if (!override?.actionContexts && override?.scope && override.scope !== values.scope)
      throw new Error("receiver scope override disagrees with invocation audience");
    const context =
      values.context ??
      override?.actionContexts?.[values.scope] ??
      override?.context ??
      consumer.defaultContext;
    if (!consumer.contexts.includes(context))
      throw new Error(`receiver ${record.id} does not advertise context ${context}`);
    const profile =
      (values.profile ? resolve(values.profile) : undefined) ??
      (await resolveConsumerProfile(
        values["profile-selector"]
          ? JSON.parse(values["profile-selector"])
          : (override?.profile ?? consumer.profile),
        record.descriptor,
        `receiver ${record.id} profile`,
      ));
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
    const registration = record.expectation ?? registryGuard(snapshot.policy, record.source!);
    const descriptorGuard = descriptor.guard;
    admitted.options.inputGuards = [...guards, descriptorGuard];
    admitted.options.registryGuards = [registration, publicationPlan.expectation];
    members.push({
      id: record.id,
      originalState: record.state,
      forced: record.state === "disabled" && values["force-enable"],
      registry: registration,
      admitted,
    });
  }
  if (members.length > 128) throw new Error("keybinding receiver batch exceeds admission bound");
  if (members.length) {
    const identities = new Set<string>();
    for (const [index, file] of resourceFiles.entries()) {
      const path = manifest.resources[index]!.path;
      const text = fileText(file);
      if (text === undefined) throw new Error(`missing packaged producer resource ${path}`);
      const record = decodeYaml(text, path);
      const identity = `${record.kind}/${record.id}`;
      if (identities.has(identity))
        throw new Error(`duplicate packaged producer resource ${identity}`);
      identities.add(identity);
    }
  }
  for (let i = 0; i < members.length; i++)
    for (let j = 0; j < i; j++) {
      const left = members[i]!.admitted.bound,
        right = members[j]!.admitted.bound;
      if (
        (await pathsSharePhysicalEntry(left.request.root.path, right.request.root.path)) ||
        (await pathsSharePhysicalEntry(left.statePath, right.statePath)) ||
        (await pathsSharePhysicalEntry(left.request.root.path, right.statePath)) ||
        (await pathsSharePhysicalEntry(left.statePath, right.request.root.path)) ||
        (await pathsSharePhysicalDirectory(left.request.materialRoot, right.request.materialRoot))
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
  await assertRegistryGuards([batch.publication.plan.expectation]);
  for (const member of batch.members) {
    console.log(
      `receiver ${member.id}: ${member.originalState}${member.forced ? " (forced for this invocation)" : ""}`,
    );
    const code = await runAdmittedKeybindingCommand(member.admitted);
    if (code !== 0) return code;
  }
  return 0;
}
