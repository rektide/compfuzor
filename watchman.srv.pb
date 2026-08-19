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
# (via ETC_FILES json:) and pass the path to the daemon via ENV: →
# EnvironmentFile (the compfuzor-native way to give a unit its own env vars).
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
# spawn, no env gymnastics.
#
# ORPHAN TAKEOVER — ExecStartPre takeover.sh: the symlink routes CLI traffic to
# our managed paths, but if the unit's daemon ever dies while a client runs a
# bare `watchman` (e.g. get-sockname at session start), the CLI auto-spawns a
# replacement daemon that takes the pidfile/socket/state through the symlink —
# with NO guard config and NO fd headroom. The unit then crash-loops on
# "Failed to lock pidfile: process N owns it" (observed: 1600+ restarts over
# ~36h, unguarded daemon serving jj/opencode the whole time, 2 GiB log).
# takeover.sh checks the pidfile flock pre-start: free → instant exit; held →
# shutdown-server the foreign daemon (preserves watched-root state) and wait.
#
# FD LIMIT + LOG — this daemon holds one inotify fd per watched dir and
# several fds per root during crawl; with hundreds of roots the user-manager
# default (1024) EMFILEs the initial crawl → poison/segv loop (observed: state
# file destroyed). LimitNOFILE matches the login-session hard limit. This
# build has no max_log rotation and --logfile=/dev/stderr aborts it, so the
# log is a plain file: takeover.sh trims it pre-start (>64MiB → keep 4MiB
# tail) and status-watchman.sh drifts if it passes 256MiB between restarts.
#
# GUARD INVERSION — the root guard refuses ~, ~/archive, ~/src only because
# those dirs contain no .git/.hg/.jj; a `git init ~` (dotfiles!) would invert
# it and resolve every watch to ~. status-watchman.sh checks ~ and ~/archive
# stay marker-free (watchman has no deny-list config; marker-freeness IS the
# denial). Requires user linger so the unit (and guard daemon) runs from boot,
# before any client could auto-spawn a foreign daemon.
#
# install-user.sh flow (auto-composed by bin_composers):
#   1. install-cli-symlink.sh   — symlink CLI default <user>-state → {{VAR}},
#                                 chmod 0700 on {{VAR}} (watchman security check)
#   2. install-systemd-user.sh  — link unit, daemon-reload, enable --now
#   3. install-user-zimfw.sh    — promote zim module into the zim host
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

    # env.export + EnvironmentFile (the compfuzor-native way). Sourced by BINS
    # scripts and loaded into the unit's own env.
    #   WATCHMAN_CONFIG_FILE → where the daemon finds the root guard config
    #   WATCHMAN_SOCK        → socket path for clients/scripts that source this
    ENV:
      WATCHMAN_SOCK: "{{VAR}}/sock"
      WATCHMAN_CONFIG_FILE: "{{ETC}}/watchman.json"

    SYSTEMD_SERVICES:
      # --logfile is explicit (not omitted): this build derives the default
      # log from the sockname dir anyway, has NO max_log rotation (Logging.cpp),
      # and --logfile=/dev/stderr aborts the daemon (folly crash) — journald
      # is not reachable. takeover.sh trims the log pre-start instead.
      ExecStart: "watchman --persistent --foreground --statefile={{VAR}}/state --pidfile={{VAR}}/pid --sockname={{VAR}}/sock --logfile={{VAR}}/log"
      ExecStartPre: "{{BINS_DIR}}/takeover.sh"
      # hundreds of watched roots × per-root fds + one inotify fd per watched
      # dir: the user-manager default 1024 EMFILEs the initial crawl → segv loop
      LimitNOFILE: 524288
      Restart: always
      RestartSec: "2s"

    # Interactive shells: ZIM_ENV promotes the two client-facing ENV vars
    # into an auto-generated env module (don't-stomp, COMPFUZOR_ENV_OVERWRITE
    # forces) -- python/node/rust clients honor $WATCHMAN_SOCK, unlike the
    # C++ CLI (handled by the install-cli-symlink.sh shim).
    ZIM_ENV:
      - WATCHMAN_SOCK
      - WATCHMAN_CONFIG_FILE

    # Register the reporter with the status subsystem → activates it (its
    # status.sh orchestrator is contributed) and bakes status-watchman.sh
    # into status.sh's ordered REPORTERS list.
    STATUSES:
      - status-watchman.sh

    ETC_FILES:
      # Global root_files guard. Read by the daemon via $WATCHMAN_CONFIG_FILE
      # at startup. Restart the service to pick up changes (existing roots are
      # NOT re-validated; only new watch-project calls are gated).
      - name: watchman.json
        json:
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

    # Ungrouped install leaf (scope: user, no subsystem) → auto-included as a
    # direct child of install-user.sh by bin_composers. Runs after the systemd
    # unit is linked and the zim module is promoted.
    BINS:
      - name: status-watchman.sh
        # stats/health via the watchman CLI: managed-socket identity, unit
        # vs pidfile, CLI-routing symlink, root-guard enforcement, guard
        # inversion (~ marker-free), linger, inotify pressure, state size,
        # journald log-health. STATUSES wires it into status.sh.
        basedir: false
      - name: takeover.sh
        # ExecStartPre: if a foreign (CLI-auto-spawned, unguarded) daemon
        # holds the pidfile flock, shutdown-server it and wait for the lock;
        # free lock → instant exit. Also trims an overgrown log (no max_log
        # in this build). See "ORPHAN TAKEOVER" in the header.
        basedir: false
        content: |
          #!/bin/sh
          # Pre-start orphan takeover + log trim for {{NAME}}. Fast path:
          # nothing holds the pidfile flock → exit 0 immediately. Slow path:
          # a foreign daemon (auto-spawned by a bare CLI, no guard config)
          # owns the lock → ask it to shut down cleanly (preserves
          # watched-root state and drops idle watches) and wait up to ~10s.
          # If it refuses, fail the start so systemd surfaces it instead of
          # crash-looping. Finally: this build has no max_log rotation, so
          # trim the log if it outgrew 64MiB (keep a 4MiB tail).
          _pidfile="{{VAR}}/pid"
          _logfile="{{VAR}}/log"
          if [ -f "$_logfile" ]; then
            _size=$(stat -c %s "$_logfile" 2>/dev/null || echo 0)
            if [ "$_size" -gt 67108864 ]; then
              echo "takeover: log is ${_size} bytes; trimming to 4MiB tail" >&2
              tail -c 4194304 "$_logfile" >"$_logfile.trim" 2>/dev/null && mv -f "$_logfile.trim" "$_logfile"
            fi
          fi
          [ -f "$_pidfile" ] || exit 0
          exec 9<>"$_pidfile" || exit 0
          flock -n 9 && exit 0
          _owner="$(tr -dc '0-9' <"$_pidfile" 2>/dev/null || true)"
          echo "takeover: pidfile lock held${_owner:+ by pid $_owner}; requesting shutdown-server" >&2
          watchman --no-spawn --no-local --sockname="{{VAR}}/sock" shutdown-server >/dev/null 2>&1 || true
          _i=0
          while [ "$_i" -lt 50 ]; do
            flock -n 9 && exit 0
            sleep 0.2
            _i=$((_i + 1))
          done
          echo "takeover: pidfile lock still held after 10s; failing start" >&2
          exit 1
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
