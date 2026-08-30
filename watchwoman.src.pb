---
# Watchwoman -- radiosilence/watchwoman, a wire-compatible watchman
# replacement, built from our fork (rektide/watchwoman, `systemd` branch):
#
#   socket-activation  daemon/activation.rs adopts systemd's LISTEN_FDS
#                      listener and never unlinks the socket file while
#                      activated — the socket unit owns it for its whole
#                      life
#   sd-notify          daemon reports READY/STOPPING → Type=notify;
#                      SIGTERM/SIGINT drain through the same graceful path
#                      as shutdown-server
#   zeroconf socket    the CLI resolves --sockname / $WATCHMAN_SOCK, then
#                      $XDG_STATE_HOME (unset on this host) →
#                      ~/.local/state/watchman/<user>-state/sock — the SAME
#                      path the socket unit binds via %h/%u specifiers, so
#                      client routing needs NO env vars, NO zim env module,
#                      NO CLI-routing symlink. The whole
#                      install-cli-symlink/takeover apparatus of
#                      watchman.srv.pb is structurally gone: the socket
#                      unit owns the bind from boot (linger), and a bare CLI
#                      only ever spawns a rival past a STOPPED or DEAFENED
#                      socket unit — which status-watchwoman.sh reports and
#                      activate-user.sh's restart heals.
#
# SINGLE STACK: this deploy assumes the C++ watchman playbook is retired
# (or about to be). RUST_ALL links all six workspace bins, including the
# `watchman` argv[0] alias — installing this IS the cutover; remove the
# old watchman.src.pb/srv.pb artifacts when you run install.sh.
#
# HYBRID DEPLOY (global build + artifacts, per-user units): ansible clones
# the fork under /usr/local/src, the rust subsystem builds it, units render
# as ETC_FILES; each user activates with {{BINS_DIR}}/activate-user.sh:
# links both units, enables ONLY the socket (sockets.target; the service
# stays link-only so BOOT stays lazy — daemon on first connection), lays
# the compat socket symlink, then restarts socket+service so the daemon
# is up and verified right away. The restart is cheap (idle: ~50ms) and
# heals every weird state (deaf socket from a unit-file unlink during
# daemon-reload, stale fd, orphan daemon) in one stroke.
#
# DELTAS vs the C++ watchman playbook, surfaced by status-watchwoman.sh:
#   - NO root guard — watchwoman has no enforce_root_files and no global
#     config; watch-project falls back to the path itself when no marker
#     is found, so `watch-project ~` is a real hazard the old guard used
#     to refuse. init-watchmanconfig.sh ports the ignore_dirs story to
#     watchwoman's per-root .watchmanconfig model (which doubles as a
#     root marker — the old `.watch` escape hatch); the status script
#     lists marker-less roots informationally.
#   - GC instead of healthcheck timers — the daemon reaps dead roots
#     (2 missed 60s ticks) and stale ones (idle 1h default, no subs/
#     triggers), so abandoned watches don't accumulate.
#   - no statefile/pidfile/logfile — zero on-disk state modulo trigger
#     persistence under the socket dir; tracing goes to the journal.
#
# Do NOT run `watchwoman install-unit` alongside this deploy: it writes
# REAL unit files over compfuzor's managed symlinks (`watchwoman
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
    # location, symlinked to our zeroconf socket by activate-user.sh for
    # clients that hardcode it (everything first-party asks the binary
    # via get-sockname instead).
    WATCHWOMAN_COMPAT_ROOT: /usr/local/var/run/watchman

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
      # Tombstones: bins retired with the dual-support design.
      - name: install-companions.sh
        state: absent
      - name: take-watchman-name.sh
        state: absent
      - name: status-watchwoman.sh
        # Drift reporter (also registered in STATUSES so status.sh runs it).
        basedir: false
      - name: activate-user.sh
        # Per-user activation WITHOUT install-user.sh's rust leaf: that
        # leaf cargo-installs every workspace bin into ~/.cargo/bin —
        # which sits EARLIER in PATH than /usr/local/bin and would leave a
        # stale shadow copy of `watchman` there after every rebuild. This
        # deploy's binary comes from the global install; only the units
        # and per-user symlinks are per-user.
        scope: user
        basedir: false
        content: |
          set -e
          cd "$(dirname "$0")"
          ./install-systemd-user.sh
          ./install-links-user.sh
          # `enable` on a socket unit implicitly enables the service it
          # activates (default.target.wants) — that would make the daemon
          # EAGER at boot. Remove just that symlink: the service stays
          # linked and the SOCKET activates it on first connection.
          # (NOT `systemctl disable`: on linked units it also unlinks the
          # unit file itself — and a unit file that vanishes while the
          # unit runs is exactly what daemon-reload-deafens a socket on.)
          rm -f "${HOME}/.config/systemd/user/default.target.wants/watchwoman.service"
          # Compat: symlink upstream watchman's default socket location to
          # the zeroconf socket, for clients that hardcode the path. The
          # root dir is system territory — best-effort with a warning when
          # sudo can't run (non-interactive shells); re-run interactively.
          _compat_dir="{{WATCHWOMAN_COMPAT_ROOT}}/$(id -un)-state"
          if mkdir -p "$_compat_dir" 2>/dev/null || sudo mkdir -p "$_compat_dir" 2>/dev/null; then
            ln -sfnv "${HOME}/.local/state/watchman/$(id -un)-state/sock" "$_compat_dir/sock"
          else
            echo "activate-user: warning: cannot create {{WATCHWOMAN_COMPAT_ROOT}} (needs root); skipping compat symlink" >&2
          fi
          # Restart heals everything: a socket deafened by a unit-file
          # unlink + daemon-reload (routine daemon-reloads are safe; only
          # a vanished unit file closes the fds — see the header), a
          # stale fd, a CLI-spawned orphan on the path. Existing clients
          # just reconnect. Idle cost: ~50ms.
          systemctl --user restart watchwoman.socket watchwoman.service
          echo "activate-user: socket enabled; service restarted and listening"
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
      workspace bins: `watchwoman` (the argv[0] alias — this deploy owns
      the classic name), `watchmanctl`, `watchman-wait`, `watchman-make`,
      `watchman-diag`.

      ## Service

      Socket-activated user units, zeroconf routing:

          watchwoman.socket   ListenStream=%h/.local/state/watchman/%u-state/sock
                              (the exact path the CLI resolves with no
                              environment), enabled at sockets.target
          watchwoman.service  Type=notify, link-only; systemd starts it on
                              the first connection and restarts it
                              (Restart=on-failure) if it dies. An idle
                              service is NORMAL (after boot, before any
                              client connects).

      Per-user activation (units, compat symlink, restart):

          {{BINS_DIR}}/activate-user.sh

      (Not install-user.sh: its rust leaf cargo-installs the workspace
      into ~/.cargo/bin, which shadows /usr/local/bin with a stale copy
      after every rebuild.)

      Because the socket unit owns the bind from boot (linger must be on),
      there is no takeover dance and no CLI-routing symlink: a bare client
      always reaches the managed daemon.

      ## Operations

          systemctl --user status watchwoman.socket watchwoman.service
          journalctl --user -t watchwoman -f
          watchwoman status            # uptime, RSS, per-root health, reaps
          watchwoman status --json     # scripting
          watchman watch-list
          {{BINS_DIR}}/status-watchwoman.sh   # drift report (units, rival
                                              # daemons, root health)

      ## Per-root ignores (no global config)

      watchwoman reads ignore_dirs from each root's `.watchmanconfig`:

          {{BINS_DIR}}/init-watchmanconfig.sh <dir> [--force]

      The file doubles as a watch-project root marker, so dropping one in
      a non-VCS dir also makes it watchable (the old `.watch` hatch).

      ## Notes

      - Cutover from C++ watchman: retire the old playbook's artifacts
        (watchman-main units, /usr/local/bin/watchman link), then run
        this playbook's install.sh — it links the `watchman` name here.
        Restart long-running clients (opencode etc.) so they rebind.
      - Do not run `watchwoman install-unit`: it writes real unit files
        over compfuzor's managed symlinks. (`watchwoman uninstall-unit`
        reverts if that already happened.)
      - XDG_STATE_HOME must stay unset (or point at ~/.local/state) for
        the zeroconf contract between the socket unit and bare CLIs to
        hold; status-watchwoman.sh checks it via get-sockname.
      - Compat: activate-user.sh symlinks
        {{WATCHWOMAN_COMPAT_ROOT}}/<user>-state/sock to the zeroconf
        socket, for clients that hardcode upstream's default path.
      - daemon-reload is safe on a running socket (even with unit content
        changes); the socket only goes deaf if its unit FILE vanishes
        while running (e.g. `systemctl disable` on a linked unit). If
        that happens: re-run activate-user.sh, or
        `systemctl --user restart watchwoman.socket watchwoman.service`.
      - Daemon state is zero-on-disk except trigger persistence under
        ~/.local/state/watchman/<user>-state/roots/. Logs are in the
        journal (identifier `watchwoman`).
      - No root guard: watch-project watches marker-less paths rather
        than refusing. init-watchmanconfig.sh + the status script's
        marker-less root listing are the mitigation.
  tasks:
    - import_tasks: tasks/compfuzor.includes
