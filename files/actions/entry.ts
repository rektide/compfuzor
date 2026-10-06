/** Process boundary shared by the tiny generated real action files. */
import { runAction } from "./runtime.ts";

export function actionEntry(
  argv: string[],
  invokedPath: string | undefined,
  entryUrl: string,
): void {
  if (!invokedPath) throw new Error("action entry requires an invocation path");
  runAction(argv, invokedPath, entryUrl).then(
    (outcome) => {
      if (outcome.signal) process.kill(process.pid, outcome.signal);
      else process.exitCode = outcome.code;
    },
    (error: unknown) => {
      console.error(error instanceof Error ? error.stack : String(error));
      process.exitCode = 2;
    },
  );
}
