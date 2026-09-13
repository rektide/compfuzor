/** Complete ordinary CONFIG install over typed assembly and delivery operations. */

import { runAssembly } from "./assembly.ts"
import type { ConfigSpec } from "./context.ts"
import { syncInputs, type InputStrategy } from "./inputs.ts"
import { publishOutputs } from "./publication.ts"

export type ConfigInstallStrategy = "assemble" | InputStrategy

export type InstallContextOptions = {
  spec: ConfigSpec
  contextName: string
  runner: string
  names: string[]
  strategy: ConfigInstallStrategy
  inputStrategy?: InputStrategy
}

export async function installContext(options: InstallContextOptions): Promise<number> {
  if (options.strategy === "copy" || options.strategy === "link") {
    return publishOutputs({ ...options, strategy: options.strategy })
  }
  if (!options.inputStrategy) throw new Error("assemble install requires an input strategy")
  const seeded = await syncInputs({ ...options, strategy: options.inputStrategy, seed: true })
  if (seeded !== 0) return seeded
  return runAssembly({
    spec: options.spec,
    contextName: options.contextName,
    runner: options.runner,
    names: options.names,
  })
}
