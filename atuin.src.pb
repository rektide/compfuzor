---
- hosts: all
  vars:
    REPO: https://github.com/atuinsh/atuin
    RUST: True
    RUST_ALL: True
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
          [daemon]
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
          # Inject the [daemon] block idempotently (appends at EOF, managed by
          # the named block so re-runs update it in place; creates the file on
          # a fresh machine).
          block-in-file -n atuin-daemon \
            -i "{{DIR}}/etc/daemon.conf" \
            -o ~/.config/atuin/config.toml \
            -a EOF -C file
  tasks:
    - import_tasks: tasks/compfuzor.includes
