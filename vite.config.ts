import { defineConfig } from "vite-plus";

const config: ReturnType<typeof defineConfig> = defineConfig({
  pack: [
    {
      entry: { "compfuzor-runtime": "files/runtime/compfuzor-runtime.ts" },
      # runtime/ also vendors zimfw.zsh (and future local-first artifacts);
      # never clean it or the build would delete the vendored controller.
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
  ],
  lint: {
    options: {
      typeAware: true,
      typeCheck: true,
    },
  },
});

export default config;
