import { describe, expect, it } from "vitest";
import { parseActionSpec, selectAction } from "../../files/actions/runtime.ts";

function spec(entryAudience = "user", defaultAudience: string | null = entryAudience) {
  return parseActionSpec({
    version: 1,
    actions: {
      install: {
        name: "install",
        action: "install",
        entry: `install-${entryAudience}.mjs`,
        ...(defaultAudience === null ? {} : { default: defaultAudience }),
        aliases: [
          ...(defaultAudience === null ? [] : ["install.mjs"]),
          `install-${entryAudience === "user" ? "system" : "user"}.mjs`,
        ],
        plans: { user: [], system: [] },
      },
    },
  });
}

describe("audience invocation identity", () => {
  it.each(["user", "system"])(
    "selects the real %s default and explicit alternate spelling",
    (audience) => {
      const compiled = spec(audience);
      const physical = `/deployment/bin/install-${audience}.mjs`;
      expect(selectAction(compiled, "/unrelated/install.mjs", physical).audience).toBe(audience);
      const alternate = audience === "user" ? "system" : "user";
      expect(selectAction(compiled, `/aliases/install-${alternate}.mjs`, physical).audience).toBe(
        alternate,
      );
      expect(selectAction(compiled, physical, physical).deploymentDir).toBe("/deployment");
    },
  );

  it("rejects undeclared names, stale real files, omitted actions and absent bare aliases", () => {
    const compiled = spec("system", null);
    expect(() =>
      selectAction(compiled, "/bin/install.mjs", "/deployment/bin/install-system.mjs"),
    ).toThrow("unavailable action alias");
    expect(() =>
      selectAction(compiled, "/bin/typo-system.mjs", "/deployment/bin/install-system.mjs"),
    ).toThrow("unavailable action alias");
    expect(() =>
      selectAction(spec("system"), "install-user.mjs", "/deployment/bin/install-user.mjs"),
    ).toThrow("stale action entry");
    expect(() =>
      selectAction(
        parseActionSpec({ version: 1, actions: {} }),
        "install.mjs",
        "/deployment/bin/install-user.mjs",
      ),
    ).toThrow("stale action entry");
  });

  it("rejects contradictory defaults, unsupported versions and escaping paths", () => {
    expect(() => spec("user", "system")).toThrow("default must match");
    expect(() => parseActionSpec({ version: 2, actions: {} })).toThrow("unsupported spec");
    const compiled = spec();
    const raw = structuredClone(compiled);
    raw.actions.install.plans.user = [{ kind: "exec", path: "bin/../outside" }];
    expect(() => parseActionSpec(raw)).toThrow("contained beneath bin");
  });
});
