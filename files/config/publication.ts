/** Whole-output publication for selected CONFIG recipes. */

import { bindContextConfigs, type ConfigSpec } from "./context.ts"
import { replaceWithCopy, replaceWithLink } from "../links/delivery.ts"

export type PublicationStrategy = "copy" | "link"

export type PublicationOptions = {
  spec: ConfigSpec
  contextName: string
  names: string[]
  strategy: PublicationStrategy
}

export async function publishOutputs(options: PublicationOptions): Promise<number> {
  const resolved = bindContextConfigs(options.spec, options.contextName, options.names)
  let failed = false
  for (const name of options.names) {
    const source = options.spec.configs[name].output
    const destination = resolved.configs[name].output
    try {
      if (options.strategy === "link") await replaceWithLink(source, destination)
      else await replaceWithCopy(source, destination)
      console.log(`${options.strategy}\t${name}\t${source}\t${destination}`)
    } catch (error) {
      failed = true
      console.error(`error: ${name}: ${error instanceof Error ? error.message : String(error)}`)
    }
  }
  return failed ? 2 : 0
}
