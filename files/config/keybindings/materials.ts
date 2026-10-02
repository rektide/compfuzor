/**
 * Pure selection and naming of native material and its incorporation references.
 * Generated binding bodies and user-authored native files enter the same explicit
 * source interface. Selection does not scan directories, inspect existence,
 * resolve filesystem aliases, copy/link files or publish CONFIG state; the consumer
 * adapter owns those observed-state checks and stages delivery with the runner.
 * Material suffixes identify definitions/includes/inline pieces, not glob membership.
 * @see /doc/config/keybinding-consumers.md
 */

import { isAbsolute, join, normalize } from "node:path";
import type { Target } from "./model.ts";
import { renderInclude } from "./render.ts";

/** Invocation-bound source membership and placement policy, before any delivery. */
export type NativeSource = {
  /** Stable contributor ID, supplied explicitly; not derived from the filename. */
  id: string;
  /** Absolute concrete native donor path; generated and user-authored bodies use it alike. */
  path: string;
  /** Explicit native language/target; extension does not determine format. */
  format: Target;
  /** Finite precedence value; ties use ID ordering, not filesystem enumeration. */
  order: number;
  /** Include by default; inline needs captured body bytes and is initially Niri-only. */
  incorporation?: "include" | "inline";
  /** False excludes membership without deleting its physical files. */
  enabled?: boolean;
  /** Optional source-registration disabled-slot suffix, interpreted by the I/O adapter. */
  disabledSuffix?: string;
  /** Native receiver policy, separate from managed YAML registration copy/link. */
  placement:
    | {
        /** Read/include the donor itself; never create a receiver copy/link. */
        strategy: "direct";
      }
    | {
        /** Plan receiver copy/link; assemble/seed preserve edits, refresh replaces explicitly. */
        strategy: "copy" | "link";
        /** Absolute concrete receiver entry used by live includes and inline rebinding. */
        path: string;
      };
};
/** Selected metadata in deterministic order; not proof that files exist or were installed. */
export type SelectedMaterial = {
  /** Stable source/contribution identity retained across path and order changes. */
  id: string;
  /** Consumer target for format checks and managed block namespace. */
  target: Target;
  /** Normalized absolute donor path; may be unneeded when an edited copy is selected. */
  sourcePath: string;
  /** Normalized live path selected for include or captured inline body resolution. */
  effectivePath: string;
  /** Requested native placement policy; actual mutation depends on consumer mode. */
  strategy: "direct" | "copy" | "link";
  /** Finite source precedence used to order root contributions. */
  order: number;
  /** Contribution-based keybinding/target/ID name; never an absolute-path block identity. */
  blockIdentity: string;
  /** Representation selected for root insertion; inline requires a body-aware adapter. */
  incorporation: "include" | "inline";
  /** Reference alternative pointing at effectivePath; not used as the inline body. */
  include: string;
};

/**
 * Name collision-resistant, target-relative definition and include material.
 * A .binding suffix keeps IDs such as launch.include distinct from companions;
 * broad *.kdl scans would still admit companions and are explicitly forbidden.
 * Niri inline naming is chosen by the consumer after body capture.
 * @param id Stable binding/contributor ID, not a source filename.
 * @param target Native adapter selection.
 * @returns Relative definition and incorporation filenames, without creating them.
 * @throws For IDs outside the safe named-record grammar.
 */
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

/**
 * Validate and order explicit native membership and render effective include metadata.
 * Disabled sources are omitted; no existence or physical alias checks happen here.
 * Consumer I/O preflight adds physical-entry checks before writes.
 * @param target Matching target required of every enabled source.
 * @param sources Declared memberships with concrete absolute donor/receiver paths.
 * @returns Selected metadata sorted by order then ID; no copy/link or commit occurs.
 * @throws For invalid enabled flags/IDs/order/paths, duplicate IDs/normalized
 * placements, wrong formats or unsupported Umbriel body inline.
 */
export function selectMaterials(
  target: Target,
  sources: readonly NativeSource[],
): SelectedMaterial[] {
  const seen = new Set<string>();
  const placements = new Map<string, string>();
  if (sources.some((source) => source.enabled !== undefined && typeof source.enabled !== "boolean"))
    throw new Error("native source enabled must be boolean");
  return sources
    .filter((source) => source.enabled !== false)
    .sort((a, b) => a.order - b.order || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
    .map((source) => {
      materialNames(source.id, target);
      if (seen.has(source.id)) throw new Error(`duplicate contribution ${source.id}`);
      seen.add(source.id);
      if (source.format !== target)
        throw new Error(`contribution ${source.id}: expected ${target} source format`);
      if (!Number.isFinite(source.order))
        throw new Error(`contribution ${source.id}: order must be finite`);
      renderInclude(target, source.path);
      const effectivePath = normalize(
        source.placement.strategy === "direct" ? source.path : source.placement.path,
      );
      if (!isAbsolute(source.path) || !isAbsolute(effectivePath))
        throw new Error(
          `contribution ${source.id}: source and selected placement paths must be absolute`,
        );
      const prior = placements.get(effectivePath);
      if (prior)
        throw new Error(`contributions ${prior} and ${source.id} claim placement ${effectivePath}`);
      placements.set(effectivePath, source.id);
      if (source.incorporation === "inline" && target !== "niri")
        throw new Error("Umbriel body inline requires explicit table adaptation; use include");
      return {
        id: source.id,
        target,
        sourcePath: normalize(source.path),
        effectivePath,
        order: source.order,
        strategy: source.placement.strategy,
        blockIdentity: `keybinding/${target}/${source.id}`,
        incorporation: source.incorporation ?? "include",
        include: renderInclude(target, effectivePath),
      };
    });
}

/**
 * Build a new include-only root/envelope: baseline first, members, personal last.
 * Umbriel emits exactly one include table and files array, never concatenated
 * keybinds tables. This is not an adoption editor for existing user text and cannot
 * supply captured inline bodies; consumer block assembly handles that path.
 * @param target Target for the complete skeleton.
 * @param materials Explicitly ordered include-only selections of that target.
 * @param baseline Ordered leading references; this helper does not check existence.
 * @param personal Ordered late references, defaulting to none.
 * @returns Root text only; no filesystem, validation subprocess or publication.
 * @throws On target mismatch, inline material or invalid reference spelling.
 */
export function renderRoot(
  target: Target,
  materials: readonly SelectedMaterial[],
  baseline: readonly string[],
  personal: readonly string[] = [],
): string {
  if (materials.some((material) => material.target !== target))
    throw new Error(`root ${target}: incorporation material belongs to another target`);
  if (materials.some((material) => material.incorporation === "inline"))
    throw new Error(
      "renderRoot composes include references only; inline requires captured body block assembly",
    );
  const refs = [
    ...baseline.map((path) => renderInclude(target, path)),
    ...materials.map((material) => material.include),
    ...personal.map((path) => renderInclude(target, path)),
  ];
  return target === "niri"
    ? refs.join("")
    : `[include]\nfiles = [\n${refs.map((entry) => "  " + entry).join("")}]\n`;
}
