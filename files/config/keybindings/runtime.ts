/**
 * Import-safe CLI admission shared by source and installed omnibus entry points.
 * Explicit commands select producer installation, host assembly, group toggling,
 * closure validation or lower-level consumer/registration operations. Other argv
 * are admitted only through the strict internal single-candidate processor parser.
 * No work runs at import; main may read profiles/manifests, mutate registration
 * batches, write private plans and spawn existing CONFIG/native workers.
 * Publication remains CONFIG's commit, not a CLI-owned transaction. Target/context/
 * scope are explicit; no PATH discovery, compositor reload or interactive adoption.
 * @see /doc/config/keybinding-producers.md
 * @see /doc/config/keybinding-consumers.md
 */
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { captureFile, fileText, assertFileGuards, type FileGuard } from "../capture.ts";
import { inspectRegistry } from "../../../runtime/registry/read.ts";
import { assertRegistryGuards } from "../../../runtime/registry/guard.ts";
import {
  keybindingConsumers,
  resolveConsumerProfile,
} from "../../../runtime/keybindings/registry.ts";
import {
  planRegistration,
  applyRegistration,
  type RegistrationPlan,
} from "../../../runtime/registry/register.ts";
import type { RegistryPolicy } from "../../../runtime/registry/model.ts";
import {
  bindRegistryPolicies,
  type RegistryPolicyPair,
} from "../../../runtime/keybindings/policy.ts";
import { parseArgs } from "node:util";
import { runProcessor } from "./processor.ts";
import { validateClosure } from "./closure.ts";
import { assembleConsumer, type ConsumerRequest } from "./consumer.ts";
import { withInputBatch, type InputRegistration } from "../registration.ts";
import { resolvePathSelector } from "../context.ts";
import {
  assembleHost,
  bindProfile,
  defaultProfile,
  installProducer,
  loadProfile,
  toggleGroup,
  validateProducerManifest,
  type BoundProfile,
  type HostOptions,
  type ProducerManifest,
} from "./membership.ts";
import type { ConfigScope } from "../context.ts";
import type { Target } from "./model.ts";

export type KeybindingHostCommand = "install" | "host" | "enable" | "disable";
export type KeybindingRuntimeDefaults = {
  runner?: string;
  validatorCommand: string[];
  registries?: RegistryPolicyPair;
};
export type KeybindingActionBinding = {
  command: "install" | "host";
  target: Target;
  audience: ConfigScope;
  context: string;
  /** A host assembly plan can assert assemble rather than accept install delivery modes. */
  mode?: "assemble";
  producer?: string;
};
export type AdmittedKeybindingCommand = {
  command: KeybindingHostCommand;
  options: HostOptions;
  bound: BoundProfile;
  manifest?: ProducerManifest;
  group?: string;
  registrySelection?: {
    id: string;
    originalState: "active" | "disabled";
    forceEnable: boolean;
    forced: boolean;
  };
  publication?: { source: string; policy: RegistryPolicy; plan: RegistrationPlan };
};

/** Load and bind the effective profile/context without membership, registration or publication. */
export async function admitKeybindingCommand(
  command: KeybindingHostCommand,
  args: string[],
  defaults: KeybindingRuntimeDefaults,
  binding?: KeybindingActionBinding,
): Promise<AdmittedKeybindingCommand> {
  const { values } = parseArgs({
    args,
    strict: true,
    allowPositionals: false,
    options: {
      manifest: { type: "string" },
      profile: { type: "string" },
      "profile-selector": { type: "string" },
      target: { type: "string", ...(binding ? { default: binding.target } : {}) },
      context: { type: "string", default: binding?.context ?? "user" },
      scope: { type: "string", default: binding?.audience ?? "user" },
      group: { type: "string" },
      mode: { type: "string" },
      check: { type: "boolean" },
      runner: { type: "string" },
      descriptor: { type: "string" },
      "force-enable": { type: "boolean", default: false },
      "registry-policy": { type: "string" },
    },
  });
  let receiver: AdmittedKeybindingCommand["registrySelection"];
  let receiverProfile: string | undefined;
  const registrationGuards: HostOptions["registryGuards"] = [];
  const registrationFiles: FileGuard[] = [];
  let publication: AdmittedKeybindingCommand["publication"];
  if (values.descriptor) {
    if (command !== "host")
      throw new Error("owned consumer descriptor applies only to host admission");
    const file = await captureFile(values.descriptor);
    const text = fileText(file);
    if (text === undefined) throw new Error("missing owned consumer descriptor");
    const own = keybindingConsumers.decode(JSON.parse(text));
    if (own.audience !== values.scope) throw new Error("owned consumer audience mismatch");
    const policies = await bindRegistryPolicies(
      own.audience,
      values["registry-policy"],
      defaults.registries,
    );
    const policy = policies.consumers;
    registrationFiles.push(...policies.guards);
    const publicationPlan = await planRegistration({
      domain: keybindingConsumers,
      policy,
      source: values.descriptor,
    });
    if (publicationPlan.disposition === "blocked")
      throw new Error(`owned receiver publication blocked: ${publicationPlan.reason}`);
    publication = { source: values.descriptor, policy, plan: publicationPlan };
    const view = await inspectRegistry(keybindingConsumers, policy);
    if (!view.complete) throw new Error("incomplete consumer registry during host admission");
    const record = view.records.find((entry) => entry.id === own.id);
    if (record?.state === "masked") throw new Error(`receiver ${own.id} is masked`);
    if (record && (record.state === "invalid" || record.state === "conflict"))
      throw new Error(`receiver ${own.id} is ${record.state}`);
    const registered = record ? await captureFile(record.source.winner.path) : undefined;
    if (registered) {
      const registeredText = fileText(registered);
      if (
        registeredText === undefined ||
        JSON.stringify(keybindingConsumers.decode(JSON.parse(registeredText))) !==
          JSON.stringify(record?.payload)
      )
        throw new Error("registered receiver changed during host admission");
    }
    const effective = record?.payload ?? own;
    const state =
      record?.state === "disabled" || (!record && own.enabled === false) ? "disabled" : "active";
    if (state === "disabled" && !values["force-enable"])
      throw new Error(`receiver ${own.id} is disabled; use --force-enable`);
    if (effective.adapter !== own.adapter || effective.audience !== own.audience)
      throw new Error("registered receiver disagrees with owned consumer");
    receiverProfile = await resolveConsumerProfile(
      effective.profile,
      record?.source.winner.path ?? values.descriptor,
      "advertised host profile",
    );
    if (
      receiverProfile !==
      (await resolveConsumerProfile(own.profile, values.descriptor, "owned host profile"))
    )
      throw new Error(
        "registered receiver redirects this owned host; select it through a producer instead",
      );
    if (!effective.contexts.includes(values.context!))
      throw new Error("host context is not advertised");
    values.target ??= own.adapter;
    if (values.target !== own.adapter) throw new Error("host native adapter mismatch");
    registrationFiles.push(file.guard);
    if (record) {
      registrationGuards.push(publicationPlan.expectation);
      registrationFiles.push(registered!.guard);
    } else registrationGuards.push(publicationPlan.expectation);
    receiver = {
      id: own.id,
      originalState: state,
      forceEnable: values["force-enable"],
      forced: state === "disabled" && values["force-enable"],
    };
  }
  if (values.target !== "niri" && values.target !== "umbriel")
    throw new Error("explicit --target niri|umbriel required");
  if (values.scope !== "user" && values.scope !== "system")
    throw new Error("--scope must be user or system");
  if (binding) {
    if (command !== binding.command)
      throw new Error("keybinding command does not match declared operation");
    if (values.target !== binding.target)
      throw new Error("keybinding target does not match declared operation");
    if (values.scope !== binding.audience)
      throw new Error(`keybinding scope does not match selected ${binding.audience} audience`);
    if (binding.mode && values.mode !== undefined && values.mode !== binding.mode)
      throw new Error(`keybinding mode must remain ${binding.mode} for the declared operation`);
    if (command === "host" && values.manifest !== undefined)
      throw new Error("host operation does not accept --manifest");
    if (values.group !== undefined)
      throw new Error("host/install operation does not accept --group");
  }
  if (values.mode !== undefined && !["assemble", "seed", "refresh"].includes(values.mode))
    throw new Error("keybinding mode must be assemble, seed, or refresh");
  const runner = values.runner ?? defaults.runner;
  if (!runner) throw new Error("installed CONFIG runner or --runner required");
  if (values.profile && values["profile-selector"])
    throw new Error("choose profile or profile-selector, not both");
  const requestedProfile = values["profile-selector"]
    ? resolvePathSelector(JSON.parse(values["profile-selector"]), undefined, "consumer profile")
    : (values.profile ?? receiverProfile);
  const profilePath = requestedProfile ? resolve(requestedProfile) : undefined;
  if (receiverProfile && profilePath !== receiverProfile)
    throw new Error("host profile override disagrees with advertised receiver");
  const loaded = profilePath
    ? await loadProfile(profilePath)
    : { profile: defaultProfile(values.target) };
  if (loaded.profile.target !== values.target) throw new Error("consumer profile target mismatch");
  const options: HostOptions = {
    ...loaded,
    context: values.context!,
    scope: values.scope,
    runner,
    validatorCommand: [...defaults.validatorCommand],
    mode: (values.mode ??
      binding?.mode ??
      (command === "host" ? "seed" : undefined)) as HostOptions["mode"],
    check: values.check,
    inputGuards: registrationFiles,
    registryGuards: registrationGuards,
  };
  const bound = bindProfile(options);
  // Native include expansion belongs to this selected invocation, not later body exports.
  bound.request.environment ??= { HOME: process.env.HOME };
  if (binding) {
    const placement = options.profile.placement ?? "link";
    const registration = options.profile.registration ?? "link";
    if (!["direct", "copy", "link"].includes(placement))
      throw new Error("invalid native placement policy");
    if (!["copy", "link"].includes(registration))
      throw new Error("invalid source registration policy");
    options.profile = {
      ...structuredClone(options.profile),
      placement,
      registration,
      placementDirectory: {
        path: resolvePathSelector(
          options.profile.placementDirectory ?? { relative: "keybindings" },
          bound.base,
          "placement directory",
        ),
      },
      userSources: (options.profile.userSources ?? []).map((source) => ({
        ...source,
        path: { path: resolvePathSelector(source.path, bound.base, "consumer source") },
      })),
    };
  }
  let manifest: ProducerManifest | undefined;
  if (command === "install") {
    if (!values.manifest) throw new Error("install requires --manifest");
    manifest = JSON.parse(await readFile(values.manifest, "utf8")) as ProducerManifest;
    validateProducerManifest(manifest, options.profile.target);
    if (binding?.producer && manifest.producer !== binding.producer)
      throw new Error("producer manifest does not match declared operation");
    if (options.check)
      throw new Error("producer registration is explicit mutation; check host assembly instead");
  }
  if (command === "enable" || command === "disable") {
    if (!values.group) throw new Error("enable/disable requires --group");
    if (values.check) throw new Error("membership mutation does not accept --check");
  }
  return {
    command,
    options,
    bound,
    manifest,
    group: values.group,
    registrySelection: receiver,
    publication,
  };
}

/** Reuse the admitted binding while keeping each complete domain operation's commit boundary. */
export async function runAdmittedKeybindingCommand(
  admitted: AdmittedKeybindingCommand,
): Promise<number> {
  const { command, options, bound } = admitted;
  await assertFileGuards(options.inputGuards ?? []);
  await assertRegistryGuards(options.registryGuards ?? []);
  const result =
    command === "install"
      ? await installProducer(admitted.manifest!, options, bound)
      : command === "host"
        ? await assembleHost(options, bound)
        : await toggleGroup(admitted.group!, command === "enable", options, bound);
  if (result.code === 0 && !options.check && options.mode !== "assemble" && admitted.publication) {
    await applyRegistration(
      {
        domain: keybindingConsumers,
        policy: admitted.publication.policy,
        source: admitted.publication.source,
      },
      admitted.publication.plan,
    );
  }
  return result.code;
}

/**
 * Dispatch one explicit keybinding operation and return its process-style outcome.
 * Install defaults native delivery to seed while managed YAML registration refreshes;
 * host CLI also defaults to seed (assembleHost's direct API defaults assemble).
 * Enable/disable stage membership with reassembly. Profile selectors resolve at
 * invocation; generated scope must match the chosen context. Register/install reject
 * --check because registration is a real mutation, unlike assembly preview.
 * @param argv Arguments after the domain alias; supported operations are install,
 * host, enable, disable, validate, assemble, register, or internal --config flags.
 * @param defaults Host-supplied installed worker/hook binding. runner may be omitted
 * for source use requiring --runner; validatorCommand is executable plus fixed argv,
 * not a shell command string. Consumer preparation appends its private --plan path.
 * @returns Runner/consumer code, or zero for successful hook/processor-only work.
 * @throws On strict argument/protocol errors, scope/profile mismatch, invalid files
 * or delegated registration/preparation failures; the outer entry owns error reporting.
 */
export async function main(argv: string[], defaults: KeybindingRuntimeDefaults): Promise<number> {
  const [command, ...args] = argv;
  if (command === "complete") {
    const { completeKeybindings } = await import("../../../runtime/keybindings/completion.ts");
    return completeKeybindings(args);
  }
  if (command === "install-offer") {
    if (args.includes("--help") || args.includes("-h")) {
      console.log(
        "install-offer --manifest PATH [--selection POLICY] [--target RECEIVER ...] [--scope user|system] [--force-enable]\n--force-enable skips only registration disabled directives for this invocation; masks remain vetoes.",
      );
      return 0;
    }
    const { admitKeybindingBatch, runAdmittedKeybindingBatch } =
      await import("../../../runtime/keybindings/invocation.ts");
    return runAdmittedKeybindingBatch(await admitKeybindingBatch({ args, defaults }));
  }
  if (["install", "host", "enable", "disable"].includes(command)) {
    if (args.includes("--help") || args.includes("-h")) {
      console.log(
        `${command} --target NATIVE --profile PATH --context ID --scope user|system\nOwned host admission also accepts --descriptor PATH and --force-enable.\n--force-enable overrides only registration disabled directives for this invocation; masks and producer-group state remain authoritative.`,
      );
      return 0;
    }
    return runAdmittedKeybindingCommand(
      await admitKeybindingCommand(command as KeybindingHostCommand, args, defaults),
    );
  }
  if (command === "validate") {
    const { values } = parseArgs({
      args,
      options: { plan: { type: "string" } },
      strict: true,
      allowPositionals: false,
    });
    if (!values.plan) throw new Error("validate requires --plan");
    await validateClosure(values.plan, process.env);
    return 0;
  }
  if (command !== "assemble" && command !== "register") {
    await runProcessor(argv, process.env);
    return 0;
  }
  const { values } = parseArgs({
    args,
    options: {
      request: { type: "string" },
      batch: { type: "string" },
      runner: { type: "string" },
      check: { type: "boolean" },
    },
    strict: true,
    allowPositionals: false,
  });
  if (!values.request) throw new Error("assemble requires explicit --request");
  const runner = values.runner ?? defaults.runner;
  if (!runner) throw new Error("assemble requires --runner outside an installed deployment");
  const request = JSON.parse(await readFile(values.request, "utf8")) as ConsumerRequest;
  const assemble = () =>
    assembleConsumer({
      request,
      runner,
      validatorCommand: defaults.validatorCommand,
      check: values.check,
    });
  if (command === "assemble" && values.batch) throw new Error("--batch requires register");
  if (command === "register" && !values.batch) throw new Error("register requires --batch");
  if (command === "register" && values.check)
    throw new Error("register mutates selected registrations; --check is assembly-only");
  let result;
  if (command === "register") {
    const records = JSON.parse(await readFile(values.batch!, "utf8")) as InputRegistration[];
    if (!Array.isArray(records)) throw new Error("registration batch must be an array");
    result = await withInputBatch(records, assemble, { success: (outcome) => outcome.code === 0 });
  } else result = await assemble();
  return result.code;
}
