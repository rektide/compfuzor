import { defineConfig } from "vite-plus";

export default defineConfig({
  pack: [
    ["config/command", "files/config/command.ts"],
    ["config-remote/config-remote", "files/config-remote.ts"],
    ["links/links", "files/links/links.ts"],
    ["zim/install", "files/zim/install.ts"],
  ].map(([name, entry]) => ({
    entry: { [name.split("/").at(-1)!]: entry },
    outDir: `build/runtime/${name.slice(0, name.lastIndexOf("/"))}`,
    clean: true,
    format: "esm",
    platform: "node",
    target: "node20.19",
    fixedExtension: true,
    hash: false,
    dts: false,
    sourcemap: false,
    outputOptions: {
      codeSplitting: false,
    },
  })),
  lint: {
    options: {
      typeAware: true,
      typeCheck: true,
    },
  },
});
