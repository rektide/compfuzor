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
# Binary comes from watchman.src.pb (getdeps build →
# /usr/local/bin/watchman-facebook). Watchwoman owns the classic `watchman`
# client name, so installing either implementation cannot change this unit's
# executable.
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
# CANONICAL SOCKET — both watchman-facebook and watchwoman use Watchman's XDG
# default: ${XDG_STATE_HOME:-$HOME/.local/state}/watchman/<user>-state/sock.
# systemd's %S is that same XDG state root for a user manager. Only one service
# may own it at a time; Conflicts against watchman.socket makes starting either
# implementation stop the other instead of creating a second watcher namespace.
# The C++ CLI ignores $WATCHMAN_SOCK and computes its socket from the
# compile-time WATCHMAN_STATE_DIR macro. The LINKS alias farm maps that
# compiled path and both legacy socket paths to the canonical listener.
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
    UNIT_SOCK: "%S/watchman/%u-state/sock"
    # per-user paths for shell artifacts (${HOME}, shell expands at runtime)
    SHELL_VAR: "{{ lookup('fsh', 'var', user=True, name=True, home='${HOME}') }}"
    SHELL_ETC_FILE: "{{ lookup('fsh', 'etc', user=True, name=True, home='${HOME}') }}/watchman.json"

    # Socket aliases, unit names, and the canonical endpoint contract live in
    # vars/common.yaml; only the fallback's own binary path is local.
    WATCHMAN_BIN: "{{GLOBAL_BINS_DIR}}/watchman-facebook"

    LINKS:
      - src: "{{WATCHMAN_CANONICAL_SOCKET}}"
        dest: "{{WATCHMAN_MAIN_SOCKET}}"
        scope: user
        policy: replace
      - src: "{{WATCHMAN_CANONICAL_SOCKET}}"
        dest: "{{WATCHMAN_DEFAULT_PREFIX}}/{{ansible_user_id}}-state/sock"
        scope: user
        policy: replace
      - src: "{{WATCHMAN_CANONICAL_STATE}}"
        dest: "{{WATCHMAN_DEFAULT_STATE_DIR}}/{{ansible_user_id}}-state"
        scope: user
        policy: replace

    SYSTEMD_SCOPE: user
    SYSTEMD_INSTALL: user
    # The fallback daemon carries an implementation-specific unit name: the
    # classic watchman.service name belongs to the watchwoman daemon's alias,
    # and watchman.socket is the canonical endpoint the fallback competes for.
    # The watchman-main deployment name is Compfuzor's generic default
    # instance name and remains only in artifact/state paths.
    SYSTEMD_SERVICE: "{{WATCHMAN_FALLBACK_UNIT}}"
    # Link-only fallback: enabling it would start the C++ daemon at boot,
    # where Conflicts=watchman.socket would evict the active endpoint owner
    # on every login. Start it deliberately to hand over the canonical socket.
    SYSTEMD_ENABLE: false

    SYSTEMD_UNITS:
      Description: Facebook Watchman file-watching daemon
      Documentation: https://facebook.github.io/watchman/
      Conflicts: "{{WATCHMAN_SOCKET_UNIT}}.socket"

    # ${HOME} literals for shell-side consumers (BINS scripts via envdefault,
    # interactive shells via the zim module). The daemon gets the same vars
    # as %h Environment= lines below, which override the EnvironmentFile.
    ENV:
      WATCHMAN_SOCK: "${XDG_STATE_HOME:-${HOME}/.local/state}/watchman/$(id -un)-state/sock"
      WATCHMAN_CONFIG_FILE: "{{SHELL_ETC_FILE}}"

    SYSTEMD_SERVICES:
      ExecStart: "{{WATCHMAN_BIN}} --persistent --foreground --statefile={{UNIT_VAR}}/state --pidfile={{UNIT_VAR}}/pid --sockname={{UNIT_SOCK}} --logfile={{UNIT_VAR}}/log"
      ExecStartPre: "{{BINS_DIR}}/takeover.sh"
      Environment:
        - "WATCHMAN_SOCK={{UNIT_SOCK}}"
        - "WATCHMAN_CONFIG_FILE={{UNIT_ETC_FILE}}"
      LimitNOFILE: 524288
      Restart: always
      RestartSec: "2s"

    # Interactive shells: ZIM_ENV promotes the two client-facing vars into
    # an env module (don't-stomp) -- python/node/rust clients honor
    # $WATCHMAN_SOCK, unlike the C++ CLI (handled by the alias farm).
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

    BINS:
      - name: status-watchman.sh
        # stats/health via the watchman CLI: managed-socket identity, unit
        # vs pidfile, compiled-path alias, root-guard enforcement, guard
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
          _watchman="{{WATCHMAN_BIN}}"
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
          _state_home="${XDG_STATE_HOME:-${HOME}/.local/state}"
          "$_watchman" --no-spawn --no-local --sockname="$_state_home/watchman/$(id -un)-state/sock" shutdown-server >/dev/null 2>&1 || true
          _i=0
          while [ "$_i" -lt 50 ]; do
            flock -n 9 && exit 0
            sleep 0.2
            _i=$((_i + 1))
          done
          echo "takeover: pidfile lock still held after 10s; failing start" >&2
          exit 1
  tasks:
    - import_tasks: tasks/compfuzor.includes
