---
# pw-eq-global — EQ scenario service: global (everything through the EQ)
#
# Topology this asserts:
#   apps + line-in -> eq_global (default sink) -> EQ bands
#   -> combine_sink -> all hardware sinks
#
# eq_global deliberately does NOT match combine_sink's fan-out whitelist
# (which admits eq_sink by name — see pipewire-virtual-sink.etc.pb): a
# global EQ whose sink were also fanned would feed its own output back
# into itself. This naming split lets one combine config serve both
# scenarios.
#
# Switching: systemctl --user start pw-eq-global (Conflicts= stops
# pw-eq-fiio first). Neither service active = no-EQ state. See
# pw-eq-fiio.etc.pb for the switching/restart mechanics and
# pw-eq.etc.pb for the shared tooling.
#
# Note: in this arrangement the WEILIANG raw fan stream should be back
# at 100% (the FiiO gets its EQ from the global chain, not a branch).

- hosts: all
  vars:
    ETC_FILES:
      - name: pw-eq-global.service
        content: |
          [Unit]
          Description=PipeWire EQ scenario: global (eq_global -> combine fan-out)
          Conflicts=pw-eq-fiio.service
          After=pipewire.service wireplumber.service

          [Service]
          Type=oneshot
          RemainAfterExit=yes
          ExecStart=/etc/opt/pw-eq-global-main/bin/pw-eq-global --install
          ExecStop=/etc/opt/pw-eq-global-main/bin/pw-eq-global --off

          [Install]
          WantedBy=default.target
    BINS:
      # Scenario wrapper — sets PW_EQ_* env for the shared pw-eq-activate
      # and execs it. Thin by design: all logic lives in pw-eq.etc.pb's
      # shared toolkit.
      - name: pw-eq-global
        src: pw-eq-global
        helpers: false

      # User-scope install in the pw-loopback.srv.pb tradition.
      - name: install-user.sh
        content: |
          #!/bin/bash
          set -euo pipefail
          [ -n "${INSTALL_DIR:-}" ] || INSTALL_DIR="$HOME/.config/systemd/user"
          mkdir -p "$INSTALL_DIR"
          ln -sf "$(pwd)/etc/pw-eq-global.service" "$INSTALL_DIR/"
          systemctl --user daemon-reload
          systemctl --user enable pw-eq-global.service
          echo "pw-eq-global.service enabled."
          echo "Activate now with: systemctl --user start pw-eq-global"
    ENV:
      ETC: "{{ETC}}"
      APP: pipewire
  tasks:
    - import_tasks: tasks/compfuzor.includes
