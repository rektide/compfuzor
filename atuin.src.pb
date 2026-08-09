---
- hosts: all
  vars:
    REPO: https://github.com/atuinsh/atuin
    RUST: True
    RUST_ALL: True
    # atuin's Cargo.toml declares rust-version = "1.97.0"; pin to match so
    # asdf/mise doesn't float below MSRV chasing the global RUST_VERSION: 1.
    TOOL_VERSIONS:
      rust: "1.97.0"
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
          # the .socket unit's ListenStream. To use the daemon's hot in-memory
          # fuzzy index, set in the main config: search_mode = "daemon-fuzzy"
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
  tasks:
    - import_tasks: tasks/compfuzor.includes
