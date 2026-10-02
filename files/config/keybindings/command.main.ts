/**
 * Deferred direct-source CLI adapter, loaded by command.ts only for physical-main
 * execution. It supplies Node plus the source command's validate subcommand as
 * the closure hook, then delegates all argument/operation admission to runtime.ts.
 * Import itself performs no assembly. Calling main reads process argv, may trigger
 * runtime filesystem/subprocess operations and records the exit code; it does not
 * provide another transaction/publisher or an implicit installed runner.
 * @see /doc/config/keybinding-consumers.md
 */
import { fileURLToPath } from "node:url";
import { main as runCommand } from "./runtime.ts";

/**
 * Run the source CLI using process argv and its explicit source validation entry.
 * @returns Resolves after runtime dispatch and assigning process.exitCode.
 * @throws Propagates argument, file, registration/preparation or runtime failures;
 * nonzero returned operation codes are assigned rather than converted to success.
 * @remarks Outside an installed deployment, assembly commands require --runner.
 */
export async function main(): Promise<void> {
  process.exitCode = await runCommand(process.argv.slice(2), {
    validatorCommand: [
      process.execPath,
      fileURLToPath(new URL("./command.ts", import.meta.url)),
      "validate",
    ],
  });
}
