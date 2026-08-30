---
# Watchwoman -- radiosilence/watchwoman, a wire-compatible watchman
# replacement, built from our fork (rektide/watchwoman, `systemd` branch)
# whose service-manager support this deploy is built around:
#
#   socket-activation  daemon/activation.rs adopts systemd's LISTEN_FDS
#                      listener (verified bound AF_UNIX SOCK_STREAM) and
#                      never unlinks the socket file while activated — the
#                      socket unit owns it for its whole life
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
#                      watchman.srv.pb is structurally gone here: the socket
#                      unit owns the bind from boot (linger), and a bare CLI
#                      only ever auto-spawns a rival past a STOPPED or
#                      DEAFENED socket unit (daemon-reload on a running
#                      socket closes its fds) — exactly the states
#                      status-watchwoman.sh reports as drift, and the one
#                      activate-user.sh rebinds away.
#
# HYBRID DEPLOY (global build + artifacts, per-user units): ansible clones
# the fork under /usr/local/src, the rust subsystem builds it, units render
# as ETC_FILES; each user activates with {{BINS_DIR}}/activate-user.sh (no
# sudo): links both units and enables ONLY the socket (sockets.target). The
# service is link-only and starts on the first connection; an idle service
# is normal. systemd auto-creates the socket's parent dirs (DirectoryMode).
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
# CUTOVER (deliberate, manual): the workspace also builds a `watchman`
# argv[0] alias binary, but RUST_BIN pins the default install to the
# `watchwoman` name so coexistence with the C++ deployment is safe. When
# retiring C++ watchman run {{BINS_DIR}}/take-watchman-name.sh: it flips
# /usr/local/bin/watchman to this build (refusing to shadow a foreign
# watchman) and lays the compat symlink at upstream's default socket
# location (/usr/local/var/run/watchman/<user>-state/sock) for clients
# that hardcode it instead of asking the binary (get-sockname) or
# honoring $WATCHMAN_SOCK. See README for the full sequence.
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
    # NOT RUST_ALL: the workspace's other bins include the `watchman`
    # argv[0] alias, and linking it IS the cutover — keep it off the
    # default install path (see take-watchman-name.sh). Companions land
    # via install-companions.sh.
    RUST_BIN: watchwoman
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

    watchwomanSocket:
      SYSTEMD_SOCKET: watchwoman
      SYSTEMD_UNITS:
        Description: "Watchwoman (watchman-compatible) file watching daemon socket"
        Documentation: https://github.com/radiosilence/watchwoman
      SYSTEMD_SOCKETS:
        # Zeroconf contract with the CLI's sock::resolve: %h/%u expand at
        # unit-load, per user, no per-user templating (XDG_STATE_HOME must
        # stay unset or default — status-watchwoman.sh checks the
        # agreement via get-sockname). systemd creates the parent dirs
        # (DirectoryMode); 0700 keeps per-user state private.
        ListenStream: "%h/.local/state/watchman/%u-state/sock"
        SocketMode: "0600"
        DirectoryMode: "0700"
      SYSTEMD_INSTALLS:
        WantedBy: sockets.target

    watchwomanService:
      SYSTEMD_SERVICE: watchwoman
      # Socket-activated: link-only. The socket unit starts this on the
      # first connection; an idle service is normal (status reports it).
      SYSTEMD_ENABLE: false
      SYSTEMD_UNITS:
        Description: "Watchwoman file watching daemon (watchman-compatible)"
        Documentation: https://github.com/radiosilence/watchwoman
        Requires: watchwoman.socket
        After: watchwoman.socket
      SYSTEMD_SERVICES:
        # --sockname is redundant with the activated listener but pins the
        # daemon's own path notion (get-sockname answer, trigger
        # persistence dir) to the socket unit's ListenStream even if the
        # unit's environment ever grows a stray XDG_STATE_HOME.
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
      - name: status-watchwoman.sh
        # Drift reporter (also registered in STATUSES so status.sh runs it).
        basedir: false
      - name: activate-user.sh
        # Per-user activation WITHOUT install-user.sh's rust leaf: that
        # leaf cargo-installs every workspace bin into ~/.cargo/bin —
        # including the `watchman` alias, which sits EARLIER in PATH than
        # /usr/local/bin and would make activation the cutover. The hybrid
        # deploy takes its binary from the global install (install.sh);
        # only the units are per-user.
        scope: user
        basedir: false
        content: |
          set -e
          cd "$(dirname "$0")"
          ./install-systemd-user.sh
          ./install-links-user.sh
          # `enable` on a socket unit implicitly enables the service it
          # activates (default.target.wants) — that makes the daemon EAGER
          # at login. Remove just that symlink: the service stays linked,
          # socket-activated, and starts on the first connection instead.
          # (NOT `systemctl disable`: on linked units it also unlinks the
          # unit file itself.)
          rm -f "${HOME}/.config/systemd/user/default.target.wants/watchwoman.service"
          # The unit installers' daemon-reloads deafen an ALREADY-running
          # socket ("unit configuration changed while running; no socket
          # file descriptors are open"): systemd closes the fds and won't
          # rebind without a restart. A deaf socket + idle service is the
          # one window where a bare CLI auto-spawns an ORPHAN daemon that
          # steals the path. Rebind unless the service is already serving
          # (its adopted listener keeps the path alive by itself).
          if ! systemctl --user is-active --quiet watchwoman.service; then
            systemctl --user restart watchwoman.socket
          fi
          echo "activate-user: socket enabled; service link-only (starts on first connect)"
      - name: install-companions.sh
        # install-rust.sh links only RUST_BIN (watchwoman); these four
        # watchwoman-named tools have no C++ namesake on this host, so
        # they're safe to install during coexistence.
        basedir: repo
        content: |
          for _bin in watchmanctl watchman-wait watchman-make watchman-diag; do
            ln -sfv "$(pwd)/target/release/${_bin}" "${GLOBAL_BINS_DIR}/${_bin}"
          done
      - name: take-watchman-name.sh
        # CUTOVER TOOL (manual, one deliberate command): flip the classic
        # `watchman` name to this build and lay the compat socket symlink
        # at upstream watchman's compile-time default location for clients
        # that hardcode it. Run AFTER retiring the C++ deployment.
        basedir: false
        content: |
          set -e
          _target="{{REPO_DIR}}/target/release/watchman"
          [ -x "$_target" ] || { echo "take-watchman-name: $_target missing; build first" >&2; exit 1; }
          if command -v watchman >/dev/null 2>&1; then
            _current="$(readlink -f "$(command -v watchman)" 2>/dev/null || true)"
            if [ "$_current" != "$(readlink -f "$_target")" ]; then
              echo "take-watchman-name: $(command -v watchman) -> $_current" >&2
              echo "take-watchman-name: refusing to shadow a foreign watchman; retire it first (this is the cutover, not an overwrite)" >&2
              exit 1
            fi
          fi
          ln -sfv "$_target" "${GLOBAL_BINS_DIR}/watchman"
          # Compat: upstream watchman (default configure prefix) computes
          # /usr/local/var/run/watchman/<user>-state/sock; symlink it to
          # the zeroconf socket so hardcoded-path clients land on the
          # activated daemon too (kernel resolves the symlink at connect,
          # activation still triggers).
          _compat_root="${WATCHWOMAN_COMPAT_ROOT:-/usr/local/var/run/watchman}"
          if [ ! -d "$_compat_root" ]; then
            sudo mkdir -p "$_compat_root"
            sudo chmod 1777 "$_compat_root"
          fi
          _compat_dir="$_compat_root/$(id -un)-state"
          mkdir -p "$_compat_dir"
          ln -sfnv "${HOME}/.local/state/watchman/$(id -un)-state/sock" "$_compat_dir/sock"
          echo "take-watchman-name: verify with: watchman version && watchman watch-list"
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
      from rektide/watchwoman's `systemd` branch. Six binaries ship in the
      workspace; the default install links `watchwoman` plus the four
      companions (`watchmanctl`, `watchman-wait`, `watchman-make`,
      `watchman-diag`) — the `watchman` argv[0] alias is the cutover, see
      below.

      ## Service

      Socket-activated user units, zeroconf routing:

          watchwoman.socket   ListenStream=%h/.local/state/watchman/%u-state/sock
                              (the exact path the CLI resolves with no
                              environment), enabled at sockets.target
          watchwoman.service  Type=notify, link-only; systemd starts it on
                              the first connection and restarts it
                              (Restart=on-failure) if it dies. An idle
                              service is NORMAL.

      Per-user activation (no sudo):

          {{BINS_DIR}}/activate-user.sh

      (Not install-user.sh: its rust leaf cargo-installs the whole
      workspace — including the `watchman` alias — into ~/.cargo/bin,
      which shadows /usr/local/bin and would make activation the
      cutover.)

      Because the socket unit owns the bind from boot (linger must be on),
      there is no takeover dance and no CLI-routing symlink: a bare client
      always reaches the managed daemon.

      ## Operations

          systemctl --user status watchwoman.socket watchwoman.service
          journalctl --user -t watchwoman -f
          watchwoman status            # uptime, RSS, per-root health, reaps
          watchwoman status --json     # scripting
          watchwoman watch-list
          {{BINS_DIR}}/status-watchwoman.sh   # drift report (units, rival
                                              # daemons, root health)

      ## Per-root ignores (no global config)

      watchwoman reads ignore_dirs from each root's `.watchmanconfig`:

          {{BINS_DIR}}/init-watchmanconfig.sh <dir> [--force]

      The file doubles as a watch-project root marker, so dropping one in
      a non-VCS dir also makes it watchable (the old `.watch` hatch).

      ## Cutover from C++ watchman

      The transition is deliberate and manual. Sequence:

          # 1. retire the C++ deploy (its playbook, its units, its env):
          systemctl --user disable --now watchman-main.service
          #    ... and remove the watchman.src.pb install symlink
          # 2. flip the name + lay the compat socket symlink:
          {{BINS_DIR}}/take-watchman-name.sh
          # 3. restart long-running clients (opencode etc.) so they rebind

      take-watchman-name.sh refuses to shadow a foreign watchman, creates
      /usr/local/var/run/watchman (1777) if missing, and symlinks
      <user>-state/sock there to the zeroconf socket for clients that
      hardcode upstream's default path.

      ## Notes

      - Do not run `watchwoman install-unit`: it writes real unit files
        over compfuzor's managed symlinks. (`watchwoman uninstall-unit`
        reverts if that already happened.)
      - XDG_STATE_HOME must stay unset (or point at ~/.local/state) for
        the zeroconf contract between the socket unit and bare CLIs to
        hold; status-watchwoman.sh checks it via get-sockname.
      - Daemon state is zero-on-disk except trigger persistence under
        ~/.local/state/watchman/<user>-state/roots/. Logs are in the
        journal (identifier `watchwoman`).
      - No root guard: watch-project watches marker-less paths rather
        than refusing. init-watchmanconfig.sh + the status script's
        marker-less root listing are the mitigation.
  tasks:
    - import_tasks: tasks/compfuzor.includes
