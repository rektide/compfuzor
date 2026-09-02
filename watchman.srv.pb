---
# Watchman file-watcher as a **user** systemd service, deployed **globally**.
#
# HYBRID DEPLOY (global artifacts, per-user service): compfuzor's fsh lookup
# makes this work without any per-user templating. Artifacts live once in
# system dirs (/srv, /etc/opt); every user who wants watchman activates it
# themselves by running {{BINS_DIR}}/install-user.sh (no sudo). Per-user
# paths in the unit are %h specifiers systemd expands at unit-load; shell
# scripts use ${HOME} literals expanded at runtime.
#
# OVERRIDABLE SYMLINK FARM: the daemon's config resolves through the USER's
# ~/.config/watchman-main/watchman.json, which defaults to a symlink to the
# global {{ETC}}/watchman.json. Delete the symlink, write your own file —
# you've overridden just that piece; everything else stays managed.
#
# Binary comes from watchman.src.pb (getdeps build → /usr/local/bin/watchman).
#
# ROOT GUARD: a bare `watchman watch-project ~/src` (or any huge tree)
# exhausts inotify watches → poison state → jj (fsmonitor) hangs. The global
# config arms `enforce_root_files` with markers [.git .hg .jj .watch]:
# watchman walks UP from the requested path to the nearest marker, refusing
# if none. `watch-project ~/src/<repo>` resolves to <repo>; bare ~,
# ~/archive, ~/src are refused (they hold no markers — the guard-inversion
# status check drifts if that ever changes, e.g. a dotfiles `git init ~`).
# Refusals are logged by the daemon (send_error_response lines with the
# client pid and requested path); status-watchman.sh surfaces an
# informational count and guard-refusals.sh aggregates them.
# `.watch` is the escape hatch for deliberately watching a non-VCS dir.
#
# CANONICAL SOCKET — both watchman-main and watchwoman use the upstream
# default path: ~/.local/state/watchman/<user>-state/sock. Only one service
# may own it at a time; mutual Conflicts declarations make starting one
# service stop the other instead of creating a second watcher namespace.
# The C++ CLI ignores $WATCHMAN_SOCK and computes its socket from the
# compile-time WATCHMAN_STATE_DIR macro, so install-cli-symlink.sh maps that
# compiled path to the same canonical socket directory.
#
# ORPHAN TAKEOVER — ExecStartPre takeover.sh: if the unit's daemon dies and
# a client's bare `watchman` auto-spawns a replacement (which takes the
# pidfile/socket through the symlink with no guard config and no fd
# headroom), the unit crash-loops on the pidfile flock. takeover.sh checks
# the flock pre-start: free → exit; held → shutdown-server the foreign
# daemon (state-preserving) and wait. Also trims an overgrown log (this
# build has no max_log rotation; --logfile=/dev/stdout aborts it).
#
# FD LIMIT: one inotify fd per watched dir plus several fds per root during
# crawl; hundreds of roots EMFILE the user-manager default 1024 → segv
# loop. LimitNOFILE matches the login-session hard limit.
#
# ENV SPLIT (two expansion worlds): EnvironmentFile contents are NOT
# expanded by systemd ($HOME stays literal) while shells expand ${HOME}
# when sourcing env.export. So env.export carries ${HOME} literals for
# shell clients, and the unit carries Environment= lines with %h for the
# daemon (Environment= wins over EnvironmentFile).
- hosts: all
  vars:
    TYPE: watchman

    # per-user paths for unit directives (%h, systemd expands at load)
    UNIT_VAR: "{{ lookup('fsh', 'var', user=True, name=True, home='%h') }}"
    UNIT_ETC_FILE: "{{ lookup('fsh', 'etc', user=True, name=True, home='%h') }}/watchman.json"
    UNIT_SOCK: "%h/.local/state/watchman/%u-state/sock"
    # per-user paths for shell artifacts (${HOME}, shell expands at runtime)
    SHELL_VAR: "{{ lookup('fsh', 'var', user=True, name=True, home='${HOME}') }}"
    SHELL_ETC_FILE: "{{ lookup('fsh', 'etc', user=True, name=True, home='${HOME}') }}/watchman.json"

    SYSTEMD_SCOPE: user
    SYSTEMD_INSTALL: user

    # ${HOME} literals for shell-side consumers (BINS scripts via envdefault,
    # interactive shells via the zim module). The daemon gets the same vars
    # as %h Environment= lines below, which override the EnvironmentFile.
    ENV:
      WATCHMAN_SOCK: "${HOME}/.local/state/watchman/$(id -un)-state/sock"
      WATCHMAN_CONFIG_FILE: "{{SHELL_ETC_FILE}}"

    SYSTEMD_UNITS:
      Conflicts: watchwoman.socket watchwoman.service
      Before: watchwoman.socket watchwoman.service
    SYSTEMD_SERVICES:
      ExecStart: "{{GLOBAL_BINS_DIR}}/watchman --persistent --foreground --statefile={{UNIT_VAR}}/state --pidfile={{UNIT_VAR}}/pid --sockname={{UNIT_SOCK}} --logfile={{UNIT_VAR}}/log"
      ExecStartPre: "{{BINS_DIR}}/takeover.sh"
      Environment:
        - "WATCHMAN_SOCK={{UNIT_SOCK}}"
        - "WATCHMAN_CONFIG_FILE={{UNIT_ETC_FILE}}"
      LimitNOFILE: 524288
      Restart: always
      RestartSec: "2s"

    # Interactive shells: ZIM_ENV promotes the two client-facing vars into
    # an env module (don't-stomp) -- python/node/rust clients honor
    # $WATCHMAN_SOCK, unlike the C++ CLI (handled by the CLI-routing symlink).
    ZIM_ENV:
      - WATCHMAN_SOCK
      - WATCHMAN_CONFIG_FILE

    STATUSES:
      - status-watchman.sh

    # Global, user-agnostic guard config. Read via the USER's
    # ~/.config/watchman-main/watchman.json symlink (override point).
    ETC_FILES:
      - name: watchman.json
        link: user
        json:
          # .watch is the manual escape hatch: `touch <dir>/.watch` makes a
          # non-VCS dir watchable. Everything else must carry a real VCS dir.
          # The daemon also always honors .watchmanconfig (prepended
          # internally, no need to list it).
          root_files: [".git", ".hg", ".jj", ".watch"]
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

    # The compile-time WATCHMAN_STATE_DIR that watchman.src.pb's getdeps
    # build baked into the binary. install-cli-symlink.sh maps its
    # <WATCHMAN_DEFAULT_STATE_DIR>/<username>-state directory to the
    # canonical XDG state directory used by watchwoman.socket.
    WATCHMAN_DEFAULT_STATE_DIR: /usr/local/src/watchman-git/watchman/var/run/watchman

    BINS:
      - name: status-watchman.sh
        # stats/health via the watchman CLI: managed-socket identity, unit
        # vs pidfile, CLI-routing symlink, root-guard enforcement, guard
        # inversion (~ marker-free), config symlink farm, linger, inotify
        # pressure, state/log sizes, guard-refusal count (informational).
        basedir: false
      - name: guard-refusals.sh
        # Dig into root_files guard refusals: parses the daemon log's
        # send_error_response lines into time/client-pid/comm/command/path
        # aggregations. The refused client sees only a JSON error (and the
        # CLI exits 0 on it), so offenders retry silently; this names them.
        # Paths are ${HOME} literals expanded at runtime.
        basedir: false
      - name: takeover.sh
        # ExecStartPre: if a foreign (CLI-auto-spawned, unguarded) daemon
        # holds the pidfile flock, shutdown-server it and wait for the lock;
        # free lock → instant exit. Trims >64MiB logs. Paths are ${HOME}
        # literals expanded at runtime.
        basedir: false
        content: |
          #!/bin/sh
          _vdir="${HOME}/.local/var/lib/watchman-main"
          _pidfile="$_vdir/pid"
          _logfile="$_vdir/log"
          _watchman="{{GLOBAL_BINS_DIR}}/watchman"
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
          "$_watchman" --no-spawn --no-local --sockname="${HOME}/.local/state/watchman/$(id -un)-state/sock" shutdown-server >/dev/null 2>&1 || true
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
          # path to the canonical socket directory. The daemon's durable state
          # remains in its own var dir; only CLI routing is shared.
          _state_dir="{{WATCHMAN_DEFAULT_STATE_DIR}}"
          _user_state="$_state_dir/$(id -un)-state"
          _canonical="${HOME}/.local/state/watchman/$(id -un)-state"
          mkdir -p "$_state_dir" "$_canonical"
          chmod 0700 "$_canonical"
          rm -rf "$_user_state"
          ln -sfnv "$_canonical" "$_user_state"
  tasks:
    - import_tasks: tasks/compfuzor.includes
