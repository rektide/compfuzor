/** Current CONFIG adapter: capture selected inputs and write ONE private candidate. */

import { readFile, writeFile } from "node:fs/promises";
import { parseArgs } from "node:util";
import { captureFile, fileText } from "../capture.ts";
import { decodeYaml } from "./decode.ts";
import { compose, type Target } from "./model.ts";
import { renderDefinition, renderInclude } from "./render.ts";

export type ProcessorEnvironment = {
  CONFIG_SPEC?: string;
  CONFIG_TRANSACTION?: string;
  CONFIG_CANDIDATE?: string;
  CONFIG_INPUTS_FILE?: string;
};

function required(value: string | undefined, label: string): string {
  if (!value)
    throw new Error(`${label} is required; use CONFIG assembly, not a direct internal leaf`);
  return value;
}

export async function runProcessor(
  argv: string[],
  environment: ProcessorEnvironment,
): Promise<void> {
  const { values } = parseArgs({
    args: argv,
    strict: true,
    allowPositionals: false,
    options: {
      config: { type: "string" },
      target: { type: "string" },
      binding: { type: "string" },
      material: { type: "string" },
    },
  });
  const name = required(values.config, "--config");
  if (values.target !== "niri" && values.target !== "umbriel")
    throw new Error("--target must be niri or umbriel");
  const target: Target = values.target;
  if (values.material !== "definition" && values.material !== "include")
    throw new Error("--material must be definition or include");
  required(environment.CONFIG_TRANSACTION, "CONFIG_TRANSACTION");
  const candidate = required(environment.CONFIG_CANDIDATE, "CONFIG_CANDIDATE");
  const [specText, manifest] = await Promise.all([
    readFile(required(environment.CONFIG_SPEC, "CONFIG_SPEC"), "utf8"),
    readFile(required(environment.CONFIG_INPUTS_FILE, "CONFIG_INPUTS_FILE"), "utf8"),
  ]);
  const spec = JSON.parse(specText) as { configs?: Record<string, unknown> };
  if (!spec.configs || !Object.hasOwn(spec.configs, name))
    throw new Error(`unknown config ${name}`);
  const rows = manifest
    .split("\n")
    .filter(Boolean)
    .map((row) => {
      const columns = row.split("\t");
      if (columns.length !== 4 || !columns[1] || !columns[2])
        throw new Error("invalid CONFIG input manifest row");
      return { identity: columns[1], path: columns[2] };
    });
  let text: string;
  if (values.material === "include") {
    if (values.binding !== undefined) throw new Error("include material does not accept --binding");
    if (rows.length !== 1)
      throw new Error("include material requires exactly one explicit native file input");
    // Bind the include reference to the SAME selected input path as the body.
    // Do not read live contents here or pretend the runner has a candidate DAG.
    text = renderInclude(target, rows[0].path);
  } else {
    const binding = required(values.binding, "--binding");
    const captured = await Promise.all(
      rows.map(async (row) => {
        const text = fileText(await captureFile(row.path));
        if (text === undefined) throw new Error(`missing selected YAML input ${row.path}`);
        return decodeYaml(text, `${row.identity} (${row.path})`);
      }),
    );
    const composition = compose(captured, target);
    const resolved = composition.bindings.find((entry) => entry.id === binding);
    if (!resolved) throw new Error(`unknown or disabled keybinding ${binding}`);
    text = renderDefinition(resolved, target);
  }
  await writeFile(candidate, text);
}
