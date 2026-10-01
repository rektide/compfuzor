/** Direct-source CLI, loaded only when command.ts is the physical main module. */
import { fileURLToPath } from "node:url";
import { main as runCommand } from "./runtime.ts";

export async function main(): Promise<void> {
  process.exitCode = await runCommand(process.argv.slice(2), {
    validatorCommand: [
      process.execPath,
      fileURLToPath(new URL("./command.ts", import.meta.url)),
      "validate",
    ],
  });
}
