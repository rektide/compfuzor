import { expect, test } from "vitest";
import {
  nativeIncludes,
  resolveNativeInclude,
  rewriteNativeIncludes,
} from "../../files/config/keybindings/native.ts";
import { fileText } from "../../files/config/capture.ts";

test("Niri strings, raw strings and comments preserve include offsets; malformed terminators are rejected", () => {
  const text =
    '/* { include "ignored" } */\nbinds { Mod+D repeat=false { spawn "braces } { and \\\"quote" r##"} literal"##; }; }\n// include "ignored"\ninclude r#"relative.kdl"# optional=true\n';
  expect(nativeIncludes(text, "niri")).toEqual([{ path: "relative.kdl", optional: true }]);
  const rewritten = rewriteNativeIncludes(text, "niri", ["/candidate/relative.kdl"]);
  expect(rewritten).toBe(text.replace('r#"relative.kdl"#', '"/candidate/relative.kdl"'));
  expect(() => nativeIncludes('binds { Mod+D { spawn "echo"; } }\n', "niri")).toThrow();
  const unicode = '// 💫\ninclude "ä file.kdl"\n';
  expect(rewriteNativeIncludes(unicode, "niri", ["/candidate/file.kdl"])).toBe(
    '// 💫\ninclude "/candidate/file.kdl"\n',
  );
});

test("captured native text fails on invalid UTF-8 instead of validating replacement bytes", () => {
  expect(() =>
    fileText({ bytes: Buffer.from([0xff]), guard: { path: "/native", parent: "/", kind: "file" } }),
  ).toThrow("not valid UTF-8");
});

test("Umbriel required/optional arrays are separately represented, and path expansion is explicit", () => {
  const text = '[include]\nfiles = ["relative.toml"]\noptional = {files = ["~/optional.toml"]}\n';
  expect(nativeIncludes(text, "umbriel")).toEqual([
    { path: "relative.toml", optional: false },
    { path: "~/optional.toml", optional: true },
  ]);
  expect(
    nativeIncludes(
      rewriteNativeIncludes(text, "umbriel", ["/candidate/one", "/candidate/two"]),
      "umbriel",
    ).map((entry) => entry.path),
  ).toEqual(["/candidate/one", "/candidate/two"]);
  expect(
    resolveNativeInclude("${CUSTOM}/body.toml", "/owner/root.toml", "umbriel", {
      CUSTOM: "/explicit",
    }),
  ).toBe("/explicit/body.toml");
  expect(() =>
    resolveNativeInclude("${CUSTOM}/body.toml", "/owner/root.toml", "umbriel", {}),
  ).toThrow("explicit environment");
});
