/** Zim command parsing, context selection, strategy normalization, and help. */

import { basename, join, resolve } from "node:path";
import { parseArgs } from "node:util";

import { getConfigContext, type ConfigSpec } from "../config/context.ts";
import type { ConfigInstallStrategy } from "../config/install.ts";
import type { InputStrategy } from "../config/inputs.ts";
import { resolveSelectedName } from "../config/invocation.ts";
import type { ZimSpec } from "./activation.ts";

export type ZimAction = "install" | "import" | "status";

export type ZimCliOptions = {
  action: ZimAction;
  context?: string;
  install?: ConfigInstallStrategy;
  dropins?: InputStrategy;
  invokedAs: string;
  zimSpecPath: string;
  configSpecPath: string;
  configSpecExplicit?: boolean;
  configRunner: string;
  activationOnly: boolean;
  assembleCanonical: boolean;
  createDestParent: boolean;
  args: string[];
};

export type ZimSettings = {
  contextName: string;
  install?: ConfigInstallStrategy;
  dropins?: InputStrategy;
};

const HELP: Record<ZimAction, string> = {
  install: `Usage: install-zim.sh [--context NAME] [--install assemble|copy|link] [--dropins copy|link]

Install and activate Zim for a selected context: install its CONFIG recipes,
project startup loaders, build both caches, wire the loaders into the context's
dotfiles (when declared), and publish the registry link.

Options:
  --context NAME                 Select a declared Zim context
  --install assemble|copy|link  Override CONFIG output installation
  --dropins copy|link            Override CONFIG input delivery
  --assemble-canonical           Assemble the canonical donor configs before
                                 the CONFIG install -- the copy/link
                                 strategies publish those donor outputs,
                                 which do not exist yet on a fresh host --
                                 and before publishing the registry link
                                 (same as config-assemble.sh --context
                                 canonical)
  --create-dest-parent           Create the registry destination's missing
                                 parent directory before linking

The registry preflight runs after activation: on a registry failure the
completed activation changes remain. Fix the stated cause and rerun --
activation is idempotent. These flags are options of install-zim.sh itself;
the aggregate install.sh compositor forwards its own arguments to every
child, so pass them to install-zim.sh directly.`,
  import: `Usage: install-zim-context.sh [--context NAME] [--dropins copy|link] PRODUCER_DIR

Import a producer's Zim fragments into a selected consumer context, then rebuild
only the channels that received fragments.

Options:
  --context NAME       Select a declared Zim context
  --dropins copy|link  Select imported fragment representation`,
  status: `Usage: status-zim.sh [--context NAME] [--activation-only]

Report Zim activation health: CONFIG state, startup loaders, both caches, and
the registry link. Exit 0 is clean, 1 is drift, and 2 is an evaluation error.

Options:
  --context NAME     Select a declared Zim context
  --activation-only  Skip CONFIG rows (used by aggregate status)`,
};

function fail(message: string): never {
  throw new Error(message);
}

export function parseInstallStrategy(
  value: string | undefined,
  label: string,
): ConfigInstallStrategy {
  if (value === "assemble" || value === "copy" || value === "link") return value;
  fail(`${label} must be assemble, copy, or link`);
}

export function parseInputStrategy(value: string | undefined, label: string): InputStrategy {
  if (value === "copy" || value === "link") return value;
  fail(`${label} must be copy or link`);
}

export function parseZimArgs(argv: string[], deploymentDir: string): ZimCliOptions {
  const { values, positionals } = parseArgs({
    args: argv,
    strict: true,
    allowPositionals: true,
    options: {
      context: { type: "string" },
      install: { type: "string" },
      dropins: { type: "string" },
      "invoked-as": { type: "string" },
      spec: { type: "string" },
      "config-spec": { type: "string" },
      "config-runner": { type: "string" },
      "activation-only": { type: "boolean" },
      "assemble-canonical": { type: "boolean" },
      "create-dest-parent": { type: "boolean" },
      help: { type: "boolean", short: "h" },
    },
  });
  const actionIndex = positionals.findIndex(
    (value) => value === "install" || value === "import" || value === "status",
  );
  const action = actionIndex < 0 ? undefined : (positionals[actionIndex] as ZimAction);
  if (values.help) {
    console.log(action ? HELP[action] : Object.values(HELP).join("\n\n"));
    process.exit(0);
  }
  if (!action) fail("expected Zim action: install, import, or status");
  const args = positionals.toSpliced(actionIndex, 1);
  if (action !== "import" && args.length > 0)
    fail(`${action} does not accept positional arguments`);
  if (action === "import" && args.length !== 1)
    fail("import requires exactly one producer directory");
  if (values["activation-only"] && action !== "status") fail("--activation-only requires status");
  if ((values["assemble-canonical"] || values["create-dest-parent"]) && action !== "install")
    fail("--assemble-canonical and --create-dest-parent require install");
  return {
    action,
    context: values.context,
    install:
      values.install === undefined ? undefined : parseInstallStrategy(values.install, "--install"),
    dropins:
      values.dropins === undefined ? undefined : parseInputStrategy(values.dropins, "--dropins"),
    invokedAs: basename(values["invoked-as"] ?? "install-zim.sh"),
    zimSpecPath: resolve(values.spec ?? join(deploymentDir, "etc", "zim.spec.json")),
    configSpecPath: resolve(
      values["config-spec"] ?? join(deploymentDir, "etc", "config.spec.json"),
    ),
    configSpecExplicit: values["config-spec"] !== undefined,
    configRunner: resolve(
      values["config-runner"] ?? join(deploymentDir, "bin", "config", "run.sh"),
    ),
    activationOnly: values["activation-only"] ?? false,
    assembleCanonical: values["assemble-canonical"] ?? false,
    createDestParent: values["create-dest-parent"] ?? false,
    args,
  };
}

function aliasContext(invokedAs: string, spec: ZimSpec): string | undefined {
  if (invokedAs === "install-zim.sh") return undefined;
  const match = /^install-zim-(.+)\.sh$/.exec(invokedAs);
  if (!match)
    fail(
      `unsupported Zim command alias ${invokedAs}; use install-zim-CONTEXT.sh or explicit --context`,
    );
  if (!(match[1] in spec.contexts))
    fail(`Zim command alias ${invokedAs} names undeclared context ${match[1]}`);
  return match[1];
}

export function resolveSettings(
  options: ZimCliOptions,
  spec: ZimSpec,
  configSpec: ConfigSpec,
): ZimSettings {
  const contextName = resolveSelectedName({
    explicit: options.context,
    invokedAs: options.invokedAs,
    inferAlias: (invokedAs) =>
      options.action === "install" ? aliasContext(invokedAs, spec) : undefined,
    environment: process.env.COMPFUZOR_ZIM_CONTEXT ?? process.env.COMPFUZOR_CONTEXT,
    fallback: spec.defaultContext,
    declared: Object.keys(spec.contexts),
    label: "Zim context",
  });
  const activation = spec.contexts[contextName];
  const configContext = getConfigContext(configSpec, activation.config);
  if (configContext.scope !== activation.scope)
    fail(`Zim context ${contextName} scope does not match config context ${activation.config}`);
  const install = options.action === "install" ? options.install : undefined;
  const dropins =
    options.action === "import"
      ? (options.dropins ??
        parseInputStrategy(
          process.env.COMPFUZOR_ZIM_DROPINS_STRATEGY ??
            process.env.COMPFUZOR_CONFIG_DROPINS_STRATEGY ??
            configContext.dropins ??
            "link",
          "effective drop-in strategy",
        ))
      : options.action === "install"
        ? options.dropins
        : undefined;
  return { contextName, install, dropins };
}
