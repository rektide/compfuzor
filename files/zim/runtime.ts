/** Complete Zim install, producer import, and status orchestration. */

import { mkdtemp, readFile, readdir, rm, stat, writeFile } from "node:fs/promises"
import { basename, dirname, join, resolve } from "node:path"
import { tmpdir } from "node:os"

import { runAssembly } from "../config/assembly.ts"
import { getConfigContext, type ConfigSpec } from "../config/context.ts"
import { installContext } from "../config/install.ts"
import { putInput } from "../config/inputs.ts"
import { statusContext } from "../config/status.ts"
import {
  activationHealthy,
  buildChannel,
  installActivation,
  resolveActivation,
  runCommand,
  type Activation,
  type ZimCanonical,
  type ZimSpec,
} from "./activation.ts"
import {
  parseInputStrategy,
  parseInstallStrategy,
  parseZimArgs,
  resolveSettings,
  type ZimCliOptions,
  type ZimSettings,
} from "./cli.ts"

export { zshQuote } from "./activation.ts"
export { parseZimArgs, resolveSettings } from "./cli.ts"
export type { ZimCliOptions, ZimSettings } from "./cli.ts"

function fail(message: string): never {
  throw new Error(message)
}

function truthy(value: string | undefined): boolean {
  return ["1", "true", "y", "yes"].includes(value?.trim().toLowerCase() ?? "")
}

async function withRegistryManifest<T>(activation: Activation, canonical: ZimCanonical, callback: (path: string) => Promise<T>): Promise<T> {
  const temporary = await mkdtemp(join(tmpdir(), "compfuzor-zim-registry-"))
  const path = join(temporary, "links.json")
  const manifest = {
    version: 1,
    deployment: { dir: dirname(canonical.controller) },
    links: [{
      id: `zim-registry-${activation.name}`,
      scope: activation.spec.scope,
      src: canonical.registry,
      dest: activation.registry,
      policy: "replace",
      state: "present",
    }],
  }
  try {
    await writeFile(path, JSON.stringify(manifest), { mode: 0o600 })
    return await callback(path)
  } finally {
    await rm(temporary, { recursive: true, force: true })
  }
}

async function runRegistry(action: "apply" | "status", activation: Activation, canonical: ZimCanonical, deploymentDir: string): Promise<number> {
  return withRegistryManifest(activation, canonical, async (manifest) => {
    const args = [action, "--scope", activation.spec.scope]
    if (action === "apply") args.push("--sudo", "never")
    args.push(manifest)
    return (await runCommand(join(deploymentDir, "bin", "links.mjs"), args)).code
  })
}

async function installZim(options: ZimCliOptions, settings: ZimSettings, activation: Activation, spec: ZimSpec, deploymentDir: string): Promise<number> {
  const configContext = getConfigContext(activation.configSpec, activation.spec.config)
  const configResult = await installContext({
    spec: activation.configSpec,
    contextName: activation.spec.config,
    runner: options.configRunner,
    names: ["zimrc", "zimenv"],
    strategy: () => settings.install ?? parseInstallStrategy(
      process.env.COMPFUZOR_ZIM_INSTALL_STRATEGY ?? process.env.COMPFUZOR_CONFIG_INSTALL_STRATEGY ?? configContext.install ?? "assemble",
      "effective install strategy",
    ),
    inputStrategy: () => settings.dropins ?? parseInputStrategy(
      process.env.COMPFUZOR_ZIM_DROPINS_STRATEGY ?? process.env.COMPFUZOR_CONFIG_DROPINS_STRATEGY ?? configContext.dropins ?? "link",
      "effective drop-in strategy",
    ),
  })
  if (configResult.code !== 0) return configResult.code
  if (configResult.status === "skipped") {
    const available = await Promise.all([activation.zimenv, activation.zimrc].map(async (path) => {
      try {
        return (await stat(path)).isFile()
      } catch {
        return false
      }
    }))
    console.error(`skipped Zim config install for ${activation.name}: ${configResult.reason}`)
    if (!available.every(Boolean)) {
      console.error(`skipped remaining Zim install for ${activation.name}: required config outputs are unavailable`)
      return 0
    }
  }
  await installActivation(activation, spec.canonical)
  const registryResult = await runRegistry("apply", activation, spec.canonical, deploymentDir)
  if (registryResult !== 0) return registryResult
  return 0
}

async function inventoryProducer(producer: string): Promise<Array<{ channel: "zimrc" | "zimenv"; source: string; disabled: boolean }>> {
  const records: Array<{ channel: "zimrc" | "zimenv"; source: string; disabled: boolean }> = []
  const seen = new Set<string>()
  for (const channel of ["zimenv", "zimrc"] as const) {
    for (const state of ["active", "disabled"] as const) {
      const directory = join(producer, "etc", "zim", channel, state)
      let entries
      try {
        entries = await readdir(directory, { withFileTypes: true, encoding: "utf8" })
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === "ENOENT") continue
        throw error
      }
      for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
        if (!entry.name.endsWith(".conf") || (!entry.isFile() && !entry.isSymbolicLink())) continue
        const key = `${channel}/${entry.name}`
        if (seen.has(key)) fail(`producer has both active and disabled entries: ${key}`)
        seen.add(key)
        records.push({ channel, source: join(directory, entry.name), disabled: state === "disabled" })
      }
    }
  }
  return records
}

async function importProducer(options: ZimCliOptions, settings: ZimSettings, activation: Activation, spec: ZimSpec): Promise<number> {
  const records = await inventoryProducer(resolve(options.args[0]))
  const touched = new Set<"zimrc" | "zimenv">()
  for (const record of records) {
    const result = await putInput({
      spec: activation.configSpec,
      contextName: activation.spec.config,
      runner: options.configRunner,
      strategy: settings.dropins!,
      rebuild: false,
      initiallyDisabled: record.disabled,
      selector: `${record.channel}/${record.channel}`,
      source: record.source,
      name: basename(record.source),
    })
    if (result !== 0) return result
    touched.add(record.channel)
  }
  for (const channel of ["zimenv", "zimrc"] as const) {
    if (!touched.has(channel)) continue
    const assembled = await runAssembly({
      spec: activation.configSpec,
      contextName: activation.spec.config,
      runner: options.configRunner,
      names: [channel],
    })
    if (assembled !== 0) return assembled
    await buildChannel(channel, activation, spec.canonical)
  }
  console.log(`install-zim-context: imported ${records.length} fragment(s) for context ${activation.name}`)
  return 0
}

async function statusZim(activation: Activation, spec: ZimSpec, deploymentDir: string, configRunner: string, activationOnly: boolean): Promise<number> {
  const configResult = activationOnly ? 0 : await statusContext({
    spec: activation.configSpec,
    contextName: activation.spec.config,
    runner: configRunner,
    names: ["zimrc", "zimenv"],
    format: "human",
  })
  const healthy = await activationHealthy(activation, spec.canonical)
  const registryResult = await runRegistry("status", activation, spec.canonical, deploymentDir)
  if (configResult === 2 || registryResult === 2) return 2
  return configResult === 0 && healthy && registryResult === 0 ? 0 : 1
}

export async function runZim(options: ZimCliOptions, deploymentDir: string): Promise<number> {
  if (options.action !== "status" && truthy(process.env.COMPFUZOR_ZIM_BYPASS)) {
    console.error(`skipped Zim ${options.action}: COMPFUZOR_ZIM_BYPASS`)
    return 0
  }
  const [zimSpec, configSpec] = await Promise.all([
    readFile(options.zimSpecPath, "utf8").then((text) => JSON.parse(text) as ZimSpec),
    readFile(options.configSpecPath, "utf8").then((text) => JSON.parse(text) as ConfigSpec),
  ])
  if (zimSpec.version !== 2) {
    fail(`unsupported Zim spec version: ${String(zimSpec.version)}; rerender the deployment with the current playbook (expected version 2)`)
  }
  const settings = resolveSettings(options, zimSpec, configSpec)
  const activation = resolveActivation(settings.contextName, zimSpec, configSpec)
  if (options.action === "install") return installZim(options, settings, activation, zimSpec, deploymentDir)
  if (options.action === "import") return importProducer(options, settings, activation, zimSpec)
  return statusZim(activation, zimSpec, deploymentDir, options.configRunner, options.activationOnly)
}

export async function main(argv: string[], deploymentDir: string): Promise<number> {
  return runZim(parseZimArgs(argv, deploymentDir), deploymentDir)
}
