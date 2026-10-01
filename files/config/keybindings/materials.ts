/** Pure source/placement/incorporation planning shared with future native admission. */

import { isAbsolute, join } from "node:path";
import type { Target } from "./model.ts";
import { renderInclude } from "./render.ts";

export type NativeSource = {
  id: string;
  path: string;
  format: Target;
  order: number;
  placement: { strategy: "direct" } | { strategy: "copy" | "link"; path: string };
};
export type SelectedMaterial = {
  id: string;
  target: Target;
  sourcePath: string;
  effectivePath: string;
  strategy: "direct" | "copy" | "link";
  order: number;
  blockIdentity: string;
  include: string;
};

export function materialNames(
  id: string,
  target: Target,
): { definition: string; incorporation: string } {
  if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(id)) throw new Error(`invalid binding id ${id}`);
  return target === "niri"
    ? {
        definition: join("niri", `${id}.binding.kdl`),
        incorporation: join("niri", `${id}.include.kdl`),
      }
    : {
        definition: join("umbriel", `${id}.binding.toml`),
        incorporation: join("umbriel", `${id}.include.toml.part`),
      };
}

/** Explicit membership: no wildcard can accidentally admit include fragments. */
export function selectMaterials(
  target: Target,
  sources: readonly NativeSource[],
): SelectedMaterial[] {
  const seen = new Set<string>();
  return [...sources]
    .sort((a, b) => a.order - b.order || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
    .map((source) => {
      materialNames(source.id, target);
      if (seen.has(source.id)) throw new Error(`duplicate contribution ${source.id}`);
      seen.add(source.id);
      if (source.format !== target)
        throw new Error(`contribution ${source.id}: expected ${target} source format`);
      if (!Number.isFinite(source.order))
        throw new Error(`contribution ${source.id}: order must be finite`);
      const effectivePath =
        source.placement.strategy === "direct" ? source.path : source.placement.path;
      if (!isAbsolute(source.path) || !isAbsolute(effectivePath))
        throw new Error(
          `contribution ${source.id}: source and selected placement paths must be absolute`,
        );
      return {
        id: source.id,
        target,
        sourcePath: source.path,
        effectivePath,
        order: source.order,
        strategy: source.placement.strategy,
        blockIdentity: `keybinding/${target}/${source.id}`,
        include: renderInclude(target, effectivePath),
      };
    });
}

/** New root skeleton only, NOT an adoption editor for existing user TOML/KDL. */
export function renderRoot(
  target: Target,
  materials: readonly SelectedMaterial[],
  baseline: readonly string[],
  personal: readonly string[] = [],
): string {
  if (materials.some((material) => material.target !== target))
    throw new Error(`root ${target}: incorporation material belongs to another target`);
  const refs = [
    ...baseline.map((path) => renderInclude(target, path)),
    ...materials.map((material) => material.include),
    ...personal.map((path) => renderInclude(target, path)),
  ];
  return target === "niri"
    ? refs.join("")
    : `[include]\nfiles = [\n${refs.map((entry) => "  " + entry).join("")}]\n`;
}
