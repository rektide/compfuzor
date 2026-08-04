---
# Watchman file-watcher as a managed **user** systemd service.
#
# WHY A USER SERVICE: watchman is inherently per-user (state dir keyed by
# username, per-user inotify watch limits). The previous system-unit form here
# was never the unit actually running — the auto-started ad-hoc daemon from
# /usr/local/src/watchman-git was. This makes `systemctl --user status watchman`
# the source of truth: known state/log/socket/pid, restartable, journalable.
#
# Binary comes from watchman.src.pb (getdeps build → /usr/local/bin/watchman).
#
# ROOT GUARD (ticket compfuzor-watchman-service):
# A bare `watchman watch-project ~/src` (or any huge tree) exhausts inotify
# watches → poison state → jj (which uses watchman as fsmonitor) hangs on every
# status/commit. The durable fix is a global root_files guard: with
# `enforce_root_files: true` + `root_files: [".git",".hg",".jj"]`, watchman
# walks UP from the requested path to the nearest dir containing a marker,
# refusing if none exists. So `watch-project ~/src/<repo>` resolves to <repo>
# (has .git); `watch-project ~/src` is refused outright.
#
# HOW THE CONFIG REACHES THE DAEMON (fully user-mode, no /etc writes):
# Watchman reads `$WATCHMAN_CONFIG_FILE` (WatchmanConfig.cpp:28, overrides the
# compile-time `/etc/watchman.json`). We emit the config at {{ETC}}/watchman.json
# (via ETC_FILES) and set the env var on the unit. No sudo.
#
# CLI→DAEMON ROUTING — install-cli-symlink.sh (auto-included in install-user.sh):
# The C++ `watchman` CLI **ignores `$WATCHMAN_SOCK`** — only python/node/rust
# clients honor it (Connect.cpp:24, sockname.cpp:25, UserDir.cpp:195). The CLI
# computes its socket from the compile-time `WATCHMAN_STATE_DIR` macro:
# `<STATE_DIR>/<username>-state/sock`. If that socket has no listener, the CLI
# auto-spawns a fresh ad-hoc daemon (main.cpp:955) that inherits the CLI's env
# (which, for non-interactive contexts, lacks `WATCHMAN_CONFIG_FILE` → no guard).
# Rather than rebuild (a getdeps dependency nightmare), install-cli-symlink.sh
# **symlinks the CLI's compile-time default `<user>-state` path to our managed
# {{VAR}} dir**. Then every bare `watchman` invocation connects through the
# symlink to our managed daemon, which has the guard loaded. Single daemon, no
# spawn, no env gymnastics. The SYSTEMD_ENV / ZIM_MODULES wiring below is
# belt-and-suspenders for python/node/rust clients (which DO honor $WATCHMAN_SOCK).
#
# install-user.sh flow (auto-composed by bin_composers):
#   1. install-systemd-user.sh  — link unit, daemon-reload, enable --now
#   2. install-user-zimfw.sh    — promote zim module into the zim host
#   3. install-cli-symlink.sh   — symlink CLI default <user>-state → {{VAR}},
#                                 chmod 0700 on {{VAR}} (watchman security check)
- hosts: all
  vars:
    TYPE: watchman
    USERMODE: True

    VAR_DIR: True
    VAR_FILES:
      - name: state
        content: "{}"

    # The compile-time WATCHMAN_STATE_DIR that watchman.src.pb's getdeps build
    # baked into the binary (see scratch/build/watchman/watchman/config.h).
    # The bare CLI computes its default socket as
    # <WATCHMAN_DEFAULT_STATE_DIR>/<username>-state/sock. install-cli-symlink.sh
    # symlinks that path to {{VAR}}. Override here if the binary is rebuilt
    # with a different -DWATCHMAN_STATE_DIR.
    WATCHMAN_DEFAULT_STATE_DIR: /usr/local/src/watchman-git/watchman/var/run/watchman

    SYSTEMD_ENV:
      WATCHMAN_SOCK: "{{VAR}}/sock"
      WATCHMAN_CONFIG_FILE: "{{ETC}}/watchman.json"

    SYSTEMD_SERVICES:
      ExecStart: "watchman --persistent --foreground --statefile={{VAR}}/state --pidfile={{VAR}}/pid --sockname={{VAR}}/sock --logfile={{VAR}}/log"
      Environment:
        - "WATCHMAN_CONFIG_FILE={{ETC}}/watchman.json"
      Restart: always
      RestartSec: "2s"

    ZIM_MODULES:
      - name: watchman-env
        phase: tools
        env:
          WATCHMAN_SOCK: "{{VAR}}/sock"
          WATCHMAN_CONFIG_FILE: "{{ETC}}/watchman.json"

    # Global root_files guard config. Emitted by ETC_FILES to {{ETC}}/watchman.json,
    # read by the daemon via $WATCHMAN_CONFIG_FILE at startup. Restart the service
    # to pick up changes (existing roots are NOT re-validated; only new
    # watch-project calls are gated).
    ROOT_GUARD:
      root_files: [".git", ".hg", ".jj"]
      enforce_root_files: true
      ignore_dirs:
        - node_modules
        - target
        - .build
        - build
        - dist
        - ".next"
        - ".cache"
        - ".turbo"
        - ".venv"
        - venv
        - __pycache__
        - ".tox"
        - ".mypy_cache"
        - ".pytest_cache"

    ETC_FILES:
      - name: watchman.json
        content: "{{ROOT_GUARD | to_nice_json}}\n"

    # Ungrouped install leaf (scope: user, no subsystem) → auto-included as a
    # direct child of install-user.sh by bin_composers. Runs after the systemd
    # unit is linked and the zim module is promoted.
    BINS:
      - name: install-cli-symlink.sh
        scope: user
        content: |
          # Symlink the bare `watchman` CLI's compile-time default <user>-state
          # path to our managed {{VAR}} dir. The C++ CLI ignores $WATCHMAN_SOCK
          # (only python/node/rust clients honor it) and computes its socket as
          # <WATCHMAN_DEFAULT_STATE_DIR>/<username>-state/sock. Without this
          # symlink it auto-spawns an ad-hoc daemon with no guard config.
          # Also enforce 0700 on {{VAR}} — watchman refuses group/other-writable
          # state dirs ("the permissions on <dir> allow others to write to it").
          _state_dir="{{WATCHMAN_DEFAULT_STATE_DIR}}"
          _user_state="$_state_dir/$(id -un)-state"
          mkdir -p "$_state_dir"
          chmod 0700 "{{VAR}}"
          rm -rf "$_user_state"
          ln -sfv "{{VAR}}" "$_user_state"
  tasks:
    - import_tasks: tasks/compfuzor.includes
