/** Direct-source CLI, loaded only when command.ts is the physical main module. */
import { runProcessor } from "./processor.ts";

export async function main(): Promise<void> {
  await runProcessor(process.argv.slice(2), process.env);
}
