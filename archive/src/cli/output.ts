/**
 * Stdout purity for machine consumers.
 *
 * Ansible parses `refresh --json` stdout as exactly one JSON line, so any
 * failure must leave stdout empty — including the help document Effect CLI
 * renders when parsing fails (upstream always prints it on `ShowHelp`, even
 * with `renderErrors: false`). Commands therefore log through the Effect
 * `Console` service, which buffers here: a successful run flushes the buffer
 * to real stdout; a failed run discards it before the failure is reported on
 * stderr.
 */
import * as Console from "effect/Console";

export type OutputBuffer = {
  /** Console service whose `log` output is captured until flush or discard. */
  readonly console: Console.Console;
  /** Write captured output to real stdout. Call exactly once, on success. */
  flush(): void;
  /** Drop captured output. Call exactly once, on failure. */
  discard(): void;
};

const write = (line: string): void => {
  process.stdout.write(line);
  process.stdout.write("\n");
};

export const createOutputBuffer = (): OutputBuffer => {
  const lines: Array<string> = [];
  const buffered: Console.Console = Object.assign(Object.create(console), {
    log: (...args: ReadonlyArray<unknown>): void => {
      lines.push(args.map(String).join(" "));
    },
    // Failures are reported through reportFailure, never through the service.
    error: (...args: ReadonlyArray<unknown>): void => {
      process.stderr.write(`${args.map(String).join(" ")}\n`);
    },
  });
  const flush = (): void => {
    for (const line of lines) write(line);
    lines.length = 0;
  };
  return {
    console: buffered,
    flush,
    discard: (): void => {
      lines.length = 0;
    },
  };
};
