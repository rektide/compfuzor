/** Domain-local admission/execution is reused; this module only binds a plan invocation. */
import { resolve } from "node:path";
import {
  admitConfigCommand,
  runAdmittedConfigCommand,
  type AdmittedConfigCommand,
} from "../config/runtime.ts";
import { configHelp, parseConfigCommandArgs, type ConfigAction } from "../config/cli.ts";
import { getConfigContext } from "../config/context.ts";
import {
  admitKeybindingCommand,
  runAdmittedKeybindingCommand,
  type AdmittedKeybindingCommand,
} from "../config/keybindings/runtime.ts";
import { fail, type Audience, type DomainStep } from "./model.ts";
import {
  admitKeybindingBatch,
  runAdmittedKeybindingBatch,
  type AdmittedKeybindingBatch,
} from "../../runtime/keybindings/invocation.ts";

export type PreparedOperation =
  | { domain: "config"; admitted: AdmittedConfigCommand }
  | { domain: "keybindings"; admitted: AdmittedKeybindingCommand }
  | { domain: "keybindings-batch"; admitted: AdmittedKeybindingBatch }
  | { domain: "help"; message: string };

export async function prepareOperation(
  step: DomainStep,
  audience: Audience,
  argv: string[],
  deploymentDir: string,
  runtimePath: string,
): Promise<PreparedOperation> {
  if (step.operation === "install-offer") {
    if (argv.includes("--help") || argv.includes("-h"))
      return {
        domain: "help",
        message:
          "install-offer [--target RECEIVER ...] [--force-enable] [--profile-selector JSON] [--context ID]",
      };
    return {
      domain: "keybindings-batch",
      admitted: await admitKeybindingBatch({
        args: argv,
        manifest: step.manifest,
        selection: step.selection,
        producer: step.producer,
        audience,
        defaults: {
          runner: resolve(deploymentDir, "bin/config/run.sh"),
          validatorCommand: [process.execPath, runtimePath, "keybindings", "validate"],
        },
      }),
    };
  }
  if (step.domain === "config") {
    const invokedAs = `config-${step.operation}.sh`;
    const args = ["--spec", resolve(deploymentDir, step.spec ?? "etc/config.spec.json"), ...argv];
    const options = parseConfigCommandArgs(args, deploymentDir, invokedAs, true);
    if (options.help) return { domain: "help", message: configHelp(invokedAs, args) };
    return {
      domain: "config",
      admitted: await admitConfigCommand(options, {
        action: step.operation as ConfigAction,
        audience,
        context: step.context,
      }),
    };
  }
  const args: string[] = [];
  if (step.profile) args.push("--profile", step.profile);
  if (step.profileSelector) args.push("--profile-selector", JSON.stringify(step.profileSelector));
  if (step.manifest) args.push("--manifest", step.manifest);
  if (step.descriptor) args.push("--descriptor", step.descriptor);
  return {
    domain: "keybindings",
    admitted: await admitKeybindingCommand(
      step.operation as "host" | "install",
      [...args, ...argv],
      {
        runner: resolve(deploymentDir, "bin/config/run.sh"),
        validatorCommand: [process.execPath, runtimePath, "keybindings", "validate"],
      },
      {
        command: step.operation as "host" | "install",
        audience,
        context: step.context,
        target: step.target!,
        mode: step.mode,
        producer: step.producer,
      },
    ),
  };
}

export function verifyPreparedOperation(
  value: PreparedOperation,
  step: DomainStep,
  audience: Audience,
): void {
  if (value.domain === "help") {
    if (typeof value.message !== "string") fail("invalid prepared help");
    return;
  }
  if (step.operation === "install-offer") {
    if (
      value.domain !== "keybindings-batch" ||
      value.admitted.kind !== "keybinding-batch" ||
      value.admitted.version !== 1 ||
      value.admitted.audience !== audience ||
      typeof value.admitted.forceEnable !== "boolean" ||
      !Array.isArray(value.admitted.members) ||
      value.admitted.members.length > 128
    )
      fail("invalid admitted receiver batch");
    if (value.admitted.publication?.plan.id !== step.producer)
      fail("prepared prospective producer mismatch");
    const ids = new Set<string>();
    for (const member of value.admitted.members) {
      if (
        ids.has(member.id) ||
        member.admitted.command !== "install" ||
        member.admitted.options.scope !== audience ||
        member.admitted.options.profile.contexts[member.admitted.options.context]?.scope !==
          audience ||
        member.admitted.manifest?.producer !== step.producer ||
        !member.admitted.bound.request.root.path ||
        !["active", "disabled"].includes(member.originalState) ||
        member.forced !== (member.originalState === "disabled" && value.admitted.forceEnable) ||
        (member.originalState === "disabled" && !value.admitted.forceEnable)
      )
        fail("prepared receiver member mismatch");
      ids.add(member.id);
    }
    return;
  }
  if (value.domain !== step.domain) fail("prepared operation domain mismatch");
  if (value.domain === "config") {
    const context = getConfigContext(value.admitted.spec, value.admitted.contextName);
    if (value.admitted.action !== step.operation || context.scope !== audience || context.canonical)
      fail("prepared config selection mismatch");
    for (const binding of Object.values(context.configs)) {
      if (
        !binding.output.path ||
        binding.output.relative ||
        binding.output.env ||
        binding.inputs.some((input) => !input.path || input.relative || input.env)
      )
        fail("prepared config receivers are not frozen");
    }
  } else {
    const { options, command, bound } = value.admitted;
    if (
      command !== step.operation ||
      options.scope !== audience ||
      options.profile.contexts[options.context]?.scope !== audience ||
      options.profile.target !== step.target ||
      (step.mode && options.mode !== step.mode) ||
      !bound.request.root.path
    )
      fail("prepared keybinding selection mismatch");
    if (step.producer && value.admitted.manifest?.producer !== step.producer)
      fail("prepared producer identity mismatch");
  }
}

export async function applyOperation(prepared: PreparedOperation): Promise<number> {
  if (prepared.domain === "help") {
    console.log(prepared.message);
    return 0;
  }
  if (prepared.domain === "keybindings-batch") return runAdmittedKeybindingBatch(prepared.admitted);
  return prepared.domain === "config"
    ? runAdmittedConfigCommand(prepared.admitted)
    : runAdmittedKeybindingCommand(prepared.admitted);
}
