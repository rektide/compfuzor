/** CLI admission for internal processors, closure validation and explicit consumers. */
import { readFile } from "node:fs/promises";
import { parseArgs } from "node:util";
import { runProcessor } from "./processor.ts";
import { validateClosure } from "./closure.ts";
import { assembleConsumer, type ConsumerRequest } from "./consumer.ts";
import { withInputBatch, type InputRegistration } from "../registration.ts";

export async function main(
  argv: string[],
  defaults: { runner?: string; validatorCommand: string[] },
): Promise<number> {
  const [command, ...args] = argv;
  if (command === "validate") {
    const { values } = parseArgs({
      args,
      options: { plan: { type: "string" } },
      strict: true,
      allowPositionals: false,
    });
    if (!values.plan) throw new Error("validate requires --plan");
    await validateClosure(values.plan, process.env);
    return 0;
  }
  if (command !== "assemble" && command !== "register") {
    await runProcessor(argv, process.env);
    return 0;
  }
  const { values } = parseArgs({
    args,
    options: {
      request: { type: "string" },
      batch: { type: "string" },
      runner: { type: "string" },
      check: { type: "boolean" },
    },
    strict: true,
    allowPositionals: false,
  });
  if (!values.request) throw new Error("assemble requires explicit --request");
  const runner = values.runner ?? defaults.runner;
  if (!runner) throw new Error("assemble requires --runner outside an installed deployment");
  const request = JSON.parse(await readFile(values.request, "utf8")) as ConsumerRequest;
  const assemble = () =>
    assembleConsumer({
      request,
      runner,
      validatorCommand: defaults.validatorCommand,
      check: values.check,
    });
  if (command === "assemble" && values.batch) throw new Error("--batch requires register");
  if (command === "register" && !values.batch) throw new Error("register requires --batch");
  if (command === "register" && values.check)
    throw new Error("register mutates selected registrations; --check is assembly-only");
  let result;
  if (command === "register") {
    const records = JSON.parse(await readFile(values.batch!, "utf8")) as InputRegistration[];
    if (!Array.isArray(records)) throw new Error("registration batch must be an array");
    result = await withInputBatch(records, assemble, { success: (outcome) => outcome.code === 0 });
  } else result = await assemble();
  return result.code;
}
