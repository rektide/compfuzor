/**
 * Existing CONFIG leaf-protocol adapter: capture ordered YAML for one definition,
 * or render one selected native path's include metadata, and write ONE candidate.
 * It reads the spec/TSV manifest and selected declaration files, but never installs,
 * registers sources, commits outputs or executes authored actions/scripts.
 * Include mode deliberately does not read the referenced live body's bytes: a body
 * may be another pending output and the runner is not a dependent-candidate DAG.
 * Full-root consumer admission belongs to the separate closure hook before commit.
 * @see /doc/config/keybindings.md
 */

import { readFile, writeFile } from "node:fs/promises";
import { parseArgs } from "node:util";
import { captureFile, fileText } from "../capture.ts";
import { decodeYaml } from "./decode.ts";
import { compose, type Target } from "./model.ts";
import { renderDefinition, renderInclude } from "./render.ts";

/** Runner-owned internal leaf binding; optional types permit admission diagnostics for missing values. */
export type ProcessorEnvironment = {
  /** Active recipe spec JSON path, including context-bound input/output paths. */
  CONFIG_SPEC?: string;
  /** Existing private transaction directory; presence prevents accidental direct leaf use. */
  CONFIG_TRANSACTION?: string;
  /** Sole private candidate output file; the processor writes no other publication target. */
  CONFIG_CANDIDATE?: string;
  /** Ordered TSV manifest: kind, identity, selected path, settings; not a byte snapshot. */
  CONFIG_INPUTS_FILE?: string;
};

function required(value: string | undefined, label: string): string {
  if (!value)
    throw new Error(`${label} is required; use CONFIG assembly, not a direct internal leaf`);
  return value;
}

/**
 * Render exactly one recipe candidate under the existing internal protocol.
 * Definition mode captures its selected YAML, composes the whole target graph and
 * renders the requested binding. Include mode accepts exactly one native path and
 * returns a reference (Umbriel array entry, not a standalone document). The runner
 * owns every later per-recipe/transaction validation, check/stdout and commit step.
 * @param argv Fixed --target/--material/optional --binding plus runner --config.
 * @param environment Explicit runner paths; no ambient source/target installation scan.
 * @returns Resolves after writing CONFIG_CANDIDATE only; no deployed output is accepted.
 * @throws On bad args/protocol/spec/manifest, missing or invalid YAML, unresolved or
 * disabled binding, composition/render errors or capture/write failure.
 */
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
