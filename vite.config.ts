import { defineConfig } from "vite-plus";

const config: ReturnType<typeof defineConfig> = defineConfig({
  pack: [
    {
      entry: { "compfuzor-runtime": "files/runtime/compfuzor-runtime.ts" },
      // runtime/ also vendors zimfw.zsh (and future local-first artifacts);
      // never clean it or the build would delete the vendored controller.
      outDir: "runtime",
      clean: false,
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
    },
    {
      // The archive toolkit's committed bundle mirrors the runtime/
      // precedent: a single ESM entry, no hashes, checked in so ansible
      // consumers work without a build step. clean: false keeps
      // archive/src and archive/README.md in the output directory.
      entry: { "repo-jj-archive": "archive/src/repo-jj-archive.ts" },
      outDir: "archive",
      clean: false,
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
    },
  ],
  lint: {
    options: {
      typeAware: true,
      typeCheck: true,
    },
  },
});

export default config;
