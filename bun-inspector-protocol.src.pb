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
          # Standalone one-bin build: same invocation minus --external=ws,
          # so ws (the only runtime dep) is bundled in (~101KB). Upstream
          # externalizes ws because bun itself provides it; standalone
          # consumers do not. install-bun.sh ships this as pkg/index.js.
          bun build --target=node --outfile=index-standalone.js --minify-syntax ./index.ts
      - name: install-bun.sh
        bypass: [LINK, BUN]
        run: "{{ INSTALL_RUN_BYPASS is not deftruthy and BINS_RUN_BYPASS is not deftruthy }}"
        basedir: repo
        content: |
          # Copy-mode install (RUST_COPY pattern): materialize the package
          # as real files under DIR/pkg instead of linking into the
          # monorepo workspace, with the standalone bundle as main. After
          # this, pkg/ is self-contained (sources + lockfile + bundled
          # index.js; no node_modules needed) and the bun monorepo archive
          # can be deleted -- only a rebuild re-clones it.
          pkg="$DIR/pkg"
          src=packages/bun-inspector-protocol
          rm -rf -- "$pkg"
          mkdir -p -- "$pkg"
          for f in package.json bun.lock index.ts tsconfig.json README.md; do
            cp -a -- "$src/$f" "$pkg/"
          done
          cp -a -- "$src/src" "$pkg/src"
          cp -a -- LICENSE.md "$pkg/LICENSE.md"
          cp -a -- "$src/index-standalone.js" "$pkg/index.js"
          git rev-parse HEAD > "$pkg/UPSTREAM"
          printf ' https://github.com/oven-sh/bun (packages/bun-inspector-protocol)\n' >> "$pkg/UPSTREAM"
          # Global registration for consumers: `bun link` (no -g; bun >= 1.4
          # misreads `bun link -g` as registering a package literally named
          # "global"). Consumers opt in per-project with
          # `bun link bun-inspector-protocol` or a
          # "bun-inspector-protocol": "link:bun-inspector-protocol" dep.
          cd "$pkg"
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
        `bun install` (just `ws`; verified no hoist to the monorepo root),
        the upstream build (external-ws `index.js`, repo-local parity), plus
        the standalone one-bin build: same `bun build` minus `--external=ws`,
        bundling ws in (~101KB `index-standalone.js`).
      - `bin/install-bun.sh` -- copy-mode install (RUST_COPY pattern):
        materializes the package as real files under `{{DIR}}/pkg` (sources,
        lockfile, upstream LICENSE.md, UPSTREAM provenance) with the standalone
        bundle as `index.js` (package main), then `bun link` from there.
        `pkg/` is self-contained -- no node_modules needed -- so the bun
        monorepo archive and `repo/` workspace can be deleted afterwards;
        only a rebuild (`bin/build.sh`, playbook rerun) re-clones it.
        Consume per-project with `bun link bun-inspector-protocol`, or add
        `"bun-inspector-protocol": "link:bun-inspector-protocol"` to the
        consumer's dependencies.

      Both stock BUN bins are suppressed (`BUN_BINS: False`) because they
      are monorepo-root shaped.
  tasks:
    - import_tasks: tasks/compfuzor.includes
