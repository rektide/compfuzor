---
- hosts: all
  vars:
    REPO: https://github.com/google/zx
    NODEJS: True
    # pnpm 12 gates dependency build scripts and fails the install outright
    # when any were skipped. esbuild's postinstall only links the binary
    # already shipped via @esbuild/linux-x64; lefthook's installs git hooks
    # into this compfuzor clone (harmless, kept upstream for CI parity).
    NODEJS_ALLOW_BUILDS:
      - esbuild
      - lefthook
    # zx's scripts/*.mjs import transitive deps (fast-glob) directly, which
    # only resolves under npm's hoisted node_modules — upstream CI builds
    # with `npm ci` + `npm run build` (package-lock.json is tracked).
    # pnpm's isolated layout breaks that, and a one-shot
    # `--public-hoist-pattern` is not persistent config: any later `pnpm
    # run` reconciles node_modules back to defaults and drops the hoist.
    # So suppress the default pnpm `build` probe and run upstream's npm
    # build verbatim (the subsystem's preceding `pnpm i --frozen-lockfile`
    # just primes the store; `npm ci` re-links the tree npm-style).
    NODEJS_BUILD_SCRIPTS: none
    NODEJS_BUILD_COMMANDS:
      - npm ci
      - npm run build
  tasks:
    - import_tasks: tasks/compfuzor.includes
