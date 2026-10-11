/** Source-only pilot CLI. Emits inspection data; cannot install or run actions. */
import { parseArgs } from "node:util";
import { planFuze } from "./plan.ts";

const { values, positionals } = parseArgs({
  options: { deployment: { type: "string" }, help: { type: "boolean", short: "h" } },
  allowPositionals: true,
  strict: true,
});
if (values.help) {
  console.log(
    "Usage: node files/fuzings/inspect.ts --deployment DIR ACTION\nRead-only JSON plan; no installation or execution.",
  );
} else {
  if (!values.deployment || positionals.length !== 1)
    throw new Error("expected --deployment DIR and exactly one action (see --help)");
  console.log(JSON.stringify(await planFuze(values.deployment, positionals[0]), null, 2));
}
