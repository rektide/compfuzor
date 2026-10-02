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
import { parseArgs } from "node:util";
import { runProcessor } from "./processor.ts";
import { validateClosure } from "./closure.ts";
import { assembleConsumer, type ConsumerRequest } from "./consumer.ts";
import { withInputBatch, type InputRegistration } from "../registration.ts";
import { resolvePathSelector } from "../context.ts";
import {
  assembleHost,
  defaultProfile,
  installProducer,
  loadProfile,
  toggleGroup,
  type HostOptions,
  type ProducerManifest,
} from "./membership.ts";

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
export async function main(
  argv: string[],
  defaults: {
    /** Installed CONFIG runner selected by the omnibus; explicit --runner may override it. */
    runner?: string;
    /** Existing closure-validator executable and fixed prefix, supplied by the entry adapter. */
    validatorCommand: string[];
  },
): Promise<number> {
  const [command, ...args] = argv;
  if (["install", "host", "enable", "disable"].includes(command)) {
    const { values } = parseArgs({
      args,
      strict: true,
      allowPositionals: false,
      options: {
        manifest: { type: "string" },
        profile: { type: "string" },
        "profile-selector": { type: "string" },
        target: { type: "string" },
        context: { type: "string", default: "user" },
        scope: { type: "string", default: "user" },
        group: { type: "string" },
        mode: { type: "string" },
        check: { type: "boolean" },
        runner: { type: "string" },
      },
    });
    if (values.target !== "niri" && values.target !== "umbriel")
      throw new Error("explicit --target niri|umbriel required");
    if (values.scope !== "user" && values.scope !== "system")
      throw new Error("--scope must be user or system");
    const runner = values.runner ?? defaults.runner;
    if (!runner) throw new Error("installed CONFIG runner or --runner required");
    if (values.profile && values["profile-selector"])
      throw new Error("choose profile or profile-selector, not both");
    const profilePath = values["profile-selector"]
      ? resolvePathSelector(JSON.parse(values["profile-selector"]), undefined, "consumer profile")
      : values.profile;
    const loaded = profilePath
      ? await loadProfile(profilePath)
      : { profile: defaultProfile(values.target) };
    if (loaded.profile.target !== values.target)
      throw new Error("consumer profile target mismatch");
    const options: HostOptions = {
      ...loaded,
      context: values.context!,
      scope: values.scope,
      runner,
      validatorCommand: defaults.validatorCommand,
      mode: values.mode as HostOptions["mode"],
      check: values.check,
    };
    let result;
    if (command === "install") {
      if (!values.manifest) throw new Error("install requires --manifest");
      const manifest = JSON.parse(await readFile(values.manifest, "utf8")) as ProducerManifest;
      result = await installProducer(manifest, options);
    } else if (command === "host")
      result = await assembleHost({ ...options, mode: options.mode ?? "seed" });
    else {
      if (!values.group) throw new Error("enable/disable requires --group");
      if (values.check) throw new Error("membership mutation does not accept --check");
      result = await toggleGroup(values.group, command === "enable", options);
    }
    return result.code;
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
