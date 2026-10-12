---
# kata -- upstream kenn-io/kata: a Go daemon (./cmd/kata) with a browser UI
# that upstream builds as a Bun/vite workspace (web/) and embeds into the
# binary at compile time.
#
# Build model: the normal Go build stays primary. `build-go.sh` is the stock
# CLI-only compile (upstream ships an embedded-assets compilation stub so the
# tree always `go build`s); the browser UI is an explicit, separate
# `build-web.sh` that drives upstream make targets. Embedding happens at Go
# compile time, so `make build` relinks ./cmd/kata itself -- a standalone
# asset build is insufficient -- and restores the stub on exit, which is why
# the two builds are ordered, not chained (see README).
#
# Runtime model: a user-scope systemd service, dormant until
# bin/install-service-user.sh is run. No autostart happens at generation:
# the unit renders to etc/ and nothing enables/starts it (the generation
# thunk is inert without SYSTEMD_EXEC, and SYSTEMD_LINK: False guards the
# legacy generation-time link+enable path).
- hosts: all
  vars:
    REPO: https://github.com/kenn-io/kata
    GO: True
    GO_BIN: kata
    GO_TARGET: ./cmd/kata
    # Web toolchain provisioning (opencode.src.pb model): upstream web/ is a
    # Bun workspace (`bun install --frozen-lockfile`, vite via bun), so
    # provision the managed Bun tool. NODEJS adds the managed node/pnpm pair
    # plus the native-build packages (build-essential, python3) JS
    # toolchains may need. Both *_BINS: False suppress the generated
    # build/install bins: those are pnpm/`bun link` shaped, would fight the
    # upstream workspace, and are replaced by build-web.sh's make targets.
    BUN: True
    BUN_BINS: False
    NODEJS: True
    NODEJS_BINS: False
    PKGS:
      # upstream Makefile targets driven by build-web.sh
      - make
    BINS:
      - name: build-web.sh
        # Explicit browser build only: compose: False keeps it out of the
        # generated bin/build.sh (whose plain Go build must not be undone by
        # lane ordering), and without `run:` it never auto-runs.
        compose: False
        basedir: repo
        bypass: [BUILD, BUN]
        content: |
          # Browser UI build, via upstream make targets from the repo root:
          #   make web-install  -- `bun install --frozen-lockfile` in web/
          #   make build        -- web-embed: vite build of web/dist,
          #                        asset validation, embed into the Go
          #                        binary, then `go build -ldflags=... -o
          #                        kata ./cmd/kata` (version-stamped).
          # The binary relink is mandatory (embedding is compile-time), and
          # upstream's EXIT trap restores the embedded-assets compilation
          # stub afterwards, returning the tree to its stock CLI-only
          # compile state. After any later plain Go rebuild, rerun this to
          # get the browser UI back.
          make web-install
          make build
    SYSTEMD_SERVICE: True
    SYSTEMD_SCOPE: user
    SYSTEMD_INSTALL: user
    # Link + enable are the generated installer's job (run by the operator);
    # keep the playbook render inert -- no unit link or enable at generation.
    SYSTEMD_LINK: False
    SYSTEMD_UNITS:
      Description: kata personal daemon (user service)
    SYSTEMD_SERVICES:
      # Resident foreground daemon (cmd/kata daemon start --foreground stays
      # in the foreground and honors Kata's default home/listen config; idle
      # shutdown only engages for the auto-start marker, which systemd is
      # not). Absolute path into the checkout repo: build-go.sh and
      # build-web.sh both write ./kata there, so the unit needs no global
      # link to be startable. Upstream's unix restart exec-replaces the
      # daemon in place (syscall.Exec), keeping systemd's MainPID valid.
      # No KATA_* runtime settings, and no EnvironmentFile at all: the
      # unit renders before subsystem ENV synthesis, so build-time Go
      # variables stay confined to {{DIR}}/env(.export) for the build bins.
      ExecStart: "{{REPO_DIR}}/kata daemon start --foreground"
    README: |
      # kata

      Upstream [kenn-io/kata](https://github.com/kenn-io/kata): Go daemon at
      `./cmd/kata`, browser UI as a Bun/vite workspace under `web/`, embedded
      into the binary at compile time. Deployed checkout: {{REPO_DIR}}.

      ## Bins

      - `bin/build-go.sh` -- plain `go build -o kata ./cmd/kata`
        (GO_BIN/GO_TARGET) in the checkout. Produces the CLI-only binary:
        upstream ships an embedded-assets compilation stub, so the stock
        tree always compiles. Runs during playbook builds; disarm the build
        lane with `-e BUILD_BYPASS=True` (or `BINS_RUN_BYPASS=True`).
        `bin/build.sh` composes exactly this CLI build.
      - `bin/build-web.sh` -- optional browser build, explicit only (not in
        `bin/build.sh`, never auto-run; `BUILD_BYPASS`/`BUN_BYPASS` disarm):
        `make web-install` (`bun install --frozen-lockfile` in web/), then
        `make build` -- web-embed vite-builds web/dist, validates, embeds,
        and relinks `./cmd/kata` with version ldflags. The relink is why a
        standalone asset build is insufficient.
      - `bin/install-go.sh` -- symlink the checkout's `kata` into
        $GLOBAL_BINS_DIR (`kata` on PATH).
      - `bin/install-service-user.sh` -- the generated user-service
        installer: links `etc/kata-git.service` into
        `~/.config/systemd/user/`, daemon-reloads, and runs
        `systemctl --user enable --now kata-git.service`. Run it
        deliberately; playbook generation renders the unit and stops there.

      **Rebuild order**: upstream `make build` restores the embedded-assets
      compilation stub when it exits, so the checkout is back to CLI-only
      compile state afterwards. Any later plain Go rebuild --
      `bin/build-go.sh`, `bin/build.sh`, or a manual `go build` -- replaces
      the browser-enabled binary with a CLI-only one. Rerun
      `bin/build-web.sh` after normal Go rebuilds whenever the browser UI
      should stay available.

      ## Service

      `kata-git.service` (user scope, `WantedBy=default.target`) runs
      `{{REPO_DIR}}/kata daemon start --foreground`: the resident foreground
      daemon with Kata's default home and listen settings untouched. No
      KATA_* runtime env and no EnvironmentFile: the unit renders before
      subsystem ENV synthesis, so build-time Go variables (GO_BIN,
      GO_TARGET) stay confined to `{{DIR}}/env(.export)` for the build bins.
      Upstream's unix restart path exec-replaces the daemon in place
      (syscall.Exec), so systemd MainPID tracking survives `kata daemon
      restart`.

          systemctl --user status kata-git.service
          journalctl --user -u kata-git.service -f

      ## Toolchain

      Upstream web/ is a Bun workspace, so the playbook provisions the
      managed Bun tool (`BUN: True`) and the node/pnpm pair plus
      native-build packages (`NODEJS: True`) while suppressing their
      generated build/install bins (`BUN_BINS`/`NODEJS_BINS: False`): those
      are pnpm/`bun link` shaped and would fight the upstream workspace.
      Tool versions are pinned via mise (`.tool-versions`); the web build
      goes through upstream make targets in `bin/build-web.sh`
      (opencode.src.pb precedent).
  tasks:
    - import_tasks: tasks/compfuzor.includes
