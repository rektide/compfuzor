---
# Watchwoman -- radiosilence/watchwoman, a wire-compatible watchman
# replacement, built from our fork (rektide/watchwoman, `systemd` branch):
# socket activation (LISTEN_FDS adoption, never unlinks the socket file
# while activated), sd_notify readiness (Type=notify), graceful SIGTERM.
#
# Endpoint naming: watchman.socket is the public endpoint (classic name);
# it activates watchwoman.service through the watchman.service alias, so
# `systemctl status watchman` works while the real unit stays
# implementation-named. The C++ fallback is watchman-facebook.service.
# The socket binds Watchman's default path
# (${XDG_STATE_HOME:-$HOME/.local/state}/watchman/<user>-state/sock) via
# systemd's %S/%u specifiers, so client routing needs no env vars.
# Compatibility aliases keep clients with older hardcoded or exported socket
# paths on this same canonical listener. First-party clients ask
# `watchman get-sockname`, which we answer.
#
# install.sh links all six workspace bins (including the `watchman`
# argv[0] alias); install-user.sh links the units (socket enabled at
# sockets.target; the service activates on first connection — enabling
# the socket also implicitly enables the service, so the daemon runs
# from login) and applies the compatibility LINKS records.
#
# Root safety is daemon-owned. WATCHWOMAN_CONFIG_FILE in the generated env
# points at managed etc/watchwoman.json: exact/subtree root denies, a 100k-file
# warning, a 2M-file per-root ceiling, and a global ignore_dirs floor unioned
# with each root's .watchmanconfig. Startup fails closed if that configured
# file is invalid; SIGHUP reloads it without a restart. No statefile/pidfile/
# logfile: zero on-disk state modulo trigger persistence under the socket dir;
# logs go to the journal.
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
    SYSTEMD_ROOTS: [watchmanService, watchmanSocket]

    # Socket aliases and unit names come from the canonical endpoint contract
    # in vars/common.yaml. links.ts owns apply, drift, deliberate removal,
    # and sudo escalation for the root-owned default-prefix parent.
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
      # Classic-name alias for the daemon unit: watchman.service loads the
      # same unit file as watchwoman.service, and watchman.socket pairs with
      # the alias name for activation.
      - src: "{{ETCS_DIR}}/{{NAME}}/{{WATCHMAN_SERVICE_UNIT}}.service"
        dest: "${HOME}/.config/systemd/user/{{WATCHMAN_SERVICE_ALIAS_UNIT}}.service"
        scope: user
        policy: replace

    # Daemon env: emitted to {{DIR}}/env (+ env.export); the systemd
    # machinery auto-injects EnvironmentFile=-{{DIR}}/env into the service
    # unit (SYSTEMD_SERVICES_DEFAULT when ENV is set).
    #
    # WATCHWOMAN_CONFIG_FILE is an absolute literal because systemd does not
    # expand shell variables in EnvironmentFile. /opt/watchwoman-git is the
    # stable deployment alias for this source tree; files/_env automatically
    # includes the mapping key in COMPFUZOR_ENVS and env.export.
    #
    # Roots with no subscriptions/triggers/commands go stale after
    # WATCHWOMAN_STALE_IDLE_SECS (upstream default 3600 = 1h) and the
    # next watch re-crawls them (daemon is in-memory only). Pin 2d so
    # idle roots survive overnight/weekend gaps: warm roots cost their
    # Tree in RAM and re-watch is O(ms); stale ones cost a full crawl.
    # Giant-root admission is handled by watchwoman.json, not by reaping.
    ENV:
      WATCHWOMAN_CONFIG_FILE: /opt/watchwoman-git/etc/watchwoman.json
      WATCHWOMAN_STALE_IDLE_SECS: 172800
      # Shell clients should use the same default socket as watchman.socket.
      # This module is deliberately one sort number before watchman-env so
      # that this contributor wins the ZIM_ENV don't-stomp race when both
      # playbooks are installed.
      WATCHMAN_SOCK: "${XDG_STATE_HOME:-${HOME}/.local/state}/watchman/$(id -un)-state/sock"
    STATUS_PROC:
      - name: watchwoman-environment
        check: mainpid-env
        unit: "{{WATCHMAN_SERVICE_UNIT}}.service"
        manager: user
        expected:
          WATCHWOMAN_CONFIG_FILE: /opt/watchwoman-git/etc/watchwoman.json
          WATCHWOMAN_STALE_IDLE_SECS: "172800"
      - name: watchwoman-executable
        check: exe-current
        unit: "{{WATCHMAN_SERVICE_UNIT}}.service"
        manager: user
        expected: "{{GLOBAL_BINS_DIR}}/watchwoman"
    ZIM_ENV_PHASE: 54
    ZIM_ENV:
      - WATCHMAN_SOCK

    watchmanSocket:
      SYSTEMD_SOCKET: "{{WATCHMAN_SOCKET_UNIT}}"
      SYSTEMD_UNITS:
        Description: "Watchman-compatible file watching daemon socket"
        Documentation: https://github.com/radiosilence/watchwoman
        # The public endpoint carries the classic name; its implicit pairing
        # resolves through the watchman.service alias to watchwoman.service.
        # Endpoint owners exclude one another with one ordering edge per
        # start direction, so systemd stops the incumbent (the
        # watchman-facebook fallback) before this socket binds, and vice
        # versa.
        Conflicts: "{{WATCHMAN_FALLBACK_UNIT}}.service"
        After: "{{WATCHMAN_FALLBACK_UNIT}}.service"
      SYSTEMD_SOCKETS:
        comments: |
          Default-path agreement with the CLI's sock::resolve: %S/%u expand
          at unit-load from XDG_STATE_HOME and the user name — the username is
          part of the path contract on BOTH sides (upstream watchman's
          <user>-state layout and watchwoman's sock::resolve agree on
          it). `%S` follows XDG_STATE_HOME with the standard fallback;
          status-watchwoman.sh checks via get-sockname. systemd creates
          the parent dirs (DirectoryMode); 0700 keeps per-user state
          private.
        ListenStream: "%S/watchman/%u-state/sock"
        SocketMode: "0600"
        DirectoryMode: "0700"
      SYSTEMD_INSTALLS:
        WantedBy: sockets.target

    watchmanService:
      SYSTEMD_SERVICE: "{{WATCHMAN_SERVICE_UNIT}}"
      # Socket-activated: link-only. BOOT stays lazy (daemon on first
      # connection); activation restarts it up immediately instead. The
      # classic-name watchman.service alias (a LINKS record) points at this
      # unit file, so watchman.socket's implicit pairing activates it.
      SYSTEMD_ENABLE: false
      SYSTEMD_UNITS:
        comments: |
          Socket-activated by watchman.socket (through the watchman.service
          alias): an idle service is normal (after boot, before any client
          connects). The daemon adopts systemd's LISTEN_FDS listener and never
          unlinks the socket file while activated — the socket unit owns it
          for its whole life, so the bind survives daemon restarts.
        Description: "Watchwoman file watching daemon (watchman-compatible)"
        Documentation: https://github.com/radiosilence/watchwoman
        Requires: "{{WATCHMAN_SOCKET_UNIT}}.socket"
        After: "{{WATCHMAN_SOCKET_UNIT}}.socket"
      SYSTEMD_SERVICES:
        comments: |
          --sockname is redundant with the activated listener but pins
          the daemon's own path notion (get-sockname answer, trigger
          persistence dir) to the socket unit's ListenStream even if the
          unit's environment ever grows a stray XDG_STATE_HOME. Routine
          restarts target this service only: watchman.socket stays active,
          keeps the path bound, and queues new connections for the replacement.
          Established connections still close and re-subscribe from a fresh
          daemon; TimeoutStopSec bounds a pathological graceful drain.
          SyslogIdentifier stays `watchwoman`: the journal tag names the
          real implementation, while the alias keeps the classic name.
        Type: notify
        ExecStart: "{{GLOBAL_BINS_DIR}}/watchwoman --sockname %S/watchman/%u-state/sock --foreground-daemon"
        Restart: on-failure
        RestartSec: 1
        TimeoutStopSec: 15s
        # One inotify watch per dir plus fds per root during crawl
        # (notify-rs inotify backend). LimitNOFILE only covers fds;
        # the WATCH budget is fs.inotify.max_user_watches, owned by
        # sysctl-fs-inotify.etc.pb (16M). Journal WARNs of
        # `Error { kind: MaxFilesWatch }` (notify-rs for inotify_add_watch
        # ENOSPC) mean that sysctl pool is exhausted — typically
        # node_modules-heavy roots without a seeded .watchmanconfig —
        # not this unit's rlimit.
        LimitNOFILE: 524288
        StandardOutput: journal
        StandardError: journal
        SyslogIdentifier: watchwoman

    # The managed global floor is unioned with a root's .watchmanconfig.
    # init-watchmanconfig.sh seeds the same floor into a root for portability
    # to other watchman-compatible daemons and lets that root add more entries.
    IGNORE_DIRS:
      - node_modules
      - .pnpm-store
      - target
      - build
      - dist
      - ".next"
      - ".nuxt"
      - ".cache"
      - ".turbo"
      - ".parcel-cache"
      - bazel-out
      - dist-newstyle
      - _build
      - __pycache__
      - ".venv"
      - venv
      - ".mypy_cache"
      - ".pytest_cache"
      - ".tox"
      - ".direnv"
      - ".test-agent"
      - coverage

    # Fail-closed daemon policy. `exact` denies only that directory as a root;
    # `subtree` denies it and all descendants. First match wins.
    ETC_FILES:
      - name: watchwoman.json
        json:
          root_policy:
            default: allow
            rules:
              - path: "~"
                match: exact
                reason: "home root: 32M files, two daemon deaths"
              - path: "~/src"
                match: exact
                reason: "watch projects, not all of src"
              - path: "~/archive"
                match: exact
                reason: "archived checkouts, huge"
              - path: "~/.cache"
                match: subtree
          max_files_per_root: 2000000
          warn_files_per_root: 100000
          ignore_dirs: "{{IGNORE_DIRS}}"

    STATUSES:
      - status-watchwoman.sh

    BINS:
      - name: status-watchwoman.sh
        # Drift reporter (also registered in STATUSES so status.sh runs it).
        basedir: false
      - name: init-watchmanconfig.sh
        # Seed a per-root .watchmanconfig with the managed global ignore floor;
        # roots can add more entries but cannot remove global ones in watchwoman.
        # The file is also a watch-project root marker — the escape hatch for
        # deliberately watching a non-VCS dir.
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
      compatibility alias farm. That's the whole install.

      ## Service

      The endpoint socket carries the classic name; the daemon unit is
      implementation-named with a classic-name alias, so both
      `systemctl status watchman` and `systemctl status watchwoman` work:

          watchman.socket     ListenStream=%S/watchman/%u-state/sock
                              (upstream's XDG state-home layout — the exact
                              path the CLI resolves with no environment),
                              enabled at sockets.target
          watchwoman.service  Type=notify, activated by the socket through
                              the watchman.service alias; Restart=on-failure
                              if it dies; TimeoutStopSec=15s
          watchman-facebook.service
                              the C++ fallback (link-only, deliberately
                              started); conflicts with watchman.socket and
                              takes the canonical socket when started

      ## Operations

          systemctl --user status watchman.socket watchwoman.service
          journalctl --user -t watchwoman -f
          watchman watch-list
          watchman status [--json]
          {{BINS_DIR}}/status-watchwoman.sh

      Policy-only changes reload without dropping allowed roots:

          jq empty /opt/watchwoman-git/etc/watchwoman.json
          systemctl --user kill -s HUP watchwoman.service

      Binary, environment, and service-unit changes need a cold daemon. Keep
      the socket active and restart only the service so connections queue at
      the stable listener instead of seeing a missing/refused socket:

          systemctl --user is-active watchman.socket
          systemctl --user restart watchwoman.service

      Never include watchman.socket in a routine restart. Existing streams
      still close and re-subscribe, and the zero-state daemon re-crawls roots.

      Handing the canonical socket to the fallback (or back) is one command —
      the Conflicts declarations evict the incumbent either way:

          systemctl --user start watchman-facebook.service   # to C++
          systemctl --user start watchman.socket             # to watchwoman

      ## Root policy and ignores

      WATCHWOMAN_CONFIG_FILE=/opt/watchwoman-git/etc/watchwoman.json points the
      daemon at the managed, fail-closed policy. It denies ~, ~/src, and
      ~/archive as exact roots (individual children remain watchable), denies
      the ~/.cache subtree, warns when a scan crosses 100k files, caps each root
      at 2M files, and supplies a global ignore_dirs floor. SIGHUP keeps the
      last-good policy if a reload is invalid.

      Each root's `.watchmanconfig` can add ignore_dirs to the global floor:

          {{BINS_DIR}}/init-watchmanconfig.sh <dir> [--force]

      The file doubles as a watch-project root marker, so dropping one in
      a non-VCS dir also makes it watchable.

      ## Notes

      - `Error { kind: MaxFilesWatch }` in the journal is notify-rs for
        inotify_add_watch ENOSPC: the user's fs.inotify.max_user_watches
        pool is gone (sysctl-fs-inotify.etc.pb owns it, 16M as of
        2026-08-31). Usual arsonist: a root with no .watchmanconfig
        crawling its node_modules — seed one with
        {{BINS_DIR}}/init-watchmanconfig.sh <dir>.
      - Do not run `watchwoman install-unit`: it writes real unit files
        over compfuzor's managed symlinks. (`watchwoman uninstall-unit`
        reverts if that already happened.)
      - `%S`, watchwoman's resolver, and the alias farm all follow
        XDG_STATE_HOME with the standard ~/.local/state fallback;
        status-watchwoman.sh checks their agreement via get-sockname.
      - The LINKS alias farm maps the legacy watchman-main socket, upstream's
        default-prefix socket, and the C++ CLI's compiled state directory to
        the canonical socket directory. All aliases reach the same listener;
        links.ts owns their apply and drift behavior.
      - Daemon state is zero-on-disk except trigger persistence under
        ${XDG_STATE_HOME:-~/.local/state}/watchman/<user>-state/roots/. Logs
        go to the journal (identifier `watchwoman`).
      - Root admission policy and the global ignore floor live in
        /opt/watchwoman-git/etc/watchwoman.json, selected through
        WATCHWOMAN_CONFIG_FILE in {{DIR}}/env. Startup fails closed; SIGHUP
        reloads while retaining the last-good policy on error.
      - Root idle reaping: WATCHWOMAN_STALE_IDLE_SECS=172800 (2d), set in
        {{DIR}}/env (the service unit's EnvironmentFile). Roots with no
        subscribers/triggers/commands for that long go stale and
        re-crawl on next watch — keep them warm; the daemon forgets
        everything on restart regardless.
  tasks:
    - import_tasks: tasks/compfuzor.includes
