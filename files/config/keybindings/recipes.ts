/** Expand captured binding membership into today's filename-keyed CONFIG recipes.
 * No dependent-candidate scheduler or multi-output processor is implied. */

import { isAbsolute, join } from "node:path";
import { materialNames } from "./materials.ts";
import type { Composition } from "./model.ts";

export type ProjectionRecipe = {
  name: string;
  processor: { command: string; args: string[] };
  inputs: { file: string }[];
};
export type ProjectionRecipes = {
  recipes: Record<string, ProjectionRecipe>;
  members: { id: string; definition: string; incorporation: string }[];
};

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
