import { describe, expect, test } from "vitest";
import { decodeContribution, decodeYaml } from "../../files/config/keybindings/decode.ts";
import { compose } from "../../files/config/keybindings/model.ts";
import {
  materialNames,
  renderRoot,
  selectMaterials,
} from "../../files/config/keybindings/materials.ts";
import { projectionRecipes } from "../../files/config/keybindings/recipes.ts";
import { renderDefinition, renderInclude } from "../../files/config/keybindings/render.ts";

const action = (extra = {}) => ({
  version: 1,
  kind: "action",
  id: "launcher",
  exec: ["vicinae", "toggle"],
  ...extra,
});
const binding = (extra = {}) => ({
  version: 1,
  kind: "keybinding",
  id: "launch",
  action: "launcher",
  keys: ["Mod+D"],
  umbriel: { keys: ["Mod+Space"] },
  ...extra,
});
const decode = (value: unknown, source = "fixture") => decodeContribution(value, source);

describe("named action/keybinding domain", () => {
  test("one YAML file per declaration, strict decoding", () => {
    expect(
      decodeYaml(
        "version: 1\nkind: action\nid: launcher\nexec: [vicinae, toggle]\n",
        "action/launcher.yaml",
      ),
    ).toEqual(decode(action(), "action/launcher.yaml"));
    expect(() => decodeYaml("version: 1\nversion: 2\n", "duplicate.yaml")).toThrow(
      /duplicate|unique/i,
    );
    expect(() => decodeYaml("a: 1\n---\na: 2\n", "two.yaml")).toThrow();
    expect(() =>
      decodeYaml("version: 1\nkind: action\nid: x\nexec: !custom [echo]\n", "tag.yaml"),
    ).toThrow("unsupported YAML syntax");
    expect(() =>
      decodeYaml(
        "version: 1\nkind: action\nid: x\nexec: &cmd [echo]\nniri: {exec: *cmd}\n",
        "alias.yaml",
      ),
    ).toThrow();
    expect(() => decode(action({ exec: [] }))).toThrow("must not be empty");
    expect(() => decode(action({ exec: "shell string" }))).toThrow("sequence");
    expect(() => decode(action({ mystery: true }))).toThrow("unknown fields");
    expect(() => decode(action({ exec: ["one"], script: { shell: "sh", body: "two" } }))).toThrow(
      "only one",
    );
    expect(() => decode(binding({ keys: ["Mod+D;bad"] }))).toThrow("chord syntax");
    expect(() => decode(action({ exec: undefined, native: "window-close" }))).toThrow(
      "target specifier",
    );
  });

  test("target differences, independent actions, complete argv replacement", () => {
    const contributions = [
      decode(action()),
      decode(binding()),
      decode(binding({ id: "alternate", keys: ["Alt+Grave"], umbriel: { keys: ["Alt+Grave"] } })),
      decode(action({ patch: true, exec: ["other", "--only"] }), "user/action.yaml"),
    ];
    const niri = compose(contributions, "niri");
    const umbriel = compose(contributions, "umbriel");
    expect(niri.bindings[0].keys).toEqual(["Mod+D"]);
    expect(umbriel.bindings[0].keys).toEqual(["Mod+Space"]);
    expect(niri.bindings[1].action.implementation).toEqual({
      kind: "exec",
      argv: ["other", "--only"],
    });
    expect(niri.actions[0].sources).toEqual(["fixture", "user/action.yaml"]);
  });

  test("user chord patch does not repeat action or get hidden by producer target defaults", () => {
    const layers = [
      decode(action()),
      decode(binding()),
      decode(
        { version: 1, kind: "keybinding", id: "launch", patch: true, keys: ["Alt+Space"] },
        "user/keybinding/launch.yaml",
      ),
    ];
    for (const target of ["niri", "umbriel"] as const) {
      expect(compose(layers, target).bindings[0].keys).toEqual(["Alt+Space"]);
      expect(compose(layers, target).bindings[0].action.id).toBe("launcher");
    }
  });

  test("deliberate additions, key replacement, scalar property override", () => {
    const layers = [
      decode(action()),
      decode(
        binding({
          options: { repeat: false },
          niri: { "add-keys": ["Alt+D"], options: { repeat: true, "cooldown-ms": 80 } },
        }),
      ),
    ];
    expect(compose(layers, "niri").bindings[0]).toMatchObject({
      keys: ["Mod+D", "Alt+D"],
      options: { repeat: true, "cooldown-ms": 80 },
    });
    layers.push(
      decode({
        version: 1,
        kind: "keybinding",
        id: "launch",
        patch: true,
        keys: ["Ctrl+L"],
        "add-keys": ["Alt+L", "Alt+L"],
      }),
    );
    expect(compose(layers, "niri").bindings[0].keys).toEqual(["Ctrl+L", "Alt+L"]);
  });

  test("invalid graphs fail, patches are explicit, disabled actions cannot be invoked", () => {
    expect(() => compose([decode(binding())], "niri")).toThrow("unresolved action launcher");
    expect(() => compose([decode(action()), decode(action())], "niri")).toThrow("duplicate action");
    expect(() => compose([decode(action({ patch: true }))], "niri")).toThrow("patch has no action");
    expect(() => compose([decode(action({ enabled: false })), decode(binding())], "niri")).toThrow(
      "unresolved action",
    );
    const collisions = [
      decode(action()),
      decode(binding({ keys: ["Mod+Shift+D"] })),
      decode(binding({ id: "collision", keys: ["Shift+Mod+D"] })),
    ];
    expect(() => compose(collisions, "niri")).toThrow("shared by launch and collision");
    expect(
      compose([decode(action()), decode(binding({ enabled: false }))], "niri").bindings,
    ).toEqual([]);
  });

  test("portable exec is argv, explicit scripts and target-native implementations remain distinct", () => {
    const rendered = compose(
      [decode(action({ exec: ["app", "a'b", "$(bad)", "", "line\nnext"] })), decode(binding())],
      "niri",
    );
    expect(renderDefinition(rendered.bindings[0], "niri")).toContain(
      'spawn "app" "a\'b" "$(bad)" "" "line\\nnext";',
    );
    const umbriel = compose(
      [decode(action({ exec: ["app", "a'b", "$(bad)", ""] })), decode(binding())],
      "umbriel",
    );
    expect(renderDefinition(umbriel.bindings[0], "umbriel")).toContain(
      JSON.stringify("spawn:'app' 'a'\"'\"'b' '$(bad)' ''"),
    );
    const scripted = decode(
      action({ exec: undefined, script: { shell: "/bin/bash", body: "printf '%s' \"$HOME\"" } }),
    );
    expect(
      renderDefinition(compose([scripted, decode(binding())], "niri").bindings[0], "niri"),
    ).toContain('spawn "/bin/bash" "-c"');
    const native = decode(
      action({
        exec: undefined,
        niri: { native: { name: "focus-workspace", args: [2] } },
        umbriel: { native: "workspace-switch:2" },
      }),
    );
    expect(
      renderDefinition(compose([native, decode(binding())], "niri").bindings[0], "niri"),
    ).toContain("focus-workspace 2;");
    expect(
      renderDefinition(compose([native, decode(binding())], "umbriel").bindings[0], "umbriel"),
    ).toContain('"workspace-switch:2"');
  });

  test("target-only actions do not need invented portable implementations", () => {
    const native = decode(action({ exec: undefined, niri: { native: { name: "close-window" } } }));
    expect(
      compose([native, decode(binding({ umbriel: { enabled: false } }))], "umbriel").bindings,
    ).toEqual([]);
    expect(() => compose([native, decode(binding())], "umbriel")).toThrow("unresolved action");
  });
});

describe("definition versus incorporation material", () => {
  test("per-binding recipes explicitly name both outputs without admitting companions as bodies", () => {
    const composition = compose([decode(action()), decode(binding())], "umbriel");
    const plan = projectionRecipes(
      composition,
      ["/etc/action/launcher.yaml", "/etc/keybinding/launch.yaml"],
      "/context",
    );
    expect(plan.members).toEqual([
      {
        id: "launch",
        definition: "/context/umbriel/launch.binding.toml",
        incorporation: "/context/umbriel/launch.include.toml.part",
      },
    ]);
    expect(plan.recipes["/context/umbriel/launch.binding.toml"].inputs).toHaveLength(2);
    expect(plan.recipes["/context/umbriel/launch.include.toml.part"].inputs).toEqual([
      { file: "/context/umbriel/launch.binding.toml" },
    ]);
    expect(materialNames("launch", "niri")).toEqual({
      definition: "niri/launch.binding.kdl",
      incorporation: "niri/launch.include.kdl",
    });
    const collisionCandidates = compose(
      [
        decode(action()),
        decode(binding()),
        decode(binding({ id: "launch.include", keys: ["Mod+X"] })),
        decode(binding({ id: "launch-include", keys: ["Mod+Y"] })),
      ],
      "niri",
    );
    const collisionPlan = projectionRecipes(collisionCandidates, ["/source.yaml"], "/out");
    expect(Object.keys(collisionPlan.recipes)).toHaveLength(6);
    expect(new Set(Object.values(collisionPlan.recipes).map((recipe) => recipe.name)).size).toBe(6);
  });

  test("native user files and generated bodies share explicit source selection and stable block identity", () => {
    const sources = [
      {
        id: "copied",
        path: "/producer/body.toml",
        format: "umbriel" as const,
        order: 20,
        placement: { strategy: "copy" as const, path: "/user/edited.toml" },
      },
      {
        id: "own",
        path: "/user/own.toml",
        format: "umbriel" as const,
        order: 10,
        placement: { strategy: "direct" as const },
      },
      {
        id: "linked",
        path: "/producer/link.toml",
        format: "umbriel" as const,
        order: 30,
        placement: { strategy: "link" as const, path: "/user/link.toml" },
      },
    ];
    const selected = selectMaterials("umbriel", sources);
    expect(selected.map((entry) => entry.id)).toEqual(["own", "copied", "linked"]);
    expect(selected[1].include).toBe('"/user/edited.toml",\n');
    const switched = selectMaterials("umbriel", [{ ...sources[0], path: "/different/body.toml" }]);
    expect(switched[0].blockIdentity).toBe(selected[1].blockIdentity);
    const root = renderRoot("umbriel", selected, ["/baseline.toml"], ["/user/personal.toml"]);
    expect(root.match(/\[include\]/g)).toHaveLength(1);
    expect(root).not.toContain("[keybinds]");
    expect(root.indexOf("/baseline")).toBeLessThan(root.indexOf("/user/own"));
    expect(root.indexOf("/user/personal")).toBeGreaterThan(root.indexOf("/user/link"));
    expect(root).not.toContain("/producer");
    expect(() => renderRoot("niri", selected, [])).toThrow("another target");
    expect(renderInclude("niri", "/user/own.kdl")).toBe('include "/user/own.kdl"\n');
  });

  test("placement identities/formats/paths are validated", () => {
    expect(() => materialNames("../escape", "niri")).toThrow("invalid binding id");
    expect(() =>
      selectMaterials("niri", [
        { id: "x", format: "umbriel", path: "/x", order: 0, placement: { strategy: "direct" } },
      ]),
    ).toThrow("format");
    expect(() =>
      selectMaterials("niri", [
        { id: "x", format: "niri", path: "relative", order: 0, placement: { strategy: "direct" } },
      ]),
    ).toThrow("absolute");
    expect(() => renderInclude("umbriel", "/bad\npath")).toThrow("include path");
  });
});
