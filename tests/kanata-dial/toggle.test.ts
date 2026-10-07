import { describe, expect, it } from "vitest";
import { toggle, type ToggleOptions } from "../../files/kanata-dial/toggle.ts";

const options: ToggleOptions = {
  mode: "on",
  material: "/fixture/producer",
  applyCommand: "/fixture/apply-config",
  receivers: [
    { target: "niri", profile: "/fixture/niri.json", context: "user" },
    { target: "umbriel", profile: "/fixture/umbriel.json", context: "user" },
  ],
  systemctl: ["mock-systemctl"],
};

function label(argv: string[]): string {
  if (argv[0] === "mock-systemctl") return argv.slice(1).join(" ");
  if (argv[0] === options.applyCommand) return "apply";
  return `${argv[2]} ${argv[argv.indexOf("--target") + 1]}`;
}

describe("enhancement-only toggle ordering over mocked service/CONFIG commands", () => {
  it("installs/enables every explicit receiver and applies config before relay start", async () => {
    const trace: string[] = [];
    let hook: string[] | undefined;
    await toggle(options, async (argv) => {
      trace.push(label(argv));
      if (argv[0] === options.applyCommand) hook = argv;
    });
    expect(trace).toEqual([
      "stop kanata-dial-relay.service",
      "start kanata-dial.service",
      "disable --now kanata-dial-relay.service",
      "start kanata-dial-reset.service",
      "install niri",
      "enable niri",
      "install umbriel",
      "enable umbriel",
      "apply",
      "start kanata-dial-relay.service",
    ]);
    expect(hook).toEqual([
      options.applyCommand,
      "on",
      "--niri-profile",
      "/fixture/niri.json",
      "--niri-context",
      "user",
      "--umbriel-profile",
      "/fixture/umbriel.json",
      "--umbriel-context",
      "user",
    ]);
  });
  it("OFF confirms reset before membership disable and leaves dial/anchor running", async () => {
    const trace: string[] = [];
    await toggle({ ...options, mode: "off" }, async (argv) => {
      trace.push(label(argv));
    });
    expect(trace).toEqual([
      "disable --now kanata-dial-relay.service",
      "start kanata-dial-reset.service",
      "disable niri",
      "disable umbriel",
      "apply",
    ]);
  });
  it("reset failure stops dial as fail-safe and retains all precision bindings", async () => {
    const trace: string[] = [];
    await expect(
      toggle({ ...options, mode: "off" }, async (argv) => {
        trace.push(label(argv));
        if (label(argv) === "start kanata-dial-reset.service") throw new Error("wrong fallback");
      }),
    ).rejects.toThrow("F bindings retained");
    expect(trace).toEqual([
      "disable --now kanata-dial-relay.service",
      "start kanata-dial-reset.service",
      "stop kanata-dial.service",
    ]);
  });
  it("partial receiver failure does not start relay and recovers to base", async () => {
    const trace: string[] = [];
    await expect(
      toggle(options, async (argv) => {
        trace.push(label(argv));
        if (label(argv) === "install umbriel") throw new Error("consumer rejected");
      }),
    ).rejects.toThrow("consumer rejected");
    expect(trace).not.toContain("start kanata-dial-relay.service");
    expect(trace.slice(-2)).toEqual([
      "disable --now kanata-dial-relay.service",
      "start kanata-dial-reset.service",
    ]);
    expect(trace).not.toContain("apply");
  });
  it("configuration-application failure leaves relay stopped", async () => {
    const trace: string[] = [];
    await expect(
      toggle(options, async (argv) => {
        trace.push(label(argv));
        if (label(argv) === "apply") throw new Error("apply rejected");
      }),
    ).rejects.toThrow("apply rejected");
    expect(trace).not.toContain("start kanata-dial-relay.service");
  });
  it("OFF consumer failure happens after safe reset and cannot re-start precision", async () => {
    const trace: string[] = [];
    await expect(
      toggle({ ...options, mode: "off" }, async (argv) => {
        trace.push(label(argv));
        if (label(argv) === "disable umbriel") throw new Error("consumer rejected");
      }),
    ).rejects.toThrow("consumer rejected");
    expect(trace.slice(0, 2)).toEqual([
      "disable --now kanata-dial-relay.service",
      "start kanata-dial-reset.service",
    ]);
    expect(trace).not.toContain("apply");
    expect(trace).not.toContain("start kanata-dial-relay.service");
  });
  it("failed relay start disables it and requires another reset", async () => {
    const trace: string[] = [];
    await expect(
      toggle(options, async (argv) => {
        trace.push(label(argv));
        if (label(argv) === "start kanata-dial-relay.service") throw new Error("start rejected");
      }),
    ).rejects.toThrow("start rejected");
    expect(trace.slice(-2)).toEqual([
      "disable --now kanata-dial-relay.service",
      "start kanata-dial-reset.service",
    ]);
  });
  it("rejects implicit receivers/application and duplicate receivers before any effect", async () => {
    const trace: string[][] = [];
    const run = async (argv: string[]): Promise<void> => {
      trace.push(argv);
    };
    await expect(toggle({ ...options, receivers: [] }, run)).rejects.toThrow("receiver");
    await expect(toggle({ ...options, applyCommand: "" }, run)).rejects.toThrow("absolute");
    await expect(
      toggle({ ...options, receivers: [options.receivers[0]!, options.receivers[0]!] }, run),
    ).rejects.toThrow("Duplicate");
    expect(trace).toEqual([]);
  });
});
