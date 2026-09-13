/** Complete ordinary CONFIG install over typed assembly and delivery operations. */

import { runAssembly } from "./assembly.ts"
import type { ConfigSpec } from "./context.ts"
import { syncInputs, type InputStrategy } from "./inputs.ts"
import { publishOutputs } from "./publication.ts"

export type ConfigInstallStrategy = "assemble" | InputStrategy
export type ConfigInstallOutcome = {
  status: "completed" | "skipped"
  code: number
  reason?: string
}

type Resolved<T> = T | (() => T)

export type InstallContextOptions = {
  spec: ConfigSpec
  contextName: string
  runner: string
  names: string[]
  strategy: Resolved<ConfigInstallStrategy>
  inputStrategy?: Resolved<InputStrategy>
}

function truthy(value: string | undefined): boolean {
  return ["1", "true", "y", "yes"].includes(value?.trim().toLowerCase() ?? "")
}

function resolve<T>(value: Resolved<T>): T {
  return typeof value === "function" ? (value as () => T)() : value
}

export async function installContext(options: InstallContextOptions): Promise<ConfigInstallOutcome> {
  const reason = truthy(process.env.COMPFUZOR_CONFIG_CONTEXTS_BYPASS)
    ? "COMPFUZOR_CONFIG_CONTEXTS_BYPASS"
    : truthy(process.env.COMPFUZOR_CONFIG_BYPASS)
      ? "COMPFUZOR_CONFIG_BYPASS"
      : undefined
  if (reason) return { status: "skipped", code: 0, reason }

  const strategy = resolve(options.strategy)
  if (strategy === "copy" || strategy === "link") {
    return { status: "completed", code: await publishOutputs({ ...options, strategy }) }
  }
  if (!options.inputStrategy) throw new Error("assemble install requires an input strategy")
  const inputStrategy = resolve(options.inputStrategy)
  const seeded = await syncInputs({ ...options, strategy: inputStrategy, seed: true })
  if (seeded !== 0) return { status: "completed", code: seeded }
  const code = await runAssembly({
    spec: options.spec,
    contextName: options.contextName,
    runner: options.runner,
    names: options.names,
  })
  return { status: "completed", code }
}
