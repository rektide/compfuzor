import { readFile } from "node:fs/promises";
import { parse } from "yaml";
import { describe, expect, it } from "vitest";
import { decodeContribution } from "../../files/config/keybindings/decode.ts";
import { compose } from "../../files/config/keybindings/model.ts";
import { renderDefinition } from "../../files/config/keybindings/render.ts";

describe("independent media precision contribution", () => {
  it("adds F23/F24 in both modifier forms and can be removed without changing legacy media", async () => {
    const media = parse(await readFile("media-keys.etc.pb", "utf8"))[0].vars;
    const dial = parse(await readFile("kanata-dial.etc.pb", "utf8"))[0].vars;
    const declarations = (vars: typeof media) =>
      [
        ...Object.entries(vars.KEYBINDING_ACTIONS).map(([id, body]) => ({
          version: 1,
          kind: "action",
          id,
          ...(body as Record<string, unknown>),
        })),
        ...Object.entries(vars.KEYBINDINGS).map(([id, body]) => ({
          version: 1,
          kind: "keybinding",
          id,
          ...(body as Record<string, unknown>),
        })),
      ].map((value) =>
        decodeContribution(
          JSON.parse(JSON.stringify(value).replaceAll("{{KANATA_DIAL_PRECISION_STEP}}", "0.005")),
          vars.TYPE,
        ),
      );
    const baseline = declarations(media);
    const precision = declarations(dial);
    for (const target of ["niri", "umbriel"] as const) {
      const off = compose(baseline, target);
      const on = compose([...baseline, ...precision], target);
      const fine = off.bindings.find((binding) => binding.id === "media-volume-up-fine")!;
      expect(fine.action.implementation).toEqual({
        kind: "exec",
        argv: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "0.01+", "-l", "1.0"],
      });
      expect(
        off.bindings.find((binding) => binding.id === "media-volume-up")!.action.implementation,
      ).toEqual({
        kind: "exec",
        argv: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "0.03+", "-l", "1.0"],
      });
      expect(on.bindings.filter((binding) => binding.id.startsWith("media-"))).toEqual(
        off.bindings,
      );
      const up = on.bindings.find((binding) => binding.id === "kanata-dial-volume-up-precision")!;
      expect(up.keys).toEqual(["F23", "Shift+F23"]);
      const down = on.bindings.find(
        (binding) => binding.id === "kanata-dial-volume-down-precision",
      )!;
      expect(down.keys).toEqual(["F24", "Shift+F24"]);
      expect(renderDefinition(up, target)).toContain("0.005+");
      expect(off.bindings.some((binding) => binding.keys.includes("F23"))).toBe(false);
    }
  });
});
