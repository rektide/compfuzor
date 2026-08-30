---
# Watchwoman -- radiosilence/watchwoman, a wire-compatible watchman
# replacement, built from our fork (rektide/watchwoman, `systemd` branch):
# socket activation (LISTEN_FDS adoption, never unlinks the socket file
# while activated), sd_notify readiness (Type=notify), graceful SIGTERM.
#
# The socket unit binds the CLI's zeroconf path
# (~/.local/state/watchman/<user>-state/sock — upstream's
# WATCHMAN_USE_XDG_STATE_HOME layout) via %h/%u specifiers, so client
# routing needs no env vars and no symlink farm. First-party clients ask
# `watchman get-sockname`, which we answer.
#
# SINGLE STACK, hard cutover: retire the C++ watchman playbook, then
# install.sh links all six workspace bins (including the `watchman`
# argv[0] alias) and install-user.sh links the units (socket enabled at
# sockets.target; the service activates on first connection — enabling
# the socket also implicitly enables the service, so the daemon runs
# from login) and applies the one compat LINKS record for hardcoding
# clients.
#
# No root guard (no enforce_root_files in watchwoman):
# init-watchmanconfig.sh seeds per-root ignore_dirs. No statefile/pidfile/
# logfile: zero on-disk state modulo trigger persistence under the socket
# dir; logs go to the journal.
#
# Do NOT run `watchwoman install-unit` alongside this deploy: it writes
# real unit files over compfuzor's managed symlinks (`watchwoman
# uninstall-unit` reverts, if that already happened).
- hosts: all
  vars:
    TYPE: watchwoman
    INSTANCE: git

    REPO: https://github.com/radiosilence/watchwoman
    GIT_REMOTES:
      rektide: https://github.com/rektide/watchwoman
    # jj-style rev@remote: the fork's `systemd` branch (socket activation,
    # sd-notify, graceful shutdown) — everything above leans on it. origin
    # stays upstream for diffing.
    GIT_VERSION: systemd@rektide

    RUST: True
    # All six bins: watchwoman + the `watchman` argv[0] alias + companions
    # (watchmanctl, watchman-wait, watchman-make, watchman-diag).
    RUST_ALL: True
    # MSRV is 1.88; pinned (like atuin) so mise doesn't float below it.
    TOOL_VERSIONS:
      rust: "1.97.0"

    SYSTEMD_SCOPE: user
    SYSTEMD_INSTALL: user
    # Service root FIRST: its installer only links the unit (link-only, no
    # enable), which must exist before the socket installer's `enable` —
    # systemd implicitly enables the service a socket activates, and fails
    # if that unit isn't linked yet.
    SYSTEMD_ROOTS: [watchwomanService, watchwomanSocket]

    # The one compat path: upstream watchman's default-prefix socket
    # location, symlinked to our zeroconf socket for clients that
    # hardcode it (everything first-party asks the binary via
    # get-sockname instead). links.ts owns it — apply, drift, removal,
    # and sudo escalation for the root-owned parent dir all included.
    WATCHWOMAN_COMPAT_ROOT: /usr/local/var/run/watchman

    LINKS:
      - src: "${HOME}/.local/state/watchman/{{ansible_user_id}}-state/sock"
        dest: "{{WATCHWOMAN_COMPAT_ROOT}}/{{ansible_user_id}}-state/sock"
        scope: user
        policy: replace

    watchwomanSocket:
      SYSTEMD_SOCKET: watchwoman
      SYSTEMD_UNITS:
        Description: "Watchwoman (watchman-compatible) file watching daemon socket"
        Documentation: https://github.com/radiosilence/watchwoman
      SYSTEMD_SOCKETS:
        comments: |
          Zeroconf contract with the CLI's sock::resolve: %h/%u expand at
          unit-load, per user, no per-user templating — the username is
          part of the path contract on BOTH sides (upstream watchman's
          <user>-state layout and watchwoman's sock::resolve agree on
          it). XDG_STATE_HOME must stay unset or default;
          status-watchwoman.sh checks via get-sockname. systemd creates
          the parent dirs (DirectoryMode); 0700 keeps per-user state
          private.
        ListenStream: "%h/.local/state/watchman/%u-state/sock"
        SocketMode: "0600"
        DirectoryMode: "0700"
      SYSTEMD_INSTALLS:
        WantedBy: sockets.target

    watchwomanService:
      SYSTEMD_SERVICE: watchwoman
      # Socket-activated: link-only. BOOT stays lazy (daemon on first
      # connection); activation restarts it up immediately instead.
      SYSTEMD_ENABLE: false
      SYSTEMD_UNITS:
        comments: |
          Socket-activated by watchwoman.socket: an idle service is
          normal (after boot, before any client connects). The daemon
          adopts systemd's LISTEN_FDS listener and never unlinks the
          socket file while activated — the socket unit owns it for its
          whole life, so the bind survives daemon restarts.
        Description: "Watchwoman file watching daemon (watchman-compatible)"
        Documentation: https://github.com/radiosilence/watchwoman
        Requires: watchwoman.socket
        After: watchwoman.socket
      SYSTEMD_SERVICES:
        comments: |
          --sockname is redundant with the activated listener but pins
          the daemon's own path notion (get-sockname answer, trigger
          persistence dir) to the socket unit's ListenStream even if the
          unit's environment ever grows a stray XDG_STATE_HOME.
        Type: notify
        ExecStart: "{{GLOBAL_BINS_DIR}}/watchwoman --sockname %h/.local/state/watchman/%u-state/sock --foreground-daemon"
        Restart: on-failure
        RestartSec: 1
        # One inotify watch per dir plus fds per root during crawl (same
        # arithmetic as the C++ deploy; notify-rs inotify backend).
        LimitNOFILE: 524288
        StandardOutput: journal
        StandardError: journal
        SyslogIdentifier: watchwoman

    # ignore_dirs seeded by init-watchmanconfig.sh into a root's
    # .watchmanconfig (watchwoman's only ignore mechanism). Same list the
    # C++ deploy shipped in its global guard config.
    IGNORE_DIRS:
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

    STATUSES:
      - status-watchwoman.sh

    BINS:
      # Tombstones: bespoke orchestration retired — the standard
      # install-user.sh (unit linkers + links.ts records) is the whole
      # activation story.
      - name: install-companions.sh
        state: absent
      - name: take-watchman-name.sh
        state: absent
      - name: activate-user.sh
        state: absent
      - name: status-watchwoman.sh
        # Drift reporter (also registered in STATUSES so status.sh runs it).
        basedir: false
      - name: init-watchmanconfig.sh
        # watchwoman's only ignore mechanism is the per-root
        # .watchmanconfig (no global config file); this seeds one with
        # the standard ignore_dirs. The file is also a watch-project root
        # marker — the escape hatch for deliberately watching a non-VCS
        # dir (the old `.watch` trick).
        basedir: false
        content: |
          set -e
          [ $# -ge 1 ] || { echo "usage: init-watchmanconfig.sh <dir> [--force]" >&2; exit 2; }
          _dir="$1"; shift
          _force=0
          [ "${1:-}" = "--force" ] && _force=1
          [ -d "$_dir" ] || { echo "init-watchmanconfig: no such dir: $_dir" >&2; exit 1; }
          _cfg="$_dir/.watchmanconfig"
          if [ -e "$_cfg" ] && [ "$_force" != 1 ]; then
            echo "init-watchmanconfig: $_cfg exists (use --force to overwrite); leaving it" >&2
            exit 0
          fi
          echo '{"ignore_dirs":{{IGNORE_DIRS|to_json}}}' >"$_cfg"
          echo "init-watchmanconfig: wrote $_cfg"

    README: |
      # Watchwoman

      A drop-in, wire-compatible replacement for Facebook watchman, built
      from rektide/watchwoman's `systemd` branch. install.sh links all six
      workspace bins — `watchwoman` (the argv[0] alias; this deploy owns
      the classic name), `watchmanctl`, `watchman-wait`, `watchman-make`,
      `watchman-diag`. install-user.sh links the units and applies the
      compat LINKS record. That's the whole install.

      ## Service

          watchwoman.socket   ListenStream=%h/.local/state/watchman/%u-state/sock
                              (upstream's XDG state-home layout — the exact
                              path the CLI resolves with no environment),
                              enabled at sockets.target
          watchwoman.service  Type=notify, activated by the socket;
                              Restart=on-failure if it dies

      Cutover from C++ watchman: retire the old playbook's artifacts
      (watchman-main units, /usr/local/bin/watchman link), run install.sh
      + install-user.sh, restart long-running clients so they rebind.

      ## Operations

          systemctl --user status watchwoman.socket watchwoman.service
          journalctl --user -t watchwoman -f
          watchman watch-list
          watchman status [--json]
          {{BINS_DIR}}/status-watchwoman.sh

      ## Per-root ignores (no global config)

      watchwoman reads ignore_dirs from each root's `.watchmanconfig`:

          {{BINS_DIR}}/init-watchmanconfig.sh <dir> [--force]

      The file doubles as a watch-project root marker, so dropping one in
      a non-VCS dir also makes it watchable (the old `.watch` hatch).

      ## Notes

      - Do not run `watchwoman install-unit`: it writes real unit files
        over compfuzor's managed symlinks. (`watchwoman uninstall-unit`
        reverts if that already happened.)
      - XDG_STATE_HOME must stay unset (or point at ~/.local/state) for
        the zeroconf contract between the socket unit and bare CLIs;
        status-watchwoman.sh checks it via get-sockname.
      - Compat LINKS record:
        {{WATCHWOMAN_COMPAT_ROOT}}/<user>-state/sock → the zeroconf
        socket, for clients that hardcode upstream's default-prefix
        path. links.ts owns it.
      - Daemon state is zero-on-disk except trigger persistence under
        ~/.local/state/watchman/<user>-state/roots/. Logs go to the
        journal (identifier `watchwoman`).
  tasks:
    - import_tasks: tasks/compfuzor.includes
