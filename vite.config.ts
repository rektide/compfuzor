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
      // Source-linked Figments and published CLI libraries must travel with the
      // deployed artifact, not rely on receiver-side node_modules/checkouts.
      deps: { alwaysBundle: [/^figmen-ts(?:\/|$)/, /^@bomb\.sh\//, /^confbox(?:\/|$)/] },
      outputOptions: {
        codeSplitting: false,
      },
    },
    {
      // The archive toolkit's committed bundle mirrors the runtime/
      // precedent: a single ESM entry, no hashes, checked in so ansible
      // consumers work without a build step. clean: false keeps
      // archive/src and archive/README.md in the output directory.
      //
      // The artifact is ONE TypeScript file (rolldown's erased JS is valid
      // TS) executed by the installed system Node 26 (nodesource 26.x)
      // via native type stripping — no .mjs twin, no node_modules
      // transport, no Node 20/22 compatibility. outExtensions names the
      // real emitted file (it overrides fixedExtension); this is the
      // pack option, not a post-build rename of the artifact.
      entry: { "repo-jj-archive": "archive/src/repo-jj-archive.ts" },
      outDir: "archive",
      clean: false,
      format: "esm",
      platform: "node",
      target: "node26",
      outExtensions: () => ({ js: ".ts" }),
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
