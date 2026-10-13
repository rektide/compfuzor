---
# bun-inspector-protocol -- Chrome DevTools Protocol (CDP) client in
# TypeScript, upstream package packages/bun-inspector-protocol inside the
# oven-sh/bun monorepo. Never published to npm (registry 404; version stays
# 0.0.2), and the original standalone repo was folded into the monorepo, so
# the source lives only at packages/bun-inspector-protocol there.
#
# Toolchain: BUN: True pins bun through mise only (TOOL_VERSIONS -> the
# deployment .tool-versions; build-mise.sh runs `mise install`) -- no other
# bun provisioning. BUN_BINS: False suppresses the stock build-bun.sh/
# install-bun.sh: those run `bun install`/`bun link` at the monorepo root,
# which installs bun's entire dev workspace. The package is self-contained
# (own package.json + bun.lock; single runtime dep `ws`), so both actions
# happen inside packages/bun-inspector-protocol instead: verified that
# `bun install` there installs only ws and never hoists to the root.
- hosts: all
  vars:
    REPO: https://github.com/oven-sh/bun
    # 410M shallow vs multi-GB full history; depth-1 archive precedent:
    # chromiumsync.src.pb (chromium/src).
    GIT_DEPTH: 1
    BUN: True
    BUN_BINS: False
    BINS:
      - name: build-bun.sh
        bypass: [BUILD, BUN]
        run: "{{ BUILD_RUN_BYPASS is not deftruthy and BINS_RUN_BYPASS is not deftruthy }}"
        basedir: repo
        content: |
          # Package-scoped install + build: upstream script is
          # `bun build --target=node --outfile=index.js --minify-syntax
          # ./index.ts --external=ws`. node_modules/ and index.js are both
          # git-ignored (root .gitignore / package .gitignore), so the
          # shared-archive workspace stays clean.
          cd packages/bun-inspector-protocol
          bun install
          bun run build
      - name: install-bun.sh
        bypass: [LINK, BUN]
        run: "{{ INSTALL_RUN_BYPASS is not deftruthy and BINS_RUN_BYPASS is not deftruthy }}"
        basedir: repo
        content: |
          # Global registration for consumers: `bun link` (no -g; bun >= 1.4
          # misreads `bun link -g` as registering a package literally named
          # "global"). Registers into ~/.bun/install/global pointing at this
          # deployment's package dir. Consumers opt in per-project with
          # `bun link bun-inspector-protocol` or a
          # "bun-inspector-protocol": "link:bun-inspector-protocol" dep.
          cd packages/bun-inspector-protocol
          bun link
    README: |
      # bun-inspector-protocol

      Upstream [packages/bun-inspector-protocol](https://github.com/oven-sh/bun/tree/main/packages/bun-inspector-protocol)
      from the oven-sh/bun monorepo: Chrome DevTools Protocol (CDP) client in
      TypeScript (the protocol implementation behind `bun --inspect`'s
      websocket frontend). Not published to npm; source exists only in the
      monorepo, carried here as a depth-1 archive clone with the deployment
      workspace at `{{REPO_DIR}}` (packages/bun-inspector-protocol inside).

      ## Toolchain

      Bun comes from mise only: `BUN: True` writes the deployment
      `.tool-versions` pin (major-only `bun 1`, resolved by mise), links it
      into the repo root, and `build-mise.sh` runs `mise install` before the
      build lane.

      ## Bins

      - `bin/build-bun.sh` -- inside packages/bun-inspector-protocol only:
        `bun install` (just `ws`; verified no hoist to the monorepo root) then
        `bun run build` (bundled `index.js`, node target, `ws` external).
      - `bin/install-bun.sh` -- `bun link` from the package dir: global
        registration under `~/.bun/install/global`. Consume per-project with
        `bun link bun-inspector-protocol`, or add
        `"bun-inspector-protocol": "link:bun-inspector-protocol"` to the
        consumer's dependencies.

      Rebuild after archive refreshes via `bin/build.sh`; both stock BUN
      bins are suppressed (`BUN_BINS: False`) because they are monorepo-root
      shaped.
  tasks:
    - import_tasks: tasks/compfuzor.includes
