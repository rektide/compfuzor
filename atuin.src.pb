---
# Atuin -- hybrid deploy (global build, per-user daemon), watchman.srv.pb
# model but FAR leaner: upstream designed the daemon for systemd, so the two
# user units ARE the whole runtime story.
#
#   atuin-daemon.socket   ListenStream=%t/atuin.sock, enabled at login
#   atuin-daemon.service  `atuin daemon start`, activated by the socket on
#                         the first history hook -- an idle service is normal
#
# No watchman-style takeover/routing scripts are needed:
#   - daemon.systemd_socket = true makes the daemon consume systemd's
#     activation fd instead of binding;
#   - with autostart = false the CLI REFUSES to autostart under
#     systemd_socket (upstream rejects the combo), so no CLI can ever spawn
#     a rival daemon;
#   - state is inherently per-user XDG ($XDG_RUNTIME_DIR/atuin.sock,
#     ~/.local/share/atuin/*) -- nothing to redirect, no symlink farm.
#
# Per-user activation (no sudo): {{DIR}}/bin/install-user.sh links the units
# into ~/.config/systemd/user and injects the managed [daemon] block into
# ~/.config/atuin/config.toml -- the block IS the client->daemon routing
# (atuin has no ATUIN_SOCKET-style env var), which is also why a config
# fragment (not a zim env module) is the right routing mechanism here.
# Interactive search can additionally be pointed at the daemon's hot
# in-memory index via ATUIN_SEARCH_MODE below.
- hosts: all
  vars:
    REPO: https://github.com/atuinsh/atuin
    RUST: True
    RUST_ALL: True
    # atuin's Cargo.toml declares rust-version = "1.98.0"; pin to match so
    # asdf/mise doesn't float below MSRV chasing the global RUST_VERSION: 1.
    TOOL_VERSIONS:
      rust: "1.98.0"
    SYSTEMD_SCOPE: user
    SYSTEMD_INSTALL: user
    SYSTEMD_ROOTS: [atuinSocket, atuinService]
    atuinSocket:
      SYSTEMD_SOCKET: atuin-daemon
      SYSTEMD_UNITS:
        Description: Socket for the Atuin history daemon
      SYSTEMD_SOCKETS:
        # %t == $XDG_RUNTIME_DIR, atuin's default socket_path
        ListenStream: "%t/atuin.sock"
        SocketMode: "0600"
      SYSTEMD_INSTALLS:
        WantedBy: sockets.target
    atuinService:
      SYSTEMD_SERVICE: atuin-daemon
      # Socket-activated: link only, don't enable. The socket activates this
      # service on the first history hook.
      SYSTEMD_ENABLE: false
      SYSTEMD_UNITS:
        Description: Atuin history daemon
        Requires: atuin-daemon.socket
        After: "atuin-daemon.socket network-online.target"
        Wants: network-online.target
      SYSTEMD_SERVICES:
        # `atuin daemon start` runs in the foreground (only the hidden
        # --daemonize flag backgrounds it), so it suits systemd directly.
        ExecStart: "{{GLOBAL_BINS_DIR}}/atuin daemon start --show-logs"
    # Interactive search routing, managed. Unset by default: search falls
    # back to atuin's local fuzzy over the database. Set to "daemon-fuzzy"
    # to make ctrl-r use the daemon's hot in-memory index (non-interactive
    # searches fall back to plain fuzzy, so scripts are unaffected).
    # Managed as a TOP-LEVEL config key (see install-atuin-config.sh).
    ATUIN_SEARCH_MODE: ""
    STATUSES:
      - status-atuin.sh
    ETC_FILES:
      - name: daemon.conf
        content: |
          # Keys land inside the stock [daemon] section that atuin's
          # default-config ships. Keep this fragment header-less so the
          # block-in-file `after:^\[daemon\]` anchor doesn't produce a
          # duplicate [daemon] header (TOML rejects duplicate tables).
          enabled = true
          # systemd manages lifecycle via the socket unit, so the CLI must not
          # autostart/double-manage it (the two are incompatible).
          autostart = false
          systemd_socket = true
          # socket_path left at default ($XDG_RUNTIME_DIR/atuin.sock) to match
          # the .socket unit's ListenStream. To point interactive search at
          # the daemon's hot in-memory fuzzy index, set the playbook var
          # ATUIN_SEARCH_MODE: daemon-fuzzy (managed as a top-level
          # search_mode key by install-atuin-config.sh).
    BINS:
      - name: install-atuin-config.sh
        scope: ['user']
        basedir: False
        content: |
          set -e
          mkdir -p ~/.config/atuin
          CFG=~/.config/atuin/config.toml
          # Seed from atuin's stock template if missing/empty, so the
          # [daemon] section header (and other defaults) exist for our
          # block to anchor against. Without this, the after-regex has
          # nothing to match and the keys would orphan at EOF with no
          # enclosing section.
          if [ ! -s "$CFG" ]; then
            atuin default-config > "$CFG"
          fi
          # Inject the [daemon] keys idempotently, anchored to the stock
          # section header so they fall UNDER [daemon] rather than being
          # appended at EOF (which previously created a duplicate table
          # and broke atuin's TOML parser).
          block-in-file -n atuin-daemon \
            -i "{{DIR}}/etc/daemon.conf" \
            -o "$CFG" \
            -a '^\[daemon\]' -C file
          # Interactive search routing. search_mode is a TOP-LEVEL key, so
          # this block anchors BEFORE the first section header (-b '^\['),
          # NOT after one: a section-scoped anchor would silently re-key it
          # into that section's table. (An after-anchor like the daemon
          # block above is the right tool only for keys that BELONG inside a
          # section.) Verified behaviors: -b '^\[' matches the FIRST header;
          # a section-less file appends at EOF, still top-level; re-runs are
          # idempotent; --append-newline keeps a blank line before the
          # header. Unset = remove the managed block: an unmanaged
          # search_mode is a deliberate local override we must not clobber
          # or duplicate (TOML duplicate keys break parsing).
          if [ -n "{{ATUIN_SEARCH_MODE|default('')}}" ]; then
            printf 'search_mode = "%s"\n' "{{ATUIN_SEARCH_MODE}}" \
              | block-in-file -n atuin-search-mode -i - -o "$CFG" \
                -b '^\[' -C file --append-newline
          else
            block-in-file --remove-all atuin-search-mode -i /dev/null -o "$CFG"
          fi
      - name: status-atuin.sh
        # Hybrid-deploy drift reporter (watchman-grade): managed unit links,
        # socket-activation enablement (socket on, service deliberately off),
        # ListenStream vs config socket_path agreement, managed-block
        # integrity (catches a manual comment-out), duplicate-key scan,
        # daemon identity/version match, stale-socket detection; linger and
        # search_mode informational. Never triggers activation.
        basedir: false
  tasks:
    - import_tasks: tasks/compfuzor.includes
