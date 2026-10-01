/** Bounded consumer capture/planning over CONFIG's existing sole commit boundary. */
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, normalize } from "node:path";
import { tmpdir } from "node:os";
import { runAssemblyResult, type AssemblyResult } from "../assembly.ts";
import { captureFile, fileText, type CapturedFile, type FileGuard } from "../capture.ts";
import { areaOffsets, assembleBlocks, type BlockArea } from "../blocks.ts";
import type { ConfigSpec } from "../context.ts";
import { inspectDeliveryEntry, pathsSharePhysicalEntry } from "../../links/delivery.ts";
import { decodeYaml } from "./decode.ts";
import { compose, type Target } from "./model.ts";
import {
  materialNames,
  selectMaterials,
  type NativeSource,
  type SelectedMaterial,
} from "./materials.ts";
import { renderDefinition, renderInclude, shellQuote } from "./render.ts";
import { captureClosure, entryKey, plannedReader, type ClosurePlan } from "./closure.ts";
import { nativeIncludes, resolveNativeInclude, rewriteNativeIncludes } from "./native.ts";

export type YamlSelection = { path: string; enabled?: boolean; disabledSuffix?: string };
export type ConsumerRequest = {
  version: 1;
  target: Target;
  root: { path: string; templateFile?: string; area?: BlockArea };
  materialRoot: string;
  yamlSources?: YamlSelection[];
  nativeSources?: NativeSource[];
  bindings?: Record<
    string,
    { order?: number; placement?: NativeSource["placement"]; incorporation?: "include" | "inline" }
  >;
  baseline?: string[];
  personal?: string[];
  mode?: "assemble" | "seed" | "refresh";
  environment?: Record<string, string | undefined>;
};
export type ConsumerOptions = {
  request: ConsumerRequest;
  runner: string;
  validatorCommand: string[];
  nativeValidator?: string;
  workspaceRoot?: string;
  blockCommand?: string;
  check?: boolean;
  stdio?: "inherit" | "pipe" | "ignore";
};
export type ConsumerResult = AssemblyResult & { materials: SelectedMaterial[]; outputs: string[] };

function absolute(path: string): string {
  if (typeof path !== "string" || !isAbsolute(path) || /[\0\r\n\t]/.test(path))
    throw new Error(`consumer path must be an absolute concrete path: ${String(path)}`);
  return normalize(path);
}

export function consumerArea(target: Target): BlockArea {
  const comment = target === "niri" ? "//" : "#";
  return {
    begin: `${comment} compfuzor-keybindings-begin`,
    end: `${comment} compfuzor-keybindings-end`,
  };
}

export function consumerTemplate(
  target: Target,
  baseline: readonly string[],
  personal: readonly string[],
  area: BlockArea = consumerArea(target),
): string {
  const refs = (paths: readonly string[]) =>
    paths.map((path) => renderInclude(target, absolute(path))).join("");
  return target === "niri"
    ? refs(baseline) + `${area.begin}\n${area.end}\n` + refs(personal)
    : `[include]\nfiles = [\n${refs(baseline)}${area.begin}\n${area.end}\n${refs(personal)}]\n`;
}

function assertAreaContext(text: string, target: Target, area: BlockArea): void {
  const span = areaOffsets(text, area);
  const probe = "/compfuzor-insertion-area-probe";
  const candidate =
    text.slice(0, span.insert) + renderInclude(target, probe) + text.slice(span.insert);
  try {
    if (!nativeIncludes(candidate, target).some((ref) => ref.path === probe && !ref.optional))
      throw new Error("probe is not in the required include scope");
  } catch (error) {
    throw new Error("adopted area must be top-level Niri or inside Umbriel include.files array", {
      cause: error,
    });
  }
}

/** Stable YAML IDs are authoritative. Paths/filenames identify provenance only. */
export async function assembleConsumer(options: ConsumerOptions): Promise<ConsumerResult> {
  const request = options.request;
  if (request.version !== 1 || (request.target !== "niri" && request.target !== "umbriel"))
    throw new Error("unsupported consumer request version/target");
  if (request.mode !== undefined && !["assemble", "seed", "refresh"].includes(request.mode))
    throw new Error("mode must be assemble, seed or refresh");
  if (!options.validatorCommand.length)
    throw new Error("explicit deployed closure-validator command is required");
  const target = request.target;
  const root = absolute(request.root.path);
  const materialRoot = absolute(request.materialRoot);
  const mode = request.mode ?? "assemble";
  const environment = request.environment ?? { HOME: process.env.HOME };
  const files = new Map<string, CapturedFile>();
  const capture = async (raw: string): Promise<CapturedFile> => {
    const path = absolute(raw);
    let file = files.get(path);
    if (!file) {
      file = await captureFile(path);
      files.set(path, file);
    }
    return file;
  };
  const yaml: { path: string; text: string }[] = [];
  for (const selected of request.yamlSources ?? []) {
    if (selected.enabled === false) continue;
    const path = absolute(selected.path);
    const active = await capture(path);
    if (selected.disabledSuffix !== undefined) {
      if (!/^\.[A-Za-z0-9_.-]+$/.test(selected.disabledSuffix))
        throw new Error("invalid disabled suffix");
      const disabled = await capture(path + selected.disabledSuffix);
      if (disabled.guard.kind !== "missing" && active.guard.kind !== "missing")
        throw new Error(`both enabled and disabled YAML source entries exist: ${path}`);
      if (disabled.guard.kind !== "missing") continue;
    }
    if (!active.bytes) throw new Error(`missing selected YAML source ${path}`);
    yaml.push({ path, text: fileText(active)! });
  }
  const composition = compose(
    yaml.map((file) => decodeYaml(file.text, file.path)),
    target,
  );
  const generated = new Map<string, string>();
  const definitionOwners = new Map<string, string>();
  const sources: NativeSource[] = [];
  for (const source of request.nativeSources ?? []) {
    if (source.enabled === false) continue;
    if (source.disabledSuffix !== undefined) {
      if (!/^\.[A-Za-z0-9_.-]+$/.test(source.disabledSuffix))
        throw new Error("invalid native registration disabled suffix");
      const active = await capture(source.path);
      const disabled = await capture(source.path + source.disabledSuffix);
      if (active.guard.kind !== "missing" && disabled.guard.kind !== "missing")
        throw new Error(`both enabled and disabled native source entries exist: ${source.path}`);
      if (disabled.guard.kind !== "missing") continue;
    }
    sources.push(source);
  }
  for (const [index, binding] of composition.bindings.entries()) {
    const settings = request.bindings?.[binding.id];
    const path = join(materialRoot, materialNames(binding.id, target).definition);
    generated.set(path, renderDefinition(binding, target));
    definitionOwners.set(path, binding.id);
    sources.push({
      id: binding.id,
      path,
      format: target,
      order: settings?.order ?? index,
      placement: settings?.placement ?? { strategy: "direct" },
      incorporation: settings?.incorporation,
    });
  }
  // Settings are not membership. They can remain when a source is disabled;
  // only enabled captured bindings produce outputs/inclusion contributions.
  const materials = selectMaterials(target, sources);
  const definitionKeys = new Set(await Promise.all([...generated.keys()].map(entryKey)));
  const claims = new Map<string, string>();
  for (const material of materials) {
    const key = await entryKey(material.effectivePath);
    const prior = claims.get(key);
    if (prior)
      throw new Error(
        `contributions ${prior} and ${material.id} claim physical placement ${material.effectivePath}`,
      );
    claims.set(key, material.id);
    if (
      material.strategy !== "direct" &&
      (await pathsSharePhysicalEntry(material.sourcePath, material.effectivePath))
    )
      throw new Error(`placement aliases donor for ${material.id}`);
    if (material.strategy !== "direct") {
      let source = material.sourcePath;
      const seen = new Set<string>();
      while (!seen.has(await entryKey(source))) {
        const key = await entryKey(source);
        seen.add(key);
        if (key === (await entryKey(material.effectivePath)))
          throw new Error(`donor symlink chain reaches placement for ${material.id}`);
        // A selected regular definition replaces an old symlink at commit.
        if (definitionKeys.has(key)) break;
        const entry = await inspectDeliveryEntry(source);
        if (entry.kind !== "symlink") break;
        source = entry.targetPath;
      }
    }
    if (
      (await pathsSharePhysicalEntry(root, material.effectivePath)) ||
      (await pathsSharePhysicalEntry(root, material.sourcePath))
    )
      throw new Error(`root aliases source/placement for ${material.id}`);
  }
  const outputBodies = new Map(generated);
  const links = new Map<string, string>();
  const effectiveBodies = new Map<string, string>();
  const reader = await plannedReader(outputBodies, async (path, optional) => {
    const file = await capture(path);
    if (!file.bytes && !optional) throw new Error(`missing selected native source ${path}`);
    return fileText(file);
  });
  for (const material of materials) {
    if (material.strategy === "direct") {
      effectiveBodies.set(material.id, (await reader(material.effectivePath, false))!);
      continue;
    }
    const current = await capture(material.effectivePath);
    const deliver = mode === "refresh" || (mode === "seed" && current.guard.kind === "missing");
    if (deliver) {
      const body = (await reader(material.sourcePath, false))!;
      outputBodies.set(material.effectivePath, body);
      if (material.strategy === "link") links.set(material.effectivePath, material.sourcePath);
      effectiveBodies.set(material.id, body);
    } else {
      if (!current.bytes)
        throw new Error(
          `selected user placement is missing or dangling: ${material.effectivePath}; request seed or refresh explicitly`,
        );
      effectiveBodies.set(material.id, (await reader(material.effectivePath, false))!);
    }
  }
  const area = request.root.area ?? consumerArea(target);
  const existingRoot = await capture(root);
  let rootText = fileText(existingRoot);
  if (rootText === undefined) {
    if (existingRoot.guard.kind !== "missing") throw new Error(`root is dangling: ${root}`);
    rootText =
      request.root.templateFile === undefined
        ? consumerTemplate(target, request.baseline ?? [], request.personal ?? [], area)
        : fileText(await capture(request.root.templateFile));
  }
  if (rootText === undefined) throw new Error("missing root template");
  assertAreaContext(rootText, target, area);
  const blocks: { id: string; content: string }[] = [];
  for (const material of materials) {
    let content = material.include;
    if (material.incorporation === "inline") {
      const body = effectiveBodies.get(material.id)!;
      content = rewriteNativeIncludes(
        body,
        target,
        nativeIncludes(body, target).map((ref) =>
          resolveNativeInclude(ref.path, material.effectivePath, target, environment),
        ),
      );
    }
    const names = materialNames(material.id, target);
    const companion = join(
      materialRoot,
      material.incorporation === "inline"
        ? names.incorporation.replace(/\.include\.kdl$/, ".inline.kdl")
        : names.incorporation,
    );
    if (
      outputBodies.has(companion) ||
      claims.has(await entryKey(companion)) ||
      (await entryKey(root)) === (await entryKey(companion))
    )
      throw new Error(`incorporation output collision ${companion}`);
    outputBodies.set(companion, content);
    blocks.push({ id: material.id, content });
  }
  // All placement/output aliases are rejected before creating private work or
  // publishing anything. Existing local bodies are inputs, not refresh recipes.
  const outputKeys = new Set<string>();
  for (const path of [...outputBodies.keys(), root]) {
    const key = await entryKey(path);
    if (outputKeys.has(key)) throw new Error(`two outputs claim physical path ${path}`);
    outputKeys.add(key);
    const claimant = claims.get(key);
    if (definitionOwners.has(path) && claimant && claimant !== definitionOwners.get(path))
      throw new Error(`generated definition overwrites placement of ${claimant}`);
    await capture(path);
    for (const source of yaml)
      if ((await entryKey(source.path)) === key)
        throw new Error(`output aliases YAML input ${source.path}`);
    for (const source of request.nativeSources ?? [])
      if ((await entryKey(source.path)) === key)
        throw new Error(`output aliases native donor ${source.path}`);
  }
  const workspace = await mkdtemp(join(options.workspaceRoot ?? tmpdir(), "keybindings-consumer-"));
  try {
    rootText = await assembleBlocks(rootText, blocks, {
      area,
      namespace: `keybinding/${target}`,
      comment: target === "niri" ? "//" : "#",
      workspace,
      command: options.blockCommand,
    });
    outputBodies.set(root, rootText);
    const captured = await captureClosure(
      root,
      target,
      await plannedReader(outputBodies, async (path, optional) => {
        const file = await capture(path);
        if (!file.bytes && !optional) throw new Error(`missing selected native source ${path}`);
        return fileText(file);
      }),
      environment,
    );
    const capturedPaths: Record<string, string> = {};
    await mkdir(join(workspace, "inputs"));
    for (const [index, [path, text]] of [...captured].entries()) {
      const file = join(workspace, "inputs", `closure-${index}`);
      await writeFile(file, text, { mode: 0o600 });
      capturedPaths[path] = file;
    }
    const guards: FileGuard[] = [...files.values()].map((file) => file.guard);
    const plan: ClosurePlan = {
      version: 1,
      target,
      root,
      captured: capturedPaths,
      guards,
      environment,
      validator: options.nativeValidator,
      definitions: [...generated.keys()],
    };
    const planPath = join(workspace, "closure.json");
    await writeFile(planPath, JSON.stringify(plan), { mode: 0o600 });
    const configs: ConfigSpec["configs"] = {};
    const bindings: NonNullable<ConfigSpec["contexts"]>[string]["configs"] = {};
    const leaf = join(dirname(options.runner), "processors/concat");
    for (const [index, [output, text]] of [...outputBodies].entries()) {
      const name = `keybinding-${target}-${index}`;
      const input = join(workspace, "inputs", `output-${index}`);
      await writeFile(input, text, { mode: 0o600 });
      configs[name] = {
        output,
        leaf,
        processor: "concat",
        inputs: [{ file: input }],
        apply: true,
        ...(links.has(output) ? { link: links.get(output) } : {}),
      };
      bindings[name] = { output: { path: output }, inputs: [{ path: input }] };
    }
    const spec: ConfigSpec = {
      version: 2,
      defaultContext: "consumer",
      configs,
      contexts: {
        consumer: { scope: "user", canonical: true, root: { path: "/" }, configs: bindings },
      },
      transaction_validate: [...options.validatorCommand, "--plan", planPath]
        .map(shellQuote)
        .join(" "),
    };
    const result = await runAssemblyResult({
      spec,
      contextName: "consumer",
      runner: options.runner,
      names: Object.keys(configs),
      check: options.check,
      quiet: options.check,
      stdio: options.stdio ?? "inherit",
    });
    return { ...result, materials, outputs: [...outputBodies.keys()] };
  } finally {
    await rm(workspace, { recursive: true, force: true });
  }
}
