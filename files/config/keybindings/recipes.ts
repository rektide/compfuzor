/**
 * Pure expansion of explicit binding membership into filename-keyed CONFIG recipes.
 * Each definition and include piece is one independent single-output recipe; the
 * runner invokes its deployed processor and owns validation/publication. Include
 * inputs identify selected paths, not a promise that pending definition candidates
 * are readable as live files. This adds no scheduler, multi-output protocol or I/O.
 * The bounded consumer adapter instead prepares captured byte inputs before CONFIG
 * when complete placement/root closure must be validated coherently.
 * @see /doc/config/keybindings.md
 * @see /doc/config/keybinding-consumers.md
 */

import { isAbsolute, join } from "node:path";
import { materialNames } from "./materials.ts";
import type { Composition } from "./model.ts";

export type ProjectionRecipe = {
  /** Explicit CONFIG identifier, distinct for definition versus inclusion material. */
  name: string;
  /** Existing external processor declaration consumed by controller compilation. */
  processor: {
    /** Deployed executable path, absolute or bin-relative; no PATH discovery. */
    command: string;
    /** Fixed argv selecting target/material/binding; compiler quotes each separately. */
    args: string[];
  };
  /** Explicit ordered file inputs; no native suffix glob can admit companion pieces. */
  inputs: {
    /** Absolute selected input path, later bindable through ordinary CONFIG contexts. */
    file: string;
  }[];
};
/** Recipe declarations plus explicit material relationships, not produced artifacts. */
export type ProjectionRecipes = {
  /** Absolute output filenames mapped to their sole-candidate recipe declarations. */
  recipes: Record<string, ProjectionRecipe>;
  /** Closed output membership that callers use instead of inspecting a directory. */
  members: {
    /** Authoritative binding ID from the supplied composition. */
    id: string;
    /** Absolute definition output containing binds/keybinds native material. */
    definition: string;
    /** Absolute include-piece output; Umbriel's piece is not standalone TOML. */
    incorporation: string;
  }[];
};

/**
 * Expand every resolved binding into independent definition/include recipes.
 * Supplying a composition does not freeze source bytes for later processor calls;
 * those processors capture their own inputs unless a higher adapter snapshots them.
 * @param composition Pure target-specific semantic result defining exact membership.
 * @param yamlPaths Absolute ordered YAML inputs, including patches in precedence order.
 * @param outputRoot Absolute material directory chosen by the caller.
 * @param processor Already deployed external command, defaulting to the stable alias.
 * @returns Declarations and relationships; does not compile bins, render files or commit.
 * @throws For nonabsolute input/output paths or invalid material IDs.
 */
export function projectionRecipes(
  composition: Composition,
  yamlPaths: readonly string[],
  outputRoot: string,
  processor = "keybinding-processor.mjs",
): ProjectionRecipes {
  if (!isAbsolute(outputRoot) || yamlPaths.some((path) => !isAbsolute(path)))
    throw new Error("projection recipes require absolute captured input and output-root paths");
  const recipes: Record<string, ProjectionRecipe> = {};
  const members: ProjectionRecipes["members"] = [];
  for (const binding of composition.bindings) {
    const names = materialNames(binding.id, composition.target);
    const definition = join(outputRoot, names.definition);
    const incorporation = join(outputRoot, names.incorporation);
    const name = `keybinding-${composition.target}-${binding.id}`;
    recipes[definition] = {
      name: `${name}-definition`,
      processor: {
        command: processor,
        args: ["--target", composition.target, "--binding", binding.id, "--material", "definition"],
      },
      inputs: yamlPaths.map((file) => ({ file })),
    };
    recipes[incorporation] = {
      name: `${name}-include`,
      processor: {
        command: processor,
        args: ["--target", composition.target, "--material", "include"],
      },
      inputs: [{ file: definition }],
    };
    members.push({ id: binding.id, definition, incorporation });
  }
  return { recipes, members };
}
